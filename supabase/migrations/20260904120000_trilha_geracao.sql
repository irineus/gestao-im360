-- =============================================================================
-- Card 6.2 — Geração da trilha pelo combo na matrícula e edição manual
--
-- Fonte: docs/regras-negocio-funcoes.md §5 (trilha), §3.2 (os dois triggers em
--        `aluno`), §13 (mapa função → card) e §14 (ajuste 4),
--        docs/estrategia-testes.md §13 (obrigação de teste de função de
--        aplicação) e §14 (decisões que precisam de teste),
--        docs/views-leitura.md §8.1 e §12.1 (o contrato de `em_fim` e o nome
--        `v_aluno_trilha`, que é do card 6.6 e NÃO nasce aqui),
--        docs/permissoes-matriz.md §4 (políticas de `aluno_material`).
--
-- Entrega:
--   • `aluno_material_hist.observacao` — ajuste 4 do §14 do card 2.2, que
--     estava atribuído a ESTE card porque é ele quem escreve na tabela;
--   • as três consultas derivadas: fn_trilha_proximo_material, fn_trilha_atual e
--     fn_trilha_em_fim — "livro atual" e "próximo" continuam sendo DERIVADOS, e
--     nenhuma coluna os guarda (decisão 2.2 (e));
--   • fn_trilha_gerar — a expansão combo → curso → material;
--   • fn_trilha_inserir / fn_trilha_remover / fn_trilha_reordenar — a edição
--     manual do §5.3;
--   • tg_aluno_trilha_inicial e tg_aluno_combo_alterado — os dois triggers em
--     `aluno` que o card 4.2 deixou nomeados e que o portão do teste 030 §6 cobra
--     desde que a geração da trilha exista;
--   • a correção de uma política do card 6.1 (seção 2), que este card é o
--     primeiro a precisar.
--
-- ⚠️ ESTRUTURA E MAIS NADA, como o 6.1: nenhuma linha de trilha entra aqui. A
--    trilha real vem pelo importador do card 9.1, no ambiente dev, e alcança
--    produção uma única vez na virada do card 9.7 (decisão de 02/09/2026). O
--    portão do card 4.0,5 tem `aluno_material` fora da lista permitida, e a
--    varredura segue as chamadas transitivamente: uma carga escondida dentro de
--    fn_trilha_gerar reprovaria, que é exatamente o disfarce que ele existe para
--    barrar.
--
-- Nenhum código de erro é inventado sem necessidade: ALUNO_SEM_COMBO,
-- TRILHA_JA_EXISTE, TRILHA_COM_ENTREGA, ITEM_JA_ENTREGUE, MATERIAL_FORA_DA_TRILHA,
-- ALUNO_INEXISTENTE, MOTIVO_OBRIGATORIO e SEM_PERMISSAO já estavam no contrato.
-- O ÚNICO novo é `MATERIAL_JA_NA_TRILHA` (409, contrato de 40 → 41), e ele existe
-- porque sem ele a segunda inclusão da mesma apostila chega à tela como um
-- `23505` cru da `aluno_material_uk` — que é o que o card 2.2 §1.2 proíbe.
--
-- ⚠️ ACHADO PARA O CARD 6.3, e está escrito aqui porque é aqui que ele aparece:
--    `fn_registrar_entrega` roda na transação do MONITOR e o §6.2 do card 2.2 diz
--    que o caminho REORDENADA chama `fn_trilha_reordenar`. Só que o monitor NÃO
--    TEM `alunos.editar_trilha` (card 2.4 §5) e o trigger
--    `tg_aluno_material_colunas_permitidas` (card 6.1, seção 9) recusa qualquer
--    escrita em `ordem` sem essa permissão. Os dois documentos estão certos
--    separadamente e incompatíveis juntos. Este card NÃO afrouxa nem a permissão
--    do §5.3 nem a guarda do 6.1 para acomodar um card que ainda não começou —
--    afrouxar aqui esconderia a decisão dentro de uma função de outro assunto. A
--    escolha (fn_registrar_entrega `security definer`, ou uma exceção explícita
--    na guarda para a reordenação por falta de estoque) é do card 6.3, e está
--    registrada nas Notas dele.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. `aluno_material_hist.observacao` — ajuste 4 do §14 do card 2.2
-- -----------------------------------------------------------------------------
-- O card 6.1 deixou a tabela sem a coluna de propósito: acrescentá-la lá daria
-- uma coluna sem escritor. Aqui ela ganha o escritor no mesmo commit.
--
-- `motivo` é um `check` fechado de quatro valores e responde "o que aconteceu";
-- `observacao` responde "por quê", e é a pergunta que o pedagógico faz três meses
-- depois ("por que este aluno pulou a apostila 7"). O reordenamento automático do
-- card 6.3 não precisa dela — `SEM_ESTOQUE` já diz tudo —, a remoção manual
-- precisa, e é por isso que ela é obrigatória em fn_trilha_remover e inexistente
-- na assinatura das outras duas (§5.3 fixa as três assinaturas).
alter table public.aluno_material_hist add column observacao text;

