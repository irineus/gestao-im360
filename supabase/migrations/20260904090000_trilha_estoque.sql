-- =============================================================================
-- Card 6.1 — Schema: trilha do aluno e estoque
--            (aluno_material, aluno_material_hist, movimento_estoque,
--             pedido_compra, pedido_item)
-- Fonte: docs/modelagem-dados-ddl.md §7 (trilha) e §10 (estoque e compras),
--        docs/permissoes-matriz.md §4 (políticas), §3.5 (domínios `estoque` e
--        `compras`) e §7 (achados 5 e 9),
--        docs/regras-negocio-funcoes.md §6 e §7 (o que NÃO é deste card),
--        Decisões vigentes, pendência 9.11 (coerência de método).
--
-- Entrega: as cinco tabelas da fase 06 + as duas FKs adiadas do card 2.1
--          + triggers de auditoria + RLS habilitada, FORÇADA e com as quinze
--          políticas do card 2.4 §4 (incluindo o insert POR TIPO de
--          movimento_estoque) + tg_movimento_imutavel
--          + a guarda de coluna que o `or` da política de update de
--            aluno_material abre (a lição dos cards 4.2 e 5.1)
--          + as duas guardas de exclusão da família do card 4.3
--          + o trigger de coerência de método da pendência 9.11, transferido
--            pelo card 4.4.
--
-- ⚠️ ESTRUTURA E MAIS NADA.
--    Decisão de 02/09/2026 (Irineu): dado de negócio vindo da planilha fica
--    restrito ao ambiente dev/homolog até a virada do card 9.7. Trilha e
--    movimentos reais não entram em supabase/migrations/ — migração é o que o CI
--    empurra para produção sozinho no merge em `main`. Eles vêm pelo importador
--    do card 9.1, carregados só no projeto dev; trilha e estoque de teste são da
--    escola-fixture do card 3.4.5, que vive em supabase/seed.sql e nunca sai do
--    stack local. O portão do card 4.0,5 (portao-migracoes/varredor.mjs) tem as
--    cinco tabelas deste arquivo FORA da lista permitida.
--
--    Atenção redobrada aqui, e é a nota do card que a escreve: `movimento_estoque`
--    é IMUTÁVEL, então movimento gravado em produção por engano NÃO SE APAGA —
--    só se estorna, e a sobra fica visível para sempre no histórico. É a tabela
--    onde o custo de contaminar prod é o mais alto do projeto.
--
-- O que este card NÃO traz, e onde está escrito que não é esquecimento:
--   • fn_trilha_* (geração pelo combo, inclusão, remoção, reordenação) e os
--     triggers tg_aluno_trilha_inicial / tg_aluno_combo_alterado são do card 6.2
--     (docs/regras-negocio-funcoes.md §6.1 e §13);
--   • tp_entrega_resultado, fn_registrar_entrega, fn_estornar_entrega e
--     fn_saldo_material são do card 6.3 (§6.2, §6.3 e §13);
--   • fn_pedido_receber, fn_ajustar_estoque, tg_movimento_valida_sinal e
--     tg_movimento_resolve_pendencia são do card 6.5 (§7 e §13) — e o teste 050
--     tem portão para os dois triggers, que reprova no dia em que
--     fn_pedido_receber nascer sem eles;
--   • v_estoque_atual, v_demanda_imediata e v_pedido_sugerido são do card 6.4
--     (docs/views-leitura.md §4.1, §5 e §6);
--   • `aluno_material_hist.observacao` é o ajuste 4 do §14 do card 2.2 e está
--     atribuído ao card **6.2**, que é quem escreve na tabela. Nasce aqui sem a
--     coluna, de propósito: acrescentá-la agora daria uma coluna sem escritor,
--     e o `add column` do 6.2 é barato.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Trilha do aluno (§7 do DDL do card 2.1)
-- -----------------------------------------------------------------------------
-- Substitui as colunas "livro atual" e "próximo" da planilha, que eram digitadas
-- à mão. Aqui o livro atual é DERIVADO (menor `ordem` com `entregue = false`) e
-- não existe coluna que o guarde — é o critério (1) do marco 6.9.
create table public.aluno_material (
  id                   uuid primary key default gen_random_uuid(),
  unidade_id           uuid not null references public.unidade(id),
  aluno_id             uuid not null references public.aluno(id) on delete cascade,
  material_id          uuid not null references public.material(id),
  ordem                integer not null check (ordem > 0),
  origem               text not null default 'COMBO' check (origem in ('COMBO','MANUAL')),
  entregue             boolean not null default false,
  data_entrega         date,
  movimento_estoque_id uuid,          -- FK adicionada na seção 4, quando a tabela existir
  criado_em            timestamptz not null default now(),
  criado_por           uuid,
  atualizado_em        timestamptz,
  atualizado_por       uuid,
  constraint aluno_material_uk unique (aluno_id, material_id),
  -- DEFERRABLE pela mesma razão de combo_curso e curso_material (card 4.1): a
  -- reordenação do card 6.2 troca posições, e trocar 1 por 2 passa por um estado
  -- intermediário duplicado que só o adiamento até o fim da transação permite.
  constraint aluno_material_ordem_uk unique (aluno_id, ordem) deferrable initially deferred,
  -- `entregue` e `data_entrega` andam juntos: um dos dois sozinho é uma entrega
  -- que aconteceu sem dia ou um dia sem entrega, e as duas metades mentem para a
  -- projeção de demanda do card 8.1, que mede intervalo entre entregas.
  constraint aluno_material_entrega_ck
    check ((entregue and data_entrega is not null) or (not entregue and data_entrega is null))
);

