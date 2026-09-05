import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/catalogo/catalogo_provider.dart';
import 'package:gestao_im360/certificados/certificados.dart';
import 'package:gestao_im360/certificados/certificados_provider.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/erros/erro_app.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/certificados/tela_certificados.dart';
import 'package:gestao_im360/theme/tema.dart';

import 'apoio/carregar.dart';
import 'apoio/catalogo_falso.dart';
import 'apoio/certificados_falso.dart';

/// A tela 9 — Certificados (docs/wireframes.md §12), card 8.6.
///
/// A obrigação de teste de um card de **Tela** (docs/estrategia-testes.md §13):
/// guarda de rota tabelada (no `guardas_rota_test`), ocultação por permissão,
/// estado vazio com o texto do card 2.7 **e o teste mobile mínimo em 390×800**,
/// que passou a ser obrigatório no card 8.1,5.
void main() {
  // O conjunto mínimo da rota (docs/permissoes-matriz.md §6, linha 9), com o
  // `materiais.ler` que o card 8.6 acrescentou.
  const leitura = {'certificados.ler', 'alunos.ler', 'materiais.ler'};
  const direcao = {
    ...leitura,
    'certificados.criar',
    'certificados.marcar_pedagogico',
    'certificados.marcar_financeiro',
    'certificados.alterar_status',
  };
  // O monitor da matriz do card 2.4 §5: vê o checklist inteiro e só marca o
  // financeiro.
  const monitor = {
    ...leitura,
    'certificados.criar',
    'certificados.marcar_financeiro',
  };

  late CatalogoFalso catalogo;
  late CertificadosFalso certificados;

  setUp(() {
    catalogo = CatalogoFalso.fixture();
    certificados = CertificadosFalso.fixture();
  });

  Future<void> montar(
    WidgetTester tester, {
    Set<String> permissoes = direcao,
    Size tamanho = const Size(1400, 1000),
    String? alunoId,
  }) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: semRetryAutomatico,
        overrides: [
          catalogoRepositorioProvider.overrideWithValue(catalogo),
          certificadosRepositorioProvider.overrideWithValue(certificados),
          permissoesProvider.overrideWithValue(permissoes),
          unidadeAtualProvider.overrideWithValue('unidade-teste'),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          home: Scaffold(body: TelaCertificados(alunoId: alunoId)),
        ),
      ),
    );
    await carregar(tester);
  }

  group('fila', () {
    testWidgets('as DUAS situações aparecem, com rótulos distintos', (
      tester,
    ) async {
      // É a divergência 2 do §17 dos wireframes: o plano fala em "fila do
      // último livro" como se fosse uma coisa só.
      await montar(tester);

      expect(find.text('Ana Paula Ribeiro (4433)'), findsOneWidget);
      expect(find.text(rotuloSituacao(situacaoUltimoLivro)), findsOneWidget);
      expect(find.text(rotuloSituacao(situacaoFim)), findsNWidgets(2));
    });

    testWidgets('FIM vem na frente da fila, e o mais antigo primeiro', (
      tester,
    ) async {
      await montar(tester);

      final nomes = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .where((t) => t != null && t.contains('('))
          .toList();
      expect(nomes.take(3), [
        'Caio Prado (4102)',
        'Bianca Moraes (4501)',
        'Ana Paula Ribeiro (4433)',
      ]);
    });

    testWidgets('quem ainda não tem checklist diz isso, e não caixas vazias', (
      tester,
    ) async {
      // "Ninguém abriu isto" e "o pedagógico ainda não assinou" são estados
      // diferentes, e três caixas vazias contariam o segundo pelo primeiro.
      await montar(tester);

      expect(find.text(semChecklist), findsOneWidget);
      // E o status da coluna Certificado é um traço, não "Não pedido".
      expect(find.text('—'), findsWidgets);
    });
  });

  group('checklist', () {
    testWidgets('o painel mostra quem marcou e quando', (tester) async {
      await montar(tester);

      await tester.tap(find.text('Bianca Moraes (4501)'));
      await carregar(tester);

      expect(find.text('Fim do curso: 18/08/2026'), findsOneWidget);
      expect(find.text('por Paula, 20/08/2026'), findsOneWidget);
      // O item não marcado não tem par quem/quando — o par não é um default.
      expect(find.text('—'), findsWidgets);
      expect(find.text(avisoSugereFormado), findsOneWidget);
    });

    testWidgets('marcar um item chega ao repositório com item e valor', (
      tester,
    ) async {
      await montar(tester);
      await tester.tap(find.text('Bianca Moraes (4501)'));
      await carregar(tester);

      await tester.tap(find.byType(Checkbox).at(1)); // Financeiro
      await carregar(tester);

      expect(certificados.escritas, ['marcar:aluno-2:FINANCEIRO:true']);
      expect(find.text(confirmacaoItemMarcado), findsOneWidget);
    });

    testWidgets('o status muda por função, e a volta é permitida', (
      tester,
    ) async {
      // Não há máquina de estados na tela: "pedido por engano" e "entregue e
      // devolvido para corrigir o nome" são casos reais, e quem decide é o
      // banco (card 8.3).
      await montar(tester);
      await tester.tap(find.text('Caio Prado (4102)'));
      await carregar(tester);

      expect(find.text(avisoFormadoSugerido), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Pedido'));
      await carregar(tester);

      expect(certificados.escritas, ['status:aluno-3:PEDIDO']);
    });

    testWidgets('sem checklist, o painel explica e oferece abrir', (
      tester,
    ) async {
      await montar(tester);
      await tester.tap(find.text('Ana Paula Ribeiro (4433)'));
      await carregar(tester);

      expect(find.text(explicacaoSemChecklist), findsOneWidget);
      await tester.tap(find.text('Abrir checklist'));
      await carregar(tester);

      expect(certificados.escritas, ['abrir:aluno-1']);
      expect(find.text(confirmacaoChecklistAberto), findsOneWidget);
    });

    testWidgets('erro de escrita fica no bloco e não derruba o checklist', (
      tester,
    ) async {
      await montar(tester);
      await tester.tap(find.text('Bianca Moraes (4501)'));
      await carregar(tester);

      certificados.erroDaEscrita = const ErroApp(
        mensagem: 'Você não tem permissão para esta ação.',
        traduzido: true,
      );
      await tester.tap(find.byType(Checkbox).at(1));
      await carregar(tester);

      expect(find.text('Você não tem permissão para esta ação.'), findsWidgets);
      // O checklist continua na tela: o que falhou foi uma marca.
      expect(find.text('Fim do curso: 18/08/2026'), findsOneWidget);
    });
  });

  group('permissão por item', () {
    testWidgets('o monitor vê o checklist inteiro e só marca o financeiro', (
      tester,
    ) async {
      // wireframe §12.2, palavra por palavra. Esconder os outros dois deixaria
      // o monitor sem saber se o pedagógico já assinou.
      await montar(tester, permissoes: monitor);
      await tester.tap(find.text('Bianca Moraes (4501)'));
      await carregar(tester);

      expect(find.text(ItemChecklist.pedagogico.rotulo), findsOneWidget);
      expect(find.text(ItemChecklist.formatura.rotulo), findsOneWidget);
      // Uma caixa só é interativa dentro do painel — a do financeiro.
      expect(find.byType(Checkbox), findsOneWidget);
      // E o status vira texto, não um seletor apagado.
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Não pedido'), findsWidgets);
    });

    testWidgets('sem permissão nenhuma de escrita não há caixa nem seletor', (
      tester,
    ) async {
      await montar(tester, permissoes: leitura);
      await tester.tap(find.text('Bianca Moraes (4501)'));
      await carregar(tester);

      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      // E o "Abrir checklist" também não aparece para quem não pode criar.
      await tester.tap(find.byTooltip('Fechar'));
      await carregar(tester);
      await tester.tap(find.text('Ana Paula Ribeiro (4433)'));
      await carregar(tester);
      expect(find.text('Abrir checklist'), findsNothing);
      expect(find.text(explicacaoSemChecklist), findsOneWidget);
    });
  });

  group('estados', () {
    testWidgets('fila vazia usa o texto do design system', (tester) async {
      certificados = CertificadosFalso.vazio();
      await montar(tester);

      expect(find.text(vazioCertificados), findsOneWidget);
    });

    testWidgets('filtro que esconde tudo oferece limpar', (tester) async {
      await montar(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TelaCertificados)),
      );
      container
          .read(filtroCertificadosProvider.notifier)
          .definir(const FiltroCertificados(busca: 'nao existe'));
      await carregar(tester);

      expect(find.text(vazioCertificadosFiltro), findsOneWidget);
      await tester.tap(find.text('Limpar filtros'));
      await carregar(tester);
      expect(find.text('Bianca Moraes (4501)'), findsOneWidget);
    });

    testWidgets('erro mostra a mensagem traduzida e o botão de repetir', (
      tester,
    ) async {
      certificados.erroDaFila = const ErroApp(
        mensagem: 'Você não tem permissão para esta ação.',
        traduzido: true,
      );
      await montar(tester);

      expect(find.text('Você não tem permissão para esta ação.'), findsWidgets);
      expect(find.text('Tentar de novo'), findsOneWidget);
    });

    testWidgets('`?aluno=` abre o checklist daquele aluno na chegada', (
      tester,
    ) async {
      await montar(tester, alunoId: 'aluno-3');
      await carregar(tester);

      expect(find.text(avisoFormadoSugerido), findsOneWidget);
    });
  });

  group('mobile', () {
    testWidgets('monta em 390×800 sem estourar, com os cartões da fila', (
      tester,
    ) async {
      await montar(tester, tamanho: const Size(390, 800));

      expect(tester.takeException(), isNull);
      expect(find.text('Bianca Moraes (4501)'), findsOneWidget);
      // O resumo do checklist vem na linha de apoio, porque não há coluna.
      expect(find.textContaining('P ok · F pendente'), findsWidgets);
    });

    testWidgets(
      'a caixa Financeiro é acionável na LISTA, sem abrir o checklist',
      (tester) async {
        // A jornada nº 2 do monitor (wireframe §12.2), e é ela que o slot de
        // ação do cartão existe para atender.
        await montar(
          tester,
          permissoes: monitor,
          tamanho: const Size(390, 800),
        );

        expect(tester.takeException(), isNull);
        final caixa = find.byType(Checkbox);
        expect(caixa, findsNWidgets(2)); // as duas linhas com checklist
        // A ordem da fila põe Caio (fim de curso mais antigo) na frente; a
        // segunda caixa é a de Bianca, cujo financeiro está pendente.
        await tester.tap(caixa.at(1));
        await carregar(tester);

        expect(certificados.escritas, ['marcar:aluno-2:FINANCEIRO:true']);
        // E o toque na caixa NÃO abriu o painel por baixo.
        expect(find.byType(Dialog), findsNothing);
      },
    );

    testWidgets('o cartão abre o painel em tela cheia', (tester) async {
      await montar(tester, tamanho: const Size(390, 800));

      await tester.tap(find.text('Bianca Moraes (4501)'));
      await carregar(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Fim do curso: 18/08/2026'), findsOneWidget);
    });
  });
}
