-- =============================================================================
-- Card 7.2 — Regras Modular: avanço conjunto de módulo, admissão com capacidade
--            de turma e a trilha modular
-- Fonte: docs/regras-negocio-funcoes.md §9 (as cinco assinaturas) e §4.5 (o
--        advisory lock), docs/modelagem-dados-ddl.md §9, docs/views-leitura.md
--        §7.2 (o módulo corrente por `modulo.ordem`) e docs/projecao-demanda.md
--        §5.4 (o passo planejado, que este card grava e o card 8.1 lê).
--
-- Entrega, na ordem das camadas do card 2.2 §1:
--   • camada 2 — `tg_turma_modular_aluno_admissao`, que vale para o POST direto
--     no PostgREST: aluno ATIVO/ACELERAR, método MODULAR, método do curso da
--     turma igual ao do aluno e vaga livre (`TURMA_LOTADA`);
--   • camada 3 — `fn_turma_modular_admitir` / `fn_turma_modular_remover`, com o
--     `pg_advisory_xact_lock` do §4.5 e a reativação em vez de duplicata;
--   • as duas derivadas — `fn_turma_modular_ocupacao` e
--     `fn_turma_modular_modulo_corrente`;
--   • `fn_turma_modular_avancar`, o avanço CONJUNTO do §9.
--
-- O que este card NÃO traz, e onde está escrito que não é esquecimento:
--   • `ALUNO_SEM_TURMA` para o aluno Modular sem turma já foi entregue pelo
--     card 7.1 (`20260905040000_turmas_modular.sql` §9), no dia em que
--     `turma_modular_aluno` nasceu e o portão do teste 090 venceu. A nota do 7.2
--     no board a pede porque foi escrita antes; ela está feita e MEDIDA no 070;
--   • `v_turma_modular_lotacao` é do card 7.4 (docs/views-leitura.md §7.2);
--   • a tela por curso é do card 7.3;
--   • a projeção Modular é do card 8.1 e lê `turma_modular_modulo` direto
--     (docs/projecao-demanda.md §5.4) — não há função a expor aqui.
--
-- ⚠️ ESTRUTURA, REGRA E MAIS NADA. Nenhuma linha de dado de negócio: decisão de
--    02/09/2026 e portão do card 4.0,5 (portao-migracoes/varredor.mjs).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. `motivo_saida` em turma_modular_aluno — divergência REGISTRADA do card 7.1
-- -----------------------------------------------------------------------------
-- O card 7.1 deixou escrito que não criaria esta coluna: «o DDL §9 não a prevê
-- aqui e inventá-la neste card seria escopo que ninguém pediu; quando a tela do
-- 7.3 precisar da frase, ela é um card». A decisão estava certa PARA AQUELE CARD
-- — e é este que a torna devida, não o 7.3.
--
-- A razão é a assinatura, que é contrato do card 2.2 §9 e não escolha deste
-- arquivo: `fn_turma_modular_remover(p_turma_id, p_aluno_id, p_motivo text)`.
-- Sem a coluna, `p_motivo` seria um parâmetro que a função aceita e joga fora —
-- a tela do 7.3 pediria o motivo da saída, a pessoa digitaria, e nada seria
-- gravado em lugar nenhum. Parâmetro que não vai a lugar algum é pior do que
-- parâmetro inexistente: ele documenta uma garantia que o sistema não dá.
--
-- É a mesma coluna de `bloco_aluno` (card 5.3), com a mesma semântica e escrita
-- pelos mesmos dois atores: `fn_turma_modular_remover` (o motivo informado por
-- quem removeu) e `tg_aluno_status_desaloca` (o status que o tirou dali).
-- Reverter é `alter table ... drop column`, e é por isso que a divergência sai
-- barata nesta direção e cara na outra.
alter table public.turma_modular_aluno
  add column motivo_saida text;

comment on column public.turma_modular_aluno.motivo_saida is
  'Por que o aluno saiu da turma Modular. Escrita por fn_turma_modular_remover (motivo informado por quem removeu) e por tg_aluno_status_desaloca (o status que o tirou dali); limpa por fn_turma_modular_admitir ao reativar. Espelha bloco_aluno.motivo_saida (card 5.3) — sem ela o p_motivo da assinatura do card 2.2 §9 seria decoração.';

