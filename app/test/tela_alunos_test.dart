import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/alunos/alunos_provider.dart';
import 'package:gestao_im360/catalogo/catalogo.dart';
import 'package:gestao_im360/catalogo/catalogo_provider.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/alunos/ficha_aluno.dart';
import 'package:gestao_im360/telas/alunos/formularios.dart';
import 'package:gestao_im360/telas/alunos/tela_alunos.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/util/datas.dart';
import 'package:gestao_im360/widgets/badge_status.dart';
import 'package:gestao_im360/widgets/formulario.dart';
import 'package:go_router/go_router.dart';

import 'apoio/alunos_falso.dart';
import 'apoio/carregar.dart';
import 'apoio/catalogo_falso.dart';

/// A obrigação de teste de um card de **Tela** (card 2.8 §13): ocultação por
/// permissão e estado vazio com o texto do card 2.7 — a guarda de rota já está
/// tabelada em `guardas_rota_test.dart`. Mais o que esta tela tem de próprio:
/// a lista resolvendo método e combo pelo catálogo, o badge de status, a
/// ficha como página, o menu de status oferecendo só as transições válidas,
/// o `MOTIVO_OBRIGATORIO` do banco virando banner **e** realce do campo, a
/// reversão só no Histórico e só para quem pode, e a troca de combo avisando.
void main() {
  // Conjuntos da matriz inicial do card 2.4 §5 recortados ao que esta tela
  // consome. `alunos.reverter_status` é só da direção.
  const leitura = {'alunos.ler', 'materiais.ler'};
  const secretaria = {
    ...leitura,
    'alunos.criar',
    'alunos.editar',
    'alunos.alterar_status',
  };
  const direcao = {
    ...secretaria,
    'alunos.reverter_status',
    'alunos.formar_sem_certificado',
  };

  Future<void> montar(
    WidgetTester tester, {
    required AlunosFalso repositorio,
    CatalogoFalso? catalogo,
    Set<String> permissoes = leitura,
    Size tamanho = const Size(1400, 900),
    String rotaInicial = '/alunos',
  }) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Router de verdade: a lista navega para a ficha com `context.go`.
    final roteador = GoRouter(
      initialLocation: rotaInicial,
      routes: [
        GoRoute(
          path: '/alunos',
          builder: (_, _) => const Scaffold(body: TelaAlunos()),
          routes: [
            GoRoute(
              path: ':id',
              builder: (_, estado) => Scaffold(
                body: FichaAluno(alunoId: estado.pathParameters['id']!),
              ),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          alunosRepositorioProvider.overrideWithValue(repositorio),
          catalogoRepositorioProvider.overrideWithValue(
            catalogo ?? CatalogoFalso.fixture(),
          ),
          permissoesProvider.overrideWithValue(permissoes),
          unidadeAtualProvider.overrideWithValue('unidade-teste'),
        ],
        child: MaterialApp.router(routerConfig: roteador, theme: temaClaro()),
      ),
    );
    await carregar(tester);
  }

  Future<void> abrirFicha(WidgetTester tester, String nome) async {
    await tester.tap(find.text(nome));
    await carregar(tester);
  }

  Future<void> escolher(WidgetTester tester, String rotulo, String item) async {
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, rotulo),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  group('lista', () {
    testWidgets('resolve método e combo pelo catálogo, mostra o badge e '
        'esconde formados e cancelados por padrão', (tester) async {
      await montar(tester, repositorio: AlunosFalso.fixture());
      expect(find.text('Ana Paula Ribeiro'), findsOneWidget);
      expect(find.text('3001'), findsOneWidget);
      expect(find.text('Informática Completo'), findsWidgets);
      expect(find.text('Modular'), findsWidgets, reason: 'Eduarda, m-mod');
      expect(find.text('Status'), findsWidgets);
      expect(find.byType(BadgeStatus), findsAtLeastNWidgets(10));
      expect(find.text('João Pedro Martins'), findsNothing, reason: 'FORMADO');
      expect(find.text('Isabela Rocha'), findsNothing, reason: 'CANCELADO');
      expect(find.text('Karina Bastos'), findsOneWidget, reason: 'sem combo');
    });

    testWidgets('sem alunos.criar o botão "Matricular" não é renderizado', (
      tester,
    ) async {
      await montar(tester, repositorio: AlunosFalso.fixture());
      expect(find.text('Matricular'), findsNothing);
      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        permissoes: secretaria,
      );
      expect(find.text('Matricular'), findsOneWidget);
    });

    testWidgets('estado vazio com o texto do card 2.7 — e a ação só para quem '
        'pode matricular', (tester) async {
      await montar(tester, repositorio: AlunosFalso());
      expect(find.text(vazioAlunos), findsOneWidget);
      expect(find.text('+ Matricular'), findsNothing);
      await montar(tester, repositorio: AlunosFalso(), permissoes: secretaria);
      expect(find.text('+ Matricular'), findsOneWidget);
    });

    testWidgets('busca sem resultado: estado vazio de filtro, e "Limpar '
        'filtros" mostra tudo — inclusive os terminais', (tester) async {
      await montar(tester, repositorio: AlunosFalso.fixture());
      await tester.enterText(find.byType(TextField).first, 'zzz');
      await tester.pumpAndSettle();
      expect(find.text(vazioAlunosFiltro), findsOneWidget);

      await tester.tap(find.text('Limpar filtros'));
      await tester.pumpAndSettle();
      expect(find.text('Ana Paula Ribeiro'), findsOneWidget);
      expect(find.text('João Pedro Martins'), findsOneWidget);
      expect(find.text('Isabela Rocha'), findsOneWidget);
      expect(
        tester.widget<FilterChip>(find.byType(FilterChip)).selected,
        false,
      );
    });

    testWidgets('a busca acha pelo código SGF', (tester) async {
      await montar(tester, repositorio: AlunosFalso.fixture());
      await tester.enterText(find.byType(TextField).first, '3006');
      await tester.pumpAndSettle();
      expect(find.text('Felipe Nunes'), findsOneWidget);
      expect(find.text('Ana Paula Ribeiro'), findsNothing);
    });

    testWidgets('matricular grava nome, método, combo e data de início; o '
        'status nasce ATIVO', (tester) async {
      final repositorio = AlunosFalso.fixture();
      await montar(tester, repositorio: repositorio, permissoes: secretaria);
      await tester.tap(find.text('Matricular'));
      await tester.pumpAndSettle();
      expect(find.text('Matricular aluno'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome *'),
        'Marina Costa',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Código SGF'),
        '3013',
      );
      await escolher(tester, 'Método *', 'Interativo');
      await escolher(tester, 'Combo', 'Informática Completo');
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      final nova = repositorio.alunos_.singleWhere(
        (a) => a.nome == 'Marina Costa',
      );
      expect(nova.codigoSgf, '3013');
      expect(nova.metodoId, 'm-int');
      expect(nova.comboId, 'cb-info');
      expect(nova.status, 'ATIVO');
      expect(nova.dataInicio, soData(DateTime.now()));
      expect(find.text('Aluno matriculado.'), findsOneWidget);
      expect(find.text('Marina Costa'), findsOneWidget, reason: 'recarregou');
    });

    testWidgets('no mobile a lista vira cartões com badge e o botão '
        'Filtrar (1)', (tester) async {
      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        tamanho: const Size(390, 800),
      );
      expect(find.text('Filtrar (1)'), findsOneWidget);
      expect(find.text('Status'), findsNothing, reason: 'sem cabeçalho');
      expect(find.text('Ana Paula Ribeiro'), findsOneWidget);
      expect(find.text('3001 · Interativo'), findsOneWidget);
      expect(find.byType(BadgeStatus), findsAtLeastNWidgets(3));
    });
  });

  group('ficha', () {
    testWidgets('tocar a linha abre a ficha: cabeçalho, badge, abas e, sem '
        'permissão, nenhuma ação', (tester) async {
      await montar(tester, repositorio: AlunosFalso.fixture());
      await abrirFicha(tester, 'Ana Paula Ribeiro');
      expect(find.text('código SGF 3001'), findsOneWidget);
      expect(find.textContaining('combo Informática Completo'), findsOneWidget);
      expect(find.text('Dados'), findsOneWidget);
      expect(find.text('Histórico'), findsOneWidget);
      expect(find.text('Data de início'), findsOneWidget);
      expect(find.text('Alterar status'), findsNothing);
      expect(find.text('Editar dados'), findsNothing);
      // Voltar para a lista.
      await tester.tap(find.text('Alunos'));
      await carregar(tester);
      expect(find.text('Matricular aluno'), findsNothing);
      expect(find.text('Bruno Carvalho'), findsOneWidget);
    });

    testWidgets('aluno inexistente (ou de outra unidade): estado próprio, '
        'não tela vazia', (tester) async {
      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        rotaInicial: '/alunos/nao-existe',
      );
      expect(find.text(fichaInexistente), findsOneWidget);
      expect(find.text('Voltar para Alunos'), findsOneWidget);
    });

    testWidgets('alterar status oferece só as transições válidas, avisa ao '
        'sair de ATIVO e grava com o motivo', (tester) async {
      final repositorio = AlunosFalso.fixture();
      await montar(tester, repositorio: repositorio, permissoes: secretaria);
      await abrirFicha(tester, 'Ana Paula Ribeiro');
      await tester.tap(find.text('Alterar status'));
      await tester.pumpAndSettle();
      expect(find.text('Alterar status — Ana Paula Ribeiro'), findsOneWidget);
      expect(find.text(avisoSaiDasTurmas), findsNothing);

      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Novo status *'),
      );
      await tester.pumpAndSettle();
      // ATIVO → ACELERAR, STANDBY, FORMADO, CANCELADO; nunca TRANCADO.
      expect(find.text('TRANCADO'), findsNothing);
      expect(find.text('FORMADO'), findsOneWidget);
      await tester.tap(find.text('STANDBY').last);
      await tester.pumpAndSettle();
      expect(find.text(avisoSaiDasTurmas), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo'),
        'viagem de trabalho',
      );
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      expect(repositorio.chamadas, contains('alterarStatus'));
      final aluno = repositorio.alunos_.singleWhere((a) => a.id == 'al-3001');
      expect(aluno.status, 'STANDBY');
      expect(
        repositorio.historicos['al-3001']!.single.motivo,
        'viagem de trabalho',
      );
      expect(find.text('Status alterado.'), findsOneWidget);
      // A ficha recarregou: o badge do cabeçalho mudou.
      expect(find.text('STANDBY'), findsWidgets);
    });

    testWidgets('MOTIVO_OBRIGATORIO vindo do banco vira banner e realce do '
        'campo — a tela não pré-validou', (tester) async {
      final repositorio = AlunosFalso.fixture();
      await montar(tester, repositorio: repositorio, permissoes: secretaria);
      await abrirFicha(tester, 'Ana Paula Ribeiro');
      await tester.tap(find.text('Alterar status'));
      await tester.pumpAndSettle();
      await escolher(tester, 'Novo status *', 'CANCELADO');
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);
      expect(
        find.text('Informe o motivo para continuar.'),
        findsNWidgets(2),
        reason: 'banner + campo',
      );
      expect(
        repositorio.alunos_.singleWhere((a) => a.id == 'al-3001').status,
        'ATIVO',
      );
      // Digitar no campo limpa o realce; o banner fica até o próximo envio.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo'),
        'mudou de cidade',
      );
      await tester.pumpAndSettle();
      expect(find.text('Informe o motivo para continuar.'), findsOneWidget);
    });

    testWidgets('terminal: "Alterar status" desabilitado com motivo; reverter '
        'mora no Histórico e só a direção vê', (tester) async {
      final repositorio = AlunosFalso.fixture();
      await montar(
        tester,
        repositorio: repositorio,
        permissoes: secretaria,
        rotaInicial: '/alunos/al-isabela',
      );
      // Cabeçalho e aba Dados.
      expect(find.text('Isabela Rocha'), findsNWidgets(2));
      final botao = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Alterar status'),
      );
      expect(botao.onPressed, isNull);
      expect(
        find.byTooltip(
          'Status terminal: para reverter, use a aba '
          'Histórico.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Histórico'));
      await carregar(tester);
      expect(find.textContaining('desistiu do curso'), findsOneWidget);
      expect(find.textContaining('por Diretora Escola A'), findsOneWidget);
      expect(find.text('Reverter status'), findsNothing, reason: 'secretaria');

      await montar(
        tester,
        repositorio: repositorio,
        permissoes: direcao,
        rotaInicial: '/alunos/al-isabela',
      );
      await tester.tap(find.text('Histórico'));
      await carregar(tester);
      await tester.tap(find.text('Reverter status'));
      await tester.pumpAndSettle();
      expect(find.text('Reverter status — Isabela Rocha'), findsOneWidget);
      await escolher(tester, 'Voltar para *', 'ATIVO');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo *'),
        'cancelamento por engano',
      );
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);
      expect(repositorio.chamadas, contains('reverterStatus'));
      final aluno = repositorio.alunos_.singleWhere(
        (a) => a.id == 'al-isabela',
      );
      expect(aluno.status, 'ATIVO');
      expect(find.text('Status revertido.'), findsOneWidget);
      expect(find.textContaining('cancelamento por engano'), findsOneWidget);
      expect(
        find.text('Reverter status'),
        findsNothing,
        reason: 'não é mais terminal',
      );
    });

    testWidgets('FORMADO ainda pode ir a CANCELADO pelo menu — é o que o '
        'banco aceita', (tester) async {
      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        permissoes: secretaria,
        rotaInicial: '/alunos/al-3010',
      );
      final botao = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Alterar status'),
      );
      expect(botao.onPressed, isNotNull);
    });

    testWidgets('editar dados: o método não muda, trocar o combo avisa, e a '
        'gravação não toca o status', (tester) async {
      final repositorio = AlunosFalso.fixture();
      final catalogo = CatalogoFalso.fixture()
        ..combos_.add(
          const Combo(id: 'cb-basico', metodoId: 'm-int', nome: 'Básico'),
        );
      await montar(
        tester,
        repositorio: repositorio,
        catalogo: catalogo,
        permissoes: secretaria,
        rotaInicial: '/alunos/al-3007',
      );
      // Gabriela: Inglês, STANDBY. O método fica travado.
      await tester.tap(find.text('Editar dados'));
      await tester.pumpAndSettle();
      expect(find.text('Dados do aluno'), findsOneWidget);
      final metodo = tester.widget<DropdownButtonFormField<String>>(
        find.widgetWithText(DropdownButtonFormField<String>, 'Método *'),
      );
      expect(metodo.onChanged, isNull);
      expect(find.text(avisoTrocaCombo), findsNothing);
      await tester.tap(find.byType(TextButton).last); // Cancelar
      await tester.pumpAndSettle();

      // Ana Paula: troca o combo de Informática pelo Básico.
      await tester.tap(find.text('Alunos'));
      await carregar(tester);
      await abrirFicha(tester, 'Ana Paula Ribeiro');
      await tester.tap(find.text('Editar dados'));
      await tester.pumpAndSettle();
      await escolher(tester, 'Combo', 'Básico');
      expect(find.text(avisoTrocaCombo), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Observações'),
        'prefere o turno da manhã',
      );
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);
      final aluno = repositorio.alunos_.singleWhere((a) => a.id == 'al-3001');
      expect(aluno.comboId, 'cb-basico');
      expect(aluno.observacoes, 'prefere o turno da manhã');
      expect(aluno.status, 'ATIVO');
      expect(find.text('Dados salvos.'), findsOneWidget);
      expect(find.textContaining('combo Básico'), findsOneWidget);
    });

    testWidgets('histórico vazio com o texto do card 2.7', (tester) async {
      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        rotaInicial: '/alunos/al-3001',
      );
      await tester.tap(find.text('Histórico'));
      await carregar(tester);
      expect(find.text(vazioHistorico), findsOneWidget);
    });
  });
}