comment on column public.aluno_material_hist.observacao is
  'Texto livre do humano que editou a trilha (ajuste 4 do §14 do card 2.2). `motivo` diz O QUE aconteceu, com quatro valores fechados; esta coluna diz POR QUE, e só a remoção manual a exige — o reordenamento automático do card 6.3 não tem nada a acrescentar a SEM_ESTOQUE.';

-- -----------------------------------------------------------------------------
-- 2. Correção de uma política do card 6.1 — a assimetria que este card encontrou
-- -----------------------------------------------------------------------------
-- O card 6.1 escreveu, com razão, o `insert` de `aluno_material` aceitando
-- `alunos.editar_trilha` OU `alunos.criar`, "porque a trilha nasce na MATRÍCULA,
-- dentro da transação de quem cadastrou o aluno". Mas o `insert` de
-- `aluno_material_hist` ficou com `alunos.editar_trilha` OU `estoque.lancar_saida`
-- — sem `alunos.criar`.
--
-- Enquanto ninguém escrevia histórico na geração, a assimetria não tinha
-- consequência. Ela passa a ter agora: fn_trilha_gerar grava uma linha
-- `GERACAO_COMBO` por item (§5.3), então um perfil com `alunos.criar` e SEM
-- `alunos.editar_trilha` conseguiria criar o aluno e a trilha e falharia no
-- histórico — com erro OPACO de RLS, numa tela de cadastro que não fala de
-- histórico de trilha, e depois de as duas primeiras escritas já terem passado.
--
-- Nenhum perfil da matriz INICIAL é assim (quem tem `alunos.criar` tem
-- `alunos.editar_trilha`), e o card 4.2 já deixou escrito que isso não é
-- argumento: a matriz é editável na tela do card 4.7 desde o primeiro dia.
--
-- A correção é acrescentar `alunos.criar` — a mesma condição da tabela-mãe. É
-- ampliação mínima e simétrica: quem pode criar a trilha pode registrar que a
-- criou.
drop policy aluno_material_hist_ins on public.aluno_material_hist;

create policy aluno_material_hist_ins on public.aluno_material_hist
  for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('alunos.editar_trilha')
                   or public.tem_permissao('alunos.criar')
                   or public.tem_permissao('estoque.lancar_saida')));

-- -----------------------------------------------------------------------------
-- 3. As três consultas derivadas (§5.2)
-- -----------------------------------------------------------------------------
-- `stable` e `security invoker`: elas leem `aluno_material`, e a RLS de quem
-- chama é exatamente o filtro certo — quem não pode ler a trilha de um aluno não
-- pode saber qual é o próximo livro dele. Não entram na lista fechada do C8.
--
-- ⚠️ Uma consequência que vale escrever, porque as três a herdam: sob RLS, "não
--    tenho `alunos.ler`" e "a trilha acabou" respondem a MESMA COISA (nulo /
--    true). É a redução silenciosa que o card 2.3 §3.4 cataloga. Aqui ela é
--    aceita de propósito, e a razão é que a alternativa é pior: `security
--    definer` faria a função responder sobre alunos que o chamador não pode ver.
--    Quem protege a tela é a guarda de rota do card 2.4 §6 (a ficha do aluno
--    exige `alunos.ler`), e quem protege a ESCRITA é fn_exige_permissao nas
--    funções da seção 5 — que é onde o dano existiria.
create or replace function public.fn_trilha_proximo_material(p_aluno_id uuid)
returns uuid
language sql
stable
set search_path = public, pg_temp
as $$
  select am.material_id
    from public.aluno_material am
   where am.aluno_id = p_aluno_id
     and not am.entregue
   order by am.ordem
   limit 1;
$$;

comment on function public.fn_trilha_proximo_material(uuid) is
  'Próximo livro da trilha: a menor `ordem` ainda não entregue. NULO = trilha em FIM (ou aluno sem trilha). Derivado a cada consulta — o card 2.2 (e) proíbe a coluna que o guardaria, porque ela sai de sincronia no primeiro estorno.';

revoke execute on function public.fn_trilha_proximo_material(uuid) from public;
revoke execute on function public.fn_trilha_proximo_material(uuid) from anon;
grant  execute on function public.fn_trilha_proximo_material(uuid) to authenticated;

