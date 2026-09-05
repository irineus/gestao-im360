-- =============================================================================
-- As três views do Dashboard completo (card 8.7)
-- docs/views-leitura.md §8 · docs/wireframes.md §5 · docs/permissoes-matriz.md §7
--
-- O card 5.9 entregou o Dashboard **v1**, que é vaga e nada mais, e saiu sem
-- migração nenhuma: ele é consumidor de `v_bloco_vagas_semana` (card 5.6). O
-- card 7.4 acrescentou a lotação Modular, também sem objeto de banco, somando
-- `v_turma_modular_lotacao` (card 7.3). O que sobra do wireframe §5 — alunos por
-- método, conclusões por semestre e tipos por bloco — depende destas três views,
-- que o §8 de views-leitura.md escreve desde 01/09/2026 e ninguém tinha criado.
-- É a razão de `alunos.ler` estar no conjunto mínimo da rota do dashboard
-- (docs/permissoes-matriz.md §6) desde o card 3.7 **sem consumidor nenhum**: ele
-- ganha consumidor aqui.
--
-- ⚠️ AS TRÊS FAZEM `join` INTERNO EM `metodo`, e a consequência é a do card 2.3
--    §3.4: sem `materiais.ler` elas vêm VAZIAS, não erradas — o dashboard abre
--    com cara de escola sem aluno nenhum e sem erro em lugar nenhum. É o
--    bloqueante nº 1 de docs/permissoes-matriz.md §7, aberto desde 01/09/2026:
--    das cinco views dele, `v_bloco_vagas_semana` foi asserida no card 5.9 e
--    `v_turma_modular_lotacao` no 7.4; **estas três eram as que faltavam**, e o
--    par vazia → inteira de cada uma entrou no teste 095 §7 neste commit. Com
--    isso o achado fecha.
--
-- ⚠️ `fn_hoje()`, NUNCA `current_date` (card 2.3 §3.3, portão C6): o Postgres do
--    Supabase roda em UTC, e das 21h à meia-noite `current_date` já é o dia
--    seguinte em São Paulo. Aqui isso decidiria se uma previsão de conclusão
--    está vencida — a coluna `qtd_vencidas` mudaria de valor à noite, e a
--    conferência da metade A do marco 8.8 (que compara com a planilha) não
--    fecharia por um motivo que não tem nada a ver com os dados.
--
-- ⚠️ NENHUMA DAS TRÊS ESCREVE UMA LINHA DE DADO. É migração de estrutura, e
--    passa pelo portão do card 4.0,5 pela mesma razão que as views dos cards
--    6.4, 6.8, 7.3, 8.5 e 8.6 passaram.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. v_dashboard_alunos_metodo — docs/views-leitura.md §8.1
-- -----------------------------------------------------------------------------
-- ⚠️ `em_ultimo_livro` (UM item pendente) e `em_fim` (NENHUM) são coisas
--    diferentes, e o plano chama as duas de "último livro". O cartão que a
--    secretaria olha é o primeiro: o aluno está RECEBENDO a última apostila e
--    ainda tem aula pela frente — é ele que dá tempo de pedir o certificado. A
--    pendência ALUNO_ULTIMO_LIVRO do card 2.2, ao contrário, nasce em
--    `fn_registrar_entrega` quando a trilha chega ao FIM: é o segundo. Colunas
--    com nomes distintos, e o wireframe §5 manda o cartão usar `em_ultimo_livro`
--    (decisão de 01/09/2026, card 2.3 §8.1).
--
-- ⚠️ `em_fim` diz `true` para aluno SEM TRILHA NENHUMA, e isso é de propósito —
--    é o mesmo critério de `fn_trilha_em_fim` (card 6.2), e as duas leituras
--    precisam concordar. Quem precisa distinguir "acabou" de "nunca começou"
--    pergunta pela trilha, e é o que `v_certificado_fila` (card 8.6) faz com um
--    `exists`. Aqui a coluna é uma CONTAGEM ao lado de outra, não uma fila de
--    formandos.
--
-- ⚠️ `sem_previsao` existe porque `v_dashboard_conclusoes_semestre` só enxerga
--    quem tem `prev_conclusao_curso` preenchida. Sem esta coluna a soma dos
--    semestres não fecha com o total de ativos, e ninguém sabe se faltou aluno
--    ou faltou data — o dashboard mostra a conta fechando, não números soltos.
--
-- `cross join lateral` e não `left join` + `group by`: a contagem de itens
-- pendentes é POR ALUNO, e um `left join` em `aluno_material` multiplicaria a
-- linha do aluno por item da trilha, inflando ativos, standby e todo o resto —
-- a armadilha do card 2.3 §3.2 na forma mais cara, porque os números continuam
-- plausíveis.
create view public.v_dashboard_alunos_metodo with (security_invoker = on) as
select a.unidade_id,
       a.metodo_id,
       me.codigo as metodo_codigo,
       count(*) filter (where a.status = 'ATIVO')::integer     as ativos,
       count(*) filter (where a.status = 'ACELERAR')::integer  as acelerar,
       count(*) filter (where a.status = 'STANDBY')::integer   as standby,
       count(*) filter (where a.status = 'TRANCADO')::integer  as trancados,
       count(*) filter (where a.status = 'CANCELADO')::integer as cancelados,
       count(*) filter (where a.status = 'FORMADO')::integer   as formados,
       count(*) filter (where a.status in ('ATIVO','ACELERAR')
                          and pend.qtd = 1)::integer           as em_ultimo_livro,
       count(*) filter (where a.status in ('ATIVO','ACELERAR')
                          and pend.qtd = 0)::integer           as em_fim,
       count(*) filter (where a.status in ('ATIVO','ACELERAR')
                          and a.prev_conclusao_curso is null)::integer as sem_previsao
  from public.aluno a
  join public.metodo me on me.id = a.metodo_id
  cross join lateral (
         select count(*)::integer as qtd
           from public.aluno_material am
          where am.aluno_id = a.id and not am.entregue
       ) pend
 group by a.unidade_id, a.metodo_id, me.codigo;

