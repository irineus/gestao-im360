import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/widgets/estados.dart';
import 'package:gestao_im360/catalogo/catalogo_provider.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/erros/erro_app.dart';
import 'package:gestao_im360/pendencias/pendencias_provider.dart';
import 'package:gestao_im360/widgets/barra_filtros.dart';
import 'package:gestao_im360/projecao/projecao.dart';
import 'package:gestao_im360/projecao/projecao_provider.dart';
import 'package:gestao_im360/rotina/rotina.dart';
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
    bool assentar = true,
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
    if (assentar) {
      await carregar(tester);
    } else {
      await tester.pump();
      await tester.pump();
    }
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

    // Card 9.2,62: a pendência que discrimina os dois vazios era lida com
    // `.value ?? false` — em carga e em erro a tela afirmava "Sem demanda
    // projetada", o que o design-system §7.2 proíbe.
    testWidgets('enquanto a pendência carrega, NENHUM dos dois vazios é '
        'afirmado', (tester) async {
      projecao = ProjecaoFalso.vazio()
        ..leituraDaRotina = () => Completer<bool>().future;
      // O esqueleto anima para sempre: `pumpAndSettle` nunca assentaria.
      await montar(tester, assentar: false);

      expect(find.text(vazioProjecao), findsNothing);
      expect(find.text(vazioProjecaoRotinaFalhou), findsNothing);
      expect(find.byType(EstadoCarregando), findsWidgets);
    });

    testWidgets('pendência que não pôde ser lida: a tela diz que não sabe, e '
        'oferece de novo', (tester) async {
      projecao = ProjecaoFalso.vazio()
        ..leituraDaRotina = () => Future<bool>.error(Exception('sem rede'));
      await montar(tester);

      expect(find.text(vazioProjecao), findsNothing);
      expect(find.text(vazioProjecaoRotinaFalhou), findsNothing);
      expect(find.text(vazioProjecaoRotinaNaoLida), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
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
      // O cabeçalho NÃO repete o erro (item B5 da revisão das telas 08/09): o
      // carimbo sai da mesma leitura que a grade, e a tabela já mostra a
      // mensagem com "Tentar de novo" — duas frases para uma falha só.
      expect(find.text(erroProjecaoCalculadaEm), findsNothing);
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

  group('revisão das telas 08/09 (itens B1, B2, B3, D3 e D4)', () {
    testWidgets(
      'em 390 px o campo de busca da folha mede o que os menus medem',
      (tester) async {
        // Medido antes: campo de 240 px ao lado de três menus de 358 (item B1).
        await montar(tester, tamanho: const Size(390, 800));
        await tester.tap(find.text('Filtrar'));
        await carregar(tester);

        final busca = tester.getSize(
          find.descendant(
            of: find.byType(CampoBusca),
            matching: find.byType(TextField),
          ),
        );
        final menu = tester.getSize(find.byType(DropdownMenu<String>).first);
        expect(busca.width, menu.width);
      },
    );

    testWidgets('"Ver pendências" define o filtro por tipo antes de navegar', (
      tester,
    ) async {
      projecao = ProjecaoFalso.vazio(rotinaFalhou: true);
      await montar(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TelaProjecao)),
      );

      await tester.tap(find.text('Ver pendências'));
      await carregar(tester);

      expect(ultimaRota, '/pendencias');
      expect(container.read(filtroPendenciasProvider).tipo, 'ROTINA_FALHOU');
    });

    testWidgets(
      'métodos em erro: a coluna diz "não lido" e a tela diz por quê',
      (tester) async {
        // Antes: `—` em toda linha e o filtro só com "Todos", para sempre e sem
        // nenhum erro em tela (item B3).
        catalogo.falhaAoLer = const ErroApp(
          mensagem: 'sem rede',
          traduzido: true,
        );
        await montar(tester);

        expect(find.text(erroMetodosNaoLidos), findsOneWidget);
        expect(find.text(metodoNaoLido), findsWidgets);
        expect(find.text('Interativo'), findsNothing);
        // A grade continua de pé.
        expect(find.text('Informática Essencial 2'), findsOneWidget);

        catalogo.falhaAoLer = null;
        await tester.tap(find.text('Tentar de novo'));
        await carregar(tester);
        expect(find.text(erroMetodosNaoLidos), findsNothing);
        expect(find.text(metodoNaoLido), findsNothing);
        expect(find.text('Interativo'), findsWidgets);
      },
    );

    testWidgets('a célula do mês tem o alvo mínimo do desktop', (tester) async {
      final semantica = tester.ensureSemantics();
      await montar(tester);

      final celula = find.bySemanticsLabel(RegExp(r'^3 em out.*ver os alunos'));
      expect(celula, findsOneWidget);
      expect(tester.getSize(celula).height, greaterThanOrEqualTo(40));
      semantica.dispose();
    });

    testWidgets('a linha do aluno no drill-down anuncia que abre a ficha', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montar(tester);
      await tester.tap(find.text('3').first);
      await carregar(tester);

      expect(
        find.bySemanticsLabel('Aluno 1 (3001), abrir a ficha'),
        findsOneWidget,
      );
      semantica.dispose();
    });
  });

  // Card 9.2,65: a direção recalcula a projeção na hora, do cabeçalho. O
  // comportamento do botão está em recalcular_agora_test; aqui, só o lugar.
  group('"Recalcular agora" no cabeçalho (card 9.2,65)', () {
    for (final (nome, tamanho) in [
      ('desktop', const Size(1400, 1000)),
      ('390 px', const Size(390, 800)),
    ]) {
      testWidgets('$nome: aparece para quem tem parametros.gerir, e só para '
          'quem tem', (tester) async {
        await montar(
          tester,
          permissoes: {...comPendencias, permissaoRecalcular},
          tamanho: tamanho,
        );
        expect(find.text(rotuloRecalcularAgora), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await montar(tester, tamanho: tamanho);
        expect(find.text(rotuloRecalcularAgora), findsNothing);
      });
    }
  });
}