comment on table public.aluno_material is
  'Trilha do aluno: a sequência de apostilas que ele tem a receber. VAZIA em produção até a virada do card 9.7 — a trilha real entra pelo importador do card 9.1, no ambiente dev. Gerada pelo combo na matrícula (card 6.2) e editável item a item.';
comment on column public.aluno_material.ordem is
  'Posição na trilha. O LIVRO ATUAL é a menor ordem com entregue = false, derivado — nunca uma coluna (card 2.3). Número de apostilas é variável: nada aqui fixa 17, que era a suposição da planilha.';
comment on column public.aluno_material.origem is
  'COMBO quando a linha veio da expansão combo → curso → material (card 6.2); MANUAL quando alguém a incluiu na mão. A distinção é o que permite ao card 6.2 regerar a trilha sem apagar o que foi acrescentado à mão.';
comment on column public.aluno_material.movimento_estoque_id is
  'Vínculo entre a entrega e a SAIDA que a pagou, escrito por fn_registrar_entrega (card 6.3). É o que torna o estorno reversível sem adivinhação: sem ele, desfazer uma entrega exigiria procurar o movimento por aluno e data, e duas entregas no mesmo dia seriam indistinguíveis.';

-- Livro atual = menor ordem com entregue = false. FIM = nenhuma linha pendente.
-- Índice PARCIAL porque o predicado é sempre o mesmo: a trilha entregue é
-- passado e não entra em nenhuma das duas perguntas (qual o próximo, quantos
-- faltam).
create index aluno_material_pendente_ix
  on public.aluno_material (aluno_id, ordem) where not entregue;

-- Histórico de reordenação da trilha (decisão de 31/08/2026, entrega sem
-- estoque). Sem ele, ninguém explica depois por que a trilha de um aluno saiu
-- da ordem do combo — e é exatamente essa a pergunta que o pedagógico faz.
create table public.aluno_material_hist (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  aluno_id       uuid not null references public.aluno(id) on delete cascade,
  material_id    uuid not null references public.material(id),
  ordem_anterior integer,
  ordem_nova     integer,
  motivo         text not null
                 check (motivo in ('SEM_ESTOQUE','MANUAL','GERACAO_COMBO','REMOCAO')),
  ocorrido_em    timestamptz not null default now(),
  usuario_id     uuid references public.usuario(id),
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid
);

comment on table public.aluno_material_hist is
  'Histórico de reordenação e remoção da trilha. Imutável pela AUSÊNCIA de política de update e delete (card 2.4 §4), como aluno_status_hist, pc_credencial_acesso e perfil_permissao_hist.';
comment on column public.aluno_material_hist.motivo is
  'SEM_ESTOQUE é a marca do reordenamento automático de fn_registrar_entrega (card 6.3) — o item pulado continua pendente e volta a ser "próximo" quando houver estoque. Os outros três são edição humana (card 6.2).';

-- -----------------------------------------------------------------------------
-- 2. Movimento de estoque, imutável (§10 do DDL do card 2.1)
-- -----------------------------------------------------------------------------
-- Estoque atual é SEMPRE sum(quantidade) desta tabela, nunca uma coluna: saldo
-- guardado em coluna diverge do histórico na primeira escrita concorrente, e o
-- que sobra é um número que ninguém consegue explicar.
create table public.movimento_estoque (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  material_id    uuid not null references public.material(id),
  tipo           text not null check (tipo in ('ENTRADA','SAIDA','AJUSTE','ESTORNO')),
  -- Quantidade COM SINAL: o saldo é uma soma simples, e não uma soma com
  -- `case` por tipo — que é onde o erro de sinal mora escondido.
  quantidade     integer not null check (quantidade <> 0),
  ocorrido_em    timestamptz not null default now(),
  aluno_id       uuid references public.aluno(id),   -- saídas de entrega
  pedido_item_id uuid,                               -- FK adicionada na seção 4
  estorno_de_id  uuid references public.movimento_estoque(id),
  observacao     text,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint movimento_sinal_ck check (
       (tipo = 'ENTRADA' and quantidade > 0)
    or (tipo = 'SAIDA'   and quantidade < 0)
    or (tipo in ('AJUSTE','ESTORNO'))      -- ajuste e estorno podem ser + ou −
  ),
  constraint movimento_estorno_ck check (
    (tipo = 'ESTORNO') = (estorno_de_id is not null)
  )
);

