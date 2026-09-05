import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/erros/erro_app.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/widgets/botoes.dart';
import 'package:gestao_im360/widgets/estados.dart';
import 'package:gestao_im360/widgets/tabela_im360.dart';

/// `TabelaIm360` (design-system §5.2): os quatro estados num contrato único, a
/// troca de linhas por cartões no mobile (card 2.8 §9.1, adiada do 3.7 para o
/// primeiro card de tabela) e a degradação por prioridade de coluna
/// (card 2.6 decisão 7).
void main() {
  final colunas = <ColunaIm360<String>>[
    ColunaIm360(
      titulo: 'Código',
      texto: (s) => s.split('|')[0],
      larguraMin: 80,
    ),
    ColunaIm360(
      titulo: 'Nome',
      texto: (s) => s.split('|')[1],
      larguraMin: 160,
      flex: 3,
    ),
    ColunaIm360(
      titulo: 'Categoria',
      texto: (s) => s.split('|')[2],
      prioridade: 3,
      larguraMin: 120,
    ),
    ColunaIm360(
      titulo: 'Mínimo',
      texto: (s) => s.split('|')[3],
      numerica: true,
      prioridade: 2,
      larguraMin: 90,
    ),
  ];

  const itens = ['01|Informática 1|APOSTILA|2', '02|Informática 2|APOSTILA|1'];

  Future<void> montar(
    WidgetTester tester,
    AsyncValue<List<String>> linhas, {
    Size tamanho = const Size(1400, 900),
    CartaoIm360 Function(String)? cartao,
    Widget? filtros,
    VoidCallback? aoRepetir,
    List<Widget> acoes = const [],
  }) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        // `BotaoAcao` observa as permissões do usuário; sem a sobrescrita ele
        // iria ao `Supabase.instance`, que não existe em widget test.
        overrides: [permissoesProvider.overrideWithValue(const {})],
        child: MaterialApp(
          theme: temaClaro(),
          home: Scaffold(
            body: TabelaIm360<String>(
              colunas: colunas,
              linhas: linhas,
              filtros: filtros,
              filtrosAtivos: 2,
              acoes: acoes,
              cartao: cartao,
              aoRepetir: aoRepetir,
              estadoVazio: const EstadoVazio(mensagem: 'Nada por aqui.'),
            ),
          ),
        ),
      ),
    );
  }

  group('estados', () {
    testWidgets('carregando: skeleton, nunca tela branca', (tester) async {
      await montar(tester, const AsyncValue.loading());
      expect(find.byType(EstadoCarregando), findsOneWidget);
      expect(find.text('Código'), findsNothing);
    });

    testWidgets('erro traduzido: mensagem do app, sem código técnico', (
      tester,
    ) async {
      var repetiu = false;
      await montar(
        tester,
        AsyncValue.error(
          const ErroApp(
            mensagem: 'Sem acesso a isto.',
            codigo: 'SEM_PERMISSAO',
          ),
          StackTrace.empty,
        ),
        aoRepetir: () => repetiu = true,
      );
      expect(find.text('Sem acesso a isto.'), findsOneWidget);
      expect(find.textContaining('Código:'), findsNothing);
      await tester.tap(find.text('Tentar de novo'));
      expect(repetiu, isTrue);
    });

    testWidgets('erro não traduzido: o código técnico aparece em apoio', (
      tester,
    ) async {
      await montar(
        tester,
        AsyncValue.error(
          const ErroApp(mensagem: 'Deu ruim.', codigo: '42501'),
          StackTrace.empty,
        ),
      );
      expect(find.text('Código: 42501'), findsOneWidget);
    });

    testWidgets('vazio: o estado da tela, não uma tabela sem linhas', (
      tester,
    ) async {
      await montar(tester, const AsyncValue.data([]));
      expect(find.text('Nada por aqui.'), findsOneWidget);
      expect(find.text('Código'), findsNothing);
    });

    testWidgets('com dados: cabeçalho e uma linha por item', (tester) async {
      await montar(tester, const AsyncValue.data(itens));
      expect(find.text('Código'), findsOneWidget);
      expect(find.text('Informática 1'), findsOneWidget);
      expect(find.text('Informática 2'), findsOneWidget);
    });

    testWidgets('a coluna numérica usa numerais tabulares', (tester) async {
      await montar(tester, const AsyncValue.data(itens));
      final texto = tester.widget<Text>(find.text('2'));
      expect(
        texto.style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(texto.textAlign, TextAlign.end);
    });
  });

  group('degradação por prioridade de coluna', () {
    test('sai primeiro a de maior prioridade; a 1 nunca sai', () {
      // 80 + 160 + 120 + 90 = 450.
      expect(TabelaIm360.colunasVisiveis(colunas, 450).map((c) => c.titulo), [
        'Código',
        'Nome',
        'Categoria',
        'Mínimo',
      ]);
      expect(TabelaIm360.colunasVisiveis(colunas, 400).map((c) => c.titulo), [
        'Código',
        'Nome',
        'Mínimo',
      ]);
      expect(TabelaIm360.colunasVisiveis(colunas, 300).map((c) => c.titulo), [
        'Código',
        'Nome',
      ]);
      // Apertada além do mínimo, as de prioridade 1 ficam mesmo assim —
      // nunca rolagem horizontal da página, nunca tabela sem identidade.
      expect(TabelaIm360.colunasVisiveis(colunas, 50).map((c) => c.titulo), [
        'Código',
        'Nome',
      ]);
    });

    testWidgets('no tablet a coluna † some do cabeçalho', (tester) async {
      await montar(
        tester,
        const AsyncValue.data(itens),
        tamanho: const Size(700, 900),
      );
      // 700 − 32 de margem = 668 ≥ 450: tudo cabe.
      expect(find.text('Categoria'), findsOneWidget);
      await montar(
        tester,
        const AsyncValue.data(itens),
        tamanho: const Size(420, 900),
      );
      // 420 − 32 = 388 < 450: a "Categoria" (prioridade 3) sai primeiro.
      expect(find.text('Categoria'), findsNothing);
      expect(find.text('Mínimo'), findsOneWidget);
    });
  });

  group('mobile', () {
    testWidgets('com cartão declarado, as linhas viram cartões e os filtros '
        'vão para a folha inferior', (tester) async {
      await montar(
        tester,
        const AsyncValue.data(itens),
        tamanho: const Size(390, 800),
        cartao: (s) => CartaoIm360(
          titulo: s.split('|')[1],
          subtitulo: s.split('|')[0],
          destaque: 'mín. ${s.split('|')[3]}',
        ),
        filtros: const Text('FILTROS AQUI'),
      );
      expect(find.text('Código'), findsNothing, reason: 'sem cabeçalho');
      expect(find.text('Informática 1'), findsOneWidget);
      expect(find.text('mín. 2'), findsOneWidget);
      expect(find.text('FILTROS AQUI'), findsNothing);
      expect(find.text('Filtrar (2)'), findsOneWidget);

      await tester.tap(find.text('Filtrar (2)'));
      await tester.pumpAndSettle();
      expect(find.text('FILTROS AQUI'), findsOneWidget);
    });

    testWidgets('sem cartão declarado, o mobile ainda é tabela degradada', (
      tester,
    ) async {
      await montar(
        tester,
        const AsyncValue.data(itens),
        tamanho: const Size(390, 800),
        filtros: const Text('FILTROS AQUI'),
      );
      expect(find.text('Código'), findsOneWidget);
      expect(find.text('Categoria'), findsNothing);
      expect(find.text('FILTROS AQUI'), findsOneWidget);
    });

    testWidgets(
      'em 390 px a barra cabe com duas ações e uma DESABILITADA com motivo '
      'longo',
      (tester) async {
        // ⚠️ Vermelho antes da correção do item H3: a barra era
        // `Row[Filtrar, Spacer, ...acoes]`, e o `BotaoAcao` desabilitado com
        // motivo vira no mobile uma `Column` com a legenda embaixo — dentro de
        // uma `Row`, sem largura para quebrar. Medido: Compras dava
        // `RenderFlex overflowed by 295 px` (537 com mais permissões) e
        // Materiais, 135 px. É o mesmo componente em nove telas.
        await montar(
          tester,
          const AsyncValue.data(itens),
          tamanho: const Size(390, 800),
          cartao: (s) => CartaoIm360(titulo: s.split('|')[1]),
          filtros: const Text('FILTROS AQUI'),
          acoes: const [
            BotaoAcao(
              rotulo: 'Criar pedido com os sugeridos',
              icone: Icons.add_shopping_cart,
              desabilitado: DesabilitadoCom(
                'Nenhum material com sugestão maior que zero na lista atual.',
              ),
            ),
            BotaoAcao(rotulo: 'Novo material', icone: Icons.add),
          ],
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Os dois continuam alcançáveis: a correção desce as ações para uma
        // segunda linha, não as esconde.
        expect(find.text('Criar pedido com os sugeridos'), findsOneWidget);
        expect(find.text('Novo material'), findsOneWidget);
        expect(find.text('Filtrar (2)'), findsOneWidget);
      },
    );
  });
}
