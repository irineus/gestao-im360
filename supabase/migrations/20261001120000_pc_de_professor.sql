-- =============================================================================
-- Card 9.2,77 — PC que não é lugar de aluno: a máquina do professor não conta
--               como vaga (pc.de_professor; fn_capacidade_efetiva,
--               fn_revalidar_blocos_sala, tg_pc_revalida_blocos em `pc`,
--               fn_importacao_validar e fn_importacao_aplicar)
--
-- Origem: retorno do monitor na rodada 1 de validação (30/09/2026, card 6.9):
--   "possivelmente o sistema está considerando o computador do professor como
--   computador que pode ser usado por alunos". Ele estava certo, e o defeito é
--   maior do que ele disse — medido no dev em 30/09/2026:
--
--   A sala Tecnologia/Inglês tem 11 PCs (PC-01..PC-10 + PC-PROFESSOR) e
--   capacidade_nominal = 10. A fórmula do card 5.2 é
--   coalesce(override, least(PCs disponíveis, nominal)):
--     • todos operacionais: least(11, 10) = 10 — a nominal ESCONDE o problema;
--     • UM PC de aluno parado: least(10, 10) = 10 — a capacidade NÃO CAI,
--       porque a máquina do professor tapa o buraco;
--     • DOIS parados: least(9, 10) = 9, quando os lugares de aluno são 8.
--   O sistema erra por exatamente UM a partir da primeira quebra, em silêncio,
--   e no sentido de admitir aluno a mais.
--
-- Decisão (resposta do monitor, 30/09/2026): "Somente o do professor; outros
-- computadores só ficarão indisponíveis em caso de manutenção." Logo a marcação
-- BOOLEANA basta — nem tipo de PC nem categoria.
--
-- ⚠️ ESTRUTURA E MAIS NADA (portão do card 4.0,5): a coluna nasce `false` em
--    toda linha, que é o valor de "é lugar de aluno" — a migração não marca PC
--    nenhum. Quem marca o PC-PROFESSOR do homolog é uma pessoa com
--    `salas.editar`, pela tela de Salas e PCs, depois que o lote for liberado.
--
-- ⚠️ TODAS AS FUNÇÕES AQUI SÃO REESCRITAS A PARTIR DA ÚLTIMA DEFINIÇÃO APLICADA
--    (lição do card 5.7: partir de um corpo antigo reintroduz o que já foi
--    removido, e nada no diff parece errado):
--      • fn_capacidade_efetiva e fn_revalidar_blocos_sala — 20260904010000
--        (card 5.4), nenhuma definição posterior;
--      • fn_importacao_validar e fn_importacao_aplicar — 20260924150000
--        (card 9.2,68), nenhuma definição posterior.
--    Fora a linha marcada com "card 9.2,77" em cada uma, os corpos são cópia.
--
-- ---------------------------------------------------------------------------
-- O QUE ESTE CARD **NÃO** ESCREVEU, e por que não é esquecimento
-- ---------------------------------------------------------------------------
-- (a) Nenhuma unique "um PC de professor por sala". O monitor descreveu a sala
--     de hoje, não uma regra: uma escola com duas máquinas de professor numa
--     sala não está errada, e a constraint recusaria o cadastro dela.
--
-- (b) O PC do professor usado como SUBSTITUTO de um PC de aluno da MESMA sala
--     continua não repondo a vaga. A fórmula do card 5.2 diz que substituto da
--     própria sala "já estava contado" — o que deixa de ser verdade para a
--     máquina do professor, que agora não conta. Tratar o caso exigiria mexer
--     nas duas cláusulas da fórmula e na condição de PC_SEM_SUBSTITUTO, por um
--     uso que o monitor disse que NÃO quer (ele precisa da máquina livre). O
--     efeito de não tratar é conservador — a capacidade fica caída e a
--     pendência diz "sem PC substituto de outra sala", que é literalmente o
--     caso —, e nunca vende vaga que não existe. Registrado, não seguido em
--     silêncio.
--
-- (c) `after insert on pc` continua fora (decisão do card 5.4): um PC novo
--     marcado como do professor não muda capacidade nenhuma, e um PC de aluno
--     novo só AUMENTA a capacidade, o que a rotina das 03:10 alcança.
--
-- A migração só será aplicada no dev quando o lote/rodada-1 for liberado para
-- `develop`; até lá vive no lote, exercitada pelo `testes.yml` do PR.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. pc.de_professor
-- -----------------------------------------------------------------------------
-- Positiva no nome e negativa no efeito: `true` diz o que a máquina É (a do
-- professor), e o efeito é ela NÃO ser lugar de aluno. O default `false` é o
-- caso de todo PC que existe hoje e de todo PC que nascer sem que alguém diga
-- o contrário — o que mantém a capacidade de toda sala exatamente como estava
-- até que alguém marque a máquina.
alter table public.pc
  add column de_professor boolean not null default false;

comment on column public.pc.de_professor is
  'A máquina do professor: NÃO é lugar de aluno e não conta na capacidade efetiva da sala (fn_capacidade_efetiva), nem abre PC_SEM_SUBSTITUTO quando para. Default false = lugar de aluno. Editável por quem tem salas.editar (tela de Salas e PCs) e pelo importador (chave opcional `de_professor` da entidade pc; ausente preserva o valor gravado). Card 9.2,77, resposta do monitor de 30/09/2026.';

-- -----------------------------------------------------------------------------
-- 2. fn_capacidade_efetiva — a máquina do professor sai da contagem
-- -----------------------------------------------------------------------------
-- Corpo do card 5.4 (20260904010000 §0), com UMA cláusula a mais, a (0). As três
-- cláusulas do card 5.2, o `least` com a nominal, o intervalo `[data_inicio,
-- data_fim)` e o `capacidade_override` continuam idênticos.
--
-- ⚠️ A cláusula entra no `count`, ANTES do `least`, e é por isso que ela muda o
--    número: com 11 PCs e nominal 10, tirar o do professor DEPOIS do `least`
--    (por exemplo, `least(...) - 1`) faria a sala com tudo operacional cair
--    para 9, que é falso — os lugares de aluno são 10.
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
                 -- (0) lugar de aluno: a máquina do professor nunca conta
                 --     (card 9.2,77).
                 and not p.de_professor
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
  'Capacidade do bloco na data: capacidade_override, ou mín(PCs de aluno disponíveis da sala, capacidade_nominal). O PC do professor (pc.de_professor) nunca conta — card 9.2,77; PC DESATIVADO nunca conta; manutenção sem substituto derruba; substituto de OUTRA sala repõe (o da própria sala já estava contado). A manutenção cobre [data_inicio, data_fim): data_fim é o dia em que o PC VOLTA a operar (card 5.4). NULO quando o bloco não é da unidade corrente. Card 5.2 é o dono da fórmula.';

