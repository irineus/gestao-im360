-- =============================================================================
-- Card 5.1 — Schema: blocos de horário e alocação
--            (bloco_horario, bloco_aluno, bloco_aluno_reposicao)
-- Fonte: docs/modelagem-dados-ddl.md §8 (§5.5 do plano),
--        docs/regra-virada-rep.md §8 (ajustes 1, 2 e 5 do card 2.5),
--        docs/regras-negocio-funcoes.md §14 (ajustes 1 e 5),
--        docs/permissoes-matriz.md §4 (políticas) e §3.4 (domínio `turmas`).
--
-- Entrega: as três tabelas do REP híbrido + triggers de auditoria + RLS
--          habilitada, FORÇADA e com as dez políticas do card 2.4 §4
--          + tg_bloco_aluno_tipo_desde (bloqueante do card 2.5)
--          + as duas guardas que as lições dos cards 4.2 e 4.3 nomearam
--            explicitamente como devidas AQUI
--          + tg_aluno_status_desaloca, que o portão do teste 030 (escrito pelo
--            card 4.2) cobra no dia em que `bloco_aluno` nascer — e nasce aqui.
--
-- ⚠️ ESTRUTURA E MAIS NADA.
--    Decisão de 02/09/2026 (Irineu): dado de negócio vindo da planilha fica
--    restrito ao ambiente dev/homolog até a virada do card 9.7. Os blocos reais
--    e as alocações de aluno não entram em supabase/migrations/ — migração é o
--    que o CI empurra para produção sozinho no merge em `main`. Eles vêm pelo
--    importador do card 9.1, carregados só no projeto dev; bloco e alocação de
--    teste são da escola-fixture do card 3.4.5, que vive em supabase/seed.sql e
--    nunca sai do stack local. O portão do card 4.0,5
--    (portao-migracoes/varredor.mjs) tem as três tabelas deste arquivo FORA da
--    lista permitida.
--
-- O que este card NÃO traz, e onde está escrito que não é esquecimento:
--   • fn_bloco_admitir/fn_bloco_remover, tg_bloco_aluno_admissao,
--     tg_reposicao_admissao e as funções da virada REP são do card 5.3
--     (docs/regras-negocio-funcoes.md §4.3 e §4.4);
--   • fn_capacidade_efetiva/fn_ocupacao_bloco são do card 5.2;
--   • fn_reposicao_registrar é do 5.3 — o ajuste 7 do §14 do card 2.2 pedia
--     "devolve text em vez de void", e aqui não há assinatura a alterar porque
--     a função ainda não existe: ela NASCE devolvendo `text` no 5.3, e a
--     obrigação foi transferida para as Notas daquele card. Divergência com a
--     nota deste, registrada em vez de seguida em silêncio.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Tabelas (§8 do DDL do card 2.1, com os dois ajustes do card 2.5)
-- -----------------------------------------------------------------------------
-- Substitui os 6 blocos × 6 abas da planilha.
create table public.bloco_horario (
  id                  uuid primary key default gen_random_uuid(),
  unidade_id          uuid not null references public.unidade(id),
  dia_semana          smallint not null check (dia_semana between 1 and 7),
  hora_inicio         time not null,
  metodo_id           uuid not null references public.metodo(id),
  professor_id        uuid references public.professor(id),
  sala_id             uuid not null references public.sala(id),
  capacidade_override integer check (capacidade_override > 0),
  ativo               boolean not null default true,
  criado_em           timestamptz not null default now(),
  criado_por          uuid,
  atualizado_em       timestamptz,
  atualizado_por      uuid,
  -- A mesma sala não pode ter dois blocos no mesmo dia e horário.
  constraint bloco_horario_uk unique (unidade_id, sala_id, dia_semana, hora_inicio)
);

comment on table public.bloco_horario is
  'Bloco de horário semanal (dia × hora × sala). VAZIA em produção até a virada do card 9.7: os blocos reais entram pelo importador do card 9.1, no ambiente dev.';
comment on column public.bloco_horario.dia_semana is
  'ISO 8601: 1 = segunda … 7 = domingo, a mesma numeração de extract(isodow), para a grade do card 5.6 não precisar de tradução.';
