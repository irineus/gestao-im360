-- =============================================================================
-- Card 5.2 — Capacidade efetiva do bloco, derivada dos PCs
--            (fn_capacidade_efetiva, fn_ocupacao_bloco, fn_vagas_livres)
-- Fonte: docs/regras-negocio-funcoes.md §4.1, §4.2 e §15 (#2 — "fórmula final
--        da capacidade efetiva" é o que este card fecha),
--        docs/views-leitura.md §3.4 e §10 (#3 — as duas primeiras passam a
--        `security definer`), §7 (v_bloco_vagas_semana chama as três por linha).
--
-- ⚠️ ESTE ARQUIVO NÃO GRAVA NADA. Só função. O portão do card 4.0,5
--    (portao-migracoes/varredor.mjs) segue as chamadas transitivamente; aqui
--    não há `insert`/`update`/`delete` nenhum, nem dentro de corpo de função.
--
-- DIVERGÊNCIA REGISTRADA, não seguida em silêncio: o mapa função → card do
-- card 2.2 (§13) põe `fn_ocupacao_bloco` e `fn_vagas_livres` no card 5.3 e só
-- `fn_capacidade_efetiva` aqui. Três documentos posteriores dizem o contrário e
-- venceram: a Nota deste card ("Vagas livres = capacidade − alocados ativos"),
-- o §10 (#3) do card 2.3, que nomeia o 5.2 como dono da mudança para `definer`
-- das DUAS, e o comentário (d) da fixture do card 5.1, que descreve a reposição
-- PREVISTA no bloco vazio como "a asserção que reprova uma fn_ocupacao_bloco
-- (card 5.2) que somou só bloco_aluno". As três nascem juntas porque uma sem a
-- outra não tem como ser exercitada: capacidade sem ocupação não vira vaga.
-- As Notas do card 5.3 foram corrigidas para não recriá-las.
--
-- O que este card NÃO traz, e onde está escrito que não é esquecimento:
--   • tg_bloco_aluno_admissao, fn_bloco_admitir/fn_bloco_remover e as funções da
--     virada REP são do card 5.3 (§4.3 e §4.4);
--   • tg_pc_manutencao_status (amarrar `pc.status` à manutenção em aberto) e
--     fn_revalidar_blocos_sala são do card 5.4 — hoje o status é escolhido à mão
--     no formulário do card 4.5, e a fórmula abaixo é correta NOS DOIS MUNDOS,
--     que é a razão de ela não olhar só para o status;
--   • v_bloco_vagas_semana e fn_grade_semana são do card 5.6 (§7 do card 2.3).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. fn_capacidade_efetiva — a fórmula, e este card é o dono dela
-- -----------------------------------------------------------------------------
-- O ponto de partida do card 2.2 §4.1 era:
--
--   count(pc where sala = X and status = 'OPERACIONAL'
--                 and not exists (manutenção sem substituto na data))
--
-- Ele tem dois furos, e os dois só aparecem quando se junta o §4.1 com o §4.6
-- do mesmo documento — cada metade lida sozinha parece certa:
--
-- (a) O §4.6 manda `tg_pc_manutencao_status` (card 5.4) pôr o PC em MANUTENCAO
--     enquanto a manutenção estiver aberta, COM SUBSTITUTO OU SEM. A partir do
--     dia em que esse trigger existir, `status = 'OPERACIONAL'` derruba também o
--     PC substituído — e "um pc_substituto_id mantém a capacidade" (plano, §6)
--     deixaria de valer, silenciosamente, num card que não fala de capacidade.
--     A cláusula `not exists` viraria letra morta no mesmo movimento. Por isso o
--     PC em manutenção COM substituto válido volta a contar, explicitamente.
--
-- (b) Substituto da PRÓPRIA SALA não cria máquina nenhuma. Apontar o
--     `pc_substituto_id` para um PC que já está na sala e já está contado somaria
--     a mesma máquina duas vezes: dez PCs físicos passariam a valer onze vagas, e
--     o número teria a cara de estar certo. Substituição só repõe capacidade
--     quando traz máquina DE FORA da sala.
--
-- Daí a regra final, em três cláusulas. Um PC da sala conta na data quando:
--   1. não está DESATIVADO (baixa definitiva nunca conta);
--   2. não tem manutenção cobrindo a data SEM substituto válido;
--   3. está OPERACIONAL, ou tem manutenção cobrindo a data COM substituto válido.
--
-- A cláusula 2 é o que faz a função responder por uma DATA e não por "agora": o
-- `status` é um estado do presente, e `p_data` existe justamente para avaliar
-- admissão futura e reposição agendada (§4.1). Manutenção agendada para a semana
-- que vem não derruba a capacidade de hoje e derruba a daquele dia.
-- A cláusula 3 é o que impede o mundo pré-5.4 de mentir na outra direção: PC que
-- alguém marcou MANUTENCAO à mão, sem linha em `pc_manutencao`, não conta.
--
-- `security definer` (correção do card 2.3, §10 #3) — e é o coração deste card:
-- `salas.ler` guarda a tabela `pc`, e como `security invoker` um leitor sem essa
-- permissão contaria ZERO PCs, receberia capacidade 0 e veria a grade semanal
-- inteira como lotada. A RLS não levanta erro: devolve menos linhas. Número
-- derivado exibido em tela não pode depender do que o leitor enxerga. O preço do
-- `definer` é o filtro de unidade ter de estar no CORPO, e ele está: o bloco só
-- resolve se for da unidade corrente.
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
           -- Escape manual da secretaria: vence sempre, e é o único caminho que
           -- não olha para PC nenhum.
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
                          and p_data between m.data_inicio
                                         and coalesce(m.data_fim, 'infinity'::date)
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
                               and p_data between m.data_inicio
                                              and coalesce(m.data_fim, 'infinity'::date)
                               and sub.sala_id <> b.sala_id))),
             -- Teto: a sala não comporta mais gente do que a capacidade nominal,
             -- ainda que alguém cadastre PC a mais.
             s.capacidade_nominal))
    from public.bloco_horario b
    join public.sala s on s.id = b.sala_id
   where b.id = p_bloco_id
     and b.unidade_id = public.fn_unidade_atual();