comment on table public.movimento_estoque is
  'Movimento de estoque, IMUTÁVEL: correção é por estorno, nunca por update. VAZIA em produção até a virada do card 9.7 — e é a tabela onde o custo de contaminar produção é o mais alto, porque a sobra não se apaga, só se estorna, e o estorno deixa duas linhas onde deveria haver zero.';
comment on column public.movimento_estoque.quantidade is
  'COM SINAL: ENTRADA > 0, SAIDA < 0, AJUSTE e ESTORNO nos dois sentidos. O saldo é sum(quantidade) puro — v_estoque_atual (card 6.4) não pode ter `case` por tipo, senão o tipo novo que alguém acrescentar entra na tabela e some da conta.';
comment on column public.movimento_estoque.estorno_de_id is
  'Movimento que este estorna. O par (tipo = ESTORNO) ⟺ (estorno_de_id não nulo) é `check`, e "um movimento só se estorna uma vez" é a unique parcial abaixo: sem ela, dois estornos do mesmo movimento devolveriam o dobro ao saldo, cada um deles parecendo certo sozinho.';
comment on column public.movimento_estoque.pedido_item_id is
  'Vínculo entre a compra e o estoque, preenchido por fn_pedido_receber (card 6.5). É o que a planilha não tinha: lá, a chegada de um pedido e a entrada em estoque eram duas anotações sem ligação nenhuma.';

-- Um movimento só pode ser estornado uma vez.
create unique index movimento_estorno_uk
  on public.movimento_estoque (estorno_de_id) where estorno_de_id is not null;

create index movimento_material_ix on public.movimento_estoque (unidade_id, material_id);

-- Imutabilidade como ESTRUTURA, em duas camadas independentes: a ausência de
-- política de update e delete (seção 6) e este trigger. Não é redundância
-- decorativa — a ausência de política não alcança quem tem BYPASSRLS (achado do
-- card 3.3: `postgres` e `service_role` têm), e o trigger alcança.
create or replace function public.fn_movimento_imutavel()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  raise exception using
    errcode = 'PT409',
    message = 'Movimento de estoque não pode ser alterado nem apagado; corrija por estorno.',
    -- Código PRÓPRIO, e não o `MOVIMENTO_NAO_ESTORNAVEL` do card 2.2 §12: aquele
    -- é a recusa de fn_estornar_entrega (card 6.3) a estornar um movimento que
    -- não se pode estornar, e a mensagem dele — "este movimento não pode ser
    -- estornado" — diria aqui o contrário do que se está pedindo à pessoa.
    detail  = json_build_object('codigo', 'MOVIMENTO_IMUTAVEL',
                                'operacao', tg_op)::text;
end $$;

comment on function public.fn_movimento_imutavel() is
  'Trigger BEFORE UPDATE OR DELETE em movimento_estoque: recusa sempre. Segunda camada da imutabilidade, e a única que vale para quem tem BYPASSRLS — a primeira é a ausência de política (card 2.4 §4).';

revoke execute on function public.fn_movimento_imutavel() from public;
revoke execute on function public.fn_movimento_imutavel() from anon;

create trigger tg_movimento_imutavel
  before update or delete on public.movimento_estoque
  for each row execute function public.fn_movimento_imutavel();

-- -----------------------------------------------------------------------------
-- 3. Compras (§10 do DDL do card 2.1)
-- -----------------------------------------------------------------------------
create table public.pedido_compra (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  numero         text not null,
  status         text not null default 'RASCUNHO'
                 check (status in ('RASCUNHO','ENVIADO','PARCIAL','RECEBIDO','CANCELADO')),
  data_envio     date,
  fornecedor     text,
  observacao     text,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint pedido_compra_numero_uk unique (unidade_id, numero)
);

comment on table public.pedido_compra is
  'Pedido de compra de material. VAZIA em produção até a virada do card 9.7. Sem política de DELETE (card 2.4 §3.5): pedido enviado vira CANCELADO, não desaparece — o histórico de compra é o que explica um saldo três meses depois.';
comment on column public.pedido_compra.status is
  'RASCUNHO → ENVIADO → PARCIAL → RECEBIDO, mais CANCELADO. Quem move PARCIAL e RECEBIDO é fn_pedido_receber (card 6.5), a partir do que foi de fato recebido item a item; RASCUNHO não abate na parcela "já pedida" do pedido sugerido (card 2.3 §6 (d)).';

