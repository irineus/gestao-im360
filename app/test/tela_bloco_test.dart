import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/alunos/alunos_provider.dart';
import 'package:gestao_im360/catalogo/catalogo_provider.dart';
import 'package:gestao_im360/erros/erro_app.dart';
import 'package:gestao_im360/infraestrutura/infraestrutura_provider.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/turmas/formularios_alocacao.dart';
import 'package:gestao_im360/telas/turmas/painel_bloco.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/turmas/turmas.dart';
import 'package:gestao_im360/turmas/turmas_provider.dart';
import 'package:gestao_im360/turmas/turmas_widgets.dart';
import 'package:gestao_im360/widgets/formulario.dart';

import 'apoio/alunos_falso.dart';
import 'apoio/carregar.dart';
import 'apoio/catalogo_falso.dart';
import 'apoio/infraestrutura_falso.dart';
import 'apoio/turmas_falso.dart';

/// Os alunos do bloco (card 5.7, wireframe §7.2). A obrigação de teste de um
/// card de **Tela** (card 2.8 §13): ocultação por permissão e estado vazio com
/// o texto do card 2.7. Mais o que esta tela tem de próprio:
///
///   • **as duas metades do REP híbrido numa lista só** — alocação e reposição,
///     cada uma com a sua ação, e a reposição dizendo de que aula ela é;
///   • **a ocupação sai da lista, não da célula** — depois de adicionar alguém
///     a célula da grade é a de quando o painel abriu, e erraria por um;
///   • **o aviso do que não se adivinha**: remover a última turma abre
///     pendência amanhã, desmarcar a reposição não repõe a aula.
void main() {
  const leitura = {
    'turmas.ler',
    'salas.ler',
    'professores.ler',
    'materiais.ler',
    'alunos.ler',
  };
  const secretaria = {...leitura, 'turmas.editar', 'turmas.alocar'};

  /// A célula do bloco cheio da fixture — 10/10, sem professor, quarta 08:00.
  Future<CelulaGrade> celulaDe(TurmasFalso turmas, String blocoId) async {
    final grade = await turmas.grade(DateTime(2026, 9, 7));
    return grade.firstWhere((c) => c.blocoId == blocoId);
  }

  Future<TurmasFalso> montar(
    WidgetTester tester, {
    String bloco = 'b-cheio',
    TurmasFalso? repositorio,
    Set<String> permissoes = secretaria,
    Size tamanho = const Size(1400, 900),
    ErroApp? erroDepoisDeAbrir,
  }) async {
    final turmas = repositorio ?? TurmasFalso.fixture();
    // A célula vem da grade, que é leitura: quebrar o repositório antes disso
    // quebraria o próprio harness, e não a tela que se quer medir.
    final celula = await celulaDe(turmas, bloco);
    turmas.erroDeLeitura = erroDepoisDeAbrir;
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: semRetryAutomatico,
        overrides: [
          turmasRepositorioProvider.overrideWithValue(turmas),
          alunosRepositorioProvider.overrideWithValue(AlunosFalso.fixture()),
          catalogoRepositorioProvider.overrideWithValue(
            CatalogoFalso.fixture(),
          ),
          infraestruturaRepositorioProvider.overrideWithValue(
            InfraestruturaFalso.fixture(),
          ),
          permissoesProvider.overrideWithValue(permissoes),
          unidadeAtualProvider.overrideWithValue('unidade-teste'),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          home: Scaffold(body: PainelBloco(celula: celula)),
        ),
      ),
    );
    await carregar(tester);
    return turmas;
  }

  testWidgets(
    'lista os alunos do bloco com o tipo, e a ocupação sai da LISTA',
    (tester) async {
      await montar(tester);

      expect(find.text('Ana Paula Ribeiro'), findsOneWidget);
      expect(find.text('Diego Alves'), findsOneWidget);
      expect(find.text('Karina Bastos'), findsOneWidget);
      // Badge de contorno do tipo (design-system §2.4, card 1.9 §6).
      expect(find.text('REM'), findsOneWidget);
      expect(find.text('PRE'), findsOneWidget);
      expect(find.text('NOVO'), findsOneWidget);

      // Três na lista, capacidade 10 da célula: o número vem da lista, e é por
      // isso que ele fica certo depois de adicionar alguém.
      expect(
        find.textContaining('Ocupação 3/10 (3 alunos)'),
        findsOneWidget,
        reason: 'a célula da grade diz 10/10; a lista tem três',
      );
    },
  );

  testWidgets('a reposição aparece na data dela, marcada e com a aula de '
      'origem', (tester) async {
    await montar(tester, bloco: 'b-vazio');
    expect(find.text('Lucas Ferreira'), findsOneWidget);
    expect(find.text('REP'), findsOneWidget);
    expect(find.text('pontual'), findsOneWidget);
    expect(
      find.textContaining('reposição de Qua 08:00 27/08'),
      findsOneWidget,
      reason: 'sem a origem o rótulo do wireframe §7.2 não existiria',
    );
    // A ação da reposição é DESMARCAR: quem a desfaz é fn_reposicao_cancelar,
    // não fn_bloco_remover.
    expect(find.text('Desmarcar'), findsOneWidget);
    expect(find.text('Remover'), findsNothing);
  });

  testWidgets('sem turmas.alocar nenhuma ação de alocação é renderizada', (
    tester,
  ) async {
    await montar(tester, permissoes: leitura);
    expect(find.text('Adicionar aluno'), findsNothing);
    expect(find.text('Lançar reposição'), findsNothing);
    expect(find.text('Remover'), findsNothing);
    // E a lista continua visível: ler a turma é do conjunto mínimo da rota.
    expect(find.text('Ana Paula Ribeiro'), findsOneWidget);
  });

  testWidgets('sem turmas.editar o "Editar bloco" some', (tester) async {
    await montar(tester, permissoes: leitura);
    expect(find.text('Editar bloco'), findsNothing);
    await montar(tester);
    expect(find.text('Editar bloco'), findsOneWidget);
  });

  testWidgets('bloco vazio na data mostra o estado vazio do card 2.7', (
    tester,
  ) async {
    final turmas = TurmasFalso(
      celulas: (await TurmasFalso.fixture().grade(DateTime(2026, 9, 7))),
      alunos: const {},
    );
    await montar(tester, repositorio: turmas);
    expect(find.text(vazioBloco), findsOneWidget);
  });

  testWidgets('adicionar aluno: só candidatos elegíveis, e a admissão chama a '
      'função do banco', (tester) async {
    final turmas = await montar(tester);
    await tester.tap(find.text('Adicionar aluno'));
    await carregar(tester);

    // Elegível = ATIVO/ACELERAR, do método do bloco, e ainda não no bloco.
    // Ana Paula já está; Gabriela está em STANDBY; Felipe é de outro método.
    // A lista escreve `Nome (código)`, e é por esse formato que se procura —
    // o painel continua atrás do diálogo com o nome puro.
    expect(find.text('Ana Paula Ribeiro (3001)'), findsNothing);
    expect(find.textContaining('Gabriela Souza'), findsNothing);
    expect(find.textContaining('Felipe Nunes'), findsNothing);
    expect(find.text('Bruno Carvalho (3002)'), findsOneWidget);

    await tester.tap(find.text('Bruno Carvalho (3002)'));
    await carregar(tester);
    await tester.tap(find.byKey(chaveBotaoSalvar));
    await carregar(tester);

    expect(turmas.admitidos, ['b-cheio|al-3002|REM']);
    expect(find.text('Aluno adicionado à turma.'), findsOneWidget);
  });

  testWidgets('a busca filtra sem derrubar a seleção — a armadilha do '
      'DropdownButtonFormField do card 5.6', (tester) async {
    await montar(tester);
    await tester.tap(find.text('Adicionar aluno'));
    await carregar(tester);

    await tester.tap(find.text('Bruno Carvalho (3002)'));
    await carregar(tester);

    // Filtrar para um texto que NÃO casa com o selecionado: com um dropdown
    // isto seria um `assert` do framework e a tela cairia.
    await tester.enterText(find.byType(TextFormField).first, 'Carla');
    await carregar(tester);
    expect(find.text('Carla Menezes (3003)'), findsOneWidget);
    expect(find.text('Bruno Carvalho (3002)'), findsNothing);

    // E a seleção sobreviveu ao filtro que a escondeu.
    await tester.enterText(find.byType(TextFormField).first, '');
    await carregar(tester);
    expect(find.text('Bruno Carvalho (3002)'), findsOneWidget);
  });

  testWidgets('salvar sem escolher aluno é erro do formulário, não do banco', (
    tester,
  ) async {
    final turmas = await montar(tester);
    await tester.tap(find.text('Adicionar aluno'));
    await carregar(tester);
    await tester.tap(find.byKey(chaveBotaoSalvar));
    await carregar(tester);
    expect(find.text(escolhaAluno), findsOneWidget);
    expect(turmas.admitidos, isEmpty);
  });

  testWidgets('remover a última turma avisa que abre pendência amanhã', (
    tester,
  ) async {
    final turmas = await montar(tester);
    // Karina está só neste bloco; Ana Paula também. Removê-la deixa o aluno
    // sem turma nenhuma, e é isso que a rotina das 03:10 acusa (card 5.5).
    await tester.tap(find.text('Remover').first);
    await carregar(tester);
    expect(find.textContaining('ficará sem nenhuma turma'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'mudou de turno');
    await tester.tap(find.byKey(chaveBotaoSalvar));
    await carregar(tester);
    expect(turmas.removidos, ['b-cheio|al-3001|mudou de turno']);
  });

  testWidgets('desmarcar a reposição avisa que a aula continua em aberto', (
    tester,
  ) async {
    final turmas = await montar(tester, bloco: 'b-vazio');
    await tester.tap(find.text('Desmarcar'));
    await carregar(tester);
    expect(find.text(avisoDesmarcarReposicao), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'remarcar');
    await tester.tap(find.byKey(chaveBotaoSalvar));
    await carregar(tester);
    expect(turmas.canceladas, ['rep-al-lucas|remarcar']);
    expect(turmas.removidos, isEmpty, reason: 'reposição não é alocação');
  });

  testWidgets('lançar reposição vem com a data da célula e aceita quem já está '
      'no bloco', (tester) async {
    final turmas = await montar(tester);
    await tester.tap(find.text('Lançar reposição'));
    await carregar(tester);

    // Ao contrário da admissão, quem já está no bloco continua elegível: repor
    // é encaixe de um dia.
    expect(find.text('Ana Paula Ribeiro (3001)'), findsOneWidget);

    await tester.tap(find.text('Ana Paula Ribeiro (3001)'));
    await carregar(tester);
    await tester.tap(find.byKey(chaveBotaoSalvar));
    await carregar(tester);

    // Quarta da semana de 07/09/2026 = 09/09.
    expect(turmas.reposicoesLancadas, ['b-cheio|al-3001|2026-09-09']);
  });

  testWidgets('data no passado sem a permissão retroativa avisa antes do '
      'clique', (tester) async {
    await montar(tester);
    await tester.tap(find.text('Lançar reposição'));
    await carregar(tester);
    expect(find.text(avisoRetroativa), findsNothing);

    // O campo da data é o segundo TextFormField (o primeiro é a busca).
    await tester.enterText(find.byType(TextFormField).at(1), '01/01/2020');
    await carregar(tester);
    expect(find.text(avisoRetroativa), findsOneWidget);
  });

  testWidgets('com a permissão retroativa o aviso não aparece', (tester) async {
    await montar(
      tester,
      permissoes: {...secretaria, 'turmas.lancar_reposicao_retroativa'},
    );
    await tester.tap(find.text('Lançar reposição'));
    await carregar(tester);
    await tester.enterText(find.byType(TextFormField).at(1), '01/01/2020');
    await carregar(tester);
    expect(find.text(avisoRetroativa), findsNothing);
  });

  testWidgets('bloco acima da capacidade avisa que a admissão está bloqueada', (
    tester,
  ) async {
    await montar(tester, bloco: 'b-acima');
    expect(find.text(avisoAcimaCapacidade), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Card 5.11 — marcar presença aqui, e os estados que faltavam
  // -------------------------------------------------------------------------

  testWidgets('Veio/Faltou existe na reposição do dia e mostra o VEREDITO em '
      'diálogo — na mão de quem lançou', (tester) async {
    final turmas = TurmasFalso.fixture()..veredito = 'SUGERIR_CONTINUO';
    await montar(tester, bloco: 'b-vazio', repositorio: turmas);

    // A alocação não tem Veio/Faltou: só a reposição PONTUAL do dia.
    expect(find.text('Veio'), findsOneWidget);
    expect(find.text('Faltou'), findsOneWidget);

    await tester.tap(find.text('Faltou'));
    await carregar(tester);

    expect(turmas.presencas, ['rep-al-lucas|FALTOU']);
    expect(find.text('Falta registrada'), findsOneWidget);
    expect(find.text(vereditosRep['SUGERIR_CONTINUO']!), findsOneWidget);
  });

  testWidgets('veredito MANTER também é dito — sem ele, silêncio', (
    tester,
  ) async {
    final turmas = TurmasFalso.fixture()..veredito = 'MANTER';
    await montar(tester, bloco: 'b-vazio', repositorio: turmas);
    await tester.tap(find.text('Veio'));
    await carregar(tester);
    expect(find.text('Presença registrada'), findsOneWidget);
    expect(find.text(avisoVereditoManter), findsOneWidget);
  });

  testWidgets('REPOSICAO_NAO_PREVISTA vira banner, e não exceção crua', (
    tester,
  ) async {
    final turmas = TurmasFalso.fixture()
      ..erroAoRegistrar = const ErroApp(
        codigo: 'REPOSICAO_NAO_PREVISTA',
        mensagem:
            'Esta reposição já não está prevista — alguém a registrou ou '
            'cancelou.',
        traduzido: true,
      );
    await montar(tester, bloco: 'b-vazio', repositorio: turmas);
    await tester.tap(find.text('Veio'));
    await carregar(tester);

    expect(
      find.text(
        'Esta reposição já não está prevista — alguém a registrou ou '
        'cancelou.',
      ),
      findsOneWidget,
    );
    // E nenhum diálogo de veredito: não houve veredito.
    expect(find.text('Presença registrada'), findsNothing);
  });

  testWidgets('sem turmas.alocar não há Veio nem Faltou', (tester) async {
    await montar(tester, bloco: 'b-vazio', permissoes: leitura);
    expect(find.text('Veio'), findsNothing);
    expect(find.text('Faltou'), findsNothing);
  });

  testWidgets('o banner de acima da capacidade sai quando o 11º é removido — '
      'ele descreve a LISTA, não a célula de quando o painel abriu', (
    tester,
  ) async {
    final turmas = await montar(tester, bloco: 'b-acima');
    expect(find.text(avisoAcimaCapacidade), findsOneWidget);

    await tester.tap(find.text('Remover').first);
    await carregar(tester);
    await tester.tap(find.byKey(chaveBotaoSalvar));
    await carregar(tester);

    expect(turmas.removidos, hasLength(1));
    expect(
      find.text(avisoAcimaCapacidade),
      findsNothing,
      reason: 'dez em dez não é acima da capacidade',
    );
  });

  testWidgets('o estado vazio do bloco oferece a ação do §7.2', (tester) async {
    final turmas = TurmasFalso(
      celulas: (await TurmasFalso.fixture().grade(DateTime(2026, 9, 7))),
      alunos: const {},
    );
    await montar(tester, repositorio: turmas);
    expect(find.text(vazioBloco), findsOneWidget);
    expect(find.text('+ Adicionar aluno'), findsOneWidget);

    // Sem `turmas.alocar` o estado vazio continua dizendo por que está vazio,
    // mas não oferece o que a RLS recusaria.
    await montar(tester, repositorio: turmas, permissoes: leitura);
    expect(find.text(vazioBloco), findsOneWidget);
    expect(find.text('+ Adicionar aluno'), findsNothing);
  });

  testWidgets('a lista que falha mostra "Tentar de novo" — o quarto estado', (
    tester,
  ) async {
    await montar(
      tester,
      erroDepoisDeAbrir: const ErroApp(
        mensagem:
            'Não foi possível falar com o servidor. Verifique a conexão e '
            'tente de novo.',
        traduzido: true,
      ),
    );
    expect(find.text('Tentar de novo'), findsOneWidget);
    expect(find.text(vazioBloco), findsNothing);
  });

  testWidgets('o cabeçalho traz o NOME do método, não o código do banco', (
    tester,
  ) async {
    await montar(tester);
    expect(find.textContaining('Interativo'), findsWidgets);
    expect(find.textContaining('INTERATIVO'), findsNothing);
  });
}
