-- =============================================================================
-- Card 8.4,5 — Alerta de estoque abaixo do mínimo (ESTOQUE_ABAIXO_MINIMO)
--
-- Entregável: o ÚLTIMO tipo de pendência do catálogo §10.1 que tinha
-- `rt_pendencias_diaria` como dona e nunca teve quem o abrisse. Nada de schema:
-- `ESTOQUE_ABAIXO_MINIMO` está no `check` de `pendencia.tipo` desde o card 5.5
-- (`20260903234500_pendencias_rotinas.sql` §1), o app já o traduz ("Estoque
-- abaixo do mínimo"), já sabe a ação dele ("Ver material") e a tela de destino
-- (tela 6, `?material=<id>`) desde o card 5.8, e o `wireframes.md` §14.3 já o
-- tabela ao lado de `COMPRA_SEM_ESTOQUE` e `ESTOQUE_ZERO`. O que faltava era
-- **quem o abre** — a mesma situação que o card 8.4 encontrou para
-- `STANDBY_PROLONGADO` e `PREVISAO_VENCIDA`, e pela terceira vez a peça que
-- faltava era a primeira da cadeia.
--
-- Este card NASCEU de uma divergência registrada pelo 8.4: a nota daquele card
-- nomeava dois tipos, os dois de aluno, e este é do domínio de estoque e
-- compras. Escrevê-lo de carona teria sido escopo que ninguém pediu.
--
-- -----------------------------------------------------------------------------
-- As cinco decisões deste arquivo
-- -----------------------------------------------------------------------------
-- (1) MORA NA ROTINA, NÃO NUM TRIGGER, e aqui a razão é mais forte do que a do
--     card 8.4: a condição depende de DUAS fontes que mudam por caminhos
--     diferentes — o saldo, que só muda por `movimento_estoque`, e o
--     `estoque_minimo`, que só muda no cadastro do material (tela 6, card 6.7).
--     Um trigger em `movimento_estoque` não veria alguém SUBIR o mínimo de 1
--     para 5 no cadastro; um trigger em `material` não veria a entrega que
--     zerou a prateleira. Seriam dois gatilhos meia-condição cada, livres para
--     divergir — o defeito que o card 5.4 pagou para aprender com
--     `BLOCO_ACIMA_CAPACIDADE`. A rotina vê as duas metades todo dia, e o
--     catálogo §10.1 já dava a dona certa.
--
-- (2) LÊ `v_estoque_atual` E NÃO REFAZ A SOMA. `abaixo_minimo` é coluna da view
--     desde o card 6.4 e é o contrato do projeto para esta comparação
--     (`docs/views-leitura.md` §4.1). Repetir aqui `sum(quantidade) <
--     estoque_minimo` seria a segunda implementação da mesma conta — e a
--     primeira a divergir seria esta, porque a view é a que a tela mostra.
--
--     ⚠️ E é lendo a view que a armadilha do §3.2 do card 2.3 fica resolvida de
--        graça: `sum()` de conjunto vazio é `null`, `null < estoque_minimo` é
--        `null`, e um `join` interno em `movimento_estoque` deixaria de fora
--        justamente o material RECÉM-CADASTRADO, sem movimento nenhum — o que
--        mais precisa ser comprado. A view já faz `left join` + `coalesce`: ali
--        ele aparece com saldo 0 e `abaixo_minimo` verdadeiro. A suíte mede isso
--        com um material criado sem movimento nenhum (teste 090 §17).
--
-- (3) `estoque_minimo > 0` É FILTRO EXPLÍCITO, e não redundância. O DDL dá
--     `default 0` à coluna, e mínimo zero quer dizer "ninguém configurou um
--     mínimo para este material", não "o mínimo é zero". Sem o filtro, o único
--     jeito de um material assim entrar na lista seria com saldo NEGATIVO — que
--     é sintoma de AJUSTE errado (comentário de `v_estoque_atual.saldo`, card
--     6.4) e tem tratamento próprio na tela do 6.7. A pendência diria "abaixo do
--     mínimo de 0", que é uma frase sem sentido, e mandaria comprar em vez de
--     mandar conferir a prateleira.
--
-- (4) SÓ MATERIAL ATIVO, e esta é a exceção declarada do §2.3 do card 2.3
--     aplicada do lado certo. `v_estoque_atual` inclui material INATIVO de
--     propósito — apostila aposentada com saldo é estoque que a escola tem —,
--     mas quem fala em COMPRAR restringe a `ativo`, e é o que `v_pedido_sugerido`
--     já faz. Pendência é pedido de ação, e a ação daqui é comprar: sem o filtro,
--     aposentar uma apostila abriria uma pendência perpétua que ninguém pode
--     fechar a não ser comprando o que a escola decidiu não usar mais.
--
-- (5) ABRE **E** FECHA pela mesma reavaliação diária, com
--     `fn_pendencias_fechar_ausentes`, como os quatro blocos que já estavam
--     aqui. O catálogo §10.1 diz "fechada quando saldo ≥ mínimo", e é isso que
--     sai do `where` na execução seguinte à entrada de estoque — sem trigger de
--     fechamento, que seria a segunda implementação da comparação (card 5.4).
--     A severidade é BAIXA e a chave é `MINIMO:<material_id>`, as duas como o
--     catálogo escreve.
--
-- -----------------------------------------------------------------------------
-- O que este arquivo NÃO faz, e por quê
-- -----------------------------------------------------------------------------
-- • Não toca em `ESTOQUE_ZERO`. Os dois tipos convivem e medem coisas
--   diferentes: `ESTOQUE_ZERO` é EVENTO (uma entrega acabou de ser reordenada
--   por causa daquele material, card 6.3) e `ESTOQUE_ABAIXO_MINIMO` é ESTADO
--   (a prateleira está abaixo do que a escola decidiu manter). Um material pode
--   estar abaixo do mínimo há meses sem nunca ter atrapalhado uma entrega, e é
--   exatamente esse o caso que esta pendência existe para mostrar antes que ele
--   vire o outro.
--
-- • Nenhum `alter table`: o `check` de `pendencia.tipo` já aceita o tipo desde o
--   card 5.5, e `pendencia.material_id` já existe com índice próprio.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. rt_pendencias_diaria — o quinto bloco, e o primeiro que não é de aluno
-- -----------------------------------------------------------------------------
-- ⚠️ `create or replace` de função inteira parte da ÚLTIMA definição APLICADA,
--    não da do card que a criou (lição do card 5.7). A última é a do card 8.4
--    (`20260905233000_alertas_aluno.sql` §1), que acrescentou os dois alertas de
--    tempo do aluno, e ela está preservada abaixo palavra por palavra —
--    inclusive a seção final que registra por que `BLOCO_ACIMA_CAPACIDADE`
--    continua fora. A única mudança é o bloco novo.
--
--    Quatro asserções vigiam essa preservação e reprovam quem partir da
--    definição errada: teste 043 §4 (continua sem `BLOCO_ACIMA_CAPACIDADE` e
--    continua lendo `v_bloco_alunos`), teste 090 §13 (cita `turma_modular_aluno`
--    e exige `tm.ativo`) e as §15/§16 do 090, que medem os dois alertas do 8.4.
--
-- `security definer` como antes: a rotina roda pelo `pg_cron`, sem `auth.uid()`,
-- e a unidade vem da GUC de contexto que `rt_diaria` seta (card 2.2 §2.2).
create or replace function public.rt_pendencias_diaria()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade      uuid;
  v_chaves       text[];
  v_standby_dias integer;
  r              record;
begin
  v_unidade := public.fn_unidade_atual();

  if v_unidade is null then
    raise exception
      'rt_pendencias_diaria: sem unidade no contexto. Chamar de rt_diaria, ou entrar no contexto de rotina antes (card 2.2 §2.2).';
  end if;

  -- ---------------------------------------------------------------------------
  -- ALUNO_SEM_TURMA (ALTA) — ATIVO/ACELERAR sem bloco nem turma modular
  -- ---------------------------------------------------------------------------
  -- Alocação de tipo REP CONTA aqui, ao contrário do que acontece na aceleração:
  -- o aluno está num bloco de verdade, ocupando vaga de verdade (card 2.5 §7 #2).
  --
  -- A segunda metade — a turma Modular — entrou no card 7.1, no dia em que a
  -- tabela nasceu. "Nenhuma turma" quer dizer nenhuma das DUAS formas.
  v_chaves := '{}';

  for r in select a.id,
                  format('%s (%s) está %s e não está em nenhuma turma.',
                         a.nome, coalesce(a.codigo_sgf, 'sem código SGF'), a.status)
                    as descricao
             from public.aluno a
            where a.unidade_id = v_unidade
              and a.status in ('ATIVO', 'ACELERAR')
              and not exists (select 1
                                from public.v_bloco_alunos t
                               where t.aluno_id = a.id and t.bloco_ativo)
              and not exists (select 1
                                from public.turma_modular_aluno ta
                                join public.turma_modular tm on tm.id = ta.turma_id
                               where ta.aluno_id = a.id and ta.ativo and tm.ativo)
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
                            from public.v_bloco_alunos t
                           where t.aluno_id = a.id and t.bloco_ativo and t.tipo <> 'REP'))
                    as descricao
             from public.aluno a
            where a.unidade_id = v_unidade
              and a.status = 'ACELERAR'
              and (select count(*)
                     from public.v_bloco_alunos t
                    where t.aluno_id = a.id and t.bloco_ativo and t.tipo <> 'REP') < 2
            order by a.nome, a.id
  loop
    v_chaves := v_chaves || ('ACELERAR:' || r.id::text);
    perform public.fn_pendencia_abrir(
      'ACELERAR_SEM_2O_BLOCO', 'ACELERAR:' || r.id::text, r.descricao,
      'BAIXA', p_aluno_id => r.id);
  end loop;

  perform public.fn_pendencias_fechar_ausentes('ACELERAR_SEM_2O_BLOCO', v_chaves);

  -- ---------------------------------------------------------------------------
  -- STANDBY_PROLONGADO (MEDIA) — card 8.4, decisão (3) e (4) do cabeçalho
  -- ---------------------------------------------------------------------------
  -- `status_desde` existe para esta consulta: o card 4.2 a criou dizendo, com
  -- todas as letras, que era "para o alerta de STANDBY prolongado não precisar
  -- varrer aluno_status_hist a cada execução da rotina diária". É a coluna que
  -- `tg_aluno_status_valida` carimba a cada transição — logo, o dia em que o
  -- aluno ENTROU no status atual, e não o dia da matrícula. A fixture separa as
  -- duas de propósito (Gabriela: em STANDBY há 45 dias, matriculada há 200), e
  -- uma fixture que as igualasse passaria sem exercitar nada.
  --
  -- ⚠️ O limiar é PARÂMETRO, e ler `standby_alerta_dias` aqui é o que impede o
  --    30 de virar literal dentro da função (card 2.2 §2.3). Sem default de
  --    propósito: ver a decisão (3) do cabeçalho do card 8.4.
  --
  -- ⚠️ A borda é `>`, não `>=`: "há MAIS de N dias". Com N = 30, o aluno que
  --    completa exatamente 30 dias hoje ainda está dentro do prazo; a pendência
  --    nasce amanhã. Isto NÃO aparece em uso e não aparece em revisão de diff —
  --    o que o separa do erro é a asserção de borda do teste 090 §14.
  v_standby_dias := public.fn_param_int('standby_alerta_dias');

  v_chaves := '{}';

  for r in select a.id,
                  format('%s (%s) está em STANDBY há %s dia(s), acima dos %s configurados — avaliar trancamento.',
                         a.nome, coalesce(a.codigo_sgf, 'sem código SGF'),
                         public.fn_hoje() - a.status_desde, v_standby_dias)
                    as descricao
             from public.aluno a
            where a.unidade_id = v_unidade
              and a.status = 'STANDBY'
              and (public.fn_hoje() - a.status_desde) > v_standby_dias
            order by a.nome, a.id
  loop
    v_chaves := v_chaves || ('STANDBY:' || r.id::text);
    perform public.fn_pendencia_abrir(
      'STANDBY_PROLONGADO', 'STANDBY:' || r.id::text, r.descricao,
      'MEDIA', p_aluno_id => r.id);
  end loop;

  perform public.fn_pendencias_fechar_ausentes('STANDBY_PROLONGADO', v_chaves);

  -- ---------------------------------------------------------------------------
  -- PREVISAO_VENCIDA (MEDIA) — card 8.4
  -- ---------------------------------------------------------------------------
  -- `prev_conclusao_curso` é informada MANUALMENTE (decisão de 30/08/2026: não
  -- há regra de cálculo), e por isso ela envelhece sozinha. Data vencida é dado
  -- ERRADO, não previsão apertada — e a projeção do card 8.1 já conta com esta
  -- pendência: `v_projecao_aluno` recusa a previsão vencida como base (o passo
  -- seria negativo e despejaria a trilha inteira no mês corrente) e cai para
  -- MEDIA_METODO, deixando para uma pessoa a correção que só ela pode fazer. Sem
  -- alguém abrindo a pendência, o aluno fica projetado pelo degrau de quem não
  -- tem previsão nenhuma e ninguém nunca fica sabendo.
  --
  -- ⚠️ Só ATIVO/ACELERAR: ver "o que este arquivo NÃO faz" no cabeçalho do card
  --    8.4. É também o que faz a formatura FECHAR a pendência na execução
  --    seguinte, sem trigger nenhum — o "fechada por ... formatura" do §10.1.
  --
  -- ⚠️ A data de hoje sai de `fn_hoje()`, nunca da data do servidor: o Postgres
  --    do Supabase roda em UTC, e das 21h à meia-noite a data dele já é a de
  --    amanhã (card 2.3 §10 #1). Numa comparação de vencimento isso adianta o
  --    alerta em um dia — e a pendência apareceria à noite e sumiria de manhã.
  --
  --    ⚠️ Medido no card 8.4: o teste C6 (`011` §C6) lê `prosrc`, que **inclui os
  --    comentários do corpo** — a primeira versão desta seção citava a função
  --    proibida pelo nome, aqui, para explicar por que não se deve usá-la, e
  --    reprovou o C6. É a lição do card 4.2 no outro sentido: lá o comentário
  --    fazia um portão passar; aqui faz um portão reprovar. O nome não se
  --    escreve, nem em comentário.
  v_chaves := '{}';

  for r in select a.id,
                  format('%s (%s) está %s e a previsão de conclusão venceu em %s, há %s dia(s).',
                         a.nome, coalesce(a.codigo_sgf, 'sem código SGF'), a.status,
                         to_char(a.prev_conclusao_curso, 'DD/MM/YYYY'),
                         public.fn_hoje() - a.prev_conclusao_curso)
                    as descricao
             from public.aluno a
            where a.unidade_id = v_unidade
              and a.status in ('ATIVO', 'ACELERAR')
              and a.prev_conclusao_curso is not null
              and a.prev_conclusao_curso < public.fn_hoje()
            order by a.nome, a.id
  loop
    v_chaves := v_chaves || ('PREVISAO:' || r.id::text);
    perform public.fn_pendencia_abrir(
      'PREVISAO_VENCIDA', 'PREVISAO:' || r.id::text, r.descricao,
      'MEDIA', p_aluno_id => r.id);
  end loop;

  perform public.fn_pendencias_fechar_ausentes('PREVISAO_VENCIDA', v_chaves);

  -- ---------------------------------------------------------------------------
  -- ESTOQUE_ABAIXO_MINIMO (BAIXA) — card 8.4,5, decisões (2) a (5)
  -- ---------------------------------------------------------------------------
  -- O primeiro bloco desta rotina que não fala de aluno: a pendência é do
  -- MATERIAL, e por isso vai em `p_material_id`, que é o que faz a central do
  -- card 5.8 oferecer "Ver material" e levar para a tela 6 (`wireframes.md`
  -- §14.3). `p_aluno_id` fica nulo — não há aluno de quem cobrar nada aqui.
  --
  -- ⚠️ A comparação NÃO se repete: `abaixo_minimo` já é coluna de
  --    `v_estoque_atual` (card 6.4), e é ela que a tela de Compras mostra. Uma
  --    segunda escrita da mesma conta aqui divergiria da primeira no dia em que
  --    alguém mexesse numa só — e a que a pessoa vê é a da view.
  --
  -- ⚠️ `e.ativo` e `e.estoque_minimo > 0` são os dois filtros que a view NÃO
  --    aplica, de propósito, e que esta pendência precisa: a view fala do
  --    estoque que a escola TEM (inclusive de apostila aposentada), e a
  --    pendência fala do que a escola precisa COMPRAR. Sem o primeiro, aposentar
  --    um material abriria pendência para sempre; sem o segundo, "abaixo do
  --    mínimo de 0" apareceria para todo saldo negativo, que é conferência de
  --    prateleira, não compra. As duas contraprovas estão no teste 090 §17.
  --
  -- ⚠️ Material sem movimento NENHUM entra aqui, e é o caso que mais importa —
  --    apostila recém-cadastrada, mínimo definido, prateleira vazia. Quem o
  --    salva é o `left join` de `v_estoque_atual` (armadilha §3.2 do card 2.3):
  --    lendo `movimento_estoque` direto, ele seria justamente o que sumiria.
  v_chaves := '{}';

  for r in select e.material_id,
                  format('%s (%s %s) está com saldo %s, abaixo do mínimo de %s — avaliar compra.',
                         e.nome, me.codigo, e.codigo, e.saldo, e.estoque_minimo)
                    as descricao
             from public.v_estoque_atual e
             join public.metodo me on me.id = e.metodo_id
            where e.unidade_id = v_unidade
              and e.ativo
              and e.estoque_minimo > 0
              and e.abaixo_minimo
            order by e.nome, e.material_id
  loop
    v_chaves := v_chaves || ('MINIMO:' || r.material_id::text);
    perform public.fn_pendencia_abrir(
      'ESTOQUE_ABAIXO_MINIMO', 'MINIMO:' || r.material_id::text, r.descricao,
      'BAIXA', p_material_id => r.material_id);
  end loop;

  perform public.fn_pendencias_fechar_ausentes('ESTOQUE_ABAIXO_MINIMO', v_chaves);

  -- ---------------------------------------------------------------------------
  -- BLOCO_ACIMA_CAPACIDADE saiu daqui no card 5.4, e continua fora
  -- ---------------------------------------------------------------------------
  -- O dono é fn_revalidar_blocos_sala, como o catálogo §10.1 sempre disse, e
  -- quem a chama todo dia é rt_capacidades — que rt_diaria executa ANTES desta
  -- rotina. Manter a cópia aqui seria manter duas implementações da mesma
  -- comparação, livres para divergir na primeira vez que alguém mexer numa só.
end $$;

comment on function public.rt_pendencias_diaria() is
  'Abre E fecha, na unidade do contexto corrente, as pendências de TEMPO e de ESTADO que o catálogo §10.1 lhe dá: ALUNO_SEM_TURMA (ALTA, as duas formas de turma desde o card 7.1), ACELERAR_SEM_2O_BLOCO (BAIXA, contando só blocos de tipo <> REP), STANDBY_PROLONGADO (MEDIA, status_desde acima de standby_alerta_dias — borda >, nunca >=), PREVISAO_VENCIDA (MEDIA, prev_conclusao_curso no passado para ATIVO/ACELERAR) e ESTOQUE_ABAIXO_MINIMO (BAIXA, abaixo_minimo de v_estoque_atual, só material ATIVO e com mínimo > 0 — card 8.4,5). BLOCO_ACIMA_CAPACIDADE saiu daqui no card 5.4 e é de fn_revalidar_blocos_sala; ALUNO_ULTIMO_LIVRO é de fn_registrar_entrega (card 6.3).';

revoke execute on function public.rt_pendencias_diaria() from public;
revoke execute on function public.rt_pendencias_diaria() from anon;
revoke execute on function public.rt_pendencias_diaria() from authenticated;
