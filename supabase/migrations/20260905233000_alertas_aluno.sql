-- =============================================================================
-- Card 8.4 — Alertas: STANDBY prolongado e previsão de conclusão vencida
--
-- Entregável: os dois últimos tipos de pendência que `rt_pendencias_diaria`
-- devia abrir e nunca abriu. Nada de schema: `STANDBY_PROLONGADO` e
-- `PREVISAO_VENCIDA` já estão no `check` de `pendencia.tipo` desde o card 5.5
-- (`20260903234500_pendencias_rotinas.sql` §2), o app já os traduz, já sabe a
-- ação de cada um e a aba da ficha para onde ela leva (`app/lib/pendencias/`,
-- card 5.8), e o `wireframes.md` §14.3 já os tabela. O que faltava era **quem
-- os abre** — e enquanto ninguém abre, tudo isso é decoração testada.
--
-- ⚠️ O comentário que a migração do 5.5 deixou escrito sobre si mesma
--    ("STANDBY_PROLONGADO, PREVISAO_VENCIDA e ALUNO_ULTIMO_LIVRO são da Fase 8")
--    é literalmente o bilhete que este card vem responder. `ALUNO_ULTIMO_LIVRO`
--    NÃO é deste card: o catálogo §10.1 dá o tipo a `fn_registrar_entrega`, e o
--    card 6.3 já o entrega por evento. Escrevê-lo aqui criaria a segunda
--    implementação da mesma condição — o defeito que o card 5.4 pagou para
--    aprender com `BLOCO_ACIMA_CAPACIDADE`.
--
-- -----------------------------------------------------------------------------
-- As quatro decisões deste arquivo
-- -----------------------------------------------------------------------------
-- (1) SÃO PENDÊNCIAS DE TEMPO, e por isso moram na rotina e não num trigger.
--     Nenhuma escrita as produz: o que muda é o **calendário**. Ninguém edita o
--     aluno no dia em que ele completa 31 dias de STANDBY, e ninguém toca na
--     linha no dia em que `prev_conclusao_curso` fica para trás. É a distinção
--     do card 5.4 entre evento e passagem do tempo, aqui do lado do tempo — e é
--     a mesma razão pela qual `rt_pcs_normaliza` existe ao lado do trigger.
--
-- (2) ABREM **E** FECHAM, pelo `fn_pendencias_fechar_ausentes` que as outras
--     duas já usam. O catálogo §10.1 diz "fechada por mudança de status" e
--     "fechada por nova prev_conclusao_curso ou formatura", e é exatamente isso
--     que sai da reavaliação diária: no dia seguinte à correção a condição
--     deixou de ser verdade e a chave sai da lista. Não há trigger de
--     fechamento, e não deve haver — seriam duas implementações da mesma
--     comparação (card 5.4).
--
-- (3) O LIMIAR É `standby_alerta_dias`, LIDO POR `fn_param_int` SEM DEFAULT.
--     Precedente direto: `rt_rep_avaliar` lê os quatro `rep_*` assim desde o
--     card 5.3, e a regra do card 2.2 §2.3 é que **nenhuma constante de negócio
--     mora dentro de função**. O parâmetro nasce no seed de configuração (card
--     3.6) para toda unidade; faltando, `fn_param_int` levanta
--     `PT422/PARAMETRO_AUSENTE`, a rotina inteira falha e `rt_diaria` registra
--     `ROTINA_FALHOU` — que é o modo de falha VISÍVEL que este projeto escolheu
--     no card 5.5, contra um default embutido que faria a regra rodar com um
--     número que ninguém configurou.
--
--     ⚠️ Um default aqui seria pior do que parece: `standby_alerta_dias` é
--     editável na tela de Parâmetros (card 4.7). Apagar o valor e ver o alerta
--     continuar saindo com 30 é a configuração que não configura nada.
--
-- (4) A BORDA É `>`, NÃO `>=`, e está escrita porque não aparece em uso.
--     O plano §6 diz "STANDBY há mais de N dias" e o DDL §5 diz "Dias em STANDBY
--     até gerar pendência": no N-ésimo dia o prazo ainda **está correndo**. É a
--     mesma leitura que o card 5.5 deu a `BLOCO_ACIMA_CAPACIDADE` ("10 alunos
--     para 10 PCs não é acima"), e a suíte mede os dois lados da borda mexendo
--     no PARÂMETRO — o que de quebra prova que ele é lido de verdade.
--
-- -----------------------------------------------------------------------------
-- O que este arquivo NÃO faz, e por quê
-- -----------------------------------------------------------------------------
-- • `PREVISAO_VENCIDA` só olha ATIVO/ACELERAR. É a nota do card e o §6 do plano
--   ("previsão anterior à data atual PARA ALUNO ATIVO"), e a razão é que a
--   pendência é um pedido de ação: previsão vencida de quem está TRANCADO,
--   CANCELADO ou FORMADO não é um problema a resolver — é história. Abri-la para
--   todos encheria a central de linhas que ninguém pode fechar, e a central que
--   se enche de linha inútil é a central que ninguém lê (card 5.5). O catálogo
--   §10.1 diz "fechada por ... formatura", e é essa metade que faz a formatura
--   fechar sozinha na execução seguinte, sem trigger nenhum.
--
-- • `ESTOQUE_ABAIXO_MINIMO` está no catálogo §10.1 com `rt_pendencias_diaria`
--   como dono e continua SEM ser aberto por ninguém. NÃO entra aqui: a nota do
--   card 8.4 nomeia dois tipos, os dois são de aluno, e o de estoque é da tela 6
--   / do domínio de compras. Divergência registrada nas Notas do card e em
--   `docs/regras-negocio-funcoes.md` §10.1, com card próprio a criar — escrevê-lo
--   de carona seria escopo que ninguém pediu (regra do `CLAUDE.md`).
--
-- • Nenhum `alter table`: o `check` de `pendencia.tipo` já aceita os dois desde
--   o 5.5, e o teste 090 §2 mede a severidade contra o `check` do DDL.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. rt_pendencias_diaria — os dois alertas de tempo do aluno
-- -----------------------------------------------------------------------------
-- ⚠️ `create or replace` de função inteira parte da ÚLTIMA definição APLICADA,
--    não da do card que a criou (lição do card 5.7, medida quando reescrever
--    esta mesma função a partir do 5.5 reintroduziu o que o 5.4 tinha removido,
--    sem que nada no diff parecesse errado). A última definição é a do card 7.1
--    (`20260905040000_turmas_modular.sql` §9), que fez `ALUNO_SEM_TURMA` olhar as
--    duas formas de turma — e ela está preservada abaixo palavra por palavra,
--    inclusive a seção final que registra por que `BLOCO_ACIMA_CAPACIDADE`
--    continua fora. As únicas mudanças são os DOIS blocos novos.
--
--    Três asserções vigiam essa preservação e reprovam quem partir da definição
--    errada: teste 043 §4 (a função continua sem `BLOCO_ACIMA_CAPACIDADE` e
--    continua lendo `v_bloco_alunos`) e teste 090 §13 (ela cita
--    `turma_modular_aluno` e exige `tm.ativo`).
--
-- `security definer` como antes: a rotina roda pelo `pg_cron`, sem `auth.uid()`,
-- e a unidade vem da GUC de contexto que `rt_diaria` seta (card 2.2 §2.2).
create or replace function public.rt_pendencias_diaria()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade      uuid;
  v_chaves       text[];
  v_standby_dias integer;
  r              record;
begin
  v_unidade := public.fn_unidade_atual();

  if v_unidade is null then
    raise exception
      'rt_pendencias_diaria: sem unidade no contexto. Chamar de rt_diaria, ou entrar no contexto de rotina antes (card 2.2 §2.2).';
  end if;

  -- ---------------------------------------------------------------------------
  -- ALUNO_SEM_TURMA (ALTA) — ATIVO/ACELERAR sem bloco nem turma modular
  -- ---------------------------------------------------------------------------
  -- Alocação de tipo REP CONTA aqui, ao contrário do que acontece na aceleração:
  -- o aluno está num bloco de verdade, ocupando vaga de verdade (card 2.5 §7 #2).
  --
  -- A segunda metade — a turma Modular — entrou no card 7.1, no dia em que a
  -- tabela nasceu. "Nenhuma turma" quer dizer nenhuma das DUAS formas.
  v_chaves := '{}';

  for r in select a.id,
                  format('%s (%s) está %s e não está em nenhuma turma.',
                         a.nome, coalesce(a.codigo_sgf, 'sem código SGF'), a.status)
                    as descricao
             from public.aluno a
            where a.unidade_id = v_unidade
              and a.status in ('ATIVO', 'ACELERAR')
              and not exists (select 1
                                from public.v_bloco_alunos t
                               where t.aluno_id = a.id and t.bloco_ativo)
              and not exists (select 1
                                from public.turma_modular_aluno ta
                                join public.turma_modular tm on tm.id = ta.turma_id
                               where ta.aluno_id = a.id and ta.ativo and tm.ativo)
            order by a.nome, a.id
  loop
    v_chaves := v_chaves || ('ALUNO_SEM_TURMA:' || r.id::text);
    perform public.fn_pendencia_abrir(
      'ALUNO_SEM_TURMA', 'ALUNO_SEM_TURMA:' || r.id::text, r.descricao,
      'ALTA', p_aluno_id => r.id);
  end loop;

  perform public.fn_pendencias_fechar_ausentes('ALUNO_SEM_TURMA', v_chaves);

  -- ---------------------------------------------------------------------------
  -- ACELERAR_SEM_2O_BLOCO (BAIXA) — ajuste 4 do §8 do card 2.5
  -- ---------------------------------------------------------------------------
  -- ⚠️ `tipo <> 'REP'` é o ajuste, e ele muda o resultado: "dois blocos por
  --    semana = aceleração" é regra do plano, e uma alocação de REP contínuo é
  --    reposição, não aceleração. Sem o filtro, um aluno ACELERAR com um bloco
  --    normal e uma alocação REP contaria dois e a pendência NÃO abriria — o
  --    aluno ficaria sem o segundo bloco de verdade e ninguém saberia. A
  --    contraprova está no teste 090, montada exatamente nesse cenário.
  --
  -- Severidade BAIXA e não INFO: ajuste 4 do §10 do card 2.3 (o `check` do DDL
  -- não tem INFO). É informativa, e a severidade é o que a central usa para
  -- ordenar (v_pendencias_abertas.ordem_severidade).
  v_chaves := '{}';

  for r in select a.id,
                  format('%s (%s) está em ACELERAR com %s bloco(s) de aula por semana — a aceleração pressupõe dois.',
                         a.nome, coalesce(a.codigo_sgf, 'sem código SGF'),
                         (select count(*)
                            from public.v_bloco_alunos t
                           where t.aluno_id = a.id and t.bloco_ativo and t.tipo <> 'REP'))
                    as descricao
             from public.aluno a
            where a.unidade_id = v_unidade
              and a.status = 'ACELERAR'
              and (select count(*)
                     from public.v_bloco_alunos t
                    where t.aluno_id = a.id and t.bloco_ativo and t.tipo <> 'REP') < 2
            order by a.nome, a.id
  loop
    v_chaves := v_chaves || ('ACELERAR:' || r.id::text);
    perform public.fn_pendencia_abrir(
      'ACELERAR_SEM_2O_BLOCO', 'ACELERAR:' || r.id::text, r.descricao,
      'BAIXA', p_aluno_id => r.id);
  end loop;

  perform public.fn_pendencias_fechar_ausentes('ACELERAR_SEM_2O_BLOCO', v_chaves);

  -- ---------------------------------------------------------------------------
  -- STANDBY_PROLONGADO (MEDIA) — card 8.4, decisão (3) e (4) do cabeçalho
  -- ---------------------------------------------------------------------------
  -- `status_desde` existe para esta consulta: o card 4.2 a criou dizendo, com
  -- todas as letras, que era "para o alerta de STANDBY prolongado não precisar
  -- varrer aluno_status_hist a cada execução da rotina diária". É a coluna que
  -- `tg_aluno_status_valida` carimba a cada transição — logo, o dia em que o
  -- aluno ENTROU no status atual, e não o dia da matrícula. A fixture separa as
  -- duas de propósito (Gabriela: em STANDBY há 45 dias, matriculada há 200), e
  -- uma fixture que as igualasse passaria sem exercitar nada.
  --
  -- ⚠️ O limiar é PARÂMETRO, e ler `standby_alerta_dias` aqui é o que impede o
  --    30 de virar literal dentro da função (card 2.2 §2.3). Sem default de
  --    propósito: ver a decisão (3) do cabeçalho.
  --
  -- ⚠️ A borda é `>`, não `>=`: "há MAIS de N dias". Com N = 30, o aluno que
  --    completa exatamente 30 dias hoje ainda está dentro do prazo; a pendência
  --    nasce amanhã. Isto NÃO aparece em uso e não aparece em revisão de diff —
  --    o que o separa do erro é a asserção de borda do teste 090 §14.
  v_standby_dias := public.fn_param_int('standby_alerta_dias');

  v_chaves := '{}';

  for r in select a.id,
                  format('%s (%s) está em STANDBY há %s dia(s), acima dos %s configurados — avaliar trancamento.',
                         a.nome, coalesce(a.codigo_sgf, 'sem código SGF'),
                         public.fn_hoje() - a.status_desde, v_standby_dias)
                    as descricao
             from public.aluno a
            where a.unidade_id = v_unidade
              and a.status = 'STANDBY'
              and (public.fn_hoje() - a.status_desde) > v_standby_dias
            order by a.nome, a.id
  loop
    v_chaves := v_chaves || ('STANDBY:' || r.id::text);
    perform public.fn_pendencia_abrir(
      'STANDBY_PROLONGADO', 'STANDBY:' || r.id::text, r.descricao,
      'MEDIA', p_aluno_id => r.id);
  end loop;

  perform public.fn_pendencias_fechar_ausentes('STANDBY_PROLONGADO', v_chaves);

  -- ---------------------------------------------------------------------------
  -- PREVISAO_VENCIDA (MEDIA) — card 8.4
  -- ---------------------------------------------------------------------------
  -- `prev_conclusao_curso` é informada MANUALMENTE (decisão de 30/08/2026: não
  -- há regra de cálculo), e por isso ela envelhece sozinha. Data vencida é dado
  -- ERRADO, não previsão apertada — e a projeção do card 8.1 já conta com esta
  -- pendência: `v_projecao_aluno` recusa a previsão vencida como base (o passo
  -- seria negativo e despejaria a trilha inteira no mês corrente) e cai para
  -- MEDIA_METODO, deixando para uma pessoa a correção que só ela pode fazer. Sem
  -- alguém abrindo a pendência, o aluno fica projetado pelo degrau de quem não
  -- tem previsão nenhuma e ninguém nunca fica sabendo.
  --
  -- ⚠️ Só ATIVO/ACELERAR: ver "o que este arquivo NÃO faz" no cabeçalho. É
  --    também o que faz a formatura FECHAR a pendência na execução seguinte, sem
  --    trigger nenhum — o "fechada por ... formatura" do catálogo §10.1.
  --
  -- ⚠️ A data de hoje sai de `fn_hoje()`, nunca da data do servidor: o Postgres
  --    do Supabase roda em UTC, e das 21h à meia-noite a data dele já é a de
  --    amanhã (card 2.3 §10 #1). Numa comparação de vencimento isso adianta o
  --    alerta em um dia — e a pendência apareceria à noite e sumiria de manhã.
  --
  --    ⚠️ Medido neste card: o teste C6 (`011` §C6) lê `prosrc`, que **inclui os
  --    comentários do corpo** — a primeira versão desta seção citava a função
  --    proibida pelo nome, aqui, para explicar por que não se deve usá-la, e
  --    reprovou o C6. É a lição do card 4.2 no outro sentido: lá o comentário
  --    fazia um portão passar; aqui faz um portão reprovar. O nome não se
  --    escreve, nem em comentário.
  v_chaves := '{}';

  for r in select a.id,
                  format('%s (%s) está %s e a previsão de conclusão venceu em %s, há %s dia(s).',
                         a.nome, coalesce(a.codigo_sgf, 'sem código SGF'), a.status,
                         to_char(a.prev_conclusao_curso, 'DD/MM/YYYY'),
                         public.fn_hoje() - a.prev_conclusao_curso)
                    as descricao
             from public.aluno a
            where a.unidade_id = v_unidade
              and a.status in ('ATIVO', 'ACELERAR')
              and a.prev_conclusao_curso is not null
              and a.prev_conclusao_curso < public.fn_hoje()
            order by a.nome, a.id
  loop
    v_chaves := v_chaves || ('PREVISAO:' || r.id::text);
    perform public.fn_pendencia_abrir(
      'PREVISAO_VENCIDA', 'PREVISAO:' || r.id::text, r.descricao,
      'MEDIA', p_aluno_id => r.id);
  end loop;

  perform public.fn_pendencias_fechar_ausentes('PREVISAO_VENCIDA', v_chaves);

  -- ---------------------------------------------------------------------------
  -- BLOCO_ACIMA_CAPACIDADE saiu daqui no card 5.4, e continua fora
  -- ---------------------------------------------------------------------------
  -- O dono é fn_revalidar_blocos_sala, como o catálogo §10.1 sempre disse, e
  -- quem a chama todo dia é rt_capacidades — que rt_diaria executa ANTES desta
  -- rotina. Manter a cópia aqui seria manter duas implementações da mesma
  -- comparação, livres para divergir na primeira vez que alguém mexer numa só.
end $$;

comment on function public.rt_pendencias_diaria() is
  'Abre E fecha, na unidade do contexto corrente, as pendências de TEMPO do aluno: ALUNO_SEM_TURMA (ALTA, as duas formas de turma desde o card 7.1), ACELERAR_SEM_2O_BLOCO (BAIXA, contando só blocos de tipo <> REP), STANDBY_PROLONGADO (MEDIA, status_desde acima de standby_alerta_dias — borda >, nunca >=) e PREVISAO_VENCIDA (MEDIA, prev_conclusao_curso no passado para ATIVO/ACELERAR). Os dois últimos entraram no card 8.4. BLOCO_ACIMA_CAPACIDADE saiu daqui no card 5.4 e é de fn_revalidar_blocos_sala; ALUNO_ULTIMO_LIVRO é de fn_registrar_entrega (card 6.3).';

revoke execute on function public.rt_pendencias_diaria() from public;
revoke execute on function public.rt_pendencias_diaria() from anon;
revoke execute on function public.rt_pendencias_diaria() from authenticated;
