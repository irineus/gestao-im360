-- =============================================================================
-- Card 5.6 — A grade semanal no banco (fn_grade_semana + v_bloco_vagas_semana)
-- Fonte: docs/views-leitura.md §7 (o SQL da view e a nota que manda escrever a
--          FUNÇÃO primeiro), §2 (princípios de view), §11 (permissões de
--          leitura) e §12 (mapa view → card),
--        docs/wireframes.md §7.1 (a tela que consome),
--        docs/regras-negocio-funcoes.md §4.1/§4.2 (as três funções do card 5.2,
--          que aqui não se reimplementam),
--        docs/estrategia-testes.md §13 (obrigação de card de View) e §17.
--
-- Entrega: `fn_grade_semana(p_segunda date)` — a grade de UMA semana — e
--          `v_bloco_vagas_semana` escrita EM CIMA dela, para a semana corrente.
--
-- ⚠️ ESTE ARQUIVO NÃO GRAVA NADA. Só função e view. O portão do card 4.0,5
--    (portao-migracoes/varredor.mjs) segue as chamadas transitivamente; aqui não
--    há `insert`/`update`/`delete` nenhum, nem dentro de corpo de função.
--
-- POR QUE A FUNÇÃO E A VIEW, E NÃO SÓ UMA DAS DUAS. A lotação de um bloco é de
-- uma DATA: a alocação em `bloco_aluno` vale toda semana, mas a reposição em
-- `bloco_aluno_reposicao` vale só no dia (card 2.1 §8, card 5.2). View não
-- recebe parâmetro, então a view fixa a semana corrente e a função cobre a
-- navegação de semanas que o wireframe §7.1 pede. Escrever a função primeiro e
-- a view em cima dela é o que impede a SEGUNDA implementação da mesma
-- aritmética (docs/views-leitura.md §7) — e o teste 095 assere que as duas
-- devolvem exatamente as mesmas linhas na semana corrente, sem o que a view
-- ficaria livre para divergir no dia em que alguém mexesse numa só.
--
-- O que este card NÃO traz, e onde está escrito que não é esquecimento:
--   • `v_bloco_alunos` (a lista de alunos do bloco) é do card 5.7 — §12.1 do
--     card 2.3 a nomeia como view de tela daquele card;
--   • as três `v_dashboard_*` são do card 8.7; o dashboard v1 do card 5.9
--     consome ESTA view e não cria a sua (§12);
--   • `v_turma_modular_lotacao` é dos cards 7.4/5.9.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. fn_grade_semana — a grade de uma semana, e a aritmética mora só aqui
-- -----------------------------------------------------------------------------
-- Três decisões, e as três têm modo de falha silencioso do outro lado:
--
-- (a) **`security invoker`** (o default), ao contrário das duas funções de
--     capacidade do card 5.2. A diferença não é descuido: aquelas devolvem um
--     NÚMERO DERIVADO, que não pode depender do que o leitor enxerga (card 2.3
--     §10 #3), e esta devolve LINHAS, que devem depender — quem não tem
--     `turmas.ler` não vê bloco nenhum, e é a RLS de `bloco_horario` que decide
--     isso. Como `definer`, esta função entregaria a grade da unidade inteira a
--     quem a RLS acabou de negar, e ainda gastaria uma vaga na lista fechada do
--     teste C8 sem necessidade (card 3.4 (a)).
--
-- (b) **`p_segunda` é NORMALIZADA para a segunda-feira da semana que a contém.**
--     A tela navega somando e subtraindo 7 dias, e um dia de folga na conta
--     (fuso, DST, um `p_segunda` vindo de um clique numa célula) faria a grade
--     mostrar a semana certa com as DATAS erradas — e como a data só aparece no
--     rótulo, a ocupação sairia deslocada em um dia sem nada na tela dizendo.
--     Com `date_trunc('week', …)` a função responde pela SEMANA de qualquer
--     data que receba, e o teste 095 assere que quarta e segunda dão a mesma
--     grade.
--
-- (c) **Nenhuma conta de capacidade aqui.** `capacidade`, `ocupacao` e
--     `vagas_livres` são as três funções do card 5.2 chamadas por linha, e não
--     `greatest(cap - ocu, 0)` escrito de novo: o card 5.2 é o dono da fórmula,
--     e uma cópia aqui divergiria no dia em que a fórmula mudasse — em silêncio,
--     porque os dois números continuariam plausíveis. O custo (cinco chamadas
--     por linha, para ~36 blocos ativos) é o preço aceito em docs/views-leitura
--     §7; se um dia doer, o alvo é a função, não esta.
--
-- `date_trunc('week', …)` devolve a SEGUNDA ISO e `dia_semana` é ISO com
-- 1 = segunda (card 5.1): `segunda + (dia_semana − 1)` dá a data daquele bloco
-- naquela semana. Um bloco de quinta consultado numa sexta traz a quinta que já
-- passou — comportamento certo para uma grade semanal, que navega semanas e não
-- dias.
--
-- ⚠️ `join` interno em `metodo` e `sala`, `left join` em `professor`: é o que o
--    card 2.3 §7 especifica, e é exatamente por causa deste join que o card 2.4
--    teve de abrir `materiais.ler`, `salas.ler` e `professores.ler` para os
--    quatro perfis. Com `security_invoker`, quem não tem `salas.ler` receberia
--    ZERO linhas — a grade inteira vazia, sem erro — e quem não tem
--    `professores.ler` receberia a grade sem professor nenhum, que não quebra,
--    mente. As duas metades viraram asserção de paridade no teste 095.
create or replace function public.fn_grade_semana(
  p_segunda date default public.fn_hoje()
)
returns table (
  unidade_id          uuid,
  bloco_id            uuid,
  dia_semana          smallint,
  hora_inicio         time,
  data_referencia     date,
  metodo_id           uuid,
  metodo_codigo       text,
  sala_id             uuid,
  sala_nome           text,
  professor_id        uuid,
  professor_nome      text,
  capacidade_override integer,
  capacidade          integer,
  ocupacao            integer,
  vagas_livres        integer,
  acima_capacidade    boolean
)
language sql
stable
set search_path = public, pg_temp
as $$
  select b.unidade_id,
         b.id,
         b.dia_semana,
         b.hora_inicio,
         ref.data,
         b.metodo_id,
         me.codigo,
         b.sala_id,
         s.nome,
         b.professor_id,
         p.nome,
         b.capacidade_override,
         n.capacidade,
         n.ocupacao,
         n.vagas_livres,
         (n.ocupacao > n.capacidade)
    from public.bloco_horario b
    cross join lateral (
           select (date_trunc('week', p_segunda)::date + (b.dia_semana - 1))
                    as data
         ) ref
    cross join lateral (
           select public.fn_capacidade_efetiva(b.id, ref.data) as capacidade,
                  public.fn_ocupacao_bloco(b.id, ref.data)     as ocupacao,
                  public.fn_vagas_livres(b.id, ref.data)       as vagas_livres
         ) n
    join public.metodo me on me.id = b.metodo_id
    join public.sala   s  on s.id  = b.sala_id
    left join public.professor p on p.id = b.professor_id
   where b.ativo;
$$;

comment on function public.fn_grade_semana(date) is
  'Grade semanal de blocos (card 5.6): uma linha por bloco ATIVO, com a data daquele bloco na semana de p_segunda e as três parcelas do card 5.2 medidas NAQUELA data. p_segunda é normalizada para a segunda-feira da semana que a contém. security invoker: quem não tem turmas.ler não vê bloco nenhum, e é a RLS que decide.';

revoke execute on function public.fn_grade_semana(date) from public;
revoke execute on function public.fn_grade_semana(date) from anon;
grant  execute on function public.fn_grade_semana(date) to authenticated;

-- -----------------------------------------------------------------------------
-- 2. v_bloco_vagas_semana — a mesma grade, na semana corrente
-- -----------------------------------------------------------------------------
-- `security_invoker = on` sem exceção (card 2.3 §2.1, asserido por C5). Aqui ela
-- é redundante duas vezes — a função já é `invoker` e a RLS de `bloco_horario` já
-- alcança o dono por `force` —, e mesmo assim está escrita: a exceção que se abre
-- "porque neste caso não faz diferença" é a que sobrevive à view seguinte.
--
-- Colunas explícitas e na ordem do card 2.3 §7 (§2.4). Não é `select *`: a view é
-- CONTRATO do card 5.9, e `select *` a faria mudar de forma sozinha no dia em que
-- a função ganhasse uma coluna — `create or replace view` recusaria, e o erro
-- apareceria numa migração que não fala de dashboard.
--
-- `fn_hoje()` e nunca `current_date` (§3.3 e C6): o Postgres do Supabase roda em
-- UTC, e das 21h à meia-noite `current_date` já é o dia seguinte — a grade da
-- semana viraria à noite de sábado, em plena aula.
create view public.v_bloco_vagas_semana with (security_invoker = on) as
select g.unidade_id,
       g.bloco_id,
       g.dia_semana,
       g.hora_inicio,
       g.data_referencia,
       g.metodo_id,
       g.metodo_codigo,
       g.sala_id,
       g.sala_nome,
       g.professor_id,
       g.professor_nome,
       g.capacidade_override,
       g.capacidade,
       g.ocupacao,
       g.vagas_livres,
       g.acima_capacidade
  from public.fn_grade_semana(date_trunc('week', public.fn_hoje())::date) g;

comment on view public.v_bloco_vagas_semana is
  'Grade da semana corrente (card 2.3 §7). É fn_grade_semana(segunda da semana de fn_hoje()) e nada mais — a aritmética mora na função, e o teste 095 assere que as duas devolvem as mesmas linhas. Consumidores: a grade do card 5.6 (que usa a FUNÇÃO, porque navega semanas) e o dashboard do card 5.9.';

revoke all   on public.v_bloco_vagas_semana from public;
revoke all   on public.v_bloco_vagas_semana from anon;
grant select on public.v_bloco_vagas_semana to authenticated;