comment on column public.bloco_horario.capacidade_override is
  'Teto manual do bloco. Nulo é o caso normal: a capacidade EFETIVA sai dos PCs OPERACIONAIS da sala (fn_capacidade_efetiva, card 5.2). Nunca 0 — bloco fechado é ativo = false, e 0 faria a grade mostrar um bloco permanentemente lotado sem dizer por quê.';
comment on column public.bloco_horario.professor_id is
  'Opcional: a planilha tem bloco sem professor definido. `left join` em v_bloco_vagas_semana (card 2.3 §7) — e é por isso que `professores.ler` é permissão dos quatro perfis (card 2.4 §6).';

-- Alocação do aluno no bloco. Um aluno pode estar em mais de um bloco
-- (dois blocos por semana = aceleração, decisão de 31/08/2026).
create table public.bloco_aluno (
  id                   uuid primary key default gen_random_uuid(),
  unidade_id           uuid not null references public.unidade(id),
  bloco_id             uuid not null references public.bloco_horario(id) on delete cascade,
  aluno_id             uuid not null references public.aluno(id) on delete cascade,
  tipo                 text not null check (tipo in ('REM','PRE','REP','NOVO')),
  -- Ajuste 1 do §8 do card 2.5, BLOQUEANTE. `default public.fn_hoje()` e não
  -- `current_date`: o Postgres do Supabase roda em UTC e das 21h à meia-noite
  -- `current_date` já é o dia seguinte (card 2.3 §3.3) — aqui isso deslocaria em
  -- um dia o corte do débito na virada. É o ajuste não bloqueante nº 5 do card
  -- 2.3 na parte que cabe a este card; o teste C6 é o portão.
  tipo_desde           date not null default public.fn_hoje(),
  data_inicio_prevista date,
  ativo                boolean not null default true,
  criado_em            timestamptz not null default now(),
  criado_por           uuid,
  atualizado_em        timestamptz,
  atualizado_por       uuid,
  constraint bloco_aluno_novo_ck
    check (tipo <> 'NOVO' or data_inicio_prevista is not null)
);

comment on table public.bloco_aluno is
  'Alocação do aluno no bloco. VAZIA em produção até a virada do card 9.7. Sem política de DELETE (card 2.4 §4): alocação encerrada é ativo = false, senão a grade histórica perde quem esteve na turma.';
comment on column public.bloco_aluno.tipo is
  'REM/PRE/REP/NOVO — o "R" da planilha é REP. REP aqui é a metade CONTÍNUA do híbrido (card 2.5): estado permanente da alocação, que consome vaga toda semana. A metade pontual é bloco_aluno_reposicao.';
comment on column public.bloco_aluno.tipo_desde is
  'Data em que o tipo atual passou a valer, escrita por tg_bloco_aluno_tipo_desde. É o relógio que a virada REP zera (card 2.5 §3.2): sem ela, o débito que motivou a conversão pesaria contra o aluno para sempre e ele nunca poderia voltar a pontual. Mesma razão de aluno.status_desde (card 2.1).';
comment on column public.bloco_aluno.ativo is
  'Falso quando o aluno sai do bloco — inclusive SEM ATOR, por tg_aluno_status_desaloca (seção 9), quando ele deixa de ser ATIVO/ACELERAR. É essa escrita de terceiro que obriga a política de update a aceitar alunos.alterar_status (card 2.4 §7), e é essa mesma folga que a guarda da seção 7 fecha por coluna.';

-- Um aluno ocupa no máximo uma vaga ativa por bloco; realocações antigas ficam
-- com ativo = false — é o que permite a fn_bloco_admitir do card 5.3 REATIVAR
-- em vez de duplicar.
create unique index bloco_aluno_ativo_uk
  on public.bloco_aluno (bloco_id, aluno_id) where ativo;