$$;

comment on function public.fn_capacidade_efetiva(uuid, date) is
  'Capacidade do bloco na data: capacidade_override, ou mín(PCs disponíveis da sala, capacidade_nominal). PC DESATIVADO nunca conta; manutenção sem substituto derruba; substituto de OUTRA sala repõe (o da própria sala já estava contado). NULO quando o bloco não é da unidade corrente. Card 5.2 é o dono da fórmula — muda aqui e o sistema inteiro acompanha.';

revoke execute on function public.fn_capacidade_efetiva(uuid, date) from public;
revoke execute on function public.fn_capacidade_efetiva(uuid, date) from anon;
grant  execute on function public.fn_capacidade_efetiva(uuid, date) to authenticated;

-- -----------------------------------------------------------------------------
-- 2. fn_ocupacao_bloco — as DUAS metades do REP híbrido
-- -----------------------------------------------------------------------------
-- Decisão de 31/08/2026: a alocação em `bloco_aluno` vale toda semana e a
-- reposição em `bloco_aluno_reposicao` vale só no dia. A lotação de uma data é a
-- soma das duas, e só `PREVISTA` ocupa vaga — REALIZADA, FALTOU e CANCELADA saem
-- da conta: o passado não bloqueia o presente (§4.2 e §4.4).
--
-- Nenhum filtro por `tipo`: REM, PRE, REP e NOVO ocupam vaga igual. Aluno remoto
-- ocupa vaga (Nota do card), e NOVO também — a vaga está reservada para ele desde
-- a `data_inicio_prevista`, senão a secretaria a vende duas vezes.
--
-- `security definer` pela mesma razão da anterior, e com a mesma
-- contrapartida: `turmas.ler` guarda `bloco_aluno`, e um leitor sem ela veria
-- ocupação 0 num bloco cheio — o erro na direção oposta ao da capacidade, e pior,
-- porque "há vaga" convida a admitir mais um.
--
-- Zero e nulo dizem coisas diferentes de propósito: 0 é "bloco seu, e vazio";
-- nulo é "este bloco não é da sua unidade / não existe". As subconsultas escalares
-- garantem o 0 (count nunca é nulo) e a linha de `bloco_horario` garante o nulo.
create or replace function public.fn_ocupacao_bloco(
  p_bloco_id uuid,
  p_data     date default public.fn_hoje()
)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select (select count(*)::integer
            from public.bloco_aluno ba
           where ba.bloco_id = b.id
             and ba.ativo)
       + (select count(*)::integer
            from public.bloco_aluno_reposicao br
           where br.bloco_id = b.id
             and br.data     = p_data
             and br.status   = 'PREVISTA')
    from public.bloco_horario b
   where b.id = p_bloco_id
     and b.unidade_id = public.fn_unidade_atual();
