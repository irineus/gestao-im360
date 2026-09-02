-- =============================================================================
-- Card 4.2 — Schema: alunos e transições de status
-- Fonte: docs/modelagem-dados-ddl.md §7 (§5.3 do plano),
--        docs/regras-negocio-funcoes.md §3 (transições, triggers e funções),
--        docs/permissoes-matriz.md §4 (políticas) e §3.3 (domínio `alunos`).
--
-- Entrega: aluno, aluno_status_hist + triggers de auditoria + RLS habilitada,
--          FORÇADA e com as políticas do card 2.4 §4 + a tabela de transições
--          (fn_aluno_transicao_valida), o gate de FORMADO, os triggers de status
--          e as duas funções de aplicação (fn_aluno_alterar_status,
--          fn_aluno_reverter_status).
--
-- ⚠️ ESTRUTURA E MAIS NADA, sem exceção nenhuma desta vez.
--    Decisão de 02/09/2026 (Irineu): dado de negócio vindo da planilha fica
--    restrito ao ambiente dev/homolog até a virada do card 9.7. NENHUM aluno
--    entra em supabase/migrations/ — migração é o que o CI empurra para produção
--    sozinho no merge em `main`, e a planilha muda todo dia. Os alunos reais vêm
--    pelo importador do card 9.1, carregados só no projeto dev; aluno de teste é
--    da escola-fixture do card 3.4.5, que vive em supabase/seed.sql e nunca sai
--    do stack local. O portão do card 4.0,5 (portao-migracoes/varredor.mjs) tem
--    `aluno` e `aluno_status_hist` FORA da lista permitida: uma carga escrita
--    aqui reprova o CI, inclusive disfarçada dentro de função chamada daqui.
--
--    Diferente do card 4.1, este arquivo não tem sequer o caso `metodo`: as duas
--    tabelas nascem vazias em todo ambiente, e é assim que ficam até o 9.1.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Tabelas (§7 do DDL)
-- -----------------------------------------------------------------------------
create table public.aluno (
  id                   uuid primary key default gen_random_uuid(),
  unidade_id           uuid not null references public.unidade(id),
  -- Referência externa ao SGF, opcional e sem integração hoje (importação
  -- assíncrona futura). Único POR UNIDADE quando informado — índice parcial.
  codigo_sgf           text,
  nome                 text not null,
  metodo_id            uuid not null references public.metodo(id),
  combo_id             uuid references public.combo(id),
  status               text not null default 'ATIVO'
                       check (status in ('ATIVO','ACELERAR','STANDBY','TRANCADO',
                                         'CANCELADO','FORMADO')),
  status_desde         date not null default public.fn_hoje(),
  prev_conclusao_curso date,
  data_inicio          date not null default public.fn_hoje(),
  observacoes          text,
  conferido            boolean not null default false,
  criado_em            timestamptz not null default now(),
  criado_por           uuid,
  atualizado_em        timestamptz,
  atualizado_por       uuid,
  -- Os dois checks abaixo não estão no DDL do card 2.1 e entram com motivo.
  --
  -- `codigo_sgf` vazio NÃO é "sem código": string vazia não é nula, então dois
  -- alunos importados com '' colidiriam no índice parcial abaixo e o card 9.1
  -- receberia um erro de chave duplicada que não fala de nada — quando o que
  -- houve foi célula em branco na planilha. Exigir null torna a intenção
  -- explícita do lado de quem importa.
  constraint aluno_codigo_sgf_ck check (codigo_sgf is null or btrim(codigo_sgf) <> ''),
  constraint aluno_nome_ck       check (btrim(nome) <> '')
);

comment on table public.aluno is
  'Cadastro único do aluno (card 2.1 §7). VAZIA em produção até a virada do card 9.7: os alunos reais entram pelo importador do card 9.1, no ambiente dev.';
comment on column public.aluno.codigo_sgf is
  'Referência externa ao SGF, opcional. Única por unidade quando informada (aluno_codigo_sgf_uk). Não há integração: a importação assíncrona é assunto de outra fase.';
comment on column public.aluno.status_desde is
  'Data da última transição de status, escrita por tg_aluno_status_valida. Existe para o alerta de STANDBY prolongado (card 5.5) não precisar varrer aluno_status_hist a cada execução da rotina diária.';
