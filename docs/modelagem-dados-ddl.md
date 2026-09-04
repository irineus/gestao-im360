# Modelagem de dados detalhada — DDL Postgres

Card de origem: **2.1 — Modelagem de dados detalhada (DDL Postgres)** (Fase 2, board Notion).
Base: `docs/plano-projeto-sistema.md` seções 5.1–5.8 e 6, mais as decisões de 31/08/2026 na página Decisões vigentes.

Este documento é a **fonte do DDL**. Os cards das fases 3 a 8 recortam daqui os arquivos de
`supabase/migrations/`, um por card (ver §11, mapa DDL → card). Nada aqui é aplicado manualmente:
migração entra como arquivo novo, `develop` aplica no dev, `main` aplica no prod.

---

## 1. Convenções obrigatórias

| Convenção | Regra |
|---|---|
| Nomes | português, `snake_case`, singular nas tabelas (`aluno`, não `alunos`) |
| Chave primária | `id uuid primary key default gen_random_uuid()` |
| Multi-unidade | `unidade_id uuid not null references unidade(id)` em **toda** tabela de negócio |
| Auditoria | `criado_em timestamptz not null default now()`, `criado_por uuid`, `atualizado_em timestamptz`, `atualizado_por uuid` |
| Conjuntos fechados | `text` + `CHECK (col IN (...))` — **não** usar `ENUM` (ver §2) |
| Datas | `date` para datas de negócio; `timestamptz` para carimbos de auditoria e eventos |
| RLS | habilitada e forçada em toda tabela, sem exceção (§4) |
| Quantidades | `integer` para quantidades de apostila; nunca `float` |

Tabelas puramente associativas (`curso_material`, `combo_curso`, `perfil_permissao`, ...) também
carregam `unidade_id` e auditoria: simplifica a RLS (uma política só) e o custo é irrelevante.

## 2. Decisão: `text` + `CHECK` em vez de `ENUM`

Migrações rodam via `supabase db push` no CI, dentro de transação. `ALTER TYPE ... ADD VALUE` tem
restrições de uso em transação e o valor novo não pode ser usado na mesma transação em que foi
criado — o que quebraria uma migração que adiciona um status e já o utiliza num backfill.
`text` + `CHECK` é alterável com `ALTER TABLE ... DROP CONSTRAINT / ADD CONSTRAINT` no mesmo
arquivo, sem armadilha. Perde-se um pouco de tipagem; ganha-se migração previsível.

Convenção: valores sempre em MAIÚSCULAS, sem acento (`ATIVO`, `NAO_PEDIDO`).

## 3. Infraestrutura comum (Fase 3)

```sql
-- Carimbo de auditoria. Um único trigger para todas as tabelas.
create or replace function public.fn_auditoria()
returns trigger
language plpgsql
as $$
begin
  if (tg_op = 'INSERT') then
    new.criado_em  := now();
    new.criado_por := auth.uid();
    new.atualizado_em  := null;
    new.atualizado_por := null;
  elsif (tg_op = 'UPDATE') then
    new.criado_em  := old.criado_em;   -- imutáveis
    new.criado_por := old.criado_por;
    new.atualizado_em  := now();
    new.atualizado_por := auth.uid();
  end if;
  return new;
end;
$$;

-- Aplicada em toda tabela de negócio:
--   create trigger tg_auditoria_<tabela> before insert or update on public.<tabela>
--     for each row execute function public.fn_auditoria();

-- Unidade do usuário autenticado. SECURITY DEFINER para não recursar na RLS de usuario.
create or replace function public.fn_unidade_atual()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select u.unidade_id from public.usuario u where u.id = auth.uid() and u.ativo;
$$;

-- Verificação de permissão. O código NUNCA verifica perfil, sempre permissão.
create or replace function public.tem_permissao(p_codigo text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from public.usuario_perfil up
      join public.perfil_permissao pp on pp.perfil_id = up.perfil_id
      join public.permissao p on p.id = pp.permissao_id
     where up.usuario_id = auth.uid()
       and p.codigo = p_codigo
       and p.ativo
  );
$$;

revoke execute on function public.tem_permissao(text) from public;
grant  execute on function public.tem_permissao(text) to authenticated;
-- idem para fn_unidade_atual()
```

