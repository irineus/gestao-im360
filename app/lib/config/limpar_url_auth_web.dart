import 'package:web/web.dart' as web;

/// Os parâmetros que o Auth acrescenta à URL de retorno, no fragmento
/// (fluxo implícito) ou na query (PKCE e erros).
const _chavesDoAuth = {
  'access_token',
  'refresh_token',
  'expires_in',
  'expires_at',
  'token_type',
  'provider_token',
  'provider_refresh_token',
  'type',
  'sb',
  'code',
  'error',
  'error_code',
  'error_description',
};

/// Remove da URL os parâmetros do Auth, sem recarregar a página.
///
/// Era o `supabase_flutter` quem fazia isto, e só quando a troca dava certo.
/// Desde o card 9.2,80 o app troca o link por sessão por conta própria
/// (`LinkInicial.trocarPorSessao`), e limpa nos DOIS desfechos: o token é uma
/// credencial e não pode ficar no histórico do navegador, e o erro, se ficasse,
/// voltaria a ser lido a cada recarga. O fragmento sai inteiro — com a rota no
/// caminho (card 3.8), ele nunca é rota; é sempre do Auth.
void limparUrlDoAuth() {
  final atual = Uri.parse(web.window.location.href);
  final consulta = {
    for (final e in atual.queryParameters.entries)
      if (!_chavesDoAuth.contains(e.key)) e.key: e.value,
  };
  final limpa = StringBuffer(atual.path.isEmpty ? '/' : atual.path);
  if (consulta.isNotEmpty) {
    limpa.write('?${Uri(queryParameters: consulta).query}');
  }
  web.window.history.replaceState(null, '', limpa.toString());
}