-- Reposição como EVENTO PONTUAL COM DATA (metade pontual do REP híbrido,
-- decisão de 31/08/2026).
create table public.bloco_aluno_reposicao (
  id              uuid primary key default gen_random_uuid(),
  unidade_id      uuid not null references public.unidade(id),
  bloco_id        uuid not null references public.bloco_horario(id),
  aluno_id        uuid not null references public.aluno(id) on delete cascade,
  data            date not null,
  bloco_origem_id uuid references public.bloco_horario(id),
  data_origem     date,
  -- Ajuste 2 do §8 do card 2.5 (= ajuste 1 do §14 do card 2.2), BLOQUEANTE: o
  -- DDL aceitava só PREVISTA/REALIZADA/CANCELADA. Sem `FALTOU`, quem não
  -- aparece à reposição fica indistinguível de quem a desmarcou com
  -- antecedência — e é exatamente essa diferença que o gatilho de reincidência
  -- do card 2.5 §3.4 mede. Nasce no `check`, sem alter table: a tabela é criada
  -- aqui, então não há "acrescentar" a fazer.
  status          text not null default 'PREVISTA'
                  check (status in ('PREVISTA','REALIZADA','FALTOU','CANCELADA')),
  observacao      text,
  criado_em       timestamptz not null default now(),
  criado_por      uuid,
  atualizado_em   timestamptz,
  atualizado_por  uuid,
  constraint bloco_aluno_reposicao_uk unique (bloco_id, aluno_id, data)
);

comment on table public.bloco_aluno_reposicao is
  'Reposição de aula perdida, com data. Só PREVISTA ocupa vaga na data (card 2.2 §4.2) — REALIZADA, FALTOU e CANCELADA saem da conta de lotação: o passado não bloqueia o presente. Sem política de DELETE: reposição registrada é histórico, e desmarcar é status = CANCELADA.';
comment on column public.bloco_aluno_reposicao.bloco_id is
  'Bloco ONDE o aluno vai repor. Sem `on delete cascade`, ao contrário de bloco_aluno: quem impede apagar o bloco é a guarda da seção 8, que dá a mensagem certa em vez do 23503 cru da FK.';
comment on column public.bloco_aluno_reposicao.bloco_origem_id is
  'Bloco da aula PERDIDA. Nulo é permitido de propósito (card 2.5 §3.1): a escola nem sempre sabe qual encontro foi perdido, e exigir o dado produziria preenchimento inventado. O preço é que reposição avulsa só se quita a si mesma.';
comment on column public.bloco_aluno_reposicao.status is
  'FALTOU não é CANCELADA, e a diferença é o gatilho de reincidência do card 2.5 §3.4: rep_faltas_max reposições FALTOU na janela do prazo bastam para sugerir a virada, mesmo com o saldo cabendo no prazo.';

-- -----------------------------------------------------------------------------
-- 2. Índices dos lados de FK que a unique não cobre
-- -----------------------------------------------------------------------------
-- Mesma razão dos cards 3.3, 4.1 e 4.3: uma unique serve de índice à FK só
-- quando a coluna é a PRIMEIRA dela, e índice parcial não serve nunca —
-- `bloco_aluno_ativo_uk` é parcial (`where ativo`), então não cobre a FK de
-- `bloco_id` nem a de `aluno_id`.
create index bloco_horario_sala_ix      on public.bloco_horario (sala_id);
create index bloco_horario_metodo_ix    on public.bloco_horario (metodo_id);
create index bloco_horario_professor_ix on public.bloco_horario (professor_id);

create index bloco_aluno_bloco_ix on public.bloco_aluno (bloco_id);
create index bloco_aluno_aluno_ix on public.bloco_aluno (aluno_id);

-- `bloco_aluno_reposicao_uk (bloco_id, aluno_id, data)` já cobre a FK de
-- `bloco_id`; as outras duas não têm quem as cubra.
create index bloco_aluno_reposicao_aluno_ix  on public.bloco_aluno_reposicao (aluno_id);
create index bloco_aluno_reposicao_origem_ix on public.bloco_aluno_reposicao (bloco_origem_id);

-- Do DDL do card 2.1: a lotação de um bloco em uma data soma as reposições
-- PREVISTA daquele dia, e isso é consulta de TELA (a grade do card 5.6 a faz por
-- bloco). Índice parcial porque o predicado é sempre o mesmo e os outros três
-- status são o passado, que não entra na conta.
create index bloco_aluno_reposicao_data_ix
  on public.bloco_aluno_reposicao (unidade_id, data) where status = 'PREVISTA';

-- -----------------------------------------------------------------------------
-- 3. Triggers de auditoria (C3 do card 2.8)
-- -----------------------------------------------------------------------------
create trigger tg_auditoria_bloco_horario
  before insert or update on public.bloco_horario
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_bloco_aluno
  before insert or update on public.bloco_aluno
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_bloco_aluno_reposicao
  before insert or update on public.bloco_aluno_reposicao
  for each row execute function public.fn_auditoria();

