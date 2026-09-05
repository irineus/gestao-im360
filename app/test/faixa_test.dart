import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/pendencias/pendencias_provider.dart';
import 'package:gestao_im360/rotas/rotas.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/theme/dimensoes.dart';
import 'package:gestao_im360/widgets/shell_im360.dart';

import 'apoio/app_de_teste.dart';
import 'apoio/pendencias_falso.dart';

/// Card 2.8 §9.1: `faixaDe(largura)` devolve menu/trilho/barra inferior nos
/// limites 600 e 1024. A troca de linhas por cartões da `TabelaIm360` está em
/// `tabela_im360_test.dart` (card 4.4, que criou o componente).
void main() {
  group('faixaDe', () {
    test(
      'os limites são fechados embaixo — 600 já é tablet, 1024 já é desktop',
      () {
        expect(faixaDe(599.9), Faixa.mobile);
        expect(faixaDe(Dim.bpTablet), Faixa.tablet);
        expect(faixaDe(1023.9), Faixa.tablet);
        expect(faixaDe(Dim.bpDesktop), Faixa.desktop);
      },
    );

    test('larguras típicas caem na faixa certa', () {
      expect(faixaDe(390), Faixa.mobile); // celular do monitor
      expect(faixaDe(820), Faixa.tablet);
      expect(faixaDe(1440), Faixa.desktop); // balcão da secretaria
      expect(faixaDe(3440), Faixa.desktop); // ultrawide
    });
  });

  group('o shell escolhe a navegação pela largura disponível', () {
    const permissoesDirecao = {
      'unidades.ler',
      'alunos.ler',
      'materiais.ler',
      'turmas.ler',
      'salas.ler',
      'professores.ler',
      'estoque.ler',
      'compras.ler',
      'certificados.ler',
      'pendencias.ler',
      'admin.ler',
    };

    Future<void> montar(WidgetTester tester, Size tamanho) async {
      tester.view.physicalSize = tamanho;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: semRetryAutomatico,
          overrides: [
            // O shell passou a observar o contador de pendências (card 5.8):
            // sem o repositório injetado ele iria ao `Supabase.instance`.
            pendenciasRepositorioProvider.overrideWithValue(
              PendenciasFalso(pendencias: const []),
            ),
            permissoesProvider.overrideWithValue(permissoesDirecao),
            resumoUsuarioProvider.overrideWithValue(
              const ResumoUsuario(
                nome: 'Direção',
                unidade: 'Instituto Mix Charqueadas',
              ),
            ),
          ],
          child: appDeTeste(
            rotaInicial: rotasAplicacao.first.caminho,
            construtor: (filho) => ShellIm360(filho: filho),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('desktop: menu lateral, sem barra inferior', (tester) async {
      await montar(tester, const Size(1400, 900));
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('Dashboard'), findsWidgets);
    });

    testWidgets('tablet: trilho de ícones', (tester) async {
      await montar(tester, const Size(800, 900));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('mobile: barra inferior com Alunos primeiro e Mais no fim', (
      tester,
    ) async {
      await montar(tester, const Size(390, 800));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);

      final barra = tester.widget<NavigationBar>(find.byType(NavigationBar));
      final rotulos = barra.destinations
          .cast<NavigationDestination>()
          .map((d) => d.label)
          .toList();
      // A jornada do monitor primeiro (docs/wireframes.md §3.2).
      expect(rotulos, ['Alunos', 'Turmas', 'Pendências', 'Mais']);
    });

    testWidgets('tocar em "Mais" ABRE a gaveta com as rotas que sobraram', (
      tester,
    ) async {
      // ⚠️ Vermelho antes da correção do item H1: `Scaffold.of(context)` era
      // chamado com o contexto do `build` de `ShellIm360`, ACIMA do Scaffold —
      // lançava `Scaffold.of() called with a context that does not contain a
      // Scaffold` e a gaveta nunca abria. Com isso, no celular, Dashboard,
      // Turmas Modular, Materiais, Compras, Projeção, Certificados, Salas,
      // Administração e Importação eram INALCANÇÁVEIS. O `faixa_test` só
      // conferia os rótulos da barra, e por isso nada no CI acusou.
      await montar(tester, const Size(390, 800));
      expect(find.byType(Drawer), findsNothing);

      await tester.tap(find.text('Mais'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Drawer), findsOneWidget);
      // As rotas que não coubemos na barra inferior estão lá dentro. (O
      // "Dashboard" aparece duas vezes: no app bar, como título da rota atual,
      // e na gaveta.)
      expect(find.text('Dashboard'), findsNWidgets(2));
      expect(find.text('Materiais e estoque'), findsOneWidget);
      expect(find.text('Administração'), findsOneWidget);
    });

    testWidgets('a gaveta diz quem está logado, e tem tema e saída', (
      tester,
    ) async {
      // Item H2: no celular e no tablet o nome e a unidade não apareciam em
      // lugar nenhum — `comNome` só existia no menu lateral do desktop.
      await montar(tester, const Size(390, 800));
      expect(find.text('Direção'), findsNothing);

      await tester.tap(find.text('Mais'));
      await tester.pumpAndSettle();

      expect(find.text('Direção'), findsOneWidget);
      expect(find.text('Instituto Mix Charqueadas'), findsOneWidget);
      expect(find.text('Sair'), findsOneWidget);
      expect(find.text('Tema escuro'), findsOneWidget);
    });

    testWidgets('o ícone do usuário do app bar abre a MESMA gaveta', (
      tester,
    ) async {
      await montar(tester, const Size(390, 800));
      await tester.tap(find.byKey(chaveGatilhoMenuUsuario));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Drawer), findsOneWidget);
      expect(find.text('Sair'), findsOneWidget);
    });

    testWidgets('o alvo do menu do usuário tem 44 px nas três faixas', (
      tester,
    ) async {
      // Medido em 24×24 px antes da correção (item H2a) — metade do mínimo do
      // design-system §8.4, no controle que é a única saída do sistema.
      for (final tamanho in [
        const Size(390, 800),
        const Size(800, 900),
        const Size(1400, 900),
      ]) {
        await montar(tester, tamanho);
        final alvo = tester.getSize(find.byKey(chaveGatilhoMenuUsuario));
        expect(
          alvo.width,
          greaterThanOrEqualTo(Dim.alvoMobile),
          reason: 'largura do gatilho em ${tamanho.width} px',
        );
        expect(
          alvo.height,
          greaterThanOrEqualTo(Dim.alvoMobile),
          reason: 'altura do gatilho em ${tamanho.width} px',
        );
      }
    });

    testWidgets('no tablet o trilho diz quem está logado', (tester) async {
      await montar(tester, const Size(800, 900));
      expect(find.text('Direção'), findsOneWidget);
    });
  });

  group('iniciais do avatar da gaveta', () {
    test('uma ou duas, e nome vazio não inventa nada', () {
      expect(iniciaisDe('Direção'), 'D');
      expect(iniciaisDe('Maria Aparecida Silva'), 'MS');
      expect(iniciaisDe('  '), '');
    });
  });
}
