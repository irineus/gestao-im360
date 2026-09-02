-- =============================================================================
-- Card 4.3 — Schema: infraestrutura física (sala, pc, pc_manutencao, professor)
-- Fonte: docs/modelagem-dados-ddl.md §8 (§5.4 e §5.5 do plano),
--        docs/politica-credenciais-pcs.md (card 2.9, política das credenciais),
--        docs/permissoes-matriz.md §4 (políticas) e §3.3 (domínios `salas` e
--        `professores`).
--
-- Entrega: sala, pc, pc_manutencao, professor e pc_credencial_acesso
--          + triggers de auditoria + RLS habilitada, FORÇADA e com as políticas
--          do card 2.4 §4 + as duas funções de credencial do card 2.9, o trigger
--          que não deixa segredo órfão no Vault e a guarda de exclusão de PC.
--
-- ⚠️ ESTRUTURA E MAIS NADA, sem exceção nenhuma.
--    Decisão de 02/09/2026 (Irineu): dado de negócio vindo da planilha fica
--    restrito ao ambiente dev/homolog até a virada do card 9.7. As salas, os PCs
--    e os professores REAIS não entram em supabase/migrations/ — migração é o
--    que o CI empurra para produção sozinho no merge em `main`. Eles vêm pelo
--    importador do card 9.1, carregados só no projeto dev; sala e PC de teste
--    são da escola-fixture do card 3.4.5, que vive em supabase/seed.sql e nunca
--    sai do stack local. O portão do card 4.0,5 (portao-migracoes/varredor.mjs)
--    tem as cinco tabelas deste arquivo FORA da lista permitida.
--
-- ⚠️ E NENHUMA SENHA, que aqui é uma proibição a mais e não a mesma.
--    As senhas atuais dos PCs estão QUEIMADAS: circularam em texto puro na aba
--    `PCS` da planilha (card 2.9 §1.5). A migração não traz credencial nenhuma;
--    as contas são rotacionadas nas máquinas na virada e digitadas uma vez, na
--    tela do card 4.5, por quem tem `salas.acessar_credencial`.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. A extensão do Vault é pré-condição, e o que cabe aqui é CONFERIR
-- -----------------------------------------------------------------------------
-- O ajuste #2 do card 2.9 pedia "habilitar a extensão supabase_vault na
-- migração". Medido no stack local (02/09/2026): não há o que habilitar —
-- `supabase_vault` já vem instalada de fábrica, no schema `vault`, em todo
-- projeto Supabase, e `create extension` seria um no-op que dá a impressão de
-- estar controlando algo. O que o card 3.11 mediu vale de lição aqui: um banco
-- criado do zero NÃO é um projeto Supabase novo, e `vault` é objeto de BANCO.
--
-- Então em vez de criar, este bloco EXIGE. Num projeto Supabase é silencioso;
-- num destino que não tenha a casca da plataforma (o alvo do ensaio de
-- restauração do card 3.11, um Postgres puro) ele para o `db push` com a causa
-- escrita, em vez de deixar as duas funções abaixo nascerem quebradas — e
-- função de credencial quebrada só se descobre no dia em que alguém precisa da
-- senha.
--
-- Sem `codigo` no DETAIL, de propósito, pela razão do card 4.1: o catálogo de
-- erros é o contrato entre o banco e o Flutter, e este erro não chega a tela
-- nenhuma — ele para o CI, que é onde precisa ser lido.
do $$
begin
  if to_regnamespace('vault') is null
     or not exists (select 1 from pg_extension where extname = 'supabase_vault') then
    raise exception 'extensão supabase_vault ausente: as credenciais de PC do card 2.9 dependem dela (schema vault + vault.create_secret + vault.decrypted_secrets)';
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- 2. Tabelas (§8 do DDL, mais pc_credencial_acesso do card 2.9 §6)
-- -----------------------------------------------------------------------------
create table public.sala (
  id                 uuid primary key default gen_random_uuid(),
  unidade_id         uuid not null references public.unidade(id),
  nome               text not null,
  tipo               text not null check (tipo in ('LABORATORIO','SALA_MODULAR')),
  capacidade_nominal integer not null check (capacidade_nominal > 0),
  ativo              boolean not null default true,
  criado_em          timestamptz not null default now(),
  criado_por         uuid,
  atualizado_em      timestamptz,
  atualizado_por     uuid,
  constraint sala_nome_uk unique (unidade_id, nome),
  -- Mesma razão do `aluno_nome_ck` do card 4.2: nome vazio não é nome, e string
  -- vazia passa por `not null` sem que nada acuse. Na sala o dano é a unique
  -- recusar a SEGUNDA sala em branco na importação do card 9.1, com erro de
  -- chave duplicada que fala de outra coisa.
  constraint sala_nome_ck check (btrim(nome) <> '')
);

