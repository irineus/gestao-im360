import 'package:flutter/material.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:go_router/go_router.dart';

/// App mínimo para widget test: tema de verdade e `GoRouter` de verdade (o
/// shell lê `GoRouterState`).
///
/// Os dados entram por sobrescrita de provider, feita pelo próprio teste ao
/// envolver isto num `ProviderScope` — nunca por um cliente Supabase falso
/// (card 2.8 §9.3). O `ProviderScope` fica com o teste porque o tipo `Override`
/// não é exportado por `flutter_riverpod`, e importar o pacote transitivo só
/// para nomeá-lo seria pior.
Widget appDeTeste({
  required Widget Function(Widget filho) construtor,
  String rotaInicial = '/',
  Widget conteudo = const SizedBox.shrink(),
}) {
  final roteador = GoRouter(
    initialLocation: rotaInicial,
    routes: [
      ShellRoute(
        builder: (_, _, filho) => construtor(filho),
        routes: [
          GoRoute(path: '/', builder: (_, _) => conteudo),
          GoRoute(path: '/:qualquer', builder: (_, _) => conteudo),
        ],
      ),
    ],
  );

  return MaterialApp.router(
    routerConfig: roteador,
    theme: temaClaro(),
    darkTheme: temaEscuro(),
  );
}
