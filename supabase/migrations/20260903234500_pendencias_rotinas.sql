-- =============================================================================
-- Card 5.5 — Schema e rotina de pendências
--            (pendencia, fn_pendencia_abrir/resolver/resolver_id,
--             rt_pendencias_diaria, rt_rep_avaliar, rt_diaria, o job pg_cron
--             e a view v_pendencias_abertas)
-- Fonte: docs/modelagem-dados-ddl.md §10 (tabela) e §11 (mapa → card 5.5),
--        docs/regras-negocio-funcoes.md §10 (as três funções), §10.1 (catálogo),
--          §11 (rotinas e o job) e §14 (ajustes 2 e 6),
--        docs/regra-virada-rep.md §6 (as duas chaves com sufixo) e §7 (#1),
--        docs/views-leitura.md §9 (v_pendencias_abertas), §2 (princípios de view)
--          e §10 (ajustes 4, 5 e 8),
--        docs/permissoes-matriz.md §4 (políticas) e §3.5 (domínio `pendencias`),
--        docs/estrategia-testes.md §5.1 (C5, C10) e §17 (arquivo 090_rotinas).
--
-- Entrega: a tabela `pendencia`, as três funções do §10, a PRIMEIRA rotina
--          agendada do projeto (rt_diaria + as duas rt_* que ela orquestra), o
--          job `pg_cron` e a PRIMEIRA view do projeto.
--          Mais o fechamento das duas pendências REP em fn_rep_virar_continuo e
--          fn_rep_voltar_pontual — o portão que o card 5.3 deixou armado no
--          teste 085 e que dispara hoje, porque `pendencia` nasce aqui.
--
-- ⚠️ ESTRUTURA E MAIS NADA. Nenhuma linha de dado de negócio, e neste card a
--    regra tem uma consequência que vale escrever: PENDÊNCIA NÃO SE MIGRA E NÃO
--    SE IMPORTA. Ela é GERADA pela rotina em cada ambiente, a partir do dado que
--    aquele ambiente tem. Em produção, antes da virada do card 9.7, a rotina
--    roda todo dia e não acha nada — e é assim que tem de ser. O portão do card
--    4.0,5 (portao-migracoes/varredor.mjs) tem `pendencia` fora da lista
--    permitida e segue as chamadas transitivamente: `insert into pendencia`
--    dentro do corpo de fn_pendencia_abrir passa justamente porque a migração
--    NÃO chama a função.
--
-- O que este card NÃO traz, e onde está escrito que não é esquecimento:
--   • fn_revalidar_blocos_sala, tg_pc_manutencao_status e a pendência
--     PC_SEM_SUBSTITUTO são do card 5.4. BLOCO_ACIMA_CAPACIDADE nasce aqui
--     porque é um dos três tipos que o título deste card nomeia — e nasce na
--     ROTINA, que a vê todo dia venha a queda de capacidade de onde vier; o 5.4
--     acrescenta o caminho por EVENTO (registrou manutenção, revalida na hora),
--     reusando fn_pendencia_abrir e a MESMA chave `CAPACIDADE:<bloco_id>`, de
--     modo que os dois caminhos convergem sem duplicar pendência;
--   • rt_pcs_normaliza e rt_capacidades (5.4) e rt_projecao_demanda (8.1) são os
--     outros três passos que o §11 do card 2.2 dá a rt_diaria. Ela chama hoje só
--     as duas que existem, e o teste 090 tem o PORTÃO que reprova no dia em que
--     qualquer uma das três nascer sem entrar na orquestradora;
--   • STANDBY_PROLONGADO, PREVISAO_VENCIDA e ALUNO_ULTIMO_LIVRO são da Fase 8;
--     ESTOQUE_*, SUGERIR_FORMADO, TRILHA_DIVERGENTE_COMBO,
--     CERTIFICADO_INCONSISTENTE e COMPRA_SEM_ESTOQUE são das fases 6 e 8. Os
--     tipos entram no `check` AGORA (ver seção 1), as funções que os abrem não.
--
-- Três códigos de erro novos (contrato de 32 → 35, test/fixtures/codigos_erro.txt):
--   PENDENCIA_INEXISTENTE (404), PENDENCIA_JA_RESOLVIDA (409) e
--   RESOLUCAO_INVALIDA (422), todos de fn_pendencia_resolver_id, pelo precedente
--   de BLOCO_INEXISTENTE/ALOCACAO_INEXISTENTE (card 5.3): sem eles a tela do
--   card 5.8 recebe erro cru de `check` do Postgres, ou pior, não recebe nada.
--   A falta de justificativa ao IGNORAR reusa MOTIVO_OBRIGATORIO — mesma
--   pergunta ao usuário ("Informe o motivo para continuar"), mesmo texto de tela,
--   e código novo aqui só cresceria o contrato sem dizer nada diferente.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. pendencia — §10 do DDL do card 2.1, com os dois ajustes já embutidos
-- -----------------------------------------------------------------------------
-- DIVERGÊNCIA REGISTRADA com o ajuste 2 do §14 do card 2.2 e com o 3 do §8 do
-- card 2.5: os dois pedem `alter table` no `check` de `pendencia.tipo` para
-- acrescentar os sete tipos de REP_VIRADA em diante. Eles foram escritos quando
-- se supunha a tabela já existente; ela NASCE neste arquivo, então os quinze
-- tipos entram direto no `check`. Um `create table` com oito seguido de um
-- `alter` com sete, no mesmo arquivo, seria cerimônia sem leitor.
--
-- Os sete adiados não são tipos "de mentira": cada um tem card, chamador e chave
-- no catálogo do §10.1 do card 2.2. Entrarem agora custa uma linha e evita que a
-- migração da Fase 6 comece com um `alter constraint` — e o C10 do card 2.8
-- garante o outro lado, que é o que interessa: nenhum tipo USADO no código fica
-- de fora do `check`.
--
-- ⚠️ AJUSTE 4 do §10 do card 2.3, BLOQUEANTE e já aplicado: a severidade `INFO`
--    que o catálogo do card 2.2 deu a ACELERAR_SEM_2O_BLOCO NÃO EXISTE no
--    `check` de `severidade` (BAIXA, MEDIA, ALTA). O DDL está certo e a rotina
--    da seção 6 abre essa pendência como BAIXA. Escrita como INFO, ela falharia
--    no `check` — dentro de um `exception when others` de rt_diaria, o que a
--    transformaria em ROTINA_FALHOU todo dia, longe da causa.
--
-- ⚠️ AJUSTE 8 do §10 do card 2.3: uma nota do board escreve
--    ACELERAR_SEM_SEGUNDO_BLOCO. Vale o DDL — ACELERAR_SEM_2O_BLOCO.
create table public.pendencia (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  tipo       text not null check (tipo in (
               -- card 5.5 (este), os três tipos do título
               'ALUNO_SEM_TURMA','BLOCO_ACIMA_CAPACIDADE','ACELERAR_SEM_2O_BLOCO',
               -- card 2.5 §6, aberto e fechado por rt_rep_avaliar (seção 7)
               'REP_VIRADA',
               -- card 2.2 §11: a falha de uma rt_* não pode sumir com o log de
               -- 1 dia do Supabase (Decisões vigentes §1, card 3.12 (g))
               'ROTINA_FALHOU',
               -- card 5.4 (fn_revalidar_blocos_sala)
               'PC_SEM_SUBSTITUTO',
               -- fase 6 (fn_registrar_entrega, tg_movimento_resolve_pendencia,
               -- tg_aluno_combo_alterado, fn_estornar_entrega)
               'COMPRA_SEM_ESTOQUE','ESTOQUE_ZERO','ESTOQUE_ABAIXO_MINIMO',
               'TRILHA_DIVERGENTE_COMBO','CERTIFICADO_INCONSISTENTE',
               -- fase 8 (rt_pendencias_diaria cresce, tg_certificado_*)
               'STANDBY_PROLONGADO','PREVISAO_VENCIDA','ALUNO_ULTIMO_LIVRO',
               'SUGERIR_FORMADO')),
  severidade text not null default 'MEDIA' check (severidade in ('BAIXA','MEDIA','ALTA')),
  descricao  text not null,
  aluno_id    uuid references public.aluno(id) on delete cascade,
  bloco_id    uuid references public.bloco_horario(id) on delete cascade,
  material_id uuid references public.material(id),
  pc_id       uuid references public.pc(id),
  -- Idempotência da rotina: a mesma pendência aberta não é recriada a cada
  -- execução. Formato `<TIPO>:<id_da_referencia>`, com SUFIXO quando o mesmo
  -- tipo tem dois sentidos (card 2.5 §6: `REP:<aluno>:CONTINUO` e
  -- `REP:<aluno>:VOLTA`) — sem o sufixo o índice parcial descartaria em silêncio
  -- a sugestão de volta enquanto a de ida estivesse aberta.
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

comment on table public.pendencia is
  'A forma que o sistema tem de dizer "isto está errado, mas eu não vou decidir por você" (card 2.2 §10). Aberta e fechada por fn_pendencia_abrir/fn_pendencia_resolver; nenhum outro código escreve aqui. NÃO se migra e NÃO se importa: é gerada pela rotina em cada ambiente, a partir do dado daquele ambiente.';

comment on column public.pendencia.chave_dedup is
  'Identidade da pendência para a rotina reexecutável: `<TIPO>:<id>`, com sufixo quando o tipo tem dois sentidos. O índice parcial pendencia_aberta_uk rejeita a duplicata enquanto a anterior estiver ABERTA — fechada, a rotina reabre no dia seguinte se a condição ainda valer, inclusive a que alguém IGNOROU (ver o comentário da seção 6).';

comment on column public.pendencia.resolvida_por is
  'Quem fechou. NULO significa fechamento AUTOMÁTICO (a condição sumiu) — é o que distingue, na central do card 5.8, a pendência que se resolveu sozinha da que alguém encerrou.';

-- -----------------------------------------------------------------------------
-- 2. Índices
-- -----------------------------------------------------------------------------
-- A deduplicação inteira do projeto está nesta linha: a rotina tenta inserir
-- todo dia e o banco ignora a repetida. É por isso que rt_* não precisa
-- perguntar "já existe?" e não tem condição de corrida com a interface.
create unique index pendencia_aberta_uk
  on public.pendencia (unidade_id, chave_dedup) where resolvida_em is null;

-- Ajuste 5 do §10 do card 2.3: a central abre ordenada por severidade, só nas
-- abertas. Precaução barata, não otimização medida (§13 (2) daquele card).
create index pendencia_severidade_ix
  on public.pendencia (unidade_id, severidade) where resolvida_em is null;

-- Lados de FK que nenhuma unique cobre — mesma razão dos cards 3.3, 4.1, 4.3 e
-- 5.1: `pendencia_aberta_uk` é parcial, e índice parcial não serve a FK nunca.
-- Sem eles, `delete` de aluno ou de bloco varre a tabela inteira (as duas FKs
-- são `on delete cascade`), e o `on delete cascade` é justamente o caminho que
-- ninguém percorre à mão para reparar.
create index pendencia_aluno_ix    on public.pendencia (aluno_id);
create index pendencia_bloco_ix    on public.pendencia (bloco_id);
create index pendencia_material_ix on public.pendencia (material_id);
create index pendencia_pc_ix       on public.pendencia (pc_id);

-- -----------------------------------------------------------------------------
-- 3. Trigger de auditoria (C3 do card 2.8)
-- -----------------------------------------------------------------------------
create trigger tg_auditoria_pendencia
  before insert or update on public.pendencia
  for each row execute function public.fn_auditoria();

-- -----------------------------------------------------------------------------
-- 4. RLS habilitada, forçada, e as três políticas do card 2.4 §4
-- -----------------------------------------------------------------------------
alter table public.pendencia enable row level security;
alter table public.pendencia force  row level security;

create policy pendencia_sel on public.pendencia for select to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('pendencias.ler'));

-- ⚠️ A ÚNICA política de insert do projeto que não exige permissão de domínio
--    nenhuma, e é decisão do card 2.4 §4, não descuido: pendência é anotação do
--    sistema, aberta por fn_registrar_entrega (monitor), por
--    tg_aluno_combo_alterado (secretaria), por fn_revalidar_blocos_sala (quem
--    registrou a manutenção) e pelas rotinas. Enumerar os autores num `or`
--    produziria uma lista que cresce a cada card e cujo esquecimento aparece
--    como erro opaco de RLS numa tela que não fala de pendência.
create policy pendencia_ins on public.pendencia for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual());

