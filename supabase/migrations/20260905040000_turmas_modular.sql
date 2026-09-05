-- =============================================================================
-- Card 7.1 — Schema: turmas Modular
--            (turma_modular, turma_modular_modulo, turma_modular_aluno)
-- Fonte: docs/modelagem-dados-ddl.md §9 (§5.6 do plano),
--        docs/permissoes-matriz.md §4 (políticas) e §7 achado 6,
--        docs/views-leitura.md §10 ajuste 2 (`default public.fn_hoje()`),
--        docs/regras-negocio-funcoes.md §3.2 (as TRÊS tabelas da desalocação).
--
-- Entrega: as três tabelas do Modular + triggers de auditoria + RLS habilitada,
--          FORÇADA e com as onze políticas do card 2.4 §4
--          + tg_turma_modular_aluno_colunas_permitidas, a guarda por coluna que
--            o `or` da política de update abre (precedente dos cards 4.2 e 5.1)
--          + tg_turma_modular_exclusao_valida, a guarda de cascata que os cards
--            4.3 e 5.1 nomearam como devida em toda tabela cuja imutabilidade é
--            a ausência de política
--          + fn_aluno_status_desaloca citando `turma_modular_aluno`, que o
--            portão do teste 040 §10 (escrito pelo card 5.1) cobra no dia em
--            que esta tabela nascer — e nasce aqui.
--
-- ⚠️ ESTRUTURA E MAIS NADA.
--    Decisão de 02/09/2026 (Irineu): dado de negócio vindo da planilha fica
--    restrito ao ambiente dev/homolog até a virada do card 9.7. As turmas
--    Modular reais, o cronograma de módulos e os alunos de cada turma NÃO
--    entram em supabase/migrations/ — migração é o que o CI empurra para
--    produção sozinho no merge em `main`. Eles vêm pelo importador do card 9.1
--    (a aba `Ger. Modular` é a fonte oficial, decisão 9), carregados só no
--    projeto dev; turma de teste é da escola-fixture do card 3.4.5, que vive em
--    supabase/seed.sql e nunca sai do stack local. As capacidades citadas na
--    nota do card (15 Eletricista, 6 Depilação, 10 padrão) são PARÂMETRO DE
--    MODELAGEM — a coluna `capacidade` existe para recebê-las —, não linha a
--    inserir. O portão do card 4.0,5 (portao-migracoes/varredor.mjs) tem as três
--    tabelas deste arquivo FORA da lista permitida.
--
-- O que este card NÃO traz, e onde está escrito que não é esquecimento:
--   • fn_turma_modular_admitir/_remover/_ocupacao/_avancar/_modulo_corrente são
--     do card 7.2 (docs/regras-negocio-funcoes.md §9) — inclusive a checagem de
--     capacidade com `pg_advisory_xact_lock` e a pendência ALUNO_SEM_TURMA para
--     o aluno Modular sem turma;
--   • v_turma_modular_lotacao é do card 7.4 (docs/views-leitura.md §7.2 e §12);
--   • TURMA_MODULAR_SEM_CRONOGRAMA já está no `check` de `pendencia.tipo` desde
--     o card 5.5 — quem a abre é a rotina do 7.2, não este arquivo.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Tabelas (§9 do DDL do card 2.1)
-- -----------------------------------------------------------------------------
-- Substitui as abas Massagem…Depilação da planilha: uma turma por curso, com
-- sala e capacidade FIXAS — ao contrário do bloco de horário (card 5.1), cuja
-- capacidade efetiva sai dos PCs operacionais da sala (card 5.2). A sala modular
-- não tem PC, e é por isso que a capacidade aqui é coluna e não conta.
create table public.turma_modular (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  curso_id       uuid not null references public.curso(id),
  nome           text not null,
  sala_id        uuid not null references public.sala(id),
  capacidade     integer not null check (capacidade > 0),
  data_inicio    date not null,
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint turma_modular_nome_uk unique (unidade_id, nome)
);