-- -----------------------------------------------------------------------------
-- 4. RLS habilitada e forçada
-- -----------------------------------------------------------------------------
-- Políticas no MESMO arquivo que as tabelas, como nos cards 4.1, 4.2 e 4.3:
-- "Automatically expose new tables" continua ligado nos dois projetos (pendência
-- técnica 3), então tabela sem política é uma API REST aberta pelo tempo que a
-- tarefa seguinte durar.
alter table public.bloco_horario         enable row level security;
alter table public.bloco_horario         force  row level security;
alter table public.bloco_aluno           enable row level security;
alter table public.bloco_aluno           force  row level security;
alter table public.bloco_aluno_reposicao enable row level security;
alter table public.bloco_aluno_reposicao force  row level security;

-- -----------------------------------------------------------------------------
-- 5. Políticas — docs/permissoes-matriz.md §4
-- -----------------------------------------------------------------------------
-- 5.1 bloco_horario — cadastro do bloco, padrão de quatro políticas
create policy bloco_horario_sel on public.bloco_horario for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('turmas.ler'));

create policy bloco_horario_ins on public.bloco_horario for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('turmas.criar'));

create policy bloco_horario_upd on public.bloco_horario for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('turmas.editar'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('turmas.editar'));

create policy bloco_horario_del on public.bloco_horario for delete to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('turmas.excluir'));

-- 5.2 bloco_aluno e bloco_aluno_reposicao — as duas fogem do padrão, e é o
--     achado central do card 2.4 (b): várias escritas acontecem como EFEITO
--     COLATERAL, dentro da transação de outro ator. `tg_aluno_status_desaloca`
--     (card 5.3) desativa as alocações quando o aluno sai de ATIVO/ACELERAR, e
--     ele roda como o pedagógico que mudou o status — que não tem
--     `turmas.alocar`. Um `turmas.alocar` sozinho no update faria a mudança de
--     status falhar com erro opaco de RLS numa tela que não fala de turma.
--
--     Sem DELETE em nenhuma das duas: alocação encerrada é `ativo = false` e
--     reposição desmarcada é `status = 'CANCELADA'`.
create policy bloco_aluno_sel on public.bloco_aluno for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('turmas.ler'));

create policy bloco_aluno_ins on public.bloco_aluno for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('turmas.alocar'));

create policy bloco_aluno_upd on public.bloco_aluno for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('turmas.alocar')
                   or public.tem_permissao('alunos.alterar_status')
                   or public.tem_permissao('alunos.reverter_status')))
  with check (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('turmas.alocar')
                   or public.tem_permissao('alunos.alterar_status')
                   or public.tem_permissao('alunos.reverter_status')));

create policy bloco_aluno_reposicao_sel on public.bloco_aluno_reposicao
  for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('turmas.ler'));

create policy bloco_aluno_reposicao_ins on public.bloco_aluno_reposicao
  for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('turmas.alocar'));

create policy bloco_aluno_reposicao_upd on public.bloco_aluno_reposicao
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
-- 6. tipo_desde é derivada, não editável (ajuste 1 do card 2.5, BLOQUEANTE)
-- -----------------------------------------------------------------------------
-- A alternativa — deduzir a data da virada de coalesce(atualizado_em, criado_em)
-- — foi descartada pelo card 2.5 §8: qualquer edição da linha empurraria a data
-- para frente e alteraria o débito sem que ninguém tivesse mudado nada.
--
-- No UPDATE a coluna é AUTORITATIVA: o valor enviado é ignorado, e só uma
-- mudança de `tipo` a move. Se o PATCH pudesse escrevê-la, a virada REP teria um
-- caminho de contorno pelo PostgREST — mandar `tipo_desde` para trás faz o
-- débito voltar a pesar, mandar para a frente o zera. É a mesma razão pela qual
-- `aluno.status_desde` só é escrita pelo trigger (card 4.2).
--
-- No INSERT o valor informado VALE, e a diferença é deliberada: o importador do
-- card 9.1 carrega alocações que já existiam, e forçar hoje ali faria toda
-- alocação migrada nascer com o relógio zerado no dia da virada — que é
-- justamente quando o dado precisa ser fiel ao passado.
create or replace function public.fn_bloco_aluno_tipo_desde()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.tipo is distinct from old.tipo then
    new.tipo_desde := public.fn_hoje();
  else
    new.tipo_desde := old.tipo_desde;
  end if;
  return new;
