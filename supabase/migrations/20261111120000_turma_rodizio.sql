-- =============================================================================
-- Card 9.2,88 — Turma Modular em rodízio (banco)
--
-- Parte 2 da proposta aprovada pelo dono do produto em 10/11/2026. Fonte:
-- docs/turma-rodizio.md (card 9.2,87), que REVOGA a premissa do card 2.2 §9 de
-- que a turma começa, percorre os módulos uma vez e termina: as turmas são
-- cíclicas, e quem entra e sai são os alunos.
--
-- A ideia central (§2 do documento): A SEQUÊNCIA DO ALUNO NÃO SE GUARDA —
-- DERIVA-SE. Guarda-se o fato (em que módulo ele entrou e quais já fez); o que
-- falta, a ordem e a previsão de conclusão saem da agenda da turma.
--
-- Entregável:
--   1. `turma_modular_modulo.ciclo` — uma volta da turma pelos módulos;
--   2. `turma_modular_aluno.modulo_entrada_id`;
--   3. `aluno_modulo` (o que o aluno já fez) e `aluno_modulo_hist`;
--   4. corrente por (ciclo, ordem) nas TRÊS definições, e `fn_turma_modular_agenda`;
--   5. admitir com módulo de entrada, avançar gravando o módulo de cada aluno
--      e abrindo o ciclo seguinte, abrir ciclo, exceção à mão e conclusão;
--   6. `v_aluno_modular_progresso` e `v_aluno_modular_modulo`;
--   7. o importador com a chave nova do cronograma.
--
-- O que este arquivo NÃO faz, e de quem é:
--   • o certificado do aluno Modular na conclusão dos módulos (D1), a previsão
--     só calculada (D2) e o combo (D3) — card 9.2,885. Aqui a conclusão libera a
--     vaga e nada mais;
--   • a regra MODULAR da projeção por aluno — card 9.2,89. ⚠️ Até lá
--     `v_projecao_aluno` lê o cronograma sem conhecer `ciclo`, e uma turma que
--     já abriu o segundo ciclo teria os módulos contados duas vezes. Os dois
--     cards saem no MESMO lote (lote/rodada-2), e é por isso que isto é
--     aceitável;
--   • as telas — card 9.2,90; o extrator e as entidades novas do importador —
--     card 9.2,91;
--   • não grava dado nenhum: `aluno_modulo` é dado de negócio e vem do
--     importador (portão do card 4.0,5).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. O ciclo no cronograma
-- -----------------------------------------------------------------------------
alter table public.turma_modular_modulo
  add column ciclo integer not null default 1 check (ciclo > 0);

comment on column public.turma_modular_modulo.ciclo is
  'A volta da turma pelos módulos do curso (card 9.2,88): a turma é cíclica, e depois do último módulo recomeça do primeiro num ciclo novo. As linhas dos ciclos passados ficam — são o histórico de quando a turma deu cada módulo, e é delas que sai o passo aprendido.';

alter table public.turma_modular_modulo drop constraint turma_modular_modulo_uk;
alter table public.turma_modular_modulo
  add constraint turma_modular_modulo_uk unique (turma_id, modulo_id, ciclo);

comment on table public.turma_modular_modulo is
  'Cronograma da turma, um registro por módulo do curso E POR CICLO (card 9.2,88). A turma avança em CONJUNTO — não existe avanço por aluno (card 2.2 §9); o que é por aluno é o REGISTRO do que ele fez, em aluno_modulo. O módulo corrente é o primeiro não concluído por (ciclo, modulo.ordem).';

-- -----------------------------------------------------------------------------
-- 2. O módulo de entrada do aluno
-- -----------------------------------------------------------------------------
alter table public.turma_modular_aluno
  add column modulo_entrada_id uuid references public.modulo(id);

create index turma_modular_aluno_modulo_entrada_ix
  on public.turma_modular_aluno (modulo_entrada_id);

comment on column public.turma_modular_aluno.modulo_entrada_id is
  'O módulo em que o aluno entrou na turma (card 9.2,88). É o que a tela mostra e o que decide, no avanço, se o aluno que ainda não começou recebe o módulo que fechou. NULO só em linha anterior a este card ou em turma sem cronograma.';

-- A guarda de coluna do card 7.1 ganha a coluna nova: o módulo de entrada é
-- alocação, e alocar exige turmas.alocar.
create or replace function public.fn_turma_modular_aluno_colunas_permitidas()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  -- `ativo` fica de fora da lista: é a única coluna que a desalocação sem ator
  -- precisa escrever, e ela é justamente o que o `or` da política existe para
  -- permitir. Tudo o mais é alocação, e alocar exige turmas.alocar.
  if new.turma_id     is distinct from old.turma_id
     or new.aluno_id     is distinct from old.aluno_id
     or new.data_entrada is distinct from old.data_entrada
     or new.modulo_entrada_id is distinct from old.modulo_entrada_id then
    perform public.fn_exige_permissao('turmas.alocar');
  end if;

  return new;
end $$;

comment on function public.fn_turma_modular_aluno_colunas_permitidas() is
  'Trigger BEFORE UPDATE em turma_modular_aluno: só `ativo` é escrita sob alunos.alterar_status; mudar turma, aluno, data de entrada ou módulo de entrada (card 9.2,88) exige turmas.alocar. Onde a permissão é por coluna, a RLS é a segunda barreira e o trigger é a primeira (cards 2.4, 4.2 e 5.1).';

-- -----------------------------------------------------------------------------
-- 3. aluno_modulo — o que o aluno JÁ FEZ
-- -----------------------------------------------------------------------------
-- A existência da linha é o fato "fez". Não há coluna de estado: "a fazer" é a
-- ausência, e é por isso que o módulo perdido em STANDBY cai sozinho no fim da
-- sequência do aluno — ele simplesmente continua faltando, e a ordem é a do
-- rodízio da turma (docs/turma-rodizio.md §2).
create table public.aluno_modulo (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  aluno_id       uuid not null references public.aluno(id) on delete cascade,
  modulo_id      uuid not null references public.modulo(id),
  turma_id       uuid references public.turma_modular(id) on delete set null,
  data_conclusao date not null,
  origem         text not null check (origem in ('TURMA','MANUAL','IMPORTACAO')),
  observacao     text,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint aluno_modulo_uk unique (aluno_id, modulo_id)
);

comment on table public.aluno_modulo is
  'Os módulos que o aluno Modular já fez (card 9.2,88, docs/turma-rodizio.md §3.3). A EXISTÊNCIA da linha é o fato — "a fazer" é a ausência. Escrita por fn_turma_modular_avancar (origem TURMA, um por aluno ativo da turma), pelas funções de exceção à mão (MANUAL) e pelo importador (IMPORTACAO). VAZIA em produção até a virada do card 9.7.';
comment on column public.aluno_modulo.turma_id is
  'A turma em que o aluno fez o módulo. NULO quando foi lançado à mão ou importado; `on delete set null` porque apagar a turma não apaga o que o aluno estudou.';
comment on column public.aluno_modulo.origem is
  'TURMA (o avanço conjunto gravou), MANUAL (exceção lançada na ficha, fn_aluno_modulo_registrar) ou IMPORTACAO.';

create index aluno_modulo_modulo_ix on public.aluno_modulo (modulo_id);
create index aluno_modulo_turma_ix  on public.aluno_modulo (turma_id);

create trigger tg_auditoria_aluno_modulo
  before insert or update on public.aluno_modulo
  for each row execute function public.fn_auditoria();

alter table public.aluno_modulo enable row level security;
alter table public.aluno_modulo force  row level security;

-- ⚠️ O `select` aceita `turmas.editar` ALÉM de `alunos.ler`, e é a folga do
--    efeito colateral (card 2.4 (b)): quem avança o módulo grava aqui dentro da
--    própria transação, e precisa ENXERGAR o que já existe para decidir quem
--    ainda não começou. Sob RLS, quem não lê recebe zero linhas sem erro — e o
--    avanço gravaria o módulo para o aluno que entrou para começar no próximo.
create policy aluno_modulo_sel on public.aluno_modulo for select to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and (public.tem_permissao('alunos.ler')
              or public.tem_permissao('turmas.editar')));

create policy aluno_modulo_ins on public.aluno_modulo for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and (public.tem_permissao('turmas.editar')
                   or public.tem_permissao('alunos.editar_trilha')));

create policy aluno_modulo_upd on public.aluno_modulo for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('alunos.editar_trilha'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('alunos.editar_trilha'));

create policy aluno_modulo_del on public.aluno_modulo for delete to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('alunos.editar_trilha'));

-- O histórico: registrar e remover módulo é a exceção à mão (regra 6), e
-- exceção sem rastro é exceção perdida. Imutável, escrito só pelo trigger.
create table public.aluno_modulo_hist (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  aluno_id       uuid not null references public.aluno(id) on delete cascade,
  modulo_id      uuid not null references public.modulo(id),
  acao           text not null check (acao in ('REGISTRADO','REMOVIDO')),
  data_conclusao date,
  origem         text,
  motivo         text,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid
);

comment on table public.aluno_modulo_hist is
  'Histórico imutável de aluno_modulo (card 9.2,88): uma linha a cada módulo registrado ou removido, com quem e quando. Escrita SÓ por tg_aluno_modulo_hist; sem política de escrita para ninguém. O motivo da remoção vem de fn_aluno_modulo_remover.';

create index aluno_modulo_hist_aluno_ix  on public.aluno_modulo_hist (aluno_id);
create index aluno_modulo_hist_modulo_ix on public.aluno_modulo_hist (modulo_id);

create trigger tg_auditoria_aluno_modulo_hist
  before insert or update on public.aluno_modulo_hist
  for each row execute function public.fn_auditoria();

alter table public.aluno_modulo_hist enable row level security;
alter table public.aluno_modulo_hist force  row level security;

create policy aluno_modulo_hist_sel on public.aluno_modulo_hist for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('alunos.ler'));

-- `security definer`: a tabela não tem política de insert para ninguém, e o
-- trigger dispara na transação de quem avançou o módulo ou lançou a exceção.
-- Como invoker, o insert seria recusado pela RLS e derrubaria o avanço inteiro.
-- A unidade vem da PRÓPRIA linha de aluno_modulo, que já passou pela política.
create or replace function public.fn_aluno_modulo_hist()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.aluno_modulo_hist (unidade_id, aluno_id, modulo_id, acao,
                                          data_conclusao, origem, motivo)
    values (new.unidade_id, new.aluno_id, new.modulo_id, 'REGISTRADO',
            new.data_conclusao, new.origem, new.observacao);
    return new;
  end if;

  insert into public.aluno_modulo_hist (unidade_id, aluno_id, modulo_id, acao,
                                        data_conclusao, origem, motivo)
  values (old.unidade_id, old.aluno_id, old.modulo_id, 'REMOVIDO',
          old.data_conclusao, old.origem,
          nullif(current_setting('app.aluno_modulo_motivo', true), ''));
  return old;
end $$;

