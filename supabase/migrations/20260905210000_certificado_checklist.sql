-- =============================================================================
-- Card 8.3 — Checklist de certificado automático no FIM e sugestão de FORMADO
--
-- Fontes: docs/modelagem-dados-ddl.md §10 (a tabela) e §11 (o mapa),
--         docs/regras-negocio-funcoes.md §8 (as três funções e os dois
--         triggers), §6.2 passo 9 e §6.3 passo 5 (os dois enxertos na entrega e
--         no estorno), §10.1 (SUGERIR_FORMADO e CERTIFICADO_INCONSISTENTE),
--         §14 ajuste 3 (formatura_por/_em),
--         docs/permissoes-matriz.md §4 (as três políticas), §5 (a matriz) e §7
--         achados 3 e 8 (os dois BLOQUEANTES que este card fecha),
--         docs/estrategia-testes.md §13 (obrigação de teste de Função/regra).
--
-- Esta migração fecha QUATRO portões que outros cards deixaram armados, e é por
-- isso que ela toca função que não criou:
--
--   (a) teste 030 §6 — `fn_aluno_pode_formar` tinha só a metade da PERMISSÃO; a
--       metade do certificado ENTREGUE não podia ser escrita porque a tabela não
--       existia. Nasceu aqui, e o portão reprova enquanto a função não a citar;
--   (b) teste 052 §11 — `fn_registrar_entrega` (passo 9) e `fn_estornar_entrega`
--       (passo 5) tinham o tratamento do checklist adiado pela mesma razão;
--   (c) teste 001 §7 — a camada `certificados` da escola-fixture era a sentinela
--       do portão das camadas, e passa a ser APLICADA (ver a divergência 2 abaixo);
--   (d) `permissoes-matriz.md` §7 achado 8 (alta) — RLS não é por coluna: com
--       `certificados.marcar_financeiro` o monitor `PATCH`aria `pedagogico_ok`
--       direto no PostgREST. É o que `tg_certificado_colunas_permitidas` fecha.
--
-- ⚠️ ESTRUTURA E MAIS NADA.
--    Decisão de 02/09/2026 (Irineu): dado de negócio não entra em
--    supabase/migrations/. Nenhum checklist real é escrito aqui — eles nascem de
--    `fn_certificado_abrir`, chamada pela entrega que fecha a trilha. O checklist
--    de teste é da escola-fixture (supabase/seed.sql, camada `certificados`), que
--    nunca sai do stack local. O portão do card 4.0,5 tem esta tabela FORA da
--    lista permitida, e é assim que deve ficar.
--
-- Três códigos de erro novos, todos no fixture `test/fixtures/codigos_erro.txt`
-- e no catálogo do app (contrato do card 2.8 §10):
--   • CERTIFICADO_INEXISTENTE (404) — vale também para aluno de OUTRA unidade,
--     pelo precedente de PC_INEXISTENTE / MOVIMENTO_INEXISTENTE: quem não pode
--     ver não descobre que existe;
--   • ITEM_CERTIFICADO_INVALIDO (422)  — `p_item` fora dos três;
--   • STATUS_CERTIFICADO_INVALIDO (422) — `p_status` fora dos três.
--
-- ⚠️ DIVERGÊNCIA REGISTRADA 1 — a assinatura do §8 conflita consigo mesma e com
--    o C6. Ela escreve `fn_certificado_abrir(p_aluno_id uuid, p_data_fim_curso
--    date default current_date)` e, na linha seguinte, «default = data da última
--    entrega da trilha». As duas coisas não podem ser verdade, e `current_date`
--    em default de PARÂMETRO é exatamente o que o C6 varre em `proargdefaults`
--    desde o card 5.2. Aqui o default é `null`, e o corpo resolve na ordem que o
--    comentário do documento pede: data da última entrega → `fn_hoje()`.
--
-- ⚠️ DIVERGÊNCIA REGISTRADA 2 — a QUARTA função. O §8 lista três
--    (`_abrir`, `_marcar`, `_status`); esta migração traz uma quarta,
--    `fn_certificado_reavaliar_estorno`, e ela não é escopo inventado: é o passo
--    5 do §6.3 escrito onde ele pode funcionar. `certificado_checklist` não tem
--    política de DELETE para ninguém (card 2.4 §4), e `fn_estornar_entrega` é
--    `invoker` — o `delete` de dentro dela afetaria ZERO linhas, sem erro nenhum,
--    que é a redução silenciosa do card 2.3 §3.4. É o mesmo desenho, e o mesmo
--    motivo, de `fn_pendencia_abrir`/`fn_pendencia_resolver` no card 5.5. Mesma
--    forma do card 6.3, que também saiu com duas funções a mais do que o §6.2
--    previa (`fn_contexto_entrega`, `fn_trilha_reposicionar`).
--
-- ⚠️ DIVERGÊNCIA REGISTRADA 3 — `fn_aluno_formado_fecha_pendencias`, o trigger
--    que fecha ALUNO_ULTIMO_LIVRO e SUGERIR_FORMADO quando o aluno vira FORMADO.
--    O §10.1 já dizia, para as duas linhas, «fechada por: formatura» — e não
--    havia código nenhum fazendo isso: só a metade do estorno existia (card 6.3).
--    Abrir SUGERIR_FORMADO sem fechá-la deixaria a central do card 5.8 sugerindo
--    para sempre que se forme quem já está FORMADO, que é a mesma perda de
--    credibilidade que o card 6.3 evitou no outro lado.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. certificado_checklist (§10 do DDL do card 2.1, com o ajuste 3 do §14 do 2.2)
-- -----------------------------------------------------------------------------
-- O ajuste 3 entra DIRETO, sem `alter`, pela mesma razão que o card 5.5 deu ao
-- `check` de `pendencia.tipo`: a tabela NASCE aqui, e um `create table` sem o par
-- `formatura_por/_em` seguido de um `add column` no mesmo arquivo seria cerimônia
-- sem leitor. O que o ajuste corrige é real: o DDL dava par "quem/quando" a
-- `pedagogico`, `financeiro` e `certificado` e não a `formatura`, e o plano exige
-- que CADA item registre quem marcou e quando.
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
  formatura_por      uuid references public.usuario(id),   -- ajuste 3 do §14
  formatura_em       timestamptz,                          -- ajuste 3 do §14
  certificado_status text not null default 'NAO_PEDIDO'
                     check (certificado_status in ('NAO_PEDIDO','PEDIDO','ENTREGUE')),
  certificado_por    uuid references public.usuario(id),
  certificado_em     timestamptz,
  observacoes text,
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint certificado_checklist_aluno_uk unique (aluno_id)
);