comment on table public.turma_modular is
  'Turma Modular por curso (§5.6 do plano). VAZIA em produção até a virada do card 9.7: as turmas reais entram pelo importador do card 9.1, no ambiente dev, a partir da aba Ger. Modular.';
comment on column public.turma_modular.capacidade is
  'Teto da turma, e aqui é COLUNA e não conta derivada — a sala modular não tem PC, então não há fn_capacidade_efetiva (card 5.2) que a produza. `> 0` no check pela mesma razão do capacidade_override do card 5.1: turma fechada é ativo = false, e 0 daria uma turma permanentemente lotada sem dizer por quê.';
comment on column public.turma_modular.data_inicio is
  'Início da turma, não do módulo corrente — o cronograma mora em turma_modular_modulo. `not null` porque uma turma sem data de início não tem como ter previsão de módulo, e a projeção Modular do card 8.1 lê dali.';

-- Cronograma da turma: todos avançam juntos (card 2.2 §9). A ORDEM não é coluna
-- daqui — vem de `modulo.ordem`, por join: o cronograma da turma herda a
-- sequência do catálogo, e uma segunda ordem aqui seria uma segunda fonte da
-- verdade livre para divergir da do curso.
create table public.turma_modular_modulo (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  turma_id       uuid not null references public.turma_modular(id) on delete cascade,
  modulo_id      uuid not null references public.modulo(id),
  data_inicio    date,
  prev_conclusao date,
  concluido      boolean not null default false,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint turma_modular_modulo_uk unique (turma_id, modulo_id)
);

comment on table public.turma_modular_modulo is
  'Cronograma da turma, um registro por módulo do curso. A turma avança em CONJUNTO — não existe avanço por aluno (card 2.2 §9). A necessidade de cada livro deriva daqui, e não do ritmo individual: é o gancho da projeção Modular do card 8.1.';
comment on column public.turma_modular_modulo.data_inicio is
  'Nulo enquanto o módulo não começou. É o par com `concluido` que define o módulo CORRENTE (o primeiro não concluído, por modulo.ordem) — turma com todos concluídos fica sem corrente, e esse é o estado "turma terminou".';
comment on column public.turma_modular_modulo.prev_conclusao is
  'Previsão editável na tela do card 7.3. Vencida (menor que fn_hoje) é o que a lotação do 7.4 marca como módulo atrasado; nulo é ausência de previsão, não previsão vencida.';

-- Alunos da turma. `on delete cascade` nos dois lados, como em bloco_aluno — e,
-- como lá, é a guarda da seção 8 que impede a cascata de apagar histórico.
create table public.turma_modular_aluno (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  turma_id       uuid not null references public.turma_modular(id) on delete cascade,
  aluno_id       uuid not null references public.aluno(id) on delete cascade,
  -- Ajuste 2 do §10 do card 2.3, na parte que cabe a este card: `default
  -- public.fn_hoje()` e não `current_date`. O Postgres do Supabase roda em UTC e
  -- das 21h à meia-noite `current_date` já é o dia seguinte — a data de entrada
  -- nasceria um dia adiante, e o teste C6 é o portão que reprova.
  data_entrada   date not null default public.fn_hoje(),
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid
);

comment on table public.turma_modular_aluno is
  'Aluno na turma Modular. VAZIA em produção até a virada do card 9.7. Sem política de DELETE (card 2.4 §4): saída da turma é ativo = false, senão a turma perde o registro de quem esteve nela — a mesma decisão de bloco_aluno (card 5.1).';
comment on column public.turma_modular_aluno.ativo is
  'Falso quando o aluno sai da turma — inclusive SEM ATOR, por tg_aluno_status_desaloca (seção 9), quando ele deixa de ser ATIVO/ACELERAR. É essa escrita de terceiro que obriga a política de update a aceitar alunos.alterar_status (achado 6 do card 2.4 §7), e é essa mesma folga que a guarda da seção 7 fecha por coluna.';
