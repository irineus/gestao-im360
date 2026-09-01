-- =============================================================================
-- Infraestrutura de teste. Aplicada APENAS por `supabase db reset` (local/CI).
--
-- ⚠️ NUNCA mover nada deste arquivo para supabase/migrations/: migração é o que
--    o CI empurra para produção, e extensão de teste em prod é superfície de
--    ataque sem uso (card 2.8, ajuste #5).
-- ⚠️ `supabase db reset --linked` fica PROIBIDO: aplicaria isto no banco remoto.
--
-- Este arquivo nasce no card 3.3 com o mínimo de que a suíte de catálogo
-- precisa para rodar (pgTAP e o schema `tests`). Os helpers tests.criar_usuario
-- /autenticar/como_anonimo/encerrar_sessao/conta_como e a escola-fixture são do
-- card 3.4.5 e entram aqui embaixo — eles dependem de usuario_perfil (3.3) e de
-- tem_permissao (3.4), que ainda não existe.
--
-- Motivo de o bootstrap vir já no 3.3: o card 2.8 (§5) declara a suíte de
-- catálogo obrigatória "desde a primeira migração" e o §13 diz que nenhum card
-- de migração fecha com ela vermelha. Sem pgTAP instalado, a suíte escrita neste
-- card não roda em lugar nenhum até o 3.4.5 — o portão existiria no papel e não
-- reprovaria nada, que é exatamente a falha que o card 2.8 combate.
-- =============================================================================

create extension if not exists pgtap with schema extensions;

create schema if not exists tests;
revoke all on schema tests from public, anon, authenticated;
