import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/erros/erro_app.dart';
import 'package:gestao_im360/importacao/importacao.dart';
import 'package:gestao_im360/importacao/importacao_provider.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/importacao/tela_importacao.dart';
import 'package:gestao_im360/telas/importacao/textos_importacao.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/widgets/estados.dart';

import 'apoio/carregar.dart';
import 'apoio/importacao_falso.dart';

/// A tela 13 — Importação (docs/wireframes.md §16), card 9.1.
///
/// A obrigação de teste de um card de **Tela** (docs/estrategia-testes.md §13):
/// guarda de rota tabelada (no `guardas_rota_test`), ocultação por permissão,
/// estado vazio com o texto do card 2.7 **e o teste mobile mínimo em 390×800**,
/// que passou a ser obrigatório no card 8.1,5.
///
/// Três propriedades desta tela que nenhum outro teste alcança:
///
///   • **o ambiente é dito antes de qualquer coisa** — as duas instalações são
///     idênticas, e aqui o erro custa a escola inteira no banco errado;
///   • **não se aplica sem simular** — o §16 escreve "(dry-run primeiro)", e o
///     botão de aplicar nasce desabilitado COM O MOTIVO (design-system §5.7);
///   • **lote reprovado não oferece aplicar** — quem recusa de verdade é o
///     banco (IMPORTACAO_REPROVADA), e a tela não pode oferecer o que vai
///     falhar (wireframes §2.2).
void main() {
  const permissoesDirecao = {
    'admin.ler',
    'materiais.criar',
    'materiais.editar',
    'alunos.criar',
    'alunos.editar',
    'alunos.editar_trilha',
    'salas.criar',
    'salas.editar',
    'salas.registrar_manutencao',
    'professores.criar',
    'turmas.criar',
    'turmas.alocar',
    'estoque.lancar_saida',
    'estoque.ajustar',
    'compras.receber',
  };

  Future<ImportacaoFalso> montar(
    WidgetTester tester, {
    ImportacaoFalso? repositorio,
    String? conteudoDoArquivo = arquivoDeTeste,
    bool seletorDisponivel = true,
    Size tamanho = const Size(1400, 1000),
  }) async {
    final falso = repositorio ?? ImportacaoFalso(totais: totaisDeTeste);
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: semRetryAutomatico,
        overrides: [
          importacaoRepositorioProvider.overrideWithValue(falso),
          seletorDisponivelProvider.overrideWithValue(seletorDisponivel),
          seletorArquivoProvider.overrideWithValue(
            () async => conteudoDoArquivo == null
                ? null
                : ArquivoEscolhido(
                    nome: 'planilha.json',
                    conteudo: conteudoDoArquivo,
                  ),
          ),
          permissoesProvider.overrideWithValue(permissoesDirecao),
          unidadeAtualProvider.overrideWithValue('unidade-teste'),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          home: const Scaffold(body: TelaImportacao()),
        ),
      ),
    );
    await carregar(tester);
    return falso;
  }

  /// A tela é um assistente vertical: o passo 4 fica abaixo da dobra mesmo no
  /// desktop. Sem `ensureVisible` o `tap` "acerta" um widget fora da viewport e
  /// o teste passa a medir o `warnIfMissed` em vez do botão.
  Future<void> tocar(WidgetTester tester, Finder alvo) async {
    await tester.ensureVisible(alvo);
    await carregar(tester);
    await tester.tap(alvo);
    await carregar(tester);
  }

  Future<void> escolherArquivoNaTela(WidgetTester tester) =>
      tocar(tester, find.text('Escolher arquivo…'));

  Future<void> validarNaTela(WidgetTester tester) =>
      tocar(tester, find.text('Validar'));

  testWidgets('a faixa do ambiente é a primeira coisa da tela', (tester) async {
    await montar(tester);
    // `local` é o que `Ambiente.ambiente` vale sem `--dart-define` — é o build
    // de teste, e é honesto que ele diga isso.
    expect(find.textContaining('Você está em ambiente local'), findsOneWidget);
    expect(find.byType(FaixaAmbiente), findsOneWidget);
  });

  testWidgets('sem arquivo, os passos seguintes dizem o que falta', (
    tester,
  ) async {
    await montar(tester);
    expect(find.text(textoImportacaoAguardandoArquivo), findsOneWidget);
    expect(find.text(textoImportacaoAguardandoValidacao), findsWidgets);
    expect(find.text('Validar'), findsNothing);
  });

  testWidgets('fora do navegador a tela diz onde se importa', (tester) async {
    await montar(tester, seletorDisponivel: false);
    expect(find.text(textoImportacaoSemSeletor), findsOneWidget);
    expect(find.text('Escolher arquivo…'), findsNothing);
  });

  testWidgets('o arquivo escolhido é contado por entidade antes de subir', (
    tester,
  ) async {
    await montar(tester);
    await escolherArquivoNaTela(tester);

    expect(find.text('planilha.json'), findsOneWidget);
    expect(find.textContaining('2 linhas em 2 entidades'), findsOneWidget);
    expect(find.text('Alunos: 1'), findsOneWidget);
    expect(find.text('Materiais: 1'), findsOneWidget);
    // O `snapshot_em` do arquivo preenche o campo — é sugestão, e continua
    // editável por quem importa.
    expect(find.text('29/08/2026'), findsOneWidget);
  });

  testWidgets('arquivo ilegível não vira lote: o motivo aparece no passo 1', (
    tester,
  ) async {
    await montar(tester, conteudoDoArquivo: '{"nada": [}');
    await escolherArquivoNaTela(tester);

    expect(find.textContaining('não é um JSON válido'), findsOneWidget);
    expect(find.text('Validar'), findsNothing);
  });

  testWidgets('fechar o seletor sem escolher não muda nada nem dá erro', (
    tester,
  ) async {
    await montar(tester, conteudoDoArquivo: null);
    await escolherArquivoNaTela(tester);

    expect(find.text('planilha.json'), findsNothing);
    expect(find.text(textoImportacaoAguardandoArquivo), findsOneWidget);
  });

  testWidgets('validar cria o lote e o relatório mostra os avisos', (
    tester,
  ) async {
    final falso = await montar(
      tester,
      repositorio: ImportacaoFalso(
        ocorrencias: [ocorrencia(severidade: 'AVISO')],
        totais: totaisDeTeste,
      ),
    );
    await escolherArquivoNaTela(tester);
    await validarNaTela(tester);

    expect(falso.ultimoArquivo, 'planilha.json');
    expect(falso.ultimoSnapshot, DateTime(2026, 8, 29));
    expect(falso.ultimoEnvio?['aluno'], isA<List<dynamic>>());
    expect(find.textContaining('0 erros · 1 aviso'), findsOneWidget);
    expect(find.textContaining('não aparece em turma nenhuma'), findsOneWidget);
  });

  testWidgets('não se aplica sem simular, e o botão diz o motivo', (
    tester,
  ) async {
    await montar(tester);
    await escolherArquivoNaTela(tester);
    await validarNaTela(tester);

    final aplicar = find.widgetWithText(
      FilledButton,
      'Aplicar em ambiente local',
    );
    expect(aplicar, findsOneWidget);
    expect(tester.widget<FilledButton>(aplicar).onPressed, isNull);
    expect(
      find.byTooltip(textoImportacaoSimuleAntes),
      findsOneWidget,
      reason: 'sem estado → desabilitado COM o motivo (design-system §5.7)',
    );
  });

  testWidgets('a simulação mostra os totais e não é a aplicação', (
    tester,
  ) async {
    final falso = await montar(tester);
    await escolherArquivoNaTela(tester);
    await validarNaTela(tester);
    await tocar(tester, find.text('Simular'));
    await carregar(tester);

    expect(falso.aplicacoes.single.simular, isTrue);
    expect(find.text(textoTotaisSimulados), findsOneWidget);
    // A coluna que se compara com o Dashboard da planilha.
    expect(find.text('265'), findsOneWidget);
  });

  testWidgets('aplicar pede confirmação com o ambiente no título', (
    tester,
  ) async {
    final falso = await montar(tester);
    await escolherArquivoNaTela(tester);
    await validarNaTela(tester);
    await tocar(tester, find.text('Simular'));
    await carregar(tester);
    await tocar(tester, find.text('Aplicar em ambiente local'));
    await carregar(tester);

    expect(find.text('Aplicar em ambiente local?'), findsOneWidget);
    await tocar(tester, find.text('Cancelar'));
    await carregar(tester);
    expect(
      falso.aplicacoes.where((a) => !a.simular),
      isEmpty,
      reason: 'cancelar não pode aplicar',
    );

    await tocar(tester, find.text('Aplicar em ambiente local'));
    await carregar(tester);
    await tocar(tester, find.text('Aplicar agora'));
    await carregar(tester);

    expect(falso.aplicacoes.last.simular, isFalse);
    expect(find.text(textoTotaisAplicados), findsOneWidget);
  });

  testWidgets('lote reprovado não oferece aplicar', (tester) async {
    await montar(
      tester,
      repositorio: ImportacaoFalso(
        ocorrencias: [
          ocorrencia(
            severidade: 'ERRO',
            codigo: 'REFERENCIA_AUSENTE',
            mensagem:
                'aluno: material "01" não existe no arquivo nem no sistema.',
          ),
        ],
        totais: totaisDeTeste,
      ),
    );
    await escolherArquivoNaTela(tester);
    await validarNaTela(tester);

    expect(find.text(textoImportacaoReprovada), findsOneWidget);
    expect(find.text('Simular'), findsNothing);
    expect(find.textContaining('não existe no arquivo'), findsOneWidget);
  });

  testWidgets('a recusa do banco vira aviso, e não erro cru', (tester) async {
    await montar(
      tester,
      repositorio: ImportacaoFalso(
        totais: totaisDeTeste,
        falhaAoAplicar: 'Bloco lotado: 2 de 2 vagas ocupadas em 06/09/2026.',
      ),
    );
    await escolherArquivoNaTela(tester);
    await validarNaTela(tester);
    await tocar(tester, find.text('Simular'));
    await carregar(tester);
    await tocar(tester, find.text('Aplicar em ambiente local'));
    await carregar(tester);
    await tocar(tester, find.text('Aplicar agora'));
    await carregar(tester);

    expect(find.textContaining('foi desfeita'), findsWidgets);
    expect(find.textContaining('Bloco lotado'), findsOneWidget);
  });

  testWidgets('erro de permissão do banco chega traduzido, no topo', (
    tester,
  ) async {
    await montar(
      tester,
      repositorio: ImportacaoFalso(
        erroAoRegistrar: const ErroApp(
          codigo: 'SEM_PERMISSAO',
          mensagem: 'Você não tem permissão para esta ação.',
        ),
      ),
    );
    await escolherArquivoNaTela(tester);
    await validarNaTela(tester);

    expect(find.text('Você não tem permissão para esta ação.'), findsOneWidget);
  });

  testWidgets('em 390 px a tela monta sem overflow', (tester) async {
    // A obrigação que o card 8.1,5 tornou regra: nenhuma das telas das fases 06
    // e 07 tinha teste em 390 px, e foi por aí que dois defeitos bloqueantes no
    // celular passaram por todo o CI.
    await montar(tester, tamanho: const Size(390, 800));
    await escolherArquivoNaTela(tester);
    await validarNaTela(tester);
    await tocar(tester, find.text('Simular'));
    await carregar(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(FaixaAmbiente), findsOneWidget);
  });

  group('o lote depois de validar (itens A4 e A5 da revisão 08/09)', () {
    testWidgets('leitura do lote falhando: erro nos passos 3 e 4, e nenhum '
        '"valide no passo 2"', (tester) async {
      // Medido antes da correção: 1 texto "Valide o arquivo no passo 2…" para
      // quem acabou de validar, 0 `EstadoErro`, 0 linha de contagem.
      await montar(
        tester,
        repositorio: ImportacaoFalso(
          totais: totaisDeTeste,
          erroAoLerLote: const ErroApp(mensagem: 'sem rede', traduzido: true),
        ),
      );
      await escolherArquivoNaTela(tester);
      await validarNaTela(tester);

      expect(find.byType(EstadoErro), findsNWidgets(2));
      expect(find.text(textoImportacaoLoteNaoLido), findsNWidgets(2));
      expect(find.text('Tentar de novo'), findsNWidgets(2));
      expect(find.text(textoImportacaoAguardandoValidacao), findsNothing);
    });

    testWidgets('uma linha do histórico REABRE o lote: relatório e Simular', (
      tester,
    ) async {
      final falso = ImportacaoFalso(
        ocorrencias: [ocorrencia(severidade: 'AVISO')],
        totais: totaisDeTeste,
      );
      await montar(tester, repositorio: falso);
      await escolherArquivoNaTela(tester);
      await validarNaTela(tester);

      // O "F5": a página nasce de novo, sem estado, com o mesmo banco. O
      // widget vazio no meio é o que derruba o `State` — um segundo
      // `pumpWidget` da mesma árvore o reaproveitaria, e o teste passaria
      // sem simular nada.
      await tester.pumpWidget(const SizedBox.shrink());
      await montar(tester, repositorio: falso);
      expect(find.text(textoImportacaoAguardandoValidacao), findsWidgets);
      expect(find.text('Simular'), findsNothing);

      await tocar(tester, find.text('planilha.json'));

      expect(find.textContaining('0 erros · 1 aviso'), findsOneWidget);
      expect(find.text('Simular'), findsOneWidget);
      expect(find.text(textoImportacaoAguardandoValidacao), findsNothing);
    });

    testWidgets('um lote APLICADA reaberto mostra os totais dele', (
      tester,
    ) async {
      final falso = ImportacaoFalso(totais: totaisDeTeste);
      await montar(tester, repositorio: falso);
      await escolherArquivoNaTela(tester);
      await validarNaTela(tester);
      await tocar(tester, find.text('Simular'));
      await tocar(tester, find.textContaining('Aplicar em'));
      await tocar(tester, find.text('Aplicar agora'));

      await tester.pumpWidget(const SizedBox.shrink());
      await montar(tester, repositorio: falso);
      expect(find.text(textoTotaisAplicados), findsNothing);

      await tocar(tester, find.text('planilha.json'));
      expect(find.text(textoTotaisAplicados), findsOneWidget);
      expect(find.text('Simular'), findsNothing);
    });
  });

  group('o relatório (itens B4, C1, D2 e E2 da revisão 08/09)', () {
    testWidgets(
      'o motivo de "Baixar relatório" acompanha o estado da leitura',
      (tester) async {
        await montar(
          tester,
          repositorio: ImportacaoFalso(
            ocorrencias: [ocorrencia(severidade: 'AVISO')],
            totais: totaisDeTeste,
            atrasoLeitura: const Duration(milliseconds: 300),
          ),
        );
        await escolherArquivoNaTela(tester);
        await tester.ensureVisible(find.text('Validar'));
        await carregar(tester);
        await tester.tap(find.text('Validar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Enquanto carrega, o motivo é "ainda está carregando" — e não "não há
        // ocorrências", que afirmaria o que ainda não se sabe.
        expect(
          find.byTooltip(textoImportacaoRelatorioCarregando),
          findsOneWidget,
        );
        expect(find.byTooltip(textoImportacaoNadaParaBaixar), findsNothing);

        await carregar(tester);
        expect(
          find.byTooltip(textoImportacaoRelatorioCarregando),
          findsNothing,
        );
      },
    );

    testWidgets('os plurais são por extenso, e o resumo por código existe', (
      tester,
    ) async {
      await montar(
        tester,
        repositorio: ImportacaoFalso(
          ocorrencias: [ocorrencia(severidade: 'AVISO')],
          totais: totaisDeTeste,
        ),
      );
      await escolherArquivoNaTela(tester);
      // "2 linhas em 2 entidades", e não "2 linhas em 2 entidades" por
      // coincidência: com UMA seria "1 linhas em 1 entidades" (item C1).
      expect(find.text('2 linhas em 2 entidades.'), findsOneWidget);
      await validarNaTela(tester);

      expect(find.textContaining('0 erros · 1 aviso'), findsOneWidget);
      expect(find.textContaining('(s)'), findsNothing);
      // O resumo POR CÓDIGO do §16 (item E2), como chip.
      expect(find.text('1 × Aluno sem turma'), findsOneWidget);
    });

    testWidgets('o texto do passo inativo não fica atrás de uma opacidade', (
      tester,
    ) async {
      // `Opacity(0.6)` no passo inteiro levava o `onSurfaceVariant` a 2,36:1;
      // AA é 4,5:1 (design-system §8.1, item D2).
      await montar(tester, conteudoDoArquivo: null);
      final texto = find.text(textoImportacaoAguardandoArquivo);
      expect(texto, findsOneWidget);
      expect(
        find.ancestor(
          of: texto,
          matching: find.byWidgetPredicate(
            (w) => w is Opacity && w.opacity < 0.85,
          ),
        ),
        findsNothing,
      );
    });
  });
}