end $$;

comment on function public.fn_bloco_aluno_tipo_desde() is
  'Trigger BEFORE UPDATE em bloco_aluno: tipo_desde acompanha a MUDANÇA de tipo e ignora o valor enviado. É o relógio que a virada REP zera (card 2.5 §3.2); editável pelo PostgREST, ele viraria o contorno da própria regra.';

revoke execute on function public.fn_bloco_aluno_tipo_desde() from public;
revoke execute on function public.fn_bloco_aluno_tipo_desde() from anon;

create trigger tg_bloco_aluno_tipo_desde
  before update on public.bloco_aluno
  for each row execute function public.fn_bloco_aluno_tipo_desde();

-- -----------------------------------------------------------------------------
-- 7. RLS não é por coluna — a folga que o `or` da política de update abre
-- -----------------------------------------------------------------------------
-- O card 4.2 fechou este mesmo buraco em `aluno` e deixou escrito quem eram os
-- próximos: «coluna com permissão própria dentro de tabela com política única
-- precisa de guarda no trigger — `bloco_aluno.tipo` no 5.1 e
-- `certificado_checklist` no 8.3». É este o card.
--
-- O `or` da seção 5.2 existe por UM motivo só: deixar `tg_aluno_status_desaloca`
-- escrever `ativo = false` na transação de quem mudou o status. Mas RLS não é
-- por coluna, então ele autoriza junto qualquer outra coluna — e um perfil com
-- `alunos.alterar_status` e SEM `turmas.alocar` (que a direção monta na tela do
-- card 4.7) poderia, com um PATCH no PostgREST:
--   • mudar `tipo` para REP — executando a virada que o card 2.5 decidiu ser
--     SUGERIDA e feita por quem tem `turmas.alocar`, pulando a pendência;
--   • mudar `bloco_id` — mudando o aluno de turma sem passar por
--     fn_bloco_admitir e, portanto, sem a checagem de vaga do card 5.3;
--   • reativar (`ativo = false → true`) uma alocação que o próprio trigger de
--     status tinha encerrado, devolvendo à turma um aluno TRANCADO.
-- Nenhum perfil da matriz inicial é assim (os três que alteram status também
-- alocam), então nada denunciaria hoje — que é exatamente o que o card 4.2 disse
-- sobre `aluno.status`.
create or replace function public.fn_bloco_aluno_colunas_permitidas()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  -- `ativo` fica de fora da lista: é a única coluna que a desalocação sem ator
  -- precisa escrever, e ela é justamente o que o `or` da política existe para
  -- permitir. Tudo o mais é alocação, e alocar exige turmas.alocar.
  if new.bloco_id             is distinct from old.bloco_id
     or new.aluno_id             is distinct from old.aluno_id
     or new.tipo                 is distinct from old.tipo
     or new.data_inicio_prevista is distinct from old.data_inicio_prevista then
    perform public.fn_exige_permissao('turmas.alocar');
  end if;

  return new;
end $$;

comment on function public.fn_bloco_aluno_colunas_permitidas() is
  'Trigger BEFORE UPDATE em bloco_aluno: só `ativo` é escrita sob alunos.alterar_status; mudar bloco, aluno, tipo ou data prevista exige turmas.alocar. Onde a permissão é por coluna, a RLS é a segunda barreira e o trigger é a primeira (card 2.4, card 4.2).';

revoke execute on function public.fn_bloco_aluno_colunas_permitidas() from public;
revoke execute on function public.fn_bloco_aluno_colunas_permitidas() from anon;

-- Triggers BEFORE de mesma linha disparam em ordem alfabética de nome, então
-- esta vem ANTES de tg_bloco_aluno_tipo_desde — e a ordem não importa: a guarda
-- só levanta exceção, que aborta a transação inteira e desfaz junto o que o
-- outro trigger tivesse escrito em NEW.
create trigger tg_bloco_aluno_colunas_permitidas
  before update on public.bloco_aluno
  for each row execute function public.fn_bloco_aluno_colunas_permitidas();

