/// O link com que o app foi aberto — em especial, o do **convite** (card 4.7).
///
/// O achado do card 3.8, medido no deploy de homologação: o convite não define
/// senha. A pessoa abre o link, ganha sessão válida e cai dentro do app — sem
/// senha cadastrada. No acesso seguinte o login por senha simplesmente não
/// funciona, e nada na tela disse que faltava um passo; a saída era adivinhar
/// que "Esqueci minha senha" resolve.
///
/// O que o Auth devolve no link de convite (gerado pela Admin API — pelo painel
/// ou pela Edge Function) é a sessão no fragmento da URL com `type=invite`
/// (`#access_token=…&type=invite`). O `supabase_flutter` cria a sessão a partir
/// dele e emite um `signedIn` comum — indistinguível de um login —, e depois
/// limpa a URL. Ou seja: o **único** momento em que dá para saber que a pessoa
/// chegou por convite é antes de o `Supabase.initialize` rodar. Por isso
/// `main` lê `Uri.base` antes de qualquer outra coisa e guarda o tipo aqui; o
/// roteador leva a pessoa à tela de definir senha antes de qualquer outra tela,
/// e a tela consome o registro quando a senha estiver definida.
///
/// O mesmo vale para o link de recuperação de senha (`type=recovery`), que o
/// `supabase_flutter` já trata com o evento `passwordRecovery`; aqui ele só é
/// reconhecido, não é usado.
library;

/// O tipo do link, pelo `type` que o Auth põe na URL de retorno.
enum TipoLinkInicial { nenhum, convite, recuperacao, outro }

/// Lê o `type` da query OU do fragmento — o Auth devolve o fluxo implícito
/// (convite pelo painel, magic link) no fragmento e o PKCE na query.
TipoLinkInicial tipoDoLink(Uri uri) {
  final tipo = uri.queryParameters['type'] ?? _parametros(uri.fragment)['type'];
  return switch (tipo) {
    null || '' => TipoLinkInicial.nenhum,
    'invite' => TipoLinkInicial.convite,
    'recovery' => TipoLinkInicial.recuperacao,
    _ => TipoLinkInicial.outro,
  };
}

Map<String, String> _parametros(String fragmento) {
  if (fragmento.isEmpty) return const {};
  try {
    return Uri.splitQueryString(fragmento);
  } on FormatException {
    return const {};
  }
}

/// O registro do link inicial — feito uma vez, em `main`, antes de o
/// `supabase_flutter` limpar a URL.
abstract final class LinkInicial {
  static TipoLinkInicial tipo = TipoLinkInicial.nenhum;

  static void registrar(Uri uri) => tipo = tipoDoLink(uri);

  /// A pessoa chegou por convite e ainda não definiu a senha.
  static bool get convitePendente => tipo == TipoLinkInicial.convite;

  /// Senha definida (ou link inválido): o registro deixa de valer.
  static void consumir() => tipo = TipoLinkInicial.nenhum;
}
