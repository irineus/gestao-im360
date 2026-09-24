import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/catalogo/catalogo_provider.dart';
import 'package:gestao_im360/compras/compras_provider.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/erros/erro_app.dart';
import 'package:gestao_im360/estoque/estoque_provider.dart';
import 'package:gestao_im360/infraestrutura/infraestrutura_provider.dart';
import 'package:gestao_im360/pendencias/pendencias_provider.dart';
import 'package:gestao_im360/projecao/projecao_provider.dart';
import 'package:gestao_im360/rotina/rotina.dart';
import 'package:gestao_im360/rotina/rotina_provider.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/compras/tela_compras.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/turmas/turmas_provider.dart';
import 'package:gestao_im360/widgets/dialogo_resultado.dart';
import 'package:gestao_im360/widgets/recalcular_agora.dart';

import 'apoio/carregar.dart';
import 'apoio/catalogo_falso.dart';
import 'apoio/compras_falso.dart';
import 'apoio/rotina_falso.dart';

/// "Recalcular agora" — a rotina diária sob demanda (card 9.2,65), exercitada
/// na tela de Compras, que é onde a direção lia "a projeção ainda não foi
/// calculada" depois de importar. A Projeção e a Importação conferem só a
/// presença do botão, nos testes delas.
///
/// O que se prova:
///   • sem `parametros.gerir` o botão não existe (card 2.6, decisão 1);
///   • EXECUTADA recarrega o que a rotina escreve — e JA_EM_EXECUCAO não;
///   • enquanto roda, o botão fica desabilitado com o motivo;
///   • o erro vira resultado legível, não exceção;
///   • 390 px e desktop.
void main() {
  const secretaria = {
    'materiais.ler',
    'estoque.ler',
    'alunos.ler',
    'compras.ler',
    'compras.criar',
  };
  const direcao = {...secretaria, permissaoRecalcular};

  late RotinaFalsa rotina;

  Future<ProviderContainer> montar(
    WidgetTester tester, {
    Set<String> permissoes = direcao,
    Size tamanho = const Size(1400, 1000),
  }) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: semRetryAutomatico,
        overrides: [
          catalogoRepositorioProvider.overrideWithValue(
            CatalogoFalso.fixture(),
          ),
          comprasRepositorioProvider.overrideWithValue(ComprasFalso.fixture()),
          rotinaRepositorioProvider.overrideWithValue(rotina),
          permissoesProvider.overrideWithValue(permissoes),
          unidadeAtualProvider.overrideWithValue('unidade-teste'),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          home: const Scaffold(body: TelaCompras()),
        ),
      ),
    );
    await carregar(tester);
    return ProviderScope.containerOf(tester.element(find.byType(TelaCompras)));
  }

  /// As seis versões que a rotina move, numa lista — comparar antes e depois.
  List<int> versoes(ProviderContainer c) => [
    c.read(versaoProjecaoProvider),
    c.read(versaoComprasProvider),
    c.read(versaoEstoqueProvider),
    c.read(versaoPendenciasProvider),
    c.read(versaoTurmasProvider),
    c.read(versaoInfraestruturaProvider),
  ];

  setUp(() => rotina = RotinaFalsa());

  for (final (nome, tamanho) in [
    ('desktop', const Size(1400, 1000)),
    ('390 px', const Size(390, 800)),
  ]) {
    group(nome, () {
      testWidgets('direção: o botão está ao lado do carimbo, e EXECUTADA '
          'recarrega projeção, compras, estoque, pendências, turmas e PCs', (
        tester,
      ) async {
        final c = await montar(tester, tamanho: tamanho);
        expect(find.byKey(chaveRecalcularAgora), findsOneWidget);
        expect(find.text(rotuloRecalcularAgora), findsOneWidget);
        final antes = versoes(c);

        await tester.tap(find.text(rotuloRecalcularAgora));
        await carregar(tester);

        expect(rotina.chamadas, 1);
        expect(find.text(tituloRotinaExecutada), findsOneWidget);
        expect(find.text(mensagemRotinaExecutada), findsOneWidget);
        expect(versoes(c), [for (final v in antes) v + 1]);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(chaveFecharResultado));
        await carregar(tester);
        expect(find.text(tituloRotinaExecutada), findsNothing);
      });

      testWidgets('sem parametros.gerir o botão não é renderizado', (
        tester,
      ) async {
        await montar(tester, permissoes: secretaria, tamanho: tamanho);
        expect(find.text(rotuloRecalcularAgora), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('JA_EM_EXECUCAO: diz para esperar e NÃO recarrega nada — a outra '
      'execução ainda não terminou', (tester) async {
    rotina = RotinaFalsa(resultado: ResultadoRotina.jaEmExecucao);
    final c = await montar(tester);
    final antes = versoes(c);

    await tester.tap(find.text(rotuloRecalcularAgora));
    await carregar(tester);

    expect(find.text(tituloRotinaEmExecucao), findsOneWidget);
    expect(find.text(mensagemRotinaEmExecucao), findsOneWidget);
    expect(versoes(c), antes);
  });

  testWidgets('enquanto roda, o botão fica desabilitado com o motivo — dois '
      'cliques não disparam duas rotinas', (tester) async {
    final espera = Completer<void>();
    rotina = RotinaFalsa(pendente: espera);
    await montar(tester);

    await tester.tap(find.text(rotuloRecalcularAgora));
    await tester.pump();

    expect(find.text(rotuloRecalculando), findsOneWidget);
    expect(find.byTooltip(motivoRecalculando), findsOneWidget);
    final botao = tester.widget<TextButton>(
      find.ancestor(
        of: find.text(rotuloRecalculando),
        matching: find.byType(TextButton),
      ),
    );
    expect(botao.onPressed, isNull);
    await tester.tap(find.text(rotuloRecalculando), warnIfMissed: false);
    expect(rotina.chamadas, 1);

    espera.complete();
    await carregar(tester);
    expect(find.text(tituloRotinaExecutada), findsOneWidget);
    expect(find.text(rotuloRecalcularAgora), findsOneWidget);
  });

  testWidgets('o erro do banco vira resultado legível, com a mensagem do '
      'catálogo — e nada é recarregado', (tester) async {
    rotina = RotinaFalsa(
      erro: const ErroApp(
        codigo: 'SEM_PERMISSAO',
        mensagem: 'Você não tem permissão para executar esta ação.',
      ),
    );
    final c = await montar(tester);
    final antes = versoes(c);

    await tester.tap(find.text(rotuloRecalcularAgora));
    await carregar(tester);

    expect(find.text(tituloRotinaNaoExecutada), findsOneWidget);
    expect(
      find.text('Você não tem permissão para executar esta ação.'),
      findsOneWidget,
    );
    expect(versoes(c), antes);
    expect(tester.takeException(), isNull);
  });

  test('o resultado do banco é lido pelo texto, e o desconhecido é erro', () {
    expect(ResultadoRotina.deTexto('EXECUTADA'), ResultadoRotina.executada);
    expect(
      ResultadoRotina.deTexto('JA_EM_EXECUCAO'),
      ResultadoRotina.jaEmExecucao,
    );
    expect(() => ResultadoRotina.deTexto('OUTRA'), throwsFormatException);
  });
}
