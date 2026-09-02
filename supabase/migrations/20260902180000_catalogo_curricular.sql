-- =============================================================================
-- Card 4.1 — Schema: catálogo curricular
-- Fonte: docs/modelagem-dados-ddl.md §6 (§5.2 do plano),
--        docs/permissoes-matriz.md §4 (políticas) e §3.3 (domínio `materiais`).
--
-- Entrega: metodo, material, curso, curso_material, modulo, combo, combo_curso
--          + triggers de auditoria + RLS habilitada, FORÇADA e com as políticas
--          do card 2.4 §4 + as TRÊS linhas de `metodo`.
--
-- ⚠️ ESTRUTURA E MAIS NADA, com uma exceção deliberada.
--    Decisão de 02/09/2026 (Irineu): dado de negócio vindo da planilha fica
--    restrito ao ambiente dev/homolog até a virada do card 9.7. Migração é o que
--    o CI empurra para produção SOZINHO no merge em `main`, e a planilha muda
--    todo dia. Então `material`, `curso`, `curso_material`, `modulo`, `combo` e
--    `combo_curso` nascem VAZIAS: o catálogo real vem pelo importador do card
--    9.1, carregado só no projeto dev, e alcança produção uma única vez no 9.7.
--
--    A exceção é `metodo`: as três linhas (INTERATIVO, INGLES, MODULAR) são
--    CONFIGURAÇÃO, não dado de planilha — enumeração fixa do produto, já
--    referenciada pelos parâmetros `ritmo_padrao_dias_*` do seed do card 3.6 e
--    escrita no `check` da própria coluna. Sem elas nenhuma outra tabela deste
--    arquivo aceita uma linha, porque todas penduram em `metodo`.
--
--    O portão do card 4.0,5 (`portao-migracoes/varredor.mjs`) tem `metodo` na
--    lista permitida e as outras seis fora dela: uma carga escrita aqui reprova
--    o CI, inclusive se vier disfarçada dentro de função chamada pela migração.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Tabelas (§6 do DDL)
-- -----------------------------------------------------------------------------
create table public.metodo (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  codigo         text not null check (codigo in ('INTERATIVO','INGLES','MODULAR')),
  nome           text not null,
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint metodo_codigo_uk unique (unidade_id, codigo)
);

comment on table public.metodo is
  'Os três métodos de ensino da escola. Enumeração FIXA do produto (check na coluna), não catálogo da planilha: as três linhas vêm nesta migração, por fn_seed_metodos (card 4.1).';
comment on column public.metodo.codigo is
  'Chave natural estável. O check é o que impede um quarto método de nascer pela tela: os parâmetros ritmo_padrao_dias_<METODO> do seed do card 3.6 e a cascata da projeção (card de Ordem 5) são escritos sobre estes três valores.';

create table public.material (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  metodo_id      uuid not null references public.metodo(id),
  codigo         text not null,
  nome           text not null,
  categoria      text not null,
  estoque_minimo integer not null default 0 check (estoque_minimo >= 0),
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  -- Código de material é único POR MÉTODO, não por unidade: os três catálogos da
  -- planilha reaproveitam a mesma numeração, e uma unique por (unidade, codigo)
  -- recusaria o segundo método na importação do card 9.1 — com erro de chave
  -- duplicada, que ninguém liga a uma decisão de modelagem.
  constraint material_codigo_uk unique (unidade_id, metodo_id, codigo)
);

comment on table public.material is
  'Apostila/livro. VAZIA em produção até a virada do card 9.7: o catálogo real entra pelo importador do card 9.1, no ambiente dev.';
comment on column public.material.estoque_minimo is
  'Piso que entra no pedido sugerido (card 2.3, v_pedido_sugerido). Origem dos valores iniciais: ajustes manuais da aba Pedidos da planilha.';

create table public.curso (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  metodo_id      uuid not null references public.metodo(id),
  nome           text not null,
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint curso_nome_uk unique (unidade_id, metodo_id, nome)
);

-- Sequência padrão de apostilas do curso. O número de apostilas é livre — o
-- plano é explícito em não fixar 17 (decisão de 30/08/2026).
create table public.curso_material (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  curso_id       uuid not null references public.curso(id) on delete cascade,
  material_id    uuid not null references public.material(id),
  ordem          integer not null check (ordem > 0),
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint curso_material_uk       unique (curso_id, material_id),
  constraint curso_material_ordem_uk unique (curso_id, ordem) deferrable initially deferred
);

comment on constraint curso_material_ordem_uk on public.curso_material is
  'DEFERRABLE INITIALLY DEFERRED de propósito (card 2.1 (e)): reordenar a sequência é UM update que troca as ordens entre si, e a checagem no fim da transação é o que dispensa passar por valores temporários. Sem o deferrable, a mesma tela precisaria de duas escritas e um estado inválido no meio.';

-- Modular: o curso tem um livro, e o livro se divide em módulos; a turma avança
-- pelos módulos em conjunto (decisão de 31/08/2026, `Ger. Modular` é a fonte).
create table public.modulo (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  curso_id       uuid not null references public.curso(id) on delete cascade,
  material_id    uuid not null references public.material(id),
  nome           text not null,
  ordem          integer not null check (ordem > 0),
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint modulo_ordem_uk unique (curso_id, ordem) deferrable initially deferred
);