comment on table public.sala is
  'Laboratório (PCs) ou sala modular. VAZIA em produção até a virada do card 9.7: as salas reais entram pelo importador do card 9.1, no ambiente dev.';
comment on column public.sala.capacidade_nominal is
  'Teto físico da sala. A capacidade EFETIVA de um bloco é função do card 5.2 — coalesce(capacidade_override, PCs OPERACIONAIS), combinada com este teto —, nunca coluna.';

create table public.pc (
  id            uuid primary key default gen_random_uuid(),
  unidade_id    uuid not null references public.unidade(id),
  sala_id       uuid not null references public.sala(id),
  identificador text not null,
  status        text not null default 'OPERACIONAL'
                check (status in ('OPERACIONAL','MANUTENCAO','DESATIVADO')),
  -- O DDL do card 2.1 reservava aqui `credencial_ref text`, com o comentário
  -- "política definitiva: card 2.9". A política existe desde 01/09/2026 e é
  -- outra: o segredo é o PAR inteiro ({usuario, senha} como jsonb) e mora
  -- cifrado em `vault.secrets`; `pc` guarda o ponteiro e mais nada em claro.
  --
  -- Nenhuma coluna de e-mail em texto puro, e a razão é do card 2.4: RLS NÃO É
  -- POR COLUNA. Um `credencial_usuario` aqui seria legível por qualquer um com
  -- `salas.ler` pelo PostgREST — e `salas.ler` é permissão dos quatro perfis.
  -- Guardando o par inteiro no Vault, a restrição volta a ser de TABELA e de
  -- FUNÇÃO, que é onde a RLS sabe trabalhar.
  --
  -- Sem FK para vault.secrets de propósito (card 2.9 §3): é tabela gerenciada
  -- pela plataforma, e uma FK para schema administrado por fora quebra em
  -- atualização do Supabase. O órfão é evitado pelo trigger da seção 8.
  credencial_secret_id uuid,
  credencial_em        timestamptz,
  credencial_por       uuid,
  observacao    text,
  criado_em     timestamptz not null default now(),
  criado_por    uuid,
  atualizado_em timestamptz,
  atualizado_por uuid,
  constraint pc_identificador_uk unique (unidade_id, identificador),
  constraint pc_identificador_ck check (btrim(identificador) <> ''),
  -- As três colunas de credencial andam JUNTAS ou nenhuma vale. Sem este check,
  -- `credencial_em` preenchido com `credencial_secret_id` nulo faria a ficha do
  -- PC (card 2.9 §8) mostrar "credencial cadastrada · atualizada em dd/mm" para
  -- um PC sem credencial nenhuma — e o monitor descobriria no laboratório, com
  -- o diálogo abrindo vazio.
  constraint pc_credencial_ck check (
    (credencial_secret_id is null and credencial_em is null and credencial_por is null)
    or (credencial_secret_id is not null and credencial_em is not null))
);

comment on table public.pc is
  'PC do laboratório. VAZIA em produção até a virada do card 9.7. As credenciais NUNCA vêm por migração nem por importação: as atuais estão queimadas (card 2.9 §1.5), e as novas são digitadas na tela depois da rotação nas máquinas.';
comment on column public.pc.credencial_secret_id is
  'Ponteiro para vault.secrets, onde vive o par {usuario, senha} cifrado. Escrito só por fn_pc_credencial_gravar; lido só por fn_pc_credencial_ler. Nenhuma tela, view ou select do PostgREST devolve a senha.';
