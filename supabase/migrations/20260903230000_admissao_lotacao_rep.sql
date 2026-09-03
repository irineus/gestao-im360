-- =============================================================================
-- Card 5.3 — Regras de admissão (bloqueio se lotado), remoção de turmas ao
--            mudar status e a execução da virada REP pontual → contínuo
-- Fonte: docs/regras-negocio-funcoes.md §4.3, §4.4 e §4.5 (advisory lock),
--        docs/regra-virada-rep.md §5 (funções) e §8 (ajustes 6 e 7),
--        docs/permissoes-matriz.md §3.4 (domínio `turmas`),
--        docs/estrategia-testes.md §6.1 (camada 2), §6.5 (as duas bordas) e §7.
--
-- Entrega: as duas camadas da admissão — os triggers-garantia
--          (tg_bloco_aluno_admissao, tg_reposicao_admissao) e as funções de
--          aplicação (fn_bloco_admitir/remover, fn_reposicao_agendar/registrar/
--          cancelar) — mais o tipo tp_rep_situacao e as quatro funções da
--          virada REP (fn_rep_situacao, fn_rep_avaliar_virada,
--          fn_rep_virar_continuo, fn_rep_voltar_pontual).
--
-- ⚠️ ESTRUTURA E MAIS NADA. Só função, trigger e UMA coluna nova; nenhuma linha
--    de dado de negócio. O portão do card 4.0,5 (portao-migracoes/varredor.mjs)
--    segue as chamadas transitivamente e confirma.
--
-- O que este card NÃO recria, e onde está escrito que não é esquecimento:
--   • fn_capacidade_efetiva, fn_ocupacao_bloco e fn_vagas_livres JÁ EXISTEM
--     desde o card 5.2 (20260903210000_capacidade_vagas.sql). O mapa §13 do
--     card 2.2 punha as duas últimas aqui; a divergência foi resolvida lá e as
--     Notas deste card corrigidas. Este arquivo as CONSOME;
--   • tg_aluno_status_desaloca nasceu no card 5.1, cobrado pelo portão do teste
--     030 no dia em que `bloco_aluno` nasceu. Aqui ele só ganha o motivo da
--     saída (seção 3);
--   • tg_pc_manutencao_status e fn_revalidar_blocos_sala são do card 5.4;
--   • `pendencia`, fn_pendencia_abrir/resolver e rt_rep_avaliar são do card 5.5
--     — a virada é SUGERIDA por pendência e EXECUTADA por uma pessoa (card 2.5
--     §1), e é a metade "executada" que cabe aqui. O passo 4 do §5.2 do card 2.5
--     (fechar a pendência) fica com um PORTÃO no teste 085, que reprova no dia
--     em que `pendencia` nascer e fn_rep_virar_continuo não a citar.
--
-- Quatro códigos de erro novos (contrato de 28 → 32, test/fixtures/codigos_erro.txt):
--   BLOCO_INEXISTENTE, ALOCACAO_INEXISTENTE, REPOSICAO_INEXISTENTE e
--   REPOSICAO_NAO_PREVISTA — todos pelo precedente de PC_INEXISTENTE (card 2.9)
--   e ALUNO_INEXISTENTE (card 4.2): a alternativa é a operação não fazer nada e
--   não dizer nada, que é a família de falhas que este projeto cataloga.
--   REP_JA_CONTINUO e REP_NAO_CONTINUO já estavam no contrato desde o card 2.5.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. bloco_aluno.motivo_saida — o parâmetro que duas especificações mandam ter
-- -----------------------------------------------------------------------------
-- `fn_bloco_remover(bloco, aluno, p_motivo)` é assinatura do card 2.2 §4.3, e o
-- card 2.5 §5.2 manda `fn_rep_voltar_pontual` EXIGIR motivo (PT422 /
-- MOTIVO_OBRIGATORIO) e repassá-lo. Só que não havia coluna nenhuma onde
-- gravá-lo: o motivo entrava pela porta e sumia. Exigir do usuário um dado que
-- se descarta é pior do que não pedir — e "por que este aluno saiu da turma" é
-- justamente o que alguém pergunta três meses depois (o mesmo argumento que o
-- §14 (#4) do card 2.2 usou para `aluno_material_hist.observacao`).
--
-- Coluna e não tabela de histórico: `bloco_aluno` não tem `delete` para ninguém
-- (card 2.4 §4) e a linha sobrevive à saída com `ativo = false`, então ela mesma
-- é o registro. Uma tabela de histórico de alocação seria o desenho certo se a
-- mesma alocação pudesse sair e voltar muitas vezes; hoje `fn_bloco_admitir`
-- reativa a linha e limpa o motivo, e o caso de dois ciclos é raro o bastante
-- para não pagar uma tabela — decisão registrada, não esquecimento.
alter table public.bloco_aluno add column motivo_saida text;

comment on column public.bloco_aluno.motivo_saida is
  'Por que o aluno saiu do bloco. Escrita por fn_bloco_remover (motivo informado por quem removeu) e por tg_aluno_status_desaloca (o status que o tirou dali); limpa por fn_bloco_admitir ao reativar. Sem ela o p_motivo de fn_bloco_remover e o MOTIVO_OBRIGATORIO de fn_rep_voltar_pontual seriam decoração.';

-- -----------------------------------------------------------------------------
-- 2. tp_rep_situacao — ajuste 6 do §8 do card 2.5
-- -----------------------------------------------------------------------------
-- A pendência (card 5.5) e a tela (5.7/5.8) precisam dizer POR QUÊ: "3 aulas em
-- aberto, a mais antiga de 12/09, prazo até 12/10, cabem 2" é acionável;
-- "sugerido virar contínuo" não é. É por isso que o veredito sozinho não basta.
create type public.tp_rep_situacao as (
  debito           integer,
  aula_mais_antiga date,
  prazo_final      date,
  semanas_uteis    integer,
  capacidade       integer,
  faltas_recentes  integer,
  rep_desde        date,
  veredito         text     -- MANTER | SUGERIR_CONTINUO | SUGERIR_VOLTA
);

comment on type public.tp_rep_situacao is
  'Retorno de fn_rep_situacao: os números do critério do card 2.5 §3 mais o veredito. Segundo tipo composto do projeto, ao lado de tp_entrega_resultado (card 6.3).';

-- -----------------------------------------------------------------------------
-- 3. fn_rep_situacao — o critério do card 2.5 §3, em uma consulta
-- -----------------------------------------------------------------------------
-- `stable` e `security invoker` (card 2.5 §5.1): enxerga pela RLS de quem chama,
-- e pelo contexto de rotina quando quem chama é a rt_rep_avaliar do card 5.5.
--
-- ⚠️ `fn_exige_permissao('turmas.ler')` no topo, e é a decisão que salva a
-- função de mentir. Sem ela, quem tem `alunos.ler` e não tem `turmas.ler` lê
-- ZERO reposições — não um erro, zero linhas (card 2.3 §3.4) — e recebe
-- `debito = 0`. Para um aluno pontual isso vira 'MANTER' (só conservador); para
-- um aluno JÁ em REP contínuo vira **'SUGERIR_VOLTA'**, isto é, o sistema
-- sugerindo desfazer a virada porque não conseguiu ver a dívida. Erro alto no
-- lugar de resposta plausível.
create or replace function public.fn_rep_situacao(p_aluno_id uuid)
returns public.tp_rep_situacao
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  r              public.tp_rep_situacao;
  v_status       text;
  v_prazo        integer;
  v_faltas_max   integer;
  v_janela_volta integer;
  v_faltas_volta integer;
  v_inviavel     boolean;
  v_reincidente  boolean;
begin
  perform public.fn_exige_permissao('turmas.ler');

  select a.status into v_status from public.aluno a where a.id = p_aluno_id;

  if v_status is null then
    raise exception using
      errcode = 'PT404',
      message = 'Aluno não encontrado.',
      detail  = json_build_object('codigo', 'ALUNO_INEXISTENTE',
                                  'aluno', p_aluno_id)::text;
  end if;

  -- Parâmetros, nunca número mágico (card 2.2 §2.3): ausência é
  -- PT422/PARAMETRO_AUSENTE, não um default escondido aqui dentro.
  v_prazo        := public.fn_param_int('rep_prazo_dias');
  r.capacidade   := public.fn_param_int('rep_capacidade_semanal');
  v_faltas_max   := public.fn_param_int('rep_faltas_max');
  v_janela_volta := public.fn_param_int('rep_janela_volta_dias');

  -- rep_desde: o relógio que a virada zerou (card 2.5 §3.2). Nulo = o aluno é
  -- pontual hoje. `order by` explícito porque `limit` sem ele é sorteio
  -- (docs/estrategia-testes.md §11) — e um aluno com duas alocações REP ativas
  -- é estado que o REP_JA_CONTINUO impede, mas o teste não pode depender disso.
  select ba.tipo_desde into r.rep_desde
    from public.bloco_aluno ba
   where ba.aluno_id = p_aluno_id and ba.ativo and ba.tipo = 'REP'
   order by ba.tipo_desde desc, ba.id
   limit 1;

  -- Débito: aulas PERDIDAS em aberto, agrupadas por aula de origem — duas
  -- reposições da mesma aula (a primeira cancelada, a segunda remarcada) são UM
  -- débito (card 2.5 §3.1). Reposição sem origem informada é uma aula própria,
  -- identificada pelo id da linha.
  with rep as (
    select r2.id, r2.status, r2.data, r2.data_origem,
           coalesce(r2.bloco_origem_id::text || '@' || r2.data_origem::text,
                    'AVULSA@' || r2.id::text) as aula
      from public.bloco_aluno_reposicao r2
     where r2.aluno_id = p_aluno_id
  ),
  aula as (
    select aula,
           min(coalesce(data_origem, data)) as data_aula,
           bool_or(status = 'REALIZADA')    as quitada
      from rep
     group by aula
  )
  select count(*)::integer, min(data_aula)
    into r.debito, r.aula_mais_antiga
    from aula
   where not quitada
     and data_aula > coalesce(r.rep_desde, date '-infinity');

  -- Viabilidade sobre a aula mais antiga, que é a que vence primeiro (§3.3).
  -- `ceil` e não `floor`, a favor do aluno: uma janela de 3 dias ainda pode
  -- conter o dia do bloco dele.
  --
  -- ⚠️ Sem débito NÃO há prazo, e escrever `greatest(ceil(null/7), 0)` devolveria
  -- **0** — o `greatest` ignora nulos, a mesma armadilha que o card 5.2 pegou em
  -- fn_vagas_livres. Aqui o 0 seria inofensivo por acidente (o veredito exige
  -- debito > 0), e é justamente por isso que passaria despercebido no dia em que
  -- alguém lesse `semanas_uteis` para montar a descrição da pendência.
  if r.aula_mais_antiga is null then
    r.prazo_final   := null;
    r.semanas_uteis := 0;
  else
    r.prazo_final   := r.aula_mais_antiga + v_prazo;
    r.semanas_uteis := greatest(
      ceil((r.prazo_final - public.fn_hoje())::numeric / 7)::integer, 0);
  end if;

  -- Reincidência (§3.4): gatilho independente da aritmética. É a diferença entre
  -- FALTOU e CANCELADA que o torna possível, e é por isso que o valor FALTOU foi
  -- bloqueante no card 5.1.
  --
  -- A janela é fechada dos DOIS lados. O §3.4 diz "nos últimos rep_prazo_dias", e
  -- escrever só o piso deixaria entrar FALTOU com data no futuro — que é dado
  -- incoerente (ninguém falta a uma aula que não aconteceu), mas dado que a tela
  -- do card 5.7 permite digitar. Contar o futuro faria a sugestão de virada
  -- nascer de um erro de digitação.
  select count(*)::integer into r.faltas_recentes
    from public.bloco_aluno_reposicao br
   where br.aluno_id = p_aluno_id
     and br.status = 'FALTOU'
     and br.data between public.fn_hoje() - v_prazo and public.fn_hoje();

  select count(*)::integer into v_faltas_volta
    from public.bloco_aluno_reposicao br
   where br.aluno_id = p_aluno_id
     and br.status = 'FALTOU'
     and br.data between public.fn_hoje() - v_janela_volta and public.fn_hoje();

  v_inviavel    := r.debito > r.capacidade * r.semanas_uteis;
  v_reincidente := r.faltas_recentes >= v_faltas_max;

  r.veredito := 'MANTER';

  -- Aluno fora de ATIVO/ACELERAR nunca é avaliado: tg_aluno_status_desaloca já
  -- cancelou as reposições futuras dele, e débito de aluno inativo não é
  -- acionável — ninguém vai alocá-lo em bloco nenhum.
  if v_status in ('ATIVO', 'ACELERAR') then
    if r.rep_desde is null then
      if r.debito > 0 and (v_inviavel or v_reincidente) then
        r.veredito := 'SUGERIR_CONTINUO';
      end if;
    else
      -- A condição de carência é o antídoto do pingue-pongue (card 2.5 §3.5): a
      -- virada zera o relógio e cancela as PREVISTA, então no instante seguinte
      -- as duas primeiras condições já estariam satisfeitas e a rotina sugeriria
      -- desfazer o que acabou de ser feito.
      if r.debito = 0
         and v_faltas_volta = 0
         and r.rep_desde <= public.fn_hoje() - v_janela_volta then
        r.veredito := 'SUGERIR_VOLTA';
      end if;
    end if;
  end if;

  return r;
end $$;

comment on function public.fn_rep_situacao(uuid) is
  'Situação de reposição do aluno (card 2.5 §3): débito de aulas em aberto, aula mais antiga, prazo, semanas úteis, faltas recentes e o veredito MANTER/SUGERIR_CONTINUO/SUGERIR_VOLTA. Exige turmas.ler — sem a permissão a RLS devolveria débito 0 e a função sugeriria VOLTAR para quem ainda deve.';

revoke execute on function public.fn_rep_situacao(uuid) from public;
revoke execute on function public.fn_rep_situacao(uuid) from anon;
grant  execute on function public.fn_rep_situacao(uuid) to authenticated;

-- O ponto de extensão que o card 2.2 §4.4 reservou: mesma assinatura, mesmos
-- três valores. Só o corpo deixa de ser 'MANTER' fixo.
create or replace function public.fn_rep_avaliar_virada(p_aluno_id uuid)
returns text
language sql
stable
set search_path = public, pg_temp
as $$ select (public.fn_rep_situacao(p_aluno_id)).veredito $$;

comment on function public.fn_rep_avaliar_virada(uuid) is
  'Veredito da virada REP: MANTER, SUGERIR_CONTINUO ou SUGERIR_VOLTA. Assinatura reservada pelo card 2.2 §4.4 e honrada pelo card 2.5. NÃO escreve — quem abre e fecha a pendência REP_VIRADA é a rt_rep_avaliar do card 5.5.';

revoke execute on function public.fn_rep_avaliar_virada(uuid) from public;
revoke execute on function public.fn_rep_avaliar_virada(uuid) from anon;
grant  execute on function public.fn_rep_avaliar_virada(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. tg_bloco_aluno_admissao — a camada 2, que vale para o POST direto
-- -----------------------------------------------------------------------------
-- Com "Automatically expose new tables" ligado (pendência técnica 3), TODA
-- tabela é uma API: a função de aplicação é o caminho normal e o trigger é a
-- garantia (card 2.2 §1). Um teste que só chama fn_bloco_admitir nunca descobre
-- que o trigger não existe — é o §6.1 do card 2.8.
--
-- ⚠️ O NULO é o centro deste trigger. fn_capacidade_efetiva e fn_ocupacao_bloco
-- são `security definer` e devolvem **nulo** (não zero) para bloco de outra
-- unidade — decisão do card 5.2. Comparar com nulo dá nulo, e um
-- `if v_ocupacao >= v_capacidade then raise` escrito sem pensar nisso deixaria o
-- BLOCO_LOTADO **passar em silêncio** exatamente no caso em que a escrita não
-- deveria nem existir. Nulo aqui é erro, não "sem opinião".
--
-- ⚠️ Limite conhecido: as leituras de `aluno` e `bloco_horario` são `invoker`,
-- então um perfil com `turmas.alocar` e SEM `alunos.ler` recebe
-- ALUNO_INEXISTENTE em vez de SEM_PERMISSAO. É fail-closed e ALTO (a escrita não
-- acontece e a mensagem aparece), e a alternativa — mais duas funções
-- `security definer` — amplia a lista fechada do C8 sem necessidade (card 3.4).
-- Nenhum perfil da matriz inicial é assim: quem aloca também lê aluno e bloco.
create or replace function public.fn_bloco_aluno_admissao()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_status     text;
  v_metodo_al  uuid;
  v_metodo_bl  uuid;
  v_capacidade integer;
  v_ocupacao   integer;
  v_entrando   boolean;
begin
  select a.status, a.metodo_id into v_status, v_metodo_al
    from public.aluno a where a.id = new.aluno_id;

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

  select b.metodo_id into v_metodo_bl
    from public.bloco_horario b where b.id = new.bloco_id;

  if v_metodo_bl is null then
    raise exception using
      errcode = 'PT404',
      message = 'Bloco de horário não encontrado nesta unidade.',
      detail  = json_build_object('codigo', 'BLOCO_INEXISTENTE',
                                  'bloco', new.bloco_id)::text;
  end if;

  if v_metodo_bl <> v_metodo_al then
    raise exception using
      errcode = 'PT422',
      message = 'O método do aluno é diferente do método da turma.',
      detail  = json_build_object('codigo', 'METODO_INCOMPATIVEL',
                                  'aluno', new.aluno_id, 'bloco', new.bloco_id)::text;
  end if;

  -- A vaga só é DISPUTADA quando a linha ENTRA na conta: insert ativo, volta de
  -- inativa para ativa, ou troca de bloco. Sem esta distinção, mudar o `tipo` de
  -- uma alocação já ativa (que é o que a virada REP faz quando o bloco de
  -- destino é o mesmo) veria a própria linha já contada e responderia
  -- BLOCO_LOTADO num bloco que não mudou de tamanho.
  v_entrando := tg_op = 'INSERT'
                or not old.ativo
                or new.bloco_id is distinct from old.bloco_id;

  if v_entrando then
    v_capacidade := public.fn_capacidade_efetiva(new.bloco_id);
    v_ocupacao   := public.fn_ocupacao_bloco(new.bloco_id);

    if v_capacidade is null or v_ocupacao is null then
      raise exception using
        errcode = 'PT404',
        message = 'Bloco de horário não encontrado nesta unidade.',
        detail  = json_build_object('codigo', 'BLOCO_INEXISTENTE',
                                    'bloco', new.bloco_id)::text;
    end if;

    -- `>=` e não `>`: a linha do BEFORE INSERT ainda não está na contagem, e a
    -- que sai de ativo = false também não estava. Nos dois casos o que se
    -- pergunta é "cabe mais um?".
    if v_ocupacao >= v_capacidade then
      raise exception using
        errcode = 'PT409',
        message = format('Bloco lotado: %s de %s vagas ocupadas em %s.',
                         v_ocupacao, v_capacidade,
                         to_char(public.fn_hoje(), 'DD/MM/YYYY')),
        detail  = json_build_object('codigo', 'BLOCO_LOTADO',
                                    'bloco', new.bloco_id,
                                    'capacidade', v_capacidade,
                                    'ocupacao', v_ocupacao)::text,
        hint    = 'Remova um aluno do bloco ou use outro horário.';
    end if;
  end if;

  return new;
end $$;

comment on function public.fn_bloco_aluno_admissao() is
  'Trigger BEFORE INSERT/UPDATE em bloco_aluno, só para linha ATIVA: aluno em ATIVO/ACELERAR (PT409/ALUNO_INATIVO), método do aluno igual ao do bloco (PT422/METODO_INCOMPATIVEL) e vaga livre quando a linha ENTRA na conta (PT409/BLOCO_LOTADO). Capacidade nula é bloco de outra unidade e vira PT404/BLOCO_INEXISTENTE — comparar com nulo deixaria a lotação passar em silêncio.';

revoke execute on function public.fn_bloco_aluno_admissao() from public;
revoke execute on function public.fn_bloco_aluno_admissao() from anon;

-- `when (new.ativo)`: a desalocação (ativo = false), inclusive a sem ator de
-- tg_aluno_status_desaloca, não passa por validação nenhuma — sair de uma turma
-- nunca pode ser recusado.
create trigger tg_bloco_aluno_admissao
  before insert or update on public.bloco_aluno
  for each row when (new.ativo)
  execute function public.fn_bloco_aluno_admissao();

-- -----------------------------------------------------------------------------
-- 5. tg_reposicao_admissao — a mesma checagem, NA DATA da reposição
-- -----------------------------------------------------------------------------
-- Três diferenças em relação ao de cima, e cada uma tem um motivo próprio:
--
--   (a) capacidade e status do aluno só são conferidos quando a linha é
--       PREVISTA. É a única situação que ocupa vaga (card 2.2 §4.4), e as outras
--       três descrevem o passado: exigir aluno ATIVO para gravar uma reposição
--       REALIZADA impediria o importador do card 9.1 de carregar o histórico de
--       quem já se formou, e conferir capacidade num dia que já passou é
--       perguntar se cabe alguém numa aula que acabou.
--       É também o que deixa tg_aluno_status_desaloca CANCELAR as reposições de
--       quem acabou de sair — sem isso, trancar um aluno falharia com
--       ALUNO_INATIVO dentro da transação de uma tela que não fala de turma.
--
--   (b) o método é conferido SEMPRE: repor Inglês num bloco de Interativo está
--       errado ontem, hoje e amanhã.
--
--   (c) data no passado exige `turmas.lancar_reposicao_retroativa` — e só quando
--       a linha NASCE ou muda de data. Conferir em todo update faria
--       fn_reposicao_registrar exigir a permissão retroativa para marcar
--       presença numa reposição de ontem, que é o uso normal dela.
create or replace function public.fn_reposicao_admissao()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_status     text;
  v_metodo_al  uuid;
  v_metodo_bl  uuid;
  v_capacidade integer;
  v_ocupacao   integer;
  v_entrando   boolean;
begin
  select a.status, a.metodo_id into v_status, v_metodo_al
    from public.aluno a where a.id = new.aluno_id;

  if v_status is null then
    raise exception using
      errcode = 'PT404',
      message = 'Aluno não encontrado.',
      detail  = json_build_object('codigo', 'ALUNO_INEXISTENTE',
                                  'aluno', new.aluno_id)::text;
  end if;

  select b.metodo_id into v_metodo_bl
    from public.bloco_horario b where b.id = new.bloco_id;

  if v_metodo_bl is null then
    raise exception using
      errcode = 'PT404',
      message = 'Bloco de horário não encontrado nesta unidade.',
      detail  = json_build_object('codigo', 'BLOCO_INEXISTENTE',
                                  'bloco', new.bloco_id)::text;
  end if;

  if v_metodo_bl <> v_metodo_al then
    raise exception using
      errcode = 'PT422',
      message = 'O método do aluno é diferente do método da turma.',
      detail  = json_build_object('codigo', 'METODO_INCOMPATIVEL',
                                  'aluno', new.aluno_id, 'bloco', new.bloco_id)::text;
  end if;

  if (tg_op = 'INSERT' or new.data is distinct from old.data)
     and new.data < public.fn_hoje() then
    perform public.fn_exige_permissao('turmas.lancar_reposicao_retroativa');
  end if;

  if new.status = 'PREVISTA' then
    if v_status not in ('ATIVO', 'ACELERAR') then
      raise exception using
        errcode = 'PT409',
        message = format('Aluno em %s não pode ter reposição agendada.', v_status),
        detail  = json_build_object('codigo', 'ALUNO_INATIVO',
                                    'aluno', new.aluno_id, 'status', v_status)::text;
    end if;

    v_entrando := tg_op = 'INSERT'
                  or old.status <> 'PREVISTA'
                  or new.bloco_id is distinct from old.bloco_id
                  or new.data    is distinct from old.data;

    if v_entrando then
      v_capacidade := public.fn_capacidade_efetiva(new.bloco_id, new.data);
      v_ocupacao   := public.fn_ocupacao_bloco(new.bloco_id, new.data);

      if v_capacidade is null or v_ocupacao is null then
        raise exception using
          errcode = 'PT404',
          message = 'Bloco de horário não encontrado nesta unidade.',
          detail  = json_build_object('codigo', 'BLOCO_INEXISTENTE',
                                      'bloco', new.bloco_id)::text;
      end if;

      if v_ocupacao >= v_capacidade then
        raise exception using
          errcode = 'PT409',
          message = format('Bloco lotado: %s de %s vagas ocupadas em %s.',
                           v_ocupacao, v_capacidade,
                           to_char(new.data, 'DD/MM/YYYY')),
          detail  = json_build_object('codigo', 'BLOCO_LOTADO',
                                      'bloco', new.bloco_id,
                                      'data', new.data,
                                      'capacidade', v_capacidade,
                                      'ocupacao', v_ocupacao)::text,
          hint    = 'Escolha outro dia ou outro horário para a reposição.';
      end if;
    end if;
  end if;

  return new;
end $$;

comment on function public.fn_reposicao_admissao() is
  'Trigger BEFORE INSERT/UPDATE em bloco_aluno_reposicao: método sempre; aluno ATIVO/ACELERAR e vaga NA DATA só quando a linha é PREVISTA (as outras três descrevem o passado); data retroativa exige turmas.lancar_reposicao_retroativa, e só quando a linha nasce ou muda de data.';

revoke execute on function public.fn_reposicao_admissao() from public;
revoke execute on function public.fn_reposicao_admissao() from anon;

create trigger tg_reposicao_admissao
  before insert or update on public.bloco_aluno_reposicao
  for each row execute function public.fn_reposicao_admissao();

-- -----------------------------------------------------------------------------
-- 6. fn_bloco_admitir / fn_bloco_remover — a camada 3
-- -----------------------------------------------------------------------------
-- O advisory lock é o §4.5 do card 2.2, e a razão de ele existir não é
-- performance: duas secretarias admitindo o último aluno ao mesmo tempo passam
-- as DUAS pela checagem de capacidade (em `read committed` nenhuma enxerga a
-- linha ainda não commitada da outra) e o bloco fica com 11 alunos em 10 PCs.
-- Nenhuma constraint pega isso — é regra de AGREGADO, não de linha. O lock é
-- por bloco, morre no fim da transação e é exercitado por
-- supabase/tests_concorrencia/admissao_ultima_vaga.sh (card 2.8 §7); a suíte
-- pgTAP roda numa conexão só e jamais o exercita.
create or replace function public.fn_bloco_admitir(
  p_bloco_id             uuid,
  p_aluno_id             uuid,
  p_tipo                 text,
  p_data_inicio_prevista date default null
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

  -- O `check` bloco_aluno_novo_ck já barraria (camada 1), com um 23514 que a
  -- tela não sabe traduzir. Aqui o mesmo fato ganha o código do catálogo.
  if p_tipo = 'NOVO' and p_data_inicio_prevista is null then
    raise exception using
      errcode = 'PT422',
      message = 'Aluno NOVO precisa de data de início prevista.',
      detail  = json_build_object('codigo', 'DATA_PREVISTA_OBRIGATORIA',
                                  'bloco', p_bloco_id, 'aluno', p_aluno_id)::text;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_bloco_id::text, 0));

  select b.unidade_id into v_unidade
    from public.bloco_horario b where b.id = p_bloco_id;

  if v_unidade is null then
    raise exception using
      errcode = 'PT404',
      message = 'Bloco de horário não encontrado nesta unidade.',
      detail  = json_build_object('codigo', 'BLOCO_INEXISTENTE',
                                  'bloco', p_bloco_id)::text;
  end if;

  -- Reativa em vez de duplicar (card 2.2 §4.3): `bloco_aluno_ativo_uk` é
  -- parcial (`where ativo`), então nada impede uma linha inativa antiga ao lado
  -- de uma ativa — daí a escolha explícita da ativa primeiro, e `order by`
  -- completo porque `limit` sem ele é sorteio (docs/estrategia-testes.md §11).
  select ba.id into v_id
    from public.bloco_aluno ba
   where ba.bloco_id = p_bloco_id and ba.aluno_id = p_aluno_id
   order by ba.ativo desc, ba.criado_em desc, ba.id
   limit 1;

  if v_id is null then
    insert into public.bloco_aluno (unidade_id, bloco_id, aluno_id, tipo,
                                    data_inicio_prevista)
    values (v_unidade, p_bloco_id, p_aluno_id, p_tipo, p_data_inicio_prevista)
    returning id into v_id;
  else
    -- Reativar limpa o motivo da saída: ele descreve uma saída que deixou de
    -- valer, e mantê-lo faria a ficha do aluno dizer que ele saiu da turma em
    -- que está.
    update public.bloco_aluno
       set ativo                = true,
           tipo                 = p_tipo,
           data_inicio_prevista = coalesce(p_data_inicio_prevista,
                                           data_inicio_prevista),
           motivo_saida         = null
     where id = v_id;
  end if;

  return v_id;
end $$;

comment on function public.fn_bloco_admitir(uuid, uuid, text, date) is
  'Admite o aluno no bloco e devolve o id da alocação. Exige turmas.alocar, serializa o bloco com pg_advisory_xact_lock (card 2.2 §4.5) e REATIVA a alocação existente em vez de duplicar. As regras (aluno ativo, método, lotação) são do tg_bloco_aluno_admissao — aqui não se reescreve nenhuma.';

revoke execute on function public.fn_bloco_admitir(uuid, uuid, text, date) from public;
revoke execute on function public.fn_bloco_admitir(uuid, uuid, text, date) from anon;
grant  execute on function public.fn_bloco_admitir(uuid, uuid, text, date) to authenticated;

create or replace function public.fn_bloco_remover(
  p_bloco_id uuid,
  p_aluno_id uuid,
  p_motivo   text default null
)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
begin
  perform public.fn_exige_permissao('turmas.alocar');

  update public.bloco_aluno
     set ativo = false, motivo_saida = p_motivo
   where bloco_id = p_bloco_id and aluno_id = p_aluno_id and ativo;

  -- Não encontrar nada é o caso que precisa DOER: silêncio aqui é a tela dizendo
  -- "removido" sobre uma turma em que o aluno continua, e o próximo a descobrir
  -- é quem contar as cadeiras.
  if not found then
    raise exception using
      errcode = 'PT404',
      message = 'Este aluno não está alocado neste bloco.',
      detail  = json_build_object('codigo', 'ALOCACAO_INEXISTENTE',
                                  'bloco', p_bloco_id, 'aluno', p_aluno_id)::text;
  end if;
end $$;

comment on function public.fn_bloco_remover(uuid, uuid, text) is
  'Desativa a alocação do aluno no bloco (alocação encerrada é ativo = false, card 2.4 §4) e grava o motivo em motivo_saida. Exige turmas.alocar; PT404/ALOCACAO_INEXISTENTE quando não há alocação ativa.';

revoke execute on function public.fn_bloco_remover(uuid, uuid, text) from public;
revoke execute on function public.fn_bloco_remover(uuid, uuid, text) from anon;
grant  execute on function public.fn_bloco_remover(uuid, uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 7. Reposições — a metade PONTUAL do REP híbrido (card 2.2 §4.4)
-- -----------------------------------------------------------------------------
create or replace function public.fn_reposicao_agendar(
  p_aluno_id        uuid,
  p_bloco_id        uuid,
  p_data            date,
  p_bloco_origem_id uuid default null,
  p_data_origem     date default null,
  p_observacao      text default null
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

  -- Mesmo lock da admissão, e pela mesma razão: a reposição PREVISTA ocupa vaga
  -- na data, então ela disputa o último lugar com uma admissão simultânea.
  perform pg_advisory_xact_lock(hashtextextended(p_bloco_id::text, 0));

  select b.unidade_id into v_unidade
    from public.bloco_horario b where b.id = p_bloco_id;

  if v_unidade is null then
    raise exception using
      errcode = 'PT404',
      message = 'Bloco de horário não encontrado nesta unidade.',
      detail  = json_build_object('codigo', 'BLOCO_INEXISTENTE',
                                  'bloco', p_bloco_id)::text;
  end if;

  insert into public.bloco_aluno_reposicao (unidade_id, bloco_id, aluno_id, data,
                                            bloco_origem_id, data_origem, observacao)
  values (v_unidade, p_bloco_id, p_aluno_id, p_data,
          p_bloco_origem_id, p_data_origem, p_observacao)
  returning id into v_id;

  return v_id;
end $$;

comment on function public.fn_reposicao_agendar(uuid, uuid, date, uuid, date, text) is
  'Agenda a reposição de uma aula perdida (status PREVISTA). Exige turmas.alocar e — via tg_reposicao_admissao — turmas.lancar_reposicao_retroativa quando a data já passou. bloco_origem_id/data_origem podem ser nulos de propósito (card 2.5 §3.1).';

revoke execute on function public.fn_reposicao_agendar(uuid, uuid, date, uuid, date, text) from public;
revoke execute on function public.fn_reposicao_agendar(uuid, uuid, date, uuid, date, text) from anon;
grant  execute on function public.fn_reposicao_agendar(uuid, uuid, date, uuid, date, text) to authenticated;

create or replace function public.fn_reposicao_cancelar(
  p_reposicao_id uuid,
  p_observacao   text
)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_status text;
begin
  perform public.fn_exige_permissao('turmas.alocar');

  select br.status into v_status
    from public.bloco_aluno_reposicao br where br.id = p_reposicao_id;

  if v_status is null then
    raise exception using
      errcode = 'PT404',
      message = 'Reposição não encontrada.',
      detail  = json_build_object('codigo', 'REPOSICAO_INEXISTENTE',
                                  'reposicao', p_reposicao_id)::text;
  end if;

  if v_status <> 'PREVISTA' then
    raise exception using
      errcode = 'PT409',
      message = format('Esta reposição já está como %s.', v_status),
      detail  = json_build_object('codigo', 'REPOSICAO_NAO_PREVISTA',
                                  'reposicao', p_reposicao_id,
                                  'status', v_status)::text;
  end if;

  update public.bloco_aluno_reposicao
     set status = 'CANCELADA',
         observacao = coalesce(p_observacao, observacao)
   where id = p_reposicao_id;
end $$;

comment on function public.fn_reposicao_cancelar(uuid, text) is
  'PREVISTA → CANCELADA. A aula perdida CONTINUA em aberto (card 2.5 §3.2): desmarcar a reposição não repõe a aula, e é isso que mantém o débito pesando até alguém remarcar.';

revoke execute on function public.fn_reposicao_cancelar(uuid, text) from public;
revoke execute on function public.fn_reposicao_cancelar(uuid, text) from anon;
grant  execute on function public.fn_reposicao_cancelar(uuid, text) to authenticated;

-- Ajuste 7 do §14 do card 2.2 / 5 do §8 do card 2.5: NASCE devolvendo `text`, e
-- não `void`. O card 5.1 registrou a transferência — não havia assinatura a
-- alterar porque a função ainda não existia. O que ela devolve é o veredito da
-- virada, para a secretaria ver na hora em que marca a falta, e não no dia
-- seguinte quando a rotina do card 5.5 abrir a pendência (card 2.2 §1.3:
-- informação que interessa à tela é status de retorno, não exceção).
create or replace function public.fn_reposicao_registrar(
  p_reposicao_id uuid,
  p_compareceu   boolean
)
returns text
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_status text;
  v_aluno  uuid;
begin
  perform public.fn_exige_permissao('turmas.alocar');

  select br.status, br.aluno_id into v_status, v_aluno
    from public.bloco_aluno_reposicao br where br.id = p_reposicao_id;

  if v_status is null then
    raise exception using
      errcode = 'PT404',
      message = 'Reposição não encontrada.',
      detail  = json_build_object('codigo', 'REPOSICAO_INEXISTENTE',
                                  'reposicao', p_reposicao_id)::text;
  end if;

  if v_status <> 'PREVISTA' then
    raise exception using
      errcode = 'PT409',
      message = format('Esta reposição já está como %s.', v_status),
      detail  = json_build_object('codigo', 'REPOSICAO_NAO_PREVISTA',
                                  'reposicao', p_reposicao_id,
                                  'status', v_status)::text;
  end if;

  update public.bloco_aluno_reposicao
     set status = case when p_compareceu then 'REALIZADA' else 'FALTOU' end
   where id = p_reposicao_id;

  return public.fn_rep_avaliar_virada(v_aluno);
end $$;

comment on function public.fn_reposicao_registrar(uuid, boolean) is
  'PREVISTA → REALIZADA (compareceu) ou FALTOU. Devolve o VEREDITO da virada REP (MANTER/SUGERIR_CONTINUO/SUGERIR_VOLTA) para a tela mostrar na hora — ajuste 7 do card 2.2 §14, transferido do card 5.1 para cá.';

revoke execute on function public.fn_reposicao_registrar(uuid, boolean) from public;
revoke execute on function public.fn_reposicao_registrar(uuid, boolean) from anon;
grant  execute on function public.fn_reposicao_registrar(uuid, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- 8. Executar a virada — card 2.5 §5.2
-- -----------------------------------------------------------------------------
-- A virada é SUGERIDA e executada por uma pessoa (decisão 1 do card 2.5): virar
-- contínuo cria alocação permanente, que consome vaga TODA SEMANA, e uma virada
-- automática escolheria o bloco sozinha e poderia esbarrar em BLOCO_LOTADO
-- dentro da rotina pg_cron, falhando em silêncio para o usuário.
--
-- Nenhuma checagem de vaga é reescrita aqui: fn_bloco_admitir já faz o advisory
-- lock, o método e o BLOCO_LOTADO. Se o bloco de destino estiver cheio, a virada
-- falha com o erro que a tela já sabe tratar e a pessoa escolhe outro.
--
-- DIVERGÊNCIA REGISTRADA com a ordem do §5.2, e o motivo é medível: lá o passo 2
-- é admitir e o 3 é cancelar as reposições PREVISTA. Aqui é o contrário. Uma
-- reposição PREVISTA do próprio aluno no bloco de destino, marcada para HOJE,
-- conta na fn_ocupacao_bloco e faria a virada morrer com um BLOCO_LOTADO causado
-- pelo próprio aluno que se está movendo para lá. Como tudo corre numa
-- transação só, cancelar antes não perde nada quando a admissão falha — o
-- rollback desfaz as duas coisas.
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

  -- PORTÃO DO CARD 5.5, no teste 085: o passo 4 do §5.2 do card 2.5 manda fechar
  -- aqui a pendência REP:<aluno>:CONTINUO com fn_pendencia_resolver. A tabela
  -- `pendencia` só nasce no card 5.5, e esquecer de voltar não daria erro
  -- nenhum: daria a lista de pendências sugerindo uma virada que já aconteceu.
  -- É a mesma forma que o card 4.2 deu ao gate de FORMADO e o 5.1 à terceira
  -- tabela de tg_aluno_status_desaloca.

  return v_id;
end $$;

comment on function public.fn_rep_virar_continuo(uuid, uuid, text) is
  'Converte o aluno para REP contínuo: cancela as reposições PREVISTA e cria (ou reativa) a alocação de tipo REP no bloco escolhido, delegando vaga e método a fn_bloco_admitir. PT409/REP_JA_CONTINUO quando já há alocação REP ativa. Falta fechar a pendência REP:<aluno>:CONTINUO quando o card 5.5 criar `pendencia` — o portão do teste 085 reprova nesse dia.';

revoke execute on function public.fn_rep_virar_continuo(uuid, uuid, text) from public;
revoke execute on function public.fn_rep_virar_continuo(uuid, uuid, text) from anon;
grant  execute on function public.fn_rep_virar_continuo(uuid, uuid, text) to authenticated;

-- A volta também é sugerida, e também é executada por uma pessoa. O motivo é
-- obrigatório porque desfazer uma conversão é decisão, não rotina — e agora ele
-- tem onde ser gravado (seção 1).
--
-- Se a alocação REP for a ÚNICA do aluno, a volta o deixa sem turma. Isso NÃO é
-- bloqueado, por decisão do card 2.5 §5.2: a rt_pendencias_diaria (card 5.5)
-- abre ALUNO_SEM_TURMA no dia seguinte, e bloquear aqui esconderia o problema
-- em vez de mostrá-lo.
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
end $$;

comment on function public.fn_rep_voltar_pontual(uuid, text) is
  'Desfaz a virada: desativa a alocação de tipo REP chamando fn_bloco_remover, que grava o motivo. PT422/MOTIVO_OBRIGATORIO sem motivo, PT409/REP_NAO_CONTINUO sem alocação REP ativa. Não impede o aluno ficar sem turma — quem denuncia isso é a pendência ALUNO_SEM_TURMA do card 5.5.';

revoke execute on function public.fn_rep_voltar_pontual(uuid, text) from public;
revoke execute on function public.fn_rep_voltar_pontual(uuid, text) from anon;
grant  execute on function public.fn_rep_voltar_pontual(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 9. A saída sem ator passa a dizer por quê
-- -----------------------------------------------------------------------------
-- `create or replace` da função do card 5.1: a única mudança é gravar
-- `motivo_saida`. Sem ela, a coluna da seção 1 nasceria nula justamente no caso
-- MAIS COMUM de saída de turma — o aluno que trancou —, e a ficha diria "saiu"
-- sem dizer nada. `motivo_saida` fica FORA da lista de
-- fn_bloco_aluno_colunas_permitidas de propósito: ela viaja junto com `ativo`,
-- que é exatamente a escrita que a política de update aceita sob
-- `alunos.alterar_status` (card 5.1 §7).
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

  update public.bloco_aluno_reposicao
     set status = 'CANCELADA'
   where aluno_id = new.id
     and status = 'PREVISTA'
     and data >= public.fn_hoje();

  return null;
end $$;

comment on function public.fn_aluno_status_desaloca() is
  'Trigger AFTER UPDATE OF status em aluno: quem deixa de ser ATIVO/ACELERAR sai dos blocos (ativo = false, com o motivo em motivo_saida) e tem as reposições FUTURAS canceladas. Voltar a ATIVO não realoca — a vaga pode já ter sido dada a outro (card 2.2 §3.2). Falta citar turma_modular_aluno quando o card 7.1 a criar; o portão do teste 040 reprova nesse dia.';

revoke execute on function public.fn_aluno_status_desaloca() from public;
revoke execute on function public.fn_aluno_status_desaloca() from anon;