-- -----------------------------------------------------------------------------
-- 3. fn_revalidar_blocos_sala — a máquina do professor parada não "derruba a
--    capacidade da sala"
-- -----------------------------------------------------------------------------
-- Corpo do card 5.4 (20260904010000 §3), com UMA condição a mais em `parado`.
-- A mensagem de PC_SEM_SUBSTITUTO termina em "a capacidade da sala caiu" — o
-- que, para a máquina do professor, passou a ser falso: ela não conta na
-- capacidade, então parada ela não derruba nada. Aberta, seria a pendência
-- falsa que ensina a central a ser ignorada.
--
-- ⚠️ O PC do professor continua sendo PERCORRIDO, como o DESATIVADO: é o `else`
--    do laço que FECHA a pendência que ele tinha aberto antes de ser marcado. O
--    PC-PROFESSOR do homolog pode ter uma hoje; marcá-lo na tela a fecha na hora
--    (seção 4), e pulá-lo no `where` a deixaria aberta para sempre.
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
  -- uma revalidação que nunca mais olharia para ele. O PC do professor segue a
  -- mesma forma, pelo mesmo motivo (card 9.2,77).
  for r in select p.id, p.identificador,
                  (not p.de_professor          -- card 9.2,77: não é lugar de aluno
                   and p.status <> 'DESATIVADO'
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
  'Revalida a sala: abre ou fecha BLOCO_ACIMA_CAPACIDADE (ALTA, chave CAPACIDADE:<bloco_id>) para cada bloco ativo e PC_SEM_SUBSTITUTO (MEDIA, chave PC_SEM_SUBST:<pc_id>) para cada PC de aluno parado sem substituto de outra sala — o PC do professor (pc.de_professor, card 9.2,77) não abre, porque parado não derruba capacidade nenhuma. Devolve quantos blocos ficaram acima; NULO para sala de outra unidade. Nunca remove aluno (card 2.2 §4.6): a turma cheia não encolhe, vira pendência, e a admissão nova já é recusada por tg_bloco_aluno_admissao.';

-- -----------------------------------------------------------------------------
-- 4. tg_pc_revalida_blocos em `pc` — marcar a máquina é EVENTO de capacidade
-- -----------------------------------------------------------------------------
-- O gatilho do card 5.4 ouvia `update of status, sala_id`. Marcar (ou
-- desmarcar) o PC do professor muda a capacidade da sala tanto quanto mudar o
-- status — e sem a coluna na lista, a marcação feita na tela deixaria a
-- pendência BLOCO_ACIMA_CAPACIDADE (e o PC_SEM_SUBSTITUTO do próprio PC do
-- professor) como estavam até as 03:10 do dia seguinte. A função não muda: ela
-- já revalida a sala do `new` para qualquer update em `pc`.
drop trigger tg_pc_revalida_blocos on public.pc;

create trigger tg_pc_revalida_blocos
  after update of status, sala_id, de_professor on public.pc
  for each row execute function public.fn_pc_revalida_blocos();

-- -----------------------------------------------------------------------------
-- 5. Importador (card 9.1) — a entidade `pc` aceita `de_professor`
-- -----------------------------------------------------------------------------
-- docs/importacao.md §3: chave OPCIONAL, booleana JSON (`true`/`false`).
--   • fn_importacao_validar, V3: valor que não seja true/false é ERRO
--     VALOR_INVALIDO — sem isso, `"sim"` chegaria ao cast da aplicação e
--     derrubaria o lote inteiro com 22P02 cru, que é o erro que o card 2.2 §1.2
--     proíbe em tela;
--   • fn_importacao_aplicar, passo 3: PC novo nasce com o valor do arquivo (ou
--     false); PC que já existe só muda quando o arquivo TRAZ a chave.
--
-- ⚠️ "Ausente é não sei" (card 9.2, §1 das Decisões vigentes). O extrator do
--    9.2 não emite a chave — a aba PCS nem tem mapa —, e um `on conflict do
--    update set de_professor = excluded.de_professor` faria a reimportação de
--    um arquivo sem ela DESMARCAR, em silêncio, o PC que alguém marcou na tela:
--    o defeito deste card de volta, sem nada no relatório. Por isso a chave sai
--    do upsert e vira um `update` próprio, só para as linhas que a trazem.

create or replace function public.fn_importacao_validar(p_importacao_id uuid)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade  uuid;
  v_snapshot date;
  v_dados    jsonb;
  v_d        jsonb;
  v_entidades constant text[] := array[
    'professor','sala','pc','pc_manutencao','material','curso','curso_material',
    'modulo','combo','combo_curso','aluno','bloco_horario','bloco_aluno',
    'turma_modular','turma_modular_modulo','turma_modular_aluno',
    'aluno_material','movimento_estoque'];
begin
  -- Card 9.2,68: o conjunto da rota 13, como em registrar e aplicar. Antes da
  -- leitura do lote: sem ele, quem não pode importar ouvia "não encontrada"
  -- (a RLS esconde o lote) em vez de SEM_PERMISSAO.
  perform public.fn_importacao_exigir();

  select i.unidade_id, i.snapshot_em, i.dados
    into v_unidade, v_snapshot, v_dados
    from public.importacao i
   where i.id = p_importacao_id;

  if v_unidade is null then
    raise exception using
      errcode = 'PT404',
      message = 'Esta importação não foi encontrada.',
      detail  = json_build_object('codigo', 'IMPORTACAO_INEXISTENTE',
                                  'importacao', p_importacao_id)::text;
  end if;

  -- Card 9.2,68: a validação roda UMA vez, dentro de fn_importacao_registrar,
  -- sobre o lote que acabou de nascer (sem ocorrência e sem totais). Chamada de
  -- novo — direto pelo PostgREST, que o grant para authenticated permite —
  -- ela DUPLICAVA todas as ocorrências, inclusive em lote já APLICADO, e o
  -- relatório do passo 3 passava a contar cada erro duas vezes. Validar de
  -- novo é enviar o arquivo de novo, pelo mesmo motivo de IMPORTACAO_JA_APLICADA:
  -- o histórico de tentativas é o que explica o que mudou entre uma e outra.
  if exists (select 1 from public.importacao i
              where i.id = p_importacao_id
                and (i.totais is not null or i.status in ('APLICADA', 'FALHOU')))
     or exists (select 1 from public.importacao_ocorrencia o
                 where o.importacao_id = p_importacao_id) then
    raise exception using
      errcode = 'PT409',
      message = 'Esta importação já foi validada. Para validar de novo, envie o arquivo de novo.',
      detail  = json_build_object('codigo', 'IMPORTACAO_JA_VALIDADA',
                                  'importacao', p_importacao_id)::text;
  end if;

  -- V1 — estrutura. Toda entidade conhecida vira array (ausente ou torta vira
  -- vazia) para o resto da função não precisar se defender a cada consulta.
  select coalesce(jsonb_object_agg(e.nome,
           case when jsonb_typeof(v_dados -> e.nome) = 'array'
                then v_dados -> e.nome else '[]'::jsonb end), '{}'::jsonb)
    into v_d
    from unnest(v_entidades) e(nome);

  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', e.nome, 'ENTIDADE_INVALIDA',
         format('A entidade "%s" veio no arquivo mas não é uma lista.', e.nome),
         jsonb_typeof(v_dados -> e.nome)
    from unnest(v_entidades) e(nome)
   where v_dados ? e.nome and jsonb_typeof(v_dados -> e.nome) <> 'array';

  -- Chave desconhecida é AVISO e não silêncio: é assim que se descobre que o
  -- extrator do card 9.2 renomeou uma aba e a importação passou por cima dela.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'AVISO', k.chave, 'ENTIDADE_DESCONHECIDA',
         format('O arquivo traz "%s", que a importação não conhece — foi ignorada.', k.chave),
         null
    from jsonb_object_keys(v_dados) k(chave)
   where not (k.chave = any (v_entidades))
     and k.chave <> 'snapshot_em';

  -- V2 — campos obrigatórios, entidade a entidade.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', x.entidade, x.n, 'CAMPO_OBRIGATORIO',
         format('%s: o campo "%s" está vazio.', x.entidade, x.campo), null
    from (
      select 'professor' as entidade, e.n, 'nome' as campo, e.j ->> 'nome' as valor
        from jsonb_array_elements(v_d -> 'professor') with ordinality e(j, n)
      union all select 'sala', e.n, 'nome', e.j ->> 'nome'
        from jsonb_array_elements(v_d -> 'sala') with ordinality e(j, n)
      union all select 'sala', e.n, 'tipo', e.j ->> 'tipo'
        from jsonb_array_elements(v_d -> 'sala') with ordinality e(j, n)
      union all select 'pc', e.n, 'identificador', e.j ->> 'identificador'
        from jsonb_array_elements(v_d -> 'pc') with ordinality e(j, n)
      union all select 'pc', e.n, 'sala', e.j ->> 'sala'
        from jsonb_array_elements(v_d -> 'pc') with ordinality e(j, n)
      union all select 'pc_manutencao', e.n, 'pc', e.j ->> 'pc'
        from jsonb_array_elements(v_d -> 'pc_manutencao') with ordinality e(j, n)
      union all select 'material', e.n, 'codigo', e.j ->> 'codigo'
        from jsonb_array_elements(v_d -> 'material') with ordinality e(j, n)
      union all select 'material', e.n, 'nome', e.j ->> 'nome'
        from jsonb_array_elements(v_d -> 'material') with ordinality e(j, n)
      union all select 'material', e.n, 'categoria', e.j ->> 'categoria'
        from jsonb_array_elements(v_d -> 'material') with ordinality e(j, n)
      union all select 'material', e.n, 'metodo', e.j ->> 'metodo'
        from jsonb_array_elements(v_d -> 'material') with ordinality e(j, n)
      union all select 'curso', e.n, 'nome', e.j ->> 'nome'
        from jsonb_array_elements(v_d -> 'curso') with ordinality e(j, n)
      union all select 'curso', e.n, 'metodo', e.j ->> 'metodo'
        from jsonb_array_elements(v_d -> 'curso') with ordinality e(j, n)
      union all select 'combo', e.n, 'nome', e.j ->> 'nome'
        from jsonb_array_elements(v_d -> 'combo') with ordinality e(j, n)
      union all select 'combo', e.n, 'metodo', e.j ->> 'metodo'
        from jsonb_array_elements(v_d -> 'combo') with ordinality e(j, n)
      union all select 'aluno', e.n, 'codigo', e.j ->> 'codigo'
        from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
      union all select 'aluno', e.n, 'nome', e.j ->> 'nome'
        from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
      union all select 'aluno', e.n, 'metodo', e.j ->> 'metodo'
        from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
      union all select 'turma_modular', e.n, 'nome', e.j ->> 'nome'
        from jsonb_array_elements(v_d -> 'turma_modular') with ordinality e(j, n)
      union all select 'movimento_estoque', e.n, 'chave', e.j ->> 'chave'
        from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
      union all select 'movimento_estoque', e.n, 'tipo', e.j ->> 'tipo'
        from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
    ) x
   where nullif(btrim(coalesce(x.valor, '')), '') is null;

  -- V3 — enumerações. Fora do check da coluna, o insert morreria com 23514 cru,
  -- que é o erro que o card 2.2 §1.2 proíbe em tela.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', x.entidade, x.n, 'VALOR_INVALIDO',
         format('%s: "%s" não é um valor aceito para %s (use %s).',
                x.entidade, x.valor, x.campo, x.aceitos), x.valor
    from (
      select 'sala' as entidade, e.n, 'tipo' as campo, e.j ->> 'tipo' as valor,
             'LABORATORIO ou SALA_MODULAR' as aceitos,
             (e.j ->> 'tipo') = any (array['LABORATORIO','SALA_MODULAR']) as ok
        from jsonb_array_elements(v_d -> 'sala') with ordinality e(j, n)
      union all
      select 'pc', e.n, 'status', e.j ->> 'status',
             'OPERACIONAL, MANUTENCAO ou DESATIVADO',
             coalesce(e.j ->> 'status', 'OPERACIONAL')
               = any (array['OPERACIONAL','MANUTENCAO','DESATIVADO'])
        from jsonb_array_elements(v_d -> 'pc') with ordinality e(j, n)
      union all
      -- card 9.2,77: chave opcional e booleana; ausente ou null não é avaliada
      -- (o `where` de baixo exige valor), e o que não for true/false é ERRO
      -- aqui em vez de 22P02 no cast da aplicação.
      select 'pc', e.n, 'de_professor', e.j ->> 'de_professor',
             'true ou false',
             (e.j ->> 'de_professor') = any (array['true','false'])
        from jsonb_array_elements(v_d -> 'pc') with ordinality e(j, n)
      union all
      select 'pc_manutencao', e.n, 'tipo', e.j ->> 'tipo',
             'PREVENTIVA, CORRETIVA ou CONFIGURACAO',
             coalesce(e.j ->> 'tipo', 'CORRETIVA')
               = any (array['PREVENTIVA','CORRETIVA','CONFIGURACAO'])
        from jsonb_array_elements(v_d -> 'pc_manutencao') with ordinality e(j, n)
      union all
      select 'aluno', e.n, 'status', e.j ->> 'status',
             'ATIVO, ACELERAR, STANDBY, TRANCADO, CANCELADO ou FORMADO',
             coalesce(e.j ->> 'status', 'ATIVO') = any (array['ATIVO','ACELERAR',
               'STANDBY','TRANCADO','CANCELADO','FORMADO'])
        from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
      union all
      select 'bloco_aluno', e.n, 'tipo', e.j ->> 'tipo',
             'REM, PRE, REP ou NOVO',
             (e.j ->> 'tipo') = any (array['REM','PRE','REP','NOVO'])
        from jsonb_array_elements(v_d -> 'bloco_aluno') with ordinality e(j, n)
      union all
      select 'aluno_material', e.n, 'origem', e.j ->> 'origem',
             'COMBO ou MANUAL',
             coalesce(e.j ->> 'origem', 'COMBO') = any (array['COMBO','MANUAL'])
        from jsonb_array_elements(v_d -> 'aluno_material') with ordinality e(j, n)
      union all
      -- ESTORNO fica fora de propósito: estorno migrado seria um estorno sem
      -- movimento de origem no sistema, e movimento_estorno_ck o recusaria.
      select 'movimento_estoque', e.n, 'tipo', e.j ->> 'tipo',
             'ENTRADA, SAIDA ou AJUSTE',
             (e.j ->> 'tipo') = any (array['ENTRADA','SAIDA','AJUSTE'])
        from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
      union all
      select x2.entidade, x2.n, 'metodo', x2.valor,
             'INTERATIVO, INGLES ou MODULAR',
             x2.valor = any (array['INTERATIVO','INGLES','MODULAR'])
        from (
          select 'material' as entidade, e.n, e.j ->> 'metodo' as valor
            from jsonb_array_elements(v_d -> 'material') with ordinality e(j, n)
          union all select 'curso', e.n, e.j ->> 'metodo'
            from jsonb_array_elements(v_d -> 'curso') with ordinality e(j, n)
          union all select 'combo', e.n, e.j ->> 'metodo'
            from jsonb_array_elements(v_d -> 'combo') with ordinality e(j, n)
          union all select 'aluno', e.n, e.j ->> 'metodo'
            from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
          union all select 'bloco_horario', e.n, e.j ->> 'metodo'
            from jsonb_array_elements(v_d -> 'bloco_horario') with ordinality e(j, n)
        ) x2
    ) x
   where not x.ok and x.valor is not null;

  -- V4 — datas e horas preenchidas que não convertem.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', x.entidade, x.n, 'DATA_INVALIDA',
         format('%s: "%s" não é uma data válida em %s (esperado AAAA-MM-DD).',
                x.entidade, x.valor, x.campo), x.valor
    from (
      select 'aluno' as entidade, e.n, 'data_inicio' as campo, e.j ->> 'data_inicio' as valor
        from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
      union all select 'aluno', e.n, 'prev_conclusao_curso', e.j ->> 'prev_conclusao_curso'
        from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
      union all select 'aluno_material', e.n, 'data_entrega', e.j ->> 'data_entrega'
        from jsonb_array_elements(v_d -> 'aluno_material') with ordinality e(j, n)
      union all select 'turma_modular', e.n, 'data_inicio', e.j ->> 'data_inicio'
        from jsonb_array_elements(v_d -> 'turma_modular') with ordinality e(j, n)
      union all select 'turma_modular_aluno', e.n, 'data_entrada', e.j ->> 'data_entrada'
        from jsonb_array_elements(v_d -> 'turma_modular_aluno') with ordinality e(j, n)
      union all select 'pc_manutencao', e.n, 'data_inicio', e.j ->> 'data_inicio'
        from jsonb_array_elements(v_d -> 'pc_manutencao') with ordinality e(j, n)
      union all select 'movimento_estoque', e.n, 'ocorrido_em', e.j ->> 'ocorrido_em'
        from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
    ) x
   where nullif(btrim(coalesce(x.valor, '')), '') is not null
     and public.fn_importacao_data(x.valor) is null;

  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', 'bloco_horario', e.n, 'DATA_INVALIDA',
         format('bloco_horario: "%s" não é uma hora válida (esperado HH:MM).',
                e.j ->> 'hora_inicio'), e.j ->> 'hora_inicio'
    from jsonb_array_elements(v_d -> 'bloco_horario') with ordinality e(j, n)
   where public.fn_importacao_hora(e.j ->> 'hora_inicio') is null;

  -- V5 — números fora de faixa, pela mesma razão do V3.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', x.entidade, x.n, 'VALOR_INVALIDO',
         format('%s: %s inválido em "%s".', x.entidade,
                coalesce(x.valor, '(vazio)'), x.campo), x.valor
    from (
      select 'sala' as entidade, e.n, 'capacidade_nominal' as campo,
             e.j ->> 'capacidade_nominal' as valor,
             coalesce(public.fn_importacao_int(e.j ->> 'capacidade_nominal'), 0) > 0 as ok
        from jsonb_array_elements(v_d -> 'sala') with ordinality e(j, n)
      union all
      select 'turma_modular', e.n, 'capacidade', e.j ->> 'capacidade',
             coalesce(public.fn_importacao_int(e.j ->> 'capacidade'), 0) > 0
        from jsonb_array_elements(v_d -> 'turma_modular') with ordinality e(j, n)
      union all
      select 'curso_material', e.n, 'ordem', e.j ->> 'ordem',
             coalesce(public.fn_importacao_int(e.j ->> 'ordem'), 0) > 0
        from jsonb_array_elements(v_d -> 'curso_material') with ordinality e(j, n)
      union all
      select 'modulo', e.n, 'ordem', e.j ->> 'ordem',
             coalesce(public.fn_importacao_int(e.j ->> 'ordem'), 0) > 0
        from jsonb_array_elements(v_d -> 'modulo') with ordinality e(j, n)
      union all
      select 'combo_curso', e.n, 'ordem', e.j ->> 'ordem',
             coalesce(public.fn_importacao_int(e.j ->> 'ordem'), 0) > 0
        from jsonb_array_elements(v_d -> 'combo_curso') with ordinality e(j, n)
      union all
      select 'aluno_material', e.n, 'ordem', e.j ->> 'ordem',
             coalesce(public.fn_importacao_int(e.j ->> 'ordem'), 0) > 0
        from jsonb_array_elements(v_d -> 'aluno_material') with ordinality e(j, n)
      union all
      select 'movimento_estoque', e.n, 'quantidade', e.j ->> 'quantidade',
             coalesce(public.fn_importacao_int(e.j ->> 'quantidade'), 0) <> 0
        from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
      union all
      select 'bloco_horario', e.n, 'dia_semana', e.j ->> 'dia_semana',
             coalesce(public.fn_importacao_int(e.j ->> 'dia_semana'), 0) between 1 and 7
        from jsonb_array_elements(v_d -> 'bloco_horario') with ordinality e(j, n)
      union all
      select 'bloco_aluno', e.n, 'dia_semana', e.j ->> 'dia_semana',
             coalesce(public.fn_importacao_int(e.j ->> 'dia_semana'), 0) between 1 and 7
        from jsonb_array_elements(v_d -> 'bloco_aluno') with ordinality e(j, n)
    ) x
   where not x.ok;

  -- V5.1 — o sinal do movimento (movimento_sinal_ck no DDL). Chegar ao check
  -- custaria a transação inteira por um sinal trocado na planilha.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', 'movimento_estoque', e.n, 'VALOR_INVALIDO',
         format('movimento_estoque: %s com quantidade %s — ENTRADA é positiva e SAIDA é negativa.',
                e.j ->> 'tipo', e.j ->> 'quantidade'), e.j ->> 'quantidade'
    from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
   where public.fn_importacao_int(e.j ->> 'quantidade') is not null
     and ((e.j ->> 'tipo' = 'ENTRADA' and public.fn_importacao_int(e.j ->> 'quantidade') < 0)
       or (e.j ->> 'tipo' = 'SAIDA'   and public.fn_importacao_int(e.j ->> 'quantidade') > 0));

  -- V6 — chave duplicada DENTRO do arquivo. Sem esta, a segunda linha venceria a
  -- primeira no `on conflict do update` e a importação diria "aplicadas: 2".
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', x.entidade, 'CHAVE_DUPLICADA',
         format('%s: a chave "%s" aparece %s vezes no arquivo.',
                x.entidade, x.chave, x.vezes), x.chave
    from (
      select entidade, chave, count(*) as vezes
        from (
          select 'professor' as entidade, btrim(e.j ->> 'nome') as chave
            from jsonb_array_elements(v_d -> 'professor') e(j)
          union all select 'sala', btrim(e.j ->> 'nome')
            from jsonb_array_elements(v_d -> 'sala') e(j)
          union all select 'pc', btrim(e.j ->> 'identificador')
            from jsonb_array_elements(v_d -> 'pc') e(j)
          union all select 'material',
                 concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'codigo'))
            from jsonb_array_elements(v_d -> 'material') e(j)
          union all select 'curso',
                 concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'nome'))
            from jsonb_array_elements(v_d -> 'curso') e(j)
          union all select 'combo', btrim(e.j ->> 'nome')
            from jsonb_array_elements(v_d -> 'combo') e(j)
          union all select 'aluno', btrim(e.j ->> 'codigo')
            from jsonb_array_elements(v_d -> 'aluno') e(j)
          union all select 'bloco_horario',
                 concat_ws('/', btrim(e.j ->> 'sala'), e.j ->> 'dia_semana',
                           e.j ->> 'hora_inicio')
            from jsonb_array_elements(v_d -> 'bloco_horario') e(j)
          union all select 'turma_modular', btrim(e.j ->> 'nome')
            from jsonb_array_elements(v_d -> 'turma_modular') e(j)
          union all select 'aluno_material',
                 concat_ws('/', btrim(e.j ->> 'aluno'), e.j ->> 'metodo',
                           btrim(e.j ->> 'material'))
            from jsonb_array_elements(v_d -> 'aluno_material') e(j)
          union all select 'movimento_estoque', btrim(e.j ->> 'chave')
            from jsonb_array_elements(v_d -> 'movimento_estoque') e(j)
        ) t
       where nullif(chave, '') is not null
       group by entidade, chave
      having count(*) > 1
    ) x;

  -- V7 — referência que não resolve, nem no arquivo nem no banco.
  --
  -- Um `left join` contra a lista DISTINTA do que existe, e não um `exists`
  -- correlacionado por linha: com 4 mil movimentos e 200 materiais, o
  -- correlacionado é produto cartesiano e a validação estoura o
  -- `statement_timeout` do PostgREST antes de dizer qualquer coisa.
  --
  -- «Nem no arquivo nem no banco» é a parte que importa: numa reimportação o
  -- material já está no banco e não precisa vir de novo no arquivo, e numa
  -- carga do zero ele vem no mesmo arquivo, algumas entidades acima. Olhar só
  -- para um dos dois lados reprovaria metade das cargas legítimas.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', r.entidade, r.n, 'REFERENCIA_AUSENTE',
         format('%s: %s "%s" não existe no arquivo nem no sistema.',
                r.entidade, r.alvo, r.chave), r.chave
    from (
      select 'pc' as entidade, e.n, 'sala' as alvo, btrim(e.j ->> 'sala') as chave
        from jsonb_array_elements(v_d -> 'pc') with ordinality e(j, n)
      union all select 'pc_manutencao', e.n, 'pc', btrim(e.j ->> 'pc')
        from jsonb_array_elements(v_d -> 'pc_manutencao') with ordinality e(j, n)
      union all select 'curso_material', e.n, 'curso',
             concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'curso'))
        from jsonb_array_elements(v_d -> 'curso_material') with ordinality e(j, n)
      union all select 'curso_material', e.n, 'material',
             concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'material'))
        from jsonb_array_elements(v_d -> 'curso_material') with ordinality e(j, n)
      union all select 'modulo', e.n, 'curso',
             concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'curso'))
        from jsonb_array_elements(v_d -> 'modulo') with ordinality e(j, n)
      union all select 'modulo', e.n, 'material',
             concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'material'))
        from jsonb_array_elements(v_d -> 'modulo') with ordinality e(j, n)
      union all select 'combo_curso', e.n, 'combo', btrim(e.j ->> 'combo')
        from jsonb_array_elements(v_d -> 'combo_curso') with ordinality e(j, n)
      union all select 'combo_curso', e.n, 'curso',
             concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'curso'))
        from jsonb_array_elements(v_d -> 'combo_curso') with ordinality e(j, n)
      union all select 'aluno', e.n, 'combo', btrim(e.j ->> 'combo')
        from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
      union all select 'bloco_horario', e.n, 'sala', btrim(e.j ->> 'sala')
        from jsonb_array_elements(v_d -> 'bloco_horario') with ordinality e(j, n)
      union all select 'bloco_horario', e.n, 'professor', btrim(e.j ->> 'professor')
        from jsonb_array_elements(v_d -> 'bloco_horario') with ordinality e(j, n)
      union all select 'bloco_aluno', e.n, 'aluno', btrim(e.j ->> 'aluno')
        from jsonb_array_elements(v_d -> 'bloco_aluno') with ordinality e(j, n)
      union all select 'bloco_aluno', e.n, 'bloco',
             concat_ws('/', btrim(e.j ->> 'sala'), e.j ->> 'dia_semana',
                       public.fn_importacao_hora(e.j ->> 'hora_inicio')::text)
        from jsonb_array_elements(v_d -> 'bloco_aluno') with ordinality e(j, n)
      union all select 'turma_modular', e.n, 'curso',
             concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'curso'))
        from jsonb_array_elements(v_d -> 'turma_modular') with ordinality e(j, n)
      union all select 'turma_modular', e.n, 'sala', btrim(e.j ->> 'sala')
        from jsonb_array_elements(v_d -> 'turma_modular') with ordinality e(j, n)
      union all select 'turma_modular_modulo', e.n, 'turma', btrim(e.j ->> 'turma')
        from jsonb_array_elements(v_d -> 'turma_modular_modulo') with ordinality e(j, n)
      union all select 'turma_modular_modulo', e.n, 'modulo',
             concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'curso'),
                       e.j ->> 'modulo_ordem')
        from jsonb_array_elements(v_d -> 'turma_modular_modulo') with ordinality e(j, n)
      union all select 'turma_modular_aluno', e.n, 'turma', btrim(e.j ->> 'turma')
        from jsonb_array_elements(v_d -> 'turma_modular_aluno') with ordinality e(j, n)
      union all select 'turma_modular_aluno', e.n, 'aluno', btrim(e.j ->> 'aluno')
        from jsonb_array_elements(v_d -> 'turma_modular_aluno') with ordinality e(j, n)
      union all select 'aluno_material', e.n, 'aluno', btrim(e.j ->> 'aluno')
        from jsonb_array_elements(v_d -> 'aluno_material') with ordinality e(j, n)
      union all select 'aluno_material', e.n, 'material',
             concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'material'))
        from jsonb_array_elements(v_d -> 'aluno_material') with ordinality e(j, n)
      union all select 'movimento_estoque', e.n, 'material',
             concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'material'))
        from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
      union all select 'movimento_estoque', e.n, 'aluno', btrim(e.j ->> 'aluno')
        from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
    ) r
    left join (
      select distinct alvo, chave from (
        select 'professor' as alvo, btrim(e.j ->> 'nome') as chave
          from jsonb_array_elements(v_d -> 'professor') e(j)
        union all select 'professor', p.nome
          from public.professor p where p.unidade_id = v_unidade
        union all select 'sala', btrim(e.j ->> 'nome')
          from jsonb_array_elements(v_d -> 'sala') e(j)
        union all select 'sala', s.nome
          from public.sala s where s.unidade_id = v_unidade
        union all select 'pc', btrim(e.j ->> 'identificador')
          from jsonb_array_elements(v_d -> 'pc') e(j)
        union all select 'pc', c.identificador
          from public.pc c where c.unidade_id = v_unidade
        union all select 'material',
               concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'codigo'))
          from jsonb_array_elements(v_d -> 'material') e(j)
        union all select 'material', concat_ws('/', mo.codigo, m.codigo)
          from public.material m
          join public.metodo mo on mo.id = m.metodo_id
         where m.unidade_id = v_unidade
        union all select 'curso',
               concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'nome'))
          from jsonb_array_elements(v_d -> 'curso') e(j)
        union all select 'curso', concat_ws('/', mo.codigo, c.nome)
          from public.curso c
          join public.metodo mo on mo.id = c.metodo_id
         where c.unidade_id = v_unidade
        union all select 'combo', btrim(e.j ->> 'nome')
          from jsonb_array_elements(v_d -> 'combo') e(j)
        union all select 'combo', cb.nome
          from public.combo cb where cb.unidade_id = v_unidade
        union all select 'aluno', btrim(e.j ->> 'codigo')
          from jsonb_array_elements(v_d -> 'aluno') e(j)
        union all select 'aluno', a.codigo_sgf
          from public.aluno a
         where a.unidade_id = v_unidade and a.codigo_sgf is not null
        union all select 'bloco',
               concat_ws('/', btrim(e.j ->> 'sala'), e.j ->> 'dia_semana',
                         public.fn_importacao_hora(e.j ->> 'hora_inicio')::text)
          from jsonb_array_elements(v_d -> 'bloco_horario') e(j)
        union all select 'bloco',
               concat_ws('/', s.nome, b.dia_semana::text, b.hora_inicio::text)
          from public.bloco_horario b
          join public.sala s on s.id = b.sala_id
         where b.unidade_id = v_unidade
        union all select 'turma', btrim(e.j ->> 'nome')
          from jsonb_array_elements(v_d -> 'turma_modular') e(j)
        union all select 'turma', t.nome
          from public.turma_modular t where t.unidade_id = v_unidade
        union all select 'modulo',
               concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'curso'),
                         e.j ->> 'ordem')
          from jsonb_array_elements(v_d -> 'modulo') e(j)
        union all select 'modulo',
               concat_ws('/', mo.codigo, c.nome, md.ordem::text)
          from public.modulo md
          join public.curso c  on c.id = md.curso_id
          join public.metodo mo on mo.id = c.metodo_id
         where md.unidade_id = v_unidade
      ) t
    ) d on d.alvo = r.alvo and d.chave = r.chave
   where nullif(btrim(coalesce(r.chave, '')), '') is not null
     and d.chave is null;

  -- V8 — método do aluno diferente do método do bloco. É o METODO_INCOMPATIVEL
  -- de fn_bloco_aluno_admissao, antecipado para TODAS as linhas de uma vez: o
  -- trigger acusa a primeira e aborta, e a segunda aparece no upload seguinte.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', 'bloco_aluno', e.n, 'METODO_INCOMPATIVEL',
         format('bloco_aluno: o aluno %s é de %s e o bloco é de %s.',
                e.j ->> 'aluno', coalesce(af.metodo, ab.metodo), bl.metodo),
         e.j ->> 'aluno'
    from jsonb_array_elements(v_d -> 'bloco_aluno') with ordinality e(j, n)
    left join (select btrim(a.j ->> 'codigo') as codigo, a.j ->> 'metodo' as metodo
                 from jsonb_array_elements(v_d -> 'aluno') a(j)) af
           on af.codigo = btrim(e.j ->> 'aluno')
    left join (select a.codigo_sgf as codigo, mo.codigo as metodo
                 from public.aluno a
                 join public.metodo mo on mo.id = a.metodo_id
                where a.unidade_id = v_unidade and a.codigo_sgf is not null) ab
           on ab.codigo = btrim(e.j ->> 'aluno')
    join (select concat_ws('/', btrim(b.j ->> 'sala'), b.j ->> 'dia_semana',
                           public.fn_importacao_hora(b.j ->> 'hora_inicio')::text) as chave,
                 b.j ->> 'metodo' as metodo
            from jsonb_array_elements(v_d -> 'bloco_horario') b(j)) bl
      on bl.chave = concat_ws('/', btrim(e.j ->> 'sala'), e.j ->> 'dia_semana',
                              public.fn_importacao_hora(e.j ->> 'hora_inicio')::text)
   where coalesce(af.metodo, ab.metodo) is not null
     and coalesce(af.metodo, ab.metodo) <> bl.metodo;

  -- V9 — aluno fora de ATIVO/ACELERAR ocupando vaga. É o ALUNO_INATIVO do mesmo
  -- trigger (e do fn_turma_modular_aluno_admissao), pela mesma razão do V8.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', x.entidade, x.n, 'ALUNO_INATIVO',
         format('%s: o aluno %s está como %s e não pode ocupar vaga.',
                x.entidade, x.aluno, s.status), x.aluno
    from (
      select 'bloco_aluno' as entidade, e.n, btrim(e.j ->> 'aluno') as aluno,
             coalesce(e.j ->> 'ativo', 'true') as ativo
        from jsonb_array_elements(v_d -> 'bloco_aluno') with ordinality e(j, n)
      union all
      select 'turma_modular_aluno', e.n, btrim(e.j ->> 'aluno'),
             coalesce(e.j ->> 'ativo', 'true')
        from jsonb_array_elements(v_d -> 'turma_modular_aluno') with ordinality e(j, n)
    ) x
    join lateral (
      select coalesce(
        (select coalesce(a.j ->> 'status', 'ATIVO')
           from jsonb_array_elements(v_d -> 'aluno') a(j)
          where btrim(a.j ->> 'codigo') = x.aluno limit 1),
        (select a.status from public.aluno a
          where a.unidade_id = v_unidade and a.codigo_sgf = x.aluno)) as status
    ) s on true
   where x.ativo <> 'false'
     and s.status is not null
     and s.status not in ('ATIVO', 'ACELERAR');

  -- V10 — saldo negativo. O comentário de v_estoque_atual.saldo diz que negativo
  -- «NÃO deveria» existir, e o critério 4 do marco 6.9 o proíbe; deixar a
  -- importação instalá-lo seria estrear o sistema violando a própria invariante.
  --
  -- ⚠️ O `not exists` sobre importacao_referencia é o que faz a SEGUNDA execução
  --    do mesmo snapshot passar: os movimentos já aplicados continuam no arquivo,
  --    mas não serão inseridos de novo — somá-los ao saldo que eles próprios
  --    formaram acusaria negativo onde não há.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', 'movimento_estoque', 'SALDO_NEGATIVO',
         format('O material %s ficaria com saldo %s depois da importação.',
                mv.chave, coalesce(ea.saldo, 0) + mv.soma), mv.chave
    from (
      select concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'material')) as chave,
             sum(coalesce(public.fn_importacao_int(e.j ->> 'quantidade'), 0)) as soma
        from jsonb_array_elements(v_d -> 'movimento_estoque') e(j)
       where not exists (
             select 1 from public.importacao_referencia r
              where r.unidade_id = v_unidade
                and r.entidade = 'movimento_estoque'
                and r.chave_externa = btrim(e.j ->> 'chave'))
       group by 1
    ) mv
    left join (
      select concat_ws('/', mo.codigo, v.codigo) as chave, v.saldo
        from public.v_estoque_atual v
        join public.metodo mo on mo.id = v.metodo_id
       where v.unidade_id = v_unidade
    ) ea on ea.chave = mv.chave
   where coalesce(ea.saldo, 0) + mv.soma < 0;

  -- V11 — aluno sem turma. É o "20 sem turma ⚠" do wireframes.md §16 e a
  -- primeira linha da lista de exceções do card 9.3. AVISO, nunca ERRO: aluno
  -- sem turma é situação REAL da escola, e a rotina diária abre ALUNO_SEM_TURMA
  -- para ele no dia seguinte — a pendência é o destino certo, não o bloqueio.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'AVISO', 'aluno', e.n, 'ALUNO_SEM_TURMA',
         format('O aluno %s (%s) não aparece em turma nenhuma no arquivo.',
                e.j ->> 'nome', e.j ->> 'codigo'), e.j ->> 'codigo'
    from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
   where coalesce(e.j ->> 'status', 'ATIVO') in ('ATIVO', 'ACELERAR')
     and not exists (select 1 from jsonb_array_elements(v_d -> 'bloco_aluno') b(j)
                      where btrim(b.j ->> 'aluno') = btrim(e.j ->> 'codigo'))
     and not exists (select 1 from jsonb_array_elements(v_d -> 'turma_modular_aluno') t(j)
                      where btrim(t.j ->> 'aluno') = btrim(e.j ->> 'codigo'));

  -- V12 — previsão atípica: as "3 previsões atípicas" do §16 e o "2023, 2050,
  -- vencidas" da nota do card 9.3. A borda de baixo é o SNAPSHOT, não hoje —
  -- comparar com hoje faria a mesma planilha mudar de veredito conforme o dia em
  -- que alguém a importa.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'AVISO', 'aluno', e.n, 'PREVISAO_ATIPICA',
         format('O aluno %s tem previsão de conclusão em %s, fora da janela do snapshot (%s).',
                e.j ->> 'codigo',
                to_char(public.fn_importacao_data(e.j ->> 'prev_conclusao_curso'), 'DD/MM/YYYY'),
                to_char(v_snapshot, 'DD/MM/YYYY')),
         e.j ->> 'prev_conclusao_curso'
    from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
   where public.fn_importacao_data(e.j ->> 'prev_conclusao_curso') is not null
     and (public.fn_importacao_data(e.j ->> 'prev_conclusao_curso') < v_snapshot
       or public.fn_importacao_data(e.j ->> 'prev_conclusao_curso') > v_snapshot + interval '3 years');

  -- V13 — as duas metades da divergência "saídas × flag Entregue" do plano §8.
  -- Elas se conferem uma contra a outra dentro do MESMO arquivo, que é o único
  -- lugar onde as duas existem juntas.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'AVISO', 'aluno_material', e.n, 'ENTREGA_SEM_SAIDA',
         format('A trilha diz que o aluno %s recebeu o material %s, e não há saída de estoque correspondente.',
                e.j ->> 'aluno', e.j ->> 'material'),
         concat_ws('/', e.j ->> 'aluno', e.j ->> 'material')
    from jsonb_array_elements(v_d -> 'aluno_material') with ordinality e(j, n)
   where coalesce(e.j ->> 'entregue', 'false') = 'true'
     and not exists (
           select 1 from jsonb_array_elements(v_d -> 'movimento_estoque') m(j)
            where m.j ->> 'tipo' = 'SAIDA'
              and btrim(coalesce(m.j ->> 'aluno', '')) = btrim(e.j ->> 'aluno')
              and btrim(coalesce(m.j ->> 'material', '')) = btrim(e.j ->> 'material'));

  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'AVISO', 'movimento_estoque', e.n, 'SAIDA_SEM_ENTREGA',
         format('Há saída do material %s para o aluno %s, e a trilha não marca a entrega.',
                e.j ->> 'material', e.j ->> 'aluno'),
         concat_ws('/', e.j ->> 'aluno', e.j ->> 'material')
    from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
   where e.j ->> 'tipo' = 'SAIDA'
     and nullif(btrim(coalesce(e.j ->> 'aluno', '')), '') is not null
     and not exists (
           select 1 from jsonb_array_elements(v_d -> 'aluno_material') t(j)
            where btrim(t.j ->> 'aluno') = btrim(e.j ->> 'aluno')
              and btrim(t.j ->> 'material') = btrim(e.j ->> 'material')
              and coalesce(t.j ->> 'entregue', 'false') = 'true');

  -- V14 — a divergência 3 do cabeçalho: pc.status derivado sem a linha que o
  -- deriva. Sem este aviso, a capacidade do bloco sobe sozinha às 03:10.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'AVISO', 'pc', e.n, 'PC_SEM_MANUTENCAO',
         format('O PC %s vem como MANUTENCAO e não há manutenção aberta para ele — a rotina diária o devolverá a OPERACIONAL.',
                e.j ->> 'identificador'), e.j ->> 'identificador'
    from jsonb_array_elements(v_d -> 'pc') with ordinality e(j, n)
   where e.j ->> 'status' = 'MANUTENCAO'
     and not exists (
           select 1 from jsonb_array_elements(v_d -> 'pc_manutencao') m(j)
            where btrim(m.j ->> 'pc') = btrim(e.j ->> 'identificador')
              and public.fn_importacao_data(m.j ->> 'data_fim') is null);

  -- V15 — saída sem aluno. O plano §8 manda transformá-la em AJUSTE, e quem faz
  -- isso é o extrator do card 9.2; aqui ela só é registrada, porque uma SAIDA
  -- sem aluno entra no banco sem erro nenhum e some da conferência.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'AVISO', 'movimento_estoque', e.n, 'SAIDA_SEM_ALUNO',
         format('Saída de %s do material %s sem aluno — o plano §8 manda que ela vire AJUSTE.',
                abs(coalesce(public.fn_importacao_int(e.j ->> 'quantidade'), 0)),
                e.j ->> 'material'), e.j ->> 'chave'
    from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
   where e.j ->> 'tipo' = 'SAIDA'
     and nullif(btrim(coalesce(e.j ->> 'aluno', '')), '') is null;

  -- V16 — status do arquivo diferente do status no sistema. A aplicação NÃO
  -- reescreve status de aluno que já existe (ver o passo 11 de
  -- fn_importacao_aplicar), e sem este aviso a diferença sumiria: a tela diria
  -- "265 alunos aplicados" e o aluno continuaria ATIVO no sistema e TRANCADO na
  -- planilha. Mudar status é transição, e transição se faz na tela 3.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'AVISO', 'aluno', e.n, 'STATUS_DIVERGENTE',
         format('O aluno %s está %s no sistema e %s no arquivo — a importação não muda status; use a tela de Alunos.',
                e.j ->> 'codigo', a.status, coalesce(e.j ->> 'status', 'ATIVO')),
         coalesce(e.j ->> 'status', 'ATIVO')
    from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
    join public.aluno a on a.unidade_id = v_unidade
                       and a.codigo_sgf = btrim(e.j ->> 'codigo')
   where a.status <> coalesce(e.j ->> 'status', 'ATIVO');
end $$;

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
        on conflict (turma_id, modulo_id) do update
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