comment on table public.certificado_checklist is
  'Checklist do certificado de um aluno (§5.8 do plano). Criado AUTOMATICAMENTE quando a última apostila da trilha é entregue (fn_certificado_abrir, dentro da transação de fn_registrar_entrega), e apagado pelo estorno que tira o aluno do FIM — só enquanto nenhum item tiver sido marcado. Uma linha por aluno (certificado_checklist_aluno_uk). NÃO se migra da planilha: a aba Certificados não guarda quem marcou nem quando, que é justamente o que esta tabela existe para guardar.';

comment on column public.certificado_checklist.data_fim_curso is
  'Data em que a trilha chegou ao FIM. `not null`, e é por isso que fn_certificado_abrir a resolve em vez de aceitar nulo: data da última entrega da trilha e, na falta dela, fn_hoje(). Nunca `current_date` — o Postgres do Supabase roda em UTC e depois das 21h a data cairia no dia seguinte (C6).';

comment on column public.certificado_checklist.formatura is
  'Único item do checklist que NÃO é uma condição de emissão: é a presença na cerimônia. Ganhou o par formatura_por/_em no card 8.3 (ajuste 3 do §14 do card 2.2) — sem ele seria o único dos quatro itens sem rastro de quem marcou.';

comment on column public.certificado_checklist.certificado_status is
  'NAO_PEDIDO → PEDIDO → ENTREGUE, alterado só por fn_certificado_status (certificados.alterar_status). ENTREGUE é a condição (1) do gate de FORMADO (card 2.2 §3.3): com ele, formar o aluno dispensa alunos.formar_sem_certificado.';

-- -----------------------------------------------------------------------------
-- 2. Índices
-- -----------------------------------------------------------------------------
-- `aluno_id` já tem índice: é a `certificado_checklist_aluno_uk`. O que falta são
-- os lados de FK que nenhuma unique cobre — mesma razão dos cards 3.3, 4.1, 4.3,
-- 5.1 e 6.1, e o precedente literal é `aluno_material_hist_usuario_ix`.
create index certificado_pedagogico_por_ix  on public.certificado_checklist (pedagogico_por);
create index certificado_financeiro_por_ix  on public.certificado_checklist (financeiro_por);
create index certificado_formatura_por_ix   on public.certificado_checklist (formatura_por);
create index certificado_certificado_por_ix on public.certificado_checklist (certificado_por);

-- A fila da tela do card 8.6 abre por unidade e ordena por data de fim de curso.
-- Precaução barata, não otimização medida (card 2.3 §13 (2)).
create index certificado_unidade_ix
  on public.certificado_checklist (unidade_id, data_fim_curso);

-- -----------------------------------------------------------------------------
-- 3. Trigger de auditoria (C3 do card 2.8)
-- -----------------------------------------------------------------------------
create trigger tg_auditoria_certificado_checklist
  before insert or update on public.certificado_checklist
  for each row execute function public.fn_auditoria();

-- -----------------------------------------------------------------------------
-- 4. RLS habilitada, forçada, e as três políticas do card 2.4 §4
-- -----------------------------------------------------------------------------
alter table public.certificado_checklist enable row level security;
alter table public.certificado_checklist force  row level security;

create policy certificado_checklist_sel on public.certificado_checklist
  for select to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('certificados.ler'));

-- `certificados.criar` para o monitor e a secretaria não é generosidade: é o
-- achado 3 do §7 do card 2.4, e ele é BLOQUEANTE. Quem registra a entrega que
-- fecha a trilha é quem abre o checklist, porque fn_certificado_abrir roda na
-- MESMA transação de fn_registrar_entrega. A matriz inicial já está certa —
-- `estoque.lancar_saida` e `certificados.criar` estão exatamente nos mesmos três
-- perfis (DIREÇÃO, SECRETARIA, MONITOR) —, e o teste 081 §2 assere essa
-- interseção contra o SEED, para que editar a matriz na tela do card 4.7 e
-- quebrar a entrega apareça como asserção e não como chamado de suporte.
create policy certificado_checklist_ins on public.certificado_checklist
  for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('certificados.criar'));

-- O `or` de três códigos é o que o card 2.4 §4 escreve, e é justamente ele que
-- torna a guarda de coluna da seção 8 obrigatória: como política, os três dão
-- acesso à LINHA inteira, e RLS não é por coluna.
create policy certificado_checklist_upd on public.certificado_checklist
  for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('certificados.marcar_pedagogico')
                or public.tem_permissao('certificados.marcar_financeiro')
                or public.tem_permissao('certificados.alterar_status')))
  with check (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('certificados.marcar_pedagogico')
                or public.tem_permissao('certificados.marcar_financeiro')
                or public.tem_permissao('certificados.alterar_status')));

-- Sem DELETE, e a ausência é a decisão (card 2.4 §4): checklist que a secretaria
-- já trabalhou não some. O único apagamento legítimo — o estorno que tira o aluno
-- do FIM antes de qualquer item marcado — é da seção 7, `security definer`, e
-- justamente por isso ele não precisa (nem deve) de política aberta a ninguém.

-- -----------------------------------------------------------------------------
-- 5. fn_certificado_abrir (§8) — idempotente, e é o passo 9 da entrega
-- -----------------------------------------------------------------------------
-- `invoker` de propósito, e a alternativa foi considerada: definer resolveria o
-- achado 3 sozinho, mas tiraria `certificados.criar` de circulação — o código
-- existiria no catálogo sem guardar nada, que é o que o C11 chama de "catalogado
-- e não usado". A permissão é conferida no TOPO, com fn_exige_permissao, e não
-- deixada para a RLS: sem isso, quem não a tem receberia um `42501` cru vindo de
-- uma tela que fala de entrega de apostila, e o card 2.2 §1.2 proíbe erro cru em
-- tela.
create or replace function public.fn_certificado_abrir(
  p_aluno_id       uuid,
  p_data_fim_curso date default null
)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_data    date;
  v_id      uuid;
