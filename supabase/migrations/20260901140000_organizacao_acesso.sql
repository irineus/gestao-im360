-- =============================================================================
-- Card 3.3 — Primeira migration: organização e acesso
-- Fonte: docs/modelagem-dados-ddl.md §3 (infraestrutura comum) e §5 (§5.1 do plano)
--
-- Entrega: fn_auditoria + unidade, usuario, perfil, permissao, perfil_permissao,
--          usuario_perfil, parametro + triggers de auditoria + RLS habilitada e
--          FORÇADA nas sete tabelas.
--
-- As POLÍTICAS de RLS são do card 3.4, junto com fn_unidade_atual() e
-- tem_permissao(), das quais dependem. Até lá estas tabelas ficam com RLS ligada
-- e NENHUMA política — ou seja, sem acesso para anon e authenticated. Isso é
-- deliberado: "Automatically expose new tables" está ligado nos dois projetos
-- Supabase (pendência técnica 3 das Decisões vigentes), então tabela criada sem
-- RLS é uma API aberta durante toda a janela entre o merge desta migração e o da
-- 3.4. Falhar fechado é a única opção segura nessa janela.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Carimbo de auditoria — um único trigger para todas as tabelas
-- -----------------------------------------------------------------------------
-- Não é security definer: só mexe em NEW/OLD da linha que o chamador já está
-- gravando. search_path fixo por exigência do teste de catálogo C7 (card 2.8).
create or replace function public.fn_auditoria()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if (tg_op = 'INSERT') then
    new.criado_em      := now();
    new.criado_por     := auth.uid();
    new.atualizado_em  := null;
    new.atualizado_por := null;
  elsif (tg_op = 'UPDATE') then
    new.criado_em      := old.criado_em;   -- imutáveis
    new.criado_por     := old.criado_por;
    new.atualizado_em  := now();
    new.atualizado_por := auth.uid();
  end if;
  return new;
end;
$$;

comment on function public.fn_auditoria() is
  'Preenche criado_em/por e atualizado_em/por. Aplicada por trigger em toda tabela de negócio (card 3.3).';

-- C9 (card 2.8): nenhuma função com execute para public ou anon. Trigger não
-- exige o privilégio em tempo de execução — o Postgres o verifica em CREATE TRIGGER.
revoke execute on function public.fn_auditoria() from public;
revoke execute on function public.fn_auditoria() from anon;
revoke execute on function public.fn_auditoria() from authenticated;

-- -----------------------------------------------------------------------------
-- 2. Tabelas (§5 do DDL)
-- -----------------------------------------------------------------------------
create table public.unidade (
  id             uuid primary key default gen_random_uuid(),
  codigo         text not null,
  nome           text not null,
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint unidade_codigo_uk unique (codigo),
  constraint unidade_nome_uk   unique (nome)
);

comment on table public.unidade is
  'Unidade da escola. Única tabela sem unidade_id — ela é a unidade (card 3.3).';
comment on column public.unidade.codigo is
  'Chave natural estável para o seed do card 3.6 e para a fixture do card 3.4.5 (ex.: ESCOLA_A). nome é editável na tela de Administração e não serve de chave de idempotência.';

create table public.usuario (
  id             uuid primary key references auth.users(id) on delete restrict,
  unidade_id     uuid not null references public.unidade(id),
  nome           text not null,
  email          text not null,
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint usuario_email_uk unique (email)
);

comment on table public.usuario is
  'Espelho de auth.users. Populado por trigger em auth.users (card 3.5).';

create table public.perfil (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  codigo         text not null,          -- DIRECAO, PEDAGOGICO, SECRETARIA, MONITOR
  nome           text not null,
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint perfil_codigo_uk unique (unidade_id, codigo)
);

create table public.permissao (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  codigo         text not null,          -- <dominio>.<acao>, ex.: estoque.lancar_saida
  descricao      text not null,
  dominio        text not null,          -- domínio no PLURAL, ex.: alunos, estoque, turmas
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint permissao_codigo_uk unique (unidade_id, codigo)
);

comment on table public.permissao is
  'Catálogo de permissões. Só muda por migração: um código novo só serve depois que alguma política, função ou rota passa a exigi-lo, e isso é código, não dado (card 2.4 (e)). Por isso não recebe política de escrita no card 3.4.';
comment on column public.permissao.dominio is
  'Domínio no PLURAL (alunos, turmas, materiais, estoque, compras, certificados, pendencias, salas, professores, admin, unidades, parametros) — card 2.4, que fecha o ajuste #7 do card 2.3.';

create table public.perfil_permissao (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  perfil_id      uuid not null references public.perfil(id) on delete cascade,
  permissao_id   uuid not null references public.permissao(id) on delete cascade,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint perfil_permissao_uk unique (perfil_id, permissao_id)
);

create table public.usuario_perfil (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  usuario_id     uuid not null references public.usuario(id) on delete cascade,
  perfil_id      uuid not null references public.perfil(id),
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint usuario_perfil_uk unique (usuario_id, perfil_id)
);

create table public.parametro (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  chave          text not null,
  valor          text not null,
  tipo           text not null default 'TEXTO'
                 check (tipo in ('TEXTO','INTEIRO','DECIMAL','BOOLEANO','DATA')),
  descricao      text,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint parametro_chave_uk unique (unidade_id, chave)
);

comment on table public.parametro is
  'Parâmetros por unidade. Parâmetro ausente é erro PARAMETRO_AUSENTE (card 2.2): não há default escondido no código. Seed no card 3.6.';

-- Índice do lado que a unique não cobre: perfil_permissao_uk é (perfil_id,
-- permissao_id), então o delete em cascata de permissao faria varredura.
create index perfil_permissao_permissao_ix on public.perfil_permissao (permissao_id);
create index usuario_perfil_perfil_ix       on public.usuario_perfil (perfil_id);

-- -----------------------------------------------------------------------------
-- 3. Triggers de auditoria (C3 do card 2.8)
-- -----------------------------------------------------------------------------
create trigger tg_auditoria_unidade
  before insert or update on public.unidade
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_usuario
  before insert or update on public.usuario
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_perfil
  before insert or update on public.perfil
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_permissao
  before insert or update on public.permissao
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_perfil_permissao
  before insert or update on public.perfil_permissao
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_usuario_perfil
  before insert or update on public.usuario_perfil
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_parametro
  before insert or update on public.parametro
  for each row execute function public.fn_auditoria();

-- -----------------------------------------------------------------------------
-- 4. RLS habilitada e forçada, sem política nenhuma (C1 do card 2.8)
--    As políticas entram no card 3.4. Sem política = sem acesso.
-- -----------------------------------------------------------------------------
alter table public.unidade          enable row level security;
alter table public.unidade          force  row level security;
alter table public.usuario          enable row level security;
alter table public.usuario          force  row level security;
alter table public.perfil           enable row level security;
alter table public.perfil           force  row level security;
alter table public.permissao        enable row level security;
alter table public.permissao        force  row level security;
alter table public.perfil_permissao enable row level security;
alter table public.perfil_permissao force  row level security;
alter table public.usuario_perfil   enable row level security;
alter table public.usuario_perfil   force  row level security;
alter table public.parametro        enable row level security;
alter table public.parametro        force  row level security;