-- A mesma folga, na mesma família: `tg_aluno_status_desaloca` cancela as
-- reposições futuras do aluno que saiu, e é só isso que precisa passar sem
-- `turmas.alocar`. Sem esta guarda, quem só altera status poderia marcar uma
-- reposição como REALIZADA — quitando um débito que não foi reposto e desligando
-- a sugestão de virada do card 2.5 pela porta dos fundos.
create or replace function public.fn_reposicao_colunas_permitidas()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.bloco_id        is distinct from old.bloco_id
     or new.aluno_id        is distinct from old.aluno_id
     or new.data            is distinct from old.data
     or new.bloco_origem_id is distinct from old.bloco_origem_id
     or new.data_origem     is distinct from old.data_origem
     or (new.status is distinct from old.status and new.status <> 'CANCELADA') then
    perform public.fn_exige_permissao('turmas.alocar');
  end if;

  return new;
end $$;

comment on function public.fn_reposicao_colunas_permitidas() is
  'Trigger BEFORE UPDATE em bloco_aluno_reposicao: sob alunos.alterar_status só se pode CANCELAR (o que tg_aluno_status_desaloca faz); registrar REALIZADA/FALTOU ou mexer em data e origem exige turmas.alocar.';

revoke execute on function public.fn_reposicao_colunas_permitidas() from public;
revoke execute on function public.fn_reposicao_colunas_permitidas() from anon;

create trigger tg_reposicao_colunas_permitidas
  before update on public.bloco_aluno_reposicao
  for each row execute function public.fn_reposicao_colunas_permitidas();

-- -----------------------------------------------------------------------------
-- 8. "Excluir bloco sem alocação" deixa de ser intenção e vira estrutura
-- -----------------------------------------------------------------------------
-- O card 4.3 mediu que a ação em cascata de uma FK NÃO passa pela RLS da tabela
-- referenciadora, e nomeou os candidatos vivos: «`bloco_aluno` /
-- `bloco_aluno_reposicao` (5.1) e, sobretudo, `movimento_estoque` (6.1)». É este
-- o card, e o buraco é o mesmo com outra roupa:
--
--   • o catálogo do card 2.4 §3.4 descreve `turmas.excluir` como "excluir
--     bloco/turma SEM ALOCAÇÃO", e nada no schema fazia isso valer;
--   • `bloco_aluno.bloco_id` é `on delete cascade`, e `bloco_aluno` não tem
--     política de delete PARA NINGUÉM — a ausência é a decisão (card 2.4 §4).
--     Um `delete from bloco_horario` da direção levava junto, em silêncio, o
--     registro de quem esteve naquela turma;
--   • `bloco_aluno_reposicao.bloco_id` é RESTRICT, então o mesmo delete falhava
--     com um `23503` cru — a MESMA operação com dois desfechos opostos, um
--     silencioso e um ilegível, o que é pior do que qualquer um dos dois.
--
-- A guarda não fecha a exclusão, fecha a exclusão COM HISTÓRICO: bloco digitado
-- errado, sem ninguém alocado e sem reposição, continua apagável — é o que
-- mantém `turmas.excluir` com um uso real. Bloco que já rodou sai por
-- `ativo = false`, que é a coluna que existe para isso.
--
-- Alocação INATIVA conta como histórico, de propósito: `ativo = false` é como o
-- aluno sai da turma, então um bloco só com alocações inativas é exatamente um
-- bloco que já teve gente — e é esse registro que a cascata apagaria.
create or replace function public.fn_bloco_exclusao_valida()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_alocacoes  bigint;
  v_reposicoes bigint;
  v_origens    bigint;
begin
  select count(*) into v_alocacoes  from public.bloco_aluno
   where bloco_id = old.id;
  select count(*) into v_reposicoes from public.bloco_aluno_reposicao
   where bloco_id = old.id;
  select count(*) into v_origens    from public.bloco_aluno_reposicao
   where bloco_origem_id = old.id;

  if v_alocacoes + v_reposicoes + v_origens > 0 then
    raise exception using
      errcode = 'PT409',
      message = 'Este bloco tem histórico de alunos e não pode ser excluído. Desative-o.',
      detail  = json_build_object('codigo', 'BLOCO_COM_ALOCACAO',
                                  'bloco', old.id,
                                  'alocacoes', v_alocacoes,
                                  'reposicoes', v_reposicoes,
                                  'reposicoes_de_origem', v_origens)::text;
  end if;

  return old;
end $$;

