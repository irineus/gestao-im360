-- =============================================================================
-- Card 6.3 — Entrega de apostila (ato único) e estorno
--
-- Fonte: docs/regras-negocio-funcoes.md §6.1 (tp_entrega_resultado), §6.2
--        (fn_registrar_entrega), §6.3 (fn_estornar_entrega), §7
--        (fn_saldo_material), §10.1 (catálogo de pendências), §12 (catálogo de
--        erros) e §13 (mapa função → card),
--        docs/estrategia-testes.md §6.1 (regra por camada), §7 (concorrência
--        fora do pgTAP), §13 (obrigação de teste de função de aplicação) e §14
--        (decisões que precisam de teste),
--        docs/views-leitura.md §4.1 (a conta do saldo, que é a mesma daqui),
--        docs/permissoes-matriz.md §4 e §5 (o que o MONITOR tem e o que não tem).
--
-- Entrega:
--   • `tp_entrega_resultado` — os três status que a tela do card 6.6 trata um a
--     um (§6.1);
--   • `fn_saldo_material` — a mesma soma de `v_estoque_atual` (card 6.4), aqui
--     para DECIDIR dentro de uma transação;
--   • `fn_contexto_entrega` + a exceção NOMEADA na guarda de coluna do card 6.1
--     §9 — a decisão que este card tinha de tomar (seção 3);
--   • `fn_trilha_reposicionar` — a mecânica de reposição, extraída de
--     `fn_trilha_reordenar` (card 6.2) para não existir uma segunda;
--   • `fn_registrar_entrega` e `fn_estornar_entrega`;
--   • `MOVIMENTO_INEXISTENTE`, o único código de erro novo (contrato de 41 → 42).
--
-- ⚠️ ESTRUTURA E MAIS NADA, como o 6.1 e o 6.2: nenhum movimento de estoque e
--    nenhuma linha de trilha entram aqui. `movimento_estoque` é IMUTÁVEL — o
--    movimento gravado em produção por engano não se apaga, só se estorna, e a
--    sobra fica visível para sempre. O portão do card 4.0,5 tem as cinco tabelas
--    da fase 06 fora da lista permitida e segue as chamadas transitivamente.
--
-- =============================================================================
-- A DECISÃO QUE ESTE CARD TINHA DE TOMAR — e por que a lista de saídas do card
-- 6.2 tinha uma opção a menos do que parecia
-- =============================================================================
-- O §6.2 manda o caminho `REORDENADA` reordenar a trilha, e reordenar exige
-- `alunos.editar_trilha` em DOIS lugares: dentro de `fn_trilha_reordenar` (card
-- 6.2 §5.3) e dentro de `tg_aluno_material_colunas_permitidas` (card 6.1 §9). O
-- monitor, que é quem entrega, não tem essa permissão (card 2.4 §5). As Notas
-- deste card registram duas saídas visíveis: `fn_registrar_entrega` como
-- `security definer`, ou uma exceção explícita e nomeada na guarda.
--
-- ⚠️ A PRIMEIRA NÃO FUNCIONA, e isto foi verificado antes de escrever uma linha:
--    `security definer` troca o PAPEL do banco (e com ele a RLS, porque o dono
--    tem BYPASSRLS), mas NÃO troca `auth.uid()`. E `tem_permissao` (card 3.4) é
--    escrita sobre `auth.uid()`, não sobre `current_user`. Logo
--    `fn_exige_permissao('alunos.editar_trilha')` continuaria levantando
--    `PT403 / SEM_PERMISSAO` dentro de uma `fn_registrar_entrega` definer,
--    exatamente como levanta hoje. Definer resolveria uma barreira de RLS; a
--    barreira aqui é de PERMISSÃO DE APLICAÇÃO, que é outra coisa e não se
--    atravessa mudando de dono.
--
--    O custo de escolher a saída que não funciona seria alto e silencioso na
--    revisão: `fn_registrar_entrega` entraria na lista fechada do C8 (deixando de
--    passar pela política `insert` POR TIPO de `movimento_estoque`, que é o achado
--    9 do card 2.4 e a única coisa que impede um `POST` de ENTRADA inventada), e
--    o defeito continuaria lá.
--
-- Fica, então, a segunda — e ela é escrita da forma mais estreita que existe:
--
--   (1) a exceção vale SÓ para a coluna `ordem` (as outras três da guarda —
--       aluno, material, origem — continuam exigindo a permissão sempre);
--   (2) vale SÓ dentro do contexto `app.entrega_reordenacao`, uma GUC de
--       TRANSAÇÃO (`is_local => true`) que `fn_registrar_entrega` liga
--       imediatamente antes da reposição e desliga imediatamente depois;
--   (3) o contexto é impossível de forjar pelo cliente, pela MESMA razão do
--       contexto de rotina do card 2.2 §2.2: `set_config` mora em `pg_catalog`,
--       que o PostgREST não expõe, e a única função do projeto que escreve esta
--       GUC é `fn_registrar_entrega` — o que virou asserção no teste 052 §10, e
--       não uma frase de confiança;
--   (4) a reposição continua GRAVANDO HISTÓRICO (`motivo = 'SEM_ESTOQUE'`), que é
--       o que a guarda existe para proteger: o mal que ela impede não é "a ordem
--       mudou", é "a ordem mudou e nada explica por quê".
--
-- Afrouxar a guarda para `estoque.lancar_saida` — a terceira saída, que ninguém
-- listou — seria dar ao monitor um `PATCH` livre em `ordem` pelo PostgREST, sem
-- histórico nenhum. É exatamente o buraco que o card 6.1 §9 fechou, e não se
-- reabre para acomodar um caminho que a GUC resolve em quatro linhas.
--
-- ⚠️ SEGUNDO ACHADO, do mesmo tipo: o passo 2 do §6.2 manda
--    `select … from aluno where id = … for update` para serializar as entregas do
--    mesmo aluno. Não dá: sob RLS, `SELECT … FOR UPDATE` exige que a linha passe
--    TAMBÉM pela `using` da política de UPDATE, e `aluno_upd` (card 4.2) pede
--    `alunos.editar` ∨ `alunos.alterar_status` ∨ `alunos.reverter_status` — o
--    monitor não tem nenhuma das três. A entrega morreria com um erro de RLS
--    ("query would be affected by row-level security policy") numa tela que não
--    fala de cadastro. A serialização por aluno é feita, aqui, com
--    `pg_advisory_xact_lock` — a MESMA ferramenta que o §4.5 já escolheu para a
--    admissão, e que não depende de política nenhuma.
--
-- O que este card NÃO traz, e onde está escrito que não é esquecimento:
--   • `fn_certificado_abrir` (passo 9 do §6.2) e o tratamento de
--     `certificado_checklist` no estorno (passo 5 do §6.3) são do card 8.3 — a
--     tabela não existe. A nota deste card já dizia "o disparo do checklist no FIM
--     entra na Fase 8". O que existe hoje é a pendência `ALUNO_ULTIMO_LIVRO`, que
--     é o aviso, e um PORTÃO no teste 052 §11 que reprova a suíte no dia em que
--     `certificado_checklist` nascer sem estas duas funções a citarem — a mesma
--     forma do portão do gate de FORMADO (card 4.2, teste 030 §6);
--   • `tg_movimento_resolve_pendencia`, que fecha `ESTOQUE_ZERO` e
--     `COMPRA_SEM_ESTOQUE` quando o pedido chega, é do card 6.5 (§7). O teste 050
--     já tem portão para ele;
--   • `fn_ajustar_estoque` e `fn_pedido_receber` são do card 6.5;
--   • `v_estoque_atual` e `v_demanda_imediata` são do card 6.4.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. tp_entrega_resultado (§6.1)
-- -----------------------------------------------------------------------------
-- Três status porque a tela reage diferente a cada um: confirmação simples,
-- aviso de trilha reordenada, ou alerta de compra. `material_solicitado` ao lado
-- de `material_id` é o que permite à tela dizer "faltou a 02, entreguei a 03" sem
-- uma segunda ida ao banco — e é a diferença entre os dois que denuncia o
-- reordenamento a quem lê o retorno sem olhar o `status`.
create type public.tp_entrega_resultado as (
  status              text,
  material_id         uuid,
  material_solicitado uuid,
  movimento_id        uuid,
  proximo_material_id uuid,
  em_fim              boolean
);