create table public.pedido_item (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  pedido_id      uuid not null references public.pedido_compra(id) on delete cascade,
  material_id    uuid not null references public.material(id),
  qtd_pedida     integer not null check (qtd_pedida > 0),
  qtd_recebida   integer not null default 0 check (qtd_recebida >= 0),
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint pedido_item_uk unique (pedido_id, material_id),
  constraint pedido_item_recebido_ck check (qtd_recebida <= qtd_pedida)
);

comment on table public.pedido_item is
  'Item de um pedido de compra. `qtd_pedida − qtd_recebida` é a parcela "já pedida" que o pedido sugerido do card 2.3 §6 abate — do ITEM, não do pedido, senão um pedido meio recebido abateria duas vezes.';
comment on column public.pedido_item.qtd_recebida is
  'Recebido acumulado. O `check (qtd_recebida <= qtd_pedida)` é a camada 1 do recebimento; a exceção é `compras.receber_excedente` (card 2.4 §3.5), e é fn_pedido_receber (card 6.5) quem a aplica — receber a mais pelo PostgREST não passa aqui, e é assim que tem de ser.';

-- -----------------------------------------------------------------------------
-- 4. As duas FKs que o card 2.1 deixou adiadas
-- -----------------------------------------------------------------------------
-- O DDL as escreve como `alter table` justamente porque as duas tabelas se
-- referenciam em círculo (aluno_material → movimento_estoque → pedido_item, e
-- movimento_estoque → aluno_material só pelo lado da trilha). Nenhuma das duas é
-- `on delete cascade`, e a razão é a mesma nos dois casos: apagar o lado
-- referenciado é impossível (movimento_estoque não tem política de delete) ou
-- guardado (pedido_item, seção 8.2).
alter table public.movimento_estoque
  add constraint movimento_pedido_item_fk
  foreign key (pedido_item_id) references public.pedido_item(id);

alter table public.aluno_material
  add constraint aluno_material_movimento_fk
  foreign key (movimento_estoque_id) references public.movimento_estoque(id);

-- -----------------------------------------------------------------------------
-- 5. Índices dos lados de FK que nenhuma unique cobre
-- -----------------------------------------------------------------------------
-- Mesma razão dos cards 3.3, 4.1, 4.3 e 5.1: uma unique só serve de índice à FK
-- quando a coluna é a PRIMEIRA dela, e índice parcial não serve nunca.
-- `aluno_material_uk (aluno_id, material_id)` cobre `aluno_id`; `material_id`
-- fica sem, e é justamente a consulta de v_demanda_imediata (card 6.4).
create index aluno_material_material_ix  on public.aluno_material (material_id);
create index aluno_material_movimento_ix on public.aluno_material (movimento_estoque_id);

create index aluno_material_hist_aluno_ix    on public.aluno_material_hist (aluno_id);
create index aluno_material_hist_material_ix on public.aluno_material_hist (material_id);
create index aluno_material_hist_usuario_ix  on public.aluno_material_hist (usuario_id);

-- `movimento_material_ix (unidade_id, material_id)` NÃO cobre a FK de
-- `material_id`, porque material_id não é a primeira coluna dele; e
-- `movimento_estorno_uk` é parcial.
create index movimento_material_fk_ix on public.movimento_estoque (material_id);
create index movimento_aluno_ix       on public.movimento_estoque (aluno_id);
create index movimento_pedido_item_ix on public.movimento_estoque (pedido_item_id);
create index movimento_estorno_fk_ix  on public.movimento_estoque (estorno_de_id);

-- `pedido_item_uk (pedido_id, material_id)` já cobre a FK de `pedido_id`.
create index pedido_item_material_ix on public.pedido_item (material_id);

-- -----------------------------------------------------------------------------
-- 6. Triggers de auditoria (C3 do card 2.8)
-- -----------------------------------------------------------------------------
create trigger tg_auditoria_aluno_material
  before insert or update on public.aluno_material
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_aluno_material_hist
  before insert or update on public.aluno_material_hist
  for each row execute function public.fn_auditoria();

-- `movimento_estoque` recebe o trigger de auditoria só no INSERT: um
-- `before update` aqui seria código morto, porque tg_movimento_imutavel derruba
-- todo update antes. Mantê-lo em `insert or update` passaria pelo C3 igual e
-- diria, a quem lê, que existe update possível nesta tabela — que é justamente
-- o contrário do contrato dela.
create trigger tg_auditoria_movimento_estoque
  before insert on public.movimento_estoque
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_pedido_compra
  before insert or update on public.pedido_compra
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_pedido_item
  before insert or update on public.pedido_item
  for each row execute function public.fn_auditoria();