`security definer` é o que evita recursão infinita: `tem_permissao` lê `usuario_perfil`, que por sua
vez tem RLS que chamaria `tem_permissao`. Rodando como owner, a leitura interna ignora RLS.

## 4. Padrão de RLS

Toda tabela recebe:

```sql
alter table public.<tabela> enable row level security;
alter table public.<tabela> force  row level security;

create policy <tabela>_sel on public.<tabela> for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('<dominio>.ler'));

create policy <tabela>_ins on public.<tabela> for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual() and public.tem_permissao('<dominio>.criar'));

create policy <tabela>_upd on public.<tabela> for update to authenticated
  using      (unidade_id = public.fn_unidade_atual() and public.tem_permissao('<dominio>.editar'))
  with check (unidade_id = public.fn_unidade_atual() and public.tem_permissao('<dominio>.editar'));

create policy <tabela>_del on public.<tabela> for delete to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('<dominio>.excluir'));
```

Regras derivadas:

- **Sem política = sem acesso.** `movimento_estoque` não tem política de `update` nem `delete`;
  é assim que a imutabilidade vira estrutura, não só trigger.
- O catálogo de `<dominio>.<acao>` é do card **2.4** (matriz de permissões). Aqui só se fixa o formato.
- `force row level security` garante que nem o dono da tabela escapa — importante porque as funções
  de negócio serão `security definer` e precisam ser auditadas uma a uma.
- ⚠️ "Automatically expose new tables" está ligado nos dois projetos Supabase. A RLS acima é a
  barreira real; a pendência de desligar a exposição automática continua aberta.

## 5. Organização e acesso (§5.1 do plano)

```sql
create table public.unidade (
  id            uuid primary key default gen_random_uuid(),
  nome          text not null,
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now(),
  criado_por    uuid,
  atualizado_em timestamptz,
  atualizado_por uuid,
  constraint unidade_nome_uk unique (nome)
);

-- Espelho de auth.users. Populado por trigger em auth.users (card 3.5).
create table public.usuario (
  id            uuid primary key references auth.users(id) on delete restrict,
  unidade_id    uuid not null references public.unidade(id),
  nome          text not null,
  email         text not null,
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now(),
  criado_por    uuid,
  atualizado_em timestamptz,
  atualizado_por uuid,
  constraint usuario_email_uk unique (email)
);

create table public.perfil (
  id            uuid primary key default gen_random_uuid(),
  unidade_id    uuid not null references public.unidade(id),
  codigo        text not null,          -- DIRECAO, PEDAGOGICO, SECRETARIA, MONITOR
  nome          text not null,
  ativo         boolean not null default true,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint perfil_codigo_uk unique (unidade_id, codigo)
);

create table public.permissao (
  id            uuid primary key default gen_random_uuid(),
  unidade_id    uuid not null references public.unidade(id),
  codigo        text not null,          -- ex.: aluno.editar, estoque.lancar_saida
  descricao     text not null,
  dominio       text not null,          -- ex.: aluno, estoque, turma
  ativo         boolean not null default true,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint permissao_codigo_uk unique (unidade_id, codigo)
);

create table public.perfil_permissao (
  id            uuid primary key default gen_random_uuid(),
  unidade_id    uuid not null references public.unidade(id),
  perfil_id     uuid not null references public.perfil(id) on delete cascade,
  permissao_id  uuid not null references public.permissao(id) on delete cascade,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint perfil_permissao_uk unique (perfil_id, permissao_id)
);

create table public.usuario_perfil (
  id            uuid primary key default gen_random_uuid(),
  unidade_id    uuid not null references public.unidade(id),
  usuario_id    uuid not null references public.usuario(id) on delete cascade,
  perfil_id     uuid not null references public.perfil(id),
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint usuario_perfil_uk unique (usuario_id, perfil_id)
);

create table public.parametro (
  id            uuid primary key default gen_random_uuid(),
  unidade_id    uuid not null references public.unidade(id),
  chave         text not null,
  valor         text not null,
  tipo          text not null default 'TEXTO'
                check (tipo in ('TEXTO','INTEIRO','DECIMAL','BOOLEANO','DATA')),
  descricao     text,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint parametro_chave_uk unique (unidade_id, chave)
);
```