-- "Livro atual" e "próximo" são o MESMO item enquanto ele não é entregue, e o
-- plano usa as duas palavras. Duas funções com um corpo só é mais barato do que
-- uma tela ter de saber que os dois nomes do plano apontam para a mesma coisa —
-- e, quando um dos dois deixar de ser sinônimo, muda uma função e não as duas.
create or replace function public.fn_trilha_atual(p_aluno_id uuid)
returns uuid
language sql
stable
set search_path = public, pg_temp
as $$
  select public.fn_trilha_proximo_material(p_aluno_id);
$$;

comment on function public.fn_trilha_atual(uuid) is
  'Sinônimo de fn_trilha_proximo_material — o "livro atual" do plano (§5.2 do card 2.2). O corpo é uma linha chamando a outra, de propósito: duas leituras do mesmo número nunca podem divergir.';

revoke execute on function public.fn_trilha_atual(uuid) from public;
revoke execute on function public.fn_trilha_atual(uuid) from anon;
grant  execute on function public.fn_trilha_atual(uuid) to authenticated;

-- ⚠️ FIM é "nenhum item PENDENTE", e não "todos os itens entregues": aluno sem
--    trilha nenhuma também devolve `true`. É a MESMA leitura da coluna `em_fim`
--    de v_dashboard_alunos_metodo (card 2.3 §8.1, `pend.qtd = 0`), e manter as
--    duas iguais é o que impede o dashboard e a ficha de discordarem sobre o
--    mesmo aluno. Quem precisa distinguir "acabou" de "nunca começou" pergunta
--    pela trilha, não por esta função.
create or replace function public.fn_trilha_em_fim(p_aluno_id uuid)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select not exists (select 1
                       from public.aluno_material am
                      where am.aluno_id = p_aluno_id
                        and not am.entregue);
$$;

comment on function public.fn_trilha_em_fim(uuid) is
  'Verdadeiro quando não há item pendente na trilha. Mesma leitura de `em_fim` em v_dashboard_alunos_metodo (card 2.3 §8.1): aluno SEM trilha também é FIM, e distinguir os dois é pergunta para quem lê a trilha.';

