-- =============================================================================
-- O nome de quem fez, no histórico, para quem não é da Administração
-- (card 9.2,74 — pendência 9.13(a) das Decisões vigentes, aberta desde o 4.6)
--
-- O DEFEITO: o embed `usuario:usuario_id(nome)` devolve NULO — não erro —
-- quando a política de `usuario` não deixa ler a linha, e só `admin.ler` e a
-- própria pessoa leem `usuario`. Na ficha do aluno a secretaria via o histórico
-- de status SEM o "quem"; no checklist de certificado o monitor lia o próprio
-- nome e nulo nos outros três; no painel de estoque, o "por …" sumia.
--
-- A DECISÃO (Irineu, 24/09/2026 — aprovada NESTE formato e só nele):
-- expor SÓ id e nome dos usuários da MESMA unidade; e-mail e perfis continuam
-- restritos a admin.ler. Qualquer coisa além disso volta a ser decisão.
--
-- Por que função e não view: toda view do projeto é `security_invoker` (C5),
-- e uma invoker sobre `usuario` herdaria a mesma política. A função é definer,
-- devolve duas colunas e filtra a unidade no corpo (C8). Nenhuma política de
-- `usuario` muda, e nenhum código de permissão é criado (o catálogo fica em 50).
-- =============================================================================

create function public.fn_usuarios_nomes()
returns table (id uuid, nome text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- Todos da unidade, ativos ou não: o histórico precisa do nome de quem já
  -- saiu da escola — é justamente o nome que ninguém mais lembra.
  select u.id, u.nome
    from public.usuario u
   where u.unidade_id = public.fn_unidade_atual()
$$;

comment on function public.fn_usuarios_nomes() is
  'Card 9.2,74 (pendência 9.13(a)): SÓ id e nome dos usuários da unidade de quem chama — o que os históricos (status do aluno, checklist de certificado, movimento de estoque) precisam para dizer QUEM fez. E-mail e perfis continuam sob a política de usuario (admin.ler). Definer com filtro de unidade no corpo; sem sessão com unidade, devolve nada. Abrir mais que id e nome é decisão de Irineu.';

revoke execute on function public.fn_usuarios_nomes() from public;
revoke execute on function public.fn_usuarios_nomes() from anon;
grant  execute on function public.fn_usuarios_nomes() to authenticated;

-- -----------------------------------------------------------------------------
-- v_material_movimento: o autor pelo nome, para quem lê estoque
-- (parte da definição do card 6.7, a única aplicada; colunas iguais)
-- -----------------------------------------------------------------------------
create or replace view public.v_material_movimento with (security_invoker = on) as
select mov.unidade_id,
       mov.id                                       as movimento_id,
       mov.material_id,
       mov.tipo,
       -- COM SINAL, como a coluna (card 6.1): a tela mostra "−1" e "+10", e a
       -- soma da lista fecha com o saldo de `v_estoque_atual`. Um valor absoluto
       -- com o sinal derivado do `tipo` recriaria em Dart o `case` por tipo que
       -- o card 2.1 tirou do banco de propósito.
       mov.quantidade,
       mov.ocorrido_em,
       mov.observacao,
       -- --- os quatro rótulos externos, todos `left join` ---------------------
       mov.aluno_id,
       a.nome                                       as aluno_nome,
       a.codigo_sgf                                 as aluno_codigo_sgf,
       mov.pedido_item_id,
       pc.numero                                    as pedido_numero,
       mov.estorno_de_id,
       orig.tipo                                    as estorno_de_tipo,
       orig.ocorrido_em                             as estorno_de_ocorrido_em,
       mov.criado_por,
       u.nome                                       as criado_por_nome
  from public.movimento_estoque mov
  left join public.aluno a
         on a.id = mov.aluno_id
  left join public.pedido_item pi
         on pi.id = mov.pedido_item_id
  left join public.pedido_compra pc
         on pc.id = pi.pedido_id
  -- O movimento estornado é da MESMA tabela e da mesma política (`estoque.ler`):
  -- este `left join` não abre nem fecha nada que a linha de cima já não decida.
  -- Continua externo porque `estorno_de_id` é nulo em três dos quatro tipos.
  left join public.movimento_estoque orig
         on orig.id = mov.estorno_de_id
  -- Card 9.2,74: o nome do autor sai de fn_usuarios_nomes(), que devolve SÓ
  -- id e nome da unidade de quem lê. Com o join direto em `usuario` a política
  -- dela (admin.ler ou a própria pessoa) zerava o nome para a secretaria e o
  -- monitor, e a tela omitia o "por …" (pendência 9.13(a)).
  left join public.fn_usuarios_nomes() u
         on u.id = mov.criado_por;

comment on column public.v_material_movimento.criado_por_nome is
  'Desde o card 9.2,74: o nome do autor para QUALQUER leitor da unidade, via fn_usuarios_nomes() (só id e nome). Nulo só quando o movimento não tem autor (carga da fixture ou da importação).';
