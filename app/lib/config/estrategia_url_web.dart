import 'package:flutter_web_plugins/url_strategy.dart';

/// Tira a rota do fragmento (`/#/alunos` → `/alunos`).
///
/// Não é preferência estética: **o fragmento é do Supabase**. Todo link que o
/// Auth gera fora do fluxo PKCE do próprio app — convite e "magic link" pelo
/// painel, que é como a v1 cria usuário (`docs/acesso-autenticacao.md` §3.1) —
/// volta como `<url>#access_token=…&sb=&type=invite`. Com a rota no fragmento,
/// o `supabase_flutter` cria a sessão, limpa os parâmetros de auth e sobra
/// `#sb`: o `go_router` navega para `/sb` e a pessoa cai em "Esta tela não
/// existe" **já autenticada**. Medido em 01/09/2026 contra o stack local.
///
/// A contrapartida vive no servidor: com a rota no caminho, `GET /alunos`
/// precisa devolver o `index.html`. É o que `web/_redirects` faz no Cloudflare
/// Pages.
void usarUrlPorCaminho() => usePathUrlStrategy();
