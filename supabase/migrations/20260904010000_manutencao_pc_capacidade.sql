-- =============================================================================
-- Card 5.4 — Manutenção de PC → recálculo de capacidade e pendência
--            (fn_pc_status_sincronizar, tg_pc_manutencao_status,
--             fn_revalidar_blocos_sala, tg_pc_revalida_blocos,
--             rt_pcs_normaliza, rt_capacidades, e as duas entram em rt_diaria)
-- Fonte: docs/regras-negocio-funcoes.md §4.6 (os dois triggers e a função),
--          §10.1 (catálogo: BLOCO_ACIMA_CAPACIDADE e PC_SEM_SUBSTITUTO, os dois
--          com fn_revalidar_blocos_sala como dono) e §11 (os cinco passos de
--          rt_diaria, dos quais este card entrega dois),
--        docs/modelagem-dados-ddl.md §8 (pc, pc_manutencao),
--        Decisões vigentes §5 pendência 9.12 (o trigger que este card devia ao
--          card 4.5) e §2 (a fórmula da capacidade, card 5.2).
--
-- Entrega: o caminho por EVENTO da capacidade — o que o card 5.5 deixou escrito
--          que faltava. A pendência BLOCO_ACIMA_CAPACIDADE já era aberta e
--          fechada todo dia pela rotina, com a chave CAPACIDADE:<bloco_id>;
--          aqui ela passa a nascer NA HORA em que a manutenção é registrada, em
--          vez de às 03:10 do dia seguinte, e a chave é a MESMA — os dois
--          caminhos convergem na dedup em vez de duplicar pendência.
--
-- ⚠️ ESTRUTURA E MAIS NADA: nenhuma linha de dado de negócio. O que estas
--    funções escrevem (`pc.status` e `pendencia`) é escrito em TEMPO DE
--    EXECUÇÃO, por trigger ou por rotina, nunca por esta migração — que não
--    chama nenhuma delas. É por isso que o portão do card 4.0,5
--    (portao-migracoes/varredor.mjs) fica verde com `update public.pc` e
--    `insert into pendencia` (via fn_pendencia_abrir) dentro dos corpos: corpo
--    de função é isento ATÉ a migração chamar a função.
--
-- ---------------------------------------------------------------------------
-- O QUE ESTE CARD **NÃO** ESCREVEU, e por que não é esquecimento
-- ---------------------------------------------------------------------------
-- A Nota do card pede "admissão bloqueada enquanto o bloco estiver acima da
-- capacidade". CONFERIDO ANTES DE ESCREVER CÓDIGO NOVO, e já está pronto desde
-- o card 5.3: `tg_bloco_aluno_admissao` compara `ocupacao >= capacidade` e
-- levanta PT409/BLOCO_LOTADO. Bloco ACIMA da capacidade satisfaz `>=` com
-- folga, então a admissão já é recusada — e é recusada pela camada 2, que vale
-- também para o POST direto no PostgREST. Escrever uma segunda guarda ("se
-- existe pendência CAPACIDADE:<bloco>, recusa") seria a terceira implementação
-- da mesma regra e teria um modo de falha próprio: a pendência é estado
-- GRAVADO, e um bloco que já normalizou continuaria bloqueado até a rotina
-- fechar a pendência. A verdade sobre a vaga é a comparação ao vivo.
-- Isso deixou de ser leitura e virou asserção: seção 5 do teste 091.
--
-- Também não entra aqui `after insert on pc`: um PC novo AUMENTA a capacidade e
-- pode fechar uma pendência, mas o §4.6 dá ao trigger `after update of status,
-- sala_id` e mais nada. A consequência de seguir a especificação é uma pendência
-- que sobrevive até as 03:10 seguintes — visível, e que se corrige sozinha. A
-- consequência de ampliar por conta própria seria escopo inventado num card que
-- não pediu. Registrado, não seguido em silêncio.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. CORREÇÃO DE FATO — o app e o banco liam `data_fim` de duas maneiras
-- -----------------------------------------------------------------------------
-- ⚠️ Achado ao escrever o trigger da seção 2, e ele SÓ APARECE quando o status
--    passa a ser derivado — até hoje as duas leituras nunca se encontravam.
--
--    O card 4.5, decisão (c), fixou a leitura do app: *"`data_fim` é previsão:
--    manutenção aberta = sem fim ou fim À FRENTE de hoje, e 'Encerrar' grava o
--    fim de HOJE"*. É o que `PcManutencao.abertaEm` implementa e é o que o botão
--    "Encerrar" faz: encerrar hoje significa **o PC voltou a operar hoje**.
--
--    O banco lia o contrário. `fn_capacidade_efetiva` (card 5.2) usa
--    `p_data between data_inicio and coalesce(data_fim, 'infinity')` — intervalo
--    FECHADO —, e o §4.6 diz "ao fechar (`data_fim` preenchida e PASSADA), volta
--    a OPERACIONAL". Sob essa leitura, encerrar a manutenção hoje deixaria o PC
--    em MANUTENCAO até amanhã: a turma da noite perderia uma vaga por uma
--    máquina que já voltou, a linha da tela mostraria "Em manutenção" sem
--    nenhuma manutenção aberta ao lado, e nada explicaria por quê.
--
--    RESOLVIDO A FAVOR DO APP, e o intervalo passa a ser `[data_inicio,
--    data_fim)`: `data_fim` é O DIA EM QUE O PC VOLTA A OPERAR. É a leitura que
--    a tela já implementa e que a única ação de encerrar do sistema produz; a
--    outra teria de mudar o comportamento do botão para continuar coerente. O
--    caso que a leitura fechada servia melhor — uma manutenção com início e fim
--    no MESMO dia, que passa a não cobrir dia nenhum — não nasce da tela: o
--    formulário de registrar deixa a previsão de fim VAZIA por padrão, que é
--    "sem previsão", e é assim que se registra um conserto em curso.
--
--    Duas leituras da mesma coluna é a divergência silenciosa que este projeto
--    cataloga; a partir daqui é UMA, e `fn_capacidade_efetiva` é reescrita aqui
--    para carregá-la. Nada mais da fórmula do card 5.2 muda — as três cláusulas,
--    o `least` com a nominal e o `capacidade_override` continuam idênticos.
create or replace function public.fn_capacidade_efetiva(
  p_bloco_id uuid,
  p_data     date default public.fn_hoje()
)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
           b.capacidade_override,
           least(
             (select count(*)::integer
                from public.pc p
               where p.sala_id    = b.sala_id
                 and p.unidade_id = b.unidade_id
                 and p.status <> 'DESATIVADO'
                 -- (2) parado na data: manutenção cobrindo p_data cujo substituto
                 --     não existe ou está na própria sala (logo, já contado).
                 and not exists (
                       select 1
                         from public.pc_manutencao m
                         left join public.pc sub on sub.id = m.pc_substituto_id
                        where m.pc_id = p.id
                          and m.data_inicio <= p_data
                          and p_data < coalesce(m.data_fim, 'infinity'::date)
                          and (m.pc_substituto_id is null
                               or sub.sala_id = b.sala_id))
                 -- (3) e disponível: OPERACIONAL, ou substituído por máquina de
                 --     fora da sala — que é o que "manter a capacidade" quer
                 --     dizer quando o status já foi para MANUTENCAO.
                 and (p.status = 'OPERACIONAL'
                      or exists (
                            select 1
                              from public.pc_manutencao m
                              join public.pc sub on sub.id = m.pc_substituto_id
                             where m.pc_id = p.id
                               and m.data_inicio <= p_data
                               and p_data < coalesce(m.data_fim, 'infinity'::date)
                               and sub.sala_id <> b.sala_id))),
             s.capacidade_nominal))
    from public.bloco_horario b
    join public.sala s on s.id = b.sala_id
   where b.id = p_bloco_id
     and b.unidade_id = public.fn_unidade_atual();
