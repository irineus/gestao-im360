-- =============================================================================
-- Card 9.2,85 — Aviso de troca de módulo (banco)
--
-- Parte 1 da proposta aprovada pelo dono do produto em 10/11/2026: nenhum
-- módulo da turma Modular começa sem alinhamento com o professor. A planilha
-- pinta a previsão de conclusão de laranja a 10 dias da troca e de vermelho no
-- dia; aqui isso vira coluna de view (a cor) e pendência (o aviso).
--
-- Entregável:
--   1. `turmas.alinhar_modulo` — o 51º código do catálogo (direção e
--      pedagógico);
--   2. `troca_modulo_alerta_dias` = 10 — o 17º parâmetro;
--   3. `TROCA_MODULO_ALINHAR` no `check` de `pendencia.tipo`, e as políticas
--      de `pendencia` passando a exigir a permissão nova PARA ESTE TIPO;
--   4. `v_turma_modular_lotacao` com o próximo módulo, a troca de livro, os
--      dias para a troca e a situação — no FIM, como manda o card 9.2,7;
--   5. `rt_pendencias_diaria` com o sexto bloco.
--
-- ⚠️ O QUE PASSA A RODAR SOZINHO depois da promoção: a partir do primeiro 03:10,
--    `rt_pendencias_diaria` abre `TROCA_MODULO_ALINHAR` para toda turma Modular
--    ativa cujo módulo corrente termina em até `troca_modulo_alerta_dias` dias
--    (ou já venceu). Em produção as turmas Modular estão vazias até a virada
--    (card 9.7), então nada abre lá antes dela.
--
-- O que este arquivo NÃO faz:
--   • não muda `modulo_atrasado` — continua "previsão vencida", `<`, e é o que
--     o cartão de lotação do Dashboard conta desde o card 7.4. A situação da
--     troca é coluna nova, com borda própria (vermelho JÁ NO DIA);
--   • não grava dado de negócio: só catálogo, matriz e parâmetro, que são
--     configuração (portão do card 4.0,5);
--   • não toca em `v_turma_modular_cronograma`: a cor do módulo corrente na
--     tela 5 sai da situação da TURMA, que é da lotação. Derivá-la de novo por
--     linha seria a segunda definição do mesmo fato (card 2.3 §4.1);
--   • não trata o cronograma em rodízio — é a Parte 2 (cards 9.2,87 e 9.2,88).
--     ⚠️ Para o 9.2,88: a chave da pendência carrega a linha do cronograma. Se
--     o rodízio REUSAR a linha a cada volta, a regra "resolvida por gente não
--     reabre" calaria o aviso da segunda volta em diante — a chave terá de
--     ganhar o ciclo.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Catálogo e matriz — `turmas.alinhar_modulo`
-- -----------------------------------------------------------------------------
-- Por que um código novo, e não `pendencias.resolver`: a decisão de 10/11/2026 é
-- que quem vê e resolve este aviso é DIREÇÃO e PEDAGÓGICO, e `pendencias.ler` /
-- `pendencias.resolver` estão também na secretaria (e a leitura, no monitor). O
-- código verifica permissão, nunca perfil — então "só estes dois perfis" só se
-- escreve como um código que só eles têm. E, sendo código, a direção pode
-- estendê-lo à secretaria na tela de Administração no dia em que quiser, sem
-- deploy: é a resposta à dúvida que o dono do produto deixou em aberto.
--
-- As duas funções partem da ÚLTIMA definição aplicada (lição do card 5.7):
-- `fn_seed_permissoes` do card 3.6 e `fn_seed_matriz` do card 4.7.5, com UMA
-- linha a mais em cada.
create or replace function public.fn_seed_permissoes(p_unidade_id uuid)
returns integer
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_n integer;
begin
  insert into public.permissao (unidade_id, codigo, descricao, dominio)
  select p_unidade_id, c.codigo, c.descricao, split_part(c.codigo, '.', 1)
    from (values
      -- admin (3)
      ('admin.ler',                        'Ler usuário, perfil, permissão, matriz e atribuições'),
      ('admin.gerir_usuarios',             'Criar/editar usuário; atribuir e remover perfis'),
      ('admin.gerir_perfis',               'Criar/editar perfil; marcar e desmarcar a matriz'),
      -- unidades (2)
      ('unidades.ler',                     'Ler a unidade (nome no cabeçalho e seleção de unidade)'),
      ('unidades.gerir',                   'Criar/editar unidade'),
      -- parametros (2)
      ('parametros.ler',                   'Ler os parâmetros na tela de Administração'),
      ('parametros.gerir',                 'Criar/editar parâmetros da escola'),
      -- materiais (4)
      ('materiais.ler',                    'Ler método, material, curso, módulo, combo e composições'),
      ('materiais.criar',                  'Criar material, curso, módulo e combo'),
      ('materiais.editar',                 'Editar material, curso, módulo, combo e suas composições'),
      ('materiais.excluir',                'Excluir cadastro sem uso e linha de composição'),
      -- alunos (7)
      ('alunos.ler',                       'Ler aluno, histórico de status e trilha'),
      ('alunos.criar',                     'Matricular aluno'),
      ('alunos.editar',                    'Editar dados cadastrais, combo e previsão de conclusão'),
      ('alunos.alterar_status',            'Alterar o status do aluno nas transições normais'),
      ('alunos.reverter_status',           'Sair de FORMADO/CANCELADO (status terminal), com motivo'),
      ('alunos.formar_sem_certificado',    'Formar aluno sem certificado ENTREGUE no checklist'),
      ('alunos.editar_trilha',             'Reordenar, incluir e remover item da trilha do aluno'),
      -- salas (6, com o 50º código do card 2.9)
      ('salas.ler',                        'Ler sala, PC e manutenções'),
      ('salas.criar',                      'Cadastrar sala e PC'),
      ('salas.editar',                     'Editar sala e PC, inclusive o status do PC'),
      ('salas.excluir',                    'Excluir sala e PC sem histórico'),
      ('salas.registrar_manutencao',       'Abrir e fechar manutenção de PC (recalcula a capacidade)'),
      ('salas.acessar_credencial',         'Ler e gravar a credencial do PC (registrada em log)'),
      -- professores (3)
      ('professores.ler',                  'Ler professor (nome na grade semanal)'),
      ('professores.criar',                'Cadastrar professor'),
      ('professores.editar',               'Editar e inativar professor'),
      -- turmas (7, com o 51º código do card 9.2,85)
      ('turmas.ler',                       'Ler blocos, alocações, reposições e turmas Modular'),
      ('turmas.criar',                     'Criar bloco de horário e turma Modular'),
      ('turmas.editar',                    'Editar bloco, cronograma e avanço de módulo'),
      ('turmas.excluir',                   'Excluir bloco e turma sem alocação'),
      ('turmas.alocar',                    'Adicionar e remover aluno de bloco/turma; lançar reposição'),
      ('turmas.lancar_reposicao_retroativa','Lançar reposição com data no passado'),
      ('turmas.alinhar_modulo',            'Ver e resolver o alinhamento da troca de módulo com o professor'),
      -- estoque (4)
      ('estoque.ler',                      'Ler movimentos e saldo de estoque'),
      ('estoque.lancar_saida',             'Registrar entrega de apostila (saída de estoque)'),
      ('estoque.estornar',                 'Estornar entrega registrada'),
      ('estoque.ajustar',                  'Ajustar o saldo com motivo obrigatório'),
      -- compras (6)
      ('compras.ler',                      'Ler pedidos de compra e seus itens'),
      ('compras.criar',                    'Criar pedido em rascunho e seus itens'),
      ('compras.editar',                   'Editar itens do rascunho, enviar e cancelar pedido'),
      ('compras.excluir',                  'Remover item de pedido em rascunho'),
      ('compras.receber',                  'Receber pedido (gera entrada no estoque)'),
      ('compras.receber_excedente',        'Receber quantidade acima da pedida'),
      -- certificados (5)
      ('certificados.ler',                 'Ler o checklist de certificado'),
      ('certificados.criar',               'Abrir o checklist de certificado do aluno'),
      ('certificados.marcar_pedagogico',   'Marcar os itens pedagógico e formatura'),
      ('certificados.marcar_financeiro',   'Marcar o item financeiro OK'),
      ('certificados.alterar_status',      'Alterar o status do certificado (pedido, entregue)'),
      -- pendencias (2)
      ('pendencias.ler',                   'Ler a central de pendências'),
      ('pendencias.resolver',              'Resolver pendência com justificativa')
    ) as c(codigo, descricao)
  on conflict (unidade_id, codigo) do update
     set descricao = excluded.descricao,
         dominio   = excluded.dominio,
         ativo     = true;

  select count(*) into v_n from public.permissao where unidade_id = p_unidade_id;
  return v_n;