comment on function public.fn_aluno_modulo_hist() is
  'Trigger AFTER INSERT OR DELETE em aluno_modulo: grava aluno_modulo_hist (card 9.2,88). SECURITY DEFINER porque a tabela de histórico não tem política de escrita; a unidade vem da linha de aluno_modulo, que já passou pela RLS. O motivo da remoção chega pela GUC local app.aluno_modulo_motivo, que fn_aluno_modulo_remover seta.';

revoke execute on function public.fn_aluno_modulo_hist() from public;
revoke execute on function public.fn_aluno_modulo_hist() from anon;
revoke execute on function public.fn_aluno_modulo_hist() from authenticated;

create trigger tg_aluno_modulo_hist
  after insert or delete on public.aluno_modulo
  for each row execute function public.fn_aluno_modulo_hist();

-- -----------------------------------------------------------------------------
-- 4. O módulo corrente, por (ciclo, ordem) — as TRÊS definições mudam juntas
-- -----------------------------------------------------------------------------
-- A função, o `left join lateral` de v_turma_modular_lotacao e a coluna
-- `corrente` de v_turma_modular_cronograma são a mesma definição escrita três
-- vezes (card 7.3), e o teste 072 §3 as compara linha a linha.
create or replace function public.fn_turma_modular_modulo_corrente(p_turma_id uuid)
returns uuid
language sql
stable
set search_path = public, pg_temp
as $$
  select tm.modulo_id
    from public.turma_modular_modulo tm
    join public.modulo m on m.id = tm.modulo_id
   where tm.turma_id = p_turma_id
     and not tm.concluido
   order by tm.ciclo, m.ordem, tm.modulo_id
   limit 1;
$$;

comment on function public.fn_turma_modular_modulo_corrente(uuid) is
  'Módulo corrente da turma Modular: o primeiro NÃO concluído por (ciclo, modulo.ordem) — card 9.2,88; antes era só por ordem (card 2.2 §9). Devolvido como modulo_id. NULO quando a turma não tem cronograma ou, em turma anterior ao rodízio, quando todos foram concluídos. `order by` completo porque limit sem ele é sorteio (docs/estrategia-testes.md §11).';