Parâmetros iniciais (seed do card 3.6), conforme decisão de 31/08/2026:

| chave | valor | tipo | descrição |
|---|---|---|---|
| `projecao_horizonte_dias` | `60` | INTEIRO | Horizonte da projeção de demanda |
| `standby_alerta_dias` | `30` | INTEIRO | Dias em STANDBY até gerar pendência |
| `ritmo_padrao_dias_<METODO>` | calibrado | INTEIRO | Fallback de ritmo por método (§5.7 do plano) |

## 6. Catálogo curricular (§5.2)

```sql
create table public.metodo (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  codigo text not null check (codigo in ('INTERATIVO','INGLES','MODULAR')),
  nome   text not null,
  ativo  boolean not null default true,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint metodo_codigo_uk unique (unidade_id, codigo)
);

create table public.material (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  metodo_id  uuid not null references public.metodo(id),
  codigo     text not null,
  nome       text not null,
  categoria  text not null,
  estoque_minimo integer not null default 0 check (estoque_minimo >= 0),
  ativo      boolean not null default true,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  -- Código de material é único POR MÉTODO: resolve a colisão entre os catálogos.
  constraint material_codigo_uk unique (unidade_id, metodo_id, codigo)
);

create table public.curso (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  metodo_id  uuid not null references public.metodo(id),
  nome       text not null,
  ativo      boolean not null default true,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint curso_nome_uk unique (unidade_id, metodo_id, nome)
);

-- Sequência padrão de apostilas do curso. Número de apostilas é livre (não fixar em 17).
create table public.curso_material (
  id uuid primary key default gen_random_uuid(),
  unidade_id  uuid not null references public.unidade(id),
  curso_id    uuid not null references public.curso(id) on delete cascade,
  material_id uuid not null references public.material(id),
  ordem       integer not null check (ordem > 0),
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint curso_material_uk unique (curso_id, material_id),
  constraint curso_material_ordem_uk unique (curso_id, ordem) deferrable initially deferred
);

-- Modular: o livro se divide em módulos; a turma avança pelos módulos em conjunto.
create table public.modulo (
  id uuid primary key default gen_random_uuid(),
  unidade_id  uuid not null references public.unidade(id),
  curso_id    uuid not null references public.curso(id) on delete cascade,
  material_id uuid not null references public.material(id),
  nome        text not null,
  ordem       integer not null check (ordem > 0),
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint modulo_ordem_uk unique (curso_id, ordem) deferrable initially deferred
);

create table public.combo (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  metodo_id  uuid not null references public.metodo(id),
  nome       text not null,
  ativo      boolean not null default true,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint combo_nome_uk unique (unidade_id, nome)
);

create table public.combo_curso (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  combo_id   uuid not null references public.combo(id) on delete cascade,
  curso_id   uuid not null references public.curso(id),
  ordem      integer not null check (ordem > 0),
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint combo_curso_uk unique (combo_id, curso_id),
  constraint combo_curso_ordem_uk unique (combo_id, ordem) deferrable initially deferred
);
```

`deferrable initially deferred` nos `unique (…, ordem)` é o que permite reordenar a trilha ou a
sequência do curso num único `UPDATE` sem passar por valores temporários.

## 7. Alunos e trilha (§5.3)