comment on table public.modulo is
  'Módulos do curso Modular. Vários módulos podem apontar para o MESMO material: no Modular o livro é único e o que avança é o módulo (card 7.2).';

create table public.combo (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  metodo_id      uuid not null references public.metodo(id),
  nome           text not null,
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint combo_nome_uk unique (unidade_id, nome)
);

comment on table public.combo is
  'O que o aluno compra. combo → curso → material é a cadeia que gera a trilha na matrícula (card 6.2, decisão 3 de 30/08/2026).';

create table public.combo_curso (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  combo_id       uuid not null references public.combo(id) on delete cascade,
  curso_id       uuid not null references public.curso(id),
  ordem          integer not null check (ordem > 0),
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint combo_curso_uk       unique (combo_id, curso_id),
  constraint combo_curso_ordem_uk unique (combo_id, ordem) deferrable initially deferred
);

-- -----------------------------------------------------------------------------
-- 2. Índices dos lados que a unique não cobre
-- -----------------------------------------------------------------------------
-- Mesma razão do card 3.3: uma unique serve de índice para a FK só quando a
-- coluna é a PRIMEIRA dela. `curso_material_uk (curso_id, material_id)` cobre
-- `curso_id` e não cobre `material_id`; `modulo_ordem_uk (curso_id, ordem)`
-- cobre `curso_id` e não cobre `material_id`; `combo_curso_uk (combo_id,
-- curso_id)` cobre `combo_id` e não cobre `curso_id`. Sem estes índices, apagar
-- um material (que TEM política de delete, `materiais.excluir`) faz o Postgres
-- varrer as tabelas referenciadoras para verificar o RESTRICT.
create index material_metodo_ix         on public.material       (metodo_id);
create index curso_metodo_ix            on public.curso          (metodo_id);
create index combo_metodo_ix            on public.combo          (metodo_id);
create index curso_material_material_ix on public.curso_material (material_id);
create index modulo_material_ix         on public.modulo         (material_id);
create index combo_curso_curso_ix       on public.combo_curso    (curso_id);

-- -----------------------------------------------------------------------------
-- 3. Triggers de auditoria (C3 do card 2.8)
-- -----------------------------------------------------------------------------
create trigger tg_auditoria_metodo
  before insert or update on public.metodo
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_material
  before insert or update on public.material
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_curso
  before insert or update on public.curso
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_curso_material
  before insert or update on public.curso_material
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_modulo
  before insert or update on public.modulo
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_combo
  before insert or update on public.combo
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_combo_curso
  before insert or update on public.combo_curso
  for each row execute function public.fn_auditoria();

-- -----------------------------------------------------------------------------
-- 4. RLS habilitada e forçada
-- -----------------------------------------------------------------------------
-- Diferente do card 3.3, as políticas vêm no MESMO arquivo: lá elas dependiam de
-- funções que ainda não existiam (fn_unidade_atual, tem_permissao) e a janela
-- entre os dois merges foi aceita de propósito. Aqui não há o que esperar, e
-- tabela publicada no PostgREST sem política é uma API aberta pelo tempo que a
-- tarefa seguinte durar ("Automatically expose new tables" continua ligado nos
-- dois projetos — pendência técnica 3 das Decisões vigentes).
alter table public.metodo         enable row level security;
alter table public.metodo         force  row level security;
alter table public.material       enable row level security;
alter table public.material       force  row level security;
alter table public.curso          enable row level security;
alter table public.curso          force  row level security;
alter table public.curso_material enable row level security;
alter table public.curso_material force  row level security;
alter table public.modulo         enable row level security;
alter table public.modulo         force  row level security;
alter table public.combo          enable row level security;
alter table public.combo          force  row level security;
alter table public.combo_curso    enable row level security;
alter table public.combo_curso    force  row level security;

-- -----------------------------------------------------------------------------
-- 5. Políticas — docs/permissoes-matriz.md §4
-- -----------------------------------------------------------------------------
-- `materiais.ler` é permissão de TODOS os quatro perfis, e não por generosidade
-- (card 2.4): cinco das dez views do card 2.3 fazem join INTERNO em
-- metodo/curso/modulo e, com `security_invoker`, quem não lê o catálogo recebe
-- ZERO LINHAS — a grade semanal e o dashboard aparecem vazios, não errados.
--
-- `metodo` é a única tabela deste arquivo sem delete: as três linhas são
-- enumeração do produto, e apagá-las levaria junto todo o catálogo pendurado
-- nelas. Fora de uso é `ativo = false`.

-- 5.1 metodo
create policy metodo_sel on public.metodo for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('materiais.ler'));

create policy metodo_ins on public.metodo for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.criar'));

create policy metodo_upd on public.metodo for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.editar'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.editar'));

-- 5.2 material
create policy material_sel on public.material for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('materiais.ler'));

create policy material_ins on public.material for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.criar'));

create policy material_upd on public.material for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.editar'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.editar'));

create policy material_del on public.material for delete to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('materiais.excluir'));

