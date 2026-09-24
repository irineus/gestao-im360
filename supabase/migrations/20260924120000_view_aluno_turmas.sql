-- =============================================================================
-- Card 9.2,6 — v_aluno_turmas: as DUAS formas de turma, vistas do lado do aluno
-- Fonte: nota do card 9.2,6 (defeito medido em 24/09/2026 no stack local),
--        docs/views-leitura.md §12.1 (view de tela é do card da tela),
--        20260905235500_alerta_estoque_minimo.sql (a última definição de
--        `rt_pendencias_diaria`, cujo bloco ALUNO_SEM_TURMA é a regra).
--
-- Entrega: UMA view de leitura (`security_invoker = on`, `unidade_id`, colunas
--          explícitas, `revoke`/`grant` do §2.5). Nenhuma função, nenhum
--          trigger, nenhuma linha de dado — view é estrutura, e as tabelas que
--          ela lê estão vazias em produção até a virada do card 9.7.
--
-- =============================================================================
-- O DEFEITO QUE ELA FECHA
-- =============================================================================
-- Desde o card 7.1, "nenhuma turma" quer dizer nenhuma das DUAS formas: bloco
-- de horário ATIVO (`v_bloco_alunos.bloco_ativo`) OU turma Modular ATIVA
-- (`turma_modular_aluno.ativo` e `turma_modular.ativo`). A rotina aprendeu a
-- segunda metade no dia em que a tabela nasceu; a TELA não aprendeu nunca — o
-- ⚠ de "sem turma" da lista de Alunos e a aba Turmas da ficha liam só
-- `v_bloco_alunos`. Eduarda Lima (3005), ATIVA na turma "Eletricista 2026.1",
-- aparecia como "sem turma" enquanto o banco, corretamente, não abria pendência
-- nenhuma para ela: tela e banco dizendo coisas opostas sobre o mesmo aluno, e
-- o ⚠ falso em TODO aluno Modular da escola.
--
-- A correção não é ensinar a segunda metade ao Dart — seria a segunda cópia da
-- regra, livre para divergir outra vez (card 5.4 (4)). É a tela ler do banco
-- as linhas já com a forma e o "conta como turma" decididos. A view devolve uma
-- linha por VÍNCULO ativo do aluno com uma turma, das duas formas, e a coluna
-- `turma_ativa` é o predicado da rotina, letra por letra:
--
--   • BLOCO   — `v_bloco_alunos` inteira, com `bloco_ativo` como `turma_ativa`.
--               Alocação em bloco DESATIVADO continua aparecendo (a ficha é a
--               única tela de onde alguém a desfaz, card 5.7) e não conta.
--   • MODULAR — `turma_modular_aluno.ativo` como FILTRO (quem saiu da turma não
--               está nela; o histórico de saída é da tela 5, por
--               `v_turma_modular_aluno`) e `turma_modular.ativo` como
--               `turma_ativa` — turma Modular desativada é a mesma órfã do bloco
--               desativado, e pelo mesmo motivo aparece e não conta.
--
-- ⚠️ A rotina NÃO passa a ler esta view, e é de propósito. Se as duas lessem a
--    mesma definição, apagar a metade Modular daqui deixaria tela e pendência
--    erradas JUNTAS e a asserção de paridade continuaria verde, sem medir nada.
--    Mantidas independentes, o teste 073 prende as duas pontas — "sem turma" da
--    view = aluno com ALUNO_SEM_TURMA depois de `rt_pendencias_diaria` —, e a
--    contraprova (tirar a metade Modular daqui) fica vermelha.
--
-- ⚠️ Os dois lados exigem as MESMAS permissões, e isso também é de propósito:
--    `v_bloco_alunos` faz `join` interno em `aluno` (card 5.7), então a metade
--    Modular também passa por `aluno` (via `v_turma_modular_aluno`). Sem isso um
--    perfil com `turmas.ler` e sem `alunos.ler` veria SÓ os vínculos Modular, e
--    todo aluno de bloco sairia "sem turma" — o ⚠ falso de volta, pelo outro
--    lado. Sem `turmas.ler` a view vem vazia, e quem esconde a coluna é a tela
--    (a mesma decisão do card 5.7).
--
-- `metodo_id` é o do BLOCO numa metade e o do ALUNO na outra: turma Modular não
-- tem método próprio (pertence a um curso), e o do aluno é o que a tela usa
-- para rotular. `sala_id` é o da sala em que a turma acontece, nas duas.
-- =============================================================================

create view public.v_aluno_turmas with (security_invoker = on) as
select t.unidade_id,
       'BLOCO'::text          as forma,
       t.alocacao_id,
       t.aluno_id,
       t.bloco_ativo          as turma_ativa,
       t.bloco_id,
       t.dia_semana,
       t.hora_inicio,
       t.metodo_id,
       t.sala_id,
       t.tipo,
       t.tipo_desde,
       t.data_inicio_prevista,
       null::uuid             as turma_modular_id,
       null::text             as turma_nome,
       null::date             as data_entrada
  from public.v_bloco_alunos t
union all
select ta.unidade_id,
       'MODULAR'::text        as forma,
       ta.alocacao_id,
       ta.aluno_id,
       tm.ativo               as turma_ativa,
       null::uuid             as bloco_id,
       null::smallint         as dia_semana,
       null::time             as hora_inicio,
       ta.metodo_id,
       tm.sala_id,
       null::text             as tipo,
       null::date             as tipo_desde,
       null::date             as data_inicio_prevista,
       tm.id                  as turma_modular_id,
       tm.nome                as turma_nome,
       ta.data_entrada
  from public.v_turma_modular_aluno ta
  join public.turma_modular tm on tm.id = ta.turma_id
 where ta.ativo;

comment on view public.v_aluno_turmas is
  'Os vínculos ATIVOS do aluno com turma, nas DUAS formas (card 9.2,6): BLOCO (v_bloco_alunos) e MODULAR (turma_modular_aluno ativa). turma_ativa é o predicado de ALUNO_SEM_TURMA em rt_pendencias_diaria — bloco ativo / turma Modular ativa —, e o complemento dela, entre os ATIVO/ACELERAR, é o ⚠ "sem turma" da lista de Alunos. A rotina NÃO lê esta view, de propósito: o teste 073 prende as duas pela paridade, e só assim a contraprova tem como ficar vermelha. Vínculo com turma desativada aparece e não conta (a ficha é de onde alguém o desfaz).';

comment on column public.v_aluno_turmas.forma is
  'BLOCO (bloco de horário semanal) ou MODULAR (turma Modular por curso). As colunas de bloco vêm nulas numa linha MODULAR, e as de turma Modular nulas numa linha BLOCO.';

comment on column public.v_aluno_turmas.turma_ativa is
  'Falso quando o bloco ou a turma Modular foi DESATIVADO com o aluno dentro. O vínculo continua existindo e aparece na ficha, mas não conta como turma — nem para o ⚠ da lista nem para ALUNO_SEM_TURMA.';

revoke all   on public.v_aluno_turmas from public;
revoke all   on public.v_aluno_turmas from anon;
grant select on public.v_aluno_turmas to authenticated;