comment on column public.aluno.prev_conclusao_curso is
  'Previsão de conclusão informada MANUALMENTE (decisão de 30/08/2026: não há regra de cálculo). É o degrau PREVISAO_CURSO da cascata da projeção (card de Ordem 5); vencida, não serve de base e vira pendência PREVISAO_VENCIDA.';
comment on column public.aluno.conferido is
  'Marca de conferência da migração (card 9.4): o aluno foi olhado por uma pessoa depois da carga. Nasce false e nada no sistema o liga sozinho.';

-- codigo_sgf é único por unidade quando informado; nulos não colidem entre si.
create unique index aluno_codigo_sgf_uk
  on public.aluno (unidade_id, codigo_sgf) where codigo_sgf is not null;

-- O DDL do card 2.1 pedia (unidade_id, status). Ajuste #6 do card 2.3 (§10 de
-- docs/views-leitura.md): o dashboard agrupa por MÉTODO dentro da unidade
-- (v_dashboard_alunos_metodo), e é essa a ordem que serve os dois usos — o
-- prefixo (unidade_id, metodo_id) e a coluna de status ao fim.
create index aluno_status_ix on public.aluno (unidade_id, metodo_id, status);

-- Lados de FK que nenhuma unique cobre. `combo` TEM política de delete
-- (materiais.excluir, card 4.1), então sem este índice apagar um combo varre a
-- tabela de alunos inteira para verificar o RESTRICT. `metodo` não tem delete
-- pela tela, mas o índice custa o mesmo e o aluno_status_ix não serve de FK:
-- metodo_id não é a primeira coluna dele.
create index aluno_combo_ix  on public.aluno (combo_id);
create index aluno_metodo_ix on public.aluno (metodo_id);

create table public.aluno_status_hist (
  id              uuid primary key default gen_random_uuid(),
  unidade_id      uuid not null references public.unidade(id),
  aluno_id        uuid not null references public.aluno(id) on delete cascade,
  status_anterior text,
  status_novo     text not null,
  ocorrido_em     timestamptz not null default now(),
  usuario_id      uuid references public.usuario(id),
  motivo          text,
  criado_em       timestamptz not null default now(),
  criado_por      uuid,
  atualizado_em   timestamptz,
  atualizado_por  uuid
);

comment on table public.aluno_status_hist is
  'Histórico imutável das transições de status. Imutável por AUSÊNCIA de política de update e delete (card 2.4 §4), como pc_credencial_acesso e movimento_estoque — "sem política, sem acesso" é o mecanismo, e o teste C4 escreve a ausência para que ela não passe por esquecimento.';
comment on column public.aluno_status_hist.status_novo is
  'Sem check duplicando o de aluno.status, de propósito: o único escritor legítimo é tg_aluno_status_hist, que copia a coluna já validada, e um check aqui teria de ser alterado em lockstep com o de lá. O que protege a linha forjada pelo PostgREST é tg_aluno_status_hist_coerente, que compara com o estado real do aluno.';
comment on column public.aluno_status_hist.motivo is
  'Motivo da transição, obrigatório para STANDBY/TRANCADO/CANCELADO e em toda reversão. Chega ao trigger pela GUC app.motivo_status; num UPDATE direto fica "alteração direta", nunca nulo por acidente.';

-- Serve à aba "Histórico de status" da ficha (card 4.6), que lê por aluno em
-- ordem cronológica, e ao ON DELETE CASCADE da FK.
create index aluno_status_hist_aluno_ix
  on public.aluno_status_hist (aluno_id, ocorrido_em desc);

-- Não há índice em usuario_id de propósito: `usuario` não tem política de delete
-- (card 2.4 §4) e o card 3.5 (c) decidiu que usuário não se apaga — a FK nunca
-- é verificada por remoção, e o índice só custaria escrita.

-- -----------------------------------------------------------------------------
-- 2. Triggers de auditoria (C3 do card 2.8)
-- -----------------------------------------------------------------------------
create trigger tg_auditoria_aluno
  before insert or update on public.aluno
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_aluno_status_hist
  before insert or update on public.aluno_status_hist
  for each row execute function public.fn_auditoria();