comment on column public.pc.status is
  'OPERACIONAL conta vaga na capacidade efetiva (card 5.2); MANUTENCAO e DESATIVADO não. Editável com `salas.editar` (card 2.4 §3.3), e a coerência com pc_manutencao em aberto é do card 5.4.';

create table public.pc_manutencao (
  id               uuid primary key default gen_random_uuid(),
  unidade_id       uuid not null references public.unidade(id),
  pc_id            uuid not null references public.pc(id) on delete cascade,
  tipo             text not null check (tipo in ('PREVENTIVA','CORRETIVA','CONFIGURACAO')),
  data_inicio      date not null default public.fn_hoje(),
  data_fim         date,
  descricao        text,
  pc_substituto_id uuid references public.pc(id),
  criado_em        timestamptz not null default now(),
  criado_por       uuid,
  atualizado_em    timestamptz,
  atualizado_por   uuid,
  constraint pc_manutencao_periodo_ck    check (data_fim is null or data_fim >= data_inicio),
  constraint pc_manutencao_substituto_ck check (pc_substituto_id is distinct from pc_id)
);

-- `default public.fn_hoje()` e não `current_date`: o Postgres do Supabase roda
-- em UTC e das 21h à meia-noite `current_date` já é o dia seguinte (card 2.3
-- §3.3). É o ajuste não bloqueante nº 5 da lista do card 2.3, na parte que cabe
-- a este card; o teste C6 é o portão.
comment on table public.pc_manutencao is
  'Ocorrência de manutenção de um PC. Sem política de DELETE (card 2.4 §4): manutenção registrada é histórico, e é o que a guarda de exclusão da seção 9 impede de sumir junto com o PC.';
comment on column public.pc_manutencao.pc_substituto_id is
  'PC que assume a vaga enquanto este está parado. Sem substituto, a manutenção derruba a capacidade efetiva do bloco e pode abrir BLOCO_ACIMA_CAPACIDADE — regra do card 5.4.';

create table public.professor (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  nome           text not null,
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint professor_nome_uk unique (unidade_id, nome),
  constraint professor_nome_ck check (btrim(nome) <> '')
);

comment on table public.professor is
  'Professor do bloco de horário (card 5.1). Sem DELETE (card 2.4 §3.3): professor sai por ativo = false, senão a grade histórica perde o nome de quem deu a aula.';

-- Log de acesso à credencial (card 2.9 §6). Sem colunas próprias de "quem" e
-- "quando": `criado_por`/`criado_em` da auditoria padrão já são exatamente isso,
-- e duplicar convidaria as duas a divergirem.
create table public.pc_credencial_acesso (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  pc_id          uuid not null references public.pc(id) on delete cascade,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid
);

comment on table public.pc_credencial_acesso is
  'Uma linha por leitura de credencial. Imutável pela AUSÊNCIA de política de update e delete (card 2.4 (c) e card 4.2), como movimento_estoque e aluno_status_hist. Quem tem a permissão pode inserir uma linha que não aconteceu — ruído; o que importa está fechado: não há caminho que devolva a senha sem gravar a linha.';

-- -----------------------------------------------------------------------------
-- 3. Índices dos lados de FK que a unique não cobre
-- -----------------------------------------------------------------------------
-- Mesma razão dos cards 3.3 e 4.1: uma unique serve de índice para a FK só
-- quando a coluna é a PRIMEIRA dela. `pc_identificador_uk (unidade_id,
-- identificador)` não cobre `sala_id`, e `sala` TEM política de delete
-- (`salas.excluir`): sem o índice, apagar uma sala varre `pc` inteira para
-- verificar o RESTRICT. Os outros três lados são de FK sem unique nenhuma.
create index pc_sala_ix                  on public.pc                   (sala_id);
create index pc_manutencao_pc_ix         on public.pc_manutencao        (pc_id);
create index pc_manutencao_substituto_ix on public.pc_manutencao        (pc_substituto_id);
create index pc_credencial_acesso_pc_ix  on public.pc_credencial_acesso (pc_id);