```sql
create table public.aluno (
  id uuid primary key default gen_random_uuid(),
  unidade_id  uuid not null references public.unidade(id),
  codigo_sgf  text,                    -- referência externa, opcional, sem integração hoje
  nome        text not null,
  metodo_id   uuid not null references public.metodo(id),
  combo_id    uuid references public.combo(id),
  status      text not null default 'ATIVO'
              check (status in ('ATIVO','ACELERAR','STANDBY','TRANCADO','CANCELADO','FORMADO')),
  status_desde date not null default current_date,   -- alimenta o alerta de STANDBY
  prev_conclusao_curso date,           -- informada manualmente, sem regra de cálculo
  data_inicio date not null default current_date,
  observacoes text,
  conferido   boolean not null default false,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid
);

-- codigo_sgf é único por unidade quando informado; nulos não colidem entre si.
create unique index aluno_codigo_sgf_uk
  on public.aluno (unidade_id, codigo_sgf) where codigo_sgf is not null;

create index aluno_status_ix on public.aluno (unidade_id, status);

create table public.aluno_status_hist (
  id uuid primary key default gen_random_uuid(),
  unidade_id      uuid not null references public.unidade(id),
  aluno_id        uuid not null references public.aluno(id) on delete cascade,
  status_anterior text,
  status_novo     text not null,
  ocorrido_em     timestamptz not null default now(),
  usuario_id      uuid references public.usuario(id),
  motivo          text,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid
);

-- Trilha do aluno. Gerada pelo combo na matrícula, editável individualmente.
create table public.aluno_material (
  id uuid primary key default gen_random_uuid(),
  unidade_id  uuid not null references public.unidade(id),
  aluno_id    uuid not null references public.aluno(id) on delete cascade,
  material_id uuid not null references public.material(id),
  ordem       integer not null check (ordem > 0),
  origem      text not null default 'COMBO' check (origem in ('COMBO','MANUAL')),
  entregue    boolean not null default false,
  data_entrega date,
  movimento_estoque_id uuid,          -- FK adicionada na migração de estoque (Fase 6)
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint aluno_material_uk unique (aluno_id, material_id),
  constraint aluno_material_ordem_uk unique (aluno_id, ordem) deferrable initially deferred,
  -- entregue e data_entrega andam juntos
  constraint aluno_material_entrega_ck
    check ((entregue and data_entrega is not null) or (not entregue and data_entrega is null))
);

-- Livro atual = menor ordem com entregue = false. FIM = nenhuma linha pendente.
create index aluno_material_pendente_ix
  on public.aluno_material (aluno_id, ordem) where not entregue;

-- Histórico de reordenação da trilha (exigido pela decisão de entrega sem estoque, 31/08/2026).
create table public.aluno_material_hist (
  id uuid primary key default gen_random_uuid(),
  unidade_id    uuid not null references public.unidade(id),
  aluno_id      uuid not null references public.aluno(id) on delete cascade,
  material_id   uuid not null references public.material(id),
  ordem_anterior integer,
  ordem_nova     integer,
  motivo        text not null
                check (motivo in ('SEM_ESTOQUE','MANUAL','GERACAO_COMBO','REMOCAO')),
  ocorrido_em   timestamptz not null default now(),
  usuario_id    uuid references public.usuario(id),
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid
);
```

**Por que `aluno_material_hist` existe:** a decisão de 31/08/2026 diz que a entrega sem estoque
não bloqueia — libera a próxima apostila da trilha que tenha estoque, alterando a ordem, e a pulada
volta a ser "próxima" quando houver estoque. Sem histórico, ninguém explica depois por que a trilha
de um aluno saiu da ordem do combo. `motivo = 'SEM_ESTOQUE'` é a marca desse reordenamento.

## 8. Infraestrutura física e turmas por horário (§5.4, §5.5)

