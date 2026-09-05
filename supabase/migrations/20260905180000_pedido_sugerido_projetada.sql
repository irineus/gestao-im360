-- =============================================================================
-- Card 8.2 — a parcela PROJETADA chega ao pedido sugerido
-- Documentos que mandam: docs/views-leitura.md §6 e §6.2 (o SQL da troca),
--                        docs/projecao-demanda.md §8 (o encaixe e as três
--                        confirmações), docs/estrategia-testes.md §6.3 e §13
--                        (a obrigação de um card de View).
--
--   sugerido = imediata + projetada(H) + estoque_mínimo − estoque − não recebido
--
-- ⚠️ ESTE ARQUIVO É UM `create or replace view` E NADA MAIS, e isso não é
--    economia — é o que o card 6.4 comprou. `create or replace view` não insere
--    coluna no meio, não renomeia e não troca tipo: só acrescenta no fim. O 6.4
--    reservou `qtd_projetada` como `0::integer` NA POSIÇÃO DEFINITIVA (§6.2)
--    justamente para que aqui não houvesse `drop view` — que derrubaria em
--    cascata tudo o que depende dela — nem coluna pendurada fora de ordem. O
--    teste 095 §13 assere a posição pelo catálogo (10ª de 12, `qtd_sugerida` na
--    última) e foi visto VERMELHO recriando a view com a coluna no fim.
--
-- MUDAM DUAS EXPRESSÕES, e é literalmente o que o §6.2 escreveu:
--   (1) `0::integer`  →  `coalesce(dp.qtd_projetada, 0)::integer`;
--   (2) `+ 0` dentro do `greatest`  →  `+ coalesce(dp.qtd_projetada, 0)`.
-- Mais o `left join` que as alimenta. Nome, tipo e ordem das doze colunas ficam
-- exatamente como estavam — o app lê por lista de colunas nomeadas
-- (`_colunasSugerido`, em app/lib/compras/compras_repositorio.dart) e a tela já
-- desenha a coluna Projetada desde o card 6.8.
--
-- TRÊS ESCOLHAS QUE O DOCUMENTO FECHA, E QUE A MIGRAÇÃO NÃO PODE SIMPLIFICAR:
--
--   (a) A JANELA É DE MÊS INTEIRO (§6 do card 2.3, §2.1 da projeção).
--       `projecao_horizonte_dias` (60) é em dias, mas o grão de
--       `demanda_projetada` é o mês: entram os meses de
--       `date_trunc('month', fn_hoje())` até
--       `date_trunc('month', fn_hoje() + projecao_horizonte_dias)`, INTEIROS.
--       Com 60 dias em 20/03 entram março, abril e maio completos. O
--       arredondamento é para mais, de propósito: sobra de apostila é capital
--       parado, falta é aula perdida. `between` sobre `mes` funciona porque a
--       coluna tem `check (mes = date_trunc('month', mes)::date)` — o dia é
--       sempre 1, então o limite superior não corta meio mês.
--
--   (b) SOMA-SE SOBRE TODAS AS REGRAS E TODOS OS MESES DA JANELA, sem
--       `distinct` e sem filtrar `regra`. A projeção guarda uma linha por
--       (material, mês, regra), e um aluno produz UMA linha — a regra é única
--       por aluno (projeção §2.2) e `aluno_material_uk` impede o mesmo material
--       duas vezes na trilha. Não há dupla contagem entre degraus da cascata, e
--       somar as quatro regras é somar alunos distintos.
--
--   (c) A PARCELA IMEDIATA E A PROJETADA SÃO DISJUNTAS, e a fórmula do plano só
--       está certa por causa disso. Quem garante é o `where k >= 2` de
--       `v_projecao_aluno` (card 8.1): a projeção começa no SEGUNDO item
--       pendente da trilha, porque o primeiro já é `v_demanda_imediata`. Sem
--       essa linha, todo aluno ativo pesaria DUAS VEZES no pedido sugerido — e
--       o número continuaria parecendo plausível ao lado dos outros. A
--       consequência é asserida no 080 §9, não a linha.
--
-- ⚠️ LÊ-SE `v_demanda_projetada`, NUNCA `demanda_projetada` (card 2.3 §5.3). A
--    view existe para que o dia em que a projeção deixar de ser materializada
--    não mude nada acima dela. Ler a tabela aqui desfaria isso em uma linha.
--
-- ⚠️ `fn_param_int` é `security definer` (card 3.4): dentro de uma view
--    `security_invoker` ela continua lendo `parametro` com os direitos do dono,
--    e o horizonte não vira 60 para uns e nulo para outros conforme a RLS. Se
--    algum dia ela virar `invoker`, a janela desta view colapsa em silêncio.
--
-- Migração de CONFIGURAÇÃO E ESTRUTURA — não grava dado de negócio nenhum
-- (decisão de 02/09/2026, portão do card 4.0,5).
-- =============================================================================