end $$;

comment on function public.fn_seed_permissoes(uuid) is
  'Catálogo de 51 permissões da unidade (card 2.4 §3 + card 2.9 + turmas.alinhar_modulo do card 9.2,85). Idempotente, com do update: o catálogo é código, não dado — permissao não tem política de escrita.';

revoke execute on function public.fn_seed_permissoes(uuid) from public, anon, authenticated;

create or replace function public.fn_seed_matriz(p_unidade_id uuid)
returns integer
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_n integer;
begin
  insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
  select p_unidade_id, pe.id, pm.id
    from (values
      ('admin.ler',                         '{DIRECAO}'::text[]),
      ('admin.gerir_usuarios',              '{DIRECAO}'),
      ('admin.gerir_perfis',                '{DIRECAO}'),
      ('unidades.ler',                      '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('unidades.gerir',                    '{DIRECAO}'),
      ('parametros.ler',                    '{DIRECAO}'),
      ('parametros.gerir',                  '{DIRECAO}'),
      ('materiais.ler',                     '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('materiais.criar',                   '{DIRECAO,SECRETARIA}'),
      ('materiais.editar',                  '{DIRECAO,SECRETARIA}'),
      ('materiais.excluir',                 '{DIRECAO,SECRETARIA}'),
      ('alunos.ler',                        '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('alunos.criar',                      '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('alunos.editar',                     '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('alunos.alterar_status',             '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('alunos.reverter_status',            '{DIRECAO}'),
      ('alunos.formar_sem_certificado',     '{DIRECAO}'),
      ('alunos.editar_trilha',              '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('salas.ler',                         '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('salas.criar',                       '{DIRECAO,SECRETARIA}'),
      ('salas.editar',                      '{DIRECAO,SECRETARIA}'),
      ('salas.excluir',                     '{DIRECAO}'),
      ('salas.registrar_manutencao',        '{DIRECAO,SECRETARIA,MONITOR}'),
      ('salas.acessar_credencial',          '{DIRECAO,MONITOR}'),
      ('professores.ler',                   '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('professores.criar',                 '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('professores.editar',                '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('turmas.ler',                        '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('turmas.criar',                      '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('turmas.editar',                     '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('turmas.excluir',                    '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('turmas.alocar',                     '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('turmas.lancar_reposicao_retroativa','{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      -- card 9.2,85: decisão do dono do produto e de Irineu (10/11/2026) —
      -- quem alinha a troca de módulo com o professor é direção e pedagógico
      ('turmas.alinhar_modulo',             '{DIRECAO,PEDAGOGICO}'),
      ('estoque.ler',                       '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('estoque.lancar_saida',              '{DIRECAO,SECRETARIA,MONITOR}'),
      ('estoque.estornar',                  '{DIRECAO,SECRETARIA}'),
      ('estoque.ajustar',                   '{DIRECAO,SECRETARIA}'),
      ('compras.ler',                       '{DIRECAO,SECRETARIA}'),
      ('compras.criar',                     '{DIRECAO,SECRETARIA}'),
      ('compras.editar',                    '{DIRECAO,SECRETARIA}'),
      ('compras.excluir',                   '{DIRECAO,SECRETARIA}'),
      ('compras.receber',                   '{DIRECAO,SECRETARIA}'),
      ('compras.receber_excedente',         '{DIRECAO}'),
      ('certificados.ler',                  '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('certificados.criar',                '{DIRECAO,SECRETARIA,MONITOR}'),
      ('certificados.marcar_pedagogico',    '{DIRECAO,PEDAGOGICO}'),
      ('certificados.marcar_financeiro',    '{DIRECAO,MONITOR}'),
      ('certificados.alterar_status',       '{DIRECAO,SECRETARIA}'),
      ('pendencias.ler',                    '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('pendencias.resolver',               '{DIRECAO,PEDAGOGICO,SECRETARIA}')
    ) as m(codigo, perfis)
    join public.permissao pm on pm.unidade_id = p_unidade_id and pm.codigo = m.codigo
    join public.perfil    pe on pe.unidade_id = p_unidade_id and pe.codigo = any (m.perfis)
   where not exists (select 1 from public.perfil_permissao pp
                      where pp.permissao_id = pm.id)
     -- card 4.7.5: código que ALGUÉM tirou (de um perfil ou de todos) não volta.
     and not exists (select 1 from public.perfil_permissao_hist h
                      where h.permissao_id = pm.id
                        and h.acao = 'REMOVIDA')
  on conflict (perfil_id, permissao_id) do nothing;

  select count(*) into v_n
    from public.perfil_permissao where unidade_id = p_unidade_id;
  return v_n;
end $$;

comment on function public.fn_seed_matriz(uuid) is
  'Matriz inicial de docs/permissoes-matriz.md §5 (direção 51, secretaria 37, pedagógico 23, monitor 14). Distribui só código que não tem linha nenhuma na unidade E nunca foi removido por ninguém (perfil_permissao_hist, card 4.7.5): código novo chega; código desmarcado na tela — de um perfil ou de todos — não volta no deploy seguinte.';

revoke execute on function public.fn_seed_matriz(uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2. O parâmetro — o 17º, e o segundo que chega por migração depois do seed
-- -----------------------------------------------------------------------------
create or replace function public.fn_seed_parametros(p_unidade_id uuid)
returns integer
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_n integer;
begin
  insert into public.parametro (unidade_id, chave, valor, tipo, descricao)
  select p_unidade_id, p.chave, p.valor, 'INTEIRO', p.descricao
    from (values
      -- decisão de 31/08/2026 (card 2.1 §5)
      ('projecao_horizonte_dias',      '60',  'Horizonte da projeção de demanda, em dias'),
      ('standby_alerta_dias',          '30',  'Dias em STANDBY até gerar pendência'),
      -- card 2.5 (docs/regra-virada-rep.md §4)
      ('rep_prazo_dias',               '30',  'Prazo, em dias corridos da aula perdida, para repor sem virar REP contínuo'),
      ('rep_capacidade_semanal',       '1',   'Reposições por semana que o aluno consegue fazer além dos encontros regulares'),
      ('rep_faltas_max',               '2',   'Faltas a reposições agendadas, na janela do prazo, que sugerem a virada'),
      ('rep_janela_volta_dias',        '30',  'Carência sem débito e sem falta para sugerir a volta a REP pontual'),
      -- card de Ordem 5 (docs/projecao-demanda.md §3)
      ('ritmo_padrao_dias_INTERATIVO', '30',  'Dias por apostila no degrau MEDIA_METODO do método Interativo'),
      ('ritmo_padrao_dias_INGLES',     '30',  'Dias por apostila no degrau MEDIA_METODO do método Inglês'),
      ('ritmo_padrao_dias_MODULAR',    '45',  'Dias por módulo no Modular, quando a turma não tem cronograma'),
      ('ritmo_padrao_dias_PADRAO',     '30',  'Último recurso, quando falta a chave do método'),
      ('ritmo_janela_entregas',        '4',   'Entregas recentes que entram na média de ritmo do aluno (4 entregas = 3 intervalos)'),
      ('ritmo_intervalo_min_dias',     '7',   'Piso: intervalo menor que isto é entrega em lote, não ritmo'),
      ('ritmo_intervalo_max_dias',     '120', 'Teto: intervalo maior que isto é interrupção, não ritmo'),
      ('projecao_acelerar_pct',        '50',  'Percentual do ritmo do método aplicado ao aluno ACELERAR'),
      ('ritmo_calibracao_dias',        '180', 'Janela da mediana observada por método na recalibração'),
      -- card 11.5,5 (retenção do arquivo bruto das importações)
      ('importacao_retencao_dias',     '30',  'Dias depois de APLICADO em que o arquivo bruto do lote de importação é limpo (o relatório fica)'),
      -- card 9.2,85 (aviso de troca de módulo; decisão do dono do produto, 10/11/2026)
      ('troca_modulo_alerta_dias',     '10',  'Dias de antecedência do aviso de troca de módulo da turma Modular')
    ) as p(chave, valor, descricao)
  on conflict (unidade_id, chave) do nothing;

  select count(*) into v_n from public.parametro where unidade_id = p_unidade_id;
  return v_n;
end $$;

comment on function public.fn_seed_parametros(uuid) is
  'Os 17 parâmetros lidos pelas regras já especificadas (cards 2.1, 2.5, Ordem 5, 11.5,5 e 9.2,85). do nothing: valor ajustado na tela não volta ao default no deploy seguinte.';

revoke execute on function public.fn_seed_parametros(uuid) from public, anon, authenticated;

-- As unidades que já existem (em produção, a real). Catálogo antes da matriz:
-- a matriz cruza por código. `do nothing` nos dois últimos — nada que a direção
-- marcou, desmarcou ou ajustou volta ao default.
select public.fn_seed_permissoes(u.id) from public.unidade u;
select public.fn_seed_matriz(u.id)     from public.unidade u;
select public.fn_seed_parametros(u.id) from public.unidade u;

-- -----------------------------------------------------------------------------
-- 3. `pendencia`: o tipo novo, e quem o enxerga
-- -----------------------------------------------------------------------------
-- A lista parte da última aplicada (card 7.2, 20260905070000_modular_regras.sql
-- §7), com um tipo a mais.
alter table public.pendencia drop constraint pendencia_tipo_check;

alter table public.pendencia add constraint pendencia_tipo_check check (tipo in (
  -- card 5.5, os três tipos do título
  'ALUNO_SEM_TURMA','BLOCO_ACIMA_CAPACIDADE','ACELERAR_SEM_2O_BLOCO',
  -- card 2.5 §6, aberto e fechado por rt_rep_avaliar
  'REP_VIRADA',
  -- card 2.2 §11: a falha de uma rt_* não pode sumir com o log de 1 dia
  'ROTINA_FALHOU',
  -- card 5.4 (fn_revalidar_blocos_sala)
  'PC_SEM_SUBSTITUTO',
  -- fase 6 (fn_registrar_entrega, tg_movimento_resolve_pendencia,
  -- tg_aluno_combo_alterado, fn_estornar_entrega)
  'COMPRA_SEM_ESTOQUE','ESTOQUE_ZERO','ESTOQUE_ABAIXO_MINIMO',
  'TRILHA_DIVERGENTE_COMBO','CERTIFICADO_INCONSISTENTE',
  -- fase 7 (card 7.2). Quem a abre é rt_projecao_demanda (card 8.1)
  'TURMA_MODULAR_SEM_CRONOGRAMA',
  -- fase 8 (rt_pendencias_diaria cresce, tg_certificado_*)
  'STANDBY_PROLONGADO','PREVISAO_VENCIDA','ALUNO_ULTIMO_LIVRO',
  'SUGERIR_FORMADO',
  -- card 9.2,85: aberta por rt_pendencias_diaria, resolvida por gente
  'TROCA_MODULO_ALINHAR'));

-- As duas políticas ganham UMA cláusula: para este tipo, e só para ele, além da
-- permissão de pendência é preciso `turmas.alinhar_modulo`. Com isso a central,
-- o contador do menu e a faixa "Atenção hoje" — que leem `v_pendencias_abertas`,
-- `security_invoker` — deixam de mostrar o aviso a quem não o resolve, sem uma
-- linha de código de tela; e `fn_pendencia_resolver_id`, que é `invoker`,
-- responde PENDENCIA_INEXISTENTE a quem não a enxerga, pelo mesmo caminho que
-- já isola unidade (card 5.5 §5).
--
-- A política de insert continua sem permissão de domínio (card 2.4 §4): quem
-- abre é a rotina.
drop policy pendencia_sel on public.pendencia;
create policy pendencia_sel on public.pendencia for select to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('pendencias.ler')
         and (tipo <> 'TROCA_MODULO_ALINHAR'
              or public.tem_permissao('turmas.alinhar_modulo')));

drop policy pendencia_upd on public.pendencia;
create policy pendencia_upd on public.pendencia for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('pendencias.resolver')
              and (tipo <> 'TROCA_MODULO_ALINHAR'
                   or public.tem_permissao('turmas.alinhar_modulo')))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('pendencias.resolver')
              and (tipo <> 'TROCA_MODULO_ALINHAR'
                   or public.tem_permissao('turmas.alinhar_modulo')));

-- -----------------------------------------------------------------------------
-- 4. v_turma_modular_lotacao — o próximo módulo e a situação da troca
-- -----------------------------------------------------------------------------
-- `create or replace` a partir da última aplicada (card 9.2,7,
-- 20260924170000_views_colunas_tela.sql), com as colunas novas NO FIM.
--
-- ⚠️ `situacao_troca` tem borda PRÓPRIA, e ela é diferente da de
--    `modulo_atrasado` de propósito: aqui o vermelho começa NO DIA da previsão
--    (`<= 0`), como na planilha e como o dono do produto confirmou — o dia da
--    troca sem alinhamento já é o problema. `modulo_atrasado` continua `<`, e
--    as duas colunas convivem: uma diz "passou da data", a outra "a troca
--    chegou".
--
-- ⚠️ A janela é PARÂMETRO, lido por `fn_param_int` SEM default (card 8.4):
--    parâmetro ausente é PARAMETRO_AUSENTE em voz alta, não um 10 embutido que
--    ninguém sabe que existe. `fn_param_int` é `security definer` (card 8.1,
--    ajuste 1) — a secretaria e o monitor, que não têm `parametros.ler`, leem a
--    view do mesmo jeito.
--
-- ⚠️ O PRÓXIMO módulo é o primeiro do CATÁLOGO do curso depois do corrente que
--    a turma ainda não concluiu — e não "a próxima linha do cronograma": o
--    cronograma pode ainda não ter a linha (a tela 5 oferece acrescentá-la), e
--    a troca de livro precisa aparecer ANTES de alguém montar o módulo
--    seguinte. Ordem total (`m3.ordem, m3.id`), porque `limit` sem ela é
--    sorteio (docs/estrategia-testes.md §11).
--
-- `troca_de_livro` é NULO quando não há próximo módulo (a turma está no último):
-- nulo é "não há troca a anunciar", e `false` afirmaria "o livro continua".
create or replace view public.v_turma_modular_lotacao with (security_invoker = on) as
select t.unidade_id,
       t.id        as turma_id,
       t.nome      as turma_nome,
       t.curso_id,
       c.nome      as curso_nome,
       t.sala_id,
       s.nome      as sala_nome,
       t.capacidade,
       (select count(*) from public.turma_modular_aluno ta
         where ta.turma_id = t.id and ta.ativo)::integer as alocados,
       greatest(t.capacidade
                - (select count(*) from public.turma_modular_aluno ta
                    where ta.turma_id = t.id and ta.ativo), 0)::integer as vagas_livres,
       mc.modulo_id      as modulo_corrente_id,
       mo.nome           as modulo_corrente_nome,
       mo.ordem          as modulo_corrente_ordem,
       mc.data_inicio    as modulo_corrente_inicio,
       mc.prev_conclusao as modulo_corrente_prev_conclusao,
       (mc.prev_conclusao is not null and mc.prev_conclusao < public.fn_hoje()) as modulo_atrasado,
       -- Card 9.2,7 (wireframes §17 div. 41): o início da TURMA — dado que o
       -- importador traz e a projeção Modular lê — ficava invisível depois de
       -- criada a turma, e por isso não podia ser corrigido na tela 5.
       t.data_inicio,
       -- Card 9.2,85: o aviso de troca de módulo.
       mc.cronograma_id  as modulo_corrente_cronograma_id,
       px.modulo_id      as proximo_modulo_id,
       px.nome           as proximo_modulo_nome,
       px.material_id    as proximo_material_id,
       pm.nome           as proximo_material_nome,
       (px.material_id <> mo.material_id) as troca_de_livro,
       (mc.prev_conclusao - public.fn_hoje())::integer as dias_para_troca,
       (case
          when mc.modulo_id is null then null
          when mc.prev_conclusao is null then 'SEM_PREVISAO'
          when mc.prev_conclusao - public.fn_hoje() <= 0 then 'HOJE_OU_VENCIDA'
          when mc.prev_conclusao - public.fn_hoje()
               <= public.fn_param_int('troca_modulo_alerta_dias') then 'PROXIMA'
          else 'EM_DIA'
        end)::text       as situacao_troca
  from public.turma_modular t
  join public.curso c on c.id = t.curso_id
  join public.sala  s on s.id = t.sala_id
  left join lateral (
         select tm.id as cronograma_id, tm.modulo_id, tm.data_inicio, tm.prev_conclusao
           from public.turma_modular_modulo tm
           join public.modulo m2 on m2.id = tm.modulo_id
          where tm.turma_id = t.id and not tm.concluido
          order by m2.ordem
          limit 1
       ) mc on true
  left join public.modulo mo on mo.id = mc.modulo_id
  left join lateral (
         select m3.id as modulo_id, m3.nome, m3.material_id
           from public.modulo m3
          where m3.curso_id = t.curso_id
            and m3.ordem > mo.ordem
            and not exists (select 1 from public.turma_modular_modulo tm3
                             where tm3.turma_id = t.id
                               and tm3.modulo_id = m3.id
                               and tm3.concluido)
          order by m3.ordem, m3.id
          limit 1
       ) px on true
  left join public.material pm on pm.id = px.material_id
 where t.ativo;

comment on column public.v_turma_modular_lotacao.modulo_corrente_cronograma_id is
  'A linha de turma_modular_modulo do módulo corrente (card 9.2,85). É o que a chave da pendência TROCA_MODULO_ALINHAR carrega, ao lado da turma.';

comment on column public.v_turma_modular_lotacao.proximo_modulo_id is
  'O primeiro módulo do CATÁLOGO do curso, depois do corrente, que a turma ainda não concluiu (card 9.2,85) — do catálogo, e não do cronograma, para a troca de livro aparecer antes de alguém montar a linha seguinte. NULO quando a turma está no último módulo.';

comment on column public.v_turma_modular_lotacao.troca_de_livro is
  'O próximo módulo é de OUTRO material (card 9.2,85): trocar de módulo nem sempre é trocar de apostila, e é só neste caso que a tela 5 oferece a entrega. NULO sem próximo módulo — nulo é "não há troca a anunciar", não "o livro continua".';

comment on column public.v_turma_modular_lotacao.dias_para_troca is
  'Previsão de conclusão do módulo corrente menos public.fn_hoje() (card 9.2,85). Zero é hoje; negativo, vencida; NULO sem previsão.';

comment on column public.v_turma_modular_lotacao.situacao_troca is
  'O aviso de troca de módulo (card 9.2,85): EM_DIA, PROXIMA (faltam troca_modulo_alerta_dias dias ou menos — laranja), HOJE_OU_VENCIDA (a previsão é hoje ou já passou — vermelho, JÁ NO DIA, borda diferente da de modulo_atrasado de propósito) ou SEM_PREVISAO. NULO quando a turma não tem módulo corrente. É a coluna que rt_pendencias_diaria lê para abrir TROCA_MODULO_ALINHAR — a comparação não se repete lá.';

-- -----------------------------------------------------------------------------
-- 5. rt_pendencias_diaria — o sexto bloco
-- -----------------------------------------------------------------------------
-- ⚠️ `create or replace` de função inteira parte da ÚLTIMA definição APLICADA
--    (lição do card 5.7): a do card 8.4,5
--    (`20260905235500_alerta_estoque_minimo.sql` §1), preservada abaixo palavra
--    por palavra. As únicas mudanças são a variável `v_troca_dias` e o bloco
--    novo, antes da seção que registra por que BLOCO_ACIMA_CAPACIDADE continua
--    fora.
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
  v_troca_dias   integer;
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
  --    propósito: ver a decisão (3) do cabeçalho do card 8.4.
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
  -- ⚠️ Só ATIVO/ACELERAR: ver "o que este arquivo NÃO faz" no cabeçalho do card
  --    8.4. É também o que faz a formatura FECHAR a pendência na execução
  --    seguinte, sem trigger nenhum — o "fechada por ... formatura" do §10.1.
  --
  -- ⚠️ A data de hoje sai de `fn_hoje()`, nunca da data do servidor: o Postgres
  --    do Supabase roda em UTC, e das 21h à meia-noite a data dele já é a de
  --    amanhã (card 2.3 §10 #1). Numa comparação de vencimento isso adianta o
  --    alerta em um dia — e a pendência apareceria à noite e sumiria de manhã.
  --
  --    ⚠️ Medido no card 8.4: o teste C6 (`011` §C6) lê `prosrc`, que **inclui os
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
  -- ESTOQUE_ABAIXO_MINIMO (BAIXA) — card 8.4,5, decisões (2) a (5)
  -- ---------------------------------------------------------------------------
  -- O primeiro bloco desta rotina que não fala de aluno: a pendência é do
  -- MATERIAL, e por isso vai em `p_material_id`, que é o que faz a central do
  -- card 5.8 oferecer "Ver material" e levar para a tela 6 (`wireframes.md`
  -- §14.3). `p_aluno_id` fica nulo — não há aluno de quem cobrar nada aqui.
  --
  -- ⚠️ A comparação NÃO se repete: `abaixo_minimo` já é coluna de
  --    `v_estoque_atual` (card 6.4), e é ela que a tela de Compras mostra. Uma
  --    segunda escrita da mesma conta aqui divergiria da primeira no dia em que
  --    alguém mexesse numa só — e a que a pessoa vê é a da view.
  --
  -- ⚠️ `e.ativo` e `e.estoque_minimo > 0` são os dois filtros que a view NÃO
  --    aplica, de propósito, e que esta pendência precisa: a view fala do
  --    estoque que a escola TEM (inclusive de apostila aposentada), e a
  --    pendência fala do que a escola precisa COMPRAR. Sem o primeiro, aposentar
  --    um material abriria pendência para sempre; sem o segundo, "abaixo do
  --    mínimo de 0" apareceria para todo saldo negativo, que é conferência de
  --    prateleira, não compra. As duas contraprovas estão no teste 090 §17.
  --
  -- ⚠️ Material sem movimento NENHUM entra aqui, e é o caso que mais importa —
  --    apostila recém-cadastrada, mínimo definido, prateleira vazia. Quem o
  --    salva é o `left join` de `v_estoque_atual` (armadilha §3.2 do card 2.3):
  --    lendo `movimento_estoque` direto, ele seria justamente o que sumiria.
  v_chaves := '{}';

  for r in select e.material_id,
                  format('%s (%s %s) está com saldo %s, abaixo do mínimo de %s — avaliar compra.',
                         e.nome, me.codigo, e.codigo, e.saldo, e.estoque_minimo)
                    as descricao
             from public.v_estoque_atual e
             join public.metodo me on me.id = e.metodo_id
            where e.unidade_id = v_unidade
              and e.ativo
              and e.estoque_minimo > 0
              and e.abaixo_minimo
            order by e.nome, e.material_id
  loop
    v_chaves := v_chaves || ('MINIMO:' || r.material_id::text);
    perform public.fn_pendencia_abrir(
      'ESTOQUE_ABAIXO_MINIMO', 'MINIMO:' || r.material_id::text, r.descricao,
      'BAIXA', p_material_id => r.material_id);
  end loop;

  perform public.fn_pendencias_fechar_ausentes('ESTOQUE_ABAIXO_MINIMO', v_chaves);

  -- ---------------------------------------------------------------------------
  -- TROCA_MODULO_ALINHAR (MEDIA → ALTA) — card 9.2,85
  -- ---------------------------------------------------------------------------
  -- O aviso existe para que nenhum módulo comece sem alinhamento com o
  -- professor (decisão do dono do produto, 10/11/2026). A pendência nasce
  -- quando a previsão de conclusão do módulo corrente entra na janela de
  -- `troca_modulo_alerta_dias`, e sobe para ALTA no dia da troca.
  --
  -- ⚠️ A comparação NÃO se repete: `situacao_troca` é coluna de
  --    `v_turma_modular_lotacao`, e é ela que o Dashboard e a tela 5 pintam. É
  --    o precedente de `abaixo_minimo` no bloco acima — uma segunda escrita da
  --    mesma conta aqui divergiria da cor que a pessoa vê.
  --
  -- ⚠️ TRÊS coisas que este bloco faz diferente dos outros quatro, e as três
  --    são a decisão do card, não descuido:
  --
  --    (a) RESOLVIDA POR GENTE NÃO REABRE. Nos outros tipos a rotina reabre no
  --        dia seguinte enquanto a condição valer; aqui "resolvida" quer dizer
  --        "o alinhamento com o professor foi feito", e a condição (a troca
  --        está próxima) continua verdadeira até o dia da troca. Reabrir seria
  --        pedir o mesmo alinhamento todo dia. O que distingue é
  --        `resolvida_por` preenchido com `resolucao = 'RESOLVIDA'`: IGNORADA
  --        continua voltando, como em todo tipo (card 5.5), e o fechamento
  --        automático (`resolvida_por` nulo) também.
  --
  --    (b) AVANÇAR O MÓDULO NÃO FECHA. Se a turma trocou de módulo e ninguém
  --        registrou o alinhamento, a pendência é exatamente o que tem de
  --        continuar na central — e em ALTA. Por isso a chave do módulo já
  --        concluído ENTRA em `v_chaves` quando a pendência dele está aberta.
  --
  --    (c) FECHA SOZINHA só quando a troca deixa de estar próxima: a previsão
  --        foi adiada para além da janela, a turma foi desativada ou o módulo
  --        saiu do cronograma.
  --
  -- A chave carrega a TURMA e a linha do CRONOGRAMA
  -- (`TROCA_MODULO:<turma>:<cronograma>`): a turma é o que a central precisa
  -- para abrir a tela 5, e `pendencia` não tem coluna de turma Modular — é o
  -- precedente de `REP:<aluno>:CONTINUO`, que a tela também lê da chave.
  v_troca_dias := public.fn_param_int('troca_modulo_alerta_dias');

  v_chaves := '{}';

  for r in select l.turma_id,
                  'TROCA_MODULO:' || l.turma_id::text || ':'
                    || l.modulo_corrente_cronograma_id::text as chave,
                  (case when l.situacao_troca = 'HOJE_OU_VENCIDA' then 'ALTA' else 'MEDIA' end)
                    as severidade,
                  format('Turma %s (%s): o módulo %s %s. Alinhar a troca de módulo com o professor%s.',
                         l.turma_nome, l.curso_nome, l.modulo_corrente_nome,
                         case
                           when l.dias_para_troca > 0 then
                             format('termina em %s, em %s dia(s)',
                                    to_char(l.modulo_corrente_prev_conclusao, 'DD/MM/YYYY'),
                                    l.dias_para_troca)
                           when l.dias_para_troca = 0 then 'termina hoje'
                           else
                             format('tinha previsão de terminar em %s, há %s dia(s)',
                                    to_char(l.modulo_corrente_prev_conclusao, 'DD/MM/YYYY'),
                                    -l.dias_para_troca)
                         end,
                         case
                           when l.troca_de_livro then
                             format(' — o próximo módulo, %s, é de outro livro (%s)',
                                    l.proximo_modulo_nome, l.proximo_material_nome)
                           else ''
                         end)
                    as descricao
             from public.v_turma_modular_lotacao l
            where l.unidade_id = v_unidade
              and l.situacao_troca in ('PROXIMA', 'HOJE_OU_VENCIDA')
            order by l.turma_nome, l.turma_id
  loop
    v_chaves := v_chaves || r.chave;

    -- (a): o alinhamento deste módulo desta turma já foi registrado por alguém
    if not exists (select 1
                     from public.pendencia p
                    where p.unidade_id = v_unidade
                      and p.chave_dedup = r.chave
                      and p.resolucao = 'RESOLVIDA'
                      and p.resolvida_por is not null) then
      perform public.fn_pendencia_abrir(
        'TROCA_MODULO_ALINHAR', r.chave, r.descricao, r.severidade);
    end if;
  end loop;

  -- (b): a turma já trocou de módulo e a pendência do módulo anterior continua
  -- aberta — fica, e em ALTA. `fn_pendencia_abrir` só refresca a descrição e a
  -- severidade: a pendência está aberta por construção do `where`.
  for r in select p.chave_dedup as chave,
                  format('Turma %s (%s): o módulo %s foi concluído sem o alinhamento com o professor registrado.',
                         t.nome, c.nome, m.nome) as descricao
             from public.pendencia p
             join public.turma_modular_modulo tm
               on p.chave_dedup = 'TROCA_MODULO:' || tm.turma_id::text || ':' || tm.id::text
             join public.turma_modular t on t.id = tm.turma_id
             join public.curso  c on c.id = t.curso_id
             join public.modulo m on m.id = tm.modulo_id
            where p.unidade_id = v_unidade
              and p.tipo = 'TROCA_MODULO_ALINHAR'
              and p.resolvida_em is null
              and tm.concluido
              and t.ativo
            order by t.nome, tm.id
  loop
    v_chaves := v_chaves || r.chave;
    perform public.fn_pendencia_abrir(
      'TROCA_MODULO_ALINHAR', r.chave, r.descricao, 'ALTA');
  end loop;

  -- (c)
  perform public.fn_pendencias_fechar_ausentes('TROCA_MODULO_ALINHAR', v_chaves);

  -- ---------------------------------------------------------------------------
  -- BLOCO_ACIMA_CAPACIDADE saiu daqui no card 5.4, e continua fora
  -- ---------------------------------------------------------------------------
  -- O dono é fn_revalidar_blocos_sala, como o catálogo §10.1 sempre disse, e
  -- quem a chama todo dia é rt_capacidades — que rt_diaria executa ANTES desta
  -- rotina. Manter a cópia aqui seria manter duas implementações da mesma
  -- comparação, livres para divergir na primeira vez que alguém mexer numa só.
end $$;

comment on function public.rt_pendencias_diaria() is
  'Abre E fecha, na unidade do contexto corrente, as pendências de TEMPO e de ESTADO que o catálogo §10.1 lhe dá: ALUNO_SEM_TURMA (ALTA, as duas formas de turma desde o card 7.1), ACELERAR_SEM_2O_BLOCO (BAIXA, contando só blocos de tipo <> REP), STANDBY_PROLONGADO (MEDIA, status_desde acima de standby_alerta_dias — borda >, nunca >=), PREVISAO_VENCIDA (MEDIA, prev_conclusao_curso no passado para ATIVO/ACELERAR), ESTOQUE_ABAIXO_MINIMO (BAIXA, abaixo_minimo de v_estoque_atual, só material ATIVO e com mínimo > 0 — card 8.4,5) e TROCA_MODULO_ALINHAR (MEDIA na janela de troca_modulo_alerta_dias, ALTA no dia da troca, lendo situacao_troca de v_turma_modular_lotacao — card 9.2,85; resolvida por gente NÃO reabre para o mesmo módulo, e avançar o módulo não a fecha). BLOCO_ACIMA_CAPACIDADE saiu daqui no card 5.4 e é de fn_revalidar_blocos_sala; ALUNO_ULTIMO_LIVRO é de fn_registrar_entrega (card 6.3).';

revoke execute on function public.rt_pendencias_diaria() from public;
revoke execute on function public.rt_pendencias_diaria() from anon;
revoke execute on function public.rt_pendencias_diaria() from authenticated;