comment on view public.v_dashboard_alunos_metodo is
  'Cartões por método do Dashboard (docs/wireframes.md §5, docs/views-leitura.md §8.1): um registro por método, com os alunos contados por status e as três leituras derivadas da trilha. em_ultimo_livro = UM item pendente (o aluno está recebendo a última apostila e ainda tem aula pela frente — é este que o cartão mostra); em_fim = NENHUM pendente, que é o mesmo critério de fn_trilha_em_fim e vale também para quem nunca teve trilha; sem_previsao = ATIVO/ACELERAR sem prev_conclusao_curso, sem o qual a soma de v_dashboard_conclusoes_semestre não fecha com o total de ativos. Leitura exige alunos.ler e materiais.ler (join interno em metodo).';

revoke all   on public.v_dashboard_alunos_metodo from public;
revoke all   on public.v_dashboard_alunos_metodo from anon;
grant select on public.v_dashboard_alunos_metodo to authenticated;

-- -----------------------------------------------------------------------------
-- 2. v_dashboard_conclusoes_semestre — docs/views-leitura.md §8.2
-- -----------------------------------------------------------------------------
-- ⚠️ PREVISÃO NO PASSADO NÃO É DESCARTADA: fica no semestre dela, contada em
--    `qtd_vencidas`. É o mesmo fato que a rotina do card 8.4 transforma na
--    pendência PREVISAO_VENCIDA, visto pelo lado do planejamento — e a tela
--    mostra os dois números juntos (wireframes §5: «mostrar qtd_vencidas junto,
--    nunca escondê-las»). Some-as e a conferência do dry-run do card 9.4 não
--    fecha: a planilha traz previsões de 2023 e de 2050 (card 9.3).
--
-- ⚠️ SÓ ATIVO/ACELERAR, como o §8.1. Formado já concluiu, cancelado e trancado
--    não estão concluindo nada — mantê-los poria toda a história da escola nos
--    semestres passados.
create view public.v_dashboard_conclusoes_semestre with (security_invoker = on) as
select a.unidade_id,
       a.metodo_id,
       me.codigo as metodo_codigo,
       extract(year from a.prev_conclusao_curso)::integer as ano,
       (case when extract(month from a.prev_conclusao_curso) <= 6 then 1 else 2 end)::smallint
                                                          as semestre,
       count(*)::integer                                  as qtd_alunos,
       -- `fn_hoje()` e não `current_date`: ver o aviso do topo.
       count(*) filter (where a.prev_conclusao_curso < public.fn_hoje())::integer as qtd_vencidas
  from public.aluno a
  join public.metodo me on me.id = a.metodo_id
 where a.status in ('ATIVO','ACELERAR')
   and a.prev_conclusao_curso is not null
 group by a.unidade_id, a.metodo_id, me.codigo, 4, 5;