comment on column public.turma_modular_aluno.data_entrada is
  'Data em que o aluno entrou na turma. Informada no INSERT vale (o importador do card 9.1 carrega entradas antigas); o default é o dia de hoje pela fn_hoje(), nunca current_date.';

-- Um aluno ocupa no máximo uma vaga ATIVA por turma; entradas antigas ficam com
-- ativo = false — é o que permite a fn_turma_modular_admitir do card 7.2
-- REATIVAR em vez de duplicar, como fn_bloco_admitir faz em bloco_aluno.
create unique index turma_modular_aluno_ativo_uk
  on public.turma_modular_aluno (turma_id, aluno_id) where ativo;

-- -----------------------------------------------------------------------------
-- 2. Índices dos lados de FK que a unique não cobre
-- -----------------------------------------------------------------------------
-- Mesma razão dos cards 3.3, 4.1, 4.3, 5.1 e 6.1: uma unique serve de índice à
-- FK só quando a coluna é a PRIMEIRA dela, e índice PARCIAL não serve nunca —
-- `turma_modular_aluno_ativo_uk` é parcial (`where ativo`), então não cobre nem
-- `turma_id` nem `aluno_id`.
create index turma_modular_curso_ix on public.turma_modular (curso_id);
create index turma_modular_sala_ix  on public.turma_modular (sala_id);

-- `turma_modular_modulo_uk (turma_id, modulo_id)` já cobre a FK de `turma_id`;
-- a de `modulo_id` não tem quem a cubra.
create index turma_modular_modulo_modulo_ix on public.turma_modular_modulo (modulo_id);

create index turma_modular_aluno_turma_ix on public.turma_modular_aluno (turma_id);
create index turma_modular_aluno_aluno_ix on public.turma_modular_aluno (aluno_id);

-- -----------------------------------------------------------------------------
-- 3. Triggers de auditoria (C3 do card 2.8)
-- -----------------------------------------------------------------------------
create trigger tg_auditoria_turma_modular
  before insert or update on public.turma_modular
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_turma_modular_modulo
  before insert or update on public.turma_modular_modulo
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_turma_modular_aluno
  before insert or update on public.turma_modular_aluno
  for each row execute function public.fn_auditoria();

-- -----------------------------------------------------------------------------
-- 4. RLS habilitada e forçada
-- -----------------------------------------------------------------------------
-- Políticas no MESMO arquivo que as tabelas, como nos cards 4.1 a 6.1:
-- "Automatically expose new tables" continua ligado nos dois projetos (pendência
-- técnica 2), então tabela sem política é uma API REST aberta pelo tempo que a
-- tarefa seguinte durar.
alter table public.turma_modular        enable row level security;
alter table public.turma_modular        force  row level security;
alter table public.turma_modular_modulo enable row level security;
alter table public.turma_modular_modulo force  row level security;
alter table public.turma_modular_aluno  enable row level security;
alter table public.turma_modular_aluno  force  row level security;

-- -----------------------------------------------------------------------------
-- 5. Políticas — docs/permissoes-matriz.md §4
-- -----------------------------------------------------------------------------
-- 5.1 turma_modular — cadastro da turma, padrão de quatro políticas
create policy turma_modular_sel on public.turma_modular for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('turmas.ler'));

create policy turma_modular_ins on public.turma_modular for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('turmas.criar'));

create policy turma_modular_upd on public.turma_modular for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('turmas.editar'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('turmas.editar'));

create policy turma_modular_del on public.turma_modular for delete to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('turmas.excluir'));

-- 5.2 turma_modular_modulo — o cronograma é CONTEÚDO da turma, não cadastro
--     próprio: o `insert` exige `turmas.editar` e não `turmas.criar` (card 2.4
--     §4), pela mesma razão pela qual `curso_material` e `combo_curso` gravam
--     com `materiais.editar` no card 4.1 — montar a sequência de uma turma é
--     editar a turma, não criar uma coisa nova.
create policy turma_modular_modulo_sel on public.turma_modular_modulo
  for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('turmas.ler'));