-- -----------------------------------------------------------------------------
-- 3. A tabela de transições — regra pura, testável sem banco carregado
-- -----------------------------------------------------------------------------
-- Duas leituras deliberadas do plano (card 2.2 §3.1), que ele não fecha:
--   • TRANCADO → ATIVO/ACELERAR é permitido (reativação de matrícula trancada);
--     barrar a volta obrigaria a recadastrar o aluno e perder o histórico.
--   • FORMADO e CANCELADO são TERMINAIS — sair deles é estorno explícito da
--     direção (fn_aluno_reverter_status), não transição comum.
create or replace function public.fn_aluno_transicao_valida(p_de text, p_para text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select (p_de, p_para) in (
    ('ATIVO','ACELERAR'), ('ACELERAR','ATIVO'),
    ('ATIVO','STANDBY'),  ('ACELERAR','STANDBY'),
    ('STANDBY','ATIVO'),  ('STANDBY','ACELERAR'), ('STANDBY','TRANCADO'),
    ('TRANCADO','ATIVO'), ('TRANCADO','ACELERAR'),
    ('ATIVO','FORMADO'),  ('ACELERAR','FORMADO')
  ) or (p_para = 'CANCELADO' and p_de <> 'CANCELADO');
$$;

comment on function public.fn_aluno_transicao_valida(text, text) is
  'Tabela de decisão das transições de status (card 2.2 §3.1). Qualquer origem vai a CANCELADO, menos CANCELADO nele mesmo: transição para o próprio status é no-op, e no-op silencioso é o que fn_aluno_alterar_status recusa.';

-- O grant é obrigatório e não é decoração: os triggers abaixo são `security
-- invoker`, então quem executa esta função é o `authenticated` que mudou o
-- status. Sem o grant, mudar status de aluno morreria com "permission denied for
-- function fn_aluno_transicao_valida" — erro que não fala de aluno nem de
-- status. Mesmo raciocínio para fn_aluno_pode_formar.
revoke execute on function public.fn_aluno_transicao_valida(text, text) from public;
revoke execute on function public.fn_aluno_transicao_valida(text, text) from anon;
grant  execute on function public.fn_aluno_transicao_valida(text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. O gate de FORMADO (card 2.2 §3.3)
-- -----------------------------------------------------------------------------
-- ATIVO/ACELERAR → FORMADO só passa se UMA destas valer:
--   (1) existe certificado_checklist do aluno com certificado_status ENTREGUE;
--   (2) tem_permissao('alunos.formar_sem_certificado') — a "confirmação da
--       direção" das Decisões vigentes, expressa como PERMISSÃO e não perfil.
--
-- ⚠️ A condição (1) NÃO PODE SER ESCRITA HOJE: `certificado_checklist` nasce no
-- card 8.3. Escrever só a (2) e confiar em que alguém se lembre de voltar aqui é
-- exatamente o que este projeto não faz — e o esquecimento teria sintoma ruim:
-- da Fase 8 em diante, o pedagógico com o certificado ENTREGUE na mão receberia
-- FORMATURA_SEM_CERTIFICADO, e a leitura óbvia do erro ("falta o certificado")
-- seria falsa.
--
-- Por isso o gate mora em função PRÓPRIA, e a metade que falta é cobrada por um
-- portão no teste 030 — o mesmo mecanismo que o card 3.4.5 usa para a fixture:
-- no dia em que `certificado_checklist` existir, a suíte fica VERMELHA enquanto
-- o corpo desta função não a citar. O card 8.3 troca só este corpo.
create or replace function public.fn_aluno_pode_formar(p_aluno_id uuid)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  -- Condição (1) entra aqui no card 8.3:
  --   exists (select 1 from certificado_checklist cc
  --            where cc.aluno_id = p_aluno_id and cc.certificado_status = 'ENTREGUE')
  --   or ...
  select public.tem_permissao('alunos.formar_sem_certificado');
$$;

comment on function public.fn_aluno_pode_formar(uuid) is
  'Gate de FORMADO (card 2.2 §3.3). Hoje só a metade da permissão: a metade do certificado ENTREGUE depende de certificado_checklist (card 8.3), e o teste 030 reprova a suíte no dia em que a tabela nascer sem esta função citá-la.';

revoke execute on function public.fn_aluno_pode_formar(uuid) from public;
revoke execute on function public.fn_aluno_pode_formar(uuid) from anon;
grant  execute on function public.fn_aluno_pode_formar(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Triggers de status (card 2.2 §3.2)
-- -----------------------------------------------------------------------------
-- 5.1 Validação — camada 2: vale mesmo para quem escreve direto no PostgREST.
--
-- `when (old.status is distinct from new.status)` não é otimização: sem ele, um
-- PATCH que reenvia a linha inteira sem mexer no status dispararia o trigger com
-- (ATIVO, ATIVO), que não está na tabela de transições — e editar o telefone de
-- um aluno responderia TRANSICAO_INVALIDA.
create or replace function public.fn_aluno_status_valida()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_reversao boolean := coalesce(current_setting('app.reverter_status', true), '') = 'on';
begin
  if v_reversao then
    -- Reversão de status terminal (card 2.2 §3.4). A GUC sozinha NÃO autoriza
    -- nada: a permissão é reconferida aqui, de modo que o desvio exija o mesmo
    -- código que fn_aluno_reverter_status exige — a GUC diz "esta é a intenção",
    -- a permissão diz "e quem quer pode".
    if not public.tem_permissao('alunos.reverter_status') then
      raise exception using
        errcode = 'PT403',
        message = 'reverter status exige a permissão alunos.reverter_status',
        detail  = json_build_object('codigo', 'SEM_PERMISSAO',
                                    'permissao', 'alunos.reverter_status')::text;
    end if;

    -- Reversão só sai de status TERMINAL e só chega a status NÃO terminal.
    -- Sem estas duas metades, a GUC viraria um desvio geral da tabela de
    -- transições, e a direção passaria a poder tudo sem que nada dissesse isso.
    if old.status not in ('FORMADO','CANCELADO')
       or new.status in ('FORMADO','CANCELADO') then
      raise exception using
        errcode = 'PT409',
        message = format('reversão inválida: %s -> %s', old.status, new.status),
        detail  = json_build_object('codigo', 'TRANSICAO_INVALIDA',
                                    'de', old.status, 'para', new.status)::text;
    end if;
  else
    -- A permissão de MUDAR STATUS é conferida aqui, e não só na função de
    -- aplicação, porque RLS não é por coluna (card 2.4): a política de update de
    -- `aluno` aceita o `or` de três códigos, então um perfil com apenas
    -- `alunos.editar` — que existe assim que a direção montar um na tela do card
    -- 4.7 — poderia PATCHar `status` pelo PostgREST sem ter
    -- `alunos.alterar_status`. É o mesmo desenho que o card 2.4 deu ao
    -- `certificado_checklist`: onde a permissão é por coluna, a RLS é a segunda
    -- barreira e o trigger é a primeira.
    if not public.tem_permissao('alunos.alterar_status') then
      raise exception using
        errcode = 'PT403',
        message = 'mudar o status do aluno exige a permissão alunos.alterar_status',
        detail  = json_build_object('codigo', 'SEM_PERMISSAO',
                                    'permissao', 'alunos.alterar_status')::text;
    end if;

    if not public.fn_aluno_transicao_valida(old.status, new.status) then
      raise exception using
        errcode = 'PT409',
        message = format('transição de status inválida: %s -> %s', old.status, new.status),
        detail  = json_build_object('codigo', 'TRANSICAO_INVALIDA',
                                    'de', old.status, 'para', new.status)::text;
    end if;

    if new.status = 'FORMADO' and not public.fn_aluno_pode_formar(new.id) then
      raise exception using
        errcode = 'PT409',
        message = 'formatura exige certificado entregue ou confirmação da direção',
        detail  = json_build_object('codigo', 'FORMATURA_SEM_CERTIFICADO',
                                    'aluno', new.id)::text;
    end if;
  end if;

  new.status_desde := public.fn_hoje();
  return new;
end $$;

comment on function public.fn_aluno_status_valida() is
  'Trigger BEFORE UPDATE OF status em aluno: recusa transição fora de fn_aluno_transicao_valida (PT409/TRANSICAO_INVALIDA), aplica o gate de FORMADO e carimba status_desde. É a camada 2 do card 2.8 §6.1 — vale para o PATCH direto no PostgREST, não só para a função de aplicação.';

revoke execute on function public.fn_aluno_status_valida() from public;
revoke execute on function public.fn_aluno_status_valida() from anon;

create trigger tg_aluno_status_valida
  before update of status on public.aluno
  for each row when (old.status is distinct from new.status)
  execute function public.fn_aluno_status_valida();

-- 5.2 Histórico — o registro nunca deixa de existir.
--
-- A GUC app.motivo_status é preenchida por fn_aluno_alterar_status. Num UPDATE
-- direto ela vem vazia e o histórico registra 'alteração direta': linha sem
-- motivo seria indistinguível de motivo esquecido, e a diferença entre "mudou
-- pela tela" e "mudou por fora" é justamente o que se quer ler três meses
-- depois.
create or replace function public.fn_aluno_status_hist()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_motivo text := nullif(btrim(coalesce(current_setting('app.motivo_status', true), '')), '');
begin
  insert into public.aluno_status_hist
    (unidade_id, aluno_id, status_anterior, status_novo, usuario_id, motivo)
  values
    (new.unidade_id, new.id, old.status, new.status, auth.uid(),
     coalesce(v_motivo, 'alteração direta'));
  return null;
end $$;

comment on function public.fn_aluno_status_hist() is
  'Trigger AFTER UPDATE OF status em aluno: grava a linha de aluno_status_hist. Roda como o chamador (invoker), então a política de insert do card 2.4 §4 — alunos.alterar_status ∨ alunos.reverter_status — é a mesma que já autorizou o update em aluno.';

revoke execute on function public.fn_aluno_status_hist() from public;
revoke execute on function public.fn_aluno_status_hist() from anon;

create trigger tg_aluno_status_hist
  after update of status on public.aluno
  for each row when (old.status is distinct from new.status)
  execute function public.fn_aluno_status_hist();

-- 5.3 Coerência do histórico — camada 2 sobre a própria tabela de histórico.
--
-- A política de insert de aluno_status_hist tem de aceitar a escrita do trigger
-- acima, e com isso aceita também um POST direto no PostgREST de quem tem
-- alunos.alterar_status. Sem guarda, dava para escrever histórico que CONTRADIZ
-- o aluno — "formado em março" num aluno ATIVO —, e histórico que mente é pior
-- que histórico ausente, porque tem cara de prova.
--
-- A guarda é mínima de propósito: exige que a linha descreva o estado real
-- (status_novo = status atual do aluno) e a unidade certa. Não impede registrar
-- uma transição a mais que de fato aconteceu; impede registrar uma que não
-- aconteceu.
create or replace function public.fn_aluno_status_hist_coerente()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_status  text;
  v_unidade uuid;
begin
  -- Lê `aluno` como o chamador (invoker), então depende de `alunos.ler`. Não é
  -- acoplamento frágil: os quatro perfis têm `alunos.ler` por decisão do card
  -- 2.4, e um perfil que pudesse mudar status sem poder ler o aluno já não
  -- conseguiria abrir a ficha de onde a ação sai.
  select a.status, a.unidade_id into v_status, v_unidade
    from public.aluno a where a.id = new.aluno_id;

  -- Os dois `raise` deste trigger saem SEM `codigo` no DETAIL, de propósito e
  -- pelo mesmo motivo do card 4.1: o catálogo de códigos é o contrato entre o
  -- banco e o Flutter (test/fixtures/codigos_erro.txt), e nenhuma tela do
  -- sistema escreve em aluno_status_hist — quem chega aqui está usando o
  -- PostgREST à mão. Inventar um código gastaria o contrato com quem não o
  -- consome, e o teste C12 cobraria uma mensagem de tela que ninguém veria.
  if v_status is null then
    raise exception using
      errcode = 'PT422',
      message = 'histórico de status de aluno inexistente ou de outra unidade';
  end if;

  if new.status_novo is distinct from v_status or new.unidade_id is distinct from v_unidade then
    raise exception using
      errcode = 'PT422',
      message = format('histórico incoerente: status_novo %s, status atual do aluno %s',
                       new.status_novo, v_status);
  end if;

  return new;
end $$;

comment on function public.fn_aluno_status_hist_coerente() is
  'Trigger BEFORE INSERT em aluno_status_hist: a linha tem de descrever o estado real do aluno (mesmo status, mesma unidade). Fecha o POST direto no PostgREST que a política de insert precisa deixar aberta para o trigger de histórico funcionar (card 2.4 §4).';

revoke execute on function public.fn_aluno_status_hist_coerente() from public;
revoke execute on function public.fn_aluno_status_hist_coerente() from anon;

create trigger tg_aluno_status_hist_coerente
  before insert on public.aluno_status_hist
  for each row execute function public.fn_aluno_status_hist_coerente();

-- -----------------------------------------------------------------------------
-- 6. RLS habilitada e forçada, com as políticas do card 2.4 §4
-- -----------------------------------------------------------------------------
-- Políticas no MESMO arquivo das tabelas, pela razão do card 4.1: "Automatically
-- expose new tables" está ligado nos dois projetos, e tabela publicada sem
-- política é uma API aberta pelo tempo que a tarefa seguinte durar.
alter table public.aluno             enable row level security;
alter table public.aluno             force  row level security;
alter table public.aluno_status_hist enable row level security;
alter table public.aluno_status_hist force  row level security;

-- 6.1 aluno — sem delete, e não por esquecimento: aluno não some, vira
-- CANCELADO (card 2.4 (a): por isso não existe o código `alunos.excluir`). Quem
-- registra essa ausência como decisão é o teste C4 por comando.
create policy aluno_sel on public.aluno for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('alunos.ler'));

create policy aluno_ins on public.aluno for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('alunos.criar'));

-- O `or` dos três códigos é o que faz a mudança de status funcionar sem dar
-- `alunos.editar` a quem só pode mudar status — e o que permite à direção
-- reverter um terminal sem passar por `alunos.editar`.
create policy aluno_upd on public.aluno for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('alunos.editar')
                or public.tem_permissao('alunos.alterar_status')
                or public.tem_permissao('alunos.reverter_status')))
  with check (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('alunos.editar')
                or public.tem_permissao('alunos.alterar_status')
                or public.tem_permissao('alunos.reverter_status')));