create or replace view public.v_pedido_sugerido with (security_invoker = on) as
select e.unidade_id,
       e.material_id,
       e.metodo_id,
       e.codigo,
       e.nome,
       e.categoria,
       e.saldo,
       e.estoque_minimo,
       coalesce(di.qtd_alunos, 0)::integer         as qtd_imediata,
       -- (1) a primeira das duas expressões do §6.2 — era `0::integer`.
       coalesce(dp.qtd_projetada, 0)::integer      as qtd_projetada,
       coalesce(pp.qtd_pendente, 0)::integer       as qtd_pedida_pendente,
       greatest(
         coalesce(di.qtd_alunos, 0)
         -- (2) a segunda — era `+ 0`.
         + coalesce(dp.qtd_projetada, 0)
         + e.estoque_minimo
         - e.saldo
         - coalesce(pp.qtd_pendente, 0),
         0)::integer                               as qtd_sugerida
  from public.v_estoque_atual e
  left join public.v_demanda_imediata di
         on di.unidade_id = e.unidade_id and di.material_id = e.material_id
  left join (
         select pi.unidade_id, pi.material_id,
                -- `greatest(…, 0)` POR ITEM (card 6.5): item recebido com
                -- excedente tem pendente negativo, e um negativo aqui abateria a
                -- necessidade de OUTRO material do mesmo pedido.
                sum(greatest(pi.qtd_pedida - pi.qtd_recebida, 0))::integer as qtd_pendente
           from public.pedido_item pi
           join public.pedido_compra pc on pc.id = pi.pedido_id
          where pc.status in ('ENVIADO','PARCIAL')
          group by pi.unidade_id, pi.material_id
       ) pp on pp.unidade_id = e.unidade_id and pp.material_id = e.material_id
  -- O `left join` novo: a soma da projeção na janela do horizonte. `left`, e não
  -- `join`: material sem projeção nenhuma continua na lista com a parcela zero —
  -- sumir dali é o oposto do que o §2.3 pede, e o material sem demanda alguma é
  -- justamente o que entra com a sugestão igual ao mínimo.
  left join (
         select d.unidade_id, d.material_id, sum(d.quantidade)::integer as qtd_projetada
           from public.v_demanda_projetada d
          where d.mes between date_trunc('month', public.fn_hoje())::date
                          and date_trunc('month',
                                public.fn_hoje()
                                + public.fn_param_int('projecao_horizonte_dias'))::date
          group by d.unidade_id, d.material_id
       ) dp on dp.unidade_id = e.unidade_id and dp.material_id = e.material_id
 where e.ativo;

comment on view public.v_pedido_sugerido is
  'Pedido sugerido COMPLETO (card 2.3 §6, fechado no card 8.2): imediata + projetada + mínimo − saldo − pendente, com greatest(…,0). Devolve TODO material ativo, inclusive com qtd_sugerida = 0 — quem filtra é a tela. Leitura exige materiais.ler, estoque.ler, alunos.ler E compras.ler: qualquer uma que falte devolve número menor sem erro nenhum.';

comment on column public.v_pedido_sugerido.qtd_projetada is
  'Soma de v_demanda_projetada.quantidade sobre TODAS as regras e todos os meses da janela [mês corrente, mês de fn_hoje() + projecao_horizonte_dias], meses inteiros (card 8.2). Disjunta da parcela imediata: a projeção começa no SEGUNDO item pendente da trilha, e sem isso todo aluno ativo pesaria duas vezes na compra. Zero significa "sem projeção calculada para este material nesta janela" — a rotina rt_projecao_demanda é quem a preenche.';

comment on column public.v_pedido_sugerido.qtd_pedida_pendente is
  'qtd_pedida − qtd_recebida somada por ITEM, com piso zero por item (card 6.5), só de pedidos ENVIADO e PARCIAL. RASCUNHO não abate (nunca foi feito a ninguém), RECEBIDO já está no saldo e CANCELADO não virá.';

-- `create or replace view` preserva os privilégios, mas repeti-los aqui é o que
-- mantém o arquivo legível sozinho — e o que garante o estado certo se um dia
-- alguém trocar o `replace` por `drop`/`create`.
revoke all   on public.v_pedido_sugerido from public;
revoke all   on public.v_pedido_sugerido from anon;
grant select on public.v_pedido_sugerido to authenticated;
