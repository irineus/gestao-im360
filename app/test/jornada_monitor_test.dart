import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/alunos/alunos_provider.dart';
import 'package:gestao_im360/catalogo/catalogo_provider.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/infraestrutura/infraestrutura_provider.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/alunos/ficha_aluno.dart';
import 'package:gestao_im360/telas/alunos/filtros_alunos.dart';
import 'package:gestao_im360/telas/alunos/tela_alunos.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/trilha/trilha.dart';
import 'package:gestao_im360/trilha/trilha_provider.dart';
import 'package:gestao_im360/turmas/turmas_provider.dart';
import 'package:go_router/go_router.dart';

import 'apoio/alunos_falso.dart';
import 'apoio/carregar.dart';
import 'apoio/catalogo_falso.dart';
import 'apoio/infraestrutura_falso.dart';
import 'apoio/trilha_falso.dart';
import 'apoio/turmas_falso.dart';

/// A jornada nº 1 do monitor, NO CELULAR (card 9.2,64, DECISÃO adotada): abrir
/// a lista → achar o aluno → registrar a entrega, em **no máximo 4 toques**.
///
/// Antes deste card: a busca ficava atrás de "Filtrar (1)" (1 toque + 1 para
/// fechar a folha), a ficha abria na aba Dados (1 toque para ir à Trilha) e o
/// cartão não dizia o próximo livro — o monitor abria a ficha para descobrir.
/// O critério 8 do marco M2 é "o monitor completa a jornada inteira NO
/// CELULAR", e é esta que ele fará.
void main() {
  // O conjunto da rota 3b (a aba Trilha) mais o que o monitor tem de fato
  // (card 2.4 §5): ler turmas e lançar a saída. Sem `alunos.alterar_status`.
  const monitor = {
    'alunos.ler',
    'materiais.ler',
    'estoque.ler',
    'estoque.lancar_saida',
    'turmas.ler',
  };
  const secretaria = {
    ...monitor,
    'alunos.editar',
    'alunos.alterar_status',
    'estoque.estornar',
  };

  late int toques;
  late TrilhaFalso trilha;

  Future<void> montar(
    WidgetTester tester, {
    Set<String> permissoes = monitor,
    Size tamanho = const Size(390, 844),
    String inicio = '/alunos',
  }) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    toques = 0;
    trilha = TrilhaFalso.fixture();
    final roteador = GoRouter(
      initialLocation: inicio,
      routes: [
        GoRoute(
          path: '/alunos',
          builder: (_, _) => const Scaffold(body: TelaAlunos()),
          routes: [
            GoRoute(
              path: ':id',
              builder: (_, estado) => Scaffold(
                body: FichaAluno(
                  alunoId: estado.pathParameters['id']!,
                  aba: estado.uri.queryParameters['aba'],
                ),
              ),
            ),
          ],
        ),
        GoRoute(path: '/pendencias', builder: (_, _) => const Scaffold()),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: semRetryAutomatico,
        overrides: [
          alunosRepositorioProvider.overrideWithValue(AlunosFalso.fixture()),
          catalogoRepositorioProvider.overrideWithValue(
            CatalogoFalso.fixture(),
          ),
          turmasRepositorioProvider.overrideWithValue(TurmasFalso.fixture()),
          infraestruturaRepositorioProvider.overrideWithValue(
            InfraestruturaFalso.fixture(),
          ),
          trilhaRepositorioProvider.overrideWithValue(trilha),
          permissoesProvider.overrideWithValue(permissoes),
          unidadeAtualProvider.overrideWithValue('unidade-teste'),
        ],
        child: MaterialApp.router(routerConfig: roteador, theme: temaClaro()),
      ),
    );
    await carregar(tester);
  }

  Future<void> tocar(WidgetTester tester, Finder alvo) async {
    toques++;
    await tester.ensureVisible(alvo);
    await tester.pumpAndSettle();
    await tester.tap(alvo);
    await carregar(tester);
  }

  testWidgets('390 px: achar o aluno e registrar a entrega em no máximo 4 '
      'toques', (tester) async {
    await montar(tester);
    expect(tester.takeException(), isNull);

    // A busca está À VISTA — nada de abrir a folha de filtros para procurar.
    final busca = find.widgetWithText(TextField, rotuloBuscaAlunos);
    expect(busca.hitTestable(), findsOneWidget);
    await tester.enterText(busca, 'Ana');
    await carregar(tester);

    // O cartão já diz o próximo livro — a informação da jornada.
    expect(
      find.text('$rotuloProximoLivro Informática Avançada 1'),
      findsOneWidget,
    );

    await tocar(tester, find.text('Ana Paula Ribeiro'));
    // A ficha abre na TRILHA, com o rodapé de entrega à vista.
    final registrar = find.widgetWithText(FilledButton, 'Registrar entrega');
    expect(registrar.hitTestable(), findsOneWidget);

    await tocar(tester, registrar);
    expect(trilha.chamadas, contains('registrarEntrega'));
    expect(toques, lessThanOrEqualTo(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a busca fora da folha não conta no "Filtrar (n)"', (
    tester,
  ) async {
    await montar(tester);
    await tester.enterText(
      find.widgetWithText(TextField, rotuloBuscaAlunos),
      'Ana',
    );
    await carregar(tester);
    // A busca não aparece de novo dentro da folha…
    await tester.tap(find.textContaining('Filtrar'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, rotuloBuscaAlunos), findsOneWidget);
  });

  for (final tamanho in const [Size(1400, 900), Size(390, 844)]) {
    testWidgets('o cabeçalho da ficha resume a jornada e não tem botão CHEIO '
        '(${tamanho.width.toInt()} px)', (tester) async {
      await montar(
        tester,
        permissoes: secretaria,
        tamanho: tamanho,
        inicio: '/alunos/al-3001?aba=dados',
      );
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('$rotuloProximoLivro Informática Avançada 1'),
        findsOneWidget,
      );
      expect(find.textContaining('Turma:'), findsOneWidget);
      // "Alterar status" era o primário laranja: a ação rara e de
      // consequência era a mais chamativa da ficha.
      // Mede-se a COR: o secundário é `FilledButton.tonal`, que não é o
      // laranja de ação.
      final fundo = tester
          .widget<Material>(
            find
                .descendant(
                  of: find.widgetWithText(FilledButton, 'Alterar status'),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color;
      expect(fundo, isNot(temaClaro().colorScheme.primary));
    });
  }

  testWidgets('sem poder entregar, a ficha continua abrindo em Dados', (
    tester,
  ) async {
    await montar(
      tester,
      permissoes: const {'alunos.ler', 'materiais.ler'},
      tamanho: const Size(1400, 900),
      inicio: '/alunos/al-3001',
    );
    expect(find.text('Observações'), findsOneWidget);
  });
}