-- -----------------------------------------------------------------------------
-- 7. RLS habilitada e forçada
-- -----------------------------------------------------------------------------
-- Políticas no MESMO arquivo que as tabelas, como nos cards 4.1, 4.2, 4.3 e 5.1:
-- "Automatically expose new tables" continua ligado nos dois projetos (pendência
-- técnica 3), então tabela sem política é uma API REST aberta pelo tempo que a
-- tarefa seguinte durar.
alter table public.aluno_material      enable row level security;
alter table public.aluno_material      force  row level security;
alter table public.aluno_material_hist enable row level security;
alter table public.aluno_material_hist force  row level security;
alter table public.movimento_estoque   enable row level security;
alter table public.movimento_estoque   force  row level security;
alter table public.pedido_compra       enable row level security;
alter table public.pedido_compra       force  row level security;
alter table public.pedido_item         enable row level security;
alter table public.pedido_item         force  row level security;

-- -----------------------------------------------------------------------------
-- 8. Políticas — docs/permissoes-matriz.md §4
-- -----------------------------------------------------------------------------
-- 8.1 aluno_material — foge do padrão, e é o achado 5 do §7 do card 2.4,
--     marcado BLOQUEANTE: `fn_registrar_entrega` (card 6.3) é `security invoker`
--     e roda na transação do MONITOR, que tem `estoque.lancar_saida` e não tem
--     `alunos.editar_trilha`. Uma política de update por `alunos.editar_trilha`
--     sozinho faria a entrega do monitor falhar com erro opaco de RLS numa tela
--     que não fala de trilha.
--
--     O `insert` aceita `alunos.criar` porque a trilha nasce na MATRÍCULA
--     (tg_aluno_trilha_inicial, card 6.2), dentro da transação de quem cadastrou
--     o aluno — mesma família.
create policy aluno_material_sel on public.aluno_material for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('alunos.ler'));

create policy aluno_material_ins on public.aluno_material for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('alunos.editar_trilha')
                   or public.tem_permissao('alunos.criar')));

create policy aluno_material_upd on public.aluno_material for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('alunos.editar_trilha')
                   or public.tem_permissao('estoque.lancar_saida')
                   or public.tem_permissao('estoque.estornar')))
  with check (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('alunos.editar_trilha')
                   or public.tem_permissao('estoque.lancar_saida')
                   or public.tem_permissao('estoque.estornar')));

create policy aluno_material_del on public.aluno_material for delete to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('alunos.editar_trilha'));

-- 8.2 aluno_material_hist — histórico imutável pela ausência de update e delete.
--     O `insert` aceita `estoque.lancar_saida` pelo mesmo motivo do update
--     acima: o reordenamento por falta de estoque é escrito pelo monitor.
create policy aluno_material_hist_sel on public.aluno_material_hist
  for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('alunos.ler'));

create policy aluno_material_hist_ins on public.aluno_material_hist
  for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('alunos.editar_trilha')
                   or public.tem_permissao('estoque.lancar_saida')));

-- 8.3 movimento_estoque — insert POR TIPO (achado 9 do §7 do card 2.4).
--     Um `estoque.criar` genérico seria uma porta aberta: a tabela está
--     publicada no PostgREST, e o monitor — que precisa gravar SAIDA — poderia
--     `POST` uma ENTRADA de 500 unidades sem passar por fn_pedido_receber,
--     inventando estoque que ninguém comprou. A política por tipo custa quatro
--     linhas e fecha isso.
--
--     Sem update e sem delete em nenhuma hipótese: é a imutabilidade como
--     estrutura, com tg_movimento_imutavel como segunda barreira.
create policy movimento_estoque_sel on public.movimento_estoque
  for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('estoque.ler'));

create policy movimento_estoque_ins on public.movimento_estoque
  for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual() and (
       (tipo = 'ENTRADA' and public.tem_permissao('compras.receber'))
    or (tipo = 'SAIDA'   and public.tem_permissao('estoque.lancar_saida'))
    or (tipo = 'AJUSTE'  and public.tem_permissao('estoque.ajustar'))
    or (tipo = 'ESTORNO' and public.tem_permissao('estoque.estornar'))));

-- 8.4 pedido_compra e pedido_item — padrão, com duas diferenças escritas:
--     `pedido_compra` sem delete (pedido vira CANCELADO) e o update das duas
--     aceitando `compras.receber`, porque fn_pedido_receber (card 6.5) escreve
--     `qtd_recebida` e o `status` do pedido na transação de quem recebe.
create policy pedido_compra_sel on public.pedido_compra for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('compras.ler'));

create policy pedido_compra_ins on public.pedido_compra for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('compras.criar'));

create policy pedido_compra_upd on public.pedido_compra for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('compras.editar')
                   or public.tem_permissao('compras.receber')))
  with check (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('compras.editar')
                   or public.tem_permissao('compras.receber')));