begin
  perform public.fn_exige_permissao('certificados.criar');

  -- A leitura é `invoker`: aluno de outra unidade é indistinguível de
  -- inexistente, pelo precedente de PC_INEXISTENTE (2.9), BLOCO_INEXISTENTE
  -- (5.3) e MOVIMENTO_INEXISTENTE (6.3).
  select a.unidade_id into v_unidade
    from public.aluno a
   where a.id = p_aluno_id;

  if v_unidade is null then
    raise exception using
      errcode = 'PT404',
      message = 'Este aluno não foi encontrado.',
      detail  = json_build_object('codigo', 'ALUNO_INEXISTENTE',
                                  'aluno', p_aluno_id)::text;
  end if;

  -- `data_fim_curso` é NOT NULL, e a ordem de resolução é a do §8: a data da
  -- ÚLTIMA entrega da trilha e, na falta dela (checklist aberto à mão antes de
  -- qualquer entrega), fn_hoje() — nunca a data do servidor, que roda em UTC e
  -- viraria depois das 21h (C6, e ver o comentário da coluna).
  v_data := coalesce(
    p_data_fim_curso,
    (select max(am.data_entrega)
       from public.aluno_material am
      where am.aluno_id = p_aluno_id and am.entregue),
    public.fn_hoje());

  -- Idempotente por construção (§8): a entrega chama isto toda vez que a trilha
  -- fecha, e o estorno seguido de nova entrega passaria por aqui de novo. Com
  -- `do nothing` a segunda chamada NÃO reescreve nada — em especial não zera item
  -- que alguém já marcou, que é a informação mais cara desta tabela.
  insert into public.certificado_checklist (unidade_id, aluno_id, data_fim_curso)
  values (v_unidade, p_aluno_id, v_data)
      on conflict (aluno_id) do nothing
   returning id into v_id;

  -- `do nothing` não devolve linha. A função promete o id do checklist — novo ou
  -- preexistente —, então busca, exatamente como fn_pendencia_abrir (card 5.5).
  if v_id is null then
    select cc.id into v_id
      from public.certificado_checklist cc
     where cc.aluno_id = p_aluno_id;
  end if;

  return v_id;
end $$;

comment on function public.fn_certificado_abrir(uuid, date) is
  'Abre o checklist do certificado do aluno, ou devolve o que já existe (idempotente, card 2.2 §8). Exige certificados.criar. Chamada por fn_registrar_entrega no passo 9 do §6.2, dentro da MESMA transação — é por isso que o monitor precisa da permissão (achado 3 do card 2.4 §7).';

revoke execute on function public.fn_certificado_abrir(uuid, date) from public;
revoke execute on function public.fn_certificado_abrir(uuid, date) from anon;
grant  execute on function public.fn_certificado_abrir(uuid, date) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. fn_certificado_marcar e fn_certificado_status (§8)
-- -----------------------------------------------------------------------------
-- A permissão POR ITEM está escrita aqui e, de novo, no trigger da seção 8. Não é
-- redundância: aqui ela dá a mensagem do catálogo a quem chama a função, e lá ela
-- alcança o `PATCH` direto no PostgREST, que não passa por função nenhuma.
create or replace function public.fn_certificado_marcar(
  p_aluno_id uuid,
  p_item     text,
  p_valor    boolean
)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if p_item is null or p_item not in ('PEDAGOGICO', 'FINANCEIRO', 'FORMATURA') then
    raise exception using
      errcode = 'PT422',
      message = 'Item do checklist inválido: use PEDAGOGICO, FINANCEIRO ou FORMATURA.',
      detail  = json_build_object('codigo', 'ITEM_CERTIFICADO_INVALIDO',
                                  'item', p_item)::text;
  end if;

  -- FORMATURA anda com PEDAGOGICO, e é o §8 que diz isso: os dois são do
  -- pedagógico, o FINANCEIRO é do monitor. A separação existe porque marcar
  -- "financeiro OK" é a única do checklist que o monitor faz.
  if p_item = 'FINANCEIRO' then
    perform public.fn_exige_permissao('certificados.marcar_financeiro');
  else
    perform public.fn_exige_permissao('certificados.marcar_pedagogico');
  end if;

  select cc.id into v_id
    from public.certificado_checklist cc
   where cc.aluno_id = p_aluno_id;

  if v_id is null then
    raise exception using
      errcode = 'PT404',
      message = 'Este aluno ainda não tem checklist de certificado.',
      detail  = json_build_object('codigo', 'CERTIFICADO_INEXISTENTE',
                                  'aluno', p_aluno_id)::text;
  end if;

  -- `coalesce(p_valor, false)`: a coluna é `not null` e um nulo vindo da tela
  -- chegaria como violação de constraint — erro cru, que o §1.2 proíbe. Desmarcar
  -- é caso legítimo (o pedagógico marcou o aluno errado), e é por isso que a
  -- função aceita `false` em vez de só somar marcas.
  update public.certificado_checklist cc
     set pedagogico_ok = case when p_item = 'PEDAGOGICO' then coalesce(p_valor, false) else cc.pedagogico_ok end,
         financeiro_ok = case when p_item = 'FINANCEIRO' then coalesce(p_valor, false) else cc.financeiro_ok end,
         formatura     = case when p_item = 'FORMATURA'  then coalesce(p_valor, false) else cc.formatura     end
   where cc.id = v_id;
end $$;

comment on function public.fn_certificado_marcar(uuid, text, boolean) is
  'Marca ou desmarca um item do checklist (card 2.2 §8). PEDAGOGICO e FORMATURA exigem certificados.marcar_pedagogico; FINANCEIRO exige certificados.marcar_financeiro. Quem marcou e quando são gravados por tg_certificado_quem_quando, nunca pelo chamador.';

revoke execute on function public.fn_certificado_marcar(uuid, text, boolean) from public;
revoke execute on function public.fn_certificado_marcar(uuid, text, boolean) from anon;
grant  execute on function public.fn_certificado_marcar(uuid, text, boolean) to authenticated;

create or replace function public.fn_certificado_status(
  p_aluno_id uuid,
  p_status   text
)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if p_status is null or p_status not in ('NAO_PEDIDO', 'PEDIDO', 'ENTREGUE') then
    raise exception using
      errcode = 'PT422',
      message = 'Status de certificado inválido: use NAO_PEDIDO, PEDIDO ou ENTREGUE.',
      detail  = json_build_object('codigo', 'STATUS_CERTIFICADO_INVALIDO',
                                  'status', p_status)::text;
  end if;

  perform public.fn_exige_permissao('certificados.alterar_status');

  select cc.id into v_id
    from public.certificado_checklist cc
   where cc.aluno_id = p_aluno_id;

  if v_id is null then
    raise exception using
      errcode = 'PT404',
      message = 'Este aluno ainda não tem checklist de certificado.',
      detail  = json_build_object('codigo', 'CERTIFICADO_INEXISTENTE',
                                  'aluno', p_aluno_id)::text;
  end if;

  -- ⚠️ NÃO há máquina de estados aqui, e a ausência é decisão. O §8 escreve a
  --    sequência NAO_PEDIDO → PEDIDO → ENTREGUE, mas não a declara irreversível:
  --    "pedido por engano" e "entregue e devolvido para correção do nome" são
  --    casos reais da secretaria, e barrá-los obrigaria a inventar um estorno de
  --    certificado que ninguém pediu. O que a volta NÃO desfaz é a formatura já
  --    ocorrida — e a pendência SUGERIR_FORMADO que ela abriu continua aberta até
  --    alguém formar o aluno ou fechá-la à mão, que é o comportamento correto.
  update public.certificado_checklist cc
     set certificado_status = p_status
   where cc.id = v_id;
end $$;

