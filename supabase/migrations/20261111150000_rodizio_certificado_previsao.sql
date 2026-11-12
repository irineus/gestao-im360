-- =============================================================================
-- Card 9.2,885 — Turma em rodízio: certificado, previsão e combo
--
-- As três decisões de Irineu de 11/11/2026 (docs/turma-rodizio.md §10), que o
-- card 9.2,88 deixou de fora por mexerem em funções de outros cards:
--
--   D1  o certificado do aluno MODULAR abre na CONCLUSÃO DOS MÓDULOS, e não na
--       entrega da última apostila — no Modular o último livro é entregue meses
--       antes do fim do curso;
--   D2  a previsão de conclusão do aluno em turma Modular é só a CALCULADA:
--       PREVISAO_VENCIDA deixa de olhar para ele;
--   D3  com mais de um curso Modular no combo, o certificado abre no fim do
--       COMBO.
--
-- Entregável:
--   1. fn_aluno_e_modular e fn_aluno_modular_modulos_pendentes;
--   2. fn_aluno_modular_avaliar_certificado, chamada pela conclusão e pela
--      exceção à mão;
--   3. fn_registrar_entrega e fn_estornar_entrega deixam o certificado do aluno
--      Modular em paz;
--   4. v_certificado_fila lê a situação do Modular dos MÓDULOS;
--   5. rt_pendencias_diaria: PREVISAO_VENCIDA sem o aluno de turma Modular.
--
-- ⚠️ Quatro substituições de função inteira, todas a partir da ÚLTIMA definição
--    aplicada (lição do card 5.7): fn_registrar_entrega e fn_estornar_entrega do
--    card 8.3 (20260905210000_certificado_checklist.sql); rt_pendencias_diaria
--    do card 9.2,85 (20261110120000_aviso_troca_modulo.sql) — com o bloco de
--    TROCA_MODULO_ALINHAR preservado; fn_aluno_modulo_remover e
--    fn_aluno_modular_avaliar_conclusao do card 9.2,88.
--
-- O que este arquivo NÃO faz: não grava dado; não muda Interativo nem Inglês; e
-- não apaga nem zera `aluno.prev_conclusao_curso` — a coluna continua vindo do
-- importador e volta a valer se o aluno sair da turma.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. As duas perguntas
-- -----------------------------------------------------------------------------
-- `security definer` nas duas, com filtro de unidade no corpo: são DECISÃO
-- DERIVADA usada dentro da transação de outro ator (o monitor que entrega, quem
-- avança o módulo) e por uma view. Lidas sob RLS, negariam linha em vez de
-- devolver erro — e o monitor sem `materiais.ler` abriria, na entrega, o
-- certificado de um aluno Modular que ainda tem módulos a fazer.
create or replace function public.fn_aluno_e_modular(p_aluno_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (select 1
                   from public.aluno a
                   join public.metodo me on me.id = a.metodo_id
                  where a.id = p_aluno_id
                    and a.unidade_id = public.fn_unidade_atual()
                    and me.codigo = 'MODULAR');
$$;

comment on function public.fn_aluno_e_modular(uuid) is
  'O aluno é do método MODULAR? (card 9.2,885). É o que separa o certificado que abre na última apostila (Interativo e Inglês) do que abre na conclusão dos módulos. SECURITY DEFINER com filtro de unidade: é lida na transação de quem entrega, e sob RLS quem não lê o catálogo receberia false — e abriria o certificado errado.';

revoke execute on function public.fn_aluno_e_modular(uuid) from public;
revoke execute on function public.fn_aluno_e_modular(uuid) from anon;
grant  execute on function public.fn_aluno_e_modular(uuid) to authenticated;

-- Quantos módulos faltam ao aluno, no ESCOPO dele (D3):
--   • os cursos Modular do COMBO, quando ele tem combo;
--   • mais os cursos das turmas em que está ou esteve, e os dos módulos que já
--     fez — o aluno sem combo conclui pelo curso da turma.
-- NULO quando o aluno ainda não começou (nenhuma turma, nenhum módulo) ou
-- quando o escopo não tem módulo nenhum: nulo é "não há o que concluir", e zero
-- afirmaria "concluiu".
create or replace function public.fn_aluno_modular_modulos_pendentes(p_aluno_id uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with escopo as (
    select cc.curso_id
      from public.aluno a
      join public.combo_curso cc on cc.combo_id = a.combo_id
      join public.curso c   on c.id = cc.curso_id
      join public.metodo me on me.id = c.metodo_id and me.codigo = 'MODULAR'
     where a.id = p_aluno_id and a.unidade_id = public.fn_unidade_atual()
    union
    select t.curso_id
      from public.turma_modular_aluno ta
      join public.turma_modular t on t.id = ta.turma_id
     where ta.aluno_id = p_aluno_id and ta.unidade_id = public.fn_unidade_atual()
    union
    select m.curso_id
      from public.aluno_modulo am
      join public.modulo m on m.id = am.modulo_id
     where am.aluno_id = p_aluno_id and am.unidade_id = public.fn_unidade_atual()
  ),
  comecou as (
    select exists (select 1 from public.turma_modular_aluno ta
                    where ta.aluno_id = p_aluno_id
                      and ta.unidade_id = public.fn_unidade_atual())
        or exists (select 1 from public.aluno_modulo am
                    where am.aluno_id = p_aluno_id
                      and am.unidade_id = public.fn_unidade_atual()) as sim
  )
  select case
           when not (select sim from comecou) then null
           when count(*) = 0 then null
           else count(*) filter (where not exists (
                  select 1 from public.aluno_modulo am
                   where am.aluno_id = p_aluno_id and am.modulo_id = m.id))::integer
         end
    from public.modulo m
   where m.curso_id in (select curso_id from escopo);
$$;

comment on function public.fn_aluno_modular_modulos_pendentes(uuid) is
  'Quantos módulos faltam ao aluno Modular, no escopo dele (card 9.2,885, decisão D3): os cursos Modular do combo, mais os das turmas em que está ou esteve e os dos módulos que já fez. ZERO = concluiu tudo; NULO = ainda não começou ou não há módulo no escopo — nulo não afirma conclusão. É a pergunta única de fn_aluno_modular_avaliar_certificado e de v_certificado_fila. SECURITY DEFINER com filtro de unidade.';

revoke execute on function public.fn_aluno_modular_modulos_pendentes(uuid) from public;
revoke execute on function public.fn_aluno_modular_modulos_pendentes(uuid) from anon;
grant  execute on function public.fn_aluno_modular_modulos_pendentes(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 2. O certificado na conclusão dos módulos (D1 e D3)
-- -----------------------------------------------------------------------------
-- O par de fn_certificado_abrir para o aluno Modular. Não a chama, de
-- propósito: aquela exige `certificados.criar` de quem a executa, e quem
-- dispara esta é quem AVANÇOU o módulo (`turmas.editar`) — a secretaria avançar
-- a turma e o avanço inteiro morrer por falta de permissão de certificado seria
-- a "ação única pela metade" que o card 8.3 descreve, do outro lado.
--
-- `security definer` pelo mesmo motivo de fn_aluno_modular_avaliar_conclusao
-- (card 9.2,88), e com o mesmo limite aceito: só age quando a conclusão é
-- VERDADEIRA.
create or replace function public.fn_aluno_modular_avaliar_certificado(p_aluno_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_data    date;
begin
  v_unidade := public.fn_unidade_atual();
  if v_unidade is null then
    raise exception
      'fn_aluno_modular_avaliar_certificado: sem unidade no contexto (nem sessão autenticada nem contexto de rotina).';
  end if;

  if not public.fn_aluno_e_modular(p_aluno_id)
     or public.fn_aluno_modular_modulos_pendentes(p_aluno_id) is distinct from 0 then
    return false;
  end if;

  -- A data de fim do curso é a do ÚLTIMO módulo concluído — a data real.
  select max(am.data_conclusao) into v_data
    from public.aluno_modulo am
   where am.aluno_id = p_aluno_id and am.unidade_id = v_unidade;

  insert into public.certificado_checklist (unidade_id, aluno_id, data_fim_curso)
  values (v_unidade, p_aluno_id, coalesce(v_data, public.fn_hoje()))
      on conflict (aluno_id) do nothing;

  -- O mesmo aviso da última apostila (card 8.3), com a mesma chave: é o que faz
  -- a formatura fechá-lo, por tg_aluno_formado_fecha_pendencias, sem código novo.
  perform public.fn_pendencia_abrir(
    'ALUNO_ULTIMO_LIVRO',
    'ULTIMO_LIVRO:' || p_aluno_id::text,
    'O aluno concluiu todos os módulos do curso. O checklist do certificado já está aberto.',
    'BAIXA',
    p_aluno_id);

  return true;
end $$;

comment on function public.fn_aluno_modular_avaliar_certificado(uuid) is
  'Card 9.2,885 (decisões D1 e D3): se o aluno é MODULAR e não lhe falta módulo nenhum no escopo dele (fn_aluno_modular_modulos_pendentes = 0 — com combo, só no fim do combo), abre o checklist do certificado com a data do último módulo e a pendência ALUNO_ULTIMO_LIVRO. Idempotente. É o par de fn_certificado_abrir para o Modular, sem exigir certificados.criar de quem avançou o módulo. SECURITY DEFINER com filtro de unidade; só age quando a conclusão é verdadeira.';

revoke execute on function public.fn_aluno_modular_avaliar_certificado(uuid) from public;
revoke execute on function public.fn_aluno_modular_avaliar_certificado(uuid) from anon;
grant  execute on function public.fn_aluno_modular_avaliar_certificado(uuid) to authenticated;

-- A conclusão do curso passa a avaliar o certificado. Parte da definição do
-- card 9.2,88; a única mudança é a chamada no fim — e ela vem DEPOIS de liberar
-- a vaga, e também quando o aluno já não estava ativo na turma.
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

  -- Card 9.2,885: o certificado. Com combo, só abre quando não resta curso
  -- Modular por concluir — quem decide é a função.
  perform public.fn_aluno_modular_avaliar_certificado(p_aluno_id);

  return true;
end $$;

comment on function public.fn_aluno_modular_avaliar_conclusao(uuid, uuid) is
  'Card 9.2,88 (docs/turma-rodizio.md §4.4): se aluno_modulo cobre todos os módulos do curso da turma, tira o aluno da turma (ativo = false, motivo_saida = Concluiu o curso), liberando a vaga, e devolve true. Desde o card 9.2,885 avalia também o certificado (fn_aluno_modular_avaliar_certificado): com combo, o checklist só abre quando não resta curso Modular por concluir. Não muda o status do aluno. SECURITY DEFINER; filtra unidade no corpo e só age quando a conclusão é verdadeira.';

-- O registro à mão também avalia o certificado — sempre, e não só quando o
-- aluno ainda está numa turma do curso.
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

  -- Card 9.2,885: o certificado é avaliado SEMPRE, e não só pelo laço acima — o
  -- aluno pode já ter saído da turma (concluiu o curso dela) e estar fechando,
  -- à mão, o último curso do combo, que não tem turma nenhuma no caminho.
  perform public.fn_aluno_modular_avaliar_certificado(p_aluno_id);

  return v_id;
end $$;

comment on function public.fn_aluno_modulo_registrar(uuid, uuid, date, text) is
  'Exceção à mão (card 9.2,88, regra 6): registra que o aluno FEZ um módulo por fora do avanço da turma (origem MANUAL). Exige alunos.editar_trilha. PT409/MODULO_JA_REGISTRADO se já existe. Registrar o último módulo do curso tira o aluno da turma, como o avanço; e, desde o card 9.2,885, avalia SEMPRE o certificado — inclusive quando o aluno já saiu da turma e está fechando o último curso do combo. p_data_conclusao tem default fn_hoje().';

-- A remoção de um módulo pode tirar o aluno do "concluiu": o aviso deixa de ser
-- verdade e o checklist é reavaliado, como o estorno faz com a última apostila.
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

  -- Card 9.2,885: a remoção tirou o aluno do "concluiu"? O aviso deixou de ser
  -- verdade, e o checklist aberto pela conclusão deixou de ter razão de
  -- existir — apaga se intocado, mantém e avisa se alguém já trabalhou nele.
  if public.fn_aluno_e_modular(p_aluno_id)
     and public.fn_aluno_modular_modulos_pendentes(p_aluno_id) is distinct from 0 then
    perform public.fn_pendencia_resolver('ULTIMO_LIVRO:' || p_aluno_id::text);
    perform public.fn_certificado_reavaliar_estorno(p_aluno_id);
  end if;
end $$;

comment on function public.fn_aluno_modulo_remover(uuid, uuid, text) is
  'Exceção à mão (card 9.2,88, regra 6): remove um módulo do registro do aluno — ele precisa refazer. Exige alunos.editar_trilha e motivo (PT422/MOTIVO_OBRIGATORIO), que vai para aluno_modulo_hist. PT404/MODULO_NAO_REGISTRADO quando não há o que remover. Desde o card 9.2,885, se a remoção tira o aluno do "concluiu", fecha ALUNO_ULTIMO_LIVRO e reavalia o checklist do certificado (apaga se intocado; senão mantém e abre CERTIFICADO_INCONSISTENTE). Não devolve o aluno à turma de que saiu por conclusão: isso é admissão.';

-- -----------------------------------------------------------------------------
-- 3. A entrega e o estorno deixam o certificado do aluno Modular em paz (D1)
-- -----------------------------------------------------------------------------
-- As duas a partir do card 8.3, palavra por palavra, com UMA condição a mais em
-- cada: `and not public.fn_aluno_e_modular(…)`. Para Interativo e Inglês nada
-- muda — o teste 081 continua sendo a medida disso.
create or replace function public.fn_registrar_entrega(
  p_aluno_id    uuid,
  p_material_id uuid default null,
  p_observacao  text default null
)
returns public.tp_entrega_resultado
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade    uuid;
  v_status     text;
  v_aluno_ok   boolean;
  v_alvo       uuid;
  v_efetivo    uuid;
  v_ordem_alvo integer;
  v_posicao    integer;
  v_mov        uuid;
  v_retorno    text := 'ENTREGUE';
  v_res        public.tp_entrega_resultado;
begin
  perform public.fn_exige_permissao('estoque.lancar_saida');

  -- (a) serializa as entregas do MESMO aluno.
  perform pg_advisory_xact_lock(hashtextextended(p_aluno_id::text, 0));

  select a.unidade_id, a.status, true
    into v_unidade, v_status, v_aluno_ok
    from public.aluno a
   where a.id = p_aluno_id;

  -- Nulo é ERRO e não "sem opinião" (lição do card 5.3): a leitura é `invoker`,
  -- então aluno de outra unidade e aluno inexistente respondem a mesma coisa —
  -- quem não pode ver não descobre que existe (precedente do card 4.2).
  if v_aluno_ok is not true then
    raise exception using
      errcode = 'PT404',
      message = 'Aluno não encontrado.',
      detail  = json_build_object('codigo', 'ALUNO_INEXISTENTE',
                                  'aluno', p_aluno_id)::text;
  end if;

  if v_status not in ('ATIVO', 'ACELERAR') then
    raise exception using
      errcode = 'PT409',
      message = 'Esta ação só vale para aluno ATIVO ou ACELERAR.',
      detail  = json_build_object('codigo', 'ALUNO_INATIVO',
                                  'aluno', p_aluno_id,
                                  'status', v_status)::text;
  end if;

  v_alvo := coalesce(p_material_id, public.fn_trilha_proximo_material(p_aluno_id));

  if v_alvo is null then
    raise exception using
      errcode = 'PT409',
      message = 'A trilha deste aluno está concluída — não há apostila pendente para entregar.',
      detail  = json_build_object('codigo', 'TRILHA_EM_FIM',
                                  'aluno', p_aluno_id)::text;
  end if;

  -- O material informado à mão tem de estar PENDENTE na trilha. Sem este passo, a
  -- tela poderia baixar estoque de uma apostila que o aluno não deve receber — ou
  -- de uma que ele já recebeu, entregando o mesmo livro duas vezes.
  select am.ordem into v_ordem_alvo
    from public.aluno_material am
   where am.aluno_id = p_aluno_id and am.material_id = v_alvo and not am.entregue;

  if v_ordem_alvo is null then
    raise exception using
      errcode = 'PT422',
      message = 'Esta apostila não está pendente na trilha do aluno.',
      detail  = json_build_object('codigo', 'MATERIAL_FORA_DA_TRILHA',
                                  'aluno', p_aluno_id,
                                  'material', v_alvo)::text;
  end if;

  -- (b) serializa o par (checar saldo, gravar saída) daquele material.
  perform pg_advisory_xact_lock(hashtextextended(v_alvo::text, 0));

  v_efetivo := v_alvo;

  if public.fn_saldo_material(v_alvo) <= 0 then
    -- Em ordem de trilha, o primeiro item pendente que TEM estoque. A ordem
    -- importa: pular para o mais adiantado que sobrou seria entregar o livro
    -- errado, e a trilha existe justamente para dizer qual é o próximo.
    select am.material_id into v_efetivo
      from public.aluno_material am
     where am.aluno_id = p_aluno_id
       and not am.entregue
       and am.material_id <> v_alvo
       and public.fn_saldo_material(am.material_id) > 0
     order by am.ordem
     limit 1;

    if v_efetivo is null then
      -- ⚠️ RETORNO, e não exceção (decisão 2.2 (b), §1.3). A pendência de compra é
      --    a única coisa útil que sobra deste caminho, e um `raise` a levaria
      --    embora no rollback: a secretaria veria um erro e o sistema não saberia
      --    que faltou apostila. É a decisão que o teste 052 §5 mede.
      perform public.fn_pendencia_abrir(
        'COMPRA_SEM_ESTOQUE',
        'COMPRA_SEM_ESTOQUE:' || p_aluno_id::text,
        'Nenhuma apostila pendente da trilha deste aluno tem estoque. A entrega está bloqueada até a compra chegar.',
        'ALTA',
        p_aluno_id,
        null,
        v_alvo);

      v_res.status              := 'BLOQUEADA_SEM_ESTOQUE';
      v_res.material_id         := null;
      v_res.material_solicitado := v_alvo;
      v_res.movimento_id        := null;
      v_res.proximo_material_id := public.fn_trilha_proximo_material(p_aluno_id);
      v_res.em_fim              := public.fn_trilha_em_fim(p_aluno_id);
      return v_res;
    end if;

    -- O material que vai sair também precisa do lock: sem ele, a corrida só se
    -- mudaria de lugar — duas entregas reordenadas para o mesmo substituto
    -- fechariam o saldo dele em −1.
    perform pg_advisory_xact_lock(hashtextextended(v_efetivo::text, 0));

    -- A POSIÇÃO do pulado, 1-based: é literalmente o que o passo 6 do §6.2 pede
    -- ("põe esse material na posição do pulado"), e é por isso que o card 6.2
    -- fixou `p_nova_ordem` como posição e não como o valor bruto da coluna.
    select count(*) into v_posicao
      from public.aluno_material am
     where am.aluno_id = p_aluno_id and am.ordem <= v_ordem_alvo;

    -- A exceção nomeada, ligada e desligada em volta da ÚNICA escrita que
    -- precisa dela. `is_local => true`: morre no fim da transação de qualquer
    -- forma, mas desligar aqui é o que mantém a brecha do tamanho de uma linha.
    perform set_config('app.entrega_reordenacao', 'on', true);
    perform public.fn_trilha_reposicionar(p_aluno_id, v_efetivo, v_posicao,
                                          'SEM_ESTOQUE', false);
    perform set_config('app.entrega_reordenacao', '', true);

    -- O pulado CONTINUA pendente e volta a ser "próximo" assim que houver
    -- estoque: ele foi empurrado uma posição, não removido.
    perform public.fn_pendencia_abrir(
      'ESTOQUE_ZERO',
      'ESTOQUE_ZERO:' || v_alvo::text,
      'Apostila sem estoque: a trilha de pelo menos um aluno foi reordenada para pular esta apostila.',
      'MEDIA',
      null,
      null,
      v_alvo);

    v_retorno := 'REORDENADA';
  end if;

  -- Quantidade COM SINAL (card 2.1): `movimento_sinal_ck` já exige SAIDA < 0, e a
  -- autoria não é coluna própria — vem de `criado_por`, que fn_auditoria preenche.
  insert into public.movimento_estoque
    (unidade_id, material_id, tipo, quantidade, aluno_id, ocorrido_em, observacao)
  values (v_unidade, v_efetivo, 'SAIDA', -1, p_aluno_id, now(), p_observacao)
  returning id into v_mov;

  -- A data da entrega é `fn_hoje()`, a data no fuso da escola (card 2.3 §3.3). O
  -- §6.2 escrevia a data do servidor, que é UTC no Supabase: depois das 21h a
  -- entrega cairia no dia seguinte, e a projeção do card 8.1 — que mede INTERVALO
  -- entre entregas — leria um ritmo que ninguém teve. O C6 reprova a forma antiga
  -- inclusive quando ela aparece só num comentário, e é por isso que este não a
  -- escreve.
  update public.aluno_material am
     set entregue             = true,
         data_entrega         = public.fn_hoje(),
         movimento_estoque_id = v_mov
   where am.aluno_id = p_aluno_id and am.material_id = v_efetivo;

  -- ÚLTIMO LIVRO ENTREGUE — o passo 9 do §6.2, COMPLETO desde o card 8.3.
  -- fn_certificado_abrir vem ANTES da pendência, e a ordem é decisão: se quem
  -- entrega não tiver `certificados.criar` (achado 3 do card 2.4 §7), a entrega
  -- inteira falha e NADA é gravado — nem o movimento, nem a marca na trilha, nem
  -- a pendência. Metade de uma "ação única" é pior que nenhuma, e a ordem inversa
  -- deixaria um aviso de "abra o checklist" que ninguém consegue atender.
  -- Severidade BAIXA porque não há nada errado — há algo a fazer.
  --
  -- ⚠️ Card 9.2,885 (decisão D1): MENOS para o aluno MODULAR. O último livro
  --    dele é entregue meses antes do fim do curso, e o checklist abre na
  --    conclusão dos MÓDULOS (fn_aluno_modular_avaliar_certificado).
  if public.fn_trilha_em_fim(p_aluno_id)
     and not public.fn_aluno_e_modular(p_aluno_id) then
    perform public.fn_certificado_abrir(p_aluno_id);

    perform public.fn_pendencia_abrir(
      'ALUNO_ULTIMO_LIVRO',
      'ULTIMO_LIVRO:' || p_aluno_id::text,
      'O aluno recebeu a última apostila da trilha. O checklist do certificado já está aberto.',
      'BAIXA',
      p_aluno_id);
  end if;

  -- O retorno já traz o próximo e o FIM recalculados: a tela do card 6.6 não
  -- precisa de uma segunda ida ao banco para saber o que mostrar em seguida.
  v_res.status              := v_retorno;
  v_res.material_id         := v_efetivo;
  v_res.material_solicitado := v_alvo;
  v_res.movimento_id        := v_mov;
  v_res.proximo_material_id := public.fn_trilha_proximo_material(p_aluno_id);
  v_res.em_fim              := public.fn_trilha_em_fim(p_aluno_id);
  return v_res;
end $$;

comment on function public.fn_registrar_entrega(uuid, uuid, text) is
  'Entrega de apostila como ATO ÚNICO (card 2.2 §6.2): SAIDA de estoque, marca na trilha e vínculo entre as duas, na mesma transação. Exige estoque.lancar_saida. Devolve ENTREGUE, REORDENADA (pulou apostila sem estoque, com rastro em aluno_material_hist e pendência ESTOQUE_ZERO) ou BLOQUEADA_SEM_ESTOQUE (nenhum item da trilha tem estoque; abre COMPRA_SEM_ESTOQUE e NÃO levanta exceção, para a pendência sobreviver ao commit). Chegando ao FIM da trilha, abre o checklist do certificado (fn_certificado_abrir) antes da pendência ALUNO_ULTIMO_LIVRO — MENOS para o aluno MODULAR (card 9.2,885): o dele abre na conclusão dos módulos. Serializa aluno e material com pg_advisory_xact_lock.';

create or replace function public.fn_estornar_entrega(
  p_movimento_id uuid,
  p_motivo       text
)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade    uuid;
  v_material   uuid;
  v_aluno      uuid;
  v_tipo       text;
  v_quantidade integer;
  v_estorno    uuid;
begin
  perform public.fn_exige_permissao('estoque.estornar');

  -- Motivo obrigatório, pelo precedente de fn_aluno_alterar_status e
  -- fn_trilha_remover: desfazer uma entrega é decisão, e decisão sem porquê é
  -- decisão perdida.
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception using
      errcode = 'PT422',
      message = 'Informe o motivo do estorno.',
      detail  = json_build_object('codigo', 'MOTIVO_OBRIGATORIO',
                                  'movimento', p_movimento_id)::text;
  end if;

  -- Serializa o movimento: `movimento_estorno_uk` (unique parcial do card 6.1) já
  -- garante que ele só se estorna uma vez, mas sem o lock a corrida chegaria à
  -- tela como um `23505` cru — que é o que o card 2.2 §1.2 proíbe. Com o lock, a
  -- segunda sessão espera e sai com MOVIMENTO_JA_ESTORNADO.
  perform pg_advisory_xact_lock(hashtextextended(p_movimento_id::text, 0));

  select mv.unidade_id, mv.material_id, mv.aluno_id, mv.tipo, mv.quantidade
    into v_unidade, v_material, v_aluno, v_tipo, v_quantidade
    from public.movimento_estoque mv
   where mv.id = p_movimento_id;

  -- Código NOVO, e a família já existe: PC_INEXISTENTE, ALUNO_INEXISTENTE,
  -- BLOCO_INEXISTENTE e PENDENCIA_INEXISTENTE dizem a mesma coisa nos seus
  -- domínios. Vale também para movimento de OUTRA unidade — a leitura é
  -- `invoker`, então quem não pode ver não descobre que existe. Reaproveitar
  -- MOVIMENTO_NAO_ESTORNAVEL aqui diria "este movimento não pode ser estornado"
  -- sobre algo que o usuário não tem, o que manda procurar o problema no lugar
  -- errado.
  if v_tipo is null then
    raise exception using
      errcode = 'PT404',
      message = 'Este movimento de estoque não foi encontrado.',
      detail  = json_build_object('codigo', 'MOVIMENTO_INEXISTENTE',
                                  'movimento', p_movimento_id)::text;
  end if;

  -- Só SAIDA se estorna por aqui: esta função desfaz uma ENTREGA, e desfazer uma
  -- ENTRADA de pedido ou um AJUSTE é outra conversa (card 6.5), com outra
  -- permissão e outro efeito na trilha — nenhum.
  if v_tipo <> 'SAIDA' then
    raise exception using
      errcode = 'PT409',
      message = 'Este movimento não pode ser estornado.',
      detail  = json_build_object('codigo', 'MOVIMENTO_NAO_ESTORNAVEL',
                                  'movimento', p_movimento_id,
                                  'tipo', v_tipo)::text;
  end if;

  if exists (select 1 from public.movimento_estoque mv
              where mv.estorno_de_id = p_movimento_id) then
    raise exception using
      errcode = 'PT409',
      message = 'Este movimento já foi estornado.',
      detail  = json_build_object('codigo', 'MOVIMENTO_JA_ESTORNADO',
                                  'movimento', p_movimento_id)::text;
  end if;

  -- Sinal OPOSTO e mesma magnitude. Escrito como `-v_quantidade` e não como `1`
  -- de propósito: o dia em que uma entrega sair com quantidade diferente de 1, o
  -- estorno continua devolvendo exatamente o que saiu.
  insert into public.movimento_estoque
    (unidade_id, material_id, tipo, quantidade, aluno_id, ocorrido_em,
     estorno_de_id, observacao)
  values (v_unidade, v_material, 'ESTORNO', -v_quantidade, v_aluno, now(),
          p_movimento_id, p_motivo)
  returning id into v_estorno;

  -- A trilha volta a PENDENTE. As três colunas são exatamente as que a guarda da
  -- seção 3 deixa fora da lista, então `estoque.estornar` basta — não é preciso
  -- ser dono da trilha para desfazer uma entrega.
  update public.aluno_material am
     set entregue             = false,
         data_entrega         = null,
         movimento_estoque_id = null
   where am.movimento_estoque_id = p_movimento_id;

  -- O ALUNO SAIU DO FIM — o passo 5 do §6.3, COMPLETO desde o card 8.3.
  -- O aviso do último livro deixou de ser verdade (pendência que ninguém fecha é
  -- a central do card 5.8 perdendo credibilidade), e o checklist aberto por
  -- aquela entrega deixou de ter razão de existir: apaga se nenhum item foi
  -- marcado, mantém e abre CERTIFICADO_INCONSISTENTE se alguém já trabalhou nele.
  -- Quem faz isso é fn_certificado_reavaliar_estorno, `security definer` porque a
  -- tabela não tem política de delete para ninguém.
  -- Card 9.2,885: o certificado do aluno MODULAR não depende da apostila — nem
  -- para abrir, nem para ser reavaliado.
  if v_aluno is not null and not public.fn_trilha_em_fim(v_aluno)
     and not public.fn_aluno_e_modular(v_aluno) then
    perform public.fn_pendencia_resolver('ULTIMO_LIVRO:' || v_aluno::text);
    perform public.fn_certificado_reavaliar_estorno(v_aluno);
  end if;

  --
  -- E o passo 6 continua valendo por AUSÊNCIA de código: um estorno NÃO reverte o
  -- reordenamento da trilha por falta de estoque. O histórico em
  -- aluno_material_hist continua contando o que aconteceu, e desfazer a
  -- reordenação inventaria uma trilha que nunca existiu.

  return v_estorno;
end $$;

comment on function public.fn_estornar_entrega(uuid, text) is
  'Estorna uma SAIDA de entrega (card 2.2 §6.3): grava o movimento ESTORNO com sinal oposto e estorno_de_id, e devolve o item da trilha a PENDENTE. Exige estoque.estornar e motivo. Saindo do FIM, fecha ALUNO_ULTIMO_LIVRO e reavalia o checklist do certificado (fn_certificado_reavaliar_estorno) — MENOS para o aluno MODULAR (card 9.2,885), cujo certificado não depende da apostila. O movimento original NUNCA é alterado nem apagado. Não reverte o reordenamento por falta de estoque — o histórico conta o que aconteceu.';

-- -----------------------------------------------------------------------------
-- 4. v_certificado_fila — a situação do Modular vem dos MÓDULOS (D1)
-- -----------------------------------------------------------------------------
-- Mesmas colunas, na mesma ordem (`create or replace`). O que muda é de onde sai
-- `itens_pendentes` para o aluno MODULAR: dos módulos que lhe faltam, e não das
-- apostilas. `ULTIMO_LIVRO` lê-se, para ele, "no último módulo".
--
-- O filtro que separa "acabou" de "nunca começou" também tem as duas formas:
-- trilha existente, para os outros; pendentes NÃO NULO, para o Modular — a
-- função devolve nulo para quem ainda não entrou em turma nenhuma.
create or replace view public.v_certificado_fila with (security_invoker = on) as
select a.unidade_id,
       a.id            as aluno_id,
       a.nome          as aluno_nome,
       a.codigo_sgf,
       a.status        as aluno_status,
       a.metodo_id,
       me.codigo       as metodo_codigo,
       me.nome         as metodo_nome,
       case when pend.qtd = 0 then 'FIM' else 'ULTIMO_LIVRO' end as situacao,
       pend.qtd        as itens_pendentes,
       cc.id           as checklist_id,
       cc.data_fim_curso,
       cc.pedagogico_ok,
       cc.financeiro_ok,
       cc.formatura,
       cc.certificado_status
  from public.aluno a
  join public.metodo me on me.id = a.metodo_id
  cross join lateral (
         select case
                  when me.codigo = 'MODULAR'
                    then public.fn_aluno_modular_modulos_pendentes(a.id)
                  else (select count(*)::integer
                          from public.aluno_material am
                         where am.aluno_id = a.id and not am.entregue)
                end as qtd
       ) pend
  left join public.certificado_checklist cc on cc.aluno_id = a.id
 where a.status in ('ATIVO', 'ACELERAR')
   and pend.qtd <= 1
   and (me.codigo = 'MODULAR'
        or exists (select 1
                     from public.aluno_material am
                    where am.aluno_id = a.id));

comment on view public.v_certificado_fila is
  'Fila da tela 9 (docs/wireframes.md §12.1): os alunos ATIVO/ACELERAR que estão chegando ao fim do curso, com o resumo do checklist ao lado. Duas situações com rótulo distinto (card 2.3 §8.1): ULTIMO_LIVRO = 1 item pendente e FIM = nenhum. Para Interativo e Inglês o item é a APOSTILA da trilha, e exige-se trilha existente; para o MODULAR (card 9.2,885, decisão D1) o item é o MÓDULO — fn_aluno_modular_modulos_pendentes, que é nula para quem ainda não entrou em turma. O left join em certificado_checklist deixa as cinco colunas do checklist NULAS para quem ainda não o tem. Leitura exige alunos.ler, materiais.ler (join interno em metodo) e certificados.ler.';

comment on column public.v_certificado_fila.itens_pendentes is
  'Quantos itens faltam: APOSTILAS da trilha para Interativo e Inglês; MÓDULOS do curso (ou do combo) para o Modular (card 9.2,885).';

-- -----------------------------------------------------------------------------
-- 5. PREVISAO_VENCIDA sem o aluno de turma Modular (D2)
-- -----------------------------------------------------------------------------
-- A previsão de conclusão dele é a CALCULADA pelo cronograma da turma
-- (v_aluno_modular_progresso), e a digitada deixa de ser lida. O atraso dele
-- aparece como troca de módulo vencida da turma (TROCA_MODULO_ALINHAR).
--
-- ⚠️ A função parte da ÚLTIMA definição aplicada — a do card 9.2,85
--    (20261110120000_aviso_troca_modulo.sql), com o bloco de
--    TROCA_MODULO_ALINHAR — e a única mudança é o `not exists` no `where` de
--    PREVISAO_VENCIDA. O teste 104 continua vigiando o bloco da troca.
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
  v_troca_dias   integer;
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
              -- Card 9.2,885 (decisão D2): o aluno em turma Modular ATIVA tem a
              -- previsão CALCULADA pelo cronograma da turma, e a digitada deixa
              -- de ser lida. O atraso dele é a troca de módulo vencida.
              and not exists (select 1
                                from public.turma_modular_aluno ta
                                join public.turma_modular tm on tm.id = ta.turma_id
                               where ta.aluno_id = a.id and ta.ativo and tm.ativo)
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
  -- TROCA_MODULO_ALINHAR (MEDIA → ALTA) — card 9.2,85
  -- ---------------------------------------------------------------------------
  -- O aviso existe para que nenhum módulo comece sem alinhamento com o
  -- professor (decisão do dono do produto, 10/11/2026). A pendência nasce
  -- quando a previsão de conclusão do módulo corrente entra na janela de
  -- `troca_modulo_alerta_dias`, e sobe para ALTA no dia da troca.
  --
  -- ⚠️ A comparação NÃO se repete: `situacao_troca` é coluna de
  --    `v_turma_modular_lotacao`, e é ela que o Dashboard e a tela 5 pintam. É
  --    o precedente de `abaixo_minimo` no bloco acima — uma segunda escrita da
  --    mesma conta aqui divergiria da cor que a pessoa vê.
  --
  -- ⚠️ TRÊS coisas que este bloco faz diferente dos outros quatro, e as três
  --    são a decisão do card, não descuido:
  --
  --    (a) RESOLVIDA POR GENTE NÃO REABRE. Nos outros tipos a rotina reabre no
  --        dia seguinte enquanto a condição valer; aqui "resolvida" quer dizer
  --        "o alinhamento com o professor foi feito", e a condição (a troca
  --        está próxima) continua verdadeira até o dia da troca. Reabrir seria
  --        pedir o mesmo alinhamento todo dia. O que distingue é
  --        `resolvida_por` preenchido com `resolucao = 'RESOLVIDA'`: IGNORADA
  --        continua voltando, como em todo tipo (card 5.5), e o fechamento
  --        automático (`resolvida_por` nulo) também.
  --
  --    (b) AVANÇAR O MÓDULO NÃO FECHA. Se a turma trocou de módulo e ninguém
  --        registrou o alinhamento, a pendência é exatamente o que tem de
  --        continuar na central — e em ALTA. Por isso a chave do módulo já
  --        concluído ENTRA em `v_chaves` quando a pendência dele está aberta.
  --
  --    (c) FECHA SOZINHA só quando a troca deixa de estar próxima: a previsão
  --        foi adiada para além da janela, a turma foi desativada ou o módulo
  --        saiu do cronograma.
  --
  -- A chave carrega a TURMA e a linha do CRONOGRAMA
  -- (`TROCA_MODULO:<turma>:<cronograma>`): a turma é o que a central precisa
  -- para abrir a tela 5, e `pendencia` não tem coluna de turma Modular — é o
  -- precedente de `REP:<aluno>:CONTINUO`, que a tela também lê da chave.
  v_troca_dias := public.fn_param_int('troca_modulo_alerta_dias');

  v_chaves := '{}';

  for r in select l.turma_id,
                  'TROCA_MODULO:' || l.turma_id::text || ':'
                    || l.modulo_corrente_cronograma_id::text as chave,
                  (case when l.situacao_troca = 'HOJE_OU_VENCIDA' then 'ALTA' else 'MEDIA' end)
                    as severidade,
                  format('Turma %s (%s): o módulo %s %s. Alinhar a troca de módulo com o professor%s.',
                         l.turma_nome, l.curso_nome, l.modulo_corrente_nome,
                         case
                           when l.dias_para_troca > 0 then
                             format('termina em %s, em %s dia(s)',
                                    to_char(l.modulo_corrente_prev_conclusao, 'DD/MM/YYYY'),
                                    l.dias_para_troca)
                           when l.dias_para_troca = 0 then 'termina hoje'
                           else
                             format('tinha previsão de terminar em %s, há %s dia(s)',
                                    to_char(l.modulo_corrente_prev_conclusao, 'DD/MM/YYYY'),
                                    -l.dias_para_troca)
                         end,
                         case
                           when l.troca_de_livro then
                             format(' — o próximo módulo, %s, é de outro livro (%s)',
                                    l.proximo_modulo_nome, l.proximo_material_nome)
                           else ''
                         end)
                    as descricao
             from public.v_turma_modular_lotacao l
            where l.unidade_id = v_unidade
              and l.situacao_troca in ('PROXIMA', 'HOJE_OU_VENCIDA')
            order by l.turma_nome, l.turma_id
  loop
    v_chaves := v_chaves || r.chave;

    -- (a): o alinhamento deste módulo desta turma já foi registrado por alguém
    if not exists (select 1
                     from public.pendencia p
                    where p.unidade_id = v_unidade
                      and p.chave_dedup = r.chave
                      and p.resolucao = 'RESOLVIDA'
                      and p.resolvida_por is not null) then
      perform public.fn_pendencia_abrir(
        'TROCA_MODULO_ALINHAR', r.chave, r.descricao, r.severidade);
    end if;
  end loop;

  -- (b): a turma já trocou de módulo e a pendência do módulo anterior continua
  -- aberta — fica, e em ALTA. `fn_pendencia_abrir` só refresca a descrição e a
  -- severidade: a pendência está aberta por construção do `where`.
  for r in select p.chave_dedup as chave,
                  format('Turma %s (%s): o módulo %s foi concluído sem o alinhamento com o professor registrado.',
                         t.nome, c.nome, m.nome) as descricao
             from public.pendencia p
             join public.turma_modular_modulo tm
               on p.chave_dedup = 'TROCA_MODULO:' || tm.turma_id::text || ':' || tm.id::text
             join public.turma_modular t on t.id = tm.turma_id
             join public.curso  c on c.id = t.curso_id
             join public.modulo m on m.id = tm.modulo_id
            where p.unidade_id = v_unidade
              and p.tipo = 'TROCA_MODULO_ALINHAR'
              and p.resolvida_em is null
              and tm.concluido
              and t.ativo
            order by t.nome, tm.id
  loop
    v_chaves := v_chaves || r.chave;
    perform public.fn_pendencia_abrir(
      'TROCA_MODULO_ALINHAR', r.chave, r.descricao, 'ALTA');
  end loop;

  -- (c)
  perform public.fn_pendencias_fechar_ausentes('TROCA_MODULO_ALINHAR', v_chaves);

  -- ---------------------------------------------------------------------------
  -- BLOCO_ACIMA_CAPACIDADE saiu daqui no card 5.4, e continua fora
  -- ---------------------------------------------------------------------------
  -- O dono é fn_revalidar_blocos_sala, como o catálogo §10.1 sempre disse, e
  -- quem a chama todo dia é rt_capacidades — que rt_diaria executa ANTES desta
  -- rotina. Manter a cópia aqui seria manter duas implementações da mesma
  -- comparação, livres para divergir na primeira vez que alguém mexer numa só.
end $$;

comment on function public.rt_pendencias_diaria() is
  'Abre E fecha, na unidade do contexto corrente, as pendências de TEMPO e de ESTADO que o catálogo §10.1 lhe dá: ALUNO_SEM_TURMA (ALTA, as duas formas de turma desde o card 7.1), ACELERAR_SEM_2O_BLOCO (BAIXA, contando só blocos de tipo <> REP), STANDBY_PROLONGADO (MEDIA, status_desde acima de standby_alerta_dias — borda >, nunca >=), PREVISAO_VENCIDA (MEDIA, prev_conclusao_curso no passado para ATIVO/ACELERAR — MENOS o aluno em turma Modular ativa, cuja previsão é calculada: card 9.2,885), ESTOQUE_ABAIXO_MINIMO (BAIXA, abaixo_minimo de v_estoque_atual, só material ATIVO e com mínimo > 0 — card 8.4,5) e TROCA_MODULO_ALINHAR (MEDIA na janela de troca_modulo_alerta_dias, ALTA no dia da troca, lendo situacao_troca de v_turma_modular_lotacao — card 9.2,85; resolvida por gente NÃO reabre para o mesmo módulo, e avançar o módulo não a fecha). BLOCO_ACIMA_CAPACIDADE saiu daqui no card 5.4 e é de fn_revalidar_blocos_sala; ALUNO_ULTIMO_LIVRO é de fn_registrar_entrega (card 6.3) e, para o Modular, de fn_aluno_modular_avaliar_certificado.';

revoke execute on function public.rt_pendencias_diaria() from public;
revoke execute on function public.rt_pendencias_diaria() from anon;
revoke execute on function public.rt_pendencias_diaria() from authenticated;