-- `security invoker` (o default), como `fn_pc_exclusao_valida` do card 4.3 e
-- pela mesma razão: ela só conta linhas de tabelas que o próprio chamador já
-- pode ler — quem tem `turmas.excluir` tem `turmas.ler`, que cobre as três —, e
-- entrar na lista fechada do C8 sem necessidade gasta a revisão consciente que a
-- lista existe para provocar (card 3.4 (a)).
comment on function public.fn_bloco_exclusao_valida() is
  'Trigger BEFORE DELETE em bloco_horario: recusa (PT409 / BLOCO_COM_ALOCACAO) apagar bloco com alocação (ativa ou não), com reposição marcada nele ou com reposição que o cite como origem. Faz valer o "sem alocação" do card 2.4 §3.4, que a cascata de bloco_aluno contornava sem erro.';

revoke execute on function public.fn_bloco_exclusao_valida() from public;
revoke execute on function public.fn_bloco_exclusao_valida() from anon;
grant  execute on function public.fn_bloco_exclusao_valida() to authenticated;

create trigger tg_bloco_exclusao_valida
  before delete on public.bloco_horario
  for each row execute function public.fn_bloco_exclusao_valida();

-- -----------------------------------------------------------------------------
-- 9. O aluno que sai de ATIVO/ACELERAR larga a vaga (card 2.2 §3.2)
-- -----------------------------------------------------------------------------
-- Este trigger é de `aluno`, não das tabelas deste card — e mesmo assim é deste
-- card, por decisão que o próprio card 4.2 deixou ESCRITA COMO PORTÃO na suíte
-- (030 §6, `portao_trigger`): «`public.bloco_aluno` → `tg_aluno_status_desaloca`
-- → card 5.1». O portão reprovou na primeira execução desta migração, que é o
-- que ele existe para fazer. A nota do card 5.1 no board não o mencionava e a do
-- 5.3 o descrevia; divergência resolvida a favor do portão, e o motivo é o que o
-- 4.2 escreveu ao lado dele: **sem este trigger, o aluno que entra em STANDBY
-- continua ocupando vaga toda semana, sem erro nenhum e sem nada na tela
-- dizendo isso** — e a partir desta migração já existe vaga para ele ocupar.
-- Adiá-lo para o 5.3 seria deixar a janela aberta pelo tempo de uma tarefa,
-- exatamente o que o card 3.3 recusou fazer com a RLS.
--
-- `security invoker` de propósito: ele escreve na transação de quem mudou o
-- status, e é precisamente para esta escrita que a política de update das duas
-- tabelas aceita `alunos.alterar_status`/`alunos.reverter_status` (card 2.4 §7).
-- As guardas da seção 7 foram desenhadas em torno dela: `ativo` em bloco_aluno e
-- `status = 'CANCELADA'` em bloco_aluno_reposicao são exatamente as duas
-- escritas que passam sem `turmas.alocar`.
--
-- Só reposição FUTURA é cancelada. A passada é histórico e é o débito que o
-- critério do card 2.5 mede: cancelar retroativamente apagaria a razão pela qual
-- o aluno seria sugerido para REP contínuo quando voltasse.
--
-- ⚠️ O card 2.2 §3.2 lista TRÊS tabelas, e a terceira — `turma_modular_aluno` —
-- só nasce no card 7.1. Não dá para citá-la aqui, e esquecer de voltar não daria
-- erro nenhum: daria o erro errado, com o aluno Modular trancado continuando na
-- turma. Por isso o portão do teste 040 reprova no dia em que a tabela nascer e
-- esta função não a citar — a mesma forma que o card 4.2 deu ao gate de FORMADO.
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
  'Trigger AFTER UPDATE OF status em aluno: quem deixa de ser ATIVO/ACELERAR sai dos blocos (ativo = false) e tem as reposições FUTURAS canceladas. Voltar a ATIVO não realoca — a vaga pode já ter sido dada a outro (card 2.2 §3.2). Falta citar turma_modular_aluno quando o card 7.1 a criar; o portão do teste 040 reprova nesse dia.';

revoke execute on function public.fn_aluno_status_desaloca() from public;
revoke execute on function public.fn_aluno_status_desaloca() from anon;

create trigger tg_aluno_status_desaloca
  after update of status on public.aluno
  for each row when (old.status is distinct from new.status)
  execute function public.fn_aluno_status_desaloca();