-- 6.2 aluno_status_hist — select e insert, nada mais.
create policy aluno_status_hist_sel on public.aluno_status_hist for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('alunos.ler'));

create policy aluno_status_hist_ins on public.aluno_status_hist for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('alunos.alterar_status')
                or public.tem_permissao('alunos.reverter_status')));

-- -----------------------------------------------------------------------------
-- 7. Funções de aplicação (card 2.2 §3.4)
-- -----------------------------------------------------------------------------
-- Ambas `security invoker`, como manda o card 2.2: a RLS que elas encontram é a
-- de quem chamou, e fn_exige_permissao existe para trocar o silêncio da RLS
-- ("zero linhas afetadas") pelo erro com código estável.
create or replace function public.fn_aluno_alterar_status(
  p_aluno_id uuid, p_status text, p_motivo text default null)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_atual  text;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  perform public.fn_exige_permissao('alunos.alterar_status');

  select status into v_atual from public.aluno where id = p_aluno_id;

  if v_atual is null then
    raise exception using
      errcode = 'PT422',
      message = 'aluno inexistente ou de outra unidade',
      detail  = json_build_object('codigo', 'ALUNO_INEXISTENTE', 'aluno', p_aluno_id)::text;
  end if;

  -- Mudar para o status que já vale seria um UPDATE sem trigger (o `when` dos
  -- triggers compara old e new) — nenhum erro, nenhum histórico, e a tela
  -- mostrando sucesso. No-op silencioso é defeito, não tolerância.
  if v_atual = p_status then
    raise exception using
      errcode = 'PT409',
      message = format('o aluno já está em %s', p_status),
      detail  = json_build_object('codigo', 'TRANSICAO_INVALIDA',
                                  'de', v_atual, 'para', p_status)::text;
  end if;

  if p_status in ('STANDBY','TRANCADO','CANCELADO') and v_motivo is null then
    raise exception using
      errcode = 'PT422',
      message = format('motivo é obrigatório para %s', p_status),
      detail  = json_build_object('codigo', 'MOTIVO_OBRIGATORIO', 'status', p_status)::text;
  end if;

  perform set_config('app.motivo_status', coalesce(v_motivo, ''), true);
  update public.aluno set status = p_status where id = p_aluno_id;
  -- Limpar depois de usar é obrigatório: a GUC é local à TRANSAÇÃO, não à
  -- chamada, e sem esta linha uma segunda mudança de status na mesma transação
  -- (outra chamada sem motivo, ou um UPDATE direto) herdaria o motivo desta —
  -- histórico com motivo de outro aluno, e nada acusando.
  perform set_config('app.motivo_status', '', true);
