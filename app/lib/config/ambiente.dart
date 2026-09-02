/// Configuração por ambiente, injetada em build time com `--dart-define`
/// (card 3.8: um projeto de Pages por ambiente, com valores diferentes).
///
/// A chave anônima é pública por desenho — vai no bundle do Flutter — e por
/// isso o cadastro público está fechado no Auth (card 3.5 §2). A *service key*
/// **nunca** entra aqui: `service_role` tem `BYPASSRLS` (card 3.3).
abstract final class Ambiente {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Base pública do app, usada para montar o `redirectTo` da recuperação de
  /// senha. Precisa estar nas Redirect URLs dos dois projetos (card 3.8).
  static const urlBase = String.fromEnvironment('APP_URL_BASE');

  /// DSN do Sentry (card 3.12). **Sem ele o Sentry não inicializa** — é o que
  /// mantém `flutter run` e a suíte sem mandar nada para lugar nenhum, e o que
  /// deixa um build de emergência subir sem depender de terceiro.
  ///
  /// O DSN é público por desenho, como a chave anônima: ele vai no bundle que
  /// qualquer visitante baixa. O que ele autoriza é *escrever* evento no
  /// projeto, nunca ler — não confundir com a *service key*.
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  static const rotaRedefinicaoSenha = '/redefinir-senha';

  /// Rótulo do ambiente, que vira o `environment` do Sentry (card 3.12).
  /// `homologacao`, `producao`, ou `local` num build sem define.
  ///
  /// ⚠️ Este valor **foi derivado do ****`supabaseUrl`**** e a derivação foi
  /// desfeita** (02/09/2026, medido). Derivar exigia citar os dois refs de
  /// projeto como literais aqui — e `String.fromEnvironment` é `const`, então
  /// os dois ficavam embutidos no `main.dart.js` de **todos** os bundles. O ref
  /// é público (está no `_headers` e no `deploy-web.yml`), então não era
  /// vazamento; o dano era outro e pior: o card 3.9 prova que os dois bundles
  /// não se confundem justamente conferindo que o de homologação **não contém**
  /// a URL de produção, e essa contraprova passava a falhar para sempre. Uma
  /// conveniência de configuração teria custado um método de verificação.
  ///
  /// A fonte única continua existindo, só que um degrau acima: no
  /// `deploy-web.yml` os três valores saem da **mesma** expressão sobre
  /// `github.ref_name`, e o passo de conferência exige que o bundle carregue o
  /// rótulo do ambiente que ele diz ser.
  static const ambiente = String.fromEnvironment(
    'APP_AMBIENTE',
    defaultValue: 'local',
  );

  /// Sem `#`: a rota vive no caminho (`lib/config/estrategia_url.dart`), e o
  /// fragmento fica livre para os tokens que o Auth devolve.
  static String get urlRedefinicaoSenha => '$urlBase$rotaRedefinicaoSenha';

  /// Sem os dois valores o app não sobe conectado a lugar nenhum. Falhar com
  /// uma tela que diz o que falta é melhor do que subir e dar erro de rede em
  /// toda consulta.
  static bool get configurado =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// `SENTRY_DSN` fica FORA desta lista de propósito: build sem observabilidade
  /// é um build pior, não um build quebrado. Quem reprova a sua ausência no
  /// caminho que importa é o `deploy-web` (card 3.9), não a tela.
  static List<String> get faltando => [
    if (supabaseUrl.isEmpty) 'SUPABASE_URL',
    if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
    if (urlBase.isEmpty) 'APP_URL_BASE',
  ];
}
