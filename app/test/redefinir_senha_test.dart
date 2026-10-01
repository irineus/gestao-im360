import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/config/link_inicial.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/erros/catalogo_erros.dart';
import 'package:gestao_im360/erros/erro_app.dart';
import 'package:gestao_im360/rotas/rotas.dart';
import 'package:gestao_im360/sessao/sessao.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/sessao/sessao_repositorio.dart';
import 'package:gestao_im360/telas/redefinir_senha.dart';
import 'package:gestao_im360/widgets/versao.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'apoio/app_de_teste.dart';
import 'apoio/carregar.dart';

/// Card 9.2,80 — a tela de definir senha trocava a senha de QUEM ESTAVA
/// LOGADO, e não a de quem recebeu o link. Em 01/10/2026, em homologação, o
/// link de convite vencido do Laurence foi aberto no desktop da secretaria com
/// a sessão do Lindomar aberta: o Auth recusou o link, a sessão que sobrou foi
/// a do Lindomar, e `updateUser` gravou a senha nova NELE (`actor =
/// lindomarsilva.ti@gmail.com`, 200). Ele ficou trancado para fora.
///
/// O que estes testes prendem: o formulário — e com ele `trocarSenha` — só
/// existe quando a sessão corrente é a que o LINK criou.
class _SessaoFalsa implements SessaoRepositorio {
  _SessaoFalsa({this.autenticado, this.falhaAoTrocar});

  @override
  UsuarioAutenticado? autenticado;

  final Object? falhaAoTrocar;
  int trocas = 0;
  int saidas = 0;

  @override
  Future<EstadoSessao> carregar() async => autenticado == null
      ? const SessaoDeslogada()
      : SessaoAtiva(
          Sessao(
            usuarioId: autenticado!.id,
            nome: 'Quem está logado',
            email: autenticado!.email,
            unidadeId: 'unidade-teste',
            permissoes: const {'alunos.ler'},
          ),
        );

  @override
  Future<void> entrar({required String email, required String senha}) async {}

  @override
  Future<void> recuperarSenha(
    String email, {
    required String redirecionarPara,
  }) async {}

  @override
  Future<void> trocarSenha(String novaSenha) async {
    trocas++;
    final falha = falhaAoTrocar;
    if (falha != null) throw falha;
  }

  @override
  Future<void> sair() async {
    saidas++;
    autenticado = null;
  }
}

const _lindomar = (id: 'u-lindomar', email: 'lindomar@escola-a.test');
const _laurence = (id: 'u-laurence', email: 'laurence@escola-a.test');

/// A URL do caso da manhã de 01/10/2026: convite vencido, recusado pelo Auth.
final _linkVencido = Uri.parse(
  'https://homolog.gestaoim360.com/#error=access_denied'
  '&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired',
);

Uri _linkQueVale(String tipo) => Uri.parse(
  'https://homolog.gestaoim360.com/redefinir-senha#access_token=t'
  '&expires_in=3600&refresh_token=r&token_type=bearer&type=$tipo',
);

/// O que `main` faz antes do `runApp`: registra a URL e a troca por sessão.
/// [usuarioDoLink] é de quem é a sessão que o Auth devolveu; nulo, a troca
/// falha com [falha].
Future<void> _abrirLink(
  Uri uri, {
  String? usuarioDoLink,
  Object falha = const AuthException('No access_token detected.'),
}) async {
  LinkInicial.registrar(uri);
  await LinkInicial.trocarPorSessao(
    (_) async => usuarioDoLink ?? (throw falha),
    codigoDoErro: (e) => e is AuthException ? e.code : null,
  );
}

