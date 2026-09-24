import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/catalogo/catalogo_provider.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/dashboard/dashboard_provider.dart';
import 'package:gestao_im360/pendencias/pendencias_provider.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/dashboard/atencao_hoje.dart';
import 'package:gestao_im360/telas/dashboard/cartoes_alunos.dart';
import 'package:gestao_im360/telas/dashboard/tela_dashboard.dart';
import 'package:gestao_im360/turmas/modular_provider.dart';
import 'package:gestao_im360/widgets/card_dashboard.dart';

import 'apoio/app_de_teste.dart';
import 'apoio/carregar.dart';
import 'apoio/catalogo_falso.dart';
import 'apoio/dashboard_falso.dart';
import 'apoio/modular_falso.dart';
import 'apoio/pendencias_falso.dart';

/// O Dashboard do card 9.2,71 — DECISÃO ADOTADA pela sessão, autorizada por
/// Irineu em 24/09/2026 (a recomendação das Notas do card):
///
///   • a faixa "Atenção hoje" ABRE a tela, com pendências ALTA, entregas
///     bloqueadas sem estoque e materiais abaixo do mínimo — cada número é
///     atalho para a central filtrada, e o zero fica em segundo plano;
///   • os cartões de método ocupam a largura no desktop;
///   • as linhas zeradas dos cartões de aluno ficam em cinza, mais baixas e
///     sem alvo;
///   • o cartão diz o NOME do método ("Inglês"), não o código ("INGLES").
///
/// 1400 px e 390 px.
void main() {
  const permissoes = {
    'alunos.ler',
    'materiais.ler',
    'turmas.ler',
    'salas.ler',
    'pendencias.ler',
    'professores.ler',
  };

  Future<ProviderContainer> montar(
    WidgetTester tester, {
    Size tamanho = const Size(1400, 900),
    PendenciasFalso? pendencias,
    bool comCatalogo = true,
  }) async {
    final container = ProviderContainer(
      retry: semRetryAutomatico,
      overrides: [
        dashboardRepositorioProvider.overrideWithValue(DashboardFalso()),
        pendenciasRepositorioProvider.overrideWithValue(
          pendencias ?? PendenciasFalso.fixture(),
        ),
        modularRepositorioProvider.overrideWithValue(ModularFalso.fixture()),
        if (comCatalogo)
          catalogoRepositorioProvider.overrideWithValue(
            CatalogoFalso.fixture(),
          ),
        permissoesProvider.overrideWithValue(permissoes),
        unidadeAtualProvider.overrideWithValue('unidade-teste'),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: appDeTeste(
          construtor: (filho) => filho,
          conteudo: const Scaffold(body: TelaDashboard()),
        ),
      ),
    );
    await carregar(tester);
    return container;
  }

  for (final (nome, tamanho) in [
    ('desktop', const Size(1400, 900)),
    ('390 px', const Size(390, 800)),
  ]) {
    group(nome, () {
      testWidgets('"Atenção hoje" é a PRIMEIRA região, acima dos alunos', (
        tester,
      ) async {
        await montar(tester, tamanho: tamanho);
        final faixa = tester.getTopLeft(find.text(tituloAtencaoHoje));
        final alunos = tester.getTopLeft(find.text(tituloAlunosPorMetodo));
        expect(faixa.dy, lessThan(alunos.dy));
        // A fixture tem três pendências ALTA e nenhuma das outras duas.
        expect(find.text('pendências de severidade alta'), findsOneWidget);
        expect(find.text('entregas bloqueadas sem estoque'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('o número é atalho para a central filtrada; o zero não é '
          'alvo', (tester) async {
        final c = await montar(tester, tamanho: tamanho);
        expect(
          find.bySemanticsLabel(
            '3 pendências de severidade alta, abrir a central de pendências',
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp('^0 entregas bloqueadas')),
          findsNothing,
          reason: 'abrir uma lista vazia não é ação',
        );

        await tester.tap(find.text('pendências de severidade alta'));
        await carregar(tester);
        expect(c.read(filtroPendenciasProvider).severidade, 'ALTA');
      });

      testWidgets('o cartão diz o NOME do método, e o zero fica em segundo '
          'plano', (tester) async {
        await montar(tester, tamanho: tamanho);
        expect(find.text('Inglês'), findsWidgets);
        expect(find.text('INGLES'), findsNothing);
        // "0 em standby" continua na tela (design-system §7.2), mas sem alvo.
        expect(find.textContaining('0 em standby'), findsWidgets);
        expect(
          find.bySemanticsLabel('0 em standby, abrir a lista'),
          findsNothing,
        );
      });
    });
  }

  testWidgets('desktop: os cartões de método dividem a largura da linha', (
    tester,
  ) async {
    await montar(tester);
    final cartoes = find.byType(CardDashboard);
    // Antes: 200 px cada, três cartões em menos da metade de 1368 px úteis.
    final larguras = [
      for (final e in cartoes.evaluate())
        tester.getSize(find.byWidget(e.widget)).width,
    ];
    expect(larguras.first, greaterThan(larguraCardDashboard * 1.5));
  });

  testWidgets('sem o catálogo, o cartão continua com o código — nunca sem '
      'rótulo', (tester) async {
    await montar(tester, comCatalogo: false);
    expect(find.text('INGLES'), findsWidgets);
  });

  testWidgets('nada pedindo ação: a faixa diz isso, em vez de três zeros', (
    tester,
  ) async {
    await montar(tester, pendencias: PendenciasFalso());
    expect(find.text(semAtencaoHoje), findsOneWidget);
  });

  test('os três números contam pelo tipo e pela severidade', () {
    final itens = itensAtencao([
      pendenciaFalsa(
        id: 'a',
        tipo: 'COMPRA_SEM_ESTOQUE',
        severidade: 'ALTA',
        descricao: 'x',
        chaveDedup: 'a',
      ),
      pendenciaFalsa(
        id: 'b',
        tipo: 'ESTOQUE_ABAIXO_MINIMO',
        severidade: 'MEDIA',
        descricao: 'x',
        chaveDedup: 'b',
      ),
    ]);
    expect([for (final i in itens) i.quantidade], [1, 1, 1]);
    expect(itens[1].rotulo, 'entrega bloqueada sem estoque');
    expect(itens[2].filtro.tipo, 'ESTOQUE_ABAIXO_MINIMO');
  });
}