revoke execute on function public.fn_trilha_em_fim(uuid) from public;
revoke execute on function public.fn_trilha_em_fim(uuid) from anon;
grant  execute on function public.fn_trilha_em_fim(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. fn_trilha_gerar — a expansão combo → curso → material (§5.1)
-- -----------------------------------------------------------------------------
-- A permissão é `alunos.editar_trilha` OU `alunos.criar`, e não uma das duas
-- sozinha: é a MESMA condição da política de `insert` de `aluno_material` (card
-- 6.1 §8.1), e pelo mesmo motivo escrito lá — a trilha nasce na matrícula, dentro
-- da transação de quem cadastrou o aluno, e a regeneração pelo botão do card 6.6
-- é edição de trilha. Exigir só `alunos.editar_trilha` faria a matrícula falhar
-- para um perfil que pode matricular; exigir só `alunos.criar` deixaria a
-- regeneração fora do controle que a nomeia.
--
-- ⚠️ A numeração é de 10 em 10 (§5.1, passo 4), e não é estética: é o espaço que
--    permite a fn_trilha_inserir da seção 5 colocar um item entre dois sem
--    renumerar a trilha inteira. Quem trocar por 1, 2, 3 não quebra nada
--    imediatamente — quebra a inserção, que passa a renumerar sempre.
create or replace function public.fn_trilha_gerar(
  p_aluno_id    uuid,
  p_combo_id    uuid    default null,
  p_substituir  boolean default false
)
returns integer
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade   uuid;
  v_combo     uuid;
  v_aluno_ok  boolean;
  v_pendentes integer;
  v_entregues integer;
  v_n         integer;
begin
  if not (public.tem_permissao('alunos.editar_trilha')
          or public.tem_permissao('alunos.criar')) then
    raise exception using
      errcode = 'PT403',
      message = 'Você não tem permissão para gerar a trilha deste aluno.',
      -- O `codigo` é o do contrato (SEM_PERMISSAO) e o DETAIL carrega as DUAS
      -- permissões que serviriam: uma mensagem que nomeia só uma das duas manda
      -- a direção conceder a permissão errada.
      detail  = json_build_object('codigo', 'SEM_PERMISSAO',
                                  'permissao', 'alunos.editar_trilha|alunos.criar')::text,
      hint    = 'Peça à direção para conceder uma das duas permissões ao seu perfil.';
  end if;

  select a.unidade_id, a.combo_id, true
    into v_unidade, v_combo, v_aluno_ok
    from public.aluno a
   where a.id = p_aluno_id;

  -- Nulo aqui é ERRO e não "sem opinião" — a lição do card 5.3. A leitura é
  -- `invoker`, então aluno de outra unidade e aluno inexistente respondem a mesma
  -- coisa, e é o desfecho certo: quem não pode ver não descobre que existe.
  if v_aluno_ok is not true then
    raise exception using
      errcode = 'PT404',
      message = 'Aluno não encontrado.',
      detail  = json_build_object('codigo', 'ALUNO_INEXISTENTE',
                                  'aluno', p_aluno_id)::text;
  end if;

  v_combo := coalesce(p_combo_id, v_combo);

  if v_combo is null then
    raise exception using
      errcode = 'PT422',
      message = 'O aluno não tem combo definido — não há de onde gerar a trilha.',
      detail  = json_build_object('codigo', 'ALUNO_SEM_COMBO',
                                  'aluno', p_aluno_id)::text;
  end if;

  select count(*) filter (where not am.entregue),
         count(*) filter (where am.entregue)
    into v_pendentes, v_entregues
    from public.aluno_material am
   where am.aluno_id = p_aluno_id;

  if v_pendentes + v_entregues > 0 then
    if not p_substituir then
      raise exception using
        errcode = 'PT409',
        message = 'Este aluno já tem trilha.',
        detail  = json_build_object('codigo', 'TRILHA_JA_EXISTE',
                                    'aluno', p_aluno_id,
                                    'itens', v_pendentes + v_entregues)::text,
        hint    = 'Para gerar de novo, use a opção de substituir.';
    end if;

    -- Substituir uma trilha COM ENTREGA apagaria a única ligação entre a SAIDA de
    -- estoque e o aluno que a recebeu — e a apostila poderia ser entregue outra
    -- vez, com cara de entrega legítima. É a mesma perda que a guarda de exclusão
    -- do card 6.1 §10.1 fecha, aqui pelo atacado.
    if v_entregues > 0 then
      raise exception using
        errcode = 'PT409',
        message = 'A trilha já tem apostila entregue e não pode ser regenerada.',
        detail  = json_build_object('codigo', 'TRILHA_COM_ENTREGA',
                                    'aluno', p_aluno_id,
                                    'entregues', v_entregues)::text,
        hint    = 'Edite a trilha item a item em vez de substituí-la.';
    end if;

    -- A trilha antiga sai com rastro. Sem estas linhas, uma regeneração deixaria
    -- a trilha diferente do que era e nada explicando a diferença — que é o
    -- silêncio que `aluno_material_hist` existe para impedir.
    insert into public.aluno_material_hist
      (unidade_id, aluno_id, material_id, ordem_anterior, ordem_nova, motivo,
       usuario_id, observacao)
    select am.unidade_id, am.aluno_id, am.material_id, am.ordem, null, 'REMOCAO',
           auth.uid(), 'substituída pela geração a partir do combo'
      from public.aluno_material am
     where am.aluno_id = p_aluno_id;

    delete from public.aluno_material am where am.aluno_id = p_aluno_id;
  end if;

  -- A expansão. Três coisas que a consulta não pode simplificar:
  --   (a) a ordem sai do PAR (combo_curso.ordem, curso_material.ordem):
  --       `curso_material.ordem` é a posição dentro do CURSO, então um combo com
  --       dois cursos tem duas apostilas com ordem 1 — usá-la sozinha derrubaria
  --       o insert em `aluno_material_ordem_uk`, ou, num combo de um curso só,
  --       passaria e deixaria a trilha errada sem nada acusando;
  --   (b) `distinct on (cm.material_id)` faz o material repetido entre cursos do
  --       combo entrar UMA vez, na PRIMEIRA posição em que aparece (§5.1, passo
  --       5) — sem isso, `aluno_material_uk` recusaria a segunda e a matrícula
  --       inteira morreria num 23505 cru;
  --   (c) a numeração de 10 em 10 vem de `row_number()` sobre o resultado já
  --       deduplicado, e não das ordens de origem: material removido de um curso
  --       deixaria buraco, e buraco na origem vira buraco na trilha.
  with itens as (
    select distinct on (cm.material_id)
           cm.material_id, cc.ordem as ordem_combo, cm.ordem as ordem_curso
      from public.combo_curso cc
      join public.curso_material cm on cm.curso_id = cc.curso_id
     where cc.combo_id = v_combo
     order by cm.material_id, cc.ordem, cm.ordem
  ),
  numerados as (
    select material_id,
           (row_number() over (order by ordem_combo, ordem_curso, material_id) * 10)::integer as ordem
      from itens
  ),
  criados as (
    insert into public.aluno_material (unidade_id, aluno_id, material_id, ordem, origem)
    select v_unidade, p_aluno_id, n.material_id, n.ordem, 'COMBO'
      from numerados n
    returning material_id, ordem
  )
  insert into public.aluno_material_hist
    (unidade_id, aluno_id, material_id, ordem_anterior, ordem_nova, motivo, usuario_id)
  select v_unidade, p_aluno_id, c.material_id, null, c.ordem, 'GERACAO_COMBO', auth.uid()
    from criados c;

  get diagnostics v_n = row_count;

  -- A trilha passou a corresponder ao combo: se havia pendência de divergência
  -- (aberta por tg_aluno_combo_alterado, seção 6), a condição sumiu. Pendência
  -- que ninguém fecha é pendência que a central do card 5.8 mostra para sempre, e
  -- o desfecho é a central inteira perder credibilidade.
  perform public.fn_pendencia_resolver('TRILHA_COMBO:' || p_aluno_id::text);

  return v_n;
end $$;

comment on function public.fn_trilha_gerar(uuid, uuid, boolean) is
  'Gera a trilha do aluno expandindo combo → curso → material, numerando de 10 em 10 e com origem COMBO (card 2.2 §5.1). Recusa sobrescrever trilha existente sem p_substituir (TRILHA_JA_EXISTE) e recusa sempre substituir trilha com entrega (TRILHA_COM_ENTREGA). Fecha a pendência TRILHA_DIVERGENTE_COMBO do aluno.';

revoke execute on function public.fn_trilha_gerar(uuid, uuid, boolean) from public;
revoke execute on function public.fn_trilha_gerar(uuid, uuid, boolean) from anon;
grant  execute on function public.fn_trilha_gerar(uuid, uuid, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Edição manual (§5.3)
-- -----------------------------------------------------------------------------
-- As três exigem `alunos.editar_trilha`, marcam `origem = 'MANUAL'` no que
-- tocam, recusam mexer em item já entregue e gravam `aluno_material_hist`.
--
-- ⚠️ `p_motivo` de fn_trilha_remover NÃO é o `motivo` da tabela. O `motivo` da
--    tabela é o `check` fechado de quatro valores e vale `REMOCAO` aqui, sempre;
--    o parâmetro é o texto livre que vai para `observacao` — é para isso que a
--    coluna nasceu na seção 1, e é a leitura que resolve a colisão de nome entre
--    a assinatura do §5.3 e a coluna do §14 (ajuste 4).

-- 5.1 Inserir
--
-- A posição sai do ESPAÇO entre `p_apos_material_id` e o item seguinte, e é para
-- isso que a geração numera de 10 em 10. `p_apos_material_id` nulo põe o item no
-- começo da trilha.
--
-- ⚠️ O espaço ACABA: quatro inclusões seguidas na mesma fresta esgotam o intervalo
--    (10 → 5 → 2 → 1 → sem espaço). Sem tratar isso, a quinta cairia em cima da
--    ordem existente e morreria num 23505 cru — ou, pior, se a `unique` não
--    existisse, produziria duas apostilas na mesma posição. O caminho é
--    RENUMERAR a trilha inteira de 10 em 10 (num único UPDATE, que é o que o
--    `deferrable initially deferred` do card 2.1 (e) compra) e tentar de novo:
--    a renumeração preserva a ordem relativa, então ninguém vê diferença — só o
--    espaço volta.
create or replace function public.fn_trilha_inserir(
  p_aluno_id         uuid,
  p_material_id      uuid,
  p_apos_material_id uuid default null
)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade   uuid;
  v_aluno_ok  boolean;
  v_anterior  integer;
  v_seguinte  integer;
  v_nova      integer;
  v_id        uuid;
begin
  perform public.fn_exige_permissao('alunos.editar_trilha');

  select a.unidade_id, true into v_unidade, v_aluno_ok
    from public.aluno a where a.id = p_aluno_id;

  if v_aluno_ok is not true then
    raise exception using
      errcode = 'PT404',
      message = 'Aluno não encontrado.',
      detail  = json_build_object('codigo', 'ALUNO_INEXISTENTE',
                                  'aluno', p_aluno_id)::text;
  end if;

  if exists (select 1 from public.aluno_material am
              where am.aluno_id = p_aluno_id and am.material_id = p_material_id) then
    raise exception using
      errcode = 'PT409',
      message = 'Esta apostila já está na trilha do aluno.',
      detail  = json_build_object('codigo', 'MATERIAL_JA_NA_TRILHA',
                                  'aluno', p_aluno_id,
                                  'material', p_material_id)::text,
      hint    = 'Para mudá-la de lugar, use a reordenação.';
  end if;

  if p_apos_material_id is null then
    v_anterior := 0;
  else
    select am.ordem into v_anterior
      from public.aluno_material am
     where am.aluno_id = p_aluno_id and am.material_id = p_apos_material_id;

    if v_anterior is null then
      raise exception using
        errcode = 'PT422',
        message = 'A apostila indicada como referência não está na trilha do aluno.',
        detail  = json_build_object('codigo', 'MATERIAL_FORA_DA_TRILHA',
                                    'aluno', p_aluno_id,
                                    'material', p_apos_material_id)::text;
    end if;
  end if;

  select min(am.ordem) into v_seguinte
    from public.aluno_material am
   where am.aluno_id = p_aluno_id and am.ordem > v_anterior;

  v_nova := case when v_seguinte is null
                 then v_anterior + 10
                 else (v_anterior + v_seguinte) / 2
            end;

  -- Sem espaço entre os dois: renumera de 10 em 10 e recalcula. Duas passagens no
  -- pior caso, e o pior caso é raro — mas escrito, porque o que não está escrito
  -- é o que falha em produção às 19h de uma segunda-feira.
  if v_nova <= v_anterior or (v_seguinte is not null and v_nova >= v_seguinte) then
    update public.aluno_material am
       set ordem = r.nova
      from (select am2.id, (row_number() over (order by am2.ordem) * 10)::integer as nova
              from public.aluno_material am2
             where am2.aluno_id = p_aluno_id) r
     where am.id = r.id and am.ordem is distinct from r.nova;

    if p_apos_material_id is null then
      v_anterior := 0;
    else
      select am.ordem into v_anterior
        from public.aluno_material am
       where am.aluno_id = p_aluno_id and am.material_id = p_apos_material_id;
    end if;

    select min(am.ordem) into v_seguinte
      from public.aluno_material am
     where am.aluno_id = p_aluno_id and am.ordem > v_anterior;

    v_nova := case when v_seguinte is null
                   then v_anterior + 10
                   else (v_anterior + v_seguinte) / 2
              end;
  end if;

  insert into public.aluno_material (unidade_id, aluno_id, material_id, ordem, origem)
  values (v_unidade, p_aluno_id, p_material_id, v_nova, 'MANUAL')
  returning id into v_id;

  insert into public.aluno_material_hist
    (unidade_id, aluno_id, material_id, ordem_anterior, ordem_nova, motivo, usuario_id)
  values (v_unidade, p_aluno_id, p_material_id, null, v_nova, 'MANUAL', auth.uid());

  return v_id;
end $$;

comment on function public.fn_trilha_inserir(uuid, uuid, uuid) is
  'Inclui uma apostila na trilha, com origem MANUAL, logo depois de p_apos_material_id (nulo = no começo). Usa o espaço da numeração de 10 em 10 e renumera a trilha quando o espaço acaba. Exige alunos.editar_trilha e grava aluno_material_hist.';

revoke execute on function public.fn_trilha_inserir(uuid, uuid, uuid) from public;
revoke execute on function public.fn_trilha_inserir(uuid, uuid, uuid) from anon;
grant  execute on function public.fn_trilha_inserir(uuid, uuid, uuid) to authenticated;

-- 5.2 Remover
--
-- Item ENTREGUE não sai da trilha, e a razão está no card 6.1 §10.1: a linha
-- entregue é a única ligação entre a SAIDA de estoque e o aluno que a recebeu.
-- Aqui a recusa vem ANTES do `delete`, com a mensagem certa; a guarda do 6.1
-- continua embaixo, para o `DELETE` direto pelo PostgREST. Camada 3 e camada 2 do
-- card 2.2 §1, e não redundância.
create or replace function public.fn_trilha_remover(
  p_aluno_id    uuid,
  p_material_id uuid,
  p_motivo      text
)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade  uuid;
  v_ordem    integer;
  v_entregue boolean;
begin
  perform public.fn_exige_permissao('alunos.editar_trilha');

  -- Motivo obrigatório, pelo precedente de fn_estornar_entrega e
  -- fn_rep_voltar_pontual: tirar uma apostila da trilha de um aluno é decisão, e
  -- decisão sem porquê é decisão perdida.
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception using
      errcode = 'PT422',
      message = 'Informe o motivo da remoção da apostila da trilha.',
      detail  = json_build_object('codigo', 'MOTIVO_OBRIGATORIO',
                                  'aluno', p_aluno_id,
                                  'material', p_material_id)::text;
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
      message = 'Esta apostila já foi entregue e não pode ser removida da trilha.',
      detail  = json_build_object('codigo', 'ITEM_JA_ENTREGUE',
                                  'aluno', p_aluno_id,
                                  'material', p_material_id)::text,
      hint    = 'Estorne a entrega primeiro.';
  end if;

  -- O histórico vem ANTES do delete: `aluno_material_hist` não tem FK para
  -- `aluno_material`, mas escrever depois deixaria a janela em que uma falha no
  -- meio apaga o item sem registrar nada.
  insert into public.aluno_material_hist
    (unidade_id, aluno_id, material_id, ordem_anterior, ordem_nova, motivo,
     usuario_id, observacao)
  values (v_unidade, p_aluno_id, p_material_id, v_ordem, null, 'REMOCAO',
          auth.uid(), p_motivo);

  delete from public.aluno_material am
   where am.aluno_id = p_aluno_id and am.material_id = p_material_id;
end $$;

comment on function public.fn_trilha_remover(uuid, uuid, text) is
  'Remove um item PENDENTE da trilha, com motivo obrigatório (que vai para aluno_material_hist.observacao; o `motivo` da tabela é REMOCAO). Recusa item entregue (ITEM_JA_ENTREGUE) — a guarda do card 6.1 §10.1 é a mesma regra na camada de baixo.';

revoke execute on function public.fn_trilha_remover(uuid, uuid, text) from public;
revoke execute on function public.fn_trilha_remover(uuid, uuid, text) from anon;
grant  execute on function public.fn_trilha_remover(uuid, uuid, text) to authenticated;

-- 5.3 Reordenar
--
-- ⚠️ DECISÃO DE CONTRATO: `p_nova_ordem` é a POSIÇÃO na trilha (1 = primeiro),
--    e NÃO o valor bruto da coluna `ordem`. O §5.3 do card 2.2 dá a assinatura e
--    não diz qual das duas; as duas leituras são possíveis e a diferença é
--    visível na tela.
--
--    A posição é a leitura certa por três razões: (a) a tela do card 6.6 arrasta
--    um item para "a terceira linha" e não para "a ordem 30" — a numeração de 10
--    em 10 é artefato interno desta migração, e contrato que vaza artefato interno
--    obriga a tela a conhecê-lo; (b) `ordem` bruta como parâmetro tornaria o
--    resultado dependente de a trilha ter ou não sido renumerada por uma inclusão
--    anterior, e o mesmo comando daria resultados diferentes em dois alunos com a
--    mesma trilha; (c) o card 6.3 chama esta função para pôr um material "na
--    posição do pulado" (§6.2, passo 6), que é literalmente uma posição.
--
--    A escrita é UM ÚNICO UPDATE sobre a trilha inteira, renumerando de 10 em 10
--    na nova sequência. É exatamente o que o `unique (aluno_id, ordem) deferrable
--    initially deferred` do card 2.1 (e) existe para permitir — sem ele seria
--    preciso um valor temporário, que é um estado inválido sobrevivendo a
--    qualquer falha no meio.
create or replace function public.fn_trilha_reordenar(
  p_aluno_id    uuid,
  p_material_id uuid,
  p_nova_ordem  integer
)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade  uuid;
  v_ordem    integer;
  v_entregue boolean;
  v_total    integer;
  v_destino  integer;
  v_ordem_nova integer;
begin
  perform public.fn_exige_permissao('alunos.editar_trilha');

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

  -- Posição fora da trilha é grampeada nas bordas em vez de virar erro: arrastar
  -- para além do fim é um gesto comum na tela e significa "põe no fim". Erro aqui
  -- seria pedir à pessoa que acertasse um número que ela não digitou.
  v_destino := least(greatest(coalesce(p_nova_ordem, v_total), 1), v_total);

  -- A sequência nova: todo mundo menos o movido, com o movido enfiado na posição
  -- `v_destino`. `row_number()` sobre essa sequência dá a numeração final.
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

  -- `origem = MANUAL` marca a linha como fora da geração pelo combo: é o que
  -- permite a uma regeneração futura distinguir o que veio do catálogo do que uma
  -- pessoa decidiu. Só a linha MOVIDA muda de origem — as outras foram empurradas,
  -- não editadas.
  update public.aluno_material am
     set origem = 'MANUAL'
   where am.aluno_id = p_aluno_id and am.material_id = p_material_id
     and am.origem <> 'MANUAL';

  insert into public.aluno_material_hist
    (unidade_id, aluno_id, material_id, ordem_anterior, ordem_nova, motivo, usuario_id)
  values (v_unidade, p_aluno_id, p_material_id, v_ordem, v_ordem_nova, 'MANUAL', auth.uid());
end $$;

comment on function public.fn_trilha_reordenar(uuid, uuid, integer) is
  'Move uma apostila PENDENTE para a POSIÇÃO p_nova_ordem da trilha (1 = primeiro; fora das bordas é grampeado). Renumera a trilha de 10 em 10 num único UPDATE, o que o unique DEFERRABLE do card 2.1 (e) permite. Exige alunos.editar_trilha, marca a linha movida como MANUAL e grava aluno_material_hist.';

revoke execute on function public.fn_trilha_reordenar(uuid, uuid, integer) from public;
revoke execute on function public.fn_trilha_reordenar(uuid, uuid, integer) from anon;
grant  execute on function public.fn_trilha_reordenar(uuid, uuid, integer) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. Os dois triggers em `aluno` (§3.2)
-- -----------------------------------------------------------------------------
-- 6.1 tg_aluno_trilha_inicial — a trilha nasce na matrícula.
--
-- Sem ele, fn_trilha_gerar seria uma função entregue, testada e SEM CHAMADOR: a
-- família de defeito do card 4.7,7, e é ela que o portão do teste 030 §6 vigia.
-- A trilha só apareceria se alguém se lembrasse de clicar num botão — e "regra
-- que depende de alguém lembrar não serve" (card 3.12 (d)).
create or replace function public.fn_aluno_trilha_inicial()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  perform public.fn_trilha_gerar(new.id);
  return null;   -- AFTER trigger: o retorno é ignorado
end $$;

comment on function public.fn_aluno_trilha_inicial() is
  'Trigger AFTER INSERT em `aluno` (só quando combo_id não é nulo): gera a trilha pelo combo (card 2.2 §3.2). É o que impede fn_trilha_gerar de nascer sem chamador.';

revoke execute on function public.fn_aluno_trilha_inicial() from public;
revoke execute on function public.fn_aluno_trilha_inicial() from anon;

-- O `when` no trigger, e não um `if` no corpo: aluno sem combo é caso normal (a
-- matrícula pode ser feita antes de o combo estar decidido), e fn_trilha_gerar
-- levantaria ALUNO_SEM_COMBO, derrubando o cadastro inteiro.
create trigger tg_aluno_trilha_inicial
  after insert on public.aluno
  for each row when (new.combo_id is not null)
  execute function public.fn_aluno_trilha_inicial();

-- 6.2 tg_aluno_combo_alterado — trocar o combo NÃO regenera a trilha.
--
-- Regenerar apagaria entregas já feitas ou duplicaria saídas de estoque (card 2.2
-- §3.2). A pendência põe um humano na decisão, e a tela do card 6.6 oferece o
-- botão que chama fn_trilha_gerar(..., p_substituir => true) — que, por sua vez,
-- só aceita enquanto não houver item entregue e fecha esta pendência ao terminar.
create or replace function public.fn_aluno_combo_alterado()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_itens integer;
begin
  select count(*) into v_itens
    from public.aluno_material am where am.aluno_id = new.id;

  -- O tipo é LITERAL na chamada, e é obrigação de contrato: o C10 do card 2.8
  -- extrai o primeiro argumento de fn_pendencia_abrir do `prosrc` e o confere
  -- contra o `check` de pendencia.tipo. Uma variável aqui cegaria o teste em
  -- silêncio.
  perform public.fn_pendencia_abrir(
    'TRILHA_DIVERGENTE_COMBO',
    'TRILHA_COMBO:' || new.id::text,
    format('O combo do aluno mudou e a trilha continua a do combo anterior (%s item(ns)). Regenere a trilha ou ajuste item a item.',
           v_itens),
    'MEDIA',
    new.id);

  return null;
end $$;

comment on function public.fn_aluno_combo_alterado() is
  'Trigger AFTER UPDATE OF combo_id em `aluno`: abre a pendência TRILHA_DIVERGENTE_COMBO em vez de regenerar a trilha (card 2.2 §3.2) — regenerar apagaria entregas ou duplicaria saídas de estoque. fn_trilha_gerar fecha a pendência quando o humano decide regenerar.';

revoke execute on function public.fn_aluno_combo_alterado() from public;
revoke execute on function public.fn_aluno_combo_alterado() from anon;

-- `when (new.combo_id is distinct from old.combo_id)`: o `update of combo_id` do
-- Postgres dispara quando a coluna está na lista do UPDATE, mesmo que o valor não
-- mude — e uma pendência aberta por gravar o mesmo combo de novo seria ruído na
-- central do card 5.8. `is distinct from` cobre os nulos dos dois lados, que é o
-- caso do aluno que ganha combo depois da matrícula.
create trigger tg_aluno_combo_alterado
  after update of combo_id on public.aluno
  for each row when (new.combo_id is distinct from old.combo_id)
  execute function public.fn_aluno_combo_alterado();