-- -----------------------------------------------------------------------------
-- 5. fn_turma_modular_agenda — uma volta à frente
-- -----------------------------------------------------------------------------
-- A ÚNICA definição de "quando a turma dará cada módulo": a previsão de
-- conclusão do aluno, a projeção (card 9.2,89) e as telas leem daqui.
--
-- Devolve os próximos N + 1 módulos do rodízio a partir do corrente (N = módulos
-- do curso): uma volta inteira MAIS o corrente outra vez, no ciclo seguinte. A
-- posição N + 1 existe para o aluno que entrou para começar no PRÓXIMO módulo —
-- o corrente de hoje é o último da sequência dele, e só volta na outra volta.
-- Vêm com as datas planejadas pelas três regras que a projeção já usava
-- (docs/projecao-demanda.md §5.4): a informada; senão o fim do anterior + 1;
-- senão a extrapolação pelo passo.
--
-- `security definer` + filtro de unidade no corpo: é DECISÃO DERIVADA, e
-- decisão derivada lida sob RLS nega linha em vez de devolver erro (card 8.3) —
-- como invoker, o aluno de quem não lê o cronograma teria previsão nula, com
-- cara de "turma sem data". Exige `turmas.ler`: sem ela devolve vazio, que é o
-- que a RLS do cronograma já diria.
create or replace function public.fn_turma_modular_agenda(p_turma_id uuid)
returns table (
  posicao       integer,
  modulo_id     uuid,
  modulo_nome   text,
  modulo_ordem  integer,
  material_id   uuid,
  ciclo         integer,
  cronograma_id uuid,
  data_inicio   date,
  data_fim      date
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_curso   uuid;
  v_inicio_turma date;
  v_n       integer;
  v_i0      integer;   -- índice (1..N) do módulo corrente na ordem do catálogo
  v_c0      integer;   -- ciclo do módulo corrente
  v_passo   integer;
  v_ant_fim date;
  r         record;
  v_ini     date;
  v_fim     date;
begin
  v_unidade := public.fn_unidade_atual();
  if v_unidade is null or not public.tem_permissao('turmas.ler') then
    return;
  end if;

  select t.curso_id, t.data_inicio into v_curso, v_inicio_turma
    from public.turma_modular t
   where t.id = p_turma_id and t.unidade_id = v_unidade;
  if v_curso is null then
    return;
  end if;

  select count(*) into v_n from public.modulo m where m.curso_id = v_curso;

  -- o corrente: a MESMA ordem de fn_turma_modular_modulo_corrente
  select x.idx, x.ciclo into v_i0, v_c0
    from (select tm.ciclo, m.ordem, tm.modulo_id,
                 (select count(*) from public.modulo m2
                   where m2.curso_id = v_curso
                     and (m2.ordem, m2.id) <= (m.ordem, m.id))::integer as idx
            from public.turma_modular_modulo tm
            join public.modulo m on m.id = tm.modulo_id
           where tm.turma_id = p_turma_id and not tm.concluido
           order by tm.ciclo, m.ordem, tm.modulo_id
           limit 1) x;
  if v_i0 is null then
    return;
  end if;

  -- o passo: a duração média dos módulos datados da turma, em qualquer ciclo
  select round(avg(tm.prev_conclusao - tm.data_inicio + 1))::integer into v_passo
    from public.turma_modular_modulo tm
   where tm.turma_id = p_turma_id
     and tm.data_inicio is not null and tm.prev_conclusao is not null;
  if v_passo is null or v_passo < 1 then
    v_passo := public.fn_param_int('ritmo_padrao_dias_MODULAR', 45);
  end if;

  -- o fim do último módulo CONCLUÍDO: é de onde o corrente parte quando não
  -- tem início informado
  select tm.prev_conclusao into v_ant_fim
    from public.turma_modular_modulo tm
    join public.modulo m on m.id = tm.modulo_id
   where tm.turma_id = p_turma_id and tm.concluido and tm.prev_conclusao is not null
   order by tm.ciclo desc, m.ordem desc, tm.modulo_id desc
   limit 1;

  for r in
    select g.p as posicao, mo.id as modulo_id, mo.nome, mo.ordem, mo.material_id,
           (v_c0 + (v_i0 - 1 + g.p - 1) / v_n) as ciclo,
           tm.id as cronograma_id, tm.data_inicio, tm.prev_conclusao
      from generate_series(1, v_n + 1) g(p)
      join (select m.id, m.nome, m.ordem, m.material_id,
                   row_number() over (order by m.ordem, m.id)::integer as idx
              from public.modulo m where m.curso_id = v_curso) mo
        on mo.idx = ((v_i0 - 1 + g.p - 1) % v_n) + 1
      left join public.turma_modular_modulo tm
        on tm.turma_id = p_turma_id and tm.modulo_id = mo.id
       and tm.ciclo = v_c0 + (v_i0 - 1 + g.p - 1) / v_n
     order by g.p
  loop
    v_ini := coalesce(r.data_inicio,
                      v_ant_fim + 1,
                      -- a turma inteira sem data nenhuma não tem o que extrapolar
                      case when r.posicao = 1 and r.prev_conclusao is not null
                           then r.prev_conclusao - v_passo + 1 end);
    v_fim := coalesce(r.prev_conclusao, v_ini + v_passo - 1);
    v_ant_fim := v_fim;

    posicao       := r.posicao;
    modulo_id     := r.modulo_id;
    modulo_nome   := r.nome;
    modulo_ordem  := r.ordem;
    material_id   := r.material_id;
    ciclo         := r.ciclo;
    cronograma_id := r.cronograma_id;
    data_inicio   := v_ini;
    data_fim      := v_fim;
    return next;
  end loop;
end $$;

comment on function public.fn_turma_modular_agenda(uuid) is
  'A agenda da turma Modular em rodízio (card 9.2,88, docs/turma-rodizio.md §5.1): os próximos N + 1 módulos a partir do corrente (N = módulos do curso) — uma volta inteira mais o corrente outra vez, no ciclo seguinte, que é o último módulo de quem entrou para começar no próximo —, com início e fim planejados — a data informada; senão o fim do anterior + 1; senão a extrapolação pelo passo médio da turma (ou ritmo_padrao_dias_MODULAR). É a ÚNICA definição de quando a turma dará cada módulo. SECURITY DEFINER com filtro de unidade no corpo; sem turmas.ler devolve vazio. Datas NULAS quando a turma não tem data nenhuma.';

revoke execute on function public.fn_turma_modular_agenda(uuid) from public;
revoke execute on function public.fn_turma_modular_agenda(uuid) from anon;
grant  execute on function public.fn_turma_modular_agenda(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. Conclusão do curso — fn_aluno_modular_avaliar_conclusao
-- -----------------------------------------------------------------------------
-- O aluno conclui quando aluno_modulo cobre TODOS os módulos do curso da turma.
-- No ato, sai da turma (libera a vaga). O certificado é do card 9.2,885.
--
-- `security definer`, e pelo motivo de fn_pendencia_resolver (card 5.5 §5): é
-- chamada como efeito colateral na transação de quem AVANÇOU o módulo
-- (`turmas.editar`), e a política de update de turma_modular_aluno exige
-- `turmas.alocar` — como invoker, o update afetaria zero linhas em silêncio e o
-- aluno formado continuaria ocupando a vaga.
--
-- ⚠️ Limite aceito, o mesmo de lá: com `grant` para authenticated, qualquer
--    perfil alcança esta função por RPC. O dano é nulo por construção — ela só
--    age quando a conclusão é VERDADEIRA, e nesse caso faz o que o avanço faria.
create or replace function public.fn_aluno_modular_avaliar_conclusao(
  p_aluno_id uuid,
  p_turma_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_curso   uuid;
  v_faltam  integer;
begin
  v_unidade := public.fn_unidade_atual();
  if v_unidade is null then
    raise exception
      'fn_aluno_modular_avaliar_conclusao: sem unidade no contexto (nem sessão autenticada nem contexto de rotina).';
  end if;

  select t.curso_id into v_curso
    from public.turma_modular t
   where t.id = p_turma_id and t.unidade_id = v_unidade;
  if v_curso is null then
    return false;
  end if;

  select count(*) into v_faltam
    from public.modulo m
   where m.curso_id = v_curso
     and not exists (select 1 from public.aluno_modulo am
                      where am.aluno_id = p_aluno_id and am.modulo_id = m.id
                        and am.unidade_id = v_unidade);

  -- Curso sem módulo nenhum não conclui ninguém: zero faltando de zero não é
  -- conclusão, é catálogo vazio.
  if v_faltam > 0
     or not exists (select 1 from public.modulo m where m.curso_id = v_curso) then
    return false;
  end if;

  update public.turma_modular_aluno ta
     set ativo = false,
         motivo_saida = 'Concluiu o curso'
   where ta.turma_id = p_turma_id and ta.aluno_id = p_aluno_id
     and ta.unidade_id = v_unidade and ta.ativo;

  return true;
end $$;

comment on function public.fn_aluno_modular_avaliar_conclusao(uuid, uuid) is
  'Card 9.2,88 (docs/turma-rodizio.md §4.4): se aluno_modulo cobre todos os módulos do curso da turma, tira o aluno da turma (ativo = false, motivo_saida = Concluiu o curso), liberando a vaga, e devolve true. Não muda o status do aluno. SECURITY DEFINER porque é efeito colateral do avanço (turmas.editar) e a política de update exige turmas.alocar; filtra unidade no corpo e só age quando a conclusão é verdadeira.';

revoke execute on function public.fn_aluno_modular_avaliar_conclusao(uuid, uuid) from public;
revoke execute on function public.fn_aluno_modular_avaliar_conclusao(uuid, uuid) from anon;
grant  execute on function public.fn_aluno_modular_avaliar_conclusao(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 7. Admissão com módulo de entrada
-- -----------------------------------------------------------------------------
-- A assinatura ganha um parâmetro com default. O `drop` da antiga é obrigatório:
-- com as duas, a chamada nomeada de dois argumentos do app ficaria ambígua.
drop function public.fn_turma_modular_admitir(uuid, uuid);

create function public.fn_turma_modular_admitir(
  p_turma_id          uuid,
  p_aluno_id          uuid,
  p_modulo_entrada_id uuid default null
)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_id       uuid;
  v_unidade  uuid;
  v_corrente uuid;
  v_proximo  uuid;
  v_entrada  uuid;
begin
  perform public.fn_exige_permissao('turmas.alocar');

  perform pg_advisory_xact_lock(hashtextextended(p_turma_id::text, 0));

  select t.unidade_id into v_unidade
    from public.turma_modular t where t.id = p_turma_id;

  if v_unidade is null then
    raise exception using
      errcode = 'PT404',
      message = 'Turma Modular não encontrada nesta unidade.',
      detail  = json_build_object('codigo', 'TURMA_INEXISTENTE',
                                  'turma', p_turma_id)::text;
  end if;

  -- O módulo de entrada: o corrente (o default — "vem preenchido", regra 2) ou
  -- o PRÓXIMO do rodízio, para quem entra perto de uma troca e não vai
  -- aproveitar o módulo em curso. Entrada histórica é do importador.
  select a.modulo_id into v_corrente
    from public.fn_turma_modular_agenda(p_turma_id) a where a.posicao = 1;
  select a.modulo_id into v_proximo
    from public.fn_turma_modular_agenda(p_turma_id) a where a.posicao = 2;

  v_entrada := coalesce(p_modulo_entrada_id, v_corrente);

  if p_modulo_entrada_id is not null
     and p_modulo_entrada_id is distinct from v_corrente
     and p_modulo_entrada_id is distinct from v_proximo then
    raise exception using
      errcode = 'PT422',
      message = 'O aluno só pode entrar no módulo atual da turma ou no próximo.',
      detail  = json_build_object('codigo', 'MODULO_ENTRADA_INVALIDO',
                                  'turma', p_turma_id,
                                  'modulo', p_modulo_entrada_id)::text;
  end if;

  -- Reativa em vez de duplicar (card 2.2 §4.3): a ativa primeiro, e `order by`
  -- completo porque `limit` sem ele é sorteio.
  select ta.id into v_id
    from public.turma_modular_aluno ta
   where ta.turma_id = p_turma_id and ta.aluno_id = p_aluno_id
   order by ta.ativo desc, ta.criado_em desc, ta.id
   limit 1;

  if v_id is null then
    insert into public.turma_modular_aluno (unidade_id, turma_id, aluno_id,
                                            modulo_entrada_id)
    values (v_unidade, p_turma_id, p_aluno_id, v_entrada)
    returning id into v_id;
  else
    -- Reativar limpa o motivo da saída e NÃO reescreve `data_entrada` (card
    -- 7.2). O módulo de entrada ORIGINAL também fica, e aluno_modulo não é
    -- tocado: é o que faz o aluno que voltou de STANDBY continuar de onde
    -- parou, com o módulo perdido no fim da sequência dele (regra 5). Só a
    -- linha antiga, sem módulo de entrada, recebe o de agora.
    update public.turma_modular_aluno
       set ativo             = true,
           motivo_saida      = null,
           modulo_entrada_id = coalesce(modulo_entrada_id, v_entrada)
     where id = v_id;
  end if;

  return v_id;
end $$;

comment on function public.fn_turma_modular_admitir(uuid, uuid, uuid) is
  'Admite o aluno na turma Modular e devolve o id da alocação. Exige turmas.alocar, serializa a turma com pg_advisory_xact_lock e REATIVA a alocação existente em vez de duplicar. Card 9.2,88: p_modulo_entrada_id é o módulo em que o aluno começa — nulo = o corrente; aceita só o corrente ou o próximo do rodízio (PT422/MODULO_ENTRADA_INVALIDO). Na reativação o módulo de entrada original e aluno_modulo são preservados. As regras de admissão (aluno ativo, método, lotação) continuam em tg_turma_modular_aluno_admissao.';

revoke execute on function public.fn_turma_modular_admitir(uuid, uuid, uuid) from public;
revoke execute on function public.fn_turma_modular_admitir(uuid, uuid, uuid) from anon;
grant  execute on function public.fn_turma_modular_admitir(uuid, uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 8. O avanço: grava o módulo de cada aluno e abre o ciclo seguinte
-- -----------------------------------------------------------------------------
-- Parte da ÚLTIMA definição aplicada (card 7.2, 20260905070000 §5). O que muda:
--
--   (a) o módulo corrente é uma LINHA do cronograma (turma, módulo, CICLO) — o
--       `update` por (turma_id, modulo_id) alcançaria a mesma linha de todos os
--       ciclos;
--   (b) cada aluno ATIVO da turma recebe o módulo que fechou em aluno_modulo,
--       menos quem entrou para começar no próximo;
--   (c) quem completou o curso sai da turma;
--   (d) o ciclo se completa sozinho: as linhas que faltam ao ciclo corrente
--       entram no avanço, e depois do último módulo abre-se o ciclo seguinte.
--       `TURMA_SEM_MODULO_CORRENTE` deixa de ser o destino de uma turma viva.
create or replace function public.fn_turma_modular_avancar(
  p_turma_id       uuid,
  p_data_conclusao date default public.fn_hoje()
)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade   uuid;
  v_curso     uuid;
  v_linha     uuid;      -- a linha do cronograma do módulo corrente
  v_modulo    uuid;
  v_ciclo     integer;
  v_ordem     integer;
  v_prox_linha uuid;
  v_proximo   uuid;
  v_passo     integer;
  v_tem_crono boolean;
  r           record;
begin
  perform public.fn_exige_permissao('turmas.editar');

  if p_data_conclusao is null then
    raise exception using
      errcode = 'PT422',
      message = 'A data de conclusão do módulo é obrigatória.',
      detail  = json_build_object('codigo', 'DATA_OBRIGATORIA',
                                  'turma', p_turma_id)::text;
  end if;

  -- Mesma chave da admissão: dois avanços simultâneos leriam o mesmo módulo
  -- corrente e o concluiriam duas vezes, pulando um; e uma admissão no meio do
  -- avanço não saberia se o aluno recebe ou não o módulo que está fechando.
  perform pg_advisory_xact_lock(hashtextextended(p_turma_id::text, 0));

  select t.unidade_id, t.curso_id into v_unidade, v_curso
    from public.turma_modular t where t.id = p_turma_id;

  if v_unidade is null then
    raise exception using
      errcode = 'PT404',
      message = 'Turma Modular não encontrada nesta unidade.',
      detail  = json_build_object('codigo', 'TURMA_INEXISTENTE',
                                  'turma', p_turma_id)::text;
  end if;

  -- a linha corrente: a MESMA ordem de fn_turma_modular_modulo_corrente
  select tm.id, tm.modulo_id, tm.ciclo, m.ordem
    into v_linha, v_modulo, v_ciclo, v_ordem
    from public.turma_modular_modulo tm
    join public.modulo m on m.id = tm.modulo_id
   where tm.turma_id = p_turma_id and not tm.concluido
   order by tm.ciclo, m.ordem, tm.modulo_id
   limit 1;

  if v_linha is null then
    select exists (select 1 from public.turma_modular_modulo tm
                    where tm.turma_id = p_turma_id)
      into v_tem_crono;

    -- Só turma ANTERIOR ao rodízio chega aqui com cronograma: a que concluiu
    -- todos os módulos antes deste card. A saída dela é abrir o ciclo seguinte.
    if v_tem_crono then
      raise exception using
        errcode = 'PT409',
        message = 'Todos os módulos desta turma já foram concluídos.',
        detail  = json_build_object('codigo', 'TURMA_SEM_MODULO_CORRENTE',
                                    'turma', p_turma_id)::text,
        hint    = 'Abra o próximo ciclo da turma para continuar o rodízio.';
    end if;

    raise exception using
      errcode = 'PT422',
      message = 'Esta turma não tem cronograma de módulos.',
      detail  = json_build_object('codigo', 'TURMA_SEM_CRONOGRAMA',
                                  'turma', p_turma_id)::text,
      hint    = 'Monte o cronograma da turma antes de avançar o módulo.';
  end if;

  -- 1. conclui o corrente, gravando a data REAL onde a agenda a lê
  update public.turma_modular_modulo
     set concluido      = true,
         prev_conclusao = p_data_conclusao
   where id = v_linha;

  -- 2. o módulo de cada aluno ATIVO da turma (regra 4). Fica de fora quem ainda
  --    não começou: sem módulo nenhum deste curso e com módulo de entrada
  --    diferente do que fechou — entrou para começar no próximo (§4.3).
  --    Aluno em STANDBY não está ativo na turma (tg_aluno_status_desaloca), e é
  --    por isso que a regra 5 não precisa de código próprio.
  for r in
    select ta.aluno_id
      from public.turma_modular_aluno ta
     where ta.turma_id = p_turma_id and ta.ativo
       and not (ta.modulo_entrada_id is not null
                and ta.modulo_entrada_id <> v_modulo
                and not exists (select 1
                                  from public.aluno_modulo am
                                  join public.modulo m on m.id = am.modulo_id
                                 where am.aluno_id = ta.aluno_id
                                   and m.curso_id = v_curso))
     order by ta.aluno_id
  loop
    insert into public.aluno_modulo (unidade_id, aluno_id, modulo_id, turma_id,
                                     data_conclusao, origem)
    values (v_unidade, r.aluno_id, v_modulo, p_turma_id, p_data_conclusao, 'TURMA')
        on conflict (aluno_id, modulo_id) do nothing;

    -- 3. quem completou o curso sai da turma
    perform public.fn_aluno_modular_avaliar_conclusao(r.aluno_id, p_turma_id);
  end loop;

  -- 4. o passo, já com a duração real do módulo que acabou de fechar
  select coalesce(round(avg(tm.prev_conclusao - tm.data_inicio + 1))::integer,
                  public.fn_param_int('ritmo_padrao_dias_MODULAR', 45))
    into v_passo
    from public.turma_modular_modulo tm
   where tm.turma_id = p_turma_id
     and tm.data_inicio is not null
     and tm.prev_conclusao is not null;

  if v_passo is null or v_passo < 1 then
    v_passo := public.fn_param_int('ritmo_padrao_dias_MODULAR', 45);
  end if;

  -- 5. o ciclo se completa: os módulos do catálogo DEPOIS do que fechou e que
  --    ainda não têm linha neste ciclo entram agora. Os de ordem menor não —
  --    inseri-los como "não concluídos" os tornaria o corrente.
  insert into public.turma_modular_modulo (unidade_id, turma_id, modulo_id, ciclo)
  select v_unidade, p_turma_id, m.id, v_ciclo
    from public.modulo m
   where m.curso_id = v_curso and m.ordem > v_ordem
      on conflict (turma_id, modulo_id, ciclo) do nothing;

  select tm.id, tm.modulo_id into v_prox_linha, v_proximo
    from public.turma_modular_modulo tm
    join public.modulo m on m.id = tm.modulo_id
   where tm.turma_id = p_turma_id and not tm.concluido
   order by tm.ciclo, m.ordem, tm.modulo_id
   limit 1;

  -- 6. acabou o ciclo: abre o seguinte, uma linha por módulo do curso
  if v_prox_linha is null then
    insert into public.turma_modular_modulo (unidade_id, turma_id, modulo_id, ciclo)
    select v_unidade, p_turma_id, m.id, v_ciclo + 1
      from public.modulo m
     where m.curso_id = v_curso
        on conflict (turma_id, modulo_id, ciclo) do nothing;

    select tm.id, tm.modulo_id into v_prox_linha, v_proximo
      from public.turma_modular_modulo tm
      join public.modulo m on m.id = tm.modulo_id
     where tm.turma_id = p_turma_id and not tm.concluido
     order by tm.ciclo, m.ordem, tm.modulo_id
     limit 1;
  end if;

  -- 7. abre o próximo, PRESERVANDO o que a tela já tiver informado
  if v_prox_linha is not null then
    update public.turma_modular_modulo tm
       set data_inicio    = coalesce(tm.data_inicio, p_data_conclusao + 1),
           prev_conclusao = coalesce(tm.prev_conclusao,
                                     coalesce(tm.data_inicio, p_data_conclusao + 1)
                                       + v_passo - 1)
     where tm.id = v_prox_linha;
  end if;

  return v_proximo;
end $$;

comment on function public.fn_turma_modular_avancar(uuid, date) is
  'Avanço CONJUNTO da turma Modular (card 7.2; em rodízio desde o card 9.2,88). Exige turmas.editar e serializa a turma. Conclui o módulo corrente — a linha do cronograma por (ciclo, ordem) — com a data REAL em prev_conclusao; grava aluno_modulo (origem TURMA) para cada aluno ATIVO da turma, menos quem entrou para começar no próximo; tira da turma quem completou o curso; completa as linhas do ciclo e, depois do último módulo, ABRE O CICLO SEGUINTE; abre o próximo com o passo aprendido, preservando datas informadas. Devolve o modulo_id do novo corrente. p_data_conclusao tem default fn_hoje().';

-- Turma anterior ao rodízio, com todos os módulos concluídos: abre o ciclo
-- seguinte no lugar do antigo estado "turma terminou".
create or replace function public.fn_turma_modular_abrir_ciclo(
  p_turma_id    uuid,
  p_data_inicio date default public.fn_hoje()
)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_curso   uuid;
  v_ciclo   integer;
  v_passo   integer;
  v_linha   uuid;
  v_modulo  uuid;
begin
  perform public.fn_exige_permissao('turmas.editar');

  if p_data_inicio is null then
    raise exception using
      errcode = 'PT422',
      message = 'A data de início do ciclo é obrigatória.',
      detail  = json_build_object('codigo', 'DATA_OBRIGATORIA',
                                  'turma', p_turma_id)::text;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_turma_id::text, 0));

  select t.unidade_id, t.curso_id into v_unidade, v_curso
    from public.turma_modular t where t.id = p_turma_id;

  if v_unidade is null then
    raise exception using
      errcode = 'PT404',
      message = 'Turma Modular não encontrada nesta unidade.',
      detail  = json_build_object('codigo', 'TURMA_INEXISTENTE',
                                  'turma', p_turma_id)::text;
  end if;

  if public.fn_turma_modular_modulo_corrente(p_turma_id) is not null then
    raise exception using
      errcode = 'PT409',
      message = 'Esta turma ainda tem módulo em curso.',
      detail  = json_build_object('codigo', 'TURMA_COM_MODULO_CORRENTE',
                                  'turma', p_turma_id)::text,
      hint    = 'O próximo ciclo abre sozinho quando o último módulo for avançado.';
  end if;

  select max(tm.ciclo) into v_ciclo
    from public.turma_modular_modulo tm where tm.turma_id = p_turma_id;

  if v_ciclo is null then
    raise exception using
      errcode = 'PT422',
      message = 'Esta turma não tem cronograma de módulos.',
      detail  = json_build_object('codigo', 'TURMA_SEM_CRONOGRAMA',
                                  'turma', p_turma_id)::text,
      hint    = 'Monte o cronograma da turma.';
  end if;

  select coalesce(round(avg(tm.prev_conclusao - tm.data_inicio + 1))::integer,
                  public.fn_param_int('ritmo_padrao_dias_MODULAR', 45))
    into v_passo
    from public.turma_modular_modulo tm
   where tm.turma_id = p_turma_id
     and tm.data_inicio is not null and tm.prev_conclusao is not null;
  if v_passo is null or v_passo < 1 then
    v_passo := public.fn_param_int('ritmo_padrao_dias_MODULAR', 45);
  end if;

  insert into public.turma_modular_modulo (unidade_id, turma_id, modulo_id, ciclo)
  select v_unidade, p_turma_id, m.id, v_ciclo + 1
    from public.modulo m
   where m.curso_id = v_curso
      on conflict (turma_id, modulo_id, ciclo) do nothing;

  select tm.id, tm.modulo_id into v_linha, v_modulo
    from public.turma_modular_modulo tm
    join public.modulo m on m.id = tm.modulo_id
   where tm.turma_id = p_turma_id and not tm.concluido
   order by tm.ciclo, m.ordem, tm.modulo_id
   limit 1;

  update public.turma_modular_modulo
     set data_inicio    = p_data_inicio,
         prev_conclusao = p_data_inicio + v_passo - 1
   where id = v_linha;

  return v_modulo;
end $$;

comment on function public.fn_turma_modular_abrir_ciclo(uuid, date) is
  'Card 9.2,88: abre o ciclo seguinte de uma turma Modular cujos módulos estão todos concluídos — o estado "turma terminou" de antes do rodízio. Exige turmas.editar e serializa a turma. Cria uma linha por módulo do curso no ciclo novo e data o primeiro (início informado, fim pelo passo). PT409/TURMA_COM_MODULO_CORRENTE se ainda há módulo em curso; PT422/TURMA_SEM_CRONOGRAMA se a turma nunca teve cronograma. Devolve o modulo_id do novo corrente.';

revoke execute on function public.fn_turma_modular_abrir_ciclo(uuid, date) from public;
revoke execute on function public.fn_turma_modular_abrir_ciclo(uuid, date) from anon;
grant  execute on function public.fn_turma_modular_abrir_ciclo(uuid, date) to authenticated;

-- -----------------------------------------------------------------------------
-- 9. A exceção à mão (regra 6)
-- -----------------------------------------------------------------------------
create or replace function public.fn_aluno_modulo_registrar(
  p_aluno_id       uuid,
  p_modulo_id      uuid,
  p_data_conclusao date default public.fn_hoje(),
  p_observacao     text default null
)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_curso   uuid;
  v_id      uuid;
  r         record;
begin
  perform public.fn_exige_permissao('alunos.editar_trilha');

  if p_data_conclusao is null then
    raise exception using
      errcode = 'PT422',
      message = 'A data de conclusão do módulo é obrigatória.',
      detail  = json_build_object('codigo', 'DATA_OBRIGATORIA',
                                  'aluno', p_aluno_id)::text;
  end if;

  select a.unidade_id into v_unidade from public.aluno a where a.id = p_aluno_id;
  if v_unidade is null then
    raise exception using
      errcode = 'PT404',
      message = 'Aluno não encontrado nesta unidade.',
      detail  = json_build_object('codigo', 'ALUNO_INEXISTENTE',
                                  'aluno', p_aluno_id)::text;
  end if;

  select m.curso_id into v_curso from public.modulo m where m.id = p_modulo_id;
  if v_curso is null then
    raise exception using
      errcode = 'PT404',
      message = 'Módulo não encontrado nesta unidade.',
      detail  = json_build_object('codigo', 'MODULO_INEXISTENTE',
                                  'modulo', p_modulo_id)::text;
  end if;

  if exists (select 1 from public.aluno_modulo am
              where am.aluno_id = p_aluno_id and am.modulo_id = p_modulo_id) then
    raise exception using
      errcode = 'PT409',
      message = 'Este módulo já está registrado para o aluno.',
      detail  = json_build_object('codigo', 'MODULO_JA_REGISTRADO',
                                  'aluno', p_aluno_id, 'modulo', p_modulo_id)::text;
  end if;

  insert into public.aluno_modulo (unidade_id, aluno_id, modulo_id, data_conclusao,
                                   origem, observacao)
  values (v_unidade, p_aluno_id, p_modulo_id, p_data_conclusao, 'MANUAL',
          nullif(btrim(p_observacao), ''))
  returning id into v_id;

  -- Registrar o último módulo conclui o curso, como o avanço faria.
  for r in select ta.turma_id
             from public.turma_modular_aluno ta
             join public.turma_modular t on t.id = ta.turma_id
            where ta.aluno_id = p_aluno_id and ta.ativo and t.curso_id = v_curso
            order by ta.turma_id
  loop
    perform public.fn_aluno_modular_avaliar_conclusao(p_aluno_id, r.turma_id);
  end loop;

  return v_id;
end $$;

comment on function public.fn_aluno_modulo_registrar(uuid, uuid, date, text) is
  'Exceção à mão (card 9.2,88, regra 6): registra que o aluno FEZ um módulo por fora do avanço da turma (origem MANUAL). Exige alunos.editar_trilha. PT409/MODULO_JA_REGISTRADO se já existe. Registrar o último módulo do curso tira o aluno da turma, como o avanço. p_data_conclusao tem default fn_hoje().';

revoke execute on function public.fn_aluno_modulo_registrar(uuid, uuid, date, text) from public;
revoke execute on function public.fn_aluno_modulo_registrar(uuid, uuid, date, text) from anon;
grant  execute on function public.fn_aluno_modulo_registrar(uuid, uuid, date, text) to authenticated;

create or replace function public.fn_aluno_modulo_remover(
  p_aluno_id  uuid,
  p_modulo_id uuid,
  p_motivo    text
)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
begin
  perform public.fn_exige_permissao('alunos.editar_trilha');

  -- Remover é dizer "ele precisa refazer", e decisão sem porquê é decisão
  -- perdida (mesmo argumento de fn_pendencia_resolver_id, card 5.5).
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception using
      errcode = 'PT422',
      message = 'Informe o motivo para remover o módulo do aluno.',
      detail  = json_build_object('codigo', 'MOTIVO_OBRIGATORIO',
                                  'aluno', p_aluno_id, 'modulo', p_modulo_id)::text;
  end if;

  -- `is_local => true`: o motivo morre no fim da transação e não vaza para a
  -- remoção seguinte.
  perform set_config('app.aluno_modulo_motivo', btrim(p_motivo), true);

  delete from public.aluno_modulo am
   where am.aluno_id = p_aluno_id and am.modulo_id = p_modulo_id;

  if not found then
    perform set_config('app.aluno_modulo_motivo', '', true);
    raise exception using
      errcode = 'PT404',
      message = 'Este módulo não está registrado para o aluno.',
      detail  = json_build_object('codigo', 'MODULO_NAO_REGISTRADO',
                                  'aluno', p_aluno_id, 'modulo', p_modulo_id)::text;
  end if;

  perform set_config('app.aluno_modulo_motivo', '', true);
end $$;

comment on function public.fn_aluno_modulo_remover(uuid, uuid, text) is
  'Exceção à mão (card 9.2,88, regra 6): remove um módulo do registro do aluno — ele precisa refazer. Exige alunos.editar_trilha e motivo (PT422/MOTIVO_OBRIGATORIO), que vai para aluno_modulo_hist. PT404/MODULO_NAO_REGISTRADO quando não há o que remover. Não devolve o aluno à turma de que saiu por conclusão: isso é admissão.';

revoke execute on function public.fn_aluno_modulo_remover(uuid, uuid, text) from public;
revoke execute on function public.fn_aluno_modulo_remover(uuid, uuid, text) from anon;
grant  execute on function public.fn_aluno_modulo_remover(uuid, uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 10. As views da turma, com o rodízio
-- -----------------------------------------------------------------------------
-- `create or replace` a partir da última aplicada (card 9.2,85), com as colunas
-- novas NO FIM. Duas mudanças no corpo:
--   • o corrente por (ciclo, ordem);
--   • o PRÓXIMO módulo dá a volta: depois do último vem o primeiro. Antes o
--     último módulo não tinha próximo; no rodízio tem, e `troca_de_livro` passa
--     a valer também na virada do ciclo.
create or replace view public.v_turma_modular_lotacao with (security_invoker = on) as
select t.unidade_id,
       t.id        as turma_id,
       t.nome      as turma_nome,
       t.curso_id,
       c.nome      as curso_nome,
       t.sala_id,
       s.nome      as sala_nome,
       t.capacidade,
       (select count(*) from public.turma_modular_aluno ta
         where ta.turma_id = t.id and ta.ativo)::integer as alocados,
       greatest(t.capacidade
                - (select count(*) from public.turma_modular_aluno ta
                    where ta.turma_id = t.id and ta.ativo), 0)::integer as vagas_livres,
       mc.modulo_id      as modulo_corrente_id,
       mo.nome           as modulo_corrente_nome,
       mo.ordem          as modulo_corrente_ordem,
       mc.data_inicio    as modulo_corrente_inicio,
       mc.prev_conclusao as modulo_corrente_prev_conclusao,
       (mc.prev_conclusao is not null and mc.prev_conclusao < public.fn_hoje()) as modulo_atrasado,
       t.data_inicio,
       -- Card 9.2,85: o aviso de troca de módulo.
       mc.cronograma_id  as modulo_corrente_cronograma_id,
       px.modulo_id      as proximo_modulo_id,
       px.nome           as proximo_modulo_nome,
       px.material_id    as proximo_material_id,
       pm.nome           as proximo_material_nome,
       (px.material_id <> mo.material_id) as troca_de_livro,
       (mc.prev_conclusao - public.fn_hoje())::integer as dias_para_troca,
       (case
          when mc.modulo_id is null then null
          when mc.prev_conclusao is null then 'SEM_PREVISAO'
          when mc.prev_conclusao - public.fn_hoje() <= 0 then 'HOJE_OU_VENCIDA'
          when mc.prev_conclusao - public.fn_hoje()
               <= public.fn_param_int('troca_modulo_alerta_dias') then 'PROXIMA'
          else 'EM_DIA'
        end)::text       as situacao_troca,
       -- Card 9.2,88: o ciclo do módulo corrente.
       mc.ciclo          as modulo_corrente_ciclo
  from public.turma_modular t
  join public.curso c on c.id = t.curso_id
  join public.sala  s on s.id = t.sala_id
  left join lateral (
         select tm.id as cronograma_id, tm.modulo_id, tm.data_inicio,
                tm.prev_conclusao, tm.ciclo
           from public.turma_modular_modulo tm
           join public.modulo m2 on m2.id = tm.modulo_id
          where tm.turma_id = t.id and not tm.concluido
          order by tm.ciclo, m2.ordem, tm.modulo_id
          limit 1
       ) mc on true
  left join public.modulo mo on mo.id = mc.modulo_id
  left join lateral (
         -- O próximo do RODÍZIO: o de ordem seguinte e, depois do último, o
         -- primeiro. `(m3.ordem > mo.ordem) desc` põe os de ordem maior na
         -- frente; sem nenhum, sobra o de menor ordem. Curso de um módulo só
         -- não tem próximo distinto.
         select m3.id as modulo_id, m3.nome, m3.material_id
           from public.modulo m3
          where m3.curso_id = t.curso_id
            and m3.id <> mo.id
          order by (m3.ordem > mo.ordem) desc, m3.ordem, m3.id
          limit 1
       ) px on true
  left join public.material pm on pm.id = px.material_id
 where t.ativo;

comment on column public.v_turma_modular_lotacao.proximo_modulo_id is
  'O próximo módulo do RODÍZIO (card 9.2,88): o de ordem seguinte no catálogo do curso e, depois do último, o primeiro. Do catálogo, e não do cronograma, para a troca de livro aparecer antes de a linha existir. NULO sem módulo corrente ou em curso de um módulo só.';

comment on column public.v_turma_modular_lotacao.modulo_corrente_ciclo is
  'O ciclo (a volta da turma pelos módulos) do módulo corrente — card 9.2,88.';

create or replace view public.v_turma_modular_cronograma with (security_invoker = on) as
select tm.unidade_id,
       tm.id          as cronograma_id,
       tm.turma_id,
       tm.modulo_id,
       m.nome         as modulo_nome,
       m.ordem        as modulo_ordem,
       m.material_id,
       tm.data_inicio,
       tm.prev_conclusao,
       tm.concluido,
       (not tm.concluido
        and row_number() over (partition by tm.turma_id, tm.concluido
                                   order by tm.ciclo, m.ordem, tm.modulo_id) = 1) as corrente,
       (not tm.concluido
        and tm.prev_conclusao is not null
        and tm.prev_conclusao < public.fn_hoje())          as atrasado,
       -- Card 9.2,88: a volta da turma. No fim, como manda o card 9.2,7.
       tm.ciclo
  from public.turma_modular_modulo tm
  join public.modulo m on m.id = tm.modulo_id;

comment on column public.v_turma_modular_cronograma.corrente is
  'O primeiro módulo NÃO concluído por (ciclo, modulo.ordem) — a mesma definição de fn_turma_modular_modulo_corrente e do left join lateral de v_turma_modular_lotacao, e o teste 072 §3 compara as três linha a linha. O ciclo entrou na ordem no card 9.2,88.';

comment on column public.v_turma_modular_cronograma.ciclo is
  'A volta da turma pelos módulos do curso (card 9.2,88). A tela mostra o ciclo corrente e guarda os anteriores como histórico.';

-- -----------------------------------------------------------------------------
-- 11. O progresso do aluno — derivado, nunca guardado
-- -----------------------------------------------------------------------------
-- Uma linha por alocação ATIVA em turma ATIVA. `security_invoker`: o join em
-- `aluno` é interno, e sem `alunos.ler` a view vem vazia — é a tela que declara
-- a permissão que falta, como em v_turma_modular_aluno (card 7.3).
--
-- A agenda é chamada por linha, e é barata: N é o número de módulos do curso.
create view public.v_aluno_modular_progresso with (security_invoker = on) as
select ta.unidade_id,
       ta.id            as alocacao_id,
       ta.turma_id,
       t.nome           as turma_nome,
       t.curso_id,
       c.nome           as curso_nome,
       ta.aluno_id,
       a.nome           as aluno_nome,
       ta.modulo_entrada_id,
       me.nome          as modulo_entrada_nome,
       tot.total        as modulos_total,
       tot.feitos       as modulos_feitos,
       fal.proximo_modulo_id,
       fal.proximo_modulo_nome,
       fal.prev_conclusao,
       esp.aguardando   as aguardando_entrada
  from public.turma_modular_aluno ta
  join public.turma_modular t on t.id = ta.turma_id
  join public.curso c on c.id = t.curso_id
  join public.aluno a on a.id = ta.aluno_id
  left join public.modulo me on me.id = ta.modulo_entrada_id
  cross join lateral (
         select count(*)::integer as total,
                count(*) filter (where exists (
                    select 1 from public.aluno_modulo am
                     where am.aluno_id = ta.aluno_id and am.modulo_id = m.id))::integer
                  as feitos
           from public.modulo m
          where m.curso_id = t.curso_id
       ) tot
  cross join lateral (
         -- Entrou para começar no PRÓXIMO módulo e ainda não começou: a MESMA
         -- condição com que fn_turma_modular_avancar deixa de lhe dar o módulo
         -- que fecha. Para ele o corrente de hoje só volta na outra volta.
         select (ta.modulo_entrada_id is not null
                 and tot.feitos = 0
                 and ta.modulo_entrada_id is distinct from
                     public.fn_turma_modular_modulo_corrente(ta.turma_id)) as aguardando
       ) esp
  left join lateral (
         -- os módulos que FALTAM ao aluno, cada um na PRIMEIRA vez em que a
         -- turma o dará a ele: o primeiro é o próximo dele; o fim do último é a
         -- previsão de conclusão
         select (array_agg(x.modulo_id   order by x.posicao))[1] as proximo_modulo_id,
                (array_agg(x.modulo_nome order by x.posicao))[1] as proximo_modulo_nome,
                max(x.data_fim) as prev_conclusao
           from (select distinct on (ag.modulo_id)
                        ag.modulo_id, ag.modulo_nome, ag.posicao, ag.data_fim
                   from public.fn_turma_modular_agenda(ta.turma_id) ag
                  where not exists (select 1 from public.aluno_modulo am
                                     where am.aluno_id = ta.aluno_id
                                       and am.modulo_id = ag.modulo_id)
                    and (ag.posicao > 1 or not esp.aguardando)
                  order by ag.modulo_id, ag.posicao) x
       ) fal on true
 where ta.ativo and t.ativo;

comment on view public.v_aluno_modular_progresso is
  'O progresso do aluno na turma Modular em rodízio (card 9.2,88, docs/turma-rodizio.md §5.2): módulo de entrada, quantos módulos fez de quantos, o próximo módulo DELE e a previsão de conclusão — a data em que a turma termina o último módulo que lhe falta, lida de fn_turma_modular_agenda. Tudo DERIVADO: nada aqui é guardado por aluno além do que ele já fez. Uma linha por alocação ativa em turma ativa.';

comment on column public.v_aluno_modular_progresso.aguardando_entrada is
  'O aluno entrou para começar no PRÓXIMO módulo e ainda não começou — a mesma condição com que fn_turma_modular_avancar não lhe dá o módulo que fecha. Para ele o módulo corrente de hoje é o último da sequência.';

comment on column public.v_aluno_modular_progresso.prev_conclusao is
  'A data planejada em que a turma termina o último módulo que falta ao aluno. NULA quando a turma não tem data nenhuma (não há o que extrapolar) ou quando não falta módulo.';

revoke all   on public.v_aluno_modular_progresso from public;
revoke all   on public.v_aluno_modular_progresso from anon;
grant select on public.v_aluno_modular_progresso to authenticated;

-- A sequência completa do aluno, para a ficha: os feitos (com a data real),
-- depois os que faltam, na ordem em que a turma os dará.
create view public.v_aluno_modular_modulo with (security_invoker = on) as
select ta.unidade_id,
       ta.id            as alocacao_id,
       ta.turma_id,
       ta.aluno_id,
       m.id             as modulo_id,
       m.nome           as modulo_nome,
       m.ordem          as modulo_ordem,
       m.material_id,
       (am.id is not null)        as feito,
       am.data_conclusao,
       am.origem,
       (m.id = ta.modulo_entrada_id) as de_entrada,
       ag.posicao       as posicao_agenda,
       ag.data_inicio   as data_prevista_inicio,
       ag.data_fim      as data_prevista_fim,
       -- A ordem de leitura: primeiro o que ele fez, por data; depois o que
       -- falta, pela agenda. Ordem TOTAL (o módulo desempata).
       row_number() over (
         partition by ta.id
         order by (am.id is null), am.data_conclusao, ag.posicao, m.ordem, m.id
       )::integer       as sequencia
  from public.turma_modular_aluno ta
  join public.turma_modular t on t.id = ta.turma_id
  join public.aluno a on a.id = ta.aluno_id
  join public.modulo m on m.curso_id = t.curso_id
  left join public.aluno_modulo am
         on am.aluno_id = ta.aluno_id and am.modulo_id = m.id
  left join lateral (
         -- a PRIMEIRA vez em que a turma dará este módulo ao aluno — para quem
         -- entrou para começar no próximo, o corrente só conta na outra volta
         select x.posicao, x.data_inicio, x.data_fim
           from public.fn_turma_modular_agenda(ta.turma_id) x
          where x.modulo_id = m.id
            and (x.posicao > 1
                 or not (ta.modulo_entrada_id is not null
                         and ta.modulo_entrada_id is distinct from
                             public.fn_turma_modular_modulo_corrente(ta.turma_id)
                         and not exists (select 1
                                           from public.aluno_modulo am2
                                           join public.modulo m2 on m2.id = am2.modulo_id
                                          where am2.aluno_id = ta.aluno_id
                                            and m2.curso_id = t.curso_id)))
          order by x.posicao
          limit 1
       ) ag on true
 where ta.ativo and t.ativo;

comment on view public.v_aluno_modular_modulo is
  'A sequência de módulos do aluno na turma Modular em rodízio, para a ficha (card 9.2,88, docs/turma-rodizio.md §5.2): uma linha por módulo do curso — os FEITOS com a data real e a origem, depois os que FALTAM com a data planejada pela agenda da turma, na ordem em que a turma os dará. `sequencia` é a ordem de leitura. Derivada: a lista por aluno não é guardada em lugar nenhum.';

revoke all   on public.v_aluno_modular_modulo from public;
revoke all   on public.v_aluno_modular_modulo from anon;
grant select on public.v_aluno_modular_modulo to authenticated;

-- -----------------------------------------------------------------------------
-- 12. O importador: a chave do cronograma ganhou o ciclo
-- -----------------------------------------------------------------------------
-- `on conflict (turma_id, modulo_id)` deixou de ter índice que o sustente — a
-- unique agora é (turma_id, modulo_id, ciclo) — e a aplicação de QUALQUER lote
-- com cronograma morreria com "no unique or exclusion constraint matching".
-- A função parte da última definição aplicada (card 9.2,77,
-- 20261001120000_pc_de_professor.sql), palavra por palavra, com UMA linha
-- trocada. O arquivo continua a entrar no ciclo 1 (a coluna tem default); o
-- ciclo, o módulo de entrada e aluno_modulo no arquivo são do card 9.2,91.
create or replace function public.fn_importacao_aplicar(
  p_importacao_id uuid,
  p_simular       boolean default true
)
returns jsonb
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_dados   jsonb;
  v_status  text;
  v_d       jsonb;
  v_totais  jsonb := '{}'::jsonb;
  v_n       integer;
  v_m       integer;
  v_estado  text;
  v_msg     text;
  v_detalhe text;
  v_codigo  text;
  v_entidades constant text[] := array[
    'professor','sala','pc','pc_manutencao','material','curso','curso_material',
    'modulo','combo','combo_curso','aluno','bloco_horario','bloco_aluno',
    'turma_modular','turma_modular_modulo','turma_modular_aluno',
    'aluno_material','movimento_estoque'];
begin
  perform public.fn_importacao_exigir();

  -- Card 9.2,68: `for update`. Sem ele, duas aplicações simultâneas do mesmo
  -- lote liam as duas o status VALIDADA e corriam juntas: medido em
  -- 24/09/2026 (tests_concorrencia/importacao_aplicar_dupla.sh), a segunda
  -- aplicava o lote DE NOVO e também devolvia APLICADA; com movimento de
  -- estoque no arquivo, ela pararia na unique de importacao_referencia, com
  -- erro de chave. Com a trava, a segunda espera a primeira terminar e lê
  -- APLICADA: recusa legível (IMPORTACAO_JA_APLICADA).
  select i.unidade_id, i.dados, i.status
    into v_unidade, v_dados, v_status
    from public.importacao i
   where i.id = p_importacao_id
     for update;

  if v_unidade is null then
    raise exception using
      errcode = 'PT404',
      message = 'Esta importação não foi encontrada.',
      detail  = json_build_object('codigo', 'IMPORTACAO_INEXISTENTE',
                                  'importacao', p_importacao_id)::text;
  end if;

  if v_status = 'APLICADA' then
    raise exception using
      errcode = 'PT409',
      message = 'Esta importação já foi aplicada. Para reexecutar o snapshot, envie o arquivo de novo.',
      detail  = json_build_object('codigo', 'IMPORTACAO_JA_APLICADA',
                                  'importacao', p_importacao_id)::text;
  end if;

  if exists (select 1 from public.importacao_ocorrencia o
              where o.importacao_id = p_importacao_id and o.severidade = 'ERRO') then
    raise exception using
      errcode = 'PT422',
      message = 'Esta importação tem erros que precisam ser corrigidos no arquivo antes de aplicar.',
      detail  = json_build_object('codigo', 'IMPORTACAO_REPROVADA',
                                  'importacao', p_importacao_id)::text;
  end if;

  select coalesce(jsonb_object_agg(e.nome,
           case when jsonb_typeof(v_dados -> e.nome) = 'array'
                then v_dados -> e.nome else '[]'::jsonb end), '{}'::jsonb)
    into v_d
    from unnest(v_entidades) e(nome);

  begin
    -- 1. professor ------------------------------------------------------------
    insert into public.professor (unidade_id, nome, ativo)
    select v_unidade, btrim(e.j ->> 'nome'),
           coalesce(e.j ->> 'ativo', 'true') <> 'false'
      from jsonb_array_elements(v_d -> 'professor') e(j)
        on conflict (unidade_id, nome) do update set ativo = excluded.ativo;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'professor',
                  jsonb_array_length(v_d -> 'professor'), v_n);

    -- 2. sala -----------------------------------------------------------------
    insert into public.sala (unidade_id, nome, tipo, capacidade_nominal, ativo)
    select v_unidade, btrim(e.j ->> 'nome'), e.j ->> 'tipo',
           public.fn_importacao_int(e.j ->> 'capacidade_nominal'),
           coalesce(e.j ->> 'ativo', 'true') <> 'false'
      from jsonb_array_elements(v_d -> 'sala') e(j)
        on conflict (unidade_id, nome) do update
       set tipo = excluded.tipo,
           capacidade_nominal = excluded.capacidade_nominal,
           ativo = excluded.ativo;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'sala',
                  jsonb_array_length(v_d -> 'sala'), v_n);

    -- 3. pc -------------------------------------------------------------------
    -- `de_professor` (card 9.2,77): o PC novo nasce com o valor do arquivo, ou
    -- false; o que já existe NÃO o recebe do upsert — ver o `update` logo
    -- abaixo, que só alcança as linhas que trazem a chave.
    insert into public.pc (unidade_id, sala_id, identificador, status, observacao,
                           de_professor)
    select v_unidade, s.id, btrim(e.j ->> 'identificador'),
           coalesce(e.j ->> 'status', 'OPERACIONAL'), e.j ->> 'observacao',
           coalesce((e.j ->> 'de_professor')::boolean, false)
      from jsonb_array_elements(v_d -> 'pc') e(j)
      join public.sala s on s.unidade_id = v_unidade
                        and s.nome = btrim(e.j ->> 'sala')
        on conflict (unidade_id, identificador) do update
       set sala_id = excluded.sala_id,
           status  = excluded.status,
           observacao = excluded.observacao;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'pc',
                  jsonb_array_length(v_d -> 'pc'), v_n);

    -- Ausente é "não sei" e preserva o que está gravado; presente vale. Sem
    -- isto, reimportar um arquivo sem a chave desmarcaria em silêncio o PC do
    -- professor marcado na tela (card 9.2,77). Não entra nos totais: a linha
    -- já foi contada pelo upsert de cima.
    update public.pc p
       set de_professor = (e.j ->> 'de_professor')::boolean
      from jsonb_array_elements(v_d -> 'pc') e(j)
     where p.unidade_id = v_unidade
       and p.identificador = btrim(e.j ->> 'identificador')
       and e.j ->> 'de_professor' is not null
       and p.de_professor is distinct from (e.j ->> 'de_professor')::boolean;

    -- 4. pc_manutencao --------------------------------------------------------
    -- Sem chave natural: idempotente por (pc, data_inicio), que é o que
    -- distingue duas manutenções do mesmo PC.
    insert into public.pc_manutencao (unidade_id, pc_id, tipo, data_inicio,
                                      data_fim, descricao)
    select v_unidade, p.id, coalesce(e.j ->> 'tipo', 'CORRETIVA'),
           coalesce(public.fn_importacao_data(e.j ->> 'data_inicio'), public.fn_hoje()),
           public.fn_importacao_data(e.j ->> 'data_fim'), e.j ->> 'descricao'
      from jsonb_array_elements(v_d -> 'pc_manutencao') e(j)
      join public.pc p on p.unidade_id = v_unidade
                      and p.identificador = btrim(e.j ->> 'pc')
     where not exists (
           select 1 from public.pc_manutencao pm
            where pm.pc_id = p.id
              and pm.data_inicio = coalesce(
                    public.fn_importacao_data(e.j ->> 'data_inicio'), public.fn_hoje()));
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'pc_manutencao',
                  jsonb_array_length(v_d -> 'pc_manutencao'), v_n);

    -- 5. material -------------------------------------------------------------
    insert into public.material (unidade_id, metodo_id, codigo, nome, categoria,
                                 estoque_minimo, ativo)
    select v_unidade, mo.id, btrim(e.j ->> 'codigo'), btrim(e.j ->> 'nome'),
           e.j ->> 'categoria',
           coalesce(public.fn_importacao_int(e.j ->> 'estoque_minimo'), 0),
           coalesce(e.j ->> 'ativo', 'true') <> 'false'
      from jsonb_array_elements(v_d -> 'material') e(j)
      join public.metodo mo on mo.unidade_id = v_unidade
                           and mo.codigo = e.j ->> 'metodo'
        on conflict (unidade_id, metodo_id, codigo) do update
       set nome = excluded.nome,
           categoria = excluded.categoria,
           estoque_minimo = excluded.estoque_minimo,
           ativo = excluded.ativo;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'material',
                  jsonb_array_length(v_d -> 'material'), v_n);

    -- 6. curso ----------------------------------------------------------------
    insert into public.curso (unidade_id, metodo_id, nome, ativo)
    select v_unidade, mo.id, btrim(e.j ->> 'nome'),
           coalesce(e.j ->> 'ativo', 'true') <> 'false'
      from jsonb_array_elements(v_d -> 'curso') e(j)
      join public.metodo mo on mo.unidade_id = v_unidade
                           and mo.codigo = e.j ->> 'metodo'
        on conflict (unidade_id, metodo_id, nome) do update set ativo = excluded.ativo;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'curso',
                  jsonb_array_length(v_d -> 'curso'), v_n);

    -- 7. curso_material -------------------------------------------------------
    -- `on conflict` na unique NÃO deferrable (curso_material_uk); a de `ordem` é
    -- deferrable e o Postgres não a aceita para inferência — o que é bom, porque
    -- é justamente ela que precisa adiar a checagem quando a sequência muda.
    insert into public.curso_material (unidade_id, curso_id, material_id, ordem)
    select v_unidade, c.id, m.id, public.fn_importacao_int(e.j ->> 'ordem')
      from jsonb_array_elements(v_d -> 'curso_material') e(j)
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
      join public.curso c   on c.unidade_id = v_unidade and c.metodo_id = mo.id
                           and c.nome = btrim(e.j ->> 'curso')
      join public.material m on m.unidade_id = v_unidade and m.metodo_id = mo.id
                            and m.codigo = btrim(e.j ->> 'material')
        on conflict (curso_id, material_id) do update set ordem = excluded.ordem;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'curso_material',
                  jsonb_array_length(v_d -> 'curso_material'), v_n);

    -- 8. modulo ---------------------------------------------------------------
    -- Update e insert separados: a única unique de `modulo` é (curso, ordem) e é
    -- DEFERRABLE, então não serve de alvo para `on conflict`.
    update public.modulo md
       set nome = btrim(e.j ->> 'nome'), material_id = m.id
      from jsonb_array_elements(v_d -> 'modulo') e(j)
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
      join public.curso c   on c.unidade_id = v_unidade and c.metodo_id = mo.id
                           and c.nome = btrim(e.j ->> 'curso')
      join public.material m on m.unidade_id = v_unidade and m.metodo_id = mo.id
                            and m.codigo = btrim(e.j ->> 'material')
     where md.curso_id = c.id
       and md.ordem = public.fn_importacao_int(e.j ->> 'ordem');
    get diagnostics v_n = row_count;

    insert into public.modulo (unidade_id, curso_id, material_id, nome, ordem)
    select v_unidade, c.id, m.id, btrim(e.j ->> 'nome'),
           public.fn_importacao_int(e.j ->> 'ordem')
      from jsonb_array_elements(v_d -> 'modulo') e(j)
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
      join public.curso c   on c.unidade_id = v_unidade and c.metodo_id = mo.id
                           and c.nome = btrim(e.j ->> 'curso')
      join public.material m on m.unidade_id = v_unidade and m.metodo_id = mo.id
                            and m.codigo = btrim(e.j ->> 'material')
     where not exists (select 1 from public.modulo md
                        where md.curso_id = c.id
                          and md.ordem = public.fn_importacao_int(e.j ->> 'ordem'));
    get diagnostics v_m = row_count;
    v_n := v_n + v_m;
    v_totais := public.fn_importacao_total(v_totais, 'modulo',
                  jsonb_array_length(v_d -> 'modulo'), v_n);

    -- 9. combo ----------------------------------------------------------------
    insert into public.combo (unidade_id, metodo_id, nome, ativo)
    select v_unidade, mo.id, btrim(e.j ->> 'nome'),
           coalesce(e.j ->> 'ativo', 'true') <> 'false'
      from jsonb_array_elements(v_d -> 'combo') e(j)
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
        on conflict (unidade_id, nome) do update
       set ativo = excluded.ativo, metodo_id = excluded.metodo_id;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'combo',
                  jsonb_array_length(v_d -> 'combo'), v_n);

    -- 10. combo_curso ---------------------------------------------------------
    insert into public.combo_curso (unidade_id, combo_id, curso_id, ordem)
    select v_unidade, cb.id, c.id, public.fn_importacao_int(e.j ->> 'ordem')
      from jsonb_array_elements(v_d -> 'combo_curso') e(j)
      join public.combo cb  on cb.unidade_id = v_unidade
                           and cb.nome = btrim(e.j ->> 'combo')
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
      join public.curso c   on c.unidade_id = v_unidade and c.metodo_id = mo.id
                           and c.nome = btrim(e.j ->> 'curso')
        on conflict (combo_id, curso_id) do update set ordem = excluded.ordem;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'combo_curso',
                  jsonb_array_length(v_d -> 'combo_curso'), v_n);

    -- 11. aluno ---------------------------------------------------------------
    -- ⚠️ `status` só entra no INSERT. No update ele fica de fora de propósito:
    --    mudar status é transição, tg_aluno_status_valida a examina e o gate de
    --    FORMADO (card 8.3) pode recusá-la — e uma importação que reprova porque
    --    um aluno se formou entre dois snapshots é uma importação que não se
    --    consegue repetir. A divergência entre arquivo e sistema vira AVISO na
    --    validação (V16), e a mudança se faz na tela, que é onde a regra mora.
    insert into public.aluno (unidade_id, codigo_sgf, nome, metodo_id, combo_id,
                              status, data_inicio, prev_conclusao_curso, observacoes)
    select v_unidade, btrim(e.j ->> 'codigo'), btrim(e.j ->> 'nome'), mo.id, cb.id,
           coalesce(e.j ->> 'status', 'ATIVO'),
           coalesce(public.fn_importacao_data(e.j ->> 'data_inicio'), public.fn_hoje()),
           public.fn_importacao_data(e.j ->> 'prev_conclusao_curso'),
           e.j ->> 'observacoes'
      from jsonb_array_elements(v_d -> 'aluno') e(j)
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
      left join public.combo cb on cb.unidade_id = v_unidade
                               and cb.nome = btrim(e.j ->> 'combo')
        on conflict (unidade_id, codigo_sgf) where codigo_sgf is not null do update
       set nome = excluded.nome,
           combo_id = excluded.combo_id,
           data_inicio = excluded.data_inicio,
           prev_conclusao_curso = excluded.prev_conclusao_curso,
           observacoes = excluded.observacoes;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'aluno',
                  jsonb_array_length(v_d -> 'aluno'), v_n);

    -- 12. bloco_horario -------------------------------------------------------
    insert into public.bloco_horario (unidade_id, dia_semana, hora_inicio, metodo_id,
                                      professor_id, sala_id, capacidade_override, ativo)
    select v_unidade, public.fn_importacao_int(e.j ->> 'dia_semana')::smallint,
           public.fn_importacao_hora(e.j ->> 'hora_inicio'), mo.id, pr.id, s.id,
           public.fn_importacao_int(e.j ->> 'capacidade_override'),
           coalesce(e.j ->> 'ativo', 'true') <> 'false'
      from jsonb_array_elements(v_d -> 'bloco_horario') e(j)
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
      join public.sala s    on s.unidade_id = v_unidade and s.nome = btrim(e.j ->> 'sala')
      left join public.professor pr on pr.unidade_id = v_unidade
                                   and pr.nome = btrim(e.j ->> 'professor')
        on conflict (unidade_id, sala_id, dia_semana, hora_inicio) do update
       set metodo_id = excluded.metodo_id,
           professor_id = excluded.professor_id,
           capacidade_override = excluded.capacidade_override,
           ativo = excluded.ativo;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'bloco_horario',
                  jsonb_array_length(v_d -> 'bloco_horario'), v_n);

    -- 13. bloco_aluno ---------------------------------------------------------
    -- A capacidade NÃO é conferida aqui: quem confere é tg_bloco_aluno_admissao,
    -- e é ele quem tem a única implementação de fn_capacidade_efetiva. Bloco
    -- lotado no arquivo derruba a transação inteira e vira ocorrência com o
    -- texto do próprio trigger — que já diz quantos cabem e quantos vieram.
    insert into public.bloco_aluno (unidade_id, bloco_id, aluno_id, tipo,
                                    data_inicio_prevista)
    select v_unidade, b.id, a.id, e.j ->> 'tipo',
           public.fn_importacao_data(e.j ->> 'data_inicio_prevista')
      from jsonb_array_elements(v_d -> 'bloco_aluno') e(j)
      join public.aluno a on a.unidade_id = v_unidade
                         and a.codigo_sgf = btrim(e.j ->> 'aluno')
      join public.sala s  on s.unidade_id = v_unidade and s.nome = btrim(e.j ->> 'sala')
      join public.bloco_horario b
             on b.unidade_id = v_unidade and b.sala_id = s.id
            and b.dia_semana = public.fn_importacao_int(e.j ->> 'dia_semana')::smallint
            and b.hora_inicio = public.fn_importacao_hora(e.j ->> 'hora_inicio')
     where coalesce(e.j ->> 'ativo', 'true') <> 'false'
        on conflict (bloco_id, aluno_id) where ativo do update
       set tipo = excluded.tipo,
           data_inicio_prevista = excluded.data_inicio_prevista;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'bloco_aluno',
                  jsonb_array_length(v_d -> 'bloco_aluno'), v_n);

    -- 14. turma_modular -------------------------------------------------------
    insert into public.turma_modular (unidade_id, curso_id, nome, sala_id,
                                      capacidade, data_inicio, ativo)
    select v_unidade, c.id, btrim(e.j ->> 'nome'), s.id,
           public.fn_importacao_int(e.j ->> 'capacidade'),
           coalesce(public.fn_importacao_data(e.j ->> 'data_inicio'), public.fn_hoje()),
           coalesce(e.j ->> 'ativo', 'true') <> 'false'
      from jsonb_array_elements(v_d -> 'turma_modular') e(j)
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
      join public.curso c   on c.unidade_id = v_unidade and c.metodo_id = mo.id
                           and c.nome = btrim(e.j ->> 'curso')
      join public.sala s    on s.unidade_id = v_unidade and s.nome = btrim(e.j ->> 'sala')
        on conflict (unidade_id, nome) do update
       set curso_id = excluded.curso_id,
           sala_id = excluded.sala_id,
           capacidade = excluded.capacidade,
           data_inicio = excluded.data_inicio,
           ativo = excluded.ativo;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'turma_modular',
                  jsonb_array_length(v_d -> 'turma_modular'), v_n);

    -- 15. turma_modular_modulo ------------------------------------------------
    insert into public.turma_modular_modulo (unidade_id, turma_id, modulo_id,
                                             data_inicio, prev_conclusao, concluido)
    select v_unidade, t.id, md.id,
           public.fn_importacao_data(e.j ->> 'data_inicio'),
           public.fn_importacao_data(e.j ->> 'prev_conclusao'),
           coalesce(e.j ->> 'concluido', 'false') = 'true'
      from jsonb_array_elements(v_d -> 'turma_modular_modulo') e(j)
      join public.turma_modular t on t.unidade_id = v_unidade
                                 and t.nome = btrim(e.j ->> 'turma')
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
      join public.curso c   on c.unidade_id = v_unidade and c.metodo_id = mo.id
                           and c.nome = btrim(e.j ->> 'curso')
      join public.modulo md on md.curso_id = c.id
                           and md.ordem = public.fn_importacao_int(e.j ->> 'modulo_ordem')
        on conflict (turma_id, modulo_id, ciclo) do update
       set data_inicio = excluded.data_inicio,
           prev_conclusao = excluded.prev_conclusao,
           concluido = excluded.concluido;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'turma_modular_modulo',
                  jsonb_array_length(v_d -> 'turma_modular_modulo'), v_n);

    -- 16. turma_modular_aluno -------------------------------------------------
    insert into public.turma_modular_aluno (unidade_id, turma_id, aluno_id, data_entrada)
    select v_unidade, t.id, a.id,
           coalesce(public.fn_importacao_data(e.j ->> 'data_entrada'), public.fn_hoje())
      from jsonb_array_elements(v_d -> 'turma_modular_aluno') e(j)
      join public.turma_modular t on t.unidade_id = v_unidade
                                 and t.nome = btrim(e.j ->> 'turma')
      join public.aluno a on a.unidade_id = v_unidade
                        and a.codigo_sgf = btrim(e.j ->> 'aluno')
     where coalesce(e.j ->> 'ativo', 'true') <> 'false'
        on conflict (turma_id, aluno_id) where ativo do update
       set data_entrada = excluded.data_entrada;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'turma_modular_aluno',
                  jsonb_array_length(v_d -> 'turma_modular_aluno'), v_n);

    -- 17. aluno_material ------------------------------------------------------
    -- ⚠️ A trilha do aluno com combo JÁ NASCEU no passo 11: tg_aluno_trilha_inicial
    --    chama fn_trilha_gerar no insert do aluno. O que o arquivo traz aqui é o
    --    ESTADO DE ENTREGA dessas linhas (e as manuais que a planilha tiver), e é
    --    por isso que este passo é um `update` na maioria das vezes. Regerar a
    --    trilha aqui seria a segunda implementação de combo → curso → material.
    insert into public.aluno_material (unidade_id, aluno_id, material_id, ordem,
                                       origem, entregue, data_entrega)
    select v_unidade, a.id, m.id, public.fn_importacao_int(e.j ->> 'ordem'),
           coalesce(e.j ->> 'origem', 'COMBO'),
           coalesce(e.j ->> 'entregue', 'false') = 'true',
           case when coalesce(e.j ->> 'entregue', 'false') = 'true'
                then coalesce(public.fn_importacao_data(e.j ->> 'data_entrega'),
                              public.fn_hoje())
                else null end
      from jsonb_array_elements(v_d -> 'aluno_material') e(j)
      join public.aluno a   on a.unidade_id = v_unidade
                          and a.codigo_sgf = btrim(e.j ->> 'aluno')
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
      join public.material m on m.unidade_id = v_unidade and m.metodo_id = mo.id
                            and m.codigo = btrim(e.j ->> 'material')
        on conflict (aluno_id, material_id) do update
       set ordem = excluded.ordem,
           origem = excluded.origem,
           entregue = excluded.entregue,
           data_entrega = excluded.data_entrega;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'aluno_material',
                  jsonb_array_length(v_d -> 'aluno_material'), v_n);

    -- 18. movimento_estoque ---------------------------------------------------
    -- A única entidade sem chave natural, e a única IMUTÁVEL: importar duas vezes
    -- não se corrige com update, só com estorno. Daí o mapa importacao_referencia
    -- e o `id` gerado no SELECT — é o que permite gravar chave → linha sem
    -- precisar que o `returning` devolva uma coluna que a tabela não tem.
    with novos as (
      select gen_random_uuid() as id,
             btrim(e.j ->> 'chave') as chave,
             e.j as item
        from jsonb_array_elements(v_d -> 'movimento_estoque') e(j)
       where not exists (
             select 1 from public.importacao_referencia r
              where r.unidade_id = v_unidade
                and r.entidade = 'movimento_estoque'
                and r.chave_externa = btrim(e.j ->> 'chave'))
    ),
    gravados as (
      insert into public.movimento_estoque (id, unidade_id, material_id, tipo,
                                            quantidade, ocorrido_em, aluno_id, observacao)
      select n.id, v_unidade, m.id, n.item ->> 'tipo',
             public.fn_importacao_int(n.item ->> 'quantidade'),
             coalesce(public.fn_importacao_data(n.item ->> 'ocorrido_em'),
                      public.fn_hoje())::timestamptz,
             a.id, n.item ->> 'observacao'
        from novos n
        join public.metodo mo on mo.unidade_id = v_unidade
                             and mo.codigo = n.item ->> 'metodo'
        join public.material m on m.unidade_id = v_unidade and m.metodo_id = mo.id
                              and m.codigo = btrim(n.item ->> 'material')
        left join public.aluno a on a.unidade_id = v_unidade
                                and a.codigo_sgf = nullif(btrim(coalesce(n.item ->> 'aluno', '')), '')
      returning id
    )
    insert into public.importacao_referencia (unidade_id, entidade, chave_externa, registro_id)
    select v_unidade, 'movimento_estoque', n.chave, n.id
      from novos n
     where n.id in (select id from gravados);
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'movimento_estoque',
                  jsonb_array_length(v_d -> 'movimento_estoque'), v_n);

    -- O número que se compara com o Dashboard da planilha (card 9.4). Vem depois
    -- de tudo escrito, e conta o que EXISTE — não o que este lote aplicou.
    v_totais := v_totais || jsonb_build_object('no_sistema', jsonb_build_object(
      'professor',           (select count(*) from public.professor           where unidade_id = v_unidade),
      'sala',                (select count(*) from public.sala                where unidade_id = v_unidade),
      'pc',                  (select count(*) from public.pc                  where unidade_id = v_unidade),
      'pc_manutencao',       (select count(*) from public.pc_manutencao       where unidade_id = v_unidade),
      'material',            (select count(*) from public.material            where unidade_id = v_unidade),
      'curso',               (select count(*) from public.curso               where unidade_id = v_unidade),
      'curso_material',      (select count(*) from public.curso_material      where unidade_id = v_unidade),
      'modulo',              (select count(*) from public.modulo              where unidade_id = v_unidade),
      'combo',               (select count(*) from public.combo               where unidade_id = v_unidade),
      'combo_curso',         (select count(*) from public.combo_curso         where unidade_id = v_unidade),
      'aluno',               (select count(*) from public.aluno               where unidade_id = v_unidade),
      'bloco_horario',       (select count(*) from public.bloco_horario       where unidade_id = v_unidade),
      'bloco_aluno',         (select count(*) from public.bloco_aluno         where unidade_id = v_unidade and ativo),
      'turma_modular',       (select count(*) from public.turma_modular       where unidade_id = v_unidade),
      'turma_modular_modulo',(select count(*) from public.turma_modular_modulo where unidade_id = v_unidade),
      'turma_modular_aluno', (select count(*) from public.turma_modular_aluno where unidade_id = v_unidade and ativo),
      'aluno_material',      (select count(*) from public.aluno_material      where unidade_id = v_unidade),
      'movimento_estoque',   (select count(*) from public.movimento_estoque   where unidade_id = v_unidade)));

    if p_simular then
      -- Não é erro: é o único jeito de desfazer o que a subtransação escreveu
      -- levando o resultado junto. O `detail` volta no handler abaixo.
      raise exception using
        errcode = 'PT299',
        message = 'simulação concluída',
        detail  = v_totais::text;
    end if;

  exception
    when sqlstate 'PT299' then
      get stacked diagnostics v_detalhe = pg_exception_detail;
      v_totais := v_detalhe::jsonb;
      v_estado := 'SIMULADA';

    when others then
      get stacked diagnostics v_estado  = returned_sqlstate,
                              v_msg     = message_text,
                              v_detalhe = pg_exception_detail;
      -- O `codigo` do DETAIL é o contrato do card 2.2 §12; nem todo erro tem um
      -- (violação de check vem sem), e aí fica o SQLSTATE, que é o que se manda
      -- ao suporte.
      begin
        v_codigo := coalesce(v_detalhe::jsonb ->> 'codigo', v_estado);
      exception when others then
        v_codigo := v_estado;
      end;
      v_estado := 'FALHOU';
  end;

  if v_estado = 'FALHOU' then
    insert into public.importacao_ocorrencia
           (unidade_id, importacao_id, severidade, entidade, codigo, mensagem, valor)
    values (v_unidade, p_importacao_id, 'ERRO', 'importacao', v_codigo,
            format('O banco recusou uma linha e a importação inteira foi desfeita: %s', v_msg),
            v_detalhe);

    update public.importacao i
       set status = 'FALHOU'
     where i.id = p_importacao_id;

    return jsonb_build_object('status', 'FALHOU', 'codigo', v_codigo,
                              'mensagem', v_msg);
  end if;

  if p_simular then
    update public.importacao i
       set simulado_em = now(), totais = v_totais
     where i.id = p_importacao_id;
    return jsonb_build_object('status', 'SIMULADA', 'totais', v_totais);
  end if;

  update public.importacao i
     set status = 'APLICADA',
         totais = v_totais,
         aplicado_em = now(),
         aplicado_por = (select u.id from public.usuario u where u.id = auth.uid())
   where i.id = p_importacao_id;

  return jsonb_build_object('status', 'APLICADA', 'totais', v_totais);
end $$;