$$;

comment on function public.fn_capacidade_efetiva(uuid, date) is
  'Capacidade do bloco na data: capacidade_override, ou mín(PCs disponíveis da sala, capacidade_nominal). PC DESATIVADO nunca conta; manutenção sem substituto derruba; substituto de OUTRA sala repõe (o da própria sala já estava contado). A manutenção cobre [data_inicio, data_fim): data_fim é o dia em que o PC VOLTA a operar, que é a leitura do card 4.5 (c) e a que o botão Encerrar produz — corrigido no card 5.4. NULO quando o bloco não é da unidade corrente. Card 5.2 é o dono da fórmula.';

-- -----------------------------------------------------------------------------
-- 1. fn_pc_status_sincronizar — UMA implementação de "qual é o status hoje"
-- -----------------------------------------------------------------------------
-- Ela existe para o trigger (seção 2) e a rotina (seção 5) não terem cada um a
-- sua cópia da regra. Duas cópias divergem, e divergem para o lado silencioso:
-- o trigger acertaria e a rotina desfaria, ou o contrário, e o sintoma seria um
-- PC que muda de status sozinho de madrugada.
--
-- A regra: `pc.status` é DERIVADO de `pc_manutencao`. Existe manutenção
-- cobrindo hoje → MANUTENCAO; não existe → OPERACIONAL. DESATIVADO nunca se
-- toca (§4.6), e é essa exceção que mantém um caminho para tirar uma máquina de
-- circulação sem inventar uma manutenção que não houve.
--
-- ⚠️ A conta olha TODAS as manutenções do PC, não a linha do trigger. Um PC pode
--    ter duas em aberto (a corretiva de ontem e a preventiva agendada); fechar
--    UMA delas não devolve a máquina à operação, e um trigger que decidisse pelo
--    `new` a devolveria — com a capacidade da sala subindo por engano e a vaga
--    sendo vendida.
--
-- ⚠️ CORREÇÃO DE FATO, e ela veio da contraprova. Esta função nasceu
--    `security definer`, com a justificativa escrita aqui de que a política de
--    `update` de `pc` exige `salas.editar` (card 4.3 §6.1) e quem registra
--    manutenção é o MONITOR, que não a tem — logo, como `invoker`, o `update`
--    afetaria zero linhas em silêncio. **A sabotagem que devia provar isso saiu
--    VERDE:** reescrita como `invoker`, a suíte passou inteira. O motivo é que
--    quem já atravessa a RLS é o `fn_pc_manutencao_status` da seção 2, que é
--    `definer` por uma razão de PRIVILÉGIO — e dentro de uma função `definer` o
--    `invoker` da chamada seguinte é o DONO, não o monitor. A justificativa
--    estava errada e a asserção que eu tinha escrito não distinguia os dois
--    mundos; foi executá-la que mostrou isso.
--
--    Resolvido pelo precedente do próprio projeto, o de
--    `fn_pendencias_fechar_ausentes` (card 5.5): **ela é `invoker` porque só
--    quem roda como o dono a chama** — aqui, o trigger da seção 2 e a rotina da
--    seção 5. Entrar na lista fechada do C8 sem necessidade gasta a revisão
--    consciente que a lista existe para provocar (card 3.4 (a)), e um `definer`
--    a mais é um lugar a mais onde alguém pode esquecer o filtro de unidade.
--    O filtro está no corpo de qualquer modo, porque a função é chamada de
--    dentro de contextos que ignoram a RLS.
--
--    O que a RLS de fato impede continua medido, e sem sabotagem nenhuma: a
--    seção 2 do teste 091 mostra o monitor tentando escrever `pc.status` e
--    afetando ZERO linhas, sem erro — e é por isso que o caminho tem de passar
--    por uma função e não pela tela.
create or replace function public.fn_pc_status_sincronizar(p_pc_id uuid)
returns boolean
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_atual   text;
  v_alvo    text;