void main() {
  setUp(LinkInicial.consumir);
  tearDown(LinkInicial.consumir);

  Future<_SessaoFalsa> montar(
    WidgetTester tester, {
    required Size tamanho,
    UsuarioAutenticado? autenticado,
    Object? falhaAoTrocar,
  }) async {
    final repositorio = _SessaoFalsa(
      autenticado: autenticado,
      falhaAoTrocar: falhaAoTrocar,
    );
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: semRetryAutomatico,
        overrides: [
          sessaoRepositorioProvider.overrideWithValue(repositorio),
          fluxoAuthProvider.overrideWithValue(null),
        ],
        child: appDeTeste(
          rotaInicial: '/redefinir-senha',
          construtor: (filho) => filho,
          conteudo: const TelaRedefinirSenha(),
        ),
      ),
    );
    await carregar(tester);
    return repositorio;
  }

  /// Preenche e salva, SE houver formulário — para que, sem a guarda, o teste
  /// troque a senha errada de verdade e a contraprova fique vermelha pelo
  /// motivo certo (`trocas == 1`), e não por um `find` que falhou.
  Future<void> tentarTrocar(WidgetTester tester) async {
    final campo = find.widgetWithText(TextFormField, 'Nova senha');
    if (campo.evaluate().isEmpty) return;
    await tester.enterText(campo, 'senha-nova-123');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Repetir a nova senha'),
      'senha-nova-123',
    );
    await tester.ensureVisible(find.text('Salvar senha'));
    await tester.tap(find.text('Salvar senha'));
    await carregar(tester);
  }

  for (final (nome, tamanho) in [
    ('390 px', const Size(390, 800)),
    ('desktop', const Size(1400, 900)),
  ]) {
    group(nome, () {
      testWidgets('o caso de 01/10/2026: convite VENCIDO aberto com a sessão '
          'de OUTRA pessoa — recusa, sem trocar a senha de ninguém', (
        tester,
      ) async {
        await _abrirLink(_linkVencido);
        final repo = await montar(
          tester,
          tamanho: tamanho,
          autenticado: _lindomar,
        );
        await tentarTrocar(tester);

        expect(repo.trocas, 0, reason: 'a senha do Lindomar foi trocada');
        expect(find.text('Salvar senha'), findsNothing);
        expect(find.text(tituloLinkRecusado), findsOneWidget);
        expect(find.text(textoLinkVencido), findsOneWidget);
        expect(find.text(textoPecaOutroLink), findsOneWidget);
        expect(find.text(textoVersao), findsOneWidget);
        // De quem é a sessão aberta, e a saída.
        expect(find.text(textoSessaoAberta(_lindomar.email)), findsOneWidget);
        await tester.tap(find.text('Sair'));
        await carregar(tester);
        expect(repo.saidas, 1);
        // E vai à tela de entrada, onde está o "Esqueci minha senha".
        final roteador = GoRouter.of(
          tester.element(find.byType(TelaRedefinirSenha)),
        );
        expect(
          roteador.routerDelegate.currentConfiguration.uri.path,
          rotaLogin.caminho,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('sessão de outra pessoa e NENHUM link (a rota aberta à mão '
          'ou recarregada): sem formulário', (tester) async {
        final repo = await montar(
          tester,
          tamanho: tamanho,
          autenticado: _lindomar,
        );
        await tentarTrocar(tester);

        expect(repo.trocas, 0);
        expect(find.text(tituloSemLink), findsOneWidget);
        expect(find.text(textoSessaoAberta(_lindomar.email)), findsOneWidget);
        expect(find.text('Voltar ao sistema'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('o link valeu, mas a sessão corrente NÃO é a que ele criou: '
          'sem formulário', (tester) async {
        await _abrirLink(_linkQueVale('recovery'), usuarioDoLink: _laurence.id);
        final repo = await montar(
          tester,
          tamanho: tamanho,
          autenticado: _lindomar,
        );
        await tentarTrocar(tester);

        expect(repo.trocas, 0);
        expect(find.text('Salvar senha'), findsNothing);
      });

      testWidgets('link de RECUPERAÇÃO que valeu: troca a senha da sessão que '
          'ele criou, e a autorização é de uso único', (tester) async {
        await _abrirLink(_linkQueVale('recovery'), usuarioDoLink: _laurence.id);
        final repo = await montar(
          tester,
          tamanho: tamanho,
          autenticado: _laurence,
        );
        expect(find.text(tituloRecuperacao), findsOneWidget);
        await tentarTrocar(tester);

        expect(repo.trocas, 1);
        expect(find.text('Senha alterada.'), findsOneWidget);
        expect(LinkInicial.autorizaTroca(_laurence.id), isFalse);
        expect(tester.takeException(), isNull);
      });

      testWidgets('link de CONVITE que valeu: o texto é o do convite', (
        tester,
      ) async {
        await _abrirLink(_linkQueVale('invite'), usuarioDoLink: _laurence.id);
        final repo = await montar(
          tester,
          tamanho: tamanho,
          autenticado: _laurence,
        );
        expect(find.text(tituloConvite), findsOneWidget);
        expect(find.text(apoioConvite), findsOneWidget);
        await tentarTrocar(tester);

        expect(repo.trocas, 1);
        expect(find.text('Senha definida.'), findsOneWidget);
      });

      testWidgets('link PKCE antigo (?code=) que não troca por sessão: diz '
          'por quê, e sem sessão oferece a tela de entrada', (tester) async {
        await _abrirLink(
          Uri.parse('https://homolog.gestaoim360.com/redefinir-senha?code=c1'),
          falha: const AuthException(
            'Code verifier could not be found in local storage.',
          ),
        );
        final repo = await montar(tester, tamanho: tamanho);
        await tentarTrocar(tester);

        expect(repo.trocas, 0);
        expect(find.text(textoLinkOutroNavegador), findsOneWidget);
        expect(find.text('Sair'), findsNothing);
        await tester.ensureVisible(find.text('Ir para a tela de entrada'));
        await tester.tap(find.text('Ir para a tela de entrada'));
        await carregar(tester);
        final roteador = GoRouter.of(
          tester.element(find.byType(TelaRedefinirSenha)),
        );
        expect(
          roteador.routerDelegate.currentConfiguration.uri.path,
          rotaLogin.caminho,
        );
        // O link recusado deixa de prender o roteador na tela de senha.
        expect(LinkInicial.pendente, isFalse);
        expect(tester.takeException(), isNull);
      });

      testWidgets('reauthentication_needed do servidor vira texto traduzido', (
        tester,
      ) async {
        await _abrirLink(_linkQueVale('recovery'), usuarioDoLink: _laurence.id);
        await montar(
          tester,
          tamanho: tamanho,
          autenticado: _laurence,
          falhaAoTrocar: const AuthApiException(
            'Password update requires reauthentication.',
            statusCode: '400',
            code: 'reauthentication_needed',
          ),
        );
        await tentarTrocar(tester);

        expect(
          find.text(mensagensAuth['reauthentication_needed']!),
          findsOneWidget,
        );
        expect(find.textContaining('código'), findsNothing);
      });

      testWidgets('erro do Auth SEM código não mostra "(código ?)"', (
        tester,
      ) async {
        await _abrirLink(_linkQueVale('recovery'), usuarioDoLink: _laurence.id);
        await montar(
          tester,
          tamanho: tamanho,
          autenticado: _laurence,
          falhaAoTrocar: AuthSessionMissingException(),
        );
        await tentarTrocar(tester);

        expect(find.text(CatalogoErros.naoMapeadoSemCodigo), findsOneWidget);
        expect(find.textContaining('código ?'), findsNothing);
      });
    });
  }
}