create policy pendencia_upd on public.pendencia for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('pendencias.resolver'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('pendencias.resolver'));

-- Sem DELETE, e a ausência é a decisão: pendência encerrada é `resolvida_em`
-- preenchida, e apagar a linha tiraria da história justamente o que se quer
-- olhar depois — quantas vezes este bloco já estourou a capacidade.

-- -----------------------------------------------------------------------------
-- 5. As três funções do §10 do card 2.2 — e por que duas são `security definer`
-- -----------------------------------------------------------------------------
-- fn_pendencia_abrir e fn_pendencia_resolver entram na LISTA FECHADA do C8 pelo
-- mesmo motivo, e ele é o achado desta seção:
--
--   As duas são chamadas como EFEITO COLATERAL, dentro da transação de outro
--   ator — hoje fn_rep_virar_continuo (`turmas.alocar`), amanhã
--   fn_registrar_entrega (monitor) e fn_revalidar_blocos_sala (quem registra
--   manutenção). Como `invoker`, elas encontram a RLS de quem chamou, e a RLS
--   NEGA LINHA, não devolve erro: `fn_pendencia_resolver` devolveria **0
--   fechadas** e `fn_pendencia_abrir` **nenhuma linha** sem que nada
--   denunciasse. O sintoma seria a central do card 5.8 sugerindo, todo dia, uma
--   virada REP que já aconteceu — e não há como distinguir isso de "a rotina não
--   rodou". É a mesma família de falhas caladas que os cards 2.3 §3.4, 5.2 e 5.3
--   catalogam, e a mesma razão pela qual fn_capacidade_efetiva é definer.
--
--   Com a matriz INICIAL nada disso aparece: `turmas.alocar` e
--   `pendencias.resolver` estão exatamente nos mesmos três perfis. Mas a matriz
--   é editável na tela do card 4.7 desde o primeiro dia, e é o card 4.2 que
--   deixou escrito que "nenhum perfil da matriz inicial é assim" não é
--   argumento.
--
-- As duas filtram unidade no corpo (`fn_unidade_atual()`), como manda a correção
-- do card 2.3, e tratam NULO como ERRO — a lição do card 5.3: sem unidade, um
-- `where unidade_id = null` não devolve zero linhas por acaso, devolve zero
-- linhas SEMPRE, e a pendência simplesmente não existiria.
--
-- fn_pendencia_resolver_id, o fechamento HUMANO, fica `invoker` e exige
-- `pendencias.resolver`: é ali que o controle importa e é ali que ele está.
--
-- ⚠️ Limite aceito e medido: com `grant` para `authenticated`, um perfil SEM
--    `pendencias.resolver` (hoje só o monitor) alcança fn_pendencia_resolver por
--    RPC e some com uma pendência da sua unidade. O dano é limitado por
--    construção — a rotina do dia seguinte REABRE tudo o que continua verdadeiro
--    (asserção no teste 090), e a linha fica com `resolvida_por` nulo, indistinta
--    de um fechamento automático. O que `pendencias.resolver` protege de verdade
--    é o IGNORAR com justificativa, que é fn_pendencia_resolver_id. Tirar o
--    `grant` não é alternativa: as chamadoras são `invoker` e rodam como o
--    usuário, então sem ele a virada REP morre com "permission denied for
--    function" para todo mundo.
create or replace function public.fn_pendencia_abrir(
  p_tipo        text,
  p_chave_dedup text,
  p_descricao   text,
  p_severidade  text default 'MEDIA',
  p_aluno_id    uuid default null,
  p_bloco_id    uuid default null,
  p_material_id uuid default null,
  p_pc_id       uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_id      uuid;
begin
  v_unidade := public.fn_unidade_atual();

  if v_unidade is null then
    raise exception
      'fn_pendencia_abrir: sem unidade no contexto (nem sessão autenticada nem contexto de rotina). Pendência sem unidade não seria vista por ninguém.';
  end if;

  -- `do update` e não `do nothing`, e a diferença é o número na tela: a
  -- descrição da pendência CARREGA os números do dia ("3 aulas a repor; cabem 2
  -- até lá", "ocupação 10 para capacidade 9"). Com `do nothing`, a pendência
  -- aberta na segunda-feira mostraria na sexta os números de segunda — número
  -- errado com cara de certo, que é o pior desfecho do card 2.3 §3.4. O `where`
  -- evita o efeito colateral do refresco: sem ele, `atualizado_em` mudaria todo
  -- dia mesmo sem nada ter mudado, e a coluna deixaria de significar algo.
  --
  -- `pendencia.tipo = excluded.tipo` no `where` fecha o único abuso que o
  -- `grant` desta função abriria: sem ele, alguém poderia reescrever a descrição
  -- de uma pendência de OUTRO tipo acertando a chave.
  insert into public.pendencia (unidade_id, tipo, severidade, descricao,
                                chave_dedup, aluno_id, bloco_id, material_id, pc_id)
  values (v_unidade, p_tipo, p_severidade, p_descricao,
          p_chave_dedup, p_aluno_id, p_bloco_id, p_material_id, p_pc_id)
      on conflict (unidade_id, chave_dedup) where resolvida_em is null
      do update set descricao  = excluded.descricao,
                    severidade = excluded.severidade
            where pendencia.tipo = excluded.tipo
              and (pendencia.descricao  is distinct from excluded.descricao
                or pendencia.severidade is distinct from excluded.severidade)
   returning id into v_id;

  -- O `do update` com `where` falso não devolve linha. A função promete o id da
  -- pendência ABERTA, nova ou preexistente (card 2.2 §10), então busca.
  if v_id is null then
    select p.id into v_id
      from public.pendencia p
     where p.unidade_id = v_unidade
       and p.chave_dedup = p_chave_dedup
       and p.resolvida_em is null;
  end if;

  return v_id;
end $$;

comment on function public.fn_pendencia_abrir(text, text, text, text, uuid, uuid, uuid, uuid) is
  'Abre a pendência, ou devolve a que já está aberta com a mesma chave_dedup, atualizando a descrição quando os números mudaram. Único caminho de escrita em `pendencia` (card 2.2 §10). SECURITY DEFINER porque é chamada como efeito colateral na transação de outro ator, e sob RLS falharia reduzindo linhas em silêncio; filtra unidade no corpo e trata unidade nula como ERRO.';

revoke execute on function public.fn_pendencia_abrir(text, text, text, text, uuid, uuid, uuid, uuid) from public;
revoke execute on function public.fn_pendencia_abrir(text, text, text, text, uuid, uuid, uuid, uuid) from anon;
grant  execute on function public.fn_pendencia_abrir(text, text, text, text, uuid, uuid, uuid, uuid) to authenticated;

-- Fechamento AUTOMÁTICO: a condição sumiu. Sem `resolvida_por` e sem
-- justificativa — a rotina não tem nenhuma a dar, e é por isso que o fechamento
-- automático e o humano são funções separadas (card 2.2 §10).
create or replace function public.fn_pendencia_resolver(p_chave_dedup text)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_n       integer;
begin
  v_unidade := public.fn_unidade_atual();

  if v_unidade is null then
    raise exception
      'fn_pendencia_resolver: sem unidade no contexto (nem sessão autenticada nem contexto de rotina).';
  end if;

  update public.pendencia p
     set resolvida_em = now(),
         resolucao    = 'RESOLVIDA',
         resolvida_por = null
   where p.unidade_id = v_unidade
     and p.chave_dedup = p_chave_dedup
     and p.resolvida_em is null;

  get diagnostics v_n = row_count;
  return v_n;
end $$;

comment on function public.fn_pendencia_resolver(text) is
  'Fechamento automático pela chave: resolvida_em = now(), resolucao = RESOLVIDA, resolvida_por NULO (foi o sistema). Devolve quantas fechou. SECURITY DEFINER pelo motivo escrito na seção 5 da migração do card 5.5.';

revoke execute on function public.fn_pendencia_resolver(text) from public;
revoke execute on function public.fn_pendencia_resolver(text) from anon;
grant  execute on function public.fn_pendencia_resolver(text) to authenticated;

-- Fechamento HUMANO. `invoker`, e exige a permissão: é aqui que
-- `pendencias.resolver` significa alguma coisa.
create or replace function public.fn_pendencia_resolver_id(
  p_pendencia_id  uuid,
  p_resolucao     text,
  p_justificativa text default null
)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_resolvida boolean;
  v_achou     boolean;
begin
  perform public.fn_exige_permissao('pendencias.resolver');

  if p_resolucao is null or p_resolucao not in ('RESOLVIDA', 'IGNORADA') then
    raise exception using
      errcode = 'PT422',
      message = 'Resolução inválida: use RESOLVIDA ou IGNORADA.',
      detail  = json_build_object('codigo', 'RESOLUCAO_INVALIDA',
                                  'resolucao', p_resolucao)::text;
  end if;

  -- IGNORAR é decisão, e decisão sem porquê é decisão perdida (mesmo argumento
  -- de fn_rep_voltar_pontual no card 5.3). O `check` da tabela já barraria — com
  -- erro cru de constraint, que é o que o card 2.2 §1.2 proíbe chegar à tela.
  if p_resolucao = 'IGNORADA'
     and (p_justificativa is null or btrim(p_justificativa) = '') then
    raise exception using
      errcode = 'PT422',
      message = 'Informe a justificativa para ignorar esta pendência.',
      detail  = json_build_object('codigo', 'MOTIVO_OBRIGATORIO',
                                  'pendencia', p_pendencia_id)::text;
  end if;

  -- Duas leituras separadas de propósito: "não existe" e "já foi fechada" são
  -- respostas diferentes para quem está na tela, e um `update ... where
  -- resolvida_em is null` que afeta zero linhas não sabe dizer qual das duas é.
  select (p.resolvida_em is not null) into v_resolvida
    from public.pendencia p
   where p.id = p_pendencia_id;

  v_achou := found;

  -- Pendência de outra unidade é indistinguível de inexistente, pela razão de
  -- PC_INEXISTENTE (card 2.9) e BLOCO_INEXISTENTE (card 5.3): quem não pode ver
  -- não descobre que existe. Quem faz esse recorte é a RLS de `pendencia_sel`,
  -- que este `select` atravessa como o usuário que chamou.
  if not v_achou then
    raise exception using
      errcode = 'PT404',
      message = 'Esta pendência não foi encontrada.',
      detail  = json_build_object('codigo', 'PENDENCIA_INEXISTENTE',
                                  'pendencia', p_pendencia_id)::text;
  end if;

  if v_resolvida then
    raise exception using
      errcode = 'PT409',
      message = 'Esta pendência já foi resolvida.',
      detail  = json_build_object('codigo', 'PENDENCIA_JA_RESOLVIDA',
                                  'pendencia', p_pendencia_id)::text;
  end if;

  update public.pendencia p
     set resolvida_em  = now(),
         resolucao     = p_resolucao,
         resolvida_por = auth.uid(),
         justificativa = nullif(btrim(coalesce(p_justificativa, '')), '')
   where p.id = p_pendencia_id
     and p.resolvida_em is null;
end $$;

comment on function public.fn_pendencia_resolver_id(uuid, text, text) is
  'Fechamento humano: exige pendencias.resolver, grava quem fechou e a justificativa. PT422/RESOLUCAO_INVALIDA fora de (RESOLVIDA, IGNORADA), PT422/MOTIVO_OBRIGATORIO ao IGNORAR sem justificativa, PT404/PENDENCIA_INEXISTENTE e PT409/PENDENCIA_JA_RESOLVIDA. `invoker` de propósito — é aqui que a permissão vale.';

revoke execute on function public.fn_pendencia_resolver_id(uuid, text, text) from public;
revoke execute on function public.fn_pendencia_resolver_id(uuid, text, text) from anon;
grant  execute on function public.fn_pendencia_resolver_id(uuid, text, text) to authenticated;

-- Fecha, de um tipo, tudo o que NÃO está na lista do que ainda é verdade.
-- Existe para não haver três cópias da mesma consulta dentro de
-- rt_pendencias_diaria — três lugares onde esquecer o filtro de unidade, e três
-- lugares para a próxima fase esquecer de mexer. Sem `grant`: só as rt_* a
-- chamam, e elas rodam como o dono.
create or replace function public.fn_pendencias_fechar_ausentes(
  p_tipo   text,
  p_chaves text[]
)
returns integer
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_n integer := 0;
  r   record;
begin
  for r in select p.chave_dedup
             from public.pendencia p
            where p.unidade_id = public.fn_unidade_atual()
              and p.tipo = p_tipo
              and p.resolvida_em is null
              and not (p.chave_dedup = any (coalesce(p_chaves, '{}'::text[])))
            order by p.chave_dedup
  loop
    v_n := v_n + public.fn_pendencia_resolver(r.chave_dedup);
  end loop;

  return v_n;
end $$;

comment on function public.fn_pendencias_fechar_ausentes(text, text[]) is
  'Fecha as pendências ABERTAS de um tipo, na unidade corrente, cuja chave não está na lista do que a rotina acabou de apurar como verdadeiro. É o "e fecha" de rt_pendencias_diaria (card 2.2 §11): a lista nunca acumula item que já deixou de ser verdade.';

revoke execute on function public.fn_pendencias_fechar_ausentes(text, text[]) from public;
revoke execute on function public.fn_pendencias_fechar_ausentes(text, text[]) from anon;

-- -----------------------------------------------------------------------------
-- 6. rt_pendencias_diaria — abre E fecha os três tipos desta fase
-- -----------------------------------------------------------------------------
-- Opera na unidade do CONTEXTO CORRENTE, não em todas: quem itera as unidades é
-- rt_diaria (seção 8), como o §11 do card 2.2 escreve. Uma rotina que iterasse
-- por conta própria e outra que também iterasse dariam dois laços aninhados no
-- dia em que a orquestradora chamasse as duas.
--
-- ⚠️ REABRE O QUE FOI IGNORADO, e é decisão, não descuido. `pendencia_aberta_uk`
--    é parcial (`where resolvida_em is null`), então a dedup só vale enquanto a
--    pendência está ABERTA — é o que o §10 do card 2.2 diz com todas as letras.
--    Consequência: IGNORAR uma pendência a esconde até a execução seguinte, e no
--    dia seguinte ela volta se a condição continuar valendo. A alternativa —
--    silêncio permanente por chave — foi recusada: um ALUNO_SEM_TURMA ignorado
--    para sempre é exatamente a falha calada que este projeto cataloga, e o
--    remédio certo para "este bloco pode ficar acima da capacidade" é
--    `capacidade_override`, não esconder o aviso. Registrado nas Decisões
--    vigentes e nas Notas do card 5.8 (a central), que é quem mostra isso a uma
--    pessoa. A asserção que fixa o comportamento está no teste 090.
create or replace function public.rt_pendencias_diaria()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_chaves  text[];
  r         record;
begin
  v_unidade := public.fn_unidade_atual();

  if v_unidade is null then
    raise exception
      'rt_pendencias_diaria: sem unidade no contexto. Chamar de rt_diaria, ou entrar no contexto de rotina antes (card 2.2 §2.2).';
  end if;

  -- ---------------------------------------------------------------------------
  -- ALUNO_SEM_TURMA (ALTA) — ATIVO/ACELERAR sem bloco nem turma modular
  -- ---------------------------------------------------------------------------
  -- ⚠️ PORTÃO DO CARD 7.1, no teste 090: `turma_modular_aluno` ainda não existe,
  --    então "sem turma" hoje é "sem bloco_aluno ativo". No dia em que a tabela
  --    nascer, um aluno MODULAR alocado numa turma modular passará a receber
  --    ALUNO_SEM_TURMA todo dia — pendência falsa, e das piores, porque a lista
  --    ensina a ser ignorada. Mesma forma que o card 5.1 deu à terceira tabela
  --    de tg_aluno_status_desaloca.
  --
  -- Alocação de tipo REP CONTA aqui, ao contrário do que acontece na aceleração:
  -- o aluno está num bloco de verdade, ocupando vaga de verdade (card 2.5 §7 #2).
  v_chaves := '{}';

  for r in select a.id,
                  format('%s (%s) está %s e não está em nenhuma turma.',
                         a.nome, coalesce(a.codigo_sgf, 'sem código SGF'), a.status)
                    as descricao
             from public.aluno a
            where a.unidade_id = v_unidade
              and a.status in ('ATIVO', 'ACELERAR')
              and not exists (select 1
                                from public.bloco_aluno ba
                               where ba.aluno_id = a.id and ba.ativo)
            order by a.nome, a.id
  loop
    v_chaves := v_chaves || ('ALUNO_SEM_TURMA:' || r.id::text);
    perform public.fn_pendencia_abrir(
      'ALUNO_SEM_TURMA', 'ALUNO_SEM_TURMA:' || r.id::text, r.descricao,
      'ALTA', p_aluno_id => r.id);
  end loop;

  perform public.fn_pendencias_fechar_ausentes('ALUNO_SEM_TURMA', v_chaves);

  -- ---------------------------------------------------------------------------
  -- ACELERAR_SEM_2O_BLOCO (BAIXA) — ajuste 4 do §8 do card 2.5
  -- ---------------------------------------------------------------------------
  -- ⚠️ `tipo <> 'REP'` é o ajuste, e ele muda o resultado: "dois blocos por
  --    semana = aceleração" é regra do plano, e uma alocação de REP contínuo é
  --    reposição, não aceleração. Sem o filtro, um aluno ACELERAR com um bloco
  --    normal e uma alocação REP contaria dois e a pendência NÃO abriria — o
  --    aluno ficaria sem o segundo bloco de verdade e ninguém saberia. A
  --    contraprova está no teste 090, montada exatamente nesse cenário.
  --
  -- Severidade BAIXA e não INFO: ajuste 4 do §10 do card 2.3 (o `check` do DDL
  -- não tem INFO). É informativa, e a severidade é o que a central usa para
  -- ordenar (v_pendencias_abertas.ordem_severidade).
  v_chaves := '{}';

  for r in select a.id,
                  format('%s (%s) está em ACELERAR com %s bloco(s) de aula por semana — a aceleração pressupõe dois.',
                         a.nome, coalesce(a.codigo_sgf, 'sem código SGF'),
                         (select count(*)
                            from public.bloco_aluno ba
                           where ba.aluno_id = a.id and ba.ativo and ba.tipo <> 'REP'))
                    as descricao
             from public.aluno a
            where a.unidade_id = v_unidade
              and a.status = 'ACELERAR'
              and (select count(*)
                     from public.bloco_aluno ba
                    where ba.aluno_id = a.id and ba.ativo and ba.tipo <> 'REP') < 2
            order by a.nome, a.id
  loop
    v_chaves := v_chaves || ('ACELERAR:' || r.id::text);
    perform public.fn_pendencia_abrir(
      'ACELERAR_SEM_2O_BLOCO', 'ACELERAR:' || r.id::text, r.descricao,
      'BAIXA', p_aluno_id => r.id);
  end loop;

  perform public.fn_pendencias_fechar_ausentes('ACELERAR_SEM_2O_BLOCO', v_chaves);

  -- ---------------------------------------------------------------------------
  -- BLOCO_ACIMA_CAPACIDADE (ALTA)
  -- ---------------------------------------------------------------------------
  -- A rotina vê a queda de capacidade venha ela de onde vier — PC posto em
  -- manutenção, PC desativado, `capacidade_override` reduzido à mão. O card 5.4
  -- acrescenta o caminho por EVENTO (fn_revalidar_blocos_sala, na hora em que a
  -- manutenção é registrada), com a MESMA chave: os dois convergem na dedup em
  -- vez de duplicar pendência.
  --
  -- ⚠️ `> 0` e não `is not null`: fn_capacidade_efetiva e fn_ocupacao_bloco são
  --    `security definer` e devolvem NULO para bloco de outra unidade (card 5.2).
  --    Aqui elas nunca deveriam devolver nulo — o `where` já limita à unidade
  --    corrente —, mas comparar nulos daria `null`, que num `where` é falso: a
  --    pendência simplesmente não abriria, em silêncio, se algum dia a premissa
  --    mudasse. O `coalesce(..., -1)` faz esse dia REPROVAR em voz alta, porque
  --    -1 > qualquer ocupação é falso e a contagem do teste 090 acusa.
  v_chaves := '{}';

  for r in select b.id,
                  public.fn_ocupacao_bloco(b.id)     as ocupacao,
                  public.fn_capacidade_efetiva(b.id) as capacidade,
                  s.nome as sala, b.dia_semana, b.hora_inicio
             from public.bloco_horario b
             join public.sala s on s.id = b.sala_id
            where b.unidade_id = v_unidade
              and b.ativo
              and coalesce(public.fn_ocupacao_bloco(b.id), -1)
                > coalesce(public.fn_capacidade_efetiva(b.id), -1)
            order by b.dia_semana, b.hora_inicio, b.id
  loop
    v_chaves := v_chaves || ('CAPACIDADE:' || r.id::text);
    perform public.fn_pendencia_abrir(
      'BLOCO_ACIMA_CAPACIDADE', 'CAPACIDADE:' || r.id::text,
      format('%s, dia %s às %s: %s aluno(s) para capacidade de %s. Admissão bloqueada até normalizar.',
             r.sala, r.dia_semana, to_char(r.hora_inicio, 'HH24:MI'),
             r.ocupacao, r.capacidade),
      'ALTA', p_bloco_id => r.id);
  end loop;

  perform public.fn_pendencias_fechar_ausentes('BLOCO_ACIMA_CAPACIDADE', v_chaves);
end $$;

comment on function public.rt_pendencias_diaria() is
  'Abre E fecha, na unidade do contexto corrente, os três tipos de pendência da Fase 5: ALUNO_SEM_TURMA, ACELERAR_SEM_2O_BLOCO (contando só blocos de tipo <> REP) e BLOCO_ACIMA_CAPACIDADE. Reavaliada todo dia: a lista nunca acumula item que já deixou de ser verdade — e reabre o que foi fechado enquanto a condição continuar valendo.';

revoke execute on function public.rt_pendencias_diaria() from public;
revoke execute on function public.rt_pendencias_diaria() from anon;
revoke execute on function public.rt_pendencias_diaria() from authenticated;

-- -----------------------------------------------------------------------------
-- 7. rt_rep_avaliar — quem ABRE e FECHA a sugestão da virada (card 2.5 §5.3)
-- -----------------------------------------------------------------------------
-- O catálogo do card 2.2 §10.1 dizia "aberta por fn_rep_avaliar_virada"; o card
-- 2.5 §5.3 corrigiu, e é esta a versão implementada: a avaliação é `stable` e
-- NÃO escreve — quem escreve é esta rotina.
--
-- As duas chaves têm SUFIXO (`:CONTINUO` e `:VOLTA`), e o card 2.5 §6 explica
-- por quê: com `REP:<aluno>` para os dois sentidos, o índice único parcial
-- descartaria em silêncio a sugestão de volta enquanto a de ida estivesse
-- aberta. Os dois nunca coexistem hoje — depender disso é que é frágil.
create or replace function public.rt_rep_avaliar()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_chaves  text[] := '{}';
  s         public.tp_rep_situacao;
  r         record;
begin
  v_unidade := public.fn_unidade_atual();

  if v_unidade is null then
    raise exception
      'rt_rep_avaliar: sem unidade no contexto. Chamar de rt_diaria, ou entrar no contexto de rotina antes (card 2.2 §2.2).';
  end if;

  -- O universo do §5.3 do card 2.5: aluno ATIVO/ACELERAR com alguma reposição
  -- não REALIZADA (tem débito, pode virar) OU com alocação REP ativa (já virou,
  -- pode voltar). Quem não está em nenhum dos dois casos não tem veredito a dar
  -- — e por isso não entra em v_chaves, o que faz o fechamento da última linha
  -- alcançar quem saiu do universo (mudou de status, quitou tudo).
  for r in select a.id
             from public.aluno a
            where a.unidade_id = v_unidade
              and a.status in ('ATIVO', 'ACELERAR')
              and (exists (select 1 from public.bloco_aluno_reposicao br
                            where br.aluno_id = a.id and br.status <> 'REALIZADA')
                or exists (select 1 from public.bloco_aluno ba
                            where ba.aluno_id = a.id and ba.ativo and ba.tipo = 'REP'))
            order by a.nome, a.id
  loop
    s := public.fn_rep_situacao(r.id);

    if s.veredito = 'SUGERIR_CONTINUO' then
      v_chaves := v_chaves || ('REP:' || r.id::text || ':CONTINUO');
      perform public.fn_pendencia_abrir(
        'REP_VIRADA', 'REP:' || r.id::text || ':CONTINUO',
        format('%s aula(s) a repor em aberto; a mais antiga é de %s e vence em %s; cabem %s reposição(ões) até lá. Sugerido converter para REP contínuo.',
               s.debito, to_char(s.aula_mais_antiga, 'DD/MM/YYYY'),
               to_char(s.prazo_final, 'DD/MM/YYYY'),
               s.capacidade * s.semanas_uteis),
        'MEDIA', p_aluno_id => r.id);

    elsif s.veredito = 'SUGERIR_VOLTA' then
      v_chaves := v_chaves || ('REP:' || r.id::text || ':VOLTA');
      perform public.fn_pendencia_abrir(
        'REP_VIRADA', 'REP:' || r.id::text || ':VOLTA',
        format('Em REP contínuo desde %s, sem aula a repor em aberto e sem falta recente. Sugerido voltar a REP pontual e liberar a vaga semanal.',
               to_char(s.rep_desde, 'DD/MM/YYYY')),
        'BAIXA', p_aluno_id => r.id);
    end if;
    -- 'MANTER' não acrescenta chave nenhuma: as duas pendências do aluno caem no
    -- fechamento abaixo. É o "some sozinha quando deixa de ser verdade".
  end loop;

  perform public.fn_pendencias_fechar_ausentes('REP_VIRADA', v_chaves);
end $$;

comment on function public.rt_rep_avaliar() is
  'Percorre os alunos ATIVO/ACELERAR com reposição em aberto ou alocação REP ativa, chama fn_rep_avaliar_virada e ABRE E FECHA as pendências REP_VIRADA (REP:<aluno>:CONTINUO, MEDIA; REP:<aluno>:VOLTA, BAIXA). Card 2.5 §5.3 e §6 — corrige o catálogo do card 2.2, que atribuía a abertura à avaliação.';

revoke execute on function public.rt_rep_avaliar() from public;
revoke execute on function public.rt_rep_avaliar() from anon;
revoke execute on function public.rt_rep_avaliar() from authenticated;

-- -----------------------------------------------------------------------------
-- 8. rt_diaria — a orquestradora, e o isolamento que a torna útil
-- -----------------------------------------------------------------------------
-- UM único job diário chamando uma orquestradora (card 2.2 §11). Vários jobs
-- concorrentes sobre as mesmas tabelas só criariam ordem de execução implícita e
-- difícil de depurar.
--
-- Cada rt_* corre dentro do seu `begin … exception when others` e a falha vira
-- pendência ROTINA_FALHOU (ALTA) — e SEGUE para a próxima. Uma unidade com dado
-- corrompido não pode impedir o alerta das outras, e uma rotina quebrada não
-- pode levar junto as que funcionam.
--
-- ⚠️ POR QUE PENDÊNCIA E NÃO LOG: o log do Supabase no free tier tem retenção de
--    UM DIA (card 3.12 (g)). Uma rotina que falha às 03:10 e some do log às
--    03:10 do dia seguinte falha em silêncio para sempre — e o sintoma seria
--    justamente uma central de pendências VAZIA, indistinguível de "está tudo
--    bem". A pendência é permanente e tem tela.
--
-- ⚠️ PORTÃO DO CARD 5.4 E DO 8.1, no teste 090: o §11 do card 2.2 dá cinco
--    passos a rt_diaria, e três ainda não existem (rt_pcs_normaliza,
--    rt_capacidades, rt_projecao_demanda). Criá-las e esquecer de chamá-las aqui
--    não daria erro nenhum: daria uma rotina que roda todo dia sem fazer o que
--    passou a ser dela. O teste reprova no dia em que qualquer uma nascer fora
--    desta função.
create or replace function public.rt_diaria()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  u record;
begin
  for u in select id from public.unidade where ativo order by id
  loop
    -- `is_local => true`: o contexto morre no `commit` mesmo se a rotina falhar
    -- no meio, e não vaza de uma unidade para a seguinte (card 2.2 §2.2).
    perform set_config('app.rotina', 'on', true);
    perform set_config('app.rotina_unidade', u.id::text, true);

    begin
      perform public.rt_pendencias_diaria();
      perform public.fn_pendencia_resolver('ROTINA_FALHOU:rt_pendencias_diaria');
    exception when others then
      perform public.fn_pendencia_abrir(
        'ROTINA_FALHOU', 'ROTINA_FALHOU:rt_pendencias_diaria',
        format('A rotina rt_pendencias_diaria falhou: %s (SQLSTATE %s). A lista de pendências desta unidade pode estar desatualizada.',
               sqlerrm, sqlstate),
        'ALTA');
    end;

    begin
      perform public.rt_rep_avaliar();
      perform public.fn_pendencia_resolver('ROTINA_FALHOU:rt_rep_avaliar');
    exception when others then
      perform public.fn_pendencia_abrir(
        'ROTINA_FALHOU', 'ROTINA_FALHOU:rt_rep_avaliar',
        format('A rotina rt_rep_avaliar falhou: %s (SQLSTATE %s). As sugestões de virada REP desta unidade podem estar desatualizadas.',
               sqlerrm, sqlstate),
        'ALTA');
    end;
  end loop;

  perform set_config('app.rotina', '', true);
  perform set_config('app.rotina_unidade', '', true);
end $$;

comment on function public.rt_diaria() is
  'Rotina diária única (card 2.2 §11): itera as unidades ativas, entra no contexto de rotina em cada uma e chama rt_pendencias_diaria e rt_rep_avaliar, cada uma isolada num bloco de exceção que registra a falha como pendência ROTINA_FALHOU (ALTA) e segue. Faltam rt_pcs_normaliza e rt_capacidades (card 5.4) e rt_projecao_demanda (8.1) — o portão do teste 090 reprova no dia em que nascerem fora daqui.';

revoke execute on function public.rt_diaria() from public;
revoke execute on function public.rt_diaria() from anon;
revoke execute on function public.rt_diaria() from authenticated;

-- -----------------------------------------------------------------------------
-- 9. O job: pg_cron, e o fuso que engana
-- -----------------------------------------------------------------------------
-- ⚠️ `pg_cron` AGENDA EM UTC. `10 6 * * *` é 03:10 em São Paulo (UTC−3), fora do
--    horário de uso da escola. Lido como horário local, `06:10` seria o começo
--    do expediente — e a rotina passaria por cima de quem está usando o sistema.
--    Está escrito aqui porque é aqui que alguém vai ler quando for mudar.
--
-- A extensão vive no schema `cron`, fora de `public`: nenhuma das suítes de
-- catálogo (que filtram `nspname = 'public'`) muda de resultado por causa dela.
-- Medido no stack local com o CLI 2.116.0 — `pg_cron` está em
-- `shared_preload_libraries` da imagem do Supabase e o papel `postgres` cria a
-- extensão sem privilégio adicional.
create extension if not exists pg_cron;

-- `cron.schedule` é upsert por `jobname`: reexecutar não duplica o job.
select cron.schedule('gi_rotina_diaria', '10 6 * * *', $cron$ select public.rt_diaria(); $cron$);

-- -----------------------------------------------------------------------------
-- 10. v_pendencias_abertas — a PRIMEIRA view do projeto (card 2.3 §9)
-- -----------------------------------------------------------------------------
-- Três decisões do card 2.3, todas visíveis no corpo:
--
--   (a) `security_invoker = on`, sem exceção (§2.1). Sem ela a view roda com a
--       identidade do DONO e vira a porta dos fundos que o `force row level
--       security` fechou na porta da frente. A partir de hoje isso é asserção de
--       catálogo (C5, teste 011), não convenção.
--
--   (b) `left join` nas QUATRO referências (§9 e §3.4). Elas são nulas por
--       natureza — cada tipo usa uma — e, com `security_invoker`, quem não pode
--       ler a referência precisa continuar VENDO a pendência: com `join` interno
--       o monitor sem `turmas.ler` perderia a linha inteira de
--       BLOCO_ACIMA_CAPACIDADE, e a central diria "nenhuma pendência" em vez de
--       "uma pendência sobre um bloco que você não pode ver".
--
--   (c) `ordem_severidade` NUMÉRICA, porque 'ALTA' < 'BAIXA' em ordenação
--       alfabética — a mesma armadilha das fases "01." a "11." do board.
--
-- Colunas explícitas e `unidade_id` sempre (§2.4); `fn_hoje()` e nunca
-- `current_date` (§3.3 e C6).
create view public.v_pendencias_abertas with (security_invoker = on) as
select p.unidade_id,
       p.id          as pendencia_id,
       p.tipo,
       p.severidade,
       (case p.severidade when 'ALTA' then 1 when 'MEDIA' then 2 else 3 end)::smallint
                     as ordem_severidade,
       p.descricao,
       p.chave_dedup,
       p.criado_em,
       (public.fn_hoje() - p.criado_em::date)::integer as dias_aberta,
       p.aluno_id,    al.nome as aluno_nome, al.codigo_sgf, al.status as aluno_status,
       p.bloco_id,    bh.dia_semana, bh.hora_inicio, sl.nome as bloco_sala_nome,
       p.material_id, mt.codigo as material_codigo, mt.nome as material_nome,
       p.pc_id,       pcs.identificador as pc_identificador
  from public.pendencia p
  left join public.aluno         al  on al.id  = p.aluno_id
  left join public.bloco_horario bh  on bh.id  = p.bloco_id
  left join public.sala          sl  on sl.id  = bh.sala_id
  left join public.material      mt  on mt.id  = p.material_id
  left join public.pc            pcs on pcs.id = p.pc_id
 where p.resolvida_em is null;

comment on view public.v_pendencias_abertas is
  'Central de pendências (card 2.3 §9, tela do card 5.8). Não filtra por tipo nem por permissão de domínio: quem filtra é o usuário. `ordem_severidade` é numérica porque ALTA < BAIXA alfabeticamente.';

revoke all   on public.v_pendencias_abertas from public;
revoke all   on public.v_pendencias_abertas from anon;
grant select on public.v_pendencias_abertas to authenticated;

-- -----------------------------------------------------------------------------
-- 11. O portão do card 5.3 dispara: as duas funções da virada fecham a pendência
-- -----------------------------------------------------------------------------
-- `create or replace` das funções do card 5.3. A única mudança é o passo 4 do
-- §5.2 do card 2.5, que só podia ser escrito depois que `pendencia` existisse —
-- e a seção 6 do teste 085 estava lá justamente para que ninguém pudesse
-- esquecer: sem isto, a central sugeriria todo dia uma virada que já aconteceu,
-- até a execução seguinte da rotina desfazer o engano.
--
-- Por que não deixar só para a rotina, que também fecharia: porque entre a
-- virada e a rotina passa até um dia, e nesse dia a lista mente para a pessoa
-- que acabou de agir. Fechar na mesma transação é o comportamento que o card 2.5
-- especificou, e a rotina continua sendo a rede embaixo.
create or replace function public.fn_rep_virar_continuo(
  p_aluno_id   uuid,
  p_bloco_id   uuid,
  p_observacao text default null
)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  r    record;
begin
  perform public.fn_exige_permissao('turmas.alocar');

  if exists (select 1 from public.bloco_aluno ba
              where ba.aluno_id = p_aluno_id and ba.ativo and ba.tipo = 'REP') then
    raise exception using
      errcode = 'PT409',
      message = 'Este aluno já está em REP contínuo.',
      detail  = json_build_object('codigo', 'REP_JA_CONTINUO',
                                  'aluno', p_aluno_id)::text;
  end if;

  -- As reposições pontuais deixam de fazer sentido: o aluno passa a vir toda
  -- semana. Cancelar libera as vagas que elas ocupavam naquelas datas.
  for r in select br.id from public.bloco_aluno_reposicao br
            where br.aluno_id = p_aluno_id and br.status = 'PREVISTA'
            order by br.data, br.id
  loop
    perform public.fn_reposicao_cancelar(
      r.id, coalesce(p_observacao, 'Absorvida pela virada para REP contínuo'));
  end loop;

  v_id := public.fn_bloco_admitir(p_bloco_id, p_aluno_id, 'REP');

  -- Passo 4 do §5.2 do card 2.5. A sugestão de ida deixou de valer no instante
  -- em que a virada aconteceu.
  perform public.fn_pendencia_resolver('REP:' || p_aluno_id::text || ':CONTINUO');

  return v_id;
end $$;

comment on function public.fn_rep_virar_continuo(uuid, uuid, text) is
  'Converte o aluno para REP contínuo: cancela as reposições PREVISTA, cria (ou reativa) a alocação de tipo REP no bloco escolhido delegando vaga e método a fn_bloco_admitir, e FECHA a pendência REP:<aluno>:CONTINUO (passo 4 do §5.2 do card 2.5). PT409/REP_JA_CONTINUO quando já há alocação REP ativa.';

revoke execute on function public.fn_rep_virar_continuo(uuid, uuid, text) from public;
revoke execute on function public.fn_rep_virar_continuo(uuid, uuid, text) from anon;
grant  execute on function public.fn_rep_virar_continuo(uuid, uuid, text) to authenticated;

create or replace function public.fn_rep_voltar_pontual(
  p_aluno_id uuid,
  p_motivo   text
)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_bloco uuid;
begin
  perform public.fn_exige_permissao('turmas.alocar');

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception using
      errcode = 'PT422',
      message = 'Informe o motivo da volta a REP pontual.',
      detail  = json_build_object('codigo', 'MOTIVO_OBRIGATORIO',
                                  'aluno', p_aluno_id)::text;
  end if;

  select ba.bloco_id into v_bloco
    from public.bloco_aluno ba
   where ba.aluno_id = p_aluno_id and ba.ativo and ba.tipo = 'REP'
   order by ba.tipo_desde desc, ba.id
   limit 1;

  if v_bloco is null then
    raise exception using
      errcode = 'PT409',
      message = 'Este aluno não está em REP contínuo.',
      detail  = json_build_object('codigo', 'REP_NAO_CONTINUO',
                                  'aluno', p_aluno_id)::text;
  end if;

  perform public.fn_bloco_remover(v_bloco, p_aluno_id, p_motivo);

  -- Simétrico do passo 4: a sugestão de VOLTA foi atendida. O sufixo da chave é
  -- o que permite fechar esta sem tocar na de ida (card 2.5 §6).
  perform public.fn_pendencia_resolver('REP:' || p_aluno_id::text || ':VOLTA');
end $$;

comment on function public.fn_rep_voltar_pontual(uuid, text) is
  'Desfaz a virada: desativa a alocação de tipo REP chamando fn_bloco_remover, que grava o motivo, e FECHA a pendência REP:<aluno>:VOLTA. PT422/MOTIVO_OBRIGATORIO sem motivo, PT409/REP_NAO_CONTINUO sem alocação REP ativa. Não impede o aluno ficar sem turma — quem denuncia isso é ALUNO_SEM_TURMA, aberta por rt_pendencias_diaria no dia seguinte.';

revoke execute on function public.fn_rep_voltar_pontual(uuid, text) from public;
revoke execute on function public.fn_rep_voltar_pontual(uuid, text) from anon;
grant  execute on function public.fn_rep_voltar_pontual(uuid, text) to authenticated;