create policy turma_modular_modulo_ins on public.turma_modular_modulo
  for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('turmas.editar'));

create policy turma_modular_modulo_upd on public.turma_modular_modulo
  for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('turmas.editar'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('turmas.editar'));

create policy turma_modular_modulo_del on public.turma_modular_modulo
  for delete to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('turmas.excluir'));

-- 5.3 turma_modular_aluno — a terceira tabela do achado (b) do card 2.4, e a
--     razão é idêntica à de bloco_aluno: `tg_aluno_status_desaloca` (seção 9)
--     desativa a linha quando o aluno sai de ATIVO/ACELERAR, e ele roda como o
--     pedagógico que mudou o status — que não tem `turmas.alocar`. Um
--     `turmas.alocar` sozinho no update faria a mudança de status falhar com
--     erro opaco de RLS numa tela que não fala de turma.
--
--     Sem DELETE: saída da turma é `ativo = false`.
create policy turma_modular_aluno_sel on public.turma_modular_aluno
  for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('turmas.ler'));

create policy turma_modular_aluno_ins on public.turma_modular_aluno
  for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('turmas.alocar'));

create policy turma_modular_aluno_upd on public.turma_modular_aluno
  for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('turmas.alocar')
                   or public.tem_permissao('alunos.alterar_status')
                   or public.tem_permissao('alunos.reverter_status')))
  with check (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('turmas.alocar')
                   or public.tem_permissao('alunos.alterar_status')
                   or public.tem_permissao('alunos.reverter_status')));

-- -----------------------------------------------------------------------------
-- 6. RLS não é por coluna — a folga que o `or` da política de update abre
-- -----------------------------------------------------------------------------
-- O card 4.2 fechou este buraco em `aluno`, o 5.1 em `bloco_aluno` e
-- `bloco_aluno_reposicao`, o 6.1 em `aluno_material` — e o 5.1 deixou escrito
-- que `turma_modular_aluno` era o próximo caso, junto com
-- `certificado_checklist` (8.3). É este o card.
--
-- O `or` da seção 5.3 existe por UM motivo só: deixar `tg_aluno_status_desaloca`
-- escrever `ativo = false` na transação de quem mudou o status. Mas RLS não é
-- por coluna, então ele autoriza junto qualquer outra coluna — e um perfil com
-- `alunos.alterar_status` e SEM `turmas.alocar` (que a direção monta na tela do
-- card 4.7) poderia, com um PATCH no PostgREST:
--   • mudar `turma_id` — trocando o aluno de turma sem passar por
--     fn_turma_modular_admitir e, portanto, sem a checagem de capacidade do
--     card 7.2;
--   • mudar `aluno_id` — pondo outra pessoa na vaga;
--   • mudar `data_entrada` — que é o que a previsão de conclusão do módulo lê;
--   • reativar (`ativo = false → true`) a linha que o próprio trigger de status
--     tinha encerrado, devolvendo à turma um aluno TRANCADO.
-- Nenhum perfil da matriz inicial é assim (os três que alteram status também
-- alocam), então nada denunciaria hoje — que é exatamente o que os cards 4.2 e
-- 5.1 disseram sobre `aluno.status` e `bloco_aluno.tipo`.
create or replace function public.fn_turma_modular_aluno_colunas_permitidas()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  -- `ativo` fica de fora da lista: é a única coluna que a desalocação sem ator
  -- precisa escrever, e ela é justamente o que o `or` da política existe para
  -- permitir. Tudo o mais é alocação, e alocar exige turmas.alocar.
  if new.turma_id     is distinct from old.turma_id
     or new.aluno_id     is distinct from old.aluno_id
     or new.data_entrada is distinct from old.data_entrada then
    perform public.fn_exige_permissao('turmas.alocar');
  end if;

  return new;
