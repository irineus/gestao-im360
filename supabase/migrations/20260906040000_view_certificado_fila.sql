-- =============================================================================
-- View da tela 9 — Certificados (card 8.6)
-- docs/wireframes.md §12 · docs/views-leitura.md §8.1 e §12.1
--
-- `v_certificado_fila` é a sexta view de tela a nascer no card da própria tela,
-- depois de `v_aluno_trilha` (6.6), `v_material_movimento` (6.7),
-- `v_pedido_compra`/`v_pedido_item` (6.8), as três do 7.3 e as duas do 8.5.
-- O §12.1 de views-leitura.md já a nomeia com o card ao lado, e é a regra:
-- **view de listagem pertence ao card da tela**; o cuidado do §3 continua valendo.
--
-- O que a tela precisa e nenhuma view existente dá: "quem está chegando ao fim
-- do curso", com o resumo do checklist ao lado. `v_dashboard_alunos_metodo`
-- (card 2.3 §8.1) CONTA os dois grupos por método e não diz QUEM são; e
-- `certificado_checklist` só tem linha para quem já chegou ao FIM.
--
-- ⚠️ AS DUAS SITUAÇÕES, COM RÓTULO DISTINTO — é a divergência 2 do §17 de
--    wireframes.md, atribuída a este card desde 01/09/2026. O plano fala em
--    "fila do último livro" como se fosse uma coisa só, e o card 2.3 §8.1 já
--    tinha separado as duas: `em_ultimo_livro` é UM item pendente (o aluno está
--    RECEBENDO a última apostila, ainda com aula pela frente — é ele que dá
--    tempo de pedir o certificado) e `em_fim` é NENHUM (a trilha acabou, e é
--    aqui que fn_registrar_entrega abre o checklist). Juntá-las numa coluna só
--    seria perder exatamente a diferença que faz a fila ser útil.
--
-- ⚠️ ALUNO SEM TRILHA NENHUMA **NÃO** É FIM, e este é o filtro que o resto do
--    sistema não tem. `fn_trilha_em_fim` e a coluna `em_fim` do dashboard
--    devolvem `true` para quem nunca teve trilha (é "nenhum item pendente"), e o
--    comentário do card 6.2 diz com todas as letras: «quem precisa distinguir
--    "acabou" de "nunca começou" pergunta pela trilha, não por esta função».
--    Esta view é quem precisa: sem o `exists`, a fixture entrega Karina Bastos e
--    Aluno Modular 01 — dois ATIVOS sem trilha — como formandos prontos para o
--    certificado, e na escola real seria todo aluno recém-matriculado antes de a
--    trilha ser gerada. O teste 083 §2 mede isso, e a contraprova é vermelha.
--
-- ⚠️ SÓ ATIVO/ACELERAR, como o §8.1. FORMADO já recebeu — é o gate do card 2.2
--    §3.3 que exige `certificado_status = 'ENTREGUE'` para formar —, e mantê-lo
--    na fila deixaria todo formando da história na tela para sempre. CANCELADO e
--    TRANCADO não estão chegando ao fim de nada. O checklist de quem saiu da
--    fila continua alcançável pela aba Certificado da ficha, e a pendência
--    CERTIFICADO_INCONSISTENTE (card 8.3) é quem manda olhar o caso em que ele
--    ficou para trás.
--
-- ⚠️ `left join` em `certificado_checklist`, e o nulo é INFORMAÇÃO: quem está em
--    ULTIMO_LIVRO ainda não tem checklist (ele nasce no passo 9 da entrega que
--    fecha a trilha), e é a tela que oferece abri-lo à mão por
--    fn_certificado_abrir — que é idempotente e resolve `data_fim_curso` por
--    `fn_hoje()` justamente para este caso, escrito no card 8.3. Um `join`
--    interno esconderia a metade da fila que existe para dar TEMPO.
--
-- ⚠️ `join` INTERNO em `metodo`, e a consequência é a do card 2.3 §3.4: sem
--    `materiais.ler` a fila vem VAZIA, não errada. É o mesmo desenho de
--    `v_projecao_material_mes` (8.5) e de `v_turma_modular_lotacao` (7.3), e por
--    isso a rota da tela 9 ganhou `materiais.ler` neste card — os quatro perfis
--    já o têm (docs/permissoes-matriz.md §5.1, item 1), então nenhum perfil
--    perde a tela.
-- =============================================================================

create view public.v_certificado_fila with (security_invoker = on) as
select a.unidade_id,
       a.id            as aluno_id,
       a.nome          as aluno_nome,
       a.codigo_sgf,
       a.status        as aluno_status,
       a.metodo_id,
       me.codigo       as metodo_codigo,
       me.nome         as metodo_nome,
       -- Os dois rótulos do §8.1. `FIM` primeiro na leitura da tela porque é
       -- quem já não tem prazo nenhum pela frente.
       case when pend.qtd = 0 then 'FIM' else 'ULTIMO_LIVRO' end as situacao,
       pend.qtd        as itens_pendentes,
       -- ⚠️ As cinco colunas abaixo são NULAS quando não há checklist, e nulo
       --    NÃO é `false`: "ainda não abriram o checklist deste aluno" e "o
       --    checklist existe e o pedagógico ainda não assinou" são coisas
       --    diferentes, e a tela desenha um traço para a primeira e uma caixa
       --    vazia para a segunda.
       cc.id           as checklist_id,
       cc.data_fim_curso,
       cc.pedagogico_ok,
       cc.financeiro_ok,
       cc.formatura,
       cc.certificado_status
  from public.aluno a
  join public.metodo me on me.id = a.metodo_id
  cross join lateral (
         select count(*)::integer as qtd
           from public.aluno_material am
          where am.aluno_id = a.id and not am.entregue
       ) pend
  left join public.certificado_checklist cc on cc.aluno_id = a.id
 where a.status in ('ATIVO', 'ACELERAR')
   and pend.qtd <= 1
   -- O filtro que separa "acabou" de "nunca começou" (ver o aviso do topo).
   and exists (select 1
                 from public.aluno_material am
                where am.aluno_id = a.id);

comment on view public.v_certificado_fila is
  'Fila da tela 9 (docs/wireframes.md §12.1): os alunos ATIVO/ACELERAR que estão chegando ao fim do curso, com o resumo do checklist ao lado. Duas situações com rótulo distinto (card 2.3 §8.1): ULTIMO_LIVRO = 1 item pendente (dá tempo de pedir o certificado) e FIM = nenhum. Exige trilha existente — sem isso, aluno recém-matriculado apareceria como formando, porque "nenhum item pendente" também é verdade para quem nunca teve trilha (card 6.2). O left join em certificado_checklist deixa as cinco colunas do checklist NULAS para quem ainda não o tem, e é a tela que oferece abri-lo por fn_certificado_abrir. Leitura exige alunos.ler, materiais.ler (join interno em metodo) e certificados.ler (as colunas do checklist).';

revoke all   on public.v_certificado_fila from public;
revoke all   on public.v_certificado_fila from anon;
grant select on public.v_certificado_fila to authenticated;