-- A capacidade efetiva (card 5.2) conta PCs OPERACIONAIS de uma sala, e é
-- consulta de TELA — a grade semanal do card 5.6 a chama por bloco. Índice
-- parcial porque o predicado é sempre o mesmo e os outros dois status são a
-- minoria que não interessa à conta.
create index pc_sala_operacional_ix on public.pc (sala_id)
  where status = 'OPERACIONAL';

-- -----------------------------------------------------------------------------
-- 4. Triggers de auditoria (C3 do card 2.8)
-- -----------------------------------------------------------------------------
create trigger tg_auditoria_sala
  before insert or update on public.sala
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_pc
  before insert or update on public.pc
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_pc_manutencao
  before insert or update on public.pc_manutencao
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_professor
  before insert or update on public.professor
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_pc_credencial_acesso
  before insert or update on public.pc_credencial_acesso
  for each row execute function public.fn_auditoria();

-- -----------------------------------------------------------------------------
-- 5. RLS habilitada e forçada
-- -----------------------------------------------------------------------------
-- Políticas no MESMO arquivo que as tabelas, como no card 4.1: "Automatically
-- expose new tables" continua ligado nos dois projetos (pendência técnica 3),
-- então tabela sem política é uma API REST aberta pelo tempo que a tarefa
-- seguinte durar.
alter table public.sala                 enable row level security;
alter table public.sala                 force  row level security;
alter table public.pc                   enable row level security;
alter table public.pc                   force  row level security;
alter table public.pc_manutencao        enable row level security;
alter table public.pc_manutencao        force  row level security;
alter table public.professor            enable row level security;
alter table public.professor            force  row level security;
alter table public.pc_credencial_acesso enable row level security;
alter table public.pc_credencial_acesso force  row level security;

-- -----------------------------------------------------------------------------
-- 6. Políticas — docs/permissoes-matriz.md §4
-- -----------------------------------------------------------------------------
-- `salas.ler` e `professores.ler` são permissão dos QUATRO perfis, e não por
-- generosidade (card 2.4 §6): `v_bloco_vagas_semana` faz `left join` em
-- `professor` e, com `security_invoker`, quem não lê professor recebe a grade
-- SEM PROFESSOR — não quebra, mente. E a capacidade do card 5.2 conta PCs: sem
-- `salas.ler`, `fn_capacidade_efetiva` devolveria zero e a grade inteira
-- apareceria lotada — por isso ela também é `security definer` com filtro de
-- unidade no corpo (correção do card 2.3).

-- 6.1 sala e pc — cadastro (`salas.criar` / `salas.editar` / `salas.excluir`)
create policy sala_sel on public.sala for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('salas.ler'));

create policy sala_ins on public.sala for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('salas.criar'));

create policy sala_upd on public.sala for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('salas.editar'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('salas.editar'));

create policy sala_del on public.sala for delete to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('salas.excluir'));

create policy pc_sel on public.pc for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('salas.ler'));

create policy pc_ins on public.pc for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('salas.criar'));

create policy pc_upd on public.pc for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('salas.editar'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('salas.editar'));

create policy pc_del on public.pc for delete to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('salas.excluir'));

-- 6.2 pc_manutencao — abrir e fechar exigem `salas.registrar_manutencao`
-- Separado de `salas.editar` (card 2.4 §3.3) porque tem consequência que editar
-- não tem: manutenção sem substituto derruba a capacidade do bloco. E é a
-- permissão que o monitor tem sem ter as outras — quem vê o PC quebrado é quem
-- está no laboratório (confirmação de Irineu, card 3.6).
--
-- Sem política de DELETE: manutenção registrada é histórico.
create policy pc_manutencao_sel on public.pc_manutencao for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('salas.ler'));

create policy pc_manutencao_ins on public.pc_manutencao for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('salas.registrar_manutencao'));

create policy pc_manutencao_upd on public.pc_manutencao for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('salas.registrar_manutencao'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('salas.registrar_manutencao'));

-- 6.3 professor — sem DELETE (sai por ativo = false)
create policy professor_sel on public.professor for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('professores.ler'));

create policy professor_ins on public.professor for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('professores.criar'));

create policy professor_upd on public.professor for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('professores.editar'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('professores.editar'));

