import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/catalogo/catalogo_provider.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/erros/erro_app.dart';
import 'package:gestao_im360/projecao/projecao.dart';
import 'package:gestao_im360/projecao/projecao_provider.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/projecao/tela_projecao.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:go_router/go_router.dart';

import 'apoio/carregar.dart';
import 'apoio/catalogo_falso.dart';
import 'apoio/projecao_falso.dart';

/// A tela 8 — Projeção de demanda (docs/wireframes.md §11), card 8.5.
///
/// A obrigação de teste de um card de **Tela** (docs/estrategia-testes.md §13):
/// guarda de rota tabelada (no `guardas_rota_test`), ocultação por permissão,
/// estado vazio com o texto do card 2.7 **e o teste mobile mínimo em 390×800**,
/// que passou a ser obrigatório no card 8.1,5 — foi por não existir que dois
/// defeitos bloqueantes no celular atravessaram todo o CI.
void main() {
  // O conjunto mínimo da rota (docs/permissoes-matriz.md §6, linha 8), com o
  // `turmas.ler` que o card 8.5 acrescentou.
  const leitura = {'materiais.ler', 'estoque.ler', 'alunos.ler', 'turmas.ler'};
  const comPendencias = {...leitura, 'pendencias.ler'};

  late CatalogoFalso catalogo;
  late ProjecaoFalso projecao;

  setUp(() {
    catalogo = CatalogoFalso.fixture();
    projecao = ProjecaoFalso.fixture();
  });

  var ultimaRota = '/projecao';

  Future<void> montar(
    WidgetTester tester, {
    Set<String> permissoes = comPendencias,
    Size tamanho = const Size(1400, 1000),
    String? materialId,
  }) async {
    ultimaRota = '/projecao';
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: semRetryAutomatico,
        overrides: [
          catalogoRepositorioProvider.overrideWithValue(catalogo),
          projecaoRepositorioProvider.overrideWithValue(projecao),
          permissoesProvider.overrideWithValue(permissoes),
          unidadeAtualProvider.overrideWithValue('unidade-teste'),
        ],
        // `GoRouter` de verdade: a linha do drill-down navega para a ficha do
        // aluno e o vazio da rotina falha navega para Pendências — as duas são
        // exigência do wireframe §11, e um `MaterialApp` com `home` não as
        // exercitaria.
        child: MaterialApp.router(
          theme: temaClaro(),
          routerConfig: GoRouter(
            initialLocation: materialId == null
                ? '/projecao'
                : '/projecao?material=$materialId',
            routes: [
              GoRoute(
                path: '/projecao',
                builder: (_, estado) => Scaffold(
                  body: TelaProjecao(
                    materialId: estado.uri.queryParameters['material'],
                  ),
                ),
              ),
              GoRoute(
                path: '/pendencias',
                builder: (_, _) {
                  ultimaRota = '/pendencias';
                  return const Scaffold(body: Text('central de pendências'));
                },
              ),
              GoRoute(
                path: '/alunos/:id',
                builder: (_, estado) {
                  ultimaRota = '/alunos/${estado.pathParameters['id']}';
                  return const Scaffold(body: Text('ficha'));
                },
              ),
            ],
          ),
        ),
      ),
    );
    await carregar(tester);
  }

  group('grade', () {
    testWidgets('mostra material × mês com o total ao lado', (tester) async {
      await montar(tester);

      // As colunas de mês vêm dos dados, e o cabeçalho é a abreviação do mês.
      expect(find.text('out'), findsOneWidget);
      expect(find.text('nov'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);

      expect(find.text('Informática Essencial 2'), findsOneWidget);
      expect(find.text('Informática Avançada 2'), findsOneWidget);
    });

    testWidgets('o carimbo do cálculo é obrigatório no cabeçalho', (
      tester,
    ) async {
      // Número de projeção sem a data do cálculo é número sem validade
      // (design-system §7.3).
      await montar(tester);

      expect(
        find.text(projecaoCalculadaEm('06/09/2026 03:12')),
        findsOneWidget,
      );
    });

    testWidgets('a proveniência aparece no total, não só no detalhe', (
      tester,
    ) async {
      await montar(tester);

      // "Regra" é o cabeçalho da coluna **e** o rótulo do filtro do
      // wireframe §11 — a proveniência aparece nos dois lugares de propósito.
      expect(find.text('Regra'), findsWidgets);
      // `04` soma dois degraus em novembro.
      expect(find.text(regrasMistas), findsOneWidget);
      expect(find.text('Média do método'), findsWidgets);
    });

    testWidgets('mês sem projeção é traço, e o traço não é alvo da célula', (
      tester,
    ) async {
      await montar(tester);

      // `03` não tem outubro. O traço **não** é alvo de célula — abrir um painel
      // do mês vazio seria a promessa que não se cumpre. O toque cai na LINHA,
      // que continua clicável e abre o material inteiro: é a diferença que o
      // subtítulo do painel diz em palavras.
      expect(find.text('—'), findsWidgets);
      await tester.tap(find.text('—').first);
      await carregar(tester);

      expect(
        find.textContaining('todos os meses do horizonte'),
        findsOneWidget,
      );
      expect(
        find.text(rotuloMes(DateTime(2026, 10), comAno: true)),
        findsNothing,
      );
    });
  });

  group('drill-down', () {
    testWidgets('a célula do mês abre os alunos daquela célula', (
      tester,
    ) async {
      await montar(tester);

      // A célula `02 × out` vale 3 — o wireframe §11 chama isso de
      // "célula INT-04 × out".
      await tester.tap(find.text('3').first);
      await carregar(tester);

      expect(find.text('02 — Informática Essencial 2'), findsOneWidget);
      expect(find.textContaining('3 alunos'), findsOneWidget);
      expect(find.text('Aluno 1 (3001)'), findsOneWidget);
    });

    testWidgets('o detalhe avisa que é de agora e o total é da madrugada', (
      tester,
    ) async {
      await montar(tester);
      await tester.tap(find.text('3').first);
      await carregar(tester);

      expect(find.text(avisoDetalheAoVivo), findsOneWidget);
    });

    testWidgets('a regra e o ritmo aparecem em cada linha do detalhe', (
      tester,
    ) async {
      await montar(tester);
      await tester.tap(find.text('3').first);
      await carregar(tester);

      expect(
        find.textContaining('Média do método · 2º de 5 pendentes'),
        findsOneWidget,
      );
      expect(find.text('30 d'), findsWidgets);
    });

    testWidgets('ritmo nulo vira traço, e não o ritmo do método', (
      tester,
    ) async {
      // `03` sai por PREVISAO_CURSO: a data foi declarada por uma pessoa, e
      // mostrar um ritmo ali seria exibir um número que não gerou aquela data.
      await montar(tester, materialId: 'mat-03');
      await carregar(tester);

      expect(find.text('Previsão do curso · 2º de 5 pendentes'), findsWidgets);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('cada linha do detalhe leva à ficha do aluno', (tester) async {
      await montar(tester);
      await tester.tap(find.text('3').first);
      await carregar(tester);

      await tester.tap(find.text('Aluno 1 (3001)'));
      await carregar(tester);

      expect(ultimaRota, '/alunos/aluno-1');
    });

    testWidgets('`?material=` abre o painel do material já na chegada', (
      tester,
    ) async {
      await montar(tester, materialId: 'mat-04');
      await carregar(tester);

      expect(find.text('04 — Informática Avançada 2'), findsOneWidget);
      expect(
        find.textContaining('todos os meses do horizonte'),
        findsOneWidget,
      );
    });
  });

  group('estados', () {
    testWidgets('rotina falhou: o vazio aponta a pendência e oferece a saída', (
      tester,
    ) async {
      projecao = ProjecaoFalso.vazio(rotinaFalhou: true);
      await montar(tester);

      expect(find.text(vazioProjecaoRotinaFalhou), findsOneWidget);
      expect(find.text(projecaoSemCarimbo), findsOneWidget);

      await tester.tap(find.text('Ver pendências'));
      await carregar(tester);
      expect(ultimaRota, '/pendencias');
    });

    testWidgets('sem pendencias.ler o botão não é renderizado', (tester) async {
      // Sem permissão o botão não aparece (design-system §5.7): oferecer o que
      // leva a "Sem acesso" ensina a não clicar nos outros. O texto continua —
      // saber que a rotina falhou não depende de poder abrir a central.
      projecao = ProjecaoFalso.vazio(rotinaFalhou: true);
      await montar(tester, permissoes: leitura);

      expect(find.text(vazioProjecaoRotinaFalhou), findsOneWidget);
      expect(find.text('Ver pendências'), findsNothing);
    });

    testWidgets('rotina ok e sem linhas: o vazio neutro, sem alarme falso', (
      tester,
    ) async {
      projecao = ProjecaoFalso.vazio();
      await montar(tester);

      expect(find.text(vazioProjecao), findsOneWidget);
      expect(find.text(vazioProjecaoRotinaFalhou), findsNothing);
    });

    testWidgets('filtro que esconde tudo oferece limpar', (tester) async {
      await montar(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TelaProjecao)),
      );
      container
          .read(filtroProjecaoProvider.notifier)
          .definir(const FiltroProjecao(busca: 'nao existe'));
      await carregar(tester);

      expect(find.text(vazioProjecaoFiltro), findsOneWidget);
      await tester.tap(find.text('Limpar filtros'));
      await carregar(tester);
      expect(find.text('Informática Essencial 2'), findsOneWidget);
    });

    testWidgets('erro mostra a mensagem traduzida e o botão de repetir', (
      tester,
    ) async {
      projecao.erroDaGrade = const ErroApp(
        mensagem: 'Você não tem permissão para esta ação.',
        traduzido: true,
      );
      await montar(tester);

      expect(find.text('Você não tem permissão para esta ação.'), findsWidgets);
      expect(find.text('Tentar de novo'), findsOneWidget);
      // O cabeçalho diz o que perdeu: a validade, não a conta.
      expect(find.text(erroProjecaoCalculadaEm), findsOneWidget);
    });
  });

  group('mobile', () {
    testWidgets('monta em 390×800 sem estourar, com o painel em tela cheia', (
      tester,
    ) async {
      await montar(tester, tamanho: const Size(390, 800));

      expect(tester.takeException(), isNull);
      // No celular a tabela vira cartões, e o total é o destaque.
      expect(find.text('Informática Essencial 2'), findsOneWidget);
      expect(find.text('total 3'), findsWidgets);
      // O detalhe do mês vem na linha de apoio do cartão, porque não há coluna.
      expect(find.textContaining('out 3'), findsOneWidget);
    });

    testWidgets('o cartão abre o material inteiro, e o painel é fullscreen', (
      tester,
    ) async {
      await montar(tester, tamanho: const Size(390, 800));

      await tester.tap(find.text('Informática Essencial 2'));
      await carregar(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('02 — Informática Essencial 2'), findsOneWidget);
      expect(
        find.textContaining('todos os meses do horizonte'),
        findsOneWidget,
      );
    });

    testWidgets('o vazio da rotina falha cabe em 390 px', (tester) async {
      // A frase é a mais longa da tela; foi por `Row` sem `Flexible` que o
      // carimbo estourou no card 8.2 (design-system §11, item 19).
      projecao = ProjecaoFalso.vazio(rotinaFalhou: true);
      await montar(tester, tamanho: const Size(390, 800));

      expect(tester.takeException(), isNull);
      expect(find.text(vazioProjecaoRotinaFalhou), findsOneWidget);
    });
  });
}