comment on view public.v_dashboard_conclusoes_semestre is
  'Conclusões previstas por semestre do Dashboard (docs/wireframes.md §5, docs/views-leitura.md §8.2): alunos ATIVO/ACELERAR com prev_conclusao_curso informada, agrupados por método, ano e semestre (1 = jan–jun, 2 = jul–dez). Previsão no passado NÃO é descartada — fica no semestre dela e entra em qtd_vencidas, que a tela mostra junto; é o mesmo fato da pendência PREVISAO_VENCIDA visto pelo lado do planejamento. Quem não tem previsão nenhuma está em v_dashboard_alunos_metodo.sem_previsao, e é assim que a soma fecha com o total de ativos. Leitura exige alunos.ler e materiais.ler (join interno em metodo).';

revoke all   on public.v_dashboard_conclusoes_semestre from public;
revoke all   on public.v_dashboard_conclusoes_semestre from anon;
grant select on public.v_dashboard_conclusoes_semestre to authenticated;

-- -----------------------------------------------------------------------------
-- 3. v_dashboard_tipos_bloco — docs/views-leitura.md §8.3
-- -----------------------------------------------------------------------------
-- ⚠️ CONTA ALOCAÇÕES, NÃO ALUNOS, e é a leitura certa: o aluno em aceleração
--    está em dois blocos e aparece duas vezes. É o que os totais REM/PRE da
--    planilha significam (soma das linhas dos blocos) e é a leitura que a
--    secretaria usa para dimensionar. A tela **diz isso** ao lado do número, em
--    vez de deixar a soma parecer contagem de gente.
--
-- ⚠️ `rep` aqui é a alocação REP CONTÍNUA (card 2.5). As reposições pontuais do
--    dia moram em `bloco_aluno_reposicao` e entram na ocupação do §7 — não neste
--    total. Somá-las aqui faria o mesmo aluno contar como turma fixa por causa
--    de uma aula avulsa.
--
-- ⚠️ `where ba.ativo`: a alocação desativada é histórico e nunca se apaga (as
--    duas tabelas de alocação nasceram sem política de `delete`, card 5.1).
--    Contá-la faria o total crescer para sempre, mesmo com a escola encolhendo.
--    O método vem do BLOCO, não do aluno: é o bloco que tem método, e a
--    admissão já recusa aluno de outro (METODO_INCOMPATIVEL, card 5.3).
create view public.v_dashboard_tipos_bloco with (security_invoker = on) as
select ba.unidade_id,
       b.metodo_id,
       me.codigo as metodo_codigo,
       count(*) filter (where ba.tipo = 'REM')::integer  as rem,
       count(*) filter (where ba.tipo = 'PRE')::integer  as pre,
       count(*) filter (where ba.tipo = 'REP')::integer  as rep,
       count(*) filter (where ba.tipo = 'NOVO')::integer as novo,
       count(*)::integer                                 as alocacoes
  from public.bloco_aluno ba
  join public.bloco_horario b on b.id = ba.bloco_id
  join public.metodo me on me.id = b.metodo_id
 where ba.ativo
 group by ba.unidade_id, b.metodo_id, me.codigo;

comment on view public.v_dashboard_tipos_bloco is
  'Totais REM/PRE/REP/NOVO por método do Dashboard (docs/wireframes.md §5, docs/views-leitura.md §8.3). Conta ALOCAÇÕES ATIVAS, não alunos: quem está em aceleração ocupa dois blocos e aparece duas vezes, que é o que os totais REM/PRE da planilha significam e a leitura que a secretaria usa para dimensionar — a tela declara isso ao lado do número. rep é a alocação REP contínua (card 2.5); as reposições pontuais estão em bloco_aluno_reposicao e entram na ocupação de v_bloco_vagas_semana, não aqui. O método vem do BLOCO. Leitura exige turmas.ler e materiais.ler (join interno em metodo).';

revoke all   on public.v_dashboard_tipos_bloco from public;
revoke all   on public.v_dashboard_tipos_bloco from anon;
grant select on public.v_dashboard_tipos_bloco to authenticated;