comment on function public.fn_certificado_status(uuid, text) is
  'Altera o status do certificado (NAO_PEDIDO | PEDIDO | ENTREGUE), exigindo certificados.alterar_status (card 2.2 §8). ENTREGUE é a condição (1) do gate de FORMADO. A volta é permitida de propósito — ver o comentário no corpo.';

revoke execute on function public.fn_certificado_status(uuid, text) from public;
revoke execute on function public.fn_certificado_status(uuid, text) from anon;
grant  execute on function public.fn_certificado_status(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 7. fn_certificado_reavaliar_estorno — o passo 5 do §6.3 (divergência 2)
-- -----------------------------------------------------------------------------
-- `security definer` pelo motivo exato de fn_pendencia_abrir (card 5.5): esta
-- função é chamada como EFEITO COLATERAL, dentro da transação de quem estorna
-- (`estoque.estornar`, hoje direção e secretaria). Ela precisa APAGAR uma linha de
-- uma tabela que não tem política de delete para ninguém — como `invoker`, o
-- `delete` afetaria zero linhas e não levantaria erro nenhum, deixando um
-- checklist aberto para um aluno que voltou a ter livro pendente. É a redução
-- silenciosa do card 2.3 §3.4, na tabela que a fila do card 8.6 lê.
--
-- Filtra a unidade no corpo (fn_unidade_atual) e trata unidade nula como ERRO,
-- como manda a correção do card 2.3 e a lição do card 5.3.
create or replace function public.fn_certificado_reavaliar_estorno(p_aluno_id uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_cc      public.certificado_checklist%rowtype;
begin
  v_unidade := public.fn_unidade_atual();

  if v_unidade is null then
    raise exception
      'fn_certificado_reavaliar_estorno: sem unidade no contexto (nem sessão autenticada nem contexto de rotina).';
  end if;

  select * into v_cc
    from public.certificado_checklist cc
   where cc.aluno_id = p_aluno_id
     and cc.unidade_id = v_unidade;

  if not found then
    return 'NENHUM';
  end if;

  -- "Nenhum item marcado" inclui o STATUS: um certificado já PEDIDO é trabalho
  -- da secretaria mesmo com os três itens em false, e apagar a linha perderia o
  -- fato de que alguém pediu.
  if v_cc.pedagogico_ok or v_cc.financeiro_ok or v_cc.formatura
     or v_cc.certificado_status <> 'NAO_PEDIDO' then
    perform public.fn_pendencia_abrir(
      'CERTIFICADO_INCONSISTENTE',
      'CERT_INCONS:' || p_aluno_id::text,
      'O aluno saiu do FIM por estorno, mas o checklist do certificado já tinha item marcado. Confira antes de emitir.',
      'MEDIA',
      p_aluno_id);
    return 'MANTIDO_INCONSISTENTE';
  end if;

  delete from public.certificado_checklist cc
   where cc.id = v_cc.id;

  return 'APAGADO';
end $$;

comment on function public.fn_certificado_reavaliar_estorno(uuid) is
  'Passo 5 do §6.3 do card 2.2: chamada por fn_estornar_entrega quando o aluno SAI do FIM. Apaga o checklist se nenhum item tiver sido marcado e o status ainda for NAO_PEDIDO; senão mantém e abre CERTIFICADO_INCONSISTENTE. Devolve APAGADO | MANTIDO_INCONSISTENTE | NENHUM. SECURITY DEFINER porque a tabela não tem política de delete para ninguém e o chamador é invoker — como invoker, o delete afetaria zero linhas em silêncio.';

revoke execute on function public.fn_certificado_reavaliar_estorno(uuid) from public;
revoke execute on function public.fn_certificado_reavaliar_estorno(uuid) from anon;
grant  execute on function public.fn_certificado_reavaliar_estorno(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 8. tg_certificado_colunas_permitidas — achado 8 do card 2.4 §7 (alta)
-- -----------------------------------------------------------------------------
-- RLS não é por coluna. A política de update aceita o `or` de três permissões, e
-- sozinha ela deixa o monitor — que tem `certificados.marcar_financeiro` — mandar
-- um `PATCH` com `pedagogico_ok = true` direto no PostgREST, sem passar por
-- fn_certificado_marcar. Mesma forma da guarda de `aluno_material` (6.1), de
-- `bloco_aluno` (5.1) e de `turma_modular_aluno` (7.1): onde a permissão é por
-- coluna, a RLS é a segunda barreira e o trigger é a primeira.
--
-- Roda ANTES de tg_certificado_quem_quando porque o Postgres dispara triggers de
-- mesmo momento em ordem ALFABÉTICA de nome, e `colunas` < `quem` — a ordem
-- importa: recusar antes de carimbar autoria é o que evita gravar "quem marcou"
-- de uma marcação que será recusada.
create or replace function public.fn_certificado_colunas_permitidas()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.pedagogico_ok is distinct from old.pedagogico_ok
     or new.formatura is distinct from old.formatura then
    perform public.fn_exige_permissao('certificados.marcar_pedagogico');
  end if;

  if new.financeiro_ok is distinct from old.financeiro_ok then
    perform public.fn_exige_permissao('certificados.marcar_financeiro');
  end if;

  if new.certificado_status is distinct from old.certificado_status then
    perform public.fn_exige_permissao('certificados.alterar_status');
  end if;

  -- Identidade do checklist: mudar de aluno ou reescrever a data em que o curso
  -- acabou é abrir OUTRO checklist por cima deste, e quem abre precisa de
  -- `certificados.criar`.
  if new.aluno_id is distinct from old.aluno_id
     or new.unidade_id is distinct from old.unidade_id
     or new.data_fim_curso is distinct from old.data_fim_curso then
    perform public.fn_exige_permissao('certificados.criar');
  end if;

  -- `observacoes` fica FORA da lista de propósito: é a anotação livre da linha, e
  -- qualquer um dos três que já pode mexer no checklist pode escrevê-la. Guardá-la
  -- por uma permissão específica inventaria um código que o catálogo do card 2.4
  -- não tem.
  return new;
end $$;

comment on function public.fn_certificado_colunas_permitidas() is
  'Trigger BEFORE UPDATE em certificado_checklist: fecha o achado 8 do card 2.4 §7. A política de update aceita o `or` de três permissões e RLS não é por coluna — aqui cada grupo de colunas volta a exigir a sua (pedagógico/formatura, financeiro, status, identidade). Alcança o PATCH direto no PostgREST, que não passa por fn_certificado_marcar.';

revoke execute on function public.fn_certificado_colunas_permitidas() from public;
revoke execute on function public.fn_certificado_colunas_permitidas() from anon;

create trigger tg_certificado_colunas_permitidas
  before update on public.certificado_checklist
  for each row execute function public.fn_certificado_colunas_permitidas();

-- -----------------------------------------------------------------------------
-- 9. tg_certificado_quem_quando (§8) — "quem e quando" vale para o PATCH também
-- -----------------------------------------------------------------------------
-- O plano exige que CADA item registre quem marcou e quando. Escrito só dentro de
-- fn_certificado_marcar, isso valeria para a tela e não para um `PATCH` direto —
-- e a coluna diria "ninguém marcou" sobre um item marcado.
--
-- Os quatro pares são de propriedade EXCLUSIVA deste trigger: quando o item não
-- muda, ele reescreve o par com o valor antigo. Sem essa metade, um `PATCH`
-- mandando `pedagogico_por = <outro usuário>` sem tocar em `pedagogico_ok`
-- passaria — e o rastro de autoria seria falsificável por quem só pode marcar o
-- financeiro.
create or replace function public.fn_certificado_quem_quando()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.pedagogico_ok is distinct from old.pedagogico_ok then
    new.pedagogico_por := auth.uid();
    new.pedagogico_em  := now();
  else
    new.pedagogico_por := old.pedagogico_por;
    new.pedagogico_em  := old.pedagogico_em;
  end if;

  if new.financeiro_ok is distinct from old.financeiro_ok then
    new.financeiro_por := auth.uid();
    new.financeiro_em  := now();
  else
    new.financeiro_por := old.financeiro_por;
    new.financeiro_em  := old.financeiro_em;
  end if;

  if new.formatura is distinct from old.formatura then
    new.formatura_por := auth.uid();
    new.formatura_em  := now();
  else
    new.formatura_por := old.formatura_por;
    new.formatura_em  := old.formatura_em;
  end if;

  if new.certificado_status is distinct from old.certificado_status then
    new.certificado_por := auth.uid();
    new.certificado_em  := now();
  else
    new.certificado_por := old.certificado_por;
    new.certificado_em  := old.certificado_em;
  end if;

  return new;
end $$;

comment on function public.fn_certificado_quem_quando() is
  'Trigger BEFORE UPDATE em certificado_checklist (card 2.2 §8): grava <item>_por = auth.uid() e <item>_em = now() a cada MUDANÇA de valor, e reescreve o par com o valor antigo quando o item não mudou. Os quatro pares são propriedade exclusiva deste trigger — sem isso a autoria seria falsificável por PATCH direto.';

revoke execute on function public.fn_certificado_quem_quando() from public;
revoke execute on function public.fn_certificado_quem_quando() from anon;

create trigger tg_certificado_quem_quando
  before update on public.certificado_checklist
  for each row execute function public.fn_certificado_quem_quando();

-- -----------------------------------------------------------------------------
-- 10. tg_certificado_sugere_formado (§8) — sugestão, nunca automação
-- -----------------------------------------------------------------------------
-- Com os TRÊS itens OK e o certificado ENTREGUE, abre SUGERIR_FORMADO (BAIXA). É
-- sugestão: quem forma o aluno é uma pessoa, por fn_aluno_alterar_status. Formar
-- automaticamente aqui desalocaria o aluno de todo bloco e turma
-- (tg_aluno_status_desaloca, card 5.1) como efeito colateral de marcar uma caixa.
create or replace function public.fn_certificado_sugere_formado()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.pedagogico_ok and new.financeiro_ok and new.formatura
     and new.certificado_status = 'ENTREGUE' then
    perform public.fn_pendencia_abrir(
      'SUGERIR_FORMADO',
      'FORMADO:' || new.aluno_id::text,
      'Checklist completo e certificado entregue: o aluno pode ser marcado como FORMADO.',
      'BAIXA',
      new.aluno_id);
  end if;

  return null;   -- AFTER trigger: o retorno é ignorado
end $$;

comment on function public.fn_certificado_sugere_formado() is
  'Trigger AFTER UPDATE em certificado_checklist (card 2.2 §8): com os três itens OK e o certificado ENTREGUE, abre a pendência SUGERIR_FORMADO (BAIXA). SUGERE — quem forma é uma pessoa, por fn_aluno_alterar_status, porque formar desaloca o aluno de todo bloco e turma.';

revoke execute on function public.fn_certificado_sugere_formado() from public;
revoke execute on function public.fn_certificado_sugere_formado() from anon;

create trigger tg_certificado_sugere_formado
  after update on public.certificado_checklist
  for each row execute function public.fn_certificado_sugere_formado();

-- -----------------------------------------------------------------------------
-- 11. O outro lado da pendência: formar o aluno FECHA as duas (divergência 3)
-- -----------------------------------------------------------------------------
-- O §10.1 do card 2.2 diz, nas duas linhas, «fechada por: formatura» —
-- ALUNO_ULTIMO_LIVRO e SUGERIR_FORMADO. Do primeiro só existia a metade do
-- estorno (card 6.3); do segundo não existia nada, porque a pendência nasce aqui.
--
-- `after update of status`, e não dentro de fn_aluno_alterar_status: a função é o
-- caminho da tela, e o card 4.2 já decidiu que o que precisa valer para o PATCH
-- direto mora em trigger. Um aluno formado pelo PostgREST tem de sair da central
-- do mesmo jeito.
create or replace function public.fn_aluno_formado_fecha_pendencias()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  perform public.fn_pendencia_resolver('ULTIMO_LIVRO:' || new.id::text);
  perform public.fn_pendencia_resolver('FORMADO:' || new.id::text);
  return null;
end $$;

comment on function public.fn_aluno_formado_fecha_pendencias() is
  'Trigger AFTER UPDATE OF status em aluno (card 8.3): formar o aluno fecha ALUNO_ULTIMO_LIVRO e SUGERIR_FORMADO, que é o que o §10.1 do card 2.2 sempre disse e nenhum código fazia. Pendência que ninguém fecha é a central do card 5.8 sugerindo para sempre que se forme quem já está FORMADO.';

revoke execute on function public.fn_aluno_formado_fecha_pendencias() from public;
revoke execute on function public.fn_aluno_formado_fecha_pendencias() from anon;

create trigger tg_aluno_formado_fecha_pendencias
  after update of status on public.aluno
  for each row
  when (new.status = 'FORMADO' and old.status is distinct from new.status)
  execute function public.fn_aluno_formado_fecha_pendencias();

-- -----------------------------------------------------------------------------
-- 12. O gate de FORMADO ganha a metade que faltava (portão do teste 030 §6)
-- -----------------------------------------------------------------------------
-- O card 4.2 escreveu a condição (2) e deixou a (1) comentada, com um portão no
-- teste 030 cobrando a citação de `certificado_checklist` no dia em que a tabela
-- existisse. Ela existe agora, e aqui está a condição (1).
--
-- ⚠️ PASSA A SER `security definer`, e isto é decisão do card, não detalhe.
--    Como `invoker`, a função lê `certificado_checklist` sob a política
--    `certificado_checklist_sel`, que exige `certificados.ler`. A RLS NEGA LINHA
--    em vez de devolver erro (card 2.3 §3.4): um perfil sem `certificados.ler`
--    que tivesse `alunos.alterar_status` receberia FORMATURA_SEM_CERTIFICADO com
--    o certificado ENTREGUE na mão — e a leitura óbvia do erro ("falta o
--    certificado") seria FALSA. É literalmente o sintoma que o comentário do card
--    4.2 descreveu como inaceitável, e agora ele teria uma segunda causa.
--
--    A matriz INICIAL não expõe isso — os quatro perfis têm `certificados.ler` —,
--    e o card 4.2 já deixou escrito que "nenhum perfil da matriz inicial é assim"
--    não é argumento: a matriz é editável na tela do card 4.7 desde o primeiro
--    dia. Mesmo raciocínio de fn_capacidade_efetiva (5.2), fn_ocupacao_bloco (5.2)
--    e fn_turma_modular_ocupacao (7.2): decisão derivada exibida ou aplicada em
--    tela não pode depender do que o leitor enxerga.
--
--    O filtro de unidade está no corpo, como manda a correção do card 2.3, e
--    `tem_permissao` continua avaliando o CHAMADOR: ela lê auth.uid(), que
--    `security definer` não muda.
create or replace function public.fn_aluno_pode_formar(p_aluno_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (select 1
                   from public.certificado_checklist cc
                  where cc.aluno_id = p_aluno_id
                    and cc.unidade_id = public.fn_unidade_atual()
                    and cc.certificado_status = 'ENTREGUE')
      or public.tem_permissao('alunos.formar_sem_certificado');
$$;

comment on function public.fn_aluno_pode_formar(uuid) is
  'Gate de FORMADO (card 2.2 §3.3), COMPLETO desde o card 8.3: passa com certificado_checklist ENTREGUE do aluno OU com alunos.formar_sem_certificado. SECURITY DEFINER com filtro de unidade no corpo — como invoker, quem não tem certificados.ler receberia FORMATURA_SEM_CERTIFICADO com o certificado na mão, que é o erro falso que o card 4.2 recusou.';

revoke execute on function public.fn_aluno_pode_formar(uuid) from public;
revoke execute on function public.fn_aluno_pode_formar(uuid) from anon;
grant  execute on function public.fn_aluno_pode_formar(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 13. fn_registrar_entrega — o passo 9 do §6.2, agora inteiro
-- -----------------------------------------------------------------------------
-- Só o bloco do FIM muda: onde havia a pendência sozinha, passa a haver a
-- pendência E o checklist, na mesma transação — a "ação única" do plano. A função
-- é reescrita por inteiro porque `create or replace` não sabe trocar um trecho, e
-- o resto do corpo é o do card 6.3 PALAVRA POR PALAVRA — inclusive os dois
-- `set_config('app.entrega_reordenacao', …)` em volta da reposição, sem os quais
-- a guarda de coluna de `aluno_material` recusa a reordenação de quem não tem
-- `alunos.editar_trilha` (é o que 58 asserções do 052 e 56 do 060 mediram
-- enquanto este arquivo foi escrito de memória, em 05/09/2026).
create or replace function public.fn_registrar_entrega(
  p_aluno_id    uuid,
  p_material_id uuid default null,
  p_observacao  text default null
)
returns public.tp_entrega_resultado
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade    uuid;
  v_status     text;
  v_aluno_ok   boolean;
  v_alvo       uuid;
  v_efetivo    uuid;
  v_ordem_alvo integer;
  v_posicao    integer;
  v_mov        uuid;
  v_retorno    text := 'ENTREGUE';
  v_res        public.tp_entrega_resultado;
begin
  perform public.fn_exige_permissao('estoque.lancar_saida');

  -- (a) serializa as entregas do MESMO aluno.
  perform pg_advisory_xact_lock(hashtextextended(p_aluno_id::text, 0));

  select a.unidade_id, a.status, true
    into v_unidade, v_status, v_aluno_ok
    from public.aluno a
   where a.id = p_aluno_id;

  -- Nulo é ERRO e não "sem opinião" (lição do card 5.3): a leitura é `invoker`,
  -- então aluno de outra unidade e aluno inexistente respondem a mesma coisa —
  -- quem não pode ver não descobre que existe (precedente do card 4.2).
  if v_aluno_ok is not true then
    raise exception using
      errcode = 'PT404',
      message = 'Aluno não encontrado.',
      detail  = json_build_object('codigo', 'ALUNO_INEXISTENTE',
                                  'aluno', p_aluno_id)::text;
  end if;

  if v_status not in ('ATIVO', 'ACELERAR') then
    raise exception using
      errcode = 'PT409',
      message = 'Esta ação só vale para aluno ATIVO ou ACELERAR.',
      detail  = json_build_object('codigo', 'ALUNO_INATIVO',
                                  'aluno', p_aluno_id,
                                  'status', v_status)::text;
  end if;

  v_alvo := coalesce(p_material_id, public.fn_trilha_proximo_material(p_aluno_id));

  if v_alvo is null then
    raise exception using
      errcode = 'PT409',
      message = 'A trilha deste aluno está concluída — não há apostila pendente para entregar.',
      detail  = json_build_object('codigo', 'TRILHA_EM_FIM',
                                  'aluno', p_aluno_id)::text;
  end if;

  -- O material informado à mão tem de estar PENDENTE na trilha. Sem este passo, a
  -- tela poderia baixar estoque de uma apostila que o aluno não deve receber — ou
  -- de uma que ele já recebeu, entregando o mesmo livro duas vezes.
  select am.ordem into v_ordem_alvo
    from public.aluno_material am
   where am.aluno_id = p_aluno_id and am.material_id = v_alvo and not am.entregue;

  if v_ordem_alvo is null then
    raise exception using
      errcode = 'PT422',
      message = 'Esta apostila não está pendente na trilha do aluno.',
      detail  = json_build_object('codigo', 'MATERIAL_FORA_DA_TRILHA',
                                  'aluno', p_aluno_id,
                                  'material', v_alvo)::text;
  end if;

  -- (b) serializa o par (checar saldo, gravar saída) daquele material.
  perform pg_advisory_xact_lock(hashtextextended(v_alvo::text, 0));

  v_efetivo := v_alvo;

  if public.fn_saldo_material(v_alvo) <= 0 then
    -- Em ordem de trilha, o primeiro item pendente que TEM estoque. A ordem
    -- importa: pular para o mais adiantado que sobrou seria entregar o livro
    -- errado, e a trilha existe justamente para dizer qual é o próximo.
    select am.material_id into v_efetivo
      from public.aluno_material am
     where am.aluno_id = p_aluno_id
       and not am.entregue
       and am.material_id <> v_alvo
       and public.fn_saldo_material(am.material_id) > 0
     order by am.ordem
     limit 1;

    if v_efetivo is null then
      -- ⚠️ RETORNO, e não exceção (decisão 2.2 (b), §1.3). A pendência de compra é
      --    a única coisa útil que sobra deste caminho, e um `raise` a levaria
      --    embora no rollback: a secretaria veria um erro e o sistema não saberia
      --    que faltou apostila. É a decisão que o teste 052 §5 mede.
      perform public.fn_pendencia_abrir(
        'COMPRA_SEM_ESTOQUE',
        'COMPRA_SEM_ESTOQUE:' || p_aluno_id::text,
        'Nenhuma apostila pendente da trilha deste aluno tem estoque. A entrega está bloqueada até a compra chegar.',
        'ALTA',
        p_aluno_id,
        null,
        v_alvo);

      v_res.status              := 'BLOQUEADA_SEM_ESTOQUE';
      v_res.material_id         := null;
      v_res.material_solicitado := v_alvo;
      v_res.movimento_id        := null;
      v_res.proximo_material_id := public.fn_trilha_proximo_material(p_aluno_id);
      v_res.em_fim              := public.fn_trilha_em_fim(p_aluno_id);
      return v_res;
    end if;

    -- O material que vai sair também precisa do lock: sem ele, a corrida só se
    -- mudaria de lugar — duas entregas reordenadas para o mesmo substituto
    -- fechariam o saldo dele em −1.
    perform pg_advisory_xact_lock(hashtextextended(v_efetivo::text, 0));

    -- A POSIÇÃO do pulado, 1-based: é literalmente o que o passo 6 do §6.2 pede
    -- ("põe esse material na posição do pulado"), e é por isso que o card 6.2
    -- fixou `p_nova_ordem` como posição e não como o valor bruto da coluna.
    select count(*) into v_posicao
      from public.aluno_material am
     where am.aluno_id = p_aluno_id and am.ordem <= v_ordem_alvo;

    -- A exceção nomeada, ligada e desligada em volta da ÚNICA escrita que
    -- precisa dela. `is_local => true`: morre no fim da transação de qualquer
    -- forma, mas desligar aqui é o que mantém a brecha do tamanho de uma linha.
    perform set_config('app.entrega_reordenacao', 'on', true);
    perform public.fn_trilha_reposicionar(p_aluno_id, v_efetivo, v_posicao,
                                          'SEM_ESTOQUE', false);
    perform set_config('app.entrega_reordenacao', '', true);

    -- O pulado CONTINUA pendente e volta a ser "próximo" assim que houver
    -- estoque: ele foi empurrado uma posição, não removido.
    perform public.fn_pendencia_abrir(
      'ESTOQUE_ZERO',
      'ESTOQUE_ZERO:' || v_alvo::text,
      'Apostila sem estoque: a trilha de pelo menos um aluno foi reordenada para pular esta apostila.',
      'MEDIA',
      null,
      null,
      v_alvo);

    v_retorno := 'REORDENADA';
  end if;

  -- Quantidade COM SINAL (card 2.1): `movimento_sinal_ck` já exige SAIDA < 0, e a
  -- autoria não é coluna própria — vem de `criado_por`, que fn_auditoria preenche.
  insert into public.movimento_estoque
    (unidade_id, material_id, tipo, quantidade, aluno_id, ocorrido_em, observacao)
  values (v_unidade, v_efetivo, 'SAIDA', -1, p_aluno_id, now(), p_observacao)
  returning id into v_mov;

  -- A data da entrega é `fn_hoje()`, a data no fuso da escola (card 2.3 §3.3). O
  -- §6.2 escrevia a data do servidor, que é UTC no Supabase: depois das 21h a
  -- entrega cairia no dia seguinte, e a projeção do card 8.1 — que mede INTERVALO
  -- entre entregas — leria um ritmo que ninguém teve. O C6 reprova a forma antiga
  -- inclusive quando ela aparece só num comentário, e é por isso que este não a
  -- escreve.
  update public.aluno_material am
     set entregue             = true,
         data_entrega         = public.fn_hoje(),
         movimento_estoque_id = v_mov
   where am.aluno_id = p_aluno_id and am.material_id = v_efetivo;

  -- ÚLTIMO LIVRO ENTREGUE — o passo 9 do §6.2, COMPLETO desde o card 8.3.
  -- fn_certificado_abrir vem ANTES da pendência, e a ordem é decisão: se quem
  -- entrega não tiver `certificados.criar` (achado 3 do card 2.4 §7), a entrega
  -- inteira falha e NADA é gravado — nem o movimento, nem a marca na trilha, nem
  -- a pendência. Metade de uma "ação única" é pior que nenhuma, e a ordem inversa
  -- deixaria um aviso de "abra o checklist" que ninguém consegue atender.
  -- Severidade BAIXA porque não há nada errado — há algo a fazer.
  if public.fn_trilha_em_fim(p_aluno_id) then
    perform public.fn_certificado_abrir(p_aluno_id);

    perform public.fn_pendencia_abrir(
      'ALUNO_ULTIMO_LIVRO',
      'ULTIMO_LIVRO:' || p_aluno_id::text,
      'O aluno recebeu a última apostila da trilha. O checklist do certificado já está aberto.',
      'BAIXA',
      p_aluno_id);
  end if;

  -- O retorno já traz o próximo e o FIM recalculados: a tela do card 6.6 não
  -- precisa de uma segunda ida ao banco para saber o que mostrar em seguida.
  v_res.status              := v_retorno;
  v_res.material_id         := v_efetivo;
  v_res.material_solicitado := v_alvo;
  v_res.movimento_id        := v_mov;
  v_res.proximo_material_id := public.fn_trilha_proximo_material(p_aluno_id);
  v_res.em_fim              := public.fn_trilha_em_fim(p_aluno_id);
  return v_res;
end $$;

comment on function public.fn_registrar_entrega(uuid, uuid, text) is
  'Entrega de apostila como ATO ÚNICO (card 2.2 §6.2): SAIDA de estoque, marca na trilha e vínculo entre as duas, na mesma transação. Exige estoque.lancar_saida. Devolve ENTREGUE, REORDENADA (pulou apostila sem estoque, com rastro em aluno_material_hist e pendência ESTOQUE_ZERO) ou BLOQUEADA_SEM_ESTOQUE (nenhum item da trilha tem estoque; abre COMPRA_SEM_ESTOQUE e NÃO levanta exceção, para a pendência sobreviver ao commit). Desde o card 8.3 o passo 9 está INTEIRO: chegando ao FIM, abre o checklist do certificado (fn_certificado_abrir) antes da pendência ALUNO_ULTIMO_LIVRO. Serializa aluno e material com pg_advisory_xact_lock.';

revoke execute on function public.fn_registrar_entrega(uuid, uuid, text) from public;
revoke execute on function public.fn_registrar_entrega(uuid, uuid, text) from anon;
grant  execute on function public.fn_registrar_entrega(uuid, uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 14. fn_estornar_entrega — o passo 5 do §6.3, agora inteiro
-- -----------------------------------------------------------------------------
-- Idem: só o bloco do FIM muda; o resto é o corpo do card 6.3.
create or replace function public.fn_estornar_entrega(
  p_movimento_id uuid,
  p_motivo       text
)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade    uuid;
  v_material   uuid;
  v_aluno      uuid;
  v_tipo       text;
  v_quantidade integer;
  v_estorno    uuid;
begin
  perform public.fn_exige_permissao('estoque.estornar');

  -- Motivo obrigatório, pelo precedente de fn_aluno_alterar_status e
  -- fn_trilha_remover: desfazer uma entrega é decisão, e decisão sem porquê é
  -- decisão perdida.
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception using
      errcode = 'PT422',
      message = 'Informe o motivo do estorno.',
      detail  = json_build_object('codigo', 'MOTIVO_OBRIGATORIO',
                                  'movimento', p_movimento_id)::text;
  end if;

  -- Serializa o movimento: `movimento_estorno_uk` (unique parcial do card 6.1) já
  -- garante que ele só se estorna uma vez, mas sem o lock a corrida chegaria à
  -- tela como um `23505` cru — que é o que o card 2.2 §1.2 proíbe. Com o lock, a
  -- segunda sessão espera e sai com MOVIMENTO_JA_ESTORNADO.
  perform pg_advisory_xact_lock(hashtextextended(p_movimento_id::text, 0));

  select mv.unidade_id, mv.material_id, mv.aluno_id, mv.tipo, mv.quantidade
    into v_unidade, v_material, v_aluno, v_tipo, v_quantidade
    from public.movimento_estoque mv
   where mv.id = p_movimento_id;

  -- Código NOVO, e a família já existe: PC_INEXISTENTE, ALUNO_INEXISTENTE,
  -- BLOCO_INEXISTENTE e PENDENCIA_INEXISTENTE dizem a mesma coisa nos seus
  -- domínios. Vale também para movimento de OUTRA unidade — a leitura é
  -- `invoker`, então quem não pode ver não descobre que existe. Reaproveitar
  -- MOVIMENTO_NAO_ESTORNAVEL aqui diria "este movimento não pode ser estornado"
  -- sobre algo que o usuário não tem, o que manda procurar o problema no lugar
  -- errado.
  if v_tipo is null then
    raise exception using
      errcode = 'PT404',
      message = 'Este movimento de estoque não foi encontrado.',
      detail  = json_build_object('codigo', 'MOVIMENTO_INEXISTENTE',
                                  'movimento', p_movimento_id)::text;
  end if;

  -- Só SAIDA se estorna por aqui: esta função desfaz uma ENTREGA, e desfazer uma
  -- ENTRADA de pedido ou um AJUSTE é outra conversa (card 6.5), com outra
  -- permissão e outro efeito na trilha — nenhum.
  if v_tipo <> 'SAIDA' then
    raise exception using
      errcode = 'PT409',
      message = 'Este movimento não pode ser estornado.',
      detail  = json_build_object('codigo', 'MOVIMENTO_NAO_ESTORNAVEL',
                                  'movimento', p_movimento_id,
                                  'tipo', v_tipo)::text;
  end if;

  if exists (select 1 from public.movimento_estoque mv
              where mv.estorno_de_id = p_movimento_id) then
    raise exception using
      errcode = 'PT409',
      message = 'Este movimento já foi estornado.',
      detail  = json_build_object('codigo', 'MOVIMENTO_JA_ESTORNADO',
                                  'movimento', p_movimento_id)::text;
  end if;

  -- Sinal OPOSTO e mesma magnitude. Escrito como `-v_quantidade` e não como `1`
  -- de propósito: o dia em que uma entrega sair com quantidade diferente de 1, o
  -- estorno continua devolvendo exatamente o que saiu.
  insert into public.movimento_estoque
    (unidade_id, material_id, tipo, quantidade, aluno_id, ocorrido_em,
     estorno_de_id, observacao)
  values (v_unidade, v_material, 'ESTORNO', -v_quantidade, v_aluno, now(),
          p_movimento_id, p_motivo)
  returning id into v_estorno;

  -- A trilha volta a PENDENTE. As três colunas são exatamente as que a guarda da
  -- seção 3 deixa fora da lista, então `estoque.estornar` basta — não é preciso
  -- ser dono da trilha para desfazer uma entrega.
  update public.aluno_material am
     set entregue             = false,
         data_entrega         = null,
         movimento_estoque_id = null
   where am.movimento_estoque_id = p_movimento_id;

  -- O ALUNO SAIU DO FIM — o passo 5 do §6.3, COMPLETO desde o card 8.3.
  -- O aviso do último livro deixou de ser verdade (pendência que ninguém fecha é
  -- a central do card 5.8 perdendo credibilidade), e o checklist aberto por
  -- aquela entrega deixou de ter razão de existir: apaga se nenhum item foi
  -- marcado, mantém e abre CERTIFICADO_INCONSISTENTE se alguém já trabalhou nele.
  -- Quem faz isso é fn_certificado_reavaliar_estorno, `security definer` porque a
  -- tabela não tem política de delete para ninguém.
  if v_aluno is not null and not public.fn_trilha_em_fim(v_aluno) then
    perform public.fn_pendencia_resolver('ULTIMO_LIVRO:' || v_aluno::text);
    perform public.fn_certificado_reavaliar_estorno(v_aluno);
  end if;

  --
  -- E o passo 6 continua valendo por AUSÊNCIA de código: um estorno NÃO reverte o
  -- reordenamento da trilha por falta de estoque. O histórico em
  -- aluno_material_hist continua contando o que aconteceu, e desfazer a
  -- reordenação inventaria uma trilha que nunca existiu.

  return v_estorno;
end $$;

comment on function public.fn_estornar_entrega(uuid, text) is
  'Estorna uma SAIDA de entrega (card 2.2 §6.3): grava o movimento ESTORNO com sinal oposto e estorno_de_id, e devolve o item da trilha a PENDENTE. Exige estoque.estornar e motivo. Desde o card 8.3 o passo 5 está INTEIRO: saindo do FIM, fecha ALUNO_ULTIMO_LIVRO e reavalia o checklist do certificado (fn_certificado_reavaliar_estorno). O movimento original NUNCA é alterado nem apagado. Não reverte o reordenamento por falta de estoque — o histórico conta o que aconteceu.';

revoke execute on function public.fn_estornar_entrega(uuid, text) from public;
revoke execute on function public.fn_estornar_entrega(uuid, text) from anon;
grant  execute on function public.fn_estornar_entrega(uuid, text) to authenticated;