```sql
create table public.sala (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  nome       text not null,
  tipo       text not null check (tipo in ('LABORATORIO','SALA_MODULAR')),
  capacidade_nominal integer not null check (capacidade_nominal > 0),
  ativo      boolean not null default true,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint sala_nome_uk unique (unidade_id, nome)
);

create table public.pc (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  sala_id    uuid not null references public.sala(id),
  identificador text not null,
  status     text not null default 'OPERACIONAL'
             check (status in ('OPERACIONAL','MANUTENCAO','DESATIVADO')),
  -- NUNCA senha em texto puro. Aqui vai apenas a referência ao cofre externo.
  -- Política definitiva: card 2.9 (Definir política para credenciais dos PCs).
  -- ⚠️ SUPERADO em 01/09/2026 pelo card 2.9 e aplicado em 02/09/2026 pelo 4.3:
  -- a coluna abaixo NÃO existe. O segredo é o par {usuario, senha} inteiro,
  -- cifrado em vault.secrets, e `pc` guarda credencial_secret_id +
  -- credencial_em + credencial_por. Ver docs/politica-credenciais-pcs.md §3.
  credencial_ref text,
  observacao text,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint pc_identificador_uk unique (unidade_id, identificador)
);

create table public.pc_manutencao (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  pc_id      uuid not null references public.pc(id) on delete cascade,
  tipo       text not null check (tipo in ('PREVENTIVA','CORRETIVA','CONFIGURACAO')),
  data_inicio date not null,
  data_fim    date,
  descricao   text,
  pc_substituto_id uuid references public.pc(id),
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint pc_manutencao_periodo_ck check (data_fim is null or data_fim >= data_inicio),
  constraint pc_manutencao_substituto_ck check (pc_substituto_id is distinct from pc_id)
);

create table public.professor (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  nome  text not null,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint professor_nome_uk unique (unidade_id, nome)
);

-- Substitui os 6 blocos × 6 abas da planilha.
create table public.bloco_horario (
  id uuid primary key default gen_random_uuid(),
  unidade_id   uuid not null references public.unidade(id),
  dia_semana   smallint not null check (dia_semana between 1 and 7),  -- ISO: 1 = segunda
  hora_inicio  time not null,
  metodo_id    uuid not null references public.metodo(id),
  professor_id uuid references public.professor(id),
  sala_id      uuid not null references public.sala(id),
  capacidade_override integer check (capacidade_override > 0),
  ativo        boolean not null default true,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  -- A mesma sala não pode ter dois blocos no mesmo dia e horário.
  constraint bloco_horario_uk unique (unidade_id, sala_id, dia_semana, hora_inicio)
);

-- Alocação do aluno no bloco. Um aluno pode estar em mais de um bloco (aceleração).
create table public.bloco_aluno (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  bloco_id   uuid not null references public.bloco_horario(id) on delete cascade,
  aluno_id   uuid not null references public.aluno(id) on delete cascade,
  tipo       text not null check (tipo in ('REM','PRE','REP','NOVO')),
  data_inicio_prevista date,           -- usado quando tipo = NOVO
  ativo      boolean not null default true,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint bloco_aluno_novo_ck
    check (tipo <> 'NOVO' or data_inicio_prevista is not null)
);

-- Um aluno ocupa no máximo uma vaga ativa por bloco; realocações antigas ficam com ativo = false.
create unique index bloco_aluno_ativo_uk
  on public.bloco_aluno (bloco_id, aluno_id) where ativo;

-- Reposição como EVENTO PONTUAL COM DATA (decisão híbrida de 31/08/2026).
create table public.bloco_aluno_reposicao (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  bloco_id   uuid not null references public.bloco_horario(id),   -- bloco onde vai repor
  aluno_id   uuid not null references public.aluno(id) on delete cascade,
  data       date not null,                                       -- dia da reposição
  bloco_origem_id uuid references public.bloco_horario(id),       -- bloco da aula perdida
  data_origem date,                                               -- dia da aula perdida
  status     text not null default 'PREVISTA'
             check (status in ('PREVISTA','REALIZADA','CANCELADA')),
  observacao text,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint bloco_aluno_reposicao_uk unique (bloco_id, aluno_id, data)
);

create index bloco_aluno_reposicao_data_ix
  on public.bloco_aluno_reposicao (unidade_id, data) where status = 'PREVISTA';
```

**REP híbrido, na prática.** A decisão de 31/08/2026 diz: reposições são lançamentos pontuais com
data enquanto o aluno consegue repor tudo no prazo; quando deixa de conseguir, vira REP contínuo na
alocação. As duas metades existem no schema:

