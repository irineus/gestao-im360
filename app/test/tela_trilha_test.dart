import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/alunos/alunos.dart';
import 'package:gestao_im360/catalogo/catalogo_provider.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/pendencias/pendencias_provider.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/alunos/aba_trilha.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/trilha/trilha.dart';
import 'package:gestao_im360/trilha/trilha_provider.dart';
import 'package:gestao_im360/widgets/formulario.dart';
import 'package:go_router/go_router.dart';

import 'apoio/carregar.dart';
import 'apoio/catalogo_falso.dart';
import 'apoio/trilha_falso.dart';

/// A aba Trilha (card 6.6, wireframe §6.3). A obrigação de teste de um card de
/// **Tela** (card 2.8 §13): ocultação por permissão e estado vazio com o texto
/// do card 2.7. Mais o que esta aba tem de próprio:
///
///   • **a aba exige `estoque.ler`, que a rota da ficha não exige** — sem ela o
///     saldo viria 0 em toda linha SEM ERRO NENHUM e toda entrega seria
///     recusada por falta de um estoque que existe. A aba diz o que falta;
///   • **os TRÊS status da entrega chegam à tela como coisas diferentes**, cada
///     um com o texto do design-system §7.3 — e nenhum deles vira snackbar;
///   • **a tela não pré-verifica saldo**: o botão da próxima com saldo 0
///     continua clicável, e quem decide é a função (card 2.6 decisão 2);
///   • **botão sem estado é desabilitado com o motivo, não escondido**
///     (decisão 1 do card 2.6): aluno inativo e trilha em fim.
void main() {
  const leitura = {'alunos.ler', 'materiais.ler', 'estoque.ler'};
  const monitor = {...leitura, 'estoque.lancar_saida'};
  const secretaria = {...monitor, 'estoque.estornar', 'alunos.editar_trilha'};

  const desktop = Size(1400, 900);
  const celular = Size(390, 844);

  Aluno aluno(
    String id, {
    String status = 'ATIVO',
    String? combo = 'cb-info',
  }) => Aluno(
    id: id,
    nome: 'Aluno $id',
    metodoId: 'm-int',
    comboId: combo,
    status: status,
  );

  Future<TrilhaFalso> montar(
    WidgetTester tester, {
    required Aluno paraAluno,
    TrilhaFalso? repositorio,
    Set<String> permissoes = secretaria,
    Size tamanho = desktop,
  }) async {
    final trilha = repositorio ?? TrilhaFalso.fixture();
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: semRetryAutomatico,
        overrides: [
          trilhaRepositorioProvider.overrideWithValue(trilha),
          catalogoRepositorioProvider.overrideWithValue(
            CatalogoFalso.fixture(),
          ),
          permissoesProvider.overrideWithValue(permissoes),
          unidadeAtualProvider.overrideWithValue('unidade-teste'),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          home: Scaffold(body: AbaTrilha(aluno: paraAluno)),
        ),
      ),
    );
    await carregar(tester);
    return trilha;
  }

  group('guarda da aba', () {
    testWidgets('sem estoque.ler a aba diz o que falta, e não lista nada', (
      tester,
    ) async {
      await montar(
        tester,
        paraAluno: aluno('al-3001'),
        permissoes: const {'alunos.ler', 'materiais.ler'},
      );

      expect(find.text(semAcessoTrilha), findsOneWidget);
      // O diagnóstico do wireframe §2.3.4 — o que falta, por nome.
      expect(find.textContaining('estoque.ler'), findsOneWidget);
      // E nenhuma linha da trilha: mostrar a lista com saldo 0 seria mentir.
      expect(find.textContaining('Informática Essencial'), findsNothing);
    });

    testWidgets('a leitura não é sequer tentada sem a permissão', (
      tester,
    ) async {
      final trilha = await montar(
        tester,
        paraAluno: aluno('al-3001'),
        permissoes: const {'alunos.ler'},
      );
      expect(trilha.chamadas, isEmpty);
    });
  });

  group('estado vazio — design-system §7.2', () {
    testWidgets('aluno sem trilha mostra o texto do card 2.7 e a ação', (
      tester,
    ) async {
      await montar(tester, paraAluno: aluno('al-karina', combo: null));

      expect(find.text(vazioTrilha), findsOneWidget);
      expect(find.text('Editar trilha'), findsOneWidget);
    });

    testWidgets('sem alunos.editar_trilha o vazio não oferece a ação', (
      tester,
    ) async {
      await montar(
        tester,
        paraAluno: aluno('al-karina', combo: null),
        permissoes: monitor,
      );

      expect(find.text(vazioTrilha), findsOneWidget);
      expect(find.text('Editar trilha'), findsNothing);
    });
  });

  group('a lista', () {
    testWidgets('mostra posição, situação e o saldo só na próxima', (
      tester,
    ) async {
      await montar(tester, paraAluno: aluno('al-3001'));

      expect(find.text('01 Informática Essencial 1'), findsOneWidget);
      expect(find.text('03 Informática Avançada 1'), findsOneWidget);
      // A entregue traz a data; a próxima traz o saldo informativo; a pendente
      // não traz nem uma coisa nem outra.
      expect(find.textContaining('entregue 07/04/2026'), findsOneWidget);
      expect(find.textContaining('próxima · est. 1'), findsOneWidget);
    });

    testWidgets('o cabeçalho conta entregues e pendentes', (tester) async {
      await montar(tester, paraAluno: aluno('al-3001'));
      expect(find.textContaining('2 entregues, 1 pendente'), findsOneWidget);
    });

    testWidgets('a posição é 1..n, e não a ordem de 10 em 10 do banco', (
      tester,
    ) async {
      await montar(tester, paraAluno: aluno('al-3001'));
      for (final n in ['1', '2', '3']) {
        expect(find.text(n), findsOneWidget);
      }
      expect(find.text('10'), findsNothing);
    });
  });

  group('ocultação por permissão', () {
    testWidgets('sem estoque.lancar_saida não há botão de entrega', (
      tester,
    ) async {
      await montar(tester, paraAluno: aluno('al-3001'), permissoes: leitura);
      expect(find.text('Registrar entrega'), findsNothing);
    });

    testWidgets('sem estoque.estornar não há botão de estorno', (tester) async {
      await montar(tester, paraAluno: aluno('al-3001'), permissoes: monitor);
      expect(find.text('Estornar'), findsNothing);
    });

    testWidgets('sem alunos.editar_trilha não há modo de edição', (
      tester,
    ) async {
      await montar(tester, paraAluno: aluno('al-3001'), permissoes: monitor);
      expect(find.text('Editar trilha'), findsNothing);
      expect(find.text('Incluir apostila'), findsNothing);
    });
  });

  group('entrega — os três resultados', () {
    Future<void> entregar(WidgetTester tester) async {
      await tester.tap(find.text('Registrar entrega'));
      await tester.pumpAndSettle();
    }

    testWidgets('ENTREGUE abre diálogo dizendo qual é a próxima', (
      tester,
    ) async {
      final trilha = TrilhaFalso.fixture();
      trilha.proximoResultado = const ResultadoEntrega(
        status: StatusEntrega.entregue,
        materialId: 'mat-int-02',
        proximoMaterialId: 'mat-int-03',
      );
      await montar(tester, paraAluno: aluno('al-3001'), repositorio: trilha);
      await entregar(tester);

      expect(find.text('Entrega registrada'), findsOneWidget);
      expect(
        find.textContaining('A próxima apostila é 03 Informática Avançada 1.'),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('REORDENADA nomeia a pulada e a entregue, e leva à pendência', (
      tester,
    ) async {
      final trilha = TrilhaFalso.fixture();
      await montar(tester, paraAluno: aluno('al-3004'), repositorio: trilha);
      await entregar(tester);

      expect(find.text('Trilha reordenada'), findsOneWidget);
      expect(
        find.textContaining('Sem estoque de 02 Informática Essencial 2'),
        findsOneWidget,
      );
      expect(find.text('Ver pendência'), findsOneWidget);
    });

    testWidgets('BLOQUEADA diz que não registrou, e oferece a pendência', (
      tester,
    ) async {
      final trilha = TrilhaFalso.fixture();
      await montar(tester, paraAluno: aluno('al-3006'), repositorio: trilha);
      await entregar(tester);

      expect(find.text('Entrega bloqueada'), findsOneWidget);
      expect(
        find.textContaining('A entrega não foi registrada'),
        findsOneWidget,
      );
      expect(find.text('Ver pendência'), findsOneWidget);
    });

    testWidgets('a trilha fechada oferece o checklist de certificado', (
      tester,
    ) async {
      final trilha = TrilhaFalso.fixture();
      await montar(tester, paraAluno: aluno('al-3001'), repositorio: trilha);
      await entregar(tester);

      expect(
        find.textContaining('o checklist de certificado foi aberto'),
        findsOneWidget,
      );
      expect(find.text('Ver checklist'), findsOneWidget);
    });

    testWidgets('erro do banco vira o texto do catálogo, pelo código', (
      tester,
    ) async {
      final trilha = TrilhaFalso.fixture();
      trilha.falhaAoGravar = TrilhaFalso.erro('403', 'SEM_PERMISSAO');
      await montar(tester, paraAluno: aluno('al-3001'), repositorio: trilha);
      await entregar(tester);

      expect(find.text('A entrega não foi registrada'), findsOneWidget);
      expect(
        find.text('Você não tem permissão para esta ação.'),
        findsOneWidget,
      );
    });

    testWidgets('a tela NÃO pré-verifica saldo: com est. 0 o botão age', (
      tester,
    ) async {
      // Diego tem saldo 0 na próxima e o botão continua clicável — quem decide
      // é fn_registrar_entrega, e ela reordena (card 2.6 decisão 2).
      final trilha = TrilhaFalso.fixture();
      await montar(tester, paraAluno: aluno('al-3004'), repositorio: trilha);
      expect(find.textContaining('próxima · est. 0'), findsOneWidget);

      await entregar(tester);
      expect(trilha.chamadas, contains('registrarEntrega'));
    });
  });

  group('rodapé do celular — a jornada nº 1 do monitor', () {
    testWidgets('o botão fica no rodapé, e a próxima é anunciada', (
      tester,
    ) async {
      await montar(
        tester,
        paraAluno: aluno('al-3001'),
        tamanho: celular,
        permissoes: monitor,
      );

      expect(find.text('Registrar entrega'), findsOneWidget);
      expect(find.text('Próxima: 03 Informática Avançada 1'), findsOneWidget);
    });

    testWidgets('aluno inativo: botão visível e desabilitado com o motivo', (
      tester,
    ) async {
      await montar(
        tester,
        paraAluno: aluno('al-3001', status: 'TRANCADO'),
        tamanho: celular,
        permissoes: monitor,
      );

      expect(find.text('Registrar entrega'), findsOneWidget);
      expect(find.text(motivoAlunoInativo), findsOneWidget);
    });

    testWidgets('trilha em fim: mesmo tratamento, motivo diferente', (
      tester,
    ) async {
      await montar(
        tester,
        paraAluno: aluno('al-3010'),
        tamanho: celular,
        permissoes: monitor,
      );

      expect(find.text('Registrar entrega'), findsOneWidget);
      expect(find.text(motivoTrilhaEmFim), findsOneWidget);
    });
  });

  group('edição da trilha', () {
    testWidgets('as setas movem uma casa, com a POSIÇÃO de destino', (
      tester,
    ) async {
      final trilha = TrilhaFalso.fixture();
      await montar(tester, paraAluno: aluno('al-3004'), repositorio: trilha);
      await tester.tap(find.text('Editar trilha'));
      await tester.pumpAndSettle();

      // Só os pendentes ganham setas: item entregue não se reordena
      // (`ITEM_JA_ENTREGUE`, card 6.2).
      expect(find.byTooltip('Descer uma posição'), findsNWidgets(2));

      await tester.tap(find.byTooltip('Descer uma posição').first);
      await tester.pumpAndSettle();
      // O item da posição 2 desce para a 3 — posição, não `ordem`.
      expect(trilha.chamadas, contains('reordenarItem:3'));
    });

    testWidgets('o modo de edição revela Incluir e Remover', (tester) async {
      await montar(tester, paraAluno: aluno('al-3004'));
      expect(find.text('Incluir apostila'), findsNothing);

      await tester.tap(find.text('Editar trilha'));
      await tester.pumpAndSettle();

      expect(find.text('Incluir apostila'), findsOneWidget);
      expect(find.text('Remover'), findsNWidgets(2));
      expect(find.text('Concluir edição'), findsOneWidget);
    });

    testWidgets('estorno sem movimento vinculado fica desabilitado, não some', (
      tester,
    ) async {
      final trilha = TrilhaFalso(
        trilhas: {
          'al-3001': [
            const ItemTrilha(
              itemId: 'i-1',
              alunoId: 'al-3001',
              materialId: 'mat-int-01',
              ordem: 10,
              posicao: 1,
              materialCodigo: '01',
              materialNome: 'Informática Essencial 1',
              entregue: true,
            ),
          ],
        },
      );
      await montar(tester, paraAluno: aluno('al-3001'), repositorio: trilha);

      expect(find.text('Estornar'), findsOneWidget);
      expect(find.text(motivoSemMovimento), findsNothing); // desktop: tooltip
      final botao = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Estornar'),
          matching: find.byType(TextButton),
        ),
      );
      expect(botao.onPressed, isNull);
    });

    testWidgets('o estorno pede motivo e chama a função', (tester) async {
      final trilha = TrilhaFalso.fixture();
      await montar(tester, paraAluno: aluno('al-3001'), repositorio: trilha);

      await tester.tap(find.text('Estornar').first);
      await tester.pumpAndSettle();
      expect(find.text('Estornar entrega'), findsOneWidget);

      // Sem motivo, a validação local barra antes de ir ao banco.
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await tester.pumpAndSettle();
      expect(trilha.chamadas, isNot(contains('estornarEntrega')));

      await tester.enterText(find.byType(TextFormField).first, 'livro trocado');
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await tester.pumpAndSettle();
      expect(trilha.chamadas, contains('estornarEntrega'));
    });
  });

  // ---------------------------------------------------------------------------
  // Revisão das telas 06/07 (card 8.1,5)
  // ---------------------------------------------------------------------------

  group('no DESKTOP a linha diz o mesmo que o rodapé do mobile (item A4)', () {
    testWidgets('aluno STANDBY: botão presente, desabilitado e com o motivo', (
      tester,
    ) async {
      // ⚠️ Vermelho antes da correção: `aoEntregar` olhava só `item.proximo`,
      // e o `BotaoAcao` da linha nascia SEM `desabilitado`. Medido no stack
      // local: Gabriela Souza (STANDBY) → aba Trilha no desktop → "Registrar
      // entrega" habilitado → clique → diálogo "A entrega não foi registrada".
      // A tela não deve oferecer o que vai falhar (wireframe §2.2).
      await montar(
        tester,
        paraAluno: aluno('al-3001', status: 'STANDBY'),
        permissoes: monitor,
      );

      final botao = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Registrar entrega'),
      );
      expect(botao.onPressed, isNull, reason: 'desabilitado, não escondido');
      expect(find.byTooltip(motivoAlunoInativo), findsOneWidget);
    });

    testWidgets('trilha em FIM: o mesmo, com o outro motivo', (tester) async {
      await montar(tester, paraAluno: aluno('al-3010'), permissoes: monitor);
      // Em fim não há próxima, então a linha não oferece a ação nenhuma: o
      // rodapé do mobile é quem diz o motivo. O que não pode existir é botão
      // HABILITADO — e é isso que se assere.
      for (final b in tester.widgetList<FilledButton>(
        find.widgetWithText(FilledButton, 'Registrar entrega'),
      )) {
        expect(b.onPressed, isNull);
      }
    });

    testWidgets('aluno ATIVO com próxima: a linha oferece a entrega', (
      tester,
    ) async {
      await montar(tester, paraAluno: aluno('al-3001'), permissoes: monitor);
      final botao = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Registrar entrega'),
      );
      expect(botao.onPressed, isNotNull);
    });
  });

  testWidgets('os botões da linha existem para o leitor de tela (item A5)', (
    tester,
  ) async {
    // ⚠️ Vermelho antes da correção: o `Semantics(excludeSemantics: true)`
    // cobria a linha inteira, e `excludeSemantics` descarta a semântica de
    // TODOS os descendentes — os botões deixavam de existir para leitor de
    // tela e para a navegação por foco, na jornada nº 1 do monitor
    // (design-system §8.3/§8.5).
    final handle = tester.ensureSemantics();
    await montar(tester, paraAluno: aluno('al-3001'), permissoes: secretaria);

    expect(find.bySemanticsLabel('Registrar entrega'), findsWidgets);
    expect(find.bySemanticsLabel('Estornar'), findsWidgets);
    handle.dispose();
  });

  group('a linha do ritmo (item A8, divergência 15 do §17)', () {
    testWidgets('com ritmo: o número vem da view, com a última entrega', (
      tester,
    ) async {
      final trilha = TrilhaFalso.fixture()
        ..ritmos['al-3001'] = RitmoAluno(
          ritmoDias: 21,
          ultimaEntrega: DateTime(2026, 8, 30),
          entregas: 3,
          intervalosConsiderados: 2,
        );
      await montar(tester, paraAluno: aluno('al-3001'), repositorio: trilha);
      expect(
        find.text(
          'ritmo: 1 apostila a cada 21 dias · última entrega '
          '30/08/2026',
        ),
        findsOneWidget,
      );
    });

    testWidgets('sem intervalo válido: NUNCA "0 dias"', (tester) async {
      final trilha = TrilhaFalso.fixture()
        ..ritmos['al-3001'] = const RitmoAluno(
          ritmoDias: null,
          ultimaEntrega: null,
          entregas: 1,
          intervalosConsiderados: 0,
        );
      await montar(tester, paraAluno: aluno('al-3001'), repositorio: trilha);
      expect(find.text(semRitmoAinda), findsOneWidget);
      expect(find.textContaining('0 dias'), findsNothing);
    });

    testWidgets('erro na leitura do ritmo NÃO vira "sem ritmo ainda"', (
      tester,
    ) async {
      // Região com os três estados: erro que vira "sem ritmo" afirmaria sobre
      // o aluno o que só se sabe da leitura (design-system §5.6).
      final trilha = TrilhaFalso.fixture()
        ..falhaAoLerRitmo = TrilhaFalso.erro('500', 'FALHA');
      await montar(tester, paraAluno: aluno('al-3001'), repositorio: trilha);
      expect(find.text(semRitmoAinda), findsNothing);
      expect(find.text('ritmo indisponível'), findsOneWidget);
      // O resto da aba continua de pé.
      expect(find.text('01 Informática Essencial 1'), findsWidgets);
    });
  });

  group('"Ver pendência" leva o filtro por tipo (item D3)', () {
    /// A aba dentro de um `GoRouter` de verdade — o link navega, e é a
    /// navegação que precisa chegar à central **já filtrada**.
    Future<ProviderContainer> montarComRota(
      WidgetTester tester,
      Aluno paraAluno,
      TrilhaFalso trilha,
    ) async {
      tester.view.physicalSize = desktop;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: semRetryAutomatico,
          overrides: [
            trilhaRepositorioProvider.overrideWithValue(trilha),
            catalogoRepositorioProvider.overrideWithValue(
              CatalogoFalso.fixture(),
            ),
            permissoesProvider.overrideWithValue(secretaria),
            unidadeAtualProvider.overrideWithValue('unidade-teste'),
          ],
          child: MaterialApp.router(
            theme: temaClaro(),
            routerConfig: GoRouter(
              initialLocation: '/alunos/${paraAluno.id}',
              routes: [
                GoRoute(
                  path: '/alunos/:id',
                  builder: (_, _) =>
                      Scaffold(body: AbaTrilha(aluno: paraAluno)),
                ),
                GoRoute(
                  path: '/pendencias',
                  builder: (_, _) =>
                      const Scaffold(body: Text('CENTRAL DE PENDÊNCIAS')),
                ),
              ],
            ),
          ),
        ),
      );
      await carregar(tester);
      return ProviderScope.containerOf(tester.element(find.byType(AbaTrilha)));
    }

    testWidgets('BLOQUEADA filtra por COMPRA_SEM_ESTOQUE', (tester) async {
      // ⚠️ Vermelho antes da correção: o link navegava para a central INTEIRA,
      // e a pessoa procurava de novo a pendência que a entrega acabou de
      // abrir — o mesmo defeito que o card 5.8 pagou com o `?bloco=`.
      final container = await montarComRota(
        tester,
        aluno('al-3006'),
        TrilhaFalso.fixture(),
      );
      await tester.tap(find.text('Registrar entrega'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver pendência'));
      await tester.pumpAndSettle();

      expect(find.text('CENTRAL DE PENDÊNCIAS'), findsOneWidget);
      expect(
        container.read(filtroPendenciasProvider).tipo,
        'COMPRA_SEM_ESTOQUE',
      );
    });

    testWidgets('REORDENADA filtra por ESTOQUE_ZERO', (tester) async {
      final container = await montarComRota(
        tester,
        aluno('al-3004'),
        TrilhaFalso.fixture(),
      );
      await tester.tap(find.text('Registrar entrega'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver pendência'));
      await tester.pumpAndSettle();

      expect(container.read(filtroPendenciasProvider).tipo, 'ESTOQUE_ZERO');
    });

    test('a função pura: ENTREGUE não abre pendência nenhuma', () {
      expect(tipoDaPendencia(StatusEntrega.entregue), isNull);
      expect(tipoDaPendencia(StatusEntrega.reordenada), 'ESTOQUE_ZERO');
      expect(
        tipoDaPendencia(StatusEntrega.bloqueadaSemEstoque),
        'COMPRA_SEM_ESTOQUE',
      );
    });
  });
}
