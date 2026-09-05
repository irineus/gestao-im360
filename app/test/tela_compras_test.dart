import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/catalogo/catalogo_provider.dart';
import 'package:gestao_im360/compras/compras.dart';
import 'package:gestao_im360/compras/compras_provider.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/rotas/rotas.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/compras/tela_compras.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/widgets/formulario.dart';
import 'package:go_router/go_router.dart';

import 'apoio/carregar.dart';
import 'apoio/catalogo_falso.dart';
import 'apoio/compras_falso.dart';

/// A tela 7 — Compras (docs/wireframes.md §10), card 6.8.
///
/// A obrigação de teste de um card de **Tela** (card 2.8 §13) — guarda de rota
/// tabelada, ocultação por permissão, estado vazio com o texto do card 2.7 —
/// está aqui; o `guardas_rota_test` percorre a tabela de rotas, e esta é a
/// única tela do sistema com perfil de fora por decisão explícita.
void main() {
  // O conjunto mínimo da rota (docs/permissoes-matriz.md §6, linha 7).
  const leitura = {'materiais.ler', 'estoque.ler', 'alunos.ler', 'compras.ler'};
  const secretaria = {
    ...leitura,
    'compras.criar',
    'compras.editar',
    'compras.excluir',
    'compras.receber',
  };
  const direcao = {...secretaria, 'compras.receber_excedente'};

  late CatalogoFalso catalogo;
  late ComprasFalso compras;

  setUp(() {
    catalogo = CatalogoFalso.fixture();
    compras = ComprasFalso.fixture();
  });

  Future<void> montar(
    WidgetTester tester, {
    Set<String> permissoes = secretaria,
    Size tamanho = const Size(1400, 1000),
    String? pedidoId,
  }) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: semRetryAutomatico,
        overrides: [
          catalogoRepositorioProvider.overrideWithValue(catalogo),
          comprasRepositorioProvider.overrideWithValue(compras),
          permissoesProvider.overrideWithValue(permissoes),
          unidadeAtualProvider.overrideWithValue('unidade-teste'),
        ],
        // ⚠️ `GoRouter` de verdade, e não um `MaterialApp` com `home`: desde a
        // correção A7 criar um rascunho NAVEGA para `?pedido=<id>`, e é essa
        // navegação que o teste precisa poder exercitar.
        child: MaterialApp.router(
          theme: temaClaro(),
          routerConfig: GoRouter(
            initialLocation: pedidoId == null
                ? '/compras'
                : '/compras?pedido=$pedidoId',
            routes: [
              GoRoute(
                path: '/compras',
                builder: (_, estado) => Scaffold(
                  body: TelaCompras(
                    pedidoId: estado.uri.queryParameters['pedido'],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await carregar(tester);
  }

  Future<void> abrirPedidos(WidgetTester tester) async {
    await tester.tap(find.text('Pedidos'));
    await carregar(tester);
  }

  Future<void> abrirPedido(WidgetTester tester, String numero) async {
    await tester.tap(find.text(numero));
    await carregar(tester);
  }

  group('a guarda da rota — a única tela com perfil de fora', () {
    test(
      'o conjunto mínimo é o do catálogo de permissões, e tem compras.ler',
      () {
        // Card 2.3: sem `compras.ler` a parcela pendente zeraria e o sistema
        // mandaria comprar de novo o que já está a caminho. É por isso que o
        // monitor não abre esta tela.
        final rota = rotasAplicacao.firstWhere((r) => r.id == 'compras');
        expect(rota.exige, {
          'materiais.ler',
          'estoque.ler',
          'alunos.ler',
          'compras.ler',
        });
        expect(podeAbrir(rota, leitura), isTrue);
        expect(
          podeAbrir(rota, const {'materiais.ler', 'estoque.ler', 'alunos.ler'}),
          isFalse,
        );
      },
    );

    test('a tela deixou de ser placeholder', () {
      // O placeholder nomeia o card que entrega a tela para não virar destino
      // permanente (wireframes §18). Este card tirou o nome da lista.
      expect(rotasAplicacao.any((r) => r.id == 'compras'), isTrue);
    });
  });

  group('a aba Pedido sugerido — a conta inteira, com as parcelas', () {
    testWidgets('as parcelas aparecem AO LADO do total', (tester) async {
      // Card 2.3 §2.3: o usuário confere a conta em vez de acreditar nela.
      await montar(tester);
      for (final coluna in [
        'Saldo',
        'Mínimo',
        'Imediata',
        'Projetada',
        'A caminho',
        'Sugerido',
      ]) {
        expect(find.text(coluna), findsOneWidget, reason: 'coluna $coluna');
      }
    });

    testWidgets('a coluna Projetada mostra ZERO, e não some da tela', (
      tester,
    ) async {
      // Card 2.3 §6.2: a reserva é honesta. Esconder a coluna faria a soma
      // exibida não fechar com o total.
      await montar(tester);
      expect(find.text('Projetada'), findsOneWidget);
      expect(find.text('0'), findsWidgets);
    });

    testWidgets(
      '"só sugeridos" vem ligado e esconde o resto — e é desligável',
      (tester) async {
        await montar(tester);
        // Com o chip ligado: os três materiais com sugestão.
        expect(find.text('Informática Avançada 1'), findsOneWidget);
        expect(find.text('Informática Essencial 1'), findsNothing);

        await tester.tap(find.text('Só sugeridos'));
        await carregar(tester);
        // Desligado, a view devolve tudo — inclusive o que acabou de zerar.
        expect(find.text('Informática Essencial 1'), findsOneWidget);
      },
    );
  });

  group('a ocultação por permissão, e o botão desabilitado COM motivo', () {
    testWidgets('sem compras.criar o botão NÃO é renderizado', (tester) async {
      // Design-system §5.7: permissão não destrava na tela; um botão
      // desabilitado sugeriria que preencher algo o destrava.
      await montar(tester, permissoes: leitura);
      expect(find.text('Criar pedido com os sugeridos'), findsNothing);
    });

    testWidgets('com a permissão e sem sugestão na lista, fica visível e '
        'desabilitado com o motivo', (tester) async {
      await montar(tester);
      // Filtra por um método sem sugestão nenhuma… há sugestão em todos os
      // três métodos na fixture, então a busca é o caminho: um termo que casa
      // só com material de sugestão zero.
      await tester.enterText(
        find.widgetWithText(TextField, 'Código ou material'),
        'Essencial 1',
      );
      await carregar(tester);

      final botao = find.widgetWithText(
        FilledButton,
        'Criar pedido com os sugeridos',
      );
      expect(botao, findsOneWidget);
      expect(tester.widget<FilledButton>(botao).onPressed, isNull);
      expect(
        find.byTooltip(
          'Nenhum material com sugestão maior que zero na lista atual.',
        ),
        findsOneWidget,
      );
    });
  });

  group('os estados vazios, com o texto do card 2.7 §7.2', () {
    testWidgets('sem nada a comprar, a frase é a do catálogo', (tester) async {
      compras = ComprasFalso(materiais: const [], pedidos: const [], itens: {});
      await montar(tester);
      expect(find.text(vazioSugerido), findsOneWidget);
    });

    testWidgets('com filtro ligado a frase muda e oferece "Limpar filtros"', (
      tester,
    ) async {
      await montar(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Código ou material'),
        'nao-existe-nada-assim',
      );
      await carregar(tester);
      expect(find.text(vazioSugeridoFiltro), findsOneWidget);
      expect(find.text('Limpar filtros'), findsOneWidget);

      await tester.tap(find.text('Limpar filtros'));
      await carregar(tester);
      expect(find.text('Informática Avançada 1'), findsOneWidget);
    });

    testWidgets('sem pedido, a frase manda ao pedido sugerido', (tester) async {
      compras = ComprasFalso(materiais: const [], pedidos: const [], itens: {});
      await montar(tester);
      await abrirPedidos(tester);
      expect(find.text(vazioPedidos), findsOneWidget);
    });
  });

  group('a aba Pedidos e o painel', () {
    testWidgets('a lista mostra número, situação e o que já chegou', (
      tester,
    ) async {
      await montar(tester);
      await abrirPedidos(tester);
      expect(find.text('2026-002'), findsOneWidget);
      // `findsWidgets`: "Enviado" também é uma opção do filtro de situação.
      expect(find.text('Enviado'), findsWidgets);
      // Rascunho e cancelado não falam de recebimento: um não foi pedido a
      // ninguém, o outro não vem.
      expect(find.text('0 de 15'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('o painel abre com os itens do pedido escolhido', (
      tester,
    ) async {
      await montar(tester);
      await abrirPedidos(tester);
      await abrirPedido(tester, '2026-002');
      expect(find.textContaining('Pedido 2026-002'), findsOneWidget);
      expect(find.text('English Book 2'), findsWidgets);
      expect(find.textContaining('recebido 0 de 10'), findsOneWidget);
    });

    testWidgets('pedido SEM item mostra o vazio que diz o que fazer', (
      tester,
    ) async {
      await montar(tester);
      await abrirPedidos(tester);
      await abrirPedido(tester, '2026-004');
      expect(find.text(vazioItens), findsOneWidget);
    });

    testWidgets(
      'o erro dos itens fica DENTRO do painel, não no lugar da tela',
      (tester) async {
        // A mesma lição do dashboard (card 5.9): a lista de pedidos não depende
        // da consulta dos itens.
        compras.falhaAoLerItens = ComprasFalso.erro('500', 'QUALQUER');
        await montar(tester);
        await abrirPedidos(tester);
        await abrirPedido(tester, '2026-002');
        expect(
          find.text('2026-001'),
          findsOneWidget,
          reason: 'a lista continua',
        );
        expect(find.text('Tentar de novo'), findsOneWidget);
      },
    );
  });

  group('as ações do painel, por ESTADO e por PERMISSÃO', () {
    testWidgets('no rascunho, Enviar está ativo e Receber tem o motivo', (
      tester,
    ) async {
      await montar(tester);
      await abrirPedidos(tester);
      await abrirPedido(tester, '2026-003');

      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Enviar'))
            .onPressed,
        isNotNull,
      );
      expect(
        find.byTooltip('Este pedido não está aguardando recebimento.'),
        findsOneWidget,
      );
    });

    testWidgets('no enviado, Receber está ativo e Enviar tem o motivo', (
      tester,
    ) async {
      await montar(tester);
      await abrirPedidos(tester);
      await abrirPedido(tester, '2026-002');

      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Receber'))
            .onPressed,
        isNotNull,
      );
      expect(
        find.byTooltip('Só pedido em rascunho pode ser editado ou enviado.'),
        findsWidgets,
      );
    });

    testWidgets('sem compras.receber o botão Receber não é renderizado', (
      tester,
    ) async {
      await montar(tester, permissoes: leitura);
      await abrirPedidos(tester);
      await abrirPedido(tester, '2026-002');
      expect(find.text('Receber'), findsNothing);
      expect(find.text('Enviar'), findsNothing);
      expect(find.text('Cancelar pedido'), findsNothing);
    });
  });

  group('o recebimento chega ao repositório, e a recusa vira BANNER', () {
    Future<void> abrirRecebimento(WidgetTester tester) async {
      await abrirPedidos(tester);
      await abrirPedido(tester, '2026-002');
      await tester.tap(find.widgetWithText(FilledButton, 'Receber'));
      await carregar(tester);
    }

    testWidgets('os campos vêm VAZIOS, e o que falta fica escrito ao lado', (
      tester,
    ) async {
      // Preencher seria oferecer "recebi tudo" como resposta pronta a uma
      // conferência — e cada linha vira ENTRADA de estoque, que é imutável.
      await montar(tester);
      await abrirRecebimento(tester);
      final campos = find.widgetWithText(TextFormField, 'Chegou');
      expect(campos, findsNWidgets(2));
      for (final c in tester.widgetList<TextFormField>(campos)) {
        expect(c.controller?.text ?? '', isEmpty);
      }
      // Dentro do formulário: o painel atrás dele mostra a mesma frase, e o que
      // se prova aqui é que ela acompanha o CAMPO.
      expect(
        find.descendant(
          of: find.byType(FormularioIm360),
          matching: find.textContaining('faltam 10'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a quantidade informada chega por item', (tester) async {
      await montar(tester);
      await abrirRecebimento(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Chegou').first,
        '4',
      );
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      expect(compras.chamadas.where((c) => c.startsWith('receber:')), [
        'receber:p-002:i-2=4',
      ]);
    });

    testWidgets('sem compras.receber_excedente, o aviso aparece ANTES', (
      tester,
    ) async {
      await montar(tester);
      await abrirRecebimento(tester);
      expect(find.text(avisoExcedente), findsOneWidget);
    });

    testWidgets('e some para a direção, que pode receber a mais', (
      tester,
    ) async {
      compras.permiteExcedente = true;
      await montar(tester, permissoes: direcao);
      await abrirRecebimento(tester);
      expect(find.text(avisoExcedente), findsNothing);
    });

    testWidgets('RECEBIMENTO_EXCEDE_PEDIDO vira a frase do catálogo, não um '
        'erro cru', (tester) async {
      // Card 2.6 decisão 2: a tela não pré-verifica; o campo aceita e o banco
      // recusa. O que a pessoa lê é o texto do card 2.7 §7.1.
      await montar(tester);
      await abrirRecebimento(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Chegou').first,
        '99',
      );
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      expect(
        find.text(
          'Quantidade acima do pedido — o recebimento com excedente requer a '
          'direção.',
        ),
        findsOneWidget,
      );
      expect(find.text('PT422'), findsNothing);
    });
  });

  group('criar rascunho a partir do sugerido', () {
    testWidgets('leva as linhas EXIBIDAS com sugestão, e abre a aba Pedidos', (
      tester,
    ) async {
      await montar(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Criar pedido com os sugeridos'),
      );
      await carregar(tester);
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      final chamada = compras.chamadas.firstWhere(
        (c) => c.startsWith('criar:'),
      );
      expect(chamada, contains('mat-int-03=4'));
      expect(chamada, contains('mat-ing-02=3'));
      expect(chamada, contains('mat-mod-01=3'));
      // Confirmação efêmera (design-system §5.8) e a aba que passa a valer.
      expect(find.text('Rascunho criado. Confira antes de enviar.'), findsOne);
    });

    testWidgets('o aviso diz que o rascunho AINDA não desconta', (
      tester,
    ) async {
      await montar(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Criar pedido com os sugeridos'),
      );
      await carregar(tester);
      expect(find.text(avisoCriarPedido), findsOneWidget);
    });
  });

  group('a edição do rascunho, e a recusa fora dele', () {
    testWidgets('mudar a quantidade de um item chega ao repositório', (
      tester,
    ) async {
      await montar(tester);
      await abrirPedidos(tester);
      await abrirPedido(tester, '2026-003');
      await tester.tap(find.byTooltip('Editar item'));
      await carregar(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quantidade *'),
        '9',
      );
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      expect(compras.chamadas, contains('quantidade:i-4=9'));
    });

    testWidgets('no pedido enviado o lápis não existe — não há o que editar', (
      tester,
    ) async {
      await montar(tester);
      await abrirPedidos(tester);
      await abrirPedido(tester, '2026-002');
      expect(find.byTooltip('Editar item'), findsNothing);
    });
  });

  group('o cancelamento pede motivo, e o pedido não some', () {
    testWidgets('sem motivo o formulário nem submete', (tester) async {
      await montar(tester);
      await abrirPedidos(tester);
      await abrirPedido(tester, '2026-002');
      await tester.tap(find.widgetWithText(FilledButton, 'Cancelar pedido'));
      await carregar(tester);
      expect(find.text(avisoCancelarPedido), findsOneWidget);

      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);
      expect(find.text('Campo obrigatório.'), findsOneWidget);
      expect(compras.chamadas.where((c) => c.startsWith('cancelar:')), isEmpty);
    });

    testWidgets('com motivo, o motivo chega ao banco', (tester) async {
      await montar(tester);
      await abrirPedidos(tester);
      await abrirPedido(tester, '2026-002');
      await tester.tap(find.widgetWithText(FilledButton, 'Cancelar pedido'));
      await carregar(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo *'),
        'fornecedor sem estoque',
      );
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      expect(
        compras.chamadas,
        contains('cancelar:p-002:fornecedor sem estoque'),
      );
    });
  });

  group('o atalho por URL', () {
    testWidgets('?pedido= abre a aba Pedidos já no pedido pedido', (
      tester,
    ) async {
      await montar(tester, pedidoId: 'p-002');
      expect(find.textContaining('Pedido 2026-002'), findsOneWidget);
    });

    testWidgets('sem o parâmetro nenhum painel abre sozinho', (tester) async {
      await montar(tester);
      await abrirPedidos(tester);
      expect(find.text(semPedidoSelecionado), findsNothing);
      expect(find.textContaining('Pedido 2026-'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Revisão das telas 06/07 (card 8.1,5)
  // ---------------------------------------------------------------------------

  testWidgets('criar o rascunho ABRE o rascunho no painel (item A7)', (
    tester,
  ) async {
    // ⚠️ Vermelho antes da correção: o `FormularioNovoPedido` devolvia o **id**
    // do pedido criado e a aba jogava fora — a pessoa caía na lista e tinha de
    // achar o rascunho —, enquanto o `?pedido=` da rota, escrito para
    // exatamente isto, não era chamado por ninguém.
    await montar(tester);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Criar pedido com os sugeridos'),
    );
    await carregar(tester);
    await tester.tap(find.byKey(chaveBotaoSalvar));
    await carregar(tester);

    await tester.pumpAndSettle();
    // O painel do pedido NOVO, aberto — e é o painel dele, não o de outro:
    // `2026-904` é o número que o falso dá ao rascunho recém-criado.
    expect(find.textContaining('Pedido 2026-904'), findsOneWidget);
    expect(find.text('Acrescentar item'), findsOneWidget);
  });

  testWidgets('o formulário de RECEBER com os itens em erro (item B1)', (
    tester,
  ) async {
    // ⚠️ Vermelho antes da correção: `itens.value ?? []` abria o formulário
    // VAZIO e "Confirmar recebimento" respondia "Informe quanto chegou de ao
    // menos um item" — a mensagem errada para "a lista não carregou".
    compras.falhaAoLerItens = ComprasFalso.erro('500', 'QUALQUER');
    await montar(tester, permissoes: direcao);
    await abrirPedidos(tester);
    await abrirPedido(tester, '2026-002');
    await tester.tap(find.widgetWithText(FilledButton, 'Receber'));
    await carregar(tester);

    expect(find.text(erroItensDoPedido), findsOneWidget);
    expect(
      find.text('Informe quanto chegou de ao menos um item.'),
      findsNothing,
    );
  });

  testWidgets('"Editar item" existe para o leitor de tela (item A5)', (
    tester,
  ) async {
    // ⚠️ Vermelho antes da correção: o `Semantics(excludeSemantics: true)` da
    // linha do item descartava a semântica de TODOS os descendentes, e o
    // "Editar item" deixava de existir para leitor de tela e para o foco. O
    // botão é um `IconButton` com tooltip, então o que se assere é o **nó
    // semântico de botão**, não um rótulo de texto.
    final handle = tester.ensureSemantics();
    await montar(tester);
    await abrirPedidos(tester);
    await abrirPedido(tester, '2026-003');
    final semantica = tester.getSemantics(find.byTooltip('Editar item'));
    expect(semantica.flagsCollection.isButton, isTrue);
    expect(semantica.tooltip, 'Editar item');
    handle.dispose();
  });

  testWidgets('em 390 px a tela monta sem overflow (item H6)', (tester) async {
    await montar(tester, tamanho: const Size(390, 800));
    expect(tester.takeException(), isNull);
    // A ação primária continua alcançável, na segunda linha da barra.
    expect(find.text('Criar pedido com os sugeridos'), findsOneWidget);
    await abrirPedidos(tester);
    expect(tester.takeException(), isNull);
  });
}