end $$;

comment on function public.fn_turma_modular_aluno_colunas_permitidas() is
  'Trigger BEFORE UPDATE em turma_modular_aluno: só `ativo` é escrita sob alunos.alterar_status; mudar turma, aluno ou data de entrada exige turmas.alocar. Onde a permissão é por coluna, a RLS é a segunda barreira e o trigger é a primeira (cards 2.4, 4.2 e 5.1).';

revoke execute on function public.fn_turma_modular_aluno_colunas_permitidas() from public;
revoke execute on function public.fn_turma_modular_aluno_colunas_permitidas() from anon;

create trigger tg_turma_modular_aluno_colunas_permitidas
  before update on public.turma_modular_aluno
  for each row execute function public.fn_turma_modular_aluno_colunas_permitidas();

-- -----------------------------------------------------------------------------
-- 7. "Excluir turma sem alocação" deixa de ser intenção e vira estrutura
-- -----------------------------------------------------------------------------
-- O card 4.3 mediu que a ação em cascata de uma FK NÃO passa pela RLS da tabela
-- referenciadora, e as Decisões vigentes generalizaram: «cascata sobre tabela
-- cuja imutabilidade É a ausência de política é caminho aberto». `turma_modular`
-- é o caso, com a mesma forma de `bloco_horario` no card 5.1:
--
--   • o catálogo do card 2.4 §3.4 descreve `turmas.excluir` como "excluir
--     bloco/turma SEM ALOCAÇÃO", e nada no schema fazia isso valer;
--   • `turma_modular_aluno.turma_id` é `on delete cascade`, e a tabela não tem
--     política de delete PARA NINGUÉM — a ausência é a decisão (card 2.4 §4).
--     Um `delete from turma_modular` da direção levaria junto, em silêncio, o
--     registro de quem esteve na turma.
--
-- O cronograma NÃO entra na guarda, e a assimetria é deliberada:
-- `turma_modular_modulo` TEM política de delete com `turmas.excluir`, é conteúdo
-- da própria turma e não registro de terceiro — quem pode apagar a turma pode
-- apagar o cronograma dela, e a cascata aqui faz exatamente o que um delete
-- explícito faria. Alocação é o oposto: ninguém pode apagá-la, em lugar nenhum.
--
-- Aluno INATIVO conta como histórico, de propósito: `ativo = false` é como o
-- aluno sai da turma, então uma turma só com linhas inativas é exatamente uma
-- turma que já teve gente — e é esse registro que a cascata apagaria. Turma
-- digitada errada, sem ninguém dentro, continua apagável; turma que já rodou sai
-- por `ativo = false`, que é a coluna que existe para isso.
create or replace function public.fn_turma_modular_exclusao_valida()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_alunos bigint;
begin
  select count(*) into v_alunos from public.turma_modular_aluno
   where turma_id = old.id;

  if v_alunos > 0 then
    raise exception using
      errcode = 'PT409',
      message = 'Esta turma tem histórico de alunos e não pode ser excluída. Desative-a.',
      detail  = json_build_object('codigo', 'TURMA_COM_ALUNO',
                                  'turma', old.id,
                                  'alunos', v_alunos)::text;
  end if;

  return old;
end $$;

-- `security invoker` (o default), como `fn_pc_exclusao_valida` (4.3) e
-- `fn_bloco_exclusao_valida` (5.1), e pela mesma razão: ela só conta linhas de
-- uma tabela que o próprio chamador já pode ler — quem tem `turmas.excluir` tem
-- `turmas.ler` —, e entrar na lista fechada do C8 sem necessidade gasta a
-- revisão consciente que a lista existe para provocar (card 3.4 (a)).
comment on function public.fn_turma_modular_exclusao_valida() is
  'Trigger BEFORE DELETE em turma_modular: recusa (PT409 / TURMA_COM_ALUNO) apagar turma com aluno registrado, ativo ou não. Faz valer o "sem alocação" do card 2.4 §3.4, que a cascata de turma_modular_aluno contornava sem erro. O cronograma fica de fora: turma_modular_modulo tem delete próprio por turmas.excluir.';