comment on type public.tp_entrega_resultado is
  'Retorno de fn_registrar_entrega (card 2.2 §6.1). `status` ∈ ENTREGUE | REORDENADA | BLOQUEADA_SEM_ESTOQUE — os três são RETORNO, nunca exceção (§1.3), porque os dois últimos precisam deixar pendência gravada e um `raise` a levaria no rollback.';

-- -----------------------------------------------------------------------------
-- 2. fn_saldo_material (§7)
-- -----------------------------------------------------------------------------
-- A mesma soma de `v_estoque_atual` (card 6.4, docs/views-leitura.md §4.1): a
-- view serve LISTAGEM, esta função serve DECISÃO dentro de outra função. Duas
-- implementações da mesma soma trivial são aceitáveis; uma terceira, em Dart,
-- não é.
--
-- `security invoker` por decisão do card 2.3, e a consequência está escrita lá:
-- quem não tem `estoque.ler` lê ZERO para todo material e toda entrega vira
-- `BLOQUEADA_SEM_ESTOQUE`, abrindo pendência de compra de um estoque que existe.
-- É por isso que `estoque.ler` está nos QUATRO perfis da matriz inicial (card 2.4
-- §5) — e é por isso que a alternativa (definer) seria pior: ela responderia
-- sobre o estoque de outra unidade a quem não pode vê-lo.
--
-- `coalesce(sum(...), 0)`: soma de conjunto vazio é NULA, não zero (card 2.3
-- §3.1). Material recém-cadastrado tem de valer 0, senão `0 <= 0` vira nulo e o
-- `if` do passo 6 da entrega não entra em ramo nenhum.
create or replace function public.fn_saldo_material(p_material_id uuid)
returns integer
language sql
stable
set search_path = public, pg_temp
as $$
  select coalesce(sum(mv.quantidade), 0)::integer
    from public.movimento_estoque mv
   where mv.material_id = p_material_id;
