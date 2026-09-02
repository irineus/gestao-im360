import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/catalogo/catalogo.dart';
import 'package:gestao_im360/catalogo/catalogo_provider.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/materiais/tela_materiais.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/widgets/formulario.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'apoio/catalogo_falso.dart';

/// A obrigação de teste de um card de **Tela** (card 2.8 §13): ocultação por
/// permissão e estado vazio com o texto do card 2.7 — a guarda de rota já está
/// tabelada em `guardas_rota_test.dart`. Mais o que esta tela tem de próprio:
/// filtros, o formulário gravando no repositório injetado e a sequência do
/// curso sendo salva como lista de ids.
void main() {
  const leitura = {'materiais.ler', 'estoque.ler'};
  const edicao = {
    ...leitura,
    'materiais.criar',
    'materiais.editar',
    'materiais.excluir',
  };

  Future<void> montar(
    WidgetTester tester, {
    required CatalogoFalso repositorio,
    Set<String> permissoes = leitura,
    Size tamanho = const Size(1400, 900),
  }) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogoRepositorioProvider.overrideWithValue(repositorio),
          permissoesProvider.overrideWithValue(permissoes),
          unidadeAtualProvider.overrideWithValue('unidade-teste'),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          home: const Scaffold(body: TelaMateriais()),
        ),
      ),
    );
    await carregar(tester);
  }

  testWidgets('a lista resolve o método pelo id e mostra as colunas', (
    tester,
  ) async {
    await montar(tester, repositorio: CatalogoFalso.fixture());
    expect(find.text('Informática Essencial 1'), findsOneWidget);
    expect(find.text('English Book 2'), findsOneWidget);
    // O filtro de método também monta os nomes (entradas do menu), então o
    // que se conta é "pelo menos" as três linhas.
    expect(find.text('Interativo'), findsAtLeastNWidgets(3));
    expect(find.text('Situação'), findsOneWidget);
    expect(find.text('Mínimo'), findsOneWidget);
  });

  testWidgets('sem materiais.criar o botão "Novo material" não é renderizado', (
    tester,
  ) async {
    await montar(tester, repositorio: CatalogoFalso.fixture());
    expect(find.text('Novo material'), findsNothing);
    expect(find.text('Métodos'), findsNothing);

    await montar(
      tester,
      repositorio: CatalogoFalso.fixture(),
      permissoes: edicao,
    );
    expect(find.text('Novo material'), findsOneWidget);
    expect(find.text('Métodos'), findsOneWidget);
  });

  testWidgets('estado vazio com o texto do card 2.7 — e a ação só para quem '
      'pode criar', (tester) async {
    final vazio = CatalogoFalso(metodos: CatalogoFalso.fixture().metodos_);
    await montar(tester, repositorio: vazio);
    expect(find.text(vazioMateriais), findsOneWidget);
    expect(find.text('+ Novo material'), findsNothing);

    await montar(tester, repositorio: vazio, permissoes: edicao);
    expect(find.text('+ Novo material'), findsOneWidget);
  });

  testWidgets('busca sem resultado: estado vazio de filtro, e "Limpar filtros" '
      'mostra tudo — inclusive o inativo', (tester) async {
    final repositorio = CatalogoFalso.fixture()
      ..materiais_.add(
        const MaterialDidatico(
          id: 'mat-x',
          metodoId: 'm-int',
          codigo: '99',
          nome: 'Aposentada',
          categoria: 'APOSTILA',
          ativo: false,
        ),
      );
    await montar(tester, repositorio: repositorio);
    expect(find.text('Aposentada'), findsNothing, reason: 'só ativos');

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text(vazioMateriaisFiltro), findsOneWidget);
    expect(find.text(vazioMateriais), findsNothing);

    await tester.tap(find.text('Limpar filtros'));
    await tester.pumpAndSettle();
    expect(find.text('Informática Essencial 1'), findsOneWidget);
    expect(find.text('Aposentada'), findsOneWidget);
    expect(find.text('Inativo'), findsOneWidget);
    final chip = tester.widget<FilterChip>(find.byType(FilterChip));
    expect(chip.selected, isFalse);
  });

  testWidgets('novo material: preencher e salvar grava no repositório, '
      'recarrega a lista e confirma', (tester) async {
    final repositorio = CatalogoFalso.fixture();
    await montar(tester, repositorio: repositorio, permissoes: edicao);

    await tester.tap(find.text('Novo material'));
    await tester.pumpAndSettle();
    expect(find.text('Novo material'), findsNWidgets(2), reason: 'título');

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Interativo'), findsWidgets, reason: 'menu aberto');
    await tester.tap(find.text('Interativo').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Código *'),
      '07',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome *'),
      'Apostila Nova',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Categoria *'),
      'APOSTILA',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Estoque mínimo *'),
      '4',
    );
    await tester.tap(find.byKey(chaveBotaoSalvar));
    await tester.pumpAndSettle();
    expect(find.text('Campo obrigatório.'), findsNothing);
    expect(find.text('Escolha o método.'), findsNothing);
    expect(repositorio.chamadas, contains('salvarMaterial'));

    final gravado = repositorio.materiais_.where((m) => m.codigo == '07');
    expect(gravado.single.nome, 'Apostila Nova');
    expect(gravado.single.metodoId, 'm-int');
    expect(gravado.single.estoqueMinimo, 4);
    expect(find.text('Material salvo.'), findsOneWidget);
    expect(find.text('Apostila Nova'), findsOneWidget, reason: 'recarregou');
  });

  testWidgets('recusa do banco vira banner no formulário, pelo SQLSTATE', (
    tester,
  ) async {
    final repositorio = CatalogoFalso.fixture()
      ..falhaAoGravar = const PostgrestException(
        message: 'duplicate key value violates unique constraint',
        code: '23505',
      );
    await montar(tester, repositorio: repositorio, permissoes: edicao);
    await tester.tap(find.text('Informática Essencial 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(chaveBotaoSalvar));
    await tester.pumpAndSettle();
    expect(
      find.text('Já existe um cadastro com este código ou nome.'),
      findsOneWidget,
    );
  });

  testWidgets('sem materiais.editar a linha abre somente para leitura', (
    tester,
  ) async {
    await montar(tester, repositorio: CatalogoFalso.fixture());
    await tester.tap(find.text('Informática Essencial 1'));
    await tester.pumpAndSettle();
    expect(find.text('Material'), findsWidgets);
    expect(find.text('Fechar'), findsOneWidget);
    expect(find.byKey(chaveBotaoSalvar), findsNothing);
    expect(find.text('Excluir'), findsNothing);
  });

  testWidgets('excluir com confirmação chama o repositório e confirma', (
    tester,
  ) async {
    final repositorio = CatalogoFalso.fixture();
    await montar(tester, repositorio: repositorio, permissoes: edicao);
    await tester.tap(find.text('English Book 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(find.text('Excluir material?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Excluir').last);
    await tester.pumpAndSettle();
    expect(repositorio.chamadas, contains('excluirMaterial'));
    expect(find.text('Excluir material?'), findsNothing, reason: 'fechou');
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Material excluído.'), findsOneWidget);
    expect(find.text('English Book 2'), findsNothing);
  });

  group('cursos', () {
    testWidgets('a aba lista os cursos com a contagem de apostilas', (
      tester,
    ) async {
      await montar(tester, repositorio: CatalogoFalso.fixture());
      await tester.tap(find.text('Cursos'));
      await carregar(tester);
      expect(find.text('Informática Essencial'), findsOneWidget);
      expect(find.text('Apostilas'), findsOneWidget);
      expect(find.text('2'), findsNWidgets(2), reason: 'Essencial e Kids');
    });

    testWidgets(
      'o detalhe mostra a sequência na ordem e salva a lista de ids',
      (tester) async {
        final repositorio = CatalogoFalso.fixture();
        await montar(tester, repositorio: repositorio, permissoes: edicao);
        await tester.tap(find.text('Cursos'));
        await carregar(tester);
        await tester.tap(find.text('Informática Essencial'));
        await carregar(tester);

        expect(find.text('Sequência de apostilas'), findsOneWidget);
        expect(find.text('01 · Informática Essencial 1'), findsOneWidget);
        expect(find.text('02 · Informática Essencial 2'), findsOneWidget);
        expect(find.text('Módulos'), findsNothing, reason: 'não é Modular');

        Finder salvar() =>
            find.widgetWithText(FilledButton, 'Salvar sequência');
        expect(
          tester.widget<FilledButton>(salvar()).onPressed,
          isNull,
          reason: 'sem alteração, desabilitado com motivo',
        );

        await tester.tap(
          find.descendant(
            of: find.widgetWithText(ListTile, '02 · Informática Essencial 2'),
            matching: find.byIcon(Icons.remove_circle_outline),
          ),
        );
        await tester.pumpAndSettle();
        // Olhar a LISTA, não a tela: o item removido reaparece como entrada
        // do menu "Adicionar apostila", cujos rótulos o DropdownMenu monta
        // mesmo fechado.
        Finder naLista(String texto) => find.widgetWithText(ListTile, texto);
        expect(naLista('01 · Informática Essencial 1'), findsOneWidget);
        expect(naLista('02 · Informática Essencial 2'), findsNothing);
        expect(tester.widget<FilledButton>(salvar()).onPressed, isNotNull);

        // Com leitura instantânea a recarga termina antes do frame seguinte e
        // o defeito não aparece; com atraso, a tela é construída no meio da
        // recarga — como contra o banco de verdade.
        repositorio.atrasoLeitura = const Duration(milliseconds: 30);
        await tester.tap(salvar());
        await carregar(tester);
        expect(repositorio.sequencias['c-ess']!.map((l) => l.filhoId), [
          'mat-int-01',
        ]);
        expect(find.text('Sequência salva.'), findsOneWidget);
        // Depois de salvar, o painel mostra o que o banco GRAVOU — e não o
        // valor anterior que o AsyncValue carrega durante a recarga — com o
        // botão de volta ao "nada a salvar".
        expect(naLista('02 · Informática Essencial 2'), findsNothing);
        expect(tester.widget<FilledButton>(salvar()).onPressed, isNull);
      },
    );

    testWidgets('curso Modular mostra os módulos na ordem', (tester) async {
      await montar(tester, repositorio: CatalogoFalso.fixture());
      await tester.tap(find.text('Cursos'));
      await carregar(tester);
      await tester.tap(find.text('Eletricista Instalador'));
      await carregar(tester);
      expect(find.text('Módulos'), findsOneWidget);
      expect(find.text('Módulo 1 — Comandos elétricos'), findsOneWidget);
      expect(find.text('Módulo 3 — Projetos'), findsOneWidget);
      expect(find.text('Novo módulo'), findsNothing, reason: 'sem criar');
      expect(find.text('Editar'), findsNothing, reason: 'sem editar');
    });
  });

  testWidgets('combos: o detalhe lista os cursos na ordem do combo', (
    tester,
  ) async {
    final repositorio = CatalogoFalso.fixture();
    await montar(tester, repositorio: repositorio, permissoes: edicao);
    await tester.tap(find.text('Combos'));
    await carregar(tester);
    expect(find.text('Informática Completo'), findsOneWidget);
    await tester.tap(find.text('Informática Completo'));
    await carregar(tester);
    expect(find.text('Cursos do combo'), findsOneWidget);
    Finder naLista(String texto) => find.widgetWithText(ListTile, texto);
    final essencial = tester.getTopLeft(naLista('Informática Essencial'));
    final avancada = tester.getTopLeft(naLista('Informática Avançada'));
    expect(essencial.dy, lessThan(avancada.dy));
    Finder salvar() => find.widgetWithText(FilledButton, 'Salvar cursos');
    expect(tester.widget<FilledButton>(salvar()).onPressed, isNull);

    // Remover o primeiro e reinserir no fim: é a TROCA de posições, que o
    // plano grava num único upsert (card 2.1 (e)). Depois de salvar, o painel
    // mostra a ordem nova, com o botão de volta ao "nada a salvar".
    await tester.tap(
      find.descendant(
        of: naLista('Informática Essencial'),
        matching: find.byIcon(Icons.remove_circle_outline),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownMenu<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Informática Essencial').last);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(salvar()).onPressed, isNotNull);
    repositorio.atrasoLeitura = const Duration(milliseconds: 30);
    await tester.tap(salvar());
    await carregar(tester);
    expect(repositorio.composicoes['cb-info']!.map((l) => l.filhoId), [
      'c-av',
      'c-ess',
    ]);
    expect(find.text('Cursos do combo salvos.'), findsOneWidget);
    expect(
      tester.getTopLeft(naLista('Informática Avançada')).dy,
      lessThan(tester.getTopLeft(naLista('Informática Essencial')).dy),
    );
    expect(tester.widget<FilledButton>(salvar()).onPressed, isNull);
  });

  testWidgets('no mobile a lista vira cartões com o botão Filtrar (n)', (
    tester,
  ) async {
    await montar(
      tester,
      repositorio: CatalogoFalso.fixture(),
      tamanho: const Size(390, 800),
    );
    expect(find.text('Filtrar (1)'), findsOneWidget);
    expect(find.text('Código'), findsNothing);
    expect(find.text('mín. 2'), findsNWidgets(2));
    expect(find.text('01 · Interativo · APOSTILA'), findsOneWidget);
  });
}

/// Os providers assíncronos resolvem em microtasks; o skeleton anima para
/// sempre, então o `pumpAndSettle` só é seguro depois que os dados chegaram.
Future<void> carregar(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}