end $$;

comment on function public.fn_aluno_alterar_status(uuid, text, text) is
  'Transição normal de status (card 2.2 §3.4). Exige alunos.alterar_status; motivo obrigatório para STANDBY/TRANCADO/CANCELADO; devolve os erros dos triggers já com código estável no DETAIL.';

revoke execute on function public.fn_aluno_alterar_status(uuid, text, text) from public;
revoke execute on function public.fn_aluno_alterar_status(uuid, text, text) from anon;
grant  execute on function public.fn_aluno_alterar_status(uuid, text, text) to authenticated;

-- Único caminho para sair de FORMADO/CANCELADO. O motivo é sempre obrigatório:
-- desfazer um estado terminal é exceção, e exceção sem justificativa escrita é o
-- que ninguém consegue auditar depois.
create or replace function public.fn_aluno_reverter_status(
  p_aluno_id uuid, p_status_destino text, p_motivo text default null)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_atual  text;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  perform public.fn_exige_permissao('alunos.reverter_status');

  select status into v_atual from public.aluno where id = p_aluno_id;

  if v_atual is null then
    raise exception using
      errcode = 'PT422',
      message = 'aluno inexistente ou de outra unidade',
      detail  = json_build_object('codigo', 'ALUNO_INEXISTENTE', 'aluno', p_aluno_id)::text;
  end if;

  if v_motivo is null then
    raise exception using
      errcode = 'PT422',
      message = 'motivo é obrigatório para reverter um status terminal',
      detail  = json_build_object('codigo', 'MOTIVO_OBRIGATORIO',
                                  'status', p_status_destino)::text;
  end if;

  perform set_config('app.motivo_status',    v_motivo, true);
  perform set_config('app.reverter_status', 'on',      true);
  update public.aluno set status = p_status_destino where id = p_aluno_id;
  perform set_config('app.reverter_status', '', true);
  perform set_config('app.motivo_status',   '', true);