create policy pedido_item_sel on public.pedido_item for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('compras.ler'));

create policy pedido_item_ins on public.pedido_item for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('compras.criar')
                   or public.tem_permissao('compras.editar')));

create policy pedido_item_upd on public.pedido_item for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('compras.editar')
                   or public.tem_permissao('compras.receber')))
  with check (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('compras.editar')
                   or public.tem_permissao('compras.receber')));

create policy pedido_item_del on public.pedido_item for delete to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('compras.excluir'));

-- -----------------------------------------------------------------------------
-- 9. RLS não é por coluna — a folga que o `or` do update de aluno_material abre
-- -----------------------------------------------------------------------------
-- O card 4.2 fechou este buraco em `aluno`, o 5.1 em `bloco_aluno` e
-- `bloco_aluno_reposicao`, e os dois deixaram escrito que ele reaparece em toda
-- tabela cuja política única cobre colunas de donos diferentes. É o caso aqui, e
-- o perfil que o expõe EXISTE na matriz inicial: o **monitor** tem
-- `estoque.lancar_saida` e `estoque.estornar` e NÃO tem `alunos.editar_trilha`
-- (card 2.4 §5). Com um PATCH no PostgREST ele poderia hoje:
--   • mudar `ordem` — reordenando a trilha sem passar pelas funções do card 6.2
--     e, portanto, sem escrever `aluno_material_hist`: a trilha sairia da ordem
--     do combo sem NADA registrando por quê, que é exatamente o silêncio que a
--     tabela de histórico existe para impedir;
--   • mudar `material_id` — trocando a apostila devida por outra, inclusive de
--     outro método;
--   • mudar `origem` de COMBO para MANUAL, tirando a linha do alcance da
--     regeneração da trilha do card 6.2.
-- Nenhuma dessas é entrega, e entrega é a única coisa que o `or` existe para
-- permitir.
create or replace function public.fn_aluno_material_colunas_permitidas()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  -- As três colunas de fora da lista são exatamente as que fn_registrar_entrega
  -- e fn_estornar_entrega (card 6.3) escrevem: `entregue`, `data_entrega` e
  -- `movimento_estoque_id`. Tudo o mais é edição de trilha.
  if new.aluno_id    is distinct from old.aluno_id
     or new.material_id is distinct from old.material_id
     or new.ordem       is distinct from old.ordem
     or new.origem      is distinct from old.origem then
    perform public.fn_exige_permissao('alunos.editar_trilha');
  end if;

  return new;
end $$;

comment on function public.fn_aluno_material_colunas_permitidas() is
  'Trigger BEFORE UPDATE em aluno_material: sob estoque.lancar_saida/estoque.estornar só se escreve a ENTREGA (entregue, data_entrega, movimento_estoque_id); mexer em aluno, material, ordem ou origem exige alunos.editar_trilha. Onde a permissão é por coluna, a RLS é a segunda barreira e o trigger é a primeira (cards 2.4, 4.2 e 5.1).';

revoke execute on function public.fn_aluno_material_colunas_permitidas() from public;
revoke execute on function public.fn_aluno_material_colunas_permitidas() from anon;

create trigger tg_aluno_material_colunas_permitidas
  before update on public.aluno_material
  for each row execute function public.fn_aluno_material_colunas_permitidas();

-- -----------------------------------------------------------------------------
-- 10. As duas guardas de exclusão (família do card 4.3)
-- -----------------------------------------------------------------------------
-- 10.1 Item de trilha já entregue não se apaga.
--
-- O catálogo do card 2.4 §3.3 descreve `alunos.editar_trilha` como "reordenar,
-- incluir e REMOVER item da trilha", e o §6.1 do card 2.2 diz que as três
-- operações "recusam mexer em item já entregue (PT409 / ITEM_JA_ENTREGUE)".
-- Nada no schema fazia isso valer para o DELETE, e o desfecho é silencioso:
-- `aluno_material.movimento_estoque_id` aponta para o movimento, não o
-- contrário, então apagar a linha entregue NÃO derruba a SAIDA — o saldo
-- continua certo e a TRILHA passa a discordar dele. A apostila some da trilha
-- como se nunca tivesse sido devida, e nada impede que ela seja incluída de novo
-- e ENTREGUE OUTRA VEZ: duas saídas do mesmo livro para a mesma pessoa, cada uma
-- com a cara de uma entrega legítima.
--
-- Não fecha a exclusão, fecha a exclusão COM ENTREGA: item incluído por engano,
-- ainda pendente, continua apagável — é o que mantém o "remover" de
-- `alunos.editar_trilha` com um uso real. O caminho para o item entregue é
-- estornar a entrega (card 6.3) e só então remover.
--
-- Código reaproveitado de propósito: `ITEM_JA_ENTREGUE` já está no contrato
-- desde o card 2.2 §12 e a mensagem do catálogo Dart já diz o certo. Criar um
-- código novo para a mesma frase seria o que a nota do card 6.1 recusa fazer com
-- `METODO_INCOMPATIVEL`, invertido.
create or replace function public.fn_aluno_material_exclusao_valida()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if old.entregue then
    raise exception using
      errcode = 'PT409',
      message = 'Esta apostila já foi entregue e não pode ser removida da trilha. Estorne a entrega primeiro.',
      detail  = json_build_object('codigo', 'ITEM_JA_ENTREGUE',
                                  'aluno_material', old.id,
                                  'data_entrega', old.data_entrega)::text;
  end if;

  return old;