-- 5.3 curso
create policy curso_sel on public.curso for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('materiais.ler'));

create policy curso_ins on public.curso for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.criar'));

create policy curso_upd on public.curso for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.editar'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.editar'));

create policy curso_del on public.curso for delete to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('materiais.excluir'));

-- 5.4 curso_material — composição, não cadastro
-- `insert` exige `materiais.editar` e não `materiais.criar` (card 2.4 §4):
-- montar a sequência de um curso é editar o curso, não criar cadastro novo.
create policy curso_material_sel on public.curso_material for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('materiais.ler'));

create policy curso_material_ins on public.curso_material for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.editar'));

create policy curso_material_upd on public.curso_material for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.editar'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.editar'));

create policy curso_material_del on public.curso_material for delete to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('materiais.excluir'));

-- 5.5 modulo
create policy modulo_sel on public.modulo for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('materiais.ler'));

create policy modulo_ins on public.modulo for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.criar'));

create policy modulo_upd on public.modulo for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.editar'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.editar'));

create policy modulo_del on public.modulo for delete to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('materiais.excluir'));

-- 5.6 combo
create policy combo_sel on public.combo for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('materiais.ler'));

create policy combo_ins on public.combo for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.criar'));

create policy combo_upd on public.combo for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.editar'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.editar'));

create policy combo_del on public.combo for delete to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('materiais.excluir'));

-- 5.7 combo_curso — composição, mesma razão de curso_material
create policy combo_curso_sel on public.combo_curso for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('materiais.ler'));

create policy combo_curso_ins on public.combo_curso for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.editar'));

create policy combo_curso_upd on public.combo_curso for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.editar'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('materiais.editar'));

create policy combo_curso_del on public.combo_curso for delete to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('materiais.excluir'));

-- -----------------------------------------------------------------------------
-- 6. As três linhas de `metodo` — configuração, exposta como função
-- -----------------------------------------------------------------------------
-- Função em vez de `insert` solto pela mesma razão do card 3.6: a escola-fixture
-- do card 3.4.5 precisa dos MESMOS três métodos nas suas duas unidades, e um
-- conjunto escrito à parte no `seed.sql` seria uma segunda fonte da verdade,
-- livre para divergir da real sem que nada acuse. Migração e fixture chamam o
-- mesmo código.
--
-- Idempotência `do nothing`, e não `do update`: a matriz do card 2.4 dá
-- `materiais.editar` sobre `metodo`, então o nome é editável na tela (card 4.4).
-- Com `do update`, uma correção feita lá voltaria ao valor da migração no deploy
-- seguinte — sem erro, sem log, e sem ninguém ligar uma coisa à outra, que é
-- exatamente a falha que o card 3.6 corrigiu no contrato do seed. O `codigo`
-- não corre esse risco: ele é a chave natural e está fechado no `check`.
create or replace function public.fn_seed_metodos(p_unidade_id uuid)
returns integer
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_n integer;
begin
  insert into public.metodo (unidade_id, codigo, nome)
  select p_unidade_id, m.codigo, m.nome
    from (values
      ('INTERATIVO', 'Interativo'),
      ('INGLES',     'Inglês'),
      ('MODULAR',    'Modular')
    ) as m(codigo, nome)
  on conflict (unidade_id, codigo) do nothing;

  get diagnostics v_n = row_count;
  return v_n;
end $$;

comment on function public.fn_seed_metodos(uuid) is
  'Os três métodos de ensino de uma unidade. Idempotente (do nothing: o nome é editável na tela do card 4.4). Chamada pela migração do card 4.1 para a unidade real e pelo supabase/seed.sql para as duas unidades da fixture — uma fonte só.';

-- C9 (card 2.8): função de seed não é botão de tela nenhuma. `create function`
-- concede EXECUTE a PUBLIC por padrão.
revoke execute on function public.fn_seed_metodos(uuid) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 7. Aplicação na unidade real
-- -----------------------------------------------------------------------------
-- `codigo = 'MATRIZ'` é a chave natural criada pelo card 3.3 exatamente para
-- isto: `nome` é editável por quem tem `unidades.gerir`.
--
-- Nenhum `select` de `metodo` acontece aqui, e nenhuma outra tabela é tocada: o
-- catálogo (material, curso, módulo, combo) é dado da planilha e entra pelo
-- importador do card 9.1, no ambiente dev.
do $$
declare
  v_unidade uuid;
begin
  select id into v_unidade from public.unidade where codigo = 'MATRIZ';

  -- Sem `codigo` no DETAIL, de propósito: o catálogo de erros do card 2.2 §1.2 é
  -- o contrato entre o banco e o Flutter (`test/fixtures/codigos_erro.txt`, 25
  -- códigos), e este erro não chega a tela nenhuma — ele para o `db push` do CI,
  -- que é onde precisa ser lido. Inventar um 26º código aqui gastaria o contrato
  -- com quem não o consome.
  if v_unidade is null then
    raise exception 'unidade MATRIZ inexistente: a migração do card 3.6 precisa ter rodado antes desta';
  end if;

  perform public.fn_seed_metodos(v_unidade);
end $$;
