/// O link com que o app foi aberto — o de **convite** (card 4.7) e o de
/// **recuperação de senha** — e o que ele de fato produziu (card 9.2,80).
///
/// O achado do card 3.8, medido no deploy de homologação: o convite não define
/// senha. A pessoa abre o link, ganha sessão válida e cai dentro do app — sem
/// senha cadastrada. No acesso seguinte o login por senha simplesmente não
/// funciona, e nada na tela disse que faltava um passo; a saída era adivinhar
/// que "Esqueci minha senha" resolve.
///
/// O que o Auth devolve no link de convite e no de recuperação (fluxo
/// implícito — card 9.2,80) é a sessão no fragmento da URL com o `type`
/// (`#access_token=…&type=invite` ou `type=recovery`). Depois de criada a
/// sessão, um convidado é indistinguível de um login. Ou seja: o **único**
/// momento em que dá para saber que a pessoa chegou por link é antes de a
/// sessão ser criada. Por isso `main` lê `Uri.base` antes de qualquer outra
/// coisa e guarda o tipo aqui; o roteador leva a pessoa à tela de definir
/// senha antes de qualquer outra tela.
///
/// ⚠️ **Card 9.2,80 — a senha trocada foi a de QUEM ESTAVA LOGADO.** Em
/// 01/10/2026 o link de convite do Laurence, vencido, foi aberto num desktop
/// em que a sessão do Lindomar estava aberta: o Auth recusou o link, a sessão
/// que SOBROU foi a do Lindomar, e a tela de senha trocou a senha dele. O
/// `type` da URL diz o que o link PRETENDIA; só a troca do link por sessão diz
/// o que ele PRODUZIU. Por isso a troca é feita aqui, por [trocarPorSessao], e
/// não mais pelo `supabase_flutter` sozinho (que engole a falha num log): o
/// resultado — de quem é a sessão que o link criou, ou por que ele falhou —
/// fica registrado, e [autorizaTroca] é a guarda que a tela e o repositório
/// consultam antes de qualquer `updateUser`.
library;

/// O tipo do link, pelo `type` que o Auth põe na URL de retorno.
enum TipoLinkInicial { nenhum, convite, recuperacao, outro }

/// Lê o `type` da query OU do fragmento — o fluxo implícito (convite,
/// recuperação, magic link) o devolve no fragmento; o PKCE, na query.
TipoLinkInicial tipoDoLink(Uri uri) {
  final tipo = _parametro(uri, 'type');
  return switch (tipo) {
    null || '' => TipoLinkInicial.nenhum,
    'invite' => TipoLinkInicial.convite,
    'recovery' => TipoLinkInicial.recuperacao,
    _ => TipoLinkInicial.outro,
  };
}

/// A URL é um retorno do Auth — o mesmo critério do `supabase_flutter`
/// (`_defaultIsAuthCallbackDeeplink`): token, código PKCE ou erro, na query
/// ou no fragmento.
bool ehRetornoDoAuth(Uri uri) =>
    _parametrosDoAuth.any((chave) => _parametro(uri, chave) != null);

/// O erro que o Auth pôs na URL ao recusar o link: `error_code` (o específico,
/// `otp_expired`) e, sem ele, `error` (o genérico, `access_denied`). Nulo
/// quando a URL não traz erro.
String? erroDaUrl(Uri uri) {
  for (final chave in const ['error_code', 'error', 'error_description']) {
    final valor = _parametro(uri, chave);
    if (valor != null && valor.isNotEmpty) {
      return chave == 'error_description' ? codigoLinkInvalido : valor;
    }
  }
  return null;
}

/// Os parâmetros que o Auth acrescenta à URL de retorno — e que não podem
/// ficar na barra de endereço depois de lidos (o token é uma credencial).
const _parametrosDoAuth = [
  'access_token',
  'code',
  'error',
  'error_code',
  'error_description',
];

/// Código registrado quando o link chega com `?code=` (PKCE) e a troca falha.
/// Desde o card 9.2,80 o app pede links no fluxo implícito; um `?code=` é um
/// link pedido ANTES da mudança, aberto num navegador que não guarda o
/// verificador — só abre no mesmo navegador (e na mesma janela, normal ou
/// anônima) em que foi pedido.
const codigoLinkOutroNavegador = 'link_outro_navegador';

