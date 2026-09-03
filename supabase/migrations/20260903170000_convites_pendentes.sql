-- =============================================================================
-- Card 4.7,7 — fn_convites_pendentes(): quem ainda não aceitou o convite
-- Fonte: achado de 03/09/2026 ao preparar o marco 4.8, docs/administracao.md,
--        docs/acesso-autenticacao.md §3.2
--
-- O problema que esta função existe para resolver é de DESCOBERTA, não de
-- comportamento: reenviar convite já funciona desde o card 4.7 (convidar de
-- novo com o mesmo e-mail devolve o MESMO usuario_id e dispara e-mail novo),
-- mas nada na tela conta isso, então quem precisa reenviar conclui que não dá.
-- A tela do card 4.7,7 passa a oferecer "Reenviar convite" na linha da pessoa —
-- e para isso precisa saber QUEM ainda não aceitou.
--
-- Por que uma função, e não uma coluna em `usuario`:
--
--   O estado mora em `auth.users.email_confirmed_at` e é o GoTrue quem o muda,
--   no momento em que a pessoa abre o link e define a senha. Espelhar isso numa
--   coluna exigiria mais um trigger em auth.users e um backfill, e a coluna
--   passaria a poder DIVERGIR do Auth em silêncio — a tela ofereceria "Reenviar
--   convite" a quem já aceitou (o GoTrue recusa com email_exists) ou o
--   esconderia de quem precisa. Lido na hora, o estado não tem como divergir.
--
-- Por que `email_confirmed_at`, e não `last_sign_in_at` ou `confirmed_at`:
--
--   É EXATAMENTE o pivô do GoTrue. O endpoint de convite recusa com
--   `email_exists` quando o usuário existe e está confirmado, e "confirmado"
--   ali é `email_confirmed_at is not null`. Então o conjunto que esta função
--   devolve não é uma aproximação de "ainda não aceitou": é a resposta literal
--   a "para quem o reenvio funciona" — que é a pergunta que a tela faz.
--   `confirmed_at` é coluna gerada e depende também do telefone, que este
--   projeto não usa; `last_sign_in_at` diria outra coisa (nunca entrou), e um
--   usuário criado já confirmado pelo painel do Auth cairia no lado errado.
--
-- security definer porque precisa ler `auth.users`, que nenhum papel do app
-- alcança — mesma justificativa de fn_usuario_espelho_coerente (card 3.5).
-- Entra na lista fechada do teste C8 com ela. O filtro de unidade está no
-- CORPO, como manda a correção do card 2.3.
-- =============================================================================

create or replace function public.fn_convites_pendentes()
returns setof uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select u.id
    from public.usuario u
    join auth.users a on a.id = u.id
   where u.unidade_id = public.fn_unidade_atual()
     and a.email_confirmed_at is null
     and public.tem_permissao('admin.ler');
$$;

comment on function public.fn_convites_pendentes() is
  'Ids dos usuários da unidade que ainda não aceitaram o convite — os únicos para quem convidar de novo reenvia o e-mail em vez de recusar com email_exists. Exige admin.ler, a mesma permissão da lista de usuários (card 4.7,7).';

-- `admin.ler` e não `admin.gerir_usuarios`, que é a permissão de reenviar: se o
-- portão fosse o da AÇÃO, quem tem `admin.ler` e não tem `admin.gerir_usuarios`
-- veria a lista inteira sem uma única marca de convite pendente — indistinguível
-- de "todo mundo já aceitou". É a família de falha calada que este projeto
-- cataloga (cards 2.3, 2.4, 3.4). Amarrada à visibilidade da LISTA, a marca é
-- verdadeira para quem quer que enxergue a linha; o botão continua exigindo
-- `admin.gerir_usuarios`, que é quem a Edge Function verifica de qualquer jeito.
--
-- Não abre nada de novo: quem tem `admin.ler` já lê a linha inteira de `usuario`
-- pela política usuario_sel (card 3.4). O que sai daqui é um booleano por linha
-- que ela já vê, e nenhuma outra coluna de auth.users atravessa a função.
revoke execute on function public.fn_convites_pendentes() from public;
revoke execute on function public.fn_convites_pendentes() from anon;
grant  execute on function public.fn_convites_pendentes() to authenticated;