$$;

comment on function public.fn_ocupacao_bloco(uuid, date) is
  'Lotação do bloco na data: alocações ativas (toda semana) + reposições PREVISTAS daquele dia. Todo tipo ocupa vaga, inclusive REM e NOVO. NULO quando o bloco não é da unidade corrente; 0 é bloco vazio de verdade.';

revoke execute on function public.fn_ocupacao_bloco(uuid, date) from public;
revoke execute on function public.fn_ocupacao_bloco(uuid, date) from anon;
grant  execute on function public.fn_ocupacao_bloco(uuid, date) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. fn_vagas_livres — e a armadilha do `greatest` com nulo
-- -----------------------------------------------------------------------------
-- NÃO é `security definer`, de propósito: ela não lê tabela nenhuma, só compõe as
-- duas de cima. Entrar na lista fechada do teste C8 sem necessidade gasta a
-- revisão consciente que a lista existe para provocar (mesma decisão que deixou
-- `fn_pc_exclusao_valida` fora dela, card 4.3).
--
-- ⚠️ `greatest(null, 0)` devolve **0**, não nulo: o `greatest` IGNORA nulos. Escrita
-- como `greatest(capacidade - ocupacao, 0)`, esta função responderia "0 vagas
-- livres" para um bloco de outra unidade — uma mentira plausível, do mesmo feitio
-- das quatro armadilhas do card 2.3 §3, e ainda por cima na direção que parece
-- segura ("lotado"), que é a que ninguém vai conferir. O `case` explícito preserva
-- o nulo das duas de cima.
create or replace function public.fn_vagas_livres(
  p_bloco_id uuid,
  p_data     date default public.fn_hoje()
)
returns integer
language sql
stable
set search_path = public, pg_temp
as $$
  select case
           when x.capacidade is null or x.ocupacao is null then null
           else greatest(x.capacidade - x.ocupacao, 0)
         end
    from (select public.fn_capacidade_efetiva(p_bloco_id, p_data) as capacidade,
                 public.fn_ocupacao_bloco(p_bloco_id, p_data)     as ocupacao) x;
$$;

comment on function public.fn_vagas_livres(uuid, date) is
  'Vagas livres do bloco na data: capacidade − ocupação, nunca negativo. Bloco acima da capacidade (card 5.4) devolve 0 aqui e continua acima — quem mostra o excesso é v_bloco_vagas_semana, comparando as duas parcelas. NULO quando o bloco não é da unidade corrente.';

revoke execute on function public.fn_vagas_livres(uuid, date) from public;
revoke execute on function public.fn_vagas_livres(uuid, date) from anon;
grant  execute on function public.fn_vagas_livres(uuid, date) to authenticated;