/// Código registrado quando a troca falha sem código do servidor.
const codigoLinkInvalido = 'link_invalido';

String? _parametro(Uri uri, String chave) =>
    uri.queryParameters[chave] ?? _parametrosDoFragmento(uri.fragment)[chave];

Map<String, String> _parametrosDoFragmento(String fragmento) {
  if (fragmento.isEmpty) return const {};
  try {
    return Uri.splitQueryString(fragmento);
  } on FormatException {
    return const {};
  }
}

/// Uma exceção do Auth vista pelo que importa aqui: o `code` (nulo quando o
/// servidor não mandou nenhum). Função, e não o tipo do pacote, para este
/// arquivo continuar sem dependência do Supabase e testável sozinho.
typedef CodigoDoErro = String? Function(Object erro);

/// O registro do link inicial — feito uma vez, em `main`, antes de a sessão
/// ser criada; completado por [trocarPorSessao] logo depois do
/// `Supabase.initialize`.
abstract final class LinkInicial {
  static TipoLinkInicial tipo = TipoLinkInicial.nenhum;

  /// Por que o link não produziu sessão: o `error_code` da URL
  /// (`otp_expired`), o código da troca que falhou, ou
  /// [codigoLinkOutroNavegador]. Nulo quando não houve falha.
  static String? erro;

  /// O usuário da sessão que o LINK criou. É contra ele que a tela confere a
  /// sessão corrente antes de trocar a senha.
  static String? usuarioId;

  static Uri? _retorno;

  static void registrar(Uri uri) {
    tipo = tipoDoLink(uri);
    _retorno = ehRetornoDoAuth(uri) ? uri : null;
    erro = _retorno == null ? null : erroDaUrl(uri);
    usuarioId = null;
  }

  /// Troca o link por sessão e registra o desfecho. [trocar] devolve o id do
  /// usuário da sessão criada (em `main`, `auth.getSessionFromUrl`).
  ///
  /// Nunca lança: link que falha é um estado da tela de senha, não um erro de
  /// inicialização do app.
  static Future<void> trocarPorSessao(
    Future<String> Function(Uri uri) trocar, {
    CodigoDoErro? codigoDoErro,
  }) async {
    final uri = _retorno;
    if (uri == null || erro != null) return;
    try {
      usuarioId = await trocar(uri);
    } catch (falha) {
      usuarioId = null;
      erro = _parametro(uri, 'code') != null
          ? codigoLinkOutroNavegador
          : codigoDoErro?.call(falha) ?? codigoLinkInvalido;
    }
  }

  /// Há um link de senha a tratar — convite ou recuperação, valendo ou não —,
  /// ou um link que o Auth recusou. O roteador leva à tela de senha, que diz
  /// qual dos casos é.
  static bool get pendente =>
      tipo == TipoLinkInicial.convite ||
      tipo == TipoLinkInicial.recuperacao ||
      erro != null;

  /// A pessoa chegou por convite e ainda não definiu a senha.
  static bool get convitePendente => tipo == TipoLinkInicial.convite;

  /// ⚠️ A GUARDA do card 9.2,80: a senha da sessão [usuarioAtualId] só pode
  /// ser trocada quando essa sessão VEIO de um link de convite ou de
  /// recuperação que valeu. Sessão que já estava aberta no navegador — de
  /// outra pessoa ou da própria — não passa.
  static bool autorizaTroca(String? usuarioAtualId) =>
      (tipo == TipoLinkInicial.convite ||
          tipo == TipoLinkInicial.recuperacao) &&
      erro == null &&
      usuarioId != null &&
      usuarioId == usuarioAtualId;

  /// Senha definida, ou a pessoa saiu da tela: o registro deixa de valer. O
  /// link é de uso único, e a autorização que ele deu também.
  static void consumir() {
    tipo = TipoLinkInicial.nenhum;
    erro = null;
    usuarioId = null;
    _retorno = null;
  }
}