end $$;

comment on function public.fn_aluno_material_exclusao_valida() is
  'Trigger BEFORE DELETE em aluno_material: recusa (PT409 / ITEM_JA_ENTREGUE) apagar item já entregue, que levaria embora a única ligação entre a SAIDA de estoque e o aluno que a recebeu. Item pendente continua removível.';

revoke execute on function public.fn_aluno_material_exclusao_valida() from public;
revoke execute on function public.fn_aluno_material_exclusao_valida() from anon;
grant  execute on function public.fn_aluno_material_exclusao_valida() to authenticated;

create trigger tg_aluno_material_exclusao_valida
  before delete on public.aluno_material
  for each row execute function public.fn_aluno_material_exclusao_valida();

-- 10.2 Item de pedido só se remove enquanto o pedido é RASCUNHO.
--
-- O catálogo do card 2.4 §3.5 descreve `compras.excluir` como "remover item de
-- pedido em RASCUNHO", e nada no schema fazia isso valer. É a MESMA operação com
-- dois desfechos opostos que o card 5.1 descreveu:
--   • item já recebido tem movimento apontando para ele, e a FK
--     `movimento_pedido_item_fk` é RESTRICT — o delete morre num `23503` cru,
--     ilegível na tela;
--   • item de um pedido ENVIADO ainda sem recebimento nenhum some em SILÊNCIO, e
--     com ele a parcela "já pedida" que o pedido sugerido do card 2.3 abate: o
--     sistema passa a sugerir comprar de novo o que já está a caminho.
-- O silencioso é o pior dos dois, e é o que nada denunciaria.
create or replace function public.fn_pedido_item_exclusao_valida()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_status      text;
  v_movimentos  bigint;
begin
  select status into v_status
    from public.pedido_compra where id = old.pedido_id;

  select count(*) into v_movimentos
    from public.movimento_estoque where pedido_item_id = old.id;

  if v_status is distinct from 'RASCUNHO' or v_movimentos > 0 then
    raise exception using
      errcode = 'PT409',
      message = 'Só dá para remover item de pedido em rascunho. Cancele o pedido ou ajuste as quantidades.',
      detail  = json_build_object('codigo', 'PEDIDO_NAO_RASCUNHO',
                                  'pedido_item', old.id,
                                  'status', v_status,
                                  'movimentos', v_movimentos)::text;
  end if;

  return old;
end $$;

-- `security invoker` (o default), como fn_pc_exclusao_valida (4.3) e
-- fn_bloco_exclusao_valida (5.1) e pela mesma razão: só conta linhas que o
-- próprio chamador já pode ler — quem tem `compras.excluir` tem `compras.ler`,
-- e `estoque.ler` acompanha os dois na matriz do card 2.4 §5. Entrar na lista
-- fechada do C8 sem necessidade gasta a revisão consciente que a lista existe
-- para provocar.
comment on function public.fn_pedido_item_exclusao_valida() is
  'Trigger BEFORE DELETE em pedido_item: recusa (PT409 / PEDIDO_NAO_RASCUNHO) remover item de pedido que já saiu de RASCUNHO ou que já tem movimento de estoque. Faz valer o "em RASCUNHO" do card 2.4 §3.5, que sumia em silêncio e levava junto a parcela já pedida do pedido sugerido.';

revoke execute on function public.fn_pedido_item_exclusao_valida() from public;
revoke execute on function public.fn_pedido_item_exclusao_valida() from anon;
grant  execute on function public.fn_pedido_item_exclusao_valida() to authenticated;

create trigger tg_pedido_item_exclusao_valida
  before delete on public.pedido_item
  for each row execute function public.fn_pedido_item_exclusao_valida();