-- 6.4 pc_credencial_acesso — só select e insert, os dois por
--     `salas.acessar_credencial` (card 2.9 §6)
create policy pc_credencial_acesso_sel on public.pc_credencial_acesso
  for select to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('salas.acessar_credencial'));

-- O `insert` precisa ficar aberto a quem tem a permissão porque o log é gravado
-- por fn_pc_credencial_ler DENTRO da transação de quem lê, e a função é
-- `security definer` do `postgres`, que tem BYPASSRLS — mas o mesmo `insert`
-- fica alcançável pelo PostgREST. É o caso residual que o card 2.9 §6 aceita e
-- nomeia: forjar linha de acesso próprio é ruído, e o que não existe é caminho
-- que devolva a senha SEM gravar a linha.
create policy pc_credencial_acesso_ins on public.pc_credencial_acesso
  for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('salas.acessar_credencial'));

-- -----------------------------------------------------------------------------
-- 7. As duas funções de credencial (card 2.9 §4)
-- -----------------------------------------------------------------------------
-- `security definer` com `search_path` fixo, e por isso na lista fechada do
-- teste C8. Como `definer` de propriedade do `postgres` (que tem BYPASSRLS,
-- achado do card 3.3) elas ignoram a RLS de `pc` POR INTEIRO — então o filtro
-- `unidade_id = fn_unidade_atual()` vai NO CORPO das duas. É exatamente a lição
-- que o card 2.3 tirou de `fn_capacidade_efetiva`.
--
-- UMA permissão para ler e gravar, e não duas: quem grava a senha está digitando
-- a senha. Um `salas.gravar_credencial` separado descreveria uma proteção que
-- não existe.

-- 7.1 Gravar / rotacionar / limpar. p_senha nula apaga a credencial.
create or replace function public.fn_pc_credencial_gravar(
  p_pc_id   uuid,
  p_usuario text,
  p_senha   text
) returns void
language plpgsql
security definer
set search_path = public, vault, pg_temp
as $$
declare
  v_pc public.pc;
begin
  perform public.fn_exige_permissao('salas.acessar_credencial');

  select * into v_pc
    from public.pc
   where id = p_pc_id and unidade_id = public.fn_unidade_atual()
   for update;

  if not found then
    raise exception using
      errcode = 'PT404',
      message = 'Este computador não foi encontrado.',
      detail  = json_build_object('codigo', 'PC_INEXISTENTE', 'pc', p_pc_id)::text;
  end if;

  -- Limpar: apaga o segredo E o ponteiro. Deixar o segredo no Vault com o
  -- ponteiro nulo seria uma senha viva que ninguém mais alcança nem apaga.
  if p_senha is null then
    if v_pc.credencial_secret_id is not null then
      delete from vault.secrets where id = v_pc.credencial_secret_id;
    end if;

    update public.pc
       set credencial_secret_id = null,
           credencial_em        = null,
           credencial_por       = null
     where id = p_pc_id;
    return;
  end if;

  if v_pc.credencial_secret_id is null then
    update public.pc
       set credencial_secret_id = vault.create_secret(
             json_build_object('usuario', p_usuario, 'senha', p_senha)::text,
             null,
             'credencial do PC ' || v_pc.identificador),
           credencial_em  = now(),
           credencial_por = auth.uid()
     where id = p_pc_id;
  else
    perform vault.update_secret(
      v_pc.credencial_secret_id,
      json_build_object('usuario', p_usuario, 'senha', p_senha)::text);

    update public.pc
       set credencial_em  = now(),
           credencial_por = auth.uid()
     where id = p_pc_id;
  end if;
end $$;

comment on function public.fn_pc_credencial_gravar(uuid, text, text) is
  'Grava, rotaciona ou limpa (p_senha nula) a credencial do PC no Vault. Exige salas.acessar_credencial e filtra a unidade no corpo. O par {usuario, senha} é UM segredo: nada em claro fica em public.pc (card 2.9 §3).';

