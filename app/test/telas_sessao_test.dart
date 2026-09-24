import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/erros/erro_app.dart';
import 'package:gestao_im360/sessao/sessao.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/sessao/sessao_repositorio.dart';
import 'package:gestao_im360/telas/acesso_bloqueado.dart';
import 'package:gestao_im360/telas/login.dart';
import 'package:gestao_im360/telas/redefinir_senha.dart';
import 'package:gestao_im360/telas/selecao_unidade.dart';
import 'package:gestao_im360/telas/sem_acesso.dart';

import 'apoio/app_de_teste.dart';
import 'apoio/carregar.dart';

/// As cinco telas de porta de entrada e de estado de sessão, que até o card
/// 9.2,73 não tinham widget test nenhum — justamente as que o card 3.7 separou
/// uma a uma: login, redefinir senha, acesso bloqueado (três modos de falha),
/// seleção de unidade e "Sem acesso". Todas em 390 px e desktop, sem estouro.
class _SessaoFalsa implements SessaoRepositorio {
  _SessaoFalsa(this.estado, {this.falhaAoEntrar});

  EstadoSessao estado;
  final Object? falhaAoEntrar;
  int saidas = 0;
  int trocas = 0;

  @override
  Future<EstadoSessao> carregar() async => estado;

  @override
  Future<void> entrar({required String email, required String senha}) async {
    final falha = falhaAoEntrar;
    if (falha != null) throw falha;
  }

  @override
  Future<void> recuperarSenha(
    String email, {
    required String redirecionarPara,
  }) async {}

  @override
  Future<void> trocarSenha(String novaSenha) async => trocas++;

  @override
  Future<void> sair() async => saidas++;
}

const _sessao = Sessao(
  usuarioId: '00000000-0000-0000-0000-000000000001',
  nome: 'Secretaria',
  email: 'secretaria@escola-a.test',
  unidadeId: '00000000-0000-0000-0000-0000000000aa',
  unidadeNome: 'Instituto Mix Charqueadas',
  permissoes: {'alunos.ler'},
);

void main() {
  Future<_SessaoFalsa> montar(
    WidgetTester tester,
    Widget tela, {
    required Size tamanho,
    EstadoSessao estado = const SessaoDeslogada(),
    Object? falhaAoEntrar,
    String rota = '/',
  }) async {
    final repositorio = _SessaoFalsa(estado, falhaAoEntrar: falhaAoEntrar);
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
          rotaInicial: rota,
          construtor: (filho) => filho,
          conteudo: tela,
        ),
      ),
    );
    await carregar(tester);
    return repositorio;
  }

  for (final (nome, tamanho) in [
    ('390 px', const Size(390, 800)),
    ('desktop', const Size(1400, 900)),
  ]) {
    group(nome, () {
      testWidgets('login: validação e o erro do servidor com texto do '
          'catálogo', (tester) async {
        await montar(
          tester,
          const TelaLogin(),
          tamanho: tamanho,
          falhaAoEntrar: const ErroApp(
            mensagem: 'E-mail ou senha incorretos.',
            traduzido: true,
          ),
        );
        await tester.tap(find.text('Entrar'));
        await carregar(tester);
        expect(find.text('Informe um e-mail válido.'), findsOneWidget);
        expect(find.text('Informe a senha.'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'E-mail'),
          'secretaria@escola-a.test',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Senha'),
          'errada',
        );
        await tester.tap(find.text('Entrar'));
        await carregar(tester);
        expect(find.text('E-mail ou senha incorretos.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('login: "Esqueci minha senha" sem e-mail diz o que falta', (
        tester,
      ) async {
        await montar(tester, const TelaLogin(), tamanho: tamanho);
        await tester.tap(find.text('Esqueci minha senha'));
        await carregar(tester);
        expect(
          find.text('Informe o e-mail para receber o link.'),
          findsOneWidget,
        );
      });

      testWidgets('redefinir senha: as duas regras de validação', (
        tester,
      ) async {
        final repo = await montar(
          tester,
          const TelaRedefinirSenha(),
          tamanho: tamanho,
          estado: const SessaoAtiva(_sessao),
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nova senha'),
          'curta',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Repetir a nova senha'),
          'outra',
        );
        await tester.ensureVisible(find.text('Salvar senha'));
        await tester.tap(find.text('Salvar senha'));
        await carregar(tester);
        expect(
          find.text('A senha precisa de ao menos 8 caracteres.'),
          findsOneWidget,
        );
        expect(
          find.text('As duas senhas precisam ser iguais.'),
          findsOneWidget,
        );
        expect(repo.trocas, 0);
        expect(tester.takeException(), isNull);
      });

      testWidgets('acesso bloqueado: os três modos de falha têm texto '
          'próprio, e "Sair" funciona', (tester) async {
        final repo = await montar(
          tester,
          const TelaAcessoBloqueado(),
          tamanho: tamanho,
          estado: const SessaoSemEspelho('nova@escola-a.test'),
        );
        expect(find.text('Seu acesso ainda não foi liberado'), findsOneWidget);
        expect(find.textContaining('nova@escola-a.test'), findsOneWidget);
        await tester.tap(find.text('Sair'));
        await carregar(tester);
        expect(repo.saidas, 1);

        await tester.pumpWidget(const SizedBox.shrink());
        await montar(
          tester,
          const TelaAcessoBloqueado(),
          tamanho: tamanho,
          estado: const SessaoSemPerfil(_sessao),
        );
        expect(find.text('Seu usuário ainda não tem perfil'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await montar(
          tester,
          const TelaAcessoBloqueado(),
          tamanho: tamanho,
          estado: const SessaoErro('Falha de rede.', codigo: 'PGRST001'),
        );
        expect(
          find.text('Não foi possível carregar sua sessão'),
          findsOneWidget,
        );
        expect(find.text('Falha de rede. (código PGRST001)'), findsOneWidget);
        expect(find.text('Tentar de novo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('seleção de unidade: diz a unidade da sessão', (
        tester,
      ) async {
        await montar(
          tester,
          const TelaSelecaoUnidade(),
          tamanho: tamanho,
          estado: const SessaoAtiva(_sessao),
        );
        expect(find.text('Escolher unidade'), findsOneWidget);
        expect(find.textContaining('Instituto Mix Charqueadas'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('"Sem acesso": oferece o caminho de volta só quando há', (
        tester,
      ) async {
        await montar(
          tester,
          const TelaSemAcesso(faltando: {'compras.ler'}, paraOndeIr: '/'),
          tamanho: tamanho,
        );
        expect(find.text('Ir para o início'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await montar(
          tester,
          const TelaSemAcesso(faltando: {'compras.ler'}),
          tamanho: tamanho,
        );
        expect(find.text('Ir para o início'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