-- -----------------------------------------------------------------------------
-- 11. Coerência de método na composição do catálogo (pendência 9.11)
-- -----------------------------------------------------------------------------
-- Transferida pelo card 4.4 (02/09/2026) e atribuída a ESTE card porque é ele
-- quem consome a cadeia combo → curso → material para gerar a trilha (6.2):
-- nada no banco impede `curso_material`, `modulo` e `combo_curso` de CRUZAREM
-- métodos — apostila de Inglês na sequência de um curso Interativo, curso
-- Modular dentro de um combo Interativo. A tela do 4.4 filtra os candidatos pelo
-- método do pai e não deixa trocar o método depois de criado, mas **tela não é
-- regra** (card 2.6, decisão 2) e um `POST` direto no PostgREST passa.
--
-- A consequência não é um erro: é uma trilha coerente para o banco e absurda
-- para a escola. O aluno de Informática receberia English Book 2 como próximo
-- livro, `METODO_INCOMPATIVEL` nunca dispararia (ele compara o método do ALUNO
-- com o da TURMA, card 5.3) e a projeção de demanda do card 8.1 pediria a
-- compra da apostila errada — cada peça funcionando exatamente como escrita.
--
-- Código de erro NOVO, como a nota do card manda: `METODO_INCOMPATIVEL` existe
-- desde o card 2.2 §12 com a mensagem "o método do aluno não é o método desta
-- turma", que aqui seria falsa em toda palavra.
create or replace function public.fn_composicao_metodo_coerente()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_metodo_pai    uuid;
  v_metodo_filho  uuid;
  v_rotulo_pai    text;
  v_rotulo_filho  text;
begin
  case tg_table_name
    when 'curso_material' then
      select metodo_id into v_metodo_pai   from public.curso    where id = new.curso_id;
      select metodo_id into v_metodo_filho from public.material where id = new.material_id;
      v_rotulo_pai := 'curso'; v_rotulo_filho := 'material';
    when 'modulo' then
      select metodo_id into v_metodo_pai   from public.curso    where id = new.curso_id;
      select metodo_id into v_metodo_filho from public.material where id = new.material_id;
      v_rotulo_pai := 'curso'; v_rotulo_filho := 'material';
    when 'combo_curso' then
      select metodo_id into v_metodo_pai   from public.combo where id = new.combo_id;
      select metodo_id into v_metodo_filho from public.curso where id = new.curso_id;
      v_rotulo_pai := 'combo'; v_rotulo_filho := 'curso';
    else
      -- Fail-closed, e com o nome da tabela dentro: pendurar este trigger numa
      -- tabela nova sem acrescentar o ramo dela aqui morreria em CASE_NOT_FOUND,
      -- que é uma mensagem que não diz nem qual tabela nem o que fazer.
      raise exception
        'fn_composicao_metodo_coerente nao sabe ler a composicao de %; acrescente o ramo dela.',
        tg_table_name;
  end case;

  -- Nulo é ERRO e não "sem opinião", pela lição do card 5.3 (decisão 1): as duas
  -- consultas acima são `security invoker`, então a RLS pode devolver NENHUMA
  -- linha para um pai ou filho de OUTRA unidade — e `a is distinct from b` com
  -- um nulo é verdadeiro, o que aqui já reprova. O `if` abaixo é escrito com
  -- `is distinct from` de propósito: com `<>` o nulo passaria em silêncio, que é
  -- exatamente a escrita que não deveria existir.
  if v_metodo_pai is distinct from v_metodo_filho then
    raise exception using
      errcode = 'PT409',
      message = format('O %s escolhido é de outro método. A composição do catálogo não pode misturar métodos.',
                       v_rotulo_filho),
      detail  = json_build_object('codigo', 'COMPOSICAO_METODO_DIVERGENTE',
                                  'tabela', tg_table_name,
                                  'pai', v_rotulo_pai,
                                  'metodo_pai', v_metodo_pai,
                                  'filho', v_rotulo_filho,
                                  'metodo_filho', v_metodo_filho)::text;
  end if;

  return new;
end $$;

comment on function public.fn_composicao_metodo_coerente() is
  'Trigger BEFORE INSERT OR UPDATE em curso_material, modulo e combo_curso: pai e filho da composição têm de ser do MESMO método (PT409 / COMPOSICAO_METODO_DIVERGENTE). Fecha a pendência 9.11, aberta pelo card 4.4: a tela filtrava, o banco não — e a trilha resultante seria coerente para o banco e absurda para a escola.';

revoke execute on function public.fn_composicao_metodo_coerente() from public;
revoke execute on function public.fn_composicao_metodo_coerente() from anon;

create trigger tg_curso_material_metodo_coerente
  before insert or update on public.curso_material
  for each row execute function public.fn_composicao_metodo_coerente();

create trigger tg_modulo_metodo_coerente
  before insert or update on public.modulo
  for each row execute function public.fn_composicao_metodo_coerente();

create trigger tg_combo_curso_metodo_coerente
  before insert or update on public.combo_curso
  for each row execute function public.fn_composicao_metodo_coerente();