- metade pontual → `bloco_aluno_reposicao` (uma linha por reposição, com data e vaga ocupada naquele dia);
- metade contínua → `bloco_aluno.tipo = 'REP'` (estado permanente da alocação).

O gatilho que promove um do outro foi fechado pelo **card 2.5** em 01/09/2026, em
`docs/regra-virada-rep.md`: débito de aulas em aberto × capacidade semanal × semanas até o prazo,
com gatilho independente por reincidência de `FALTOU`, e virada **sugerida** (pendência
`REP_VIRADA`), executada por uma pessoa. Aquele card exige uma coluna nova aqui —
`bloco_aluno.tipo_desde date not null default current_date`, mantida por trigger — sem a qual a
virada não tem como zerar o relógio do débito. Entra na migração do card 5.1.

**Capacidade efetiva** (função do card 5.2, não é coluna):
`coalesce(capacidade_override, nº de PCs OPERACIONAIS da sala)`, combinada com a capacidade nominal
conforme o plano. Aluno remoto ocupa vaga — acessa o PC do laboratório remotamente, então o PC está
tomado. Capacidades confirmadas em 31/08/2026: laboratório 10, Eletricista 15, Depilação 6.
A reposição do dia consome vaga na data: a lotação do bloco em uma data é
`bloco_aluno ativo + bloco_aluno_reposicao PREVISTA naquela data`.

## 9. Turmas Modular (§5.6)

```sql
create table public.turma_modular (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  curso_id   uuid not null references public.curso(id),
  nome       text not null,
  sala_id    uuid not null references public.sala(id),
  capacidade integer not null check (capacidade > 0),
  data_inicio date not null,
  ativo      boolean not null default true,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint turma_modular_nome_uk unique (unidade_id, nome)
);

-- Cronograma da turma: todos avançam juntos. `Ger. Modular` é a fonte oficial na migração.
create table public.turma_modular_modulo (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  turma_id   uuid not null references public.turma_modular(id) on delete cascade,
  modulo_id  uuid not null references public.modulo(id),
  data_inicio    date,
  prev_conclusao date,
  concluido  boolean not null default false,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint turma_modular_modulo_uk unique (turma_id, modulo_id)
);

create table public.turma_modular_aluno (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  turma_id   uuid not null references public.turma_modular(id) on delete cascade,
  aluno_id   uuid not null references public.aluno(id) on delete cascade,
  data_entrada date not null default current_date,
  ativo      boolean not null default true,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid
);

create unique index turma_modular_aluno_ativo_uk
  on public.turma_modular_aluno (turma_id, aluno_id) where ativo;
```

A previsão de necessidade de cada livro do aluno modular deriva do `turma_modular_modulo` do
primeiro módulo daquele livro — a projeção de demanda (Fase 8) lê daqui, não do ritmo individual.

## 10. Estoque, compras, certificados e pendências (§5.7, §5.8)