begin
  v_unidade := public.fn_unidade_atual();

  if v_unidade is null then
    raise exception
      'fn_pc_status_sincronizar: sem unidade no contexto (nem sessão autenticada nem contexto de rotina). Sincronizar status sem unidade alcançaria PC de qualquer escola.';
  end if;

  select p.status into v_atual
    from public.pc p
   where p.id = p_pc_id and p.unidade_id = v_unidade;

  -- PC de outra unidade, inexistente, ou dado baixa: nada a fazer, e o `false`
  -- diz "não mexi" — quem precisa distinguir os casos é a tela, não esta função.
  if v_atual is null or v_atual = 'DESATIVADO' then
    return false;
  end if;

  -- `[data_inicio, data_fim)`, a leitura única fixada na seção 0.
  v_alvo := case
              when exists (select 1
                             from public.pc_manutencao m
                            where m.pc_id = p_pc_id
                              and m.data_inicio <= public.fn_hoje()
                              and public.fn_hoje() < coalesce(m.data_fim, 'infinity'::date))
              then 'MANUTENCAO'
              else 'OPERACIONAL'
            end;

  if v_alvo = v_atual then
    return false;
  end if;

  update public.pc
     set status = v_alvo
   where id = p_pc_id and unidade_id = v_unidade;

  return true;
end $$;

comment on function public.fn_pc_status_sincronizar(uuid) is
  'Deriva pc.status de pc_manutencao: MANUTENCAO enquanto houver manutenção cobrindo fn_hoje(), OPERACIONAL quando não houver. Nunca toca em DESATIVADO. Devolve true quando mudou. Fonte única da regra para o trigger (evento) e para rt_pcs_normaliza (passagem do tempo). INVOKER de propósito, pelo precedente de fn_pendencias_fechar_ausentes: só quem roda como o dono a chama, e sem grant para authenticated ninguém mais alcança.';

revoke execute on function public.fn_pc_status_sincronizar(uuid) from public;
revoke execute on function public.fn_pc_status_sincronizar(uuid) from anon;
revoke execute on function public.fn_pc_status_sincronizar(uuid) from authenticated;

-- -----------------------------------------------------------------------------
-- 2. tg_pc_manutencao_status — o status acompanha a manutenção (§4.6)
-- -----------------------------------------------------------------------------
-- Fecha a pendência 9.12 das Decisões vigentes, aberta pelo card 4.5: até hoje o
-- formulário oferecia um interruptor a quem tem `salas.editar` e AVISAVA o
-- monitor de que o status não mudaria. Com o trigger, os dois saem do
-- formulário — a tela deixa de oferecer uma escolha que o banco passou a tomar.
--
-- `security definer`, e é ESTE o definer que carrega as duas metades da coisa —
-- a seção 1 registra por que o outro foi desfeito.
--
--   (a) PRIVILÉGIO: o Postgres confere o EXECUTE de um trigger no
--       `create trigger` e não a cada disparo (card 3.3 (c)), mas a CHAMADA
--       daqui para fn_pc_status_sincronizar é chamada normal, e essa função não
--       tem `grant` para `authenticated`. Como `invoker`, o trigger morreria com
--       "permission denied for function" na cara do monitor. A alternativa era
--       conceder a função ao `authenticated`, o que criaria uma RPC publicada
--       sem consumidor nenhum — o que o card 2.4 (a) recusa para código de
--       permissão e vale igual para função.
--
--   (b) RLS: é aqui que a travessia acontece. A política de `update` de `pc`
--       exige `salas.editar` (card 4.3 §6.1) e quem registra manutenção é o
--       MONITOR, que tem `salas.registrar_manutencao` e não tem a outra
--       (confirmação de Irineu, card 3.6). Rodando como o dono, o `update` da
--       seção 1 alcança a linha; rodando como o monitor, afetaria ZERO linhas
--       **sem erro nenhum** (card 3.4 (d)) e o PC ficaria OPERACIONAL na ficha
--       enquanto estivesse quebrado. As duas metades são vistas vermelhas: a (a)
--       sabotando este `definer`, a (b) na própria seção 2 do teste 091, que
--       mede o `update` do monitor afetando zero linhas.
create or replace function public.fn_pc_manutencao_status()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.fn_pc_status_sincronizar(new.pc_id);

  -- `pc_id` não muda na prática, mas nada no schema o impede, e um UPDATE que o
  -- mudasse deixaria a máquina ANTIGA parada para sempre — sem erro nenhum.
  if tg_op = 'UPDATE' and old.pc_id is distinct from new.pc_id then
    perform public.fn_pc_status_sincronizar(old.pc_id);
  end if;

  return null;
