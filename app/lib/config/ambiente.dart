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

  static const rotaRedefinicaoSenha = '/redefinir-senha';

  /// Sem `#`: a rota vive no caminho (`lib/config/estrategia_url.dart`), e o
  /// fragmento fica livre para os tokens que o Auth devolve.
  static String get urlRedefinicaoSenha => '$urlBase$rotaRedefinicaoSenha';

  /// Sem os dois valores o app não sobe conectado a lugar nenhum. Falhar com
  /// uma tela que diz o que falta é melhor do que subir e dar erro de rede em
  /// toda consulta.
  static bool get configurado =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static List<String> get faltando => [
    if (supabaseUrl.isEmpty) 'SUPABASE_URL',
    if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
    if (urlBase.isEmpty) 'APP_URL_BASE',
  ];
}
