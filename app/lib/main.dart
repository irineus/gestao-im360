import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/ambiente.dart';
import 'config/estrategia_url.dart';
import 'config/link_inicial.dart';
import 'observabilidade/observabilidade.dart';
import 'rotas/roteador.dart';
import 'theme/dimensoes.dart';
import 'theme/preferencia_tema.dart';
import 'theme/tema.dart';
import 'theme/tipografia.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ANTES do Supabase.initialize: o `type=invite` do link de convite vive no
  // fragmento da URL, e o supabase_flutter o consome e limpa ao criar a sessão
  // — depois disso um convidado é indistinguível de um login (card 4.7,
  // lib/config/link_inicial.dart).
  LinkInicial.registrar(Uri.base);
  // Antes de qualquer rota ser lida: o fragmento da URL é do Auth, não do
  // roteador (card 3.8).
  usarUrlPorCaminho();

  // O Sentry envolve TUDO o que vem abaixo, inclusive a tela de build não
  // configurado (card 3.12): build sem `--dart-define` é justamente o defeito
  // de empacotamento que se quer ver no painel, e não só na tela de quem
  // abriu o app. Sem `SENTRY_DSN` isto é um `await rodarApp()` e mais nada.
  await iniciarObservabilidade(_subir);
}

Future<void> _subir() async {
  if (!Ambiente.configurado) {
    // Subir desconectado daria erro de rede em toda consulta, e o diagnóstico
    // seria feito na tela errada. Melhor dizer o que falta.
    runApp(const AppNaoConfigurado());
    return;
  }

  // `publishableKey` é o nome novo da chave anônima no supabase_flutter; o
  // --dart-define continua se chamando SUPABASE_ANON_KEY, que é como a chave
  // aparece no painel e nos secrets do card 3.8.
  await Supabase.initialize(
    url: Ambiente.supabaseUrl,
    publishableKey: Ambiente.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: AppIm360()));
}

class AppIm360 extends ConsumerWidget {
  const AppIm360({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Gestão IM360',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(roteadorProvider),
      themeMode: ref.watch(preferenciaTemaProvider),
      // A densidade vem da faixa, junto com o shell (design-system §4.2):
      // compacta no desktop e no tablet, padrão no mobile.
      builder: (context, filho) {
        final compacto =
            faixaDe(MediaQuery.sizeOf(context).width) != Faixa.mobile;
        return Theme(
          data: Theme.of(context).brightness == Brightness.dark
              ? temaEscuro(compacto: compacto)
              : temaClaro(compacto: compacto),
          child: filho ?? const SizedBox.shrink(),
        );
      },
      theme: temaClaro(),
      darkTheme: temaEscuro(),
    );
  }
}

/// Tela de build sem `--dart-define`. Não é estado de erro do usuário: é erro
/// de empacotamento, e quem a vê é quem está montando o build.
class AppNaoConfigurado extends StatelessWidget {
  const AppNaoConfigurado({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestão IM360',
      debugShowCheckedModeBanner: false,
      theme: temaClaro(),
      darkTheme: temaEscuro(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(Dim.e24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Gestão IM360', style: Tipografia.titulo),
                const SizedBox(height: Dim.e8),
                Text(
                  'Este build não recebeu a configuração do ambiente.\n'
                  'Falta: ${Ambiente.faltando.join(', ')}.',
                  style: Tipografia.corpo,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Dim.e8),
                Text(
                  'Passe os valores com --dart-define (veja app/README.md).',
                  style: Tipografia.apoio,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