end $$;

comment on function public.fn_aluno_reverter_status(uuid, text, text) is
  'Estorno de status terminal (card 2.2 §3.4): único caminho para sair de FORMADO/CANCELADO. Exige alunos.reverter_status — só a direção na matriz inicial — e motivo não vazio. A GUC app.reverter_status apenas declara a intenção; quem autoriza é a permissão, reconferida dentro do trigger.';

revoke execute on function public.fn_aluno_reverter_status(uuid, text, text) from public;
revoke execute on function public.fn_aluno_reverter_status(uuid, text, text) from anon;
grant  execute on function public.fn_aluno_reverter_status(uuid, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 8. O que este card NÃO entrega, e onde isso está cobrado
-- -----------------------------------------------------------------------------
-- Três triggers de `aluno` do card 2.2 §3.2 dependem de tabelas que ainda não
-- existem, e cada um tem um portão no teste 030 que fica VERMELHO no dia em que
-- a tabela nascer sem ele:
--
--   • tg_aluno_status_desaloca — precisa de bloco_aluno (card 5.1). Sem ele, o
--     aluno em STANDBY continua ocupando vaga toda semana, em silêncio.
--   • tg_aluno_trilha_inicial  — precisa de aluno_material (card 6.1/6.2).
--   • tg_aluno_combo_alterado  — precisa de pendencia   (card 5.5).
--
-- Escrevê-los agora derrubaria a migração no primeiro `insert`; comentá-los sem
-- portão produziria o artefato que o card 2.8 combate. A ausência fica declarada
-- e cobrada, que é o padrão do card 3.4.5.