revoke execute on function public.fn_turma_modular_exclusao_valida() from public;
revoke execute on function public.fn_turma_modular_exclusao_valida() from anon;
grant  execute on function public.fn_turma_modular_exclusao_valida() to authenticated;

create trigger tg_turma_modular_exclusao_valida
  before delete on public.turma_modular
  for each row execute function public.fn_turma_modular_exclusao_valida();

-- -----------------------------------------------------------------------------
-- 8. A terceira tabela da desalocação, que o portão do 040 cobra hoje
-- -----------------------------------------------------------------------------
-- O card 2.2 §3.2 manda desalocar de `bloco_aluno`, `bloco_aluno_reposicao` E
-- `turma_modular_aluno` quando o aluno deixa de ser ATIVO/ACELERAR. As duas
-- primeiras estão lá desde o card 5.1; a terceira não existia, e o 5.1 escreveu
-- o porquê de o esquecimento ser caro: **não daria erro nenhum — daria o erro
-- ERRADO**, com o aluno Modular trancado continuando na turma e a previsão do
-- módulo contando com ele. O portão do teste 040 §10 reprova no dia em que a
-- tabela nascer e esta função não a citar; é hoje.
--
-- ⚠️ `create or replace` de função inteira parte da ÚLTIMA definição APLICADA,
--    não da do card que a criou (lição do card 5.7, medida quando reescrever
--    `rt_pendencias_diaria` a partir do 5.5 reintroduziu o que o 5.4 tinha
--    removido, sem que nada no diff parecesse errado). A última definição é a do
--    card 5.3 (`20260903230000_admissao_lotacao_rep.sql` §9), que acrescentou
--    `motivo_saida` — e ela está preservada abaixo, palavra por palavra. A única
--    mudança é o `update` novo.
--
-- `turma_modular_aluno` NÃO tem `motivo_saida`: a coluna é do card 5.3 e existe
-- em `bloco_aluno` porque a ficha do aluno mostra por que ele saiu do bloco. O
-- DDL §9 não a prevê aqui e inventá-la neste card seria escopo que ninguém
-- pediu; quando a tela do 7.3 precisar da frase, ela é um card.
--
-- `security invoker` de propósito, como antes: a função escreve na transação de
-- quem mudou o status, e é precisamente para esta escrita que a política de
-- update das TRÊS tabelas aceita `alunos.alterar_status`/`alunos.reverter_status`
-- (card 2.4 §7). A guarda da seção 6 foi desenhada em torno dela: `ativo` é a
-- única coluna de `turma_modular_aluno` que passa sem `turmas.alocar`.
create or replace function public.fn_aluno_status_desaloca()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.status in ('ATIVO', 'ACELERAR') then
    return null;
  end if;

  update public.bloco_aluno
     set ativo = false,
         motivo_saida = format('Aluno passou a %s', new.status)
   where aluno_id = new.id and ativo;

  update public.turma_modular_aluno
     set ativo = false
   where aluno_id = new.id and ativo;

  update public.bloco_aluno_reposicao
     set status = 'CANCELADA'
   where aluno_id = new.id
     and status = 'PREVISTA'
     and data >= public.fn_hoje();

  return null;
end $$;

comment on function public.fn_aluno_status_desaloca() is
  'Trigger AFTER UPDATE OF status em aluno: quem deixa de ser ATIVO/ACELERAR sai dos blocos (ativo = false, com o motivo em motivo_saida), sai das turmas Modular (ativo = false) e tem as reposições FUTURAS canceladas — as TRÊS tabelas do card 2.2 §3.2. Voltar a ATIVO não realoca: a vaga pode já ter sido dada a outro.';

