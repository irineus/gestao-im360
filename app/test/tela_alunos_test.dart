import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/alunos/alunos_provider.dart';
import 'package:gestao_im360/catalogo/catalogo.dart';
import 'package:gestao_im360/erros/erro_app.dart';
import 'package:gestao_im360/catalogo/catalogo_provider.dart';
import 'package:gestao_im360/infraestrutura/infraestrutura_provider.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/alunos/aba_turmas.dart';
import 'package:gestao_im360/telas/alunos/ficha_aluno.dart';
import 'package:gestao_im360/telas/alunos/formularios.dart';
import 'package:gestao_im360/telas/alunos/tela_alunos.dart';
import 'package:gestao_im360/turmas/turmas_widgets.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/turmas/turmas.dart';
import 'package:gestao_im360/turmas/turmas_provider.dart';
import 'package:gestao_im360/widgets/badge_status.dart';
import 'package:gestao_im360/widgets/badge_tipo.dart';
import 'package:gestao_im360/widgets/estados.dart';
import 'package:gestao_im360/widgets/formulario.dart';
import 'package:go_router/go_router.dart';

import 'apoio/alunos_falso.dart';
import 'apoio/carregar.dart';
import 'apoio/catalogo_falso.dart';
import 'apoio/infraestrutura_falso.dart';
import 'apoio/turmas_falso.dart';

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

  // Card 5.7: a coluna Turmas e a aba Turmas exigem `turmas.ler`, que NÃO está
  // no conjunto mínimo da rota (card 2.4 §6) — a lista abre sem ele, e é essa
  // diferença que a coluna respeita.
  const comTurmas = {...leitura, 'turmas.ler'};

  Future<void> montar(
    WidgetTester tester, {
    required AlunosFalso repositorio,
    CatalogoFalso? catalogo,
    TurmasFalso? turmas,
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
        retry: semRetryAutomatico,
        overrides: [
          alunosRepositorioProvider.overrideWithValue(repositorio),
          catalogoRepositorioProvider.overrideWithValue(
            catalogo ?? CatalogoFalso.fixture(),
          ),
          turmasRepositorioProvider.overrideWithValue(
            turmas ?? TurmasFalso.fixture(),
          ),
          infraestruturaRepositorioProvider.overrideWithValue(
            InfraestruturaFalso.fixture(),
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

    testWidgets('no mobile o cartão traz a TURMA e o alerta como ÍCONE — o '
        'caractere não existe nas fontes do app', (tester) async {
      // ⚠️ O teste anterior usava um perfil SEM `turmas.ler`, então nunca
      // exercitava a linha de apoio com turma nenhuma — e foi por isso que o
      // cartão ficou sem alerta quando o glifo quebrado saiu (revisão da
      // fase 05, item A1).
      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        permissoes: comTurmas,
        tamanho: const Size(390, 800),
      );

      expect(find.text('Qua 08:00'), findsWidgets, reason: 'a turma no cartão');
      expect(find.text('sem turma'), findsWidgets);
      // O alerta é um `Icon`, e nunca o caractere: o portão de
      // `texto_de_tela_test.dart` já reprova o caractere no código; aqui se
      // assere que o ícone tomou o lugar dele em vez de sumir.
      expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
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

  // -------------------------------------------------------------------------
  // Card 5.7 — a coluna Turmas, o ⚠ de sem turma, e a aba Turmas da ficha
  // -------------------------------------------------------------------------

  group('coluna Turmas', () {
    testWidgets('mostra os blocos do aluno e o ⚠ de quem está em curso sem '
        'turma', (tester) async {
      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        permissoes: comTurmas,
      );
      expect(find.text('Turmas'), findsOneWidget, reason: 'o cabeçalho');
      expect(
        find.text('Qua 08:00'),
        findsNWidgets(3),
        reason: 'Ana Paula, Diego e Karina estão no bloco de quarta',
      );
      // Bruno, Carla, Gabriela, Henrique, Lucas e Eduarda não estão em bloco
      // ativo; só os EM CURSO (ATIVO/ACELERAR) recebem o ⚠.
      // Por LINHA, e não `findsWidgets` solto: só quem está EM CURSO recebe o
      // alerta. Gabriela está em STANDBY e não é problema nenhum.
      Finder linhaDe(String nome) =>
          find.ancestor(of: find.text(nome), matching: find.byType(Row));
      expect(
        find.descendant(
          of: linhaDe('Bruno Carvalho').first,
          matching: find.text('sem turma'),
        ),
        findsOneWidget,
        reason: 'ATIVO sem turma',
      );
      expect(
        find.descendant(
          of: linhaDe('Gabriela Souza').first,
          matching: find.text('sem turma'),
        ),
        findsNothing,
        reason: 'STANDBY não está em curso',
      );
    });

    testWidgets('enquanto as turmas CARREGAM ninguém é marcado como sem turma', (
      tester,
    ) async {
      // ⚠️ `turmasPorAlunoProvider` lê `turmasProvider.value ?? []`: em
      // `loading` o conjunto é vazio e o alerta caía sobre TODO aluno em curso
      // (revisão da fase 05, item B1).
      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        turmas: TurmasFalso(
          celulas: const [],
          turmas: const [],
          atrasoLeitura: const Duration(milliseconds: 200),
        ),
        permissoes: comTurmas,
      );
      await tester.pump();
      expect(find.text('sem turma'), findsNothing);
      await carregar(tester);
    });

    testWidgets('turmas que FALHAM não viram "sem turma" para a escola '
        'inteira', (tester) async {
      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        turmas: TurmasFalso.queFalha(),
        permissoes: comTurmas,
      );
      expect(
        find.text('sem turma'),
        findsNothing,
        reason:
            'alerta falso na tela inteira é a falha calada que o projeto '
            'cataloga',
      );
      // E a coluna DIZ que não deu para saber, com o caminho de volta.
      expect(find.byIcon(Icons.refresh), findsWidgets);
    });

    testWidgets(
      'alocação em bloco DESATIVADO conta como sem turma — o ajuste que o '
      'card 5.6 deixou para cá',
      (tester) async {
        await montar(
          tester,
          repositorio: AlunosFalso.fixture(),
          permissoes: comTurmas,
        );
        // Eduarda está alocada no bloco de sexta, que está desativado: para o
        // sistema ela está sem turma, e é isso que a rotina diária passou a
        // enxergar desde este card.
        expect(find.text('Sex 14:00'), findsNothing);
        final linha = find.ancestor(
          of: find.text('Eduarda Lima'),
          matching: find.byType(Row),
        );
        expect(
          find.descendant(of: linha.first, matching: find.text('sem turma')),
          findsOneWidget,
        );
      },
    );

    testWidgets('status terminal não recebe ⚠: quem cancelou não precisa de '
        'turma', (tester) async {
      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        permissoes: {...comTurmas, 'alunos.criar'},
      );
      // Sem o filtro padrão, os terminais aparecem — e sem ⚠.
      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();
      final linha = find.ancestor(
        of: find.text('Isabela Rocha'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: linha.first, matching: find.text('sem turma')),
        findsNothing,
      );
    });

    testWidgets(
      'sem turmas.ler a coluna NÃO EXISTE — coluna cheia de alerta falso é '
      'pior que coluna ausente',
      (tester) async {
        await montar(tester, repositorio: AlunosFalso.fixture());
        expect(find.text('Turmas'), findsNothing);
        expect(find.text('sem turma'), findsNothing);
        expect(find.text('Qua 08:00'), findsNothing);
      },
    );
  });

  group('aba Turmas da ficha', () {
    testWidgets('lista o bloco com o badge de tipo, e as reposições com a aula '
        'de origem', (tester) async {
      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        permissoes: comTurmas,
        rotaInicial: '/alunos/al-3001',
      );
      await tester.tap(find.text('Turmas'));
      await carregar(tester);

      expect(find.text('Qua 08:00'), findsOneWidget);
      expect(find.byType(BadgeTipo), findsOneWidget);
      expect(find.text('REM'), findsOneWidget);
      // Ana Paula não tem reposição: a seção existe e diz isso.
      expect(find.text(vazioReposicoes), findsOneWidget);
    });

    testWidgets('as reposições do aluno trazem status, bloco e aula perdida', (
      tester,
    ) async {
      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        permissoes: comTurmas,
        rotaInicial: '/alunos/al-lucas',
      );
      await tester.tap(find.text('Turmas'));
      await carregar(tester);

      expect(
        find.textContaining('07/09/2026 · Seg 08:00 · Prevista'),
        findsOneWidget,
      );
      expect(
        find.textContaining('20/08/2026 · Seg 08:00 · Faltou'),
        findsOneWidget,
        reason: 'a reposição quitada ou perdida continua na lista',
      );
      expect(
        find.textContaining('aula de Qua 08:00 · perdida em 27/08/2026'),
        findsWidgets,
      );
    });

    testWidgets('bloco desativado é mostrado, marcado, e com o aviso de que '
        'para o sistema o aluno está sem turma', (tester) async {
      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        permissoes: comTurmas,
        rotaInicial: '/alunos/al-3005',
      );
      await tester.tap(find.text('Turmas'));
      await carregar(tester);

      // A ficha MOSTRA a alocação órfã — é a única tela de onde alguém a
      // desfaz; esconder deixaria o ⚠ da lista sem explicação e sem saída.
      expect(find.text('Sex 14:00'), findsOneWidget);
      expect(find.text('bloco desativado'), findsOneWidget);
      expect(find.text(avisoTurmaDesativada), findsOneWidget);
    });

    testWidgets('aluno em curso sem turma nenhuma avisa em vez de só mostrar '
        'vazio', (tester) async {
      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        permissoes: comTurmas,
        rotaInicial: '/alunos/al-3006',
      );
      await tester.tap(find.text('Turmas'));
      await carregar(tester);
      expect(find.text(vazioTurmasAluno), findsOneWidget);
      expect(find.text(avisoSemTurma), findsOneWidget);
    });

    testWidgets('a situação REP só aparece quando há o que dizer', (
      tester,
    ) async {
      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        permissoes: comTurmas,
        rotaInicial: '/alunos/al-3001',
      );
      await tester.tap(find.text('Turmas'));
      await carregar(tester);
      expect(find.text('Situação de reposição'), findsNothing);

      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        turmas: TurmasFalso(
          turmas: [turmaFalsa(alunoId: 'al-3001', blocoId: 'b-1', tipo: 'REP')],
          situacao: SituacaoRep(
            debito: 3,
            aulaMaisAntiga: DateTime(2026, 9, 12),
            prazoFinal: DateTime(2026, 10, 12),
            semanasUteis: 2,
            capacidade: 1,
            faltasRecentes: 1,
            veredito: 'SUGERIR_CONTINUO',
          ),
        ),
        permissoes: comTurmas,
        rotaInicial: '/alunos/al-3001',
      );
      await tester.tap(find.text('Turmas'));
      await carregar(tester);

      // Os NÚMEROS, e não só o veredito: é o que torna a sugestão acionável
      // (card 5.3, tp_rep_situacao).
      expect(find.textContaining('3 aula(s) a repor'), findsOneWidget);
      expect(find.textContaining('prazo até 12/10/2026'), findsOneWidget);
      expect(find.textContaining('cabem 2 até lá'), findsOneWidget);
      expect(find.text(vereditosRep['SUGERIR_CONTINUO']!), findsOneWidget);
    });

    testWidgets('sem turmas.ler a aba diz o que falta, e não mostra lista '
        'vazia', (tester) async {
      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        rotaInicial: '/alunos/al-3001',
      );
      await tester.tap(find.text('Turmas'));
      await carregar(tester);
      expect(find.byType(EstadoSemAcesso), findsOneWidget);
      expect(find.text(vazioTurmasAluno), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Card 5.11 — as ações da aba Turmas, e os estados que faltavam
  // -------------------------------------------------------------------------

  group('aba Turmas — ações', () {
    const podeAlocar = {...comTurmas, 'turmas.alocar'};

    Future<TurmasFalso> abrirAba(
      WidgetTester tester, {
      TurmasFalso? turmas,
      String aluno = 'al-3001',
      Set<String> permissoes = podeAlocar,
    }) async {
      final repo = turmas ?? TurmasFalso.fixture();
      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        turmas: repo,
        permissoes: permissoes,
        rotaInicial: '/alunos/$aluno',
      );
      await tester.tap(find.text('Turmas'));
      await carregar(tester);
      return repo;
    }

    testWidgets('sem turmas.alocar a aba continua só de leitura', (
      tester,
    ) async {
      await abrirAba(tester, permissoes: comTurmas);
      expect(find.text('Alocar em bloco'), findsNothing);
      expect(find.text('Lançar reposição'), findsNothing);
      expect(find.text('Remover'), findsNothing);
      // E a lista continua visível: ler turma é o que a aba exige.
      expect(find.text('Qua 08:00'), findsOneWidget);
    });

    testWidgets('alocar em bloco escolhe o horário e chama fn_bloco_admitir', (
      tester,
    ) async {
      // Bruno não está em turma nenhuma — é o caso do estado vazio com ação.
      final turmas = await abrirAba(tester, aluno: 'al-3002');
      expect(find.text(vazioTurmasAluno), findsOneWidget);

      await tester.tap(find.text('Alocar em bloco').first);
      await carregar(tester);

      // Só blocos do método dele e com vaga: o de quarta está 10/10 e o de
      // Inglês é de outro método.
      expect(find.textContaining('Seg 08:00 · Laboratório 1'), findsOneWidget);
      expect(find.textContaining('Qua 08:00 · Laboratório 1'), findsNothing);
      expect(find.textContaining('Laboratório 2'), findsNothing);

      await tester.tap(find.textContaining('Seg 08:00 · Laboratório 1'));
      await carregar(tester);
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      expect(turmas.admitidos, ['b-vazio|al-3002|REM']);
      expect(find.text('Aluno alocado.'), findsOneWidget);
    });

    testWidgets('sem escolher bloco é erro do formulário, não do banco', (
      tester,
    ) async {
      final turmas = await abrirAba(tester, aluno: 'al-3002');
      await tester.tap(find.text('Alocar em bloco').first);
      await carregar(tester);
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);
      expect(find.text(escolhaBloco), findsOneWidget);
      expect(turmas.admitidos, isEmpty);
    });

    testWidgets('BLOCO_LOTADO do banco vira banner — a tela não pré-validou', (
      tester,
    ) async {
      final turmas = TurmasFalso.fixture()
        ..erroAoAdmitir = const ErroApp(
          codigo: 'BLOCO_LOTADO',
          mensagem: 'Este bloco não tem vaga livre nesta data.',
          traduzido: true,
        );
      await abrirAba(tester, turmas: turmas, aluno: 'al-3002');
      await tester.tap(find.text('Alocar em bloco').first);
      await carregar(tester);
      await tester.tap(find.textContaining('Seg 08:00 · Laboratório 1'));
      await carregar(tester);
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      expect(
        find.text('Este bloco não tem vaga livre nesta data.'),
        findsOneWidget,
      );
      expect(turmas.admitidos, isNotEmpty, reason: 'a chamada foi feita');
    });

    testWidgets('lançar reposição pela ficha escolhe bloco e data, e a lista '
        'recarrega', (tester) async {
      final turmas = await abrirAba(tester, aluno: 'al-3002');
      await tester.tap(find.text('Lançar reposição'));
      await carregar(tester);

      // Repor é encaixe de um dia: o bloco cheio TAMBÉM é oferecido.
      expect(find.textContaining('Qua 08:00 · Laboratório 1'), findsOneWidget);
      await tester.tap(find.textContaining('Qua 08:00 · Laboratório 1'));
      await carregar(tester);
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      expect(turmas.reposicoesLancadas.single, startsWith('b-cheio|al-3002|'));
      expect(find.text('Reposição lançada.'), findsOneWidget);
      // O falso INSERE de verdade, então a aba mostra o que acabou de nascer —
      // sem isso o teste mediria um mundo em que salvar não muda nada.
      expect(find.text('Próximas'), findsOneWidget);
    });

    testWidgets(
      'alocação em bloco DESATIVADO se remove daqui — e é a única tela que a '
      'desfaz',
      (tester) async {
        // Eduarda está alocada no bloco de sexta, que está desativado: ele não
        // aparece na grade, então o painel do bloco nunca abre para ele.
        final turmas = await abrirAba(tester, aluno: 'al-3005');
        expect(find.text('Sex 14:00'), findsOneWidget);
        expect(find.text('bloco desativado'), findsOneWidget);
        expect(find.text(avisoTurmaDesativada), findsOneWidget);

        await tester.tap(find.text('Remover'));
        await carregar(tester);
        await tester.enterText(
          find.byType(TextFormField).first,
          'bloco encerrado',
        );
        await tester.tap(find.byKey(chaveBotaoSalvar));
        await carregar(tester);

        expect(turmas.removidos, ['b-inativo|al-3005|bloco encerrado']);
        expect(find.text('Aluno removido da turma.'), findsOneWidget);
      },
    );

    testWidgets('remover a última turma ATIVA avisa que abre pendência', (
      tester,
    ) async {
      await abrirAba(tester);
      await tester.tap(find.text('Remover'));
      await carregar(tester);
      expect(find.textContaining('ficará sem nenhuma turma'), findsOneWidget);
    });

    testWidgets('remover alocação órfã NÃO avisa que ficará sem turma — ela já '
        'não contava', (tester) async {
      await abrirAba(tester, aluno: 'al-3005');
      await tester.tap(find.text('Remover'));
      await carregar(tester);
      expect(find.textContaining('ficará sem nenhuma turma'), findsNothing);
    });
  });

  group('aba Turmas — o quarto estado', () {
    testWidgets('erro ao ler as turmas mostra "Tentar de novo", e não uma '
        'lista vazia', (tester) async {
      await montar(
        tester,
        repositorio: AlunosFalso.fixture(),
        turmas: TurmasFalso.queFalha(),
        permissoes: comTurmas,
        rotaInicial: '/alunos/al-3001',
      );
      await tester.tap(find.text('Turmas'));
      await carregar(tester);

      // Três regiões falham juntas (turmas, reposições e situação REP), e
      // nenhuma delas some em silêncio.
      expect(find.text('Tentar de novo'), findsWidgets);
      expect(find.text(vazioTurmasAluno), findsNothing);
      expect(find.text(vazioReposicoes), findsNothing);
    });

    testWidgets(
      'a situação REP que falha DIZ que falhou — antes era indistinguível de '
      'aluno em dia',
      (tester) async {
        await montar(
          tester,
          repositorio: AlunosFalso.fixture(),
          turmas: TurmasFalso.fixture()
            ..erroAoLerSituacao = const ErroApp(
              codigo: 'ALUNO_INEXISTENTE',
              mensagem: 'Este aluno não existe ou você não tem acesso a ele.',
              traduzido: true,
            ),
          permissoes: comTurmas,
          rotaInicial: '/alunos/al-3001',
        );
        await tester.tap(find.text('Turmas'));
        await carregar(tester);

        expect(find.text('Situação de reposição'), findsOneWidget);
        expect(
          find.text('Este aluno não existe ou você não tem acesso a ele.'),
          findsOneWidget,
        );
      },
    );
  });
}
