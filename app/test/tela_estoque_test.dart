import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/catalogo/catalogo_provider.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/estoque/estoque.dart';
import 'package:gestao_im360/estoque/estoque_provider.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/materiais/tela_materiais.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/widgets/formulario.dart';

import 'apoio/carregar.dart';
import 'apoio/catalogo_falso.dart';
import 'apoio/estoque_falso.dart';

/// O que o card **6.7** acrescentou à tela 6 (docs/wireframes.md §9): as
/// colunas de estoque, a linha em alerta, o painel de movimentações e o ajuste.
///
/// A obrigação de teste de um card de **Tela** (card 2.8 §13) — guarda de rota
/// tabelada, ocultação por permissão, estado vazio com o texto do card 2.7 —
/// está aqui e no `tela_materiais_test`, que continua respondendo pelo catálogo.
void main() {
  const leitura = {'materiais.ler', 'estoque.ler'};
  const comAjuste = {...leitura, 'estoque.ajustar'};
  // Quem edita o cadastro do material, para o painel do mobile ter o que abrir.
  const comEdicao = {...comAjuste, 'materiais.criar', 'materiais.editar'};

  late CatalogoFalso catalogo;
  late EstoqueFalso estoque;

  setUp(() {
    catalogo = CatalogoFalso.fixture();
    estoque = EstoqueFalso.fixture(catalogo);
  });

  Future<void> montar(
    WidgetTester tester, {
    Set<String> permissoes = leitura,
    Size tamanho = const Size(1400, 1000),
  }) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: semRetryAutomatico,
        overrides: [
          catalogoRepositorioProvider.overrideWithValue(catalogo),
          estoqueRepositorioProvider.overrideWithValue(estoque),
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

  Future<void> abrirPainel(WidgetTester tester, String nome) async {
    await tester.tap(find.text(nome));
    await carregar(tester);
  }

  group('a lista com estoque', () {
    testWidgets('saldo negativo é destacado em ERRO e nunca escondido', (
      tester,
    ) async {
      // Card 2.3 §4.1: saldo negativo é sintoma de AJUSTE errado ou de
      // divergência da migração. Some da tela é como um erro de contagem vira
      // um erro de compra.
      await montar(tester);
      expect(find.text('English Book 2'), findsOneWidget);
      expect(find.text('-2'), findsOneWidget);

      final fundo = tester
          .widget<Material>(
            find
                .ancestor(
                  of: find.text('English Book 2'),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color;
      expect(fundo, temaClaro().colorScheme.errorContainer);
      // Cor nunca é portadora única (§8.2): o ícone tem forma própria e o
      // leitor de tela recebe a palavra.
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .where((s) => s.properties.label == 'Saldo -2, saldo negativo'),
        hasLength(1),
        reason: 'quem usa leitor de tela recebe a palavra, não a cor',
      );
    });

    testWidgets('abaixo do mínimo é ATENÇÃO, com fundo tonal terciário', (
      tester,
    ) async {
      await montar(tester);
      final fundo = tester
          .widget<Material>(
            find
                .ancestor(
                  of: find.text('Informática Essencial 2'),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color;
      expect(fundo, temaClaro().colorScheme.tertiaryContainer);
      expect(find.byIcon(Icons.warning_amber_outlined), findsWidgets);
    });

    testWidgets('"Só abaixo do mínimo" filtra, e o estado vazio oferece '
        'limpar', (tester) async {
      await montar(tester);
      expect(find.text('Eletricista Instalador'), findsWidgets);

      await tester.tap(find.widgetWithText(FilterChip, 'Só abaixo do mínimo'));
      await tester.pumpAndSettle();
      expect(find.text('Informática Essencial 2'), findsOneWidget);
      expect(find.text('English Book 2'), findsOneWidget);
      expect(find.text('English Book 1'), findsOneWidget, reason: 'sem saldo');
      expect(
        find.text('Informática Essencial 1'),
        findsNothing,
        reason: 'saldo 24 e mínimo 2',
      );

      // O filtro é da TELA, não da view (card 2.3 §2.3(h)): desligar devolve
      // tudo, e o `(n)` do mobile conta o que está ligado.
      await tester.tap(find.widgetWithText(FilterChip, 'Só abaixo do mínimo'));
      await tester.pumpAndSettle();
      expect(find.text('Informática Essencial 1'), findsOneWidget);
    });
  });

  group('o painel de movimentações', () {
    testWidgets('a linha abre o painel daquele material, com a história', (
      tester,
    ) async {
      await montar(tester);
      await abrirPainel(tester, 'Informática Essencial 1');

      expect(find.text('Movimentações 01'), findsOneWidget);
      expect(
        find.textContaining('saldo 24'),
        findsOneWidget,
        reason: 'o cabeçalho lê o saldo da view, não uma soma da tela',
      );
      // O `DropdownMenu` de tipo monta os rótulos mesmo fechado, então cada
      // tipo aparece uma vez a mais do que na lista.
      expect(find.text('ENTRADA'), findsNWidgets(2));
      expect(find.text('SAIDA'), findsNWidgets(3));
      expect(find.text('+26'), findsOneWidget);
      expect(find.text('−1'), findsNWidgets(2));
      expect(find.text('Pedido 2026-001'), findsOneWidget);
      expect(find.text('Ana Paula Ribeiro (4433)'), findsOneWidget);
      expect(find.text('por Débora'), findsOneWidget);
      expect(find.text('por Célia'), findsOneWidget);
      expect(estoque.chamadas, contains('movimentos:mat-int-01'));
    });

    testWidgets('aluno e pedido que EXISTEM e não são legíveis aparecem por '
        'extenso, nunca como traço', (tester) async {
      // É a decisão da migração deste card: todo `join` de rótulo é externo, e
      // a view manda o id ao lado do nome justamente para a tela poder dizer a
      // diferença. Um traço faria a entrega parecer um ajuste sem dono.
      await montar(tester);
      await abrirPainel(tester, 'Informática Essencial 1');
      expect(find.text('Aluno não visível para o seu perfil'), findsOneWidget);

      await abrirPainel(tester, 'Eletricista Instalador');
      expect(
        find.text(
          'Recebimento de pedido (número não visível para o seu '
          'perfil)',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Estorno de saida de 16/07/2026'),
        findsNothing,
        reason: 'o estorno tem aluno, e o aluno vem antes',
      );
      expect(find.text('Eduarda Lima'), findsNWidgets(2));
    });

    testWidgets('material sem movimento: o texto do §7.2 aponta para Compras', (
      tester,
    ) async {
      await montar(tester);
      await abrirPainel(tester, 'English Book 1');
      expect(find.text(vazioMovimentos), findsOneWidget);
      expect(
        vazioMovimentos,
        contains('Compras'),
        reason: 'não existe "lançar entrada" aqui — card 2.4 (c)',
      );
    });

    testWidgets('o filtro de período esvazia sem esconder que é filtro', (
      tester,
    ) async {
      await montar(tester);
      await abrirPainel(tester, 'Informática Essencial 1');
      expect(find.text('ENTRADA'), findsNWidgets(2), reason: 'lista + menu');

      await tester.tap(find.widgetWithText(DropdownMenu<String>, 'Tipo').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('AJUSTE').last);
      await tester.pumpAndSettle();

      // Vazio POR FILTRO tem texto próprio e ação de limpar (§7.2) — dizer
      // "nenhuma movimentação" aqui faria a pessoa procurar um defeito.
      expect(find.text(vazioMovimentosFiltro), findsOneWidget);
      expect(find.text(vazioMovimentos), findsNothing);
      await tester.tap(find.text('Limpar filtros'));
      await tester.pumpAndSettle();
      expect(find.text('ENTRADA'), findsNWidgets(2));
    });

    testWidgets('erro de leitura do painel fica DENTRO do painel, e a lista '
        'continua de pé', (tester) async {
      // É a correção que o card 5.9 registrou para o dashboard: o erro de uma
      // região não pode ocupar o lugar da tela. Aqui vale igual — a lista de
      // materiais não depende da história de um deles.
      estoque.falhaAoLerMovimentos = EstoqueFalso.erro('403', 'SEM_PERMISSAO', {
        'material': 'mat-int-01',
      });
      await montar(tester);
      await abrirPainel(tester, 'Informática Essencial 1');

      expect(find.text('Movimentações 01'), findsOneWidget);
      expect(
        find.text('Você não tem permissão para esta ação.'),
        findsOneWidget,
      );
      expect(find.text('Tentar de novo'), findsOneWidget);
      // A lista de cima continua lá, com as outras linhas.
      expect(find.text('English Book 2'), findsOneWidget);
      expect(find.text('Eletricista Instalador'), findsWidgets);
    });
  });

  group('o ajuste', () {
    testWidgets('sem estoque.ajustar o botão não é renderizado', (
      tester,
    ) async {
      await montar(tester);
      await abrirPainel(tester, 'Informática Essencial 1');
      expect(find.text('Ajustar'), findsNothing);

      await montar(tester, permissoes: comAjuste);
      await abrirPainel(tester, 'Informática Essencial 1');
      expect(find.text('Ajustar'), findsOneWidget);
    });

    testWidgets('lançar ajuste chega ao repositório com SINAL e motivo, '
        'recarrega e confirma', (tester) async {
      await montar(tester, permissoes: comAjuste);
      await abrirPainel(tester, 'Informática Essencial 1');
      await tester.tap(find.text('Ajustar'));
      await tester.pumpAndSettle();

      expect(find.text('Ajustar estoque'), findsOneWidget);
      expect(find.textContaining('saldo atual 24'), findsOneWidget);
      expect(find.text(avisoAjusteNaoEEntrada), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantidade (com sinal) *'),
        '-3',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo *'),
        'conferência de prateleira',
      );
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      expect(estoque.chamadas, contains('ajustar:mat-int-01:-3'));
      expect(find.text('Ajuste lançado.'), findsOneWidget);
      // O saldo da lista e o do cabeçalho do painel vêm da view recarregada —
      // segurar a linha antiga mostraria o número de antes do lançamento.
      expect(find.text('21'), findsOneWidget);
      expect(find.textContaining('saldo 21'), findsOneWidget);
      expect(find.text('AJUSTE'), findsNWidgets(2), reason: 'lista + menu');
      expect(find.text('conferência de prateleira'), findsOneWidget);
    });

    testWidgets('motivo em branco para no formulário, e MOTIVO_OBRIGATORIO do '
        'banco realça o campo', (tester) async {
      // Duas barreiras que não se substituem: a local é de FORMATO (§5.4) e
      // pega o campo em branco antes da ida ao banco; a do banco é a regra, e
      // chega pelo `codigo` do DETAIL — nunca pelo texto da mensagem.
      await montar(tester, permissoes: comAjuste);
      await abrirPainel(tester, 'Informática Essencial 1');
      await tester.tap(find.text('Ajustar'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantidade (com sinal) *'),
        '2',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo *'),
        '   ',
      );
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await tester.pumpAndSettle();
      expect(find.text('Campo obrigatório.'), findsOneWidget);
      expect(
        estoque.chamadas.where((c) => c.startsWith('ajustar')),
        isEmpty,
        reason: 'campo em branco não chega ao banco',
      );

      // Agora a recusa do banco, com o motivo preenchido: o texto vem do
      // catálogo do card 2.7 §7.1, pelo `codigo`.
      estoque.falhaAoGravar = EstoqueFalso.erro('422', 'MOTIVO_OBRIGATORIO', {
        'material': 'mat-int-01',
      });
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo *'),
        'contagem',
      );
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await tester.pumpAndSettle();
      expect(find.text('Informe o motivo para continuar.'), findsWidgets);
    });

    testWidgets('zero é recusado no formulário, antes de sair da tela', (
      tester,
    ) async {
      // Formato, não regra: zero não é quantidade nenhuma. O banco recusa
      // igual (`QUANTIDADE_INVALIDA`), e as duas barreiras não se substituem.
      await montar(tester, permissoes: comAjuste);
      await abrirPainel(tester, 'Informática Essencial 1');
      await tester.tap(find.text('Ajustar'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantidade (com sinal) *'),
        '0',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo *'),
        'teste',
      );
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await tester.pumpAndSettle();
      expect(
        find.text('A quantidade do ajuste não pode ser zero.'),
        findsOneWidget,
      );
      expect(estoque.chamadas.where((c) => c.startsWith('ajustar')), isEmpty);
    });

    testWidgets('SALDO_INSUFICIENTE vira banner traduzido — a tela não '
        'pré-verifica saldo', (tester) async {
      // Card 2.6 decisão 2: quem decide se o ajuste cabe é a função, dentro da
      // transação e com o advisory lock por material. Conferir aqui seria a
      // terceira soma que o card 2.3 §4.1 proíbe.
      await montar(tester, permissoes: comAjuste);
      await abrirPainel(tester, 'Informática Essencial 1');
      await tester.tap(find.text('Ajustar'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantidade (com sinal) *'),
        '-99',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo *'),
        'contagem',
      );
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await tester.pumpAndSettle();
      expect(
        estoque.chamadas,
        contains('ajustar:mat-int-01:-99'),
        reason: 'a tela submeteu em vez de decidir sozinha',
      );
      expect(
        find.textContaining('O ajuste deixaria o estoque negativo'),
        findsOneWidget,
      );
    });
  });

  testWidgets('não existe caminho de ENTRADA nesta tela', (tester) async {
    // Decisão (c) do card 2.4 §7: `movimento_estoque` recebe `insert` por tipo,
    // e ENTRADA exige `compras.receber`. Entrada é sempre recebimento de
    // pedido, na tela 7 (card 6.8). Divergência da nota do card 6.7 registrada
    // em docs/wireframes.md §17.
    await montar(tester, permissoes: {...comAjuste, 'compras.receber'});
    await abrirPainel(tester, 'Informática Essencial 1');
    expect(find.text('Lançar entrada'), findsNothing);
    expect(find.text('Nova entrada'), findsNothing);
    expect(find.text('Registrar entrada'), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // Revisão das telas 06/07 (card 8.1,5)
  // ---------------------------------------------------------------------------

  testWidgets('o TEXTO da linha em alerta acompanha o fundo tonal (item A1)', (
    tester,
  ) async {
    // ⚠️ Vermelho antes da correção: o fundo vinha de `tertiaryContainer` e o
    // texto ficava com o `onSurface` da tabela — o par de contraste verificado
    // é (container, onContainer), e metade dele não estava sendo usada. Com o
    // `tertiary` também ausente do esquema, o fundo saía GRAFITE e a linha
    // "abaixo do mínimo" ficava ilegível no tema claro.
    await montar(tester);
    final estilo = DefaultTextStyle.of(
      tester.element(find.text('Informática Essencial 2')),
    ).style;
    expect(estilo.color, temaClaro().colorScheme.onTertiaryContainer);
  });

  group('o painel do MOBILE passa pelos mesmos callbacks da aba (item A6)', () {
    testWidgets('editar pelo painel recarrega a lista e confirma', (
      tester,
    ) async {
      // ⚠️ Vermelho antes da correção: `_PainelMobile` chamava
      // `mostrarFormulario` direto, sem passar por `_editar` — que é quem
      // incrementa `versaoEstoqueProvider` (o cadastro muda `estoque_minimo` e
      // `ativo`, colunas de `v_estoque_atual`) e mostra a confirmação. No
      // celular, salvar o mínimo novo deixava lista e cabeçalho no valor
      // antigo.
      await montar(
        tester,
        permissoes: comEdicao,
        tamanho: const Size(390, 800),
      );
      // No mobile a lista é de cartões, e o cartão é aberto pelo NOME.
      await abrirPainel(tester, 'English Book 1');
      await tester.tap(find.text('Editar material'));
      await carregar(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Estoque mínimo *'),
        '9',
      );
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      expect(catalogo.chamadas, contains(startsWith('salvarMaterial')));
      expect(find.text('Material salvo.'), findsOneWidget);
    });
  });

  testWidgets('em 390 px a tela monta sem overflow (item H6)', (tester) async {
    await montar(tester, permissoes: comEdicao, tamanho: const Size(390, 800));
    expect(tester.takeException(), isNull);
    // A ação primária e a folha de filtros continuam alcançáveis — é o que a
    // barra em `Wrap` garante (item H3).
    expect(find.text('Novo material'), findsOneWidget);
    expect(find.text('Filtrar (1)'), findsOneWidget);
    // E as linhas viraram cartões, com o alerta em ícone e palavra.
    expect(find.text('English Book 1'), findsOneWidget);
    expect(find.text('abaixo do mínimo'), findsOneWidget);
  });
}