revoke execute on function public.fn_aluno_status_desaloca() from public;
revoke execute on function public.fn_aluno_status_desaloca() from anon;

-- -----------------------------------------------------------------------------
-- 9. O SEGUNDO portão que vence hoje: "sem turma" passa a incluir a Modular
-- -----------------------------------------------------------------------------
-- O card 5.5 deixou escrito, dentro da própria rotina e no teste 090, que
-- `ALUNO_SEM_TURMA` era "sem `bloco_aluno` ativo" só enquanto `turma_modular_aluno`
-- não existisse — e que, nascida a tabela, **um aluno MODULAR alocado numa turma
-- passaria a receber a pendência todo dia**. Pendência falsa, e das piores: a
-- lista de pendências ensina a ser ignorada, e depois disso a verdadeira também
-- passa despercebida. O portão do teste 090 reprova hoje.
--
-- A nota do card 7.1 no board não menciona esta rotina — ela fala das três
-- tabelas e da desalocação. Divergência resolvida a favor do PORTÃO, que é o
-- precedente que o próprio card 5.1 fixou nas Decisões vigentes ("quando a nota
-- do board e um portão da suíte divergem, o portão vence"), e pela razão que
-- torna o adiamento caro: a fixture deste card põe uma aluna Modular numa turma,
-- de modo que a pendência falsa passa a ser produzida já no primeiro `db reset`.
--
-- ⚠️ De novo o método do card 5.7: a ÚLTIMA definição aplicada é a do card 5.7
--    (`20260904060000_alunos_do_bloco.sql`), que trocou `bloco_aluno` por
--    `v_bloco_alunos` com `bloco_ativo` nas DUAS contagens. Ela está preservada
--    abaixo palavra por palavra — inclusive a seção que diz por que
--    `BLOCO_ACIMA_CAPACIDADE` continua fora (card 5.4). A única mudança é o
--    `not exists` novo em ALUNO_SEM_TURMA.
--
-- E a turma Modular precisa estar ATIVA para contar, exatamente pela razão que o
-- card 5.7 deu ao `bloco_ativo`: turma desativada não é turma, e sem isso
-- desativar uma turma tiraria a turma da tela sem abrir pendência nenhuma. O
-- teste 070 §7 monta os dois casos.
--
-- `ACELERAR_SEM_2O_BLOCO` NÃO muda, e a ausência é a decisão: "dois blocos por
-- semana = aceleração" é regra de bloco de horário semanal (card 2.5 §7), e a
-- turma Modular não tem essa forma — ela avança por módulo, em conjunto. Contar
-- turma Modular ali faria um aluno em turma modular parecer acelerado.
create or replace function public.rt_pendencias_diaria()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_chaves  text[];
  r         record;
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
  -- BLOCO_ACIMA_CAPACIDADE saiu daqui no card 5.4, e continua fora
  -- ---------------------------------------------------------------------------
  -- O dono é fn_revalidar_blocos_sala, como o catálogo §10.1 sempre disse, e
  -- quem a chama todo dia é rt_capacidades — que rt_diaria executa ANTES desta
  -- rotina. Manter a cópia aqui seria manter duas implementações da mesma
  -- comparação, livres para divergir na primeira vez que alguém mexer numa só.
end $$;

comment on function public.rt_pendencias_diaria() is
  'Abre E fecha, na unidade do contexto corrente, ALUNO_SEM_TURMA e ACELERAR_SEM_2O_BLOCO (contando só blocos de tipo <> REP). Desde o card 7.1, "nenhuma turma" cobre as DUAS formas: bloco de horário ativo (v_bloco_alunos.bloco_ativo) e turma Modular ativa. BLOCO_ACIMA_CAPACIDADE saiu daqui no card 5.4 e é de fn_revalidar_blocos_sala.';

revoke execute on function public.rt_pendencias_diaria() from public;
revoke execute on function public.rt_pendencias_diaria() from anon;
revoke execute on function public.rt_pendencias_diaria() from authenticated;