end $$;

comment on function public.fn_pc_manutencao_status() is
  'AFTER INSERT/UPDATE em pc_manutencao: sincroniza o status do PC afetado (e do anterior, se pc_id mudou). Toda a regra mora em fn_pc_status_sincronizar — aqui só se decide QUAIS PCs revisar. SECURITY DEFINER para poder chamá-la sem que ela precise de grant para authenticated.';

revoke execute on function public.fn_pc_manutencao_status() from public;
revoke execute on function public.fn_pc_manutencao_status() from anon;

create trigger tg_pc_manutencao_status
  after insert or update on public.pc_manutencao
  for each row execute function public.fn_pc_manutencao_status();

-- -----------------------------------------------------------------------------
-- 3. fn_revalidar_blocos_sala — o dono das duas pendências de capacidade
-- -----------------------------------------------------------------------------
-- ⚠️ DIVERGÊNCIA DO CARD 5.5 RESOLVIDA, e é a decisão que estrutura este card.
--    O 5.5 registrou que `BLOCO_ACIMA_CAPACIDADE` nascia em `rt_pendencias_diaria`
--    e não aqui — divergência com o §10.1, aceita porque a função ainda não
--    existia. Ela existe agora, e MANTER as duas seria manter DUAS
--    implementações da mesma comparação (a mesma condição, o mesmo `format`, a
--    mesma severidade), escritas em lugares diferentes e livres para divergir na
--    primeira vez que alguém mexer numa só. É exatamente a terceira
--    implementação que o card 2.3 §4.1 proíbe. Então o tipo volta ao dono que o
--    catálogo lhe dá: a seção 8 desta migração TIRA o bloco de
--    `rt_pendencias_diaria`, e quem passa a cobrir o caminho diário é
--    `rt_capacidades` (seção 6), que roda ANTES dela dentro de `rt_diaria`.
--    Dois CAMINHOS (evento e rotina) continuam existindo, como o 5.5 previu; o
--    que deixa de existir é a segunda CÓPIA da regra.
--
-- Nunca remove aluno (§4.6): a turma cheia não encolhe. Ela vira pendência, e a
-- admissão nova já é recusada por `tg_bloco_aluno_admissao` — ver a nota do
-- cabeçalho sobre o que este card deliberadamente não escreveu.
--
-- `security definer` pelos dois motivos que o projeto já catalogou: ela lê `pc`
-- e `bloco_horario` (guardados por `salas.ler` e `turmas.ler`) e escreve em
-- `pendencia` através de fn_pendencia_abrir. Como `invoker`, um perfil com
-- `salas.registrar_manutencao` e sem `turmas.ler` percorreria ZERO blocos e a
-- pendência simplesmente não abriria — sem erro, porque a RLS nega linha. Filtro
-- de unidade no corpo, como manda a correção do card 2.3.
--
-- NULO ≠ 0, pela mesma razão de fn_capacidade_efetiva (card 5.2): 0 é "sala sua,
-- e nenhum bloco acima da capacidade"; nulo é "esta sala não é da sua unidade".
create or replace function public.fn_revalidar_blocos_sala(p_sala_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_n       integer := 0;
  r         record;
begin
  v_unidade := public.fn_unidade_atual();

  if v_unidade is null then
    raise exception
      'fn_revalidar_blocos_sala: sem unidade no contexto (nem sessão autenticada nem contexto de rotina). Chamar de rt_capacidades, ou entrar no contexto de rotina antes (card 2.2 §2.2).';
  end if;

  if not exists (select 1 from public.sala s
                  where s.id = p_sala_id and s.unidade_id = v_unidade) then
    return null;
  end if;

  -- ---------------------------------------------------------------------------
  -- 3.1 BLOCO_ACIMA_CAPACIDADE (ALTA) — chave CAPACIDADE:<bloco_id>
  -- ---------------------------------------------------------------------------
  -- ⚠️ `coalesce(..., -1)` e não `is not null`, herdado do card 5.5: as duas
  --    funções devolvem nulo para bloco de outra unidade, e `null > null` é
  --    nulo, que num `if` é falso — a pendência não abriria, em silêncio, se a
  --    premissa do filtro de unidade mudasse. Com -1 o dia em que isso
  --    acontecer REPROVA em voz alta, porque -1 não é maior que ocupação
  --    nenhuma e a contagem do teste acusa.
  for r in select b.id,
                  public.fn_ocupacao_bloco(b.id)     as ocupacao,
                  public.fn_capacidade_efetiva(b.id) as capacidade,
                  s.nome as sala, b.dia_semana, b.hora_inicio
             from public.bloco_horario b
             join public.sala s on s.id = b.sala_id
            where b.sala_id   = p_sala_id
              and b.unidade_id = v_unidade
              and b.ativo
            order by b.dia_semana, b.hora_inicio, b.id
  loop
    if coalesce(r.ocupacao, -1) > coalesce(r.capacidade, -1) then
      perform public.fn_pendencia_abrir(
        'BLOCO_ACIMA_CAPACIDADE', 'CAPACIDADE:' || r.id::text,
        format('%s, dia %s às %s: %s aluno(s) para capacidade de %s. Admissão bloqueada até normalizar.',
               r.sala, r.dia_semana, to_char(r.hora_inicio, 'HH24:MI'),
               r.ocupacao, r.capacidade),
        'ALTA', p_bloco_id => r.id);
      v_n := v_n + 1;
    else
      perform public.fn_pendencia_resolver('CAPACIDADE:' || r.id::text);
    end if;
  end loop;

  -- ---------------------------------------------------------------------------
  -- 3.2 PC_SEM_SUBSTITUTO (MEDIA) — chave PC_SEM_SUBST:<pc_id>
  -- ---------------------------------------------------------------------------
  -- O tipo que o §10.1 acrescentou ao desenho original: o bloco acima da
  -- capacidade é o SINTOMA, e o PC parado sem quem o substitua é a CAUSA. Sem
  -- ela, uma sala sem turma nenhuma teria máquina parada e nada diria; e numa
  -- sala com turma a central mostraria o bloco estourado sem dizer o que
  -- resolveria (informar um substituto).
  --
  -- ⚠️ "SEM SUBSTITUTO" AQUI É O MESMO "SEM SUBSTITUTO" DA FÓRMULA DA CAPACIDADE
  --    (card 5.2, decisão (b)): substituto da PRÓPRIA sala não repõe máquina
  --    nenhuma, porque ela já estava contada. Uma pendência que aceitasse o
  --    substituto da própria sala fecharia dizendo "resolvido" exatamente
  --    enquanto a capacidade continuasse caída — a mentira plausível que este
  --    projeto cataloga. As duas condições são a mesma frase, e é de propósito.
  --
  -- DESATIVADO entra no laço e sai pelo `case`: um PC dado baixa não é "parado
  -- sem substituto", é uma máquina que não existe mais para a capacidade. Ele
  -- precisa ser PERCORRIDO para que desativar um PC FECHE a pendência que ele
  -- tinha aberta — pulá-lo no `where` a deixaria aberta para sempre, esperando
  -- uma revalidação que nunca mais olharia para ele.
  for r in select p.id, p.identificador,
                  (p.status <> 'DESATIVADO'
                   and exists (select 1
                                 from public.pc_manutencao m
                                 left join public.pc sub on sub.id = m.pc_substituto_id
                                where m.pc_id = p.id
                                  and m.data_inicio <= public.fn_hoje()
                                  and public.fn_hoje() < coalesce(m.data_fim, 'infinity'::date)
                                  and (m.pc_substituto_id is null
                                       or sub.sala_id = p.sala_id))) as parado,
                  (select min(m.data_inicio)
                     from public.pc_manutencao m
                    where m.pc_id = p.id
                      and m.data_inicio <= public.fn_hoje()
                      and public.fn_hoje() < coalesce(m.data_fim, 'infinity'::date)) as desde
             from public.pc p
            where p.sala_id    = p_sala_id
              and p.unidade_id = v_unidade
            order by p.identificador, p.id
  loop
    if r.parado then
      perform public.fn_pendencia_abrir(
        'PC_SEM_SUBSTITUTO', 'PC_SEM_SUBST:' || r.id::text,
        format('%s está em manutenção desde %s sem PC substituto de outra sala — a capacidade da sala caiu.',
               r.identificador, to_char(r.desde, 'DD/MM/YYYY')),
        'MEDIA', p_pc_id => r.id);
    else
      perform public.fn_pendencia_resolver('PC_SEM_SUBST:' || r.id::text);
    end if;
  end loop;

  return v_n;
end $$;

comment on function public.fn_revalidar_blocos_sala(uuid) is
  'Revalida a sala: abre ou fecha BLOCO_ACIMA_CAPACIDADE (ALTA, chave CAPACIDADE:<bloco_id>) para cada bloco ativo e PC_SEM_SUBSTITUTO (MEDIA, chave PC_SEM_SUBST:<pc_id>) para cada PC parado sem substituto de outra sala. Devolve quantos blocos ficaram acima; NULO para sala de outra unidade. Nunca remove aluno (card 2.2 §4.6): a turma cheia não encolhe, vira pendência, e a admissão nova já é recusada por tg_bloco_aluno_admissao.';

-- Sem `grant` para `authenticated`, de propósito: hoje os dois únicos chamadores
-- são o trigger da seção 4 e a rotina da seção 6, e os dois rodam como o dono.
-- Publicá-la como RPC seria oferecer uma ação sem consumidor — e o dia em que a
-- central do card 5.8 quiser um "revalidar agora" é o dia de decidir isso, com
-- o botão na frente.
revoke execute on function public.fn_revalidar_blocos_sala(uuid) from public;
revoke execute on function public.fn_revalidar_blocos_sala(uuid) from anon;
revoke execute on function public.fn_revalidar_blocos_sala(uuid) from authenticated;

-- -----------------------------------------------------------------------------
-- 4. tg_pc_revalida_blocos — o caminho por EVENTO (§4.6)
-- -----------------------------------------------------------------------------
-- ⚠️ CORREÇÃO DE FATO — a ordem entre os dois triggers de `pc_manutencao` NÃO
--    importa, e eu escrevi aqui que importava. O raciocínio parecia fechado: o
--    Postgres dispara triggers de mesmo tipo em ordem alfabética de nome
--    (`tg_pc_manutencao_status` < `tg_pc_revalida_blocos`, m < r), e ao ENCERRAR
--    uma manutenção a revalidação feita ANTES da sincronização veria o PC ainda
--    em MANUTENCAO e sem manutenção cobrindo hoje — a cláusula (3) da fórmula do
--    card 5.2 não o contaria, e a pendência ficaria aberta um dia inteiro depois
--    de o problema ter sido resolvido.
--
--    **A sabotagem que devia provar isso saiu VERDE.** Renomeado o primeiro
--    trigger para forçar a ordem inversa, a suíte passou inteira. O motivo é o
--    segundo trigger desta mesma seção: quando `fn_pc_status_sincronizar` grava
--    `pc.status`, esse `update` dispara `tg_pc_revalida_blocos` **em `pc`**, e a
--    sala é revalidada de novo — já com o status certo. A revalidação
--    "adiantada" não some, ela é seguida por outra que corrige.
--
--    Fica registrado porque é uma propriedade do desenho e não sorte de
--    nomenclatura: **a redundância entre os dois gatilhos é o que torna o
--    resultado independente da ordem**. Quem um dia remover o trigger de `pc`
--    por achá-lo redundante reintroduz a dependência de ordem — e aí ela volta a
--    ser silenciosa. A asserção do teste 091 continua valendo pelo que ela de
--    fato mede: encerrar a manutenção FECHA a pendência na mesma transação.
create or replace function public.fn_pc_revalida_blocos()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_sala     uuid;
  v_sala_old uuid;
begin
  if tg_table_name = 'pc_manutencao' then
    select p.sala_id into v_sala from public.pc p where p.id = new.pc_id;
    perform public.fn_revalidar_blocos_sala(v_sala);

    if tg_op = 'UPDATE' and old.pc_id is distinct from new.pc_id then
      select p.sala_id into v_sala_old from public.pc p where p.id = old.pc_id;
      if v_sala_old is distinct from v_sala then
        perform public.fn_revalidar_blocos_sala(v_sala_old);
      end if;
    end if;
  else
    perform public.fn_revalidar_blocos_sala(new.sala_id);

    -- PC que MUDA DE SALA mexe nas DUAS: a de destino ganha máquina e a de
    -- origem perde. Revalidar só a nova deixaria a origem sem a pendência que
    -- acabou de nascer — e o §4.6, que diz `fn_revalidar_blocos_sala(sala_id)`
    -- no singular, não tinha como prever de qual das duas se fala. Divergência
    -- registrada: aqui são as duas.
    if old.sala_id is distinct from new.sala_id then
      perform public.fn_revalidar_blocos_sala(old.sala_id);
    end if;
  end if;

  return null;
end $$;

comment on function public.fn_pc_revalida_blocos() is
  'AFTER em pc_manutencao (insert/update) e em pc (update de status ou sala_id): chama fn_revalidar_blocos_sala para a sala afetada — e para as DUAS quando o PC muda de sala. SECURITY DEFINER porque precisa ler pc.sala_id: quem registra manutenção pode não ter salas.ler, e como invoker leria nulo e a revalidação não aconteceria, sem erro nenhum.';

revoke execute on function public.fn_pc_revalida_blocos() from public;
revoke execute on function public.fn_pc_revalida_blocos() from anon;

create trigger tg_pc_revalida_blocos
  after insert or update on public.pc_manutencao
  for each row execute function public.fn_pc_revalida_blocos();

create trigger tg_pc_revalida_blocos
  after update of status, sala_id on public.pc
  for each row execute function public.fn_pc_revalida_blocos();

-- -----------------------------------------------------------------------------
-- 5. rt_pcs_normaliza — porque o TEMPO PASSAR não é evento
-- -----------------------------------------------------------------------------
-- É a razão de esta rotina existir ao lado do trigger, e vale escrever: uma
-- manutenção com `data_fim` amanhã não gera evento nenhum depois de amanhã. O
-- trigger só fala quando alguém escreve; a passagem da meia-noite não escreve
-- em lugar nenhum. Sem esta rotina, o PC ficaria MANUTENCAO para sempre — e a
-- capacidade da sala com ele, porque a cláusula (3) da fórmula do card 5.2 não
-- conta PC em MANUTENCAO sem manutenção cobrindo a data.
--
-- ⚠️ DIVERGÊNCIA REGISTRADA com o §11, que descreve a rotina como "fecha
--    manutenções com data_fim vencida; devolve PCs a OPERACIONAL". A primeira
--    metade não tem o que fazer: manutenção com `data_fim` no passado JÁ está
--    fechada pelas próprias datas, e manutenção com `data_fim` nulo está aberta
--    por definição — não existe estado "vencida" a fechar, e escrever em
--    `pc_manutencao` aqui inventaria histórico que ninguém registrou. O que a
--    passagem do tempo deixa desatualizado é `pc.status`, e é isso que a rotina
--    conserta.
--
--    E conserta nos DOIS SENTIDOS, não só "devolve a OPERACIONAL": uma
--    manutenção AGENDADA para daqui a uma semana nasce sem tocar no status (o
--    trigger a vê como não-cobrindo-hoje, e está certo), e no dia em que ela
--    começar nada dispara. Metade da regra deixaria o PC OPERACIONAL enquanto
--    estivesse parado — o erro na direção pior, a que vende vaga que não existe.
create or replace function public.rt_pcs_normaliza()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  r         record;
begin
  v_unidade := public.fn_unidade_atual();

  if v_unidade is null then
    raise exception
      'rt_pcs_normaliza: sem unidade no contexto. Chamar de rt_diaria, ou entrar no contexto de rotina antes (card 2.2 §2.2).';
  end if;

  for r in select p.id
             from public.pc p
            where p.unidade_id = v_unidade
              and p.status <> 'DESATIVADO'
            order by p.identificador, p.id
  loop
    -- O `update` de dentro dispara tg_pc_revalida_blocos, que revalida a sala:
    -- normalizar o status e reavaliar a capacidade são o mesmo movimento, e é
    -- por isso que rt_pcs_normaliza corre ANTES de rt_capacidades no §11.
    perform public.fn_pc_status_sincronizar(r.id);
  end loop;
end $$;

comment on function public.rt_pcs_normaliza() is
  'Passo 1 de rt_diaria (card 2.2 §11): põe pc.status em dia com pc_manutencao na unidade do contexto, nos dois sentidos — manutenção que terminou devolve o PC a OPERACIONAL, manutenção agendada que começou hoje o põe em MANUTENCAO. Existe porque o tempo passar não é evento e trigger nenhum o observa.';

revoke execute on function public.rt_pcs_normaliza() from public;
revoke execute on function public.rt_pcs_normaliza() from anon;
revoke execute on function public.rt_pcs_normaliza() from authenticated;

-- -----------------------------------------------------------------------------
-- 6. rt_capacidades — o caminho diário, agora dono de BLOCO_ACIMA_CAPACIDADE
-- -----------------------------------------------------------------------------
-- Todo bloco ativo mora em alguma sala, então percorrer as salas da unidade
-- cobre todos os blocos — e a rotina continua vendo a queda de capacidade venha
-- ela de onde vier: PC em manutenção, PC desativado, `capacidade_override`
-- reduzido à mão, aluno admitido antes de a capacidade cair.
--
-- A varredura do fim é o que o `fn_pendencias_fechar_ausentes` fazia pela
-- rotina do card 5.5 e que o laço por sala não alcança: bloco DESATIVADO
-- (`ativo = false`) sai do laço e levaria a pendência dele para sempre. Bloco
-- APAGADO não precisa de varredura — `pendencia.bloco_id` é `on delete cascade`.
-- PC não precisa de varredura nenhuma: fn_revalidar_blocos_sala percorre também
-- o DESATIVADO, justamente para fechar a pendência dele.
create or replace function public.rt_capacidades()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  r         record;
begin
  v_unidade := public.fn_unidade_atual();

  if v_unidade is null then
    raise exception
      'rt_capacidades: sem unidade no contexto. Chamar de rt_diaria, ou entrar no contexto de rotina antes (card 2.2 §2.2).';
  end if;

  for r in select s.id
             from public.sala s
            where s.unidade_id = v_unidade
            order by s.nome, s.id
  loop
    perform public.fn_revalidar_blocos_sala(r.id);
  end loop;

  for r in select p.chave_dedup
             from public.pendencia p
            where p.unidade_id  = v_unidade
              and p.tipo        = 'BLOCO_ACIMA_CAPACIDADE'
              and p.resolvida_em is null
              and not exists (select 1
                                from public.bloco_horario b
                               where b.id = p.bloco_id
                                 and b.unidade_id = v_unidade
                                 and b.ativo)
            order by p.chave_dedup
  loop
    perform public.fn_pendencia_resolver(r.chave_dedup);
  end loop;
end $$;

comment on function public.rt_capacidades() is
  'Passo 2 de rt_diaria (card 2.2 §11): fn_revalidar_blocos_sala em todas as salas da unidade do contexto, mais o fechamento das pendências de bloco que deixou de ser ativo. É o caminho DIÁRIO das duas pendências de capacidade; o caminho por EVENTO é tg_pc_revalida_blocos, e os dois usam a MESMA chave de dedup.';

revoke execute on function public.rt_capacidades() from public;
revoke execute on function public.rt_capacidades() from anon;
revoke execute on function public.rt_capacidades() from authenticated;

-- -----------------------------------------------------------------------------
-- 7. rt_diaria — os dois passos novos, na ordem do §11
-- -----------------------------------------------------------------------------
-- Reescrita inteira (não há como acrescentar passo a um corpo), preservando o
-- que o card 5.5 decidiu: cada rt_* no seu `begin … exception when others`, a
-- falha virando pendência ROTINA_FALHOU (ALTA) em vez de log — o log do
-- Supabase no free tier tem retenção de UM DIA (card 3.12 (g)), e uma rotina que
-- falha às 03:10 e some do log às 03:10 do dia seguinte falha em silêncio para
-- sempre, com o sintoma sendo uma central VAZIA.
--
-- A ORDEM é a do §11 e não é indiferente: `rt_pcs_normaliza` põe o status em dia
-- ANTES de `rt_capacidades` medir a capacidade, senão a primeira execução do dia
-- avaliaria a sala com o status de ontem e a pendência só corrigiria no dia
-- seguinte. Este é o portão que o card 5.5 armou no teste 090 e que este card
-- satisfaz: toda `rt_*` do projeto é chamada aqui. Falta `rt_projecao_demanda`,
-- do card 8.1 — o portão continua armado para ela.
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
      perform public.rt_pcs_normaliza();
      perform public.fn_pendencia_resolver('ROTINA_FALHOU:rt_pcs_normaliza');
    exception when others then
      perform public.fn_pendencia_abrir(
        'ROTINA_FALHOU', 'ROTINA_FALHOU:rt_pcs_normaliza',
        format('A rotina rt_pcs_normaliza falhou: %s (SQLSTATE %s). O status dos PCs desta unidade pode estar desatualizado.',
               sqlerrm, sqlstate),
        'ALTA');
    end;

    begin
      perform public.rt_capacidades();
      perform public.fn_pendencia_resolver('ROTINA_FALHOU:rt_capacidades');
    exception when others then
      perform public.fn_pendencia_abrir(
        'ROTINA_FALHOU', 'ROTINA_FALHOU:rt_capacidades',
        format('A rotina rt_capacidades falhou: %s (SQLSTATE %s). Os blocos acima da capacidade desta unidade podem não estar na central.',
               sqlerrm, sqlstate),
        'ALTA');
    end;

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
  'Rotina diária única (card 2.2 §11): itera as unidades ativas, entra no contexto de rotina em cada uma e chama, nesta ordem, rt_pcs_normaliza, rt_capacidades, rt_pendencias_diaria e rt_rep_avaliar — cada uma isolada num bloco de exceção que registra a falha como pendência ROTINA_FALHOU (ALTA) e segue. Falta rt_projecao_demanda (card 8.1); o portão do teste 090 reprova no dia em que ela nascer fora daqui.';

revoke execute on function public.rt_diaria() from public;
revoke execute on function public.rt_diaria() from anon;
revoke execute on function public.rt_diaria() from authenticated;

-- -----------------------------------------------------------------------------
-- 8. rt_pendencias_diaria — devolve BLOCO_ACIMA_CAPACIDADE ao dono do catálogo
-- -----------------------------------------------------------------------------
-- Reescrita SEM a seção de BLOCO_ACIMA_CAPACIDADE, pela decisão da seção 3
-- desta migração. As duas seções que ficam são idênticas às do card 5.5 — o que
-- sai é a terceira, inteira, com o `fn_pendencias_fechar_ausentes` dela.
--
-- Consequência para quem for ler o teste 090: a seção 6 daquele arquivo passou a
-- chamar `rt_capacidades()` e a derrubar a capacidade por `capacidade_override`,
-- que é a fonte de queda que trigger NENHUM observa — assim ela continua
-- medindo o caminho DIÁRIO, e não o caminho por evento deste card.
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
  -- BLOCO_ACIMA_CAPACIDADE saiu daqui no card 5.4
  -- ---------------------------------------------------------------------------
  -- O dono é fn_revalidar_blocos_sala, como o catálogo §10.1 sempre disse, e
  -- quem a chama todo dia é rt_capacidades — que rt_diaria executa ANTES desta
  -- rotina. Não é perda de cobertura: é a mesma regra, num lugar só. Manter a
  -- cópia aqui seria manter duas implementações da mesma comparação, livres para
  -- divergir na primeira vez que alguém mexer numa delas.
end $$;

comment on function public.rt_pendencias_diaria() is
  'Abre E fecha, na unidade do contexto corrente, as pendências de tempo desta fase: ALUNO_SEM_TURMA e ACELERAR_SEM_2O_BLOCO (contando só blocos de tipo <> REP). BLOCO_ACIMA_CAPACIDADE saiu daqui no card 5.4 e voltou ao dono do catálogo §10.1, fn_revalidar_blocos_sala, chamada todo dia por rt_capacidades. Reavaliada todo dia: a lista nunca acumula item que já deixou de ser verdade — e reabre o que foi fechado enquanto a condição continuar valendo.';

revoke execute on function public.rt_pendencias_diaria() from public;
revoke execute on function public.rt_pendencias_diaria() from anon;
revoke execute on function public.rt_pendencias_diaria() from authenticated;