```sql
-- Movimento IMUTÁVEL. Correção é por estorno, nunca por update.
create table public.movimento_estoque (
  id uuid primary key default gen_random_uuid(),
  unidade_id  uuid not null references public.unidade(id),
  material_id uuid not null references public.material(id),
  tipo        text not null check (tipo in ('ENTRADA','SAIDA','AJUSTE','ESTORNO')),
  -- quantidade COM SINAL: estoque atual = soma simples da coluna.
  quantidade  integer not null check (quantidade <> 0),
  ocorrido_em timestamptz not null default now(),
  aluno_id    uuid references public.aluno(id),        -- saídas de entrega
  pedido_item_id uuid,                                 -- FK adicionada abaixo
  estorno_de_id  uuid references public.movimento_estoque(id),
  observacao  text,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint movimento_sinal_ck check (
       (tipo = 'ENTRADA' and quantidade > 0)
    or (tipo = 'SAIDA'   and quantidade < 0)
    or (tipo in ('AJUSTE','ESTORNO'))      -- ajuste e estorno podem ser + ou −
  ),
  constraint movimento_estorno_ck check (
    (tipo = 'ESTORNO') = (estorno_de_id is not null)
  )
);

-- Um movimento só pode ser estornado uma vez.
create unique index movimento_estorno_uk
  on public.movimento_estoque (estorno_de_id) where estorno_de_id is not null;

create index movimento_material_ix on public.movimento_estoque (unidade_id, material_id);

-- Imutabilidade como estrutura: nem update nem delete, para ninguém.
create or replace function public.fn_movimento_imutavel()
returns trigger language plpgsql as $$
begin
  raise exception 'movimento_estoque é imutável; corrija por estorno (tipo = ESTORNO)';
end;
$$;

create trigger tg_movimento_imutavel
  before update or delete on public.movimento_estoque
  for each row execute function public.fn_movimento_imutavel();

create table public.pedido_compra (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  numero     text not null,
  status     text not null default 'RASCUNHO'
             check (status in ('RASCUNHO','ENVIADO','PARCIAL','RECEBIDO','CANCELADO')),
  data_envio date,
  fornecedor text,
  observacao text,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint pedido_compra_numero_uk unique (unidade_id, numero)
);

create table public.pedido_item (
  id uuid primary key default gen_random_uuid(),
  unidade_id  uuid not null references public.unidade(id),
  pedido_id   uuid not null references public.pedido_compra(id) on delete cascade,
  material_id uuid not null references public.material(id),
  qtd_pedida   integer not null check (qtd_pedida > 0),
  qtd_recebida integer not null default 0 check (qtd_recebida >= 0),
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint pedido_item_uk unique (pedido_id, material_id),
  constraint pedido_item_recebido_ck check (qtd_recebida <= qtd_pedida)
);

alter table public.movimento_estoque
  add constraint movimento_pedido_item_fk
  foreign key (pedido_item_id) references public.pedido_item(id);

alter table public.aluno_material
  add constraint aluno_material_movimento_fk
  foreign key (movimento_estoque_id) references public.movimento_estoque(id);

-- Criado automaticamente quando a trilha chega ao FIM.
create table public.certificado_checklist (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  aluno_id   uuid not null references public.aluno(id) on delete cascade,
  data_fim_curso date not null,
  pedagogico_ok      boolean not null default false,
  pedagogico_por     uuid references public.usuario(id),
  pedagogico_em      timestamptz,
  financeiro_ok      boolean not null default false,   -- marcado pelo monitor
  financeiro_por     uuid references public.usuario(id),
  financeiro_em      timestamptz,
  formatura          boolean not null default false,
  certificado_status text not null default 'NAO_PEDIDO'
                     check (certificado_status in ('NAO_PEDIDO','PEDIDO','ENTREGUE')),
  certificado_por    uuid references public.usuario(id),
  certificado_em     timestamptz,
  observacoes text,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint certificado_checklist_aluno_uk unique (aluno_id)
);

create table public.pendencia (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  tipo       text not null check (tipo in (
               'ALUNO_SEM_TURMA','BLOCO_ACIMA_CAPACIDADE','ACELERAR_SEM_2O_BLOCO',
               'STANDBY_PROLONGADO','PREVISAO_VENCIDA','ALUNO_ULTIMO_LIVRO',
               'COMPRA_SEM_ESTOQUE','PC_SEM_SUBSTITUTO')),
  severidade text not null default 'MEDIA' check (severidade in ('BAIXA','MEDIA','ALTA')),
  descricao  text not null,
  aluno_id    uuid references public.aluno(id) on delete cascade,
  bloco_id    uuid references public.bloco_horario(id) on delete cascade,
  material_id uuid references public.material(id),
  pc_id       uuid references public.pc(id),
  -- Idempotência da rotina: a mesma pendência aberta não é recriada a cada execução.
  chave_dedup text not null,
  resolvida_em  timestamptz,
  resolvida_por uuid references public.usuario(id),
  resolucao     text check (resolucao in ('RESOLVIDA','IGNORADA')),
  justificativa text,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint pendencia_resolucao_ck check (
    (resolvida_em is null and resolucao is null)
    or (resolvida_em is not null and resolucao is not null)
  ),
  -- Ignorar exige justificativa; resolver não.
  constraint pendencia_ignorada_ck check (
    resolucao is distinct from 'IGNORADA' or justificativa is not null
  )
);

create unique index pendencia_aberta_uk
  on public.pendencia (unidade_id, chave_dedup) where resolvida_em is null;
```