$$;

comment on function public.fn_saldo_material(uuid) is
  'Saldo do material = soma COM SINAL de movimento_estoque (card 2.2 §7). Nunca cacheia e nunca lê coluna: a mesma conta de v_estoque_atual (card 6.4). `security invoker` por decisão do card 2.3 — sem `estoque.ler` devolve 0, que é a redução silenciosa da RLS documentada em 2.3 §3.4.';

revoke execute on function public.fn_saldo_material(uuid) from public;
revoke execute on function public.fn_saldo_material(uuid) from anon;
grant  execute on function public.fn_saldo_material(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. A exceção nomeada: contexto de entrega + a guarda do card 6.1 §9
-- -----------------------------------------------------------------------------
-- Espelha `fn_contexto_rotina` (card 2.2 §2.2), de propósito: mesma forma, mesma
-- GUC de transação, mesma justificativa de por que um cliente não entra nela.
create or replace function public.fn_contexto_entrega()
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$ select coalesce(current_setting('app.entrega_reordenacao', true), '') = 'on' $$;

comment on function public.fn_contexto_entrega() is
  'Verdadeiro dentro da reposição de trilha por falta de estoque de fn_registrar_entrega (GUC app.entrega_reordenacao, is_local). É a exceção NOMEADA que o card 6.3 escolheu para a guarda do card 6.1 §9 — e a única função do projeto que escreve a GUC é fn_registrar_entrega, o que o teste 052 §10 asserta em vez de confiar.';

-- Grant para `authenticated` porque quem a chama é
-- `fn_aluno_material_colunas_permitidas`, que é `security invoker` e roda na pele
-- do monitor: sem o grant o trigger morreria com "permission denied for
-- function". Ler a GUC não concede nada — quem concede é quem a ESCREVE, e
-- `set_config` mora em `pg_catalog`, fora do alcance do PostgREST.
revoke execute on function public.fn_contexto_entrega() from public;
revoke execute on function public.fn_contexto_entrega() from anon;
grant  execute on function public.fn_contexto_entrega() to authenticated;

-- A guarda do card 6.1 §9, agora com a exceção. As três colunas de fora da lista
-- (`entregue`, `data_entrega`, `movimento_estoque_id`) continuam livres para quem
-- tem `estoque.lancar_saida`/`estoque.estornar`; `aluno_id`, `material_id` e
-- `origem` continuam exigindo `alunos.editar_trilha` SEMPRE; e `ordem` passa a ter
-- uma única brecha, com nome, com escopo de transação e com histórico obrigatório
-- do outro lado.
create or replace function public.fn_aluno_material_colunas_permitidas()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  -- Estas três não têm exceção nenhuma, e é o que mantém a guarda de pé: trocar a
  -- apostila devida por outra, mudar o aluno, ou tirar a linha do alcance da
  -- regeneração (origem COMBO → MANUAL) nunca é entrega.
  if new.aluno_id      is distinct from old.aluno_id
     or new.material_id is distinct from old.material_id
     or new.origem      is distinct from old.origem then
    perform public.fn_exige_permissao('alunos.editar_trilha');
  end if;

  -- `ordem`: a exceção nomeada do card 6.3. Fora do contexto de entrega — isto é,
  -- num `PATCH` direto pelo PostgREST, ou em qualquer outra transação — continua
  -- exigindo `alunos.editar_trilha`, exatamente como antes.
  if new.ordem is distinct from old.ordem
     and not public.fn_contexto_entrega() then
    perform public.fn_exige_permissao('alunos.editar_trilha');
  end if;

  return new;
end $$;

comment on function public.fn_aluno_material_colunas_permitidas() is
  'Trigger BEFORE UPDATE em aluno_material: sob estoque.lancar_saida/estoque.estornar só se escreve a ENTREGA (entregue, data_entrega, movimento_estoque_id); aluno, material e origem exigem alunos.editar_trilha sempre; `ordem` também, EXCETO na reposição por falta de estoque de fn_registrar_entrega (card 6.3, contexto app.entrega_reordenacao), que grava aluno_material_hist com motivo SEM_ESTOQUE.';

revoke execute on function public.fn_aluno_material_colunas_permitidas() from public;
revoke execute on function public.fn_aluno_material_colunas_permitidas() from anon;

-- -----------------------------------------------------------------------------
-- 4. fn_trilha_reposicionar — a mecânica, com um dono só
-- -----------------------------------------------------------------------------
-- `fn_trilha_reordenar` (card 6.2 §5.3) já sabia mover um item para uma POSIÇÃO
-- renumerando de 10 em 10 num único UPDATE — o que o `unique … deferrable
-- initially deferred` do card 2.1 (e) existe para permitir. A entrega precisa da
-- mesma mecânica com três diferenças: sem exigir `alunos.editar_trilha`, sem
-- marcar `origem = 'MANUAL'` (o reordenamento por falta de estoque não é decisão
-- de ninguém, e marcar MANUAL tiraria a linha do alcance da regeneração do card
-- 6.6) e com `motivo = 'SEM_ESTOQUE'` no histórico.
--
-- Copiar o UPDATE para cá daria DUAS implementações da mesma renumeração, e o dia
-- em que uma mudasse a outra ficaria errada em silêncio. Extraída, ela tem um
-- dono só e os dois caminhos a exercitam.
--
-- ⚠️ Ela NÃO tem `fn_exige_permissao` própria, e isso é deliberado — mas não é
--    gratuito: como é `invoker`, precisa de `grant execute` para `authenticated`
--    (senão `fn_trilha_reordenar`, que também é invoker, morreria em "permission
--    denied for function"). Quem a protege é a guarda da seção 3, que roda no
--    trigger e alcança QUALQUER caminho até a coluna `ordem` — inclusive uma
--    chamada RPC direta a esta função. As duas coisas que ela garante sozinha, e
--    que por isso vivem aqui e não nos chamadores, são as que uma chamada direta
--    não poderia pular: item entregue não se move, e TODA reposição deixa linha em
--    `aluno_material_hist`.
create or replace function public.fn_trilha_reposicionar(
  p_aluno_id      uuid,
  p_material_id   uuid,
  p_posicao       integer,
  p_motivo        text,
  p_marcar_manual boolean default false
)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade    uuid;
  v_ordem      integer;
  v_entregue   boolean;
  v_total      integer;
  v_destino    integer;
  v_ordem_nova integer;
begin
  -- Só os dois motivos que reposicionam. `GERACAO_COMBO` e `REMOCAO` são de
  -- outros caminhos, e aceitá-los aqui deixaria o histórico contar uma história
  -- que não aconteceu. Não é `check` de tabela porque a tabela precisa dos quatro.
  if p_motivo is null or p_motivo not in ('MANUAL', 'SEM_ESTOQUE') then
    raise exception
      'fn_trilha_reposicionar aceita motivo MANUAL ou SEM_ESTOQUE; recebeu %.',
      coalesce(p_motivo, '<nulo>');
  end if;

  select am.unidade_id, am.ordem, am.entregue
    into v_unidade, v_ordem, v_entregue
    from public.aluno_material am
   where am.aluno_id = p_aluno_id and am.material_id = p_material_id;

  if v_ordem is null then
    raise exception using
      errcode = 'PT422',
      message = 'Esta apostila não está na trilha do aluno.',
      detail  = json_build_object('codigo', 'MATERIAL_FORA_DA_TRILHA',
                                  'aluno', p_aluno_id,
                                  'material', p_material_id)::text;
  end if;

  if v_entregue then
    raise exception using
      errcode = 'PT409',
      message = 'Esta apostila já foi entregue e não pode mudar de posição na trilha.',
      detail  = json_build_object('codigo', 'ITEM_JA_ENTREGUE',
                                  'aluno', p_aluno_id,
                                  'material', p_material_id)::text,
      hint    = 'Estorne a entrega primeiro.';
  end if;

  select count(*) into v_total
    from public.aluno_material am where am.aluno_id = p_aluno_id;

  -- Posição fora da trilha é grampeada nas bordas em vez de virar erro (card 6.2
  -- §5.3): arrastar para além do fim é um gesto comum na tela e significa "põe no
  -- fim".
  v_destino := least(greatest(coalesce(p_posicao, v_total), 1), v_total);

  with sequencia as (
    select am.id,
           row_number() over (order by am.ordem) as pos
      from public.aluno_material am
     where am.aluno_id = p_aluno_id
       and am.material_id <> p_material_id
  ),
  final as (
    select id,
           case when pos < v_destino then pos else pos + 1 end as pos
      from sequencia
    union all
    select am.id, v_destino
      from public.aluno_material am
     where am.aluno_id = p_aluno_id and am.material_id = p_material_id
  )
  update public.aluno_material am
     set ordem = (f.pos * 10)::integer
    from final f
   where am.id = f.id
     and am.ordem is distinct from (f.pos * 10)::integer;

  select am.ordem into v_ordem_nova
    from public.aluno_material am
   where am.aluno_id = p_aluno_id and am.material_id = p_material_id;

  -- Só a linha MOVIDA muda de origem, e só na edição humana — as outras foram
  -- empurradas, não editadas. Na reposição por falta de estoque ninguém decidiu
  -- nada: marcar MANUAL ali tiraria a linha do alcance da regeneração do card 6.6.
  if p_marcar_manual then
    update public.aluno_material am
       set origem = 'MANUAL'
     where am.aluno_id = p_aluno_id and am.material_id = p_material_id
       and am.origem <> 'MANUAL';
  end if;

  insert into public.aluno_material_hist
    (unidade_id, aluno_id, material_id, ordem_anterior, ordem_nova, motivo, usuario_id)
  values (v_unidade, p_aluno_id, p_material_id, v_ordem, v_ordem_nova, p_motivo, auth.uid());
end $$;

comment on function public.fn_trilha_reposicionar(uuid, uuid, integer, text, boolean) is
  'Mecânica da reposição de um item PENDENTE para a POSIÇÃO p_posicao (1 = primeiro; fora das bordas é grampeado), renumerando a trilha de 10 em 10 num único UPDATE. Dona única do algoritmo: fn_trilha_reordenar (MANUAL, card 6.2) e fn_registrar_entrega (SEM_ESTOQUE, card 6.3) a chamam. Não checa permissão — quem o faz é tg_aluno_material_colunas_permitidas, que alcança qualquer caminho até a coluna `ordem`.';

revoke execute on function public.fn_trilha_reposicionar(uuid, uuid, integer, text, boolean) from public;
revoke execute on function public.fn_trilha_reposicionar(uuid, uuid, integer, text, boolean) from anon;
grant  execute on function public.fn_trilha_reposicionar(uuid, uuid, integer, text, boolean) to authenticated;

-- `fn_trilha_reordenar` passa a ser a permissão mais a mecânica. O contrato
-- externo não muda em nada: mesma assinatura, mesmos códigos de erro, mesma
-- POSIÇÃO como parâmetro, mesmo `origem = 'MANUAL'` na linha movida, mesmo
-- histórico — o teste 051 §8 continua sendo a medida disso.
create or replace function public.fn_trilha_reordenar(
  p_aluno_id    uuid,
  p_material_id uuid,
  p_nova_ordem  integer
)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
begin
  perform public.fn_exige_permissao('alunos.editar_trilha');
  perform public.fn_trilha_reposicionar(p_aluno_id, p_material_id, p_nova_ordem,
                                        'MANUAL', true);
end $$;

comment on function public.fn_trilha_reordenar(uuid, uuid, integer) is
  'Move uma apostila PENDENTE para a POSIÇÃO p_nova_ordem da trilha (1 = primeiro; fora das bordas é grampeado). Exige alunos.editar_trilha, marca a linha movida como MANUAL e grava aluno_material_hist. A mecânica mora em fn_trilha_reposicionar (card 6.3), compartilhada com a entrega — duas cópias da mesma renumeração divergiriam em silêncio.';

revoke execute on function public.fn_trilha_reordenar(uuid, uuid, integer) from public;
revoke execute on function public.fn_trilha_reordenar(uuid, uuid, integer) from anon;
grant  execute on function public.fn_trilha_reordenar(uuid, uuid, integer) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. fn_registrar_entrega (§6.2) — a regra mais delicada do sistema
-- -----------------------------------------------------------------------------
-- Os passos 7 a 9 do §6.2 são UM ATO SÓ, na mesma transação: ou o movimento, a
-- marca na trilha e o vínculo entre os dois acontecem juntos, ou nenhum acontece.
-- É a "ação única" do plano, e é o que a planilha não tinha — lá, dar o livro e
-- baixar o estoque eram duas anotações que se desencontravam.
--
-- ⚠️ Os DOIS advisory locks, e a ordem entre eles importa:
--    (a) por ALUNO, substituindo o `for update` do §6.2 — ver o segundo achado no
--        cabeçalho. Serializa duas entregas simultâneas para a mesma pessoa;
--    (b) por MATERIAL, que é o do card 2.2 §4.5: sem ele, duas entregas
--        simultâneas do ÚLTIMO exemplar leem saldo 1 as duas (em `read committed`
--        nenhuma enxerga a linha ainda não commitada da outra) e o saldo fecha em
--        −1. NENHUMA constraint pega isso: saldo é regra de AGREGADO.
--    A ordem é sempre aluno → material, nas duas sessões, e é o que impede o
--    abraço mortal. A prova de que o lock segura está em
--    supabase/tests_concorrencia/entrega_ultimo_exemplar.sh, fora do pgTAP porque
--    uma suíte de conexão única não tem corrida nenhuma (card 2.8 §7).
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

  -- Último livro entregue: o aviso existe hoje, o checklist do certificado é do
  -- card 8.3 (fn_certificado_abrir). Severidade BAIXA porque não há nada errado —
  -- há algo a fazer.
  if public.fn_trilha_em_fim(p_aluno_id) then
    perform public.fn_pendencia_abrir(
      'ALUNO_ULTIMO_LIVRO',
      'ULTIMO_LIVRO:' || p_aluno_id::text,
      'O aluno recebeu a última apostila da trilha. Abra o checklist do certificado.',
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
  'Entrega de apostila como ATO ÚNICO (card 2.2 §6.2): SAIDA de estoque, marca na trilha e vínculo entre as duas, na mesma transação. Exige estoque.lancar_saida. Devolve ENTREGUE, REORDENADA (pulou apostila sem estoque, com rastro em aluno_material_hist e pendência ESTOQUE_ZERO) ou BLOQUEADA_SEM_ESTOQUE (nenhum item da trilha tem estoque; abre COMPRA_SEM_ESTOQUE e NÃO levanta exceção, para a pendência sobreviver ao commit). Serializa aluno e material com pg_advisory_xact_lock.';

revoke execute on function public.fn_registrar_entrega(uuid, uuid, text) from public;
revoke execute on function public.fn_registrar_entrega(uuid, uuid, text) from anon;
grant  execute on function public.fn_registrar_entrega(uuid, uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. fn_estornar_entrega (§6.3)
-- -----------------------------------------------------------------------------
-- Correção é por ESTORNO, nunca por update: o movimento original nunca é apagado
-- nem alterado (`tg_movimento_imutavel` do card 6.1 mais a ausência de política de
-- update/delete). O estorno deixa DUAS linhas onde alguém gostaria de ver zero, e
-- é assim que tem de ser — é o histórico que explica um saldo três meses depois.
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

  -- O aluno saiu do FIM: o aviso do último livro deixou de ser verdade.
  -- Pendência que ninguém fecha é a central do card 5.8 perdendo credibilidade.
  if v_aluno is not null and not public.fn_trilha_em_fim(v_aluno) then
    perform public.fn_pendencia_resolver('ULTIMO_LIVRO:' || v_aluno::text);
  end if;

  -- ⚠️ O passo 5 do §6.3 — apagar o certificado_checklist sem item marcado, ou
  --    manter e abrir CERTIFICADO_INCONSISTENTE — é do card 8.3: a tabela não
  --    existe. O teste 052 §11 é o portão que reprova a suíte no dia em que ela
  --    nascer sem esta função a citar, pela mesma forma do gate de FORMADO
  --    (card 4.2).
  --
  -- E o passo 6 continua valendo por AUSÊNCIA de código: um estorno NÃO reverte o
  -- reordenamento da trilha por falta de estoque. O histórico em
  -- aluno_material_hist continua contando o que aconteceu, e desfazer a
  -- reordenação inventaria uma trilha que nunca existiu.

  return v_estorno;
end $$;

comment on function public.fn_estornar_entrega(uuid, text) is
  'Estorna uma SAIDA de entrega (card 2.2 §6.3): grava o movimento ESTORNO com sinal oposto e estorno_de_id, e devolve o item da trilha a PENDENTE. Exige estoque.estornar e motivo. O movimento original NUNCA é alterado nem apagado. Não reverte o reordenamento por falta de estoque — o histórico conta o que aconteceu.';

revoke execute on function public.fn_estornar_entrega(uuid, text) from public;
revoke execute on function public.fn_estornar_entrega(uuid, text) from anon;
grant  execute on function public.fn_estornar_entrega(uuid, text) to authenticated;