-- 7.2 Ler. Registra o acesso ANTES de devolver.
create or replace function public.fn_pc_credencial_ler(p_pc_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, vault, pg_temp
as $$
declare
  v_pc      public.pc;
  v_segredo text;
begin
  perform public.fn_exige_permissao('salas.acessar_credencial');

  select * into v_pc
    from public.pc
   where id = p_pc_id and unidade_id = public.fn_unidade_atual();

  -- PC de outra unidade responde o MESMO que PC inexistente, de propósito: quem
  -- não pode ver não descobre que existe (card 2.9 §4).
  if not found then
    raise exception using
      errcode = 'PT404',
      message = 'Este computador não foi encontrado.',
      detail  = json_build_object('codigo', 'PC_INEXISTENTE', 'pc', p_pc_id)::text;
  end if;

  if v_pc.credencial_secret_id is null then
    return null;
  end if;

  -- Log como PRÉ-CONDIÇÃO da leitura, não efeito colateral: mesma transação e
  -- SEM `exception` em volta. Registro que falha derruba a leitura. Com três
  -- pessoas autorizadas, é o único controle que sobra (card 2.9 §1.4).
  insert into public.pc_credencial_acesso (unidade_id, pc_id)
  values (v_pc.unidade_id, v_pc.id);

  select decrypted_secret into v_segredo
    from vault.decrypted_secrets
   where id = v_pc.credencial_secret_id;

  return v_segredo::jsonb;
end $$;

comment on function public.fn_pc_credencial_ler(uuid) is
  'Devolve {usuario, senha} do PC, gravando a linha em pc_credencial_acesso ANTES de retornar, na mesma transação e sem exception: não há caminho que devolva a senha sem registrar quem leu (card 2.9 §1.4).';

-- C9 (card 2.8): nada de EXECUTE para public/anon. `create function` concede a
-- PUBLIC por padrão, e sem o revoke a credencial ficaria a uma chamada anônima
-- de distância — a função confere a permissão, mas `anon` não deve nem alcançar
-- a porta.
revoke execute on function public.fn_pc_credencial_gravar(uuid, text, text) from public;
revoke execute on function public.fn_pc_credencial_gravar(uuid, text, text) from anon;
grant  execute on function public.fn_pc_credencial_gravar(uuid, text, text) to authenticated;

revoke execute on function public.fn_pc_credencial_ler(uuid) from public;
revoke execute on function public.fn_pc_credencial_ler(uuid) from anon;
grant  execute on function public.fn_pc_credencial_ler(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 8. PC apagado não deixa segredo órfão no Vault (card 2.9 §7)
-- -----------------------------------------------------------------------------
-- Nome divergente do documento, e a divergência é de propósito: o card 2.9 §7
-- batiza a FUNÇÃO de `tg_pc_credencial_apaga`, e neste projeto `tg_` é o
-- prefixo do TRIGGER e `fn_` o da função (cards 2.2 §16 e 4.2). Duas convenções
-- vivas no mesmo schema é o tipo de coisa que ninguém encontra porque as duas
-- linhas parecem certas.
create or replace function public.fn_pc_credencial_apagar()
returns trigger
language plpgsql
security definer
set search_path = public, vault, pg_temp
as $$
begin
  if old.credencial_secret_id is not null then
    delete from vault.secrets where id = old.credencial_secret_id;
  end if;
  return old;
end $$;

comment on function public.fn_pc_credencial_apagar() is
  'Trigger BEFORE DELETE em pc: apaga o segredo do Vault junto com o PC. Sem ela, o par {usuario, senha} sobreviveria ao PC sem ponteiro nenhum — senha viva que ninguém alcança para apagar.';

revoke execute on function public.fn_pc_credencial_apagar() from public;
revoke execute on function public.fn_pc_credencial_apagar() from anon;

create trigger tg_pc_credencial_apaga
  before delete on public.pc
  for each row execute function public.fn_pc_credencial_apagar();

-- -----------------------------------------------------------------------------
-- 9. "Excluir PC sem histórico" deixa de ser intenção e vira estrutura
-- -----------------------------------------------------------------------------
-- O catálogo do card 2.4 descreve `salas.excluir` como "excluir sala/PC SEM
-- HISTÓRICO", e o §6 do card 2.9 escreve que `pc_credencial_acesso` é imutável
-- — nem update nem delete, para ninguém. Nada no schema fazia as duas coisas
-- valerem: `pc_manutencao.pc_id` e `pc_credencial_acesso.pc_id` são
-- `on delete cascade`, e a ação em cascata de uma FK NÃO passa pela RLS da
-- tabela referenciadora (medido na bancada deste card). Ou seja, um `delete
-- from pc` da direção levava junto, em silêncio, a manutenção registrada e o
-- log de quem leu a senha — apagando exatamente a prova que o card 2.9 elegeu
-- como único controle sobrevivente.
--
-- É a mesma família de `tg_aluno_status_hist_coerente` (card 4.2): onde a
-- ausência de política EXPRESSA uma decisão, um caminho que a contorna sem erro
-- é pior do que a decisão não existir, porque o histórico continua parecendo
-- completo.
--
-- A guarda não fecha a exclusão, fecha a exclusão COM histórico: PC digitado
-- errado, sem manutenção e sem leitura de credencial, continua apagável — é o
-- que mantém `salas.excluir` com um uso real. PC que já rodou sai por
-- `status = 'DESATIVADO'`.
create or replace function public.fn_pc_exclusao_valida()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_manutencoes bigint;
  v_acessos     bigint;
  v_substituto  bigint;
begin
  select count(*) into v_manutencoes from public.pc_manutencao        where pc_id = old.id;
  select count(*) into v_acessos     from public.pc_credencial_acesso where pc_id = old.id;
  select count(*) into v_substituto  from public.pc_manutencao        where pc_substituto_id = old.id;

  if v_manutencoes + v_acessos + v_substituto > 0 then
    raise exception using
      errcode = 'PT409',
      message = 'Este computador tem histórico e não pode ser excluído. Marque-o como desativado.',
      detail  = json_build_object('codigo', 'PC_COM_HISTORICO',
                                  'pc', old.id,
                                  'manutencoes', v_manutencoes,
                                  'acessos_credencial', v_acessos,
                                  'substituicoes', v_substituto)::text;
  end if;

  return old;
end $$;

-- `security invoker` (o default), ao contrário das três funções acima: ela não
-- precisa contornar RLS nenhuma para contar linhas de duas tabelas que o próprio
-- chamador está autorizado a ler — quem tem `salas.excluir` tem `salas.ler`. E
-- entrar na lista fechada do C8 sem necessidade gasta a revisão consciente que
-- a lista existe para provocar (card 3.4 (a)).
--
-- ⚠️ Consequência assumida: quem NÃO tem `salas.acessar_credencial` não enxerga
-- pc_credencial_acesso pela RLS, então para essa pessoa a contagem de acessos é
-- zero e a guarda pode deixar passar um PC cujo único histórico é uma leitura de
-- credencial. Não é buraco de segurança (o `delete` continua exigindo
-- `salas.excluir`, que só a direção tem, e a direção tem as duas permissões na
-- matriz inicial): é uma guarda que enxerga o que o chamador enxerga. Torná-la
-- `definer` compraria o caso residual ao preço de mais uma função ignorando a
-- RLS inteira — troca ruim, registrada aqui em vez de decidida em silêncio.
comment on function public.fn_pc_exclusao_valida() is
  'Trigger BEFORE DELETE em pc: recusa (PT409 / PC_COM_HISTORICO) apagar PC com manutenção, leitura de credencial ou papel de substituto. Faz valer o "sem histórico" do card 2.4 §3.3, que a cascata das FKs contornava sem erro.';

revoke execute on function public.fn_pc_exclusao_valida() from public;
revoke execute on function public.fn_pc_exclusao_valida() from anon;
grant  execute on function public.fn_pc_exclusao_valida() to authenticated;

-- Os dois triggers BEFORE DELETE de `pc` disparam em ordem alfabética de nome,
-- então `tg_pc_credencial_apaga` vem antes desta guarda. Não há o que corrigir:
-- o `raise` aborta a transação, e o `delete from vault.secrets` volta atrás
-- junto. Ordem alfabética só importaria se a limpeza do Vault fosse fora de
-- transação — e não é.
create trigger tg_pc_exclusao_valida
  before delete on public.pc
  for each row execute function public.fn_pc_exclusao_valida();