-- A coluna fica FORA da lista de `tg_turma_modular_aluno_colunas_permitidas`
-- (card 7.1 §6), e a ausência é a decisão: `motivo_saida` é escrita na MESMA
-- operação que `ativo`, inclusive pela desalocação sem ator. Exigir
-- `turmas.alocar` para ela faria o pedagógico trancar um aluno e a transação
-- morrer com SEM_PERMISSAO numa tela que não fala de turma — exatamente o erro
-- opaco que o `or` da política de update existe para evitar.

-- -----------------------------------------------------------------------------
-- 2. As duas derivadas (§9)
-- -----------------------------------------------------------------------------
-- ⚠️ `security definer`, e é a mesma razão de `fn_ocupacao_bloco` (card 5.2):
--    número derivado que decide LOTAÇÃO não pode depender do que o leitor
--    enxerga. Como `invoker`, um chamador sem `turmas.ler` contaria ZERO alunos
--    numa turma cheia — e a RLS nega linha em vez de devolver erro (card 2.3
--    §3.4), então a admissão passaria em silêncio numa turma lotada. Aqui o
--    silêncio é fail-OPEN, que é o pior dos dois lados.
--
--    Filtra a unidade no corpo e devolve NULO — não zero — para turma de outra
--    unidade, como manda a correção do card 2.3 e como faz `fn_ocupacao_bloco`.
--    Nulo aqui é erro, não "sem opinião": é o que a seção 3 transforma em
--    TURMA_INEXISTENTE.
create or replace function public.fn_turma_modular_ocupacao(p_turma_id uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select (select count(*)::integer
            from public.turma_modular_aluno ta
           where ta.turma_id = t.id
             and ta.ativo)
    from public.turma_modular t
   where t.id = p_turma_id
     and t.unidade_id = public.fn_unidade_atual();
$$;

comment on function public.fn_turma_modular_ocupacao(uuid) is
  'Quantos alunos ATIVOS a turma Modular tem. NULO quando a turma não é da unidade corrente; 0 é turma vazia de verdade. security definer pela mesma razão de fn_ocupacao_bloco (card 5.2): lotação lida com a visibilidade do leitor deixaria a admissão passar numa turma cheia, sem erro nenhum.';

revoke execute on function public.fn_turma_modular_ocupacao(uuid) from public;
revoke execute on function public.fn_turma_modular_ocupacao(uuid) from anon;
grant  execute on function public.fn_turma_modular_ocupacao(uuid) to authenticated;

-- O módulo corrente é o primeiro NÃO CONCLUÍDO por `modulo.ordem` — a ordem vem
-- do catálogo e não de coluna de `turma_modular_modulo` (card 2.2 §9). Devolve o
-- `modulo_id`, o mesmo que `v_turma_modular_lotacao.modulo_corrente_id` (card
-- 7.4) expõe, para que tela e função nunca digam coisas diferentes.
--
-- NULO tem DOIS sentidos aqui, e os dois são legítimos: turma com todos os
-- módulos concluídos (o estado "turma terminou") e turma sem cronograma nenhum.
-- Quem precisa distingui-los é a seção 5, que trata os dois como fim de linha
-- para o avanço mas com mensagens diferentes.
--
-- `invoker` de propósito, ao contrário da de cima: ela não decide lotação, e
-- quem não pode ler o cronograma recebe nulo e esbarra em TURMA_SEM_MODULO —
-- fail-CLOSED. Entrar na lista fechada do C8 sem necessidade gasta a revisão
-- consciente que a lista existe para provocar (card 3.4 (a)).
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
   order by m.ordem, tm.modulo_id
   limit 1;
$$;

comment on function public.fn_turma_modular_modulo_corrente(uuid) is
  'Módulo corrente da turma Modular: o primeiro NÃO concluído por modulo.ordem (card 2.2 §9), devolvido como modulo_id. NULO quando todos foram concluídos ou quando a turma não tem cronograma. `order by` completo porque limit sem ele é sorteio (docs/estrategia-testes.md §11).';

revoke execute on function public.fn_turma_modular_modulo_corrente(uuid) from public;
revoke execute on function public.fn_turma_modular_modulo_corrente(uuid) from anon;
grant  execute on function public.fn_turma_modular_modulo_corrente(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. tg_turma_modular_aluno_admissao — a camada 2, que vale para o POST direto
-- -----------------------------------------------------------------------------
-- Com "Automatically expose new tables" ligado (pendência técnica 2), TODA
-- tabela é uma API: a função de aplicação é o caminho normal e o trigger é a
-- garantia (card 2.2 §1). Um teste que só chama `fn_turma_modular_admitir` nunca
-- descobre que o trigger não existe — é o §6.1 do card 2.8, e é por isso que o
-- teste 071 monta os dois caminhos.
--
-- Três diferenças em relação ao `tg_bloco_aluno_admissao` do card 5.3, e cada
-- uma tem motivo próprio:
--
--   (a) a capacidade é COLUNA e não conta de PC — a sala modular não tem
--       nenhum (card 7.1). Não há `fn_capacidade_efetiva` a chamar, e é por isso
--       que a turma de outra unidade se descobre pela ocupação NULA e não por
--       uma capacidade nula;
--
--   (b) o método do aluno tem de ser MODULAR, e não só igual ao do curso da
--       turma (§9: «exige aluno ATIVO/ACELERAR do método MODULAR»). As duas
--       checagens juntas cobrem o caso que uma só deixaria passar: `metodo.codigo
--       = 'MODULAR'` sozinho aceitaria a aluna numa turma cuja `curso_id` aponta
--       para um curso de Inglês (nada no schema impede a turma de nascer assim),
--       e a igualdade sozinha aceitaria uma turma Interativo inteira;
--
--   (c) não há `data_inicio_prevista` nem `tipo`: a turma Modular não tem as
--       formas do bloco de horário, e o que ela tem — o cronograma — é da turma,
--       não do aluno.
--
-- ⚠️ Limite conhecido, o mesmo do card 5.3: as leituras de `aluno`, `curso` e
--    `metodo` são `invoker`, então um perfil com `turmas.alocar` e SEM
--    `alunos.ler` recebe ALUNO_INEXISTENTE em vez de SEM_PERMISSAO. É
--    fail-closed e ALTO (a escrita não acontece e a mensagem aparece), e a
--    alternativa — mais funções `security definer` — amplia a lista fechada do
--    C8 sem necessidade (card 3.4). Nenhum perfil da matriz inicial é assim.
create or replace function public.fn_turma_modular_aluno_admissao()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_status     text;
  v_metodo_al  uuid;
  v_codigo_al  text;
  v_metodo_cur uuid;
  v_capacidade integer;
  v_ocupacao   integer;
  v_entrando   boolean;
begin
  select a.status, a.metodo_id, me.codigo
    into v_status, v_metodo_al, v_codigo_al
    from public.aluno a
    join public.metodo me on me.id = a.metodo_id
   where a.id = new.aluno_id;

  if v_status is null then
    raise exception using
      errcode = 'PT404',
      message = 'Aluno não encontrado.',
      detail  = json_build_object('codigo', 'ALUNO_INEXISTENTE',
                                  'aluno', new.aluno_id)::text;
  end if;

  if v_status not in ('ATIVO', 'ACELERAR') then
    raise exception using
      errcode = 'PT409',
      message = format('Aluno em %s não pode ocupar vaga em turma.', v_status),
      detail  = json_build_object('codigo', 'ALUNO_INATIVO',
                                  'aluno', new.aluno_id, 'status', v_status)::text;
  end if;

  if v_codigo_al <> 'MODULAR' then
    raise exception using
      errcode = 'PT422',
      message = 'Só aluno do método Modular entra em turma Modular.',
      detail  = json_build_object('codigo', 'ALUNO_NAO_MODULAR',
                                  'aluno', new.aluno_id,
                                  'metodo', v_codigo_al)::text,
      hint    = 'Alunos dos outros métodos são alocados em blocos de horário.';
  end if;

  select c.metodo_id, t.capacidade
    into v_metodo_cur, v_capacidade
    from public.turma_modular t
    join public.curso c on c.id = t.curso_id
   where t.id = new.turma_id;

  -- A ocupação é quem responde "esta turma é da minha unidade?", porque ela é a
  -- única leitura `definer` daqui: `turma_modular` é `invoker` e some por RLS
  -- antes de dizer de que unidade era.
  v_ocupacao := public.fn_turma_modular_ocupacao(new.turma_id);

  if v_metodo_cur is null or v_ocupacao is null then
    raise exception using
      errcode = 'PT404',
      message = 'Turma Modular não encontrada nesta unidade.',
      detail  = json_build_object('codigo', 'TURMA_INEXISTENTE',
                                  'turma', new.turma_id)::text;
  end if;

  if v_metodo_cur <> v_metodo_al then
    raise exception using
      errcode = 'PT422',
      message = 'O método do aluno é diferente do método do curso da turma.',
      detail  = json_build_object('codigo', 'METODO_INCOMPATIVEL',
                                  'aluno', new.aluno_id,
                                  'turma', new.turma_id)::text;
  end if;

  -- A vaga só é DISPUTADA quando a linha ENTRA na conta: insert ativo, volta de
  -- inativa para ativa, ou troca de turma. Sem esta distinção, qualquer update
  -- de linha já ativa veria a PRÓPRIA linha na contagem e responderia
  -- TURMA_LOTADA numa turma que não mudou de tamanho — é o achado do card 5.3.
  v_entrando := tg_op = 'INSERT'
                or not old.ativo
                or new.turma_id is distinct from old.turma_id;

  if v_entrando then
    -- `>=` e não `>`: a linha do BEFORE INSERT ainda não está na contagem, e a
    -- que sai de ativo = false também não estava. Nos dois casos o que se
    -- pergunta é "cabe mais um?".
    if v_ocupacao >= v_capacidade then
      raise exception using
        errcode = 'PT409',
        message = format('Turma lotada: %s de %s vagas ocupadas.',
                         v_ocupacao, v_capacidade),
        detail  = json_build_object('codigo', 'TURMA_LOTADA',
                                    'turma', new.turma_id,
                                    'capacidade', v_capacidade,
                                    'ocupacao', v_ocupacao)::text,
        hint    = 'Remova um aluno da turma ou use outra turma do curso.';
    end if;
  end if;

  return new;
end $$;

comment on function public.fn_turma_modular_aluno_admissao() is
  'Trigger BEFORE INSERT/UPDATE em turma_modular_aluno, só para linha ATIVA: aluno em ATIVO/ACELERAR (PT409/ALUNO_INATIVO), método do aluno MODULAR (PT422/ALUNO_NAO_MODULAR), método do curso da turma igual ao do aluno (PT422/METODO_INCOMPATIVEL) e vaga livre quando a linha ENTRA na conta (PT409/TURMA_LOTADA). Ocupação nula é turma de outra unidade e vira PT404/TURMA_INEXISTENTE.';

revoke execute on function public.fn_turma_modular_aluno_admissao() from public;
revoke execute on function public.fn_turma_modular_aluno_admissao() from anon;

-- `when (new.ativo)`: a saída da turma (ativo = false), inclusive a sem ator de
-- tg_aluno_status_desaloca, não passa por validação nenhuma — sair de uma turma
-- nunca pode ser recusado. É a mesma cláusula de tg_bloco_aluno_admissao, e sem
-- ela trancar um aluno morreria com ALUNO_INATIVO dentro da transação de uma
-- tela que não fala de turma.
create trigger tg_turma_modular_aluno_admissao
  before insert or update on public.turma_modular_aluno
  for each row when (new.ativo)
  execute function public.fn_turma_modular_aluno_admissao();

-- -----------------------------------------------------------------------------
-- 4. fn_turma_modular_admitir / fn_turma_modular_remover — a camada 3 (§9)
-- -----------------------------------------------------------------------------
-- O advisory lock é o §4.5 do card 2.2, que o cita nominalmente («mesmo padrão
-- em fn_turma_modular_admitir»), e a razão não é performance: duas secretarias
-- admitindo o último aluno ao mesmo tempo passam as DUAS pela checagem de
-- capacidade — em `read committed` nenhuma enxerga a linha ainda não commitada
-- da outra — e a turma de 15 fica com 16. Nenhuma constraint pega isso: é regra
-- de AGREGADO, não de linha, e a suíte pgTAP roda numa conexão só e jamais a
-- exercita (card 2.8 §7).
--
-- A chave do lock é a TURMA, e é a mesma da seção 5: admitir e avançar são as
-- duas operações que leem o estado da turma inteira antes de escrever, e
-- serializá-las com chaves diferentes seria serializar cada uma consigo mesma e
-- com mais ninguém.
create or replace function public.fn_turma_modular_admitir(
  p_turma_id uuid,
  p_aluno_id uuid
)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_id      uuid;
  v_unidade uuid;
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

  -- Reativa em vez de duplicar (card 2.2 §4.3, e o card 7.1 criou a unique
  -- PARCIAL `turma_modular_aluno_ativo_uk` exatamente para permiti-lo): nada
  -- impede uma linha inativa antiga ao lado de uma ativa, daí a escolha
  -- explícita da ativa primeiro, e `order by` completo porque `limit` sem ele é
  -- sorteio (docs/estrategia-testes.md §11).
  select ta.id into v_id
    from public.turma_modular_aluno ta
   where ta.turma_id = p_turma_id and ta.aluno_id = p_aluno_id
   order by ta.ativo desc, ta.criado_em desc, ta.id
   limit 1;

  if v_id is null then
    insert into public.turma_modular_aluno (unidade_id, turma_id, aluno_id)
    values (v_unidade, p_turma_id, p_aluno_id)
    returning id into v_id;
  else
    -- Reativar limpa o motivo da saída: ele descreve uma saída que deixou de
    -- valer, e mantê-lo faria a ficha do aluno dizer que ele saiu da turma em
    -- que está. `data_entrada` NÃO é reescrita — a data em que o aluno entrou na
    -- turma da primeira vez é o que a previsão de conclusão do módulo lê, e
    -- reescrevê-la a cada volta apagaria o histórico que a coluna existe para
    -- guardar (é também por isso que ela está na guarda de coluna do card 7.1).
    update public.turma_modular_aluno
       set ativo        = true,
           motivo_saida = null
     where id = v_id;
  end if;

  return v_id;
end $$;

comment on function public.fn_turma_modular_admitir(uuid, uuid) is
  'Admite o aluno na turma Modular e devolve o id da alocação. Exige turmas.alocar, serializa a turma com pg_advisory_xact_lock (card 2.2 §4.5) e REATIVA a alocação existente em vez de duplicar, limpando motivo_saida. As regras (aluno ativo, método MODULAR, método do curso, lotação) são do tg_turma_modular_aluno_admissao — aqui não se reescreve nenhuma.';

revoke execute on function public.fn_turma_modular_admitir(uuid, uuid) from public;
revoke execute on function public.fn_turma_modular_admitir(uuid, uuid) from anon;
grant  execute on function public.fn_turma_modular_admitir(uuid, uuid) to authenticated;

create or replace function public.fn_turma_modular_remover(
  p_turma_id uuid,
  p_aluno_id uuid,
  p_motivo   text default null
)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
begin
  perform public.fn_exige_permissao('turmas.alocar');

  update public.turma_modular_aluno
     set ativo = false, motivo_saida = p_motivo
   where turma_id = p_turma_id and aluno_id = p_aluno_id and ativo;

  -- Não encontrar nada é o caso que precisa DOER: silêncio aqui é a tela dizendo
  -- "removido" sobre uma turma em que o aluno continua, e o próximo a descobrir
  -- é quem contar as cadeiras.
  if not found then
    raise exception using
      errcode = 'PT404',
      message = 'Este aluno não está nesta turma Modular.',
      detail  = json_build_object('codigo', 'ALOCACAO_INEXISTENTE',
                                  'turma', p_turma_id, 'aluno', p_aluno_id)::text;
  end if;
end $$;

comment on function public.fn_turma_modular_remover(uuid, uuid, text) is
  'Tira o aluno da turma Modular (saída é ativo = false, card 2.4 §4 — a tabela não tem política de delete) e grava o motivo em motivo_saida. Exige turmas.alocar; PT404/ALOCACAO_INEXISTENTE quando não há alocação ativa.';

revoke execute on function public.fn_turma_modular_remover(uuid, uuid, text) from public;
revoke execute on function public.fn_turma_modular_remover(uuid, uuid, text) from anon;
grant  execute on function public.fn_turma_modular_remover(uuid, uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. fn_turma_modular_avancar — o avanço CONJUNTO (§9)
-- -----------------------------------------------------------------------------
-- «A turma avança em conjunto — não existe avanço por aluno» (card 2.2 §9). É
-- por isso que esta função recebe a TURMA e não o par turma+aluno, e é por isso
-- que ela não toca em `turma_modular_aluno`: quem está na turma no dia do avanço
-- avançou, e quem entrar depois entra no módulo corrente.
--
-- ⚠️ DIVERGÊNCIA REGISTRADA da assinatura do §9, que escreve
--    `p_data_conclusao date default current_date`. Vale `public.fn_hoje()`, pelo
--    ajuste 2 do §10 do card 2.3: o Postgres do Supabase roda em UTC e das 21h à
--    meia-noite `current_date` já é o dia seguinte — um avanço lançado à noite
--    concluiria o módulo com a data de amanhã e deslocaria o cronograma inteiro
--    em um dia, silenciosamente. Não é preferência: o teste C6 do 011 varre
--    `proargdefaults` desde o card 5.2 e reprovaria a suíte com `current_date`
--    aqui. A assinatura de tipos — `(uuid, date)` — é a do §9, palavra por
--    palavra.
--
-- O que acontece, na ordem, e por que a ordem importa:
--
--   1. o módulo corrente é marcado `concluido` e sua `prev_conclusao` recebe a
--      data REAL da conclusão. Não há coluna `data_conclusao` no DDL §9, e
--      inventá-la seria escopo que ninguém pediu — mas há um lugar em que a data
--      real é exatamente o que o resto do sistema quer ler: a regra 2 do §5.4 de
--      docs/projecao-demanda.md lê «`prev_conclusao` do módulo anterior + 1 dia»
--      para saber quando o próximo módulo começa. Gravar ali a data real faz o
--      cronograma se corrigir sozinho a cada avanço, em vez de projetar o resto
--      da turma sobre uma previsão que já se sabe errada;
--
--   2. só DEPOIS disso o passo planejado é calculado, e a ordem é a decisão:
--      incluindo o módulo recém-concluído, a média aprende com a duração REAL do
--      que acabou de acontecer. Calculá-lo antes usaria a previsão que a turma
--      acabou de desmentir;
--
--   3. o próximo módulo (por `modulo.ordem`) abre com `data_inicio` no dia
--      seguinte e `prev_conclusao = data_inicio + passo - 1`. As datas já
--      informadas na tela do card 7.3 são PRESERVADAS: `coalesce` em cima do que
--      já existe, porque uma previsão digitada por quem conhece a turma vale
--      mais que uma média, e sobrescrevê-la faria o avanço apagar em silêncio o
--      trabalho de quem montou o cronograma.
--
-- `passo`: a duração média planejada dos módulos DATADOS da turma
-- (`prev_conclusao - data_inicio + 1`), ou `ritmo_padrao_dias_MODULAR` quando
-- nenhum módulo tem as duas datas. É literalmente o `passo_turma` do §5.4 da
-- projeção, e ser a mesma expressão é o ponto: o card 8.1 extrapola o resto do
-- cronograma com ela, e duas definições do mesmo passo divergiriam na primeira
-- vez que alguém mexesse numa só.
--
-- `turmas.editar` e não `turmas.alocar`: o catálogo do card 2.4 §3.4 descreve
-- `turmas.editar` como «cronograma e avanço de módulo», com todas as letras.
create or replace function public.fn_turma_modular_avancar(
  p_turma_id       uuid,
  p_data_conclusao date default public.fn_hoje()
)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade  uuid;
  v_corrente uuid;
  v_proximo  uuid;
  v_passo    integer;
  v_tem_crono boolean;
begin
  perform public.fn_exige_permissao('turmas.editar');

  if p_data_conclusao is null then
    raise exception using
      errcode = 'PT422',
      message = 'A data de conclusão do módulo é obrigatória.',
      detail  = json_build_object('codigo', 'DATA_OBRIGATORIA',
                                  'turma', p_turma_id)::text;
  end if;

  -- Mesma chave da seção 4: dois avanços simultâneos leriam o mesmo módulo
  -- corrente e concluiriam o mesmo módulo duas vezes, pulando um.
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

  v_corrente := public.fn_turma_modular_modulo_corrente(p_turma_id);

  if v_corrente is null then
    -- Os dois sentidos do nulo (seção 2) viram mensagens diferentes: dizer
    -- "todos os módulos já foram concluídos" a quem nunca montou o cronograma
    -- manda a pessoa procurar o erro no lugar errado.
    select exists (select 1 from public.turma_modular_modulo tm
                    where tm.turma_id = p_turma_id)
      into v_tem_crono;

    if v_tem_crono then
      raise exception using
        errcode = 'PT409',
        message = 'Todos os módulos desta turma já foram concluídos.',
        detail  = json_build_object('codigo', 'TURMA_SEM_MODULO_CORRENTE',
                                    'turma', p_turma_id)::text,
        hint    = 'Desative a turma ou acrescente módulos ao cronograma.';
    end if;

    raise exception using
      errcode = 'PT422',
      message = 'Esta turma não tem cronograma de módulos.',
      detail  = json_build_object('codigo', 'TURMA_SEM_CRONOGRAMA',
                                  'turma', p_turma_id)::text,
      hint    = 'Monte o cronograma da turma antes de avançar o módulo.';
  end if;

  -- 1. conclui o corrente, gravando a data REAL onde a projeção a lê
  update public.turma_modular_modulo
     set concluido      = true,
         prev_conclusao = p_data_conclusao
   where turma_id = p_turma_id and modulo_id = v_corrente;

  -- 2. o passo, já com a duração real do módulo que acabou de fechar
  select coalesce(round(avg(tm.prev_conclusao - tm.data_inicio + 1))::integer,
                  public.fn_param_int('ritmo_padrao_dias_MODULAR', 45))
    into v_passo
    from public.turma_modular_modulo tm
   where tm.turma_id = p_turma_id
     and tm.data_inicio is not null
     and tm.prev_conclusao is not null;

  -- Passo não positivo é cronograma incoerente (um módulo que termina antes de
  -- começar). Cair para o parâmetro é melhor que gravar uma previsão anterior ao
  -- início do próprio módulo, que é o que `data_inicio + passo - 1` daria.
  if v_passo is null or v_passo < 1 then
    v_passo := public.fn_param_int('ritmo_padrao_dias_MODULAR', 45);
  end if;

  v_proximo := public.fn_turma_modular_modulo_corrente(p_turma_id);

  -- 3. abre o próximo, PRESERVANDO o que a tela do 7.3 já tiver informado
  if v_proximo is not null then
    update public.turma_modular_modulo tm
       set data_inicio    = coalesce(tm.data_inicio, p_data_conclusao + 1),
           prev_conclusao = coalesce(tm.prev_conclusao,
                                     coalesce(tm.data_inicio, p_data_conclusao + 1)
                                       + v_passo - 1)
     where tm.turma_id = p_turma_id and tm.modulo_id = v_proximo;
  end if;

  return v_proximo;
end $$;

comment on function public.fn_turma_modular_avancar(uuid, date) is
  'Avança a turma Modular INTEIRA de módulo (card 2.2 §9): conclui o corrente gravando a data real em prev_conclusao — que é de onde docs/projecao-demanda.md §5.4 tira o início do próximo — e abre o seguinte por modulo.ordem, com prev_conclusao = data_inicio + passo - 1. Preserva as datas já informadas na tela do 7.3. Devolve o modulo_id do novo corrente, ou NULO quando a turma terminou. Exige turmas.editar.';

revoke execute on function public.fn_turma_modular_avancar(uuid, date) from public;
revoke execute on function public.fn_turma_modular_avancar(uuid, date) from anon;
grant  execute on function public.fn_turma_modular_avancar(uuid, date) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. tg_aluno_status_desaloca — o motivo da saída, agora nas TRÊS tabelas
-- -----------------------------------------------------------------------------
-- ⚠️ `create or replace` de função inteira parte da ÚLTIMA definição APLICADA,
--    não da do card que a criou (lição do card 5.7). A última é a do card 7.1
--    (`20260905040000_turmas_modular.sql` §8), que acrescentou o `update` em
--    `turma_modular_aluno` — e ela está preservada abaixo palavra por palavra. A
--    única mudança é o `motivo_saida` desse `update`, que a coluna da seção 1
--    passou a permitir.
--
-- A frase é a MESMA de `bloco_aluno` de propósito: a ficha do aluno mostra as
-- duas saídas lado a lado, e duas redações para o mesmo fato fariam a pessoa
-- procurar diferença onde não há.
create or replace function public.fn_aluno_status_desaloca()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.status in ('ATIVO', 'ACELERAR') then
    return null;
  end if;

  update public.bloco_aluno
     set ativo = false,
         motivo_saida = format('Aluno passou a %s', new.status)
   where aluno_id = new.id and ativo;

  update public.turma_modular_aluno
     set ativo = false,
         motivo_saida = format('Aluno passou a %s', new.status)
   where aluno_id = new.id and ativo;

  update public.bloco_aluno_reposicao
     set status = 'CANCELADA'
   where aluno_id = new.id
     and status = 'PREVISTA'
     and data >= public.fn_hoje();

  return null;
end $$;

comment on function public.fn_aluno_status_desaloca() is
  'Trigger AFTER UPDATE OF status em aluno: quem deixa de ser ATIVO/ACELERAR sai dos blocos e das turmas Modular (ativo = false, com o motivo em motivo_saida nas duas) e tem as reposições FUTURAS canceladas — as TRÊS tabelas do card 2.2 §3.2. Voltar a ATIVO não realoca: a vaga pode já ter sido dada a outro.';

revoke execute on function public.fn_aluno_status_desaloca() from public;
revoke execute on function public.fn_aluno_status_desaloca() from anon;

-- -----------------------------------------------------------------------------
-- 7. TURMA_MODULAR_SEM_CRONOGRAMA no `check` de pendencia.tipo
-- -----------------------------------------------------------------------------
-- ⚠️ ACHADO DESTE CARD, e o tipo de achado que o §5 do card 2.8 diz ser o mais
--    caro do projeto: uma função grava um valor que o `check` da tabela não
--    aceita, dentro de uma rotina, e o sintoma é uma `ROTINA_FALHOU` às 03:10 da
--    manhã com a projeção de demanda simplesmente deixando de existir.
--
-- O ajuste 3 do §17 de docs/estrategia-testes.md atribui este tipo ao card 5.5 e
-- o marca como BLOQUEANTE; o card 7.1 escreveu, em comentário, que ele «já está
-- no check de pendencia.tipo desde o card 5.5»; e a nota do card 8.1 no board o
-- lista como pré-condição resolvida. As três afirmações estão erradas: o `check`
-- de `20260903234500_pendencias_rotinas.sql` tem quinze tipos e nenhum deles é
-- este. Ninguém mediu porque quem abre a pendência é a rotina do 8.1, que ainda
-- não existe — e no dia em que existisse, o erro apareceria longe da causa.
--
-- Entra aqui, e não num card próprio, por duas razões: é uma pendência do
-- Modular (docs/projecao-demanda.md §7.5 — turma Modular sem cronograma datado),
-- e são três linhas com uma asserção de catálogo que a mede. O `check` inline do
-- card 5.5 nasceu sem nome explícito, então o nome é o que o Postgres deu.
alter table public.pendencia drop constraint pendencia_tipo_check;

alter table public.pendencia add constraint pendencia_tipo_check check (tipo in (
  -- card 5.5, os três tipos do título
  'ALUNO_SEM_TURMA','BLOCO_ACIMA_CAPACIDADE','ACELERAR_SEM_2O_BLOCO',
  -- card 2.5 §6, aberto e fechado por rt_rep_avaliar
  'REP_VIRADA',
  -- card 2.2 §11: a falha de uma rt_* não pode sumir com o log de 1 dia
  'ROTINA_FALHOU',
  -- card 5.4 (fn_revalidar_blocos_sala)
  'PC_SEM_SUBSTITUTO',
  -- fase 6 (fn_registrar_entrega, tg_movimento_resolve_pendencia,
  -- tg_aluno_combo_alterado, fn_estornar_entrega)
  'COMPRA_SEM_ESTOQUE','ESTOQUE_ZERO','ESTOQUE_ABAIXO_MINIMO',
  'TRILHA_DIVERGENTE_COMBO','CERTIFICADO_INCONSISTENTE',
  -- fase 7 (este card): ajuste 3 do §17, que o card 5.5 não aplicou.
  -- Quem a abre é rt_projecao_demanda (card 8.1, docs/projecao-demanda.md §7.5)
  'TURMA_MODULAR_SEM_CRONOGRAMA',
  -- fase 8 (rt_pendencias_diaria cresce, tg_certificado_*)
  'STANDBY_PROLONGADO','PREVISAO_VENCIDA','ALUNO_ULTIMO_LIVRO',
  'SUGERIR_FORMADO'));