**`chave_dedup`** é o que torna a rotina de pendências reexecutável: a rotina do card 5.5 roda todo
dia e tenta inserir; o índice parcial rejeita a duplicata enquanto a pendência anterior estiver
aberta. Formato sugerido: `'<TIPO>:<id_da_referencia>'`.

**Estoque atual** é sempre `sum(quantidade)` de `movimento_estoque` — nunca uma coluna. A view
`v_estoque_atual` é do card 6.4.

## 11. Mapa DDL → card do board

| Bloco deste documento | Tabelas / objetos | Card |
|---|---|---|
| §3 infra comum, §5 | `fn_auditoria`, `unidade`, `usuario`, `perfil`, `permissao`, `perfil_permissao`, `usuario_perfil`, `parametro` | 3.3 |
| §3, §4 | `fn_unidade_atual`, `tem_permissao`, políticas de RLS | 3.4 |
| §5 (seed) | parâmetros iniciais, perfis, matriz, usuário direção | 3.6 |
| §6 | `metodo`, `material`, `curso`, `curso_material`, `modulo`, `combo`, `combo_curso` | 4.1 |
| §7 | `aluno`, `aluno_status_hist` (+ trigger de transições) | 4.2 |
| §8 (físico) | `sala`, `pc`, `pc_manutencao`, `professor` | 4.3 |
| §8 (turmas) | `bloco_horario`, `bloco_aluno`, `bloco_aluno_reposicao` | 5.1 |
| §10 (pendência) | `pendencia` + rotina | 5.5 ✅ — criada em 03/09/2026 com os **quinze** tipos no `check` (os oito daqui mais os sete do ajuste 2 do §14 do card 2.2), mais `pendencia_severidade_ix` |
| §7 (trilha), §10 (estoque) | `aluno_material`, `aluno_material_hist`, `movimento_estoque`, `pedido_compra`, `pedido_item` | 6.1 ✅ — criadas em 04/09/2026 com as **quinze** políticas do card 2.4 §4 (o `insert` de `movimento_estoque` é POR TIPO), `tg_movimento_imutavel`, a guarda de coluna de `aluno_material`, as duas guardas de exclusão (`ITEM_JA_ENTREGUE`, `PEDIDO_NAO_RASCUNHO`) e o trigger de coerência de método da pendência 9.11 |
| §9 | `turma_modular`, `turma_modular_modulo`, `turma_modular_aluno` | 7.1 |
| §10 (certificado) | `certificado_checklist` | 8.3 |

Ordem de dependência entre migrações: 3.3 → 3.4 → 3.6 → 4.1 → 4.2 → 4.3 → 5.1 → 5.5 → 6.1 → 7.1 → 8.3.
As duas FKs adiadas (`aluno_material.movimento_estoque_id` e `movimento_estoque.pedido_item_id`) são
criadas na migração 6.1, quando as duas pontas já existem.

## 12. Pontos que este documento deixa em aberto

1. ~~**Critério objetivo da virada REP pontual → contínuo**~~ — **fechado em 01/09/2026**
   (card 2.5, `docs/regra-virada-rep.md`). Acrescenta `bloco_aluno.tipo_desde` a este DDL, na
   migração do card 5.1.
2. **Catálogo de códigos de permissão** (`<dominio>.<acao>`) — card 2.4. Até lá, as políticas de RLS
   estão escritas com o formato, não com a lista.
3. **Política definitiva de credenciais dos PCs** — card 2.9. `pc.credencial_ref` é um placeholder
   para referência a cofre externo; nenhuma senha em texto puro entra no banco.
4. **Capacidade nominal mínima da sala** na fórmula de capacidade efetiva: o plano diz "mín. com
   capacidade nominal"; a função do card 5.2 precisa fixar exatamente como as duas se combinam.
