import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/catalogo/catalogo_provider.dart';
import 'package:gestao_im360/infraestrutura/infraestrutura_provider.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/turmas/tela_turmas.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/turmas/turmas.dart';
import 'package:gestao_im360/turmas/turmas_provider.dart';

import 'apoio/carregar.dart';
import 'apoio/catalogo_falso.dart';
import 'apoio/infraestrutura_falso.dart';
import 'apoio/turmas_falso.dart';

/// A obrigação de teste de um card de **Tela** (card 2.8 §13): ocultação por
/// permissão e estado vazio com o texto do card 2.7 — a guarda de rota já está
/// tabelada em `guardas_rota_test.dart`. Mais o que esta tela tem de próprio:
/// a navegação de semanas (que é a razão de a fonte ser a FUNÇÃO e não a view),
/// a célula com os dois alertas e a célula que carrega duas turmas.
void main() {
  // O conjunto mínimo da rota `turmas` (docs/permissoes-matriz.md §6) e as
  // ações de cima dele, na matriz inicial do card 2.4 §5.
  const leitura = {
    'turmas.ler',
    'salas.ler',
    'professores.ler',
    'materiais.ler',
  };
  const secretaria = {
    ...leitura,
    'turmas.criar',
    'turmas.editar',
    'turmas.excluir',
    'turmas.alocar',
  };

  Future<TurmasFalso> montar(
    WidgetTester tester, {
    TurmasFalso? repositorio,
    Set<String> permissoes = leitura,
    Size tamanho = const Size(1400, 900),
  }) async {
    final turmas = repositorio ?? TurmasFalso.fixture();
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          turmasRepositorioProvider.overrideWithValue(turmas),
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
          home: const Scaffold(body: TelaTurmas()),
        ),
      ),
    );
    await carregar(tester);
    return turmas;
  }

  testWidgets('a grade mostra ocupação/capacidade, sala e professor de cada '
      'bloco', (tester) async {
    await montar(tester);
    expect(find.text('9/10'), findsOneWidget, reason: 'bloco quase cheio');
    expect(find.text('10/10'), findsOneWidget, reason: 'bloco cheio');
    expect(find.text('4/6'), findsOneWidget, reason: 'bloco de Inglês');
    expect(find.text('Renata Alves'), findsOneWidget);
    // Seg a Sáb sempre, mesmo sem bloco em quinta, sexta e sábado.
    for (final dia in ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb']) {
      expect(find.text(dia), findsOneWidget, reason: dia);
    }
    expect(find.text('Dom'), findsNothing, reason: 'sem bloco no domingo');
  });

  testWidgets('bloco sem professor aparece com o traço, e não some da grade', (
    tester,
  ) async {
    await montar(tester);
    // O bloco de 10 alunos é o sem professor: com `join` interno em professor a
    // linha inteira sumiria do banco, e aqui ela some da tela.
    expect(find.text('10/10'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('as duas turmas do mesmo dia e horário aparecem as duas', (
    tester,
  ) async {
    await montar(tester);
    // Quarta 08:00 tem Laboratório 1 (Interativo) e Laboratório 2 (Inglês).
    expect(find.text('INGLES'), findsOneWidget);
    expect(find.text('Laboratório 2'), findsOneWidget);
    expect(find.text('4/6'), findsOneWidget);
  });

  testWidgets('a legenda diz o que cada ⚠ significa', (tester) async {
    await montar(tester);
    expect(find.text('acima da capacidade'), findsOneWidget);
    expect(find.text('sem professor'), findsOneWidget);
  });

  testWidgets('sem turmas.criar o botão "Novo bloco" não é renderizado', (
    tester,
  ) async {
    await montar(tester);
    expect(find.text('Novo bloco'), findsNothing);

    await montar(tester, permissoes: secretaria);
    expect(find.text('Novo bloco'), findsOneWidget);
  });

  testWidgets('a navegação pede ao banco a semana pedida, e "Hoje" volta', (
    tester,
  ) async {
    final repositorio = await montar(tester);
    final corrente = segundaDe(DateTime.now());
    expect(repositorio.ultimaSemana, corrente);

    await tester.tap(find.byTooltip('Próxima semana'));
    await carregar(tester);
    expect(
      repositorio.ultimaSemana,
      DateTime(corrente.year, corrente.month, corrente.day + 7),
      reason:
          'a grade de outra semana é outra consulta — a lotação é de uma data',
    );

    await tester.tap(find.byTooltip('Semana anterior'));
    await tester.tap(find.byTooltip('Semana anterior'));
    await carregar(tester);
    expect(
      repositorio.ultimaSemana,
      DateTime(corrente.year, corrente.month, corrente.day - 7),
    );

    await tester.tap(find.text('Hoje'));
    await carregar(tester);
    expect(repositorio.ultimaSemana, corrente);
    expect(find.text('Hoje'), findsNothing, reason: 'na semana corrente, some');
  });

  testWidgets('estado vazio com o texto do card 2.7 — e a ação só para quem '
      'pode criar', (tester) async {
    await montar(tester, repositorio: TurmasFalso());
    expect(find.text(vazioTurmas), findsOneWidget);
    expect(find.text('+ Novo bloco'), findsNothing);

    await montar(tester, repositorio: TurmasFalso(), permissoes: secretaria);
    expect(find.text('+ Novo bloco'), findsOneWidget);
  });

  testWidgets('filtrar até não sobrar nada dá o vazio DE FILTRO, com a saída', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        turmasRepositorioProvider.overrideWithValue(TurmasFalso.fixture()),
        catalogoRepositorioProvider.overrideWithValue(CatalogoFalso.fixture()),
        infraestruturaRepositorioProvider.overrideWithValue(
          InfraestruturaFalso.fixture(),
        ),
        permissoesProvider.overrideWithValue(leitura),
        unidadeAtualProvider.overrideWithValue('unidade-teste'),
      ],
    );
    addTearDown(container.dispose);
    // Método que existe no catálogo e não tem bloco nenhum: o vazio tem de
    // dizer "com esses filtros", não "nenhum bloco cadastrado".
    container
        .read(filtroGradeProvider.notifier)
        .definir(const FiltroGrade(metodoId: 'm-mod'));

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: temaClaro(),
          home: const Scaffold(body: TelaTurmas()),
        ),
      ),
    );
    await carregar(tester);

    expect(find.text(vazioTurmasFiltro), findsOneWidget);
    expect(find.text('Limpar filtros'), findsOneWidget);

    await tester.tap(find.text('Limpar filtros'));
    await carregar(tester);
    expect(find.text('9/10'), findsOneWidget);
  });

  testWidgets('"Inativos" só aparece quando há bloco inativo, e só para quem '
      'edita', (tester) async {
    await montar(tester, permissoes: secretaria);
    expect(find.text('Inativos (1)'), findsOneWidget);

    // Sem turmas.editar o botão some — desativar e reabrir é edição.
    await montar(tester);
    expect(find.text('Inativos (1)'), findsNothing);

    await montar(
      tester,
      repositorio: TurmasFalso(celulas: [], blocos: const []),
      permissoes: secretaria,
    );
    expect(find.textContaining('Inativos'), findsNothing);
  });

  testWidgets('tocar a célula abre os alunos do bloco, e o cadastro fica no '
      '"Editar bloco" de dentro', (tester) async {
    await montar(tester, permissoes: secretaria);
    await tester.tap(find.text('9/10'));
    await carregar(tester);

    // O painel do card 5.7, e não o formulário do bloco: quem clica numa turma
    // quer ver quem está nela (wireframe §7.2).
    expect(find.textContaining('Ter 08:00'), findsWidgets);
    expect(find.text('Bloco de horário'), findsNothing);

    await tester.tap(find.text('Editar bloco'));
    await carregar(tester);
    expect(find.text('Bloco de horário'), findsOneWidget);
    // A capacidade derivada da sala fica ao lado do override, para a decisão
    // ser informada (wireframes §7.1).
    expect(find.textContaining('Capacidade derivada'), findsOneWidget);
  });

  testWidgets('no mobile a grade vira um dia por vez', (tester) async {
    await montar(tester, tamanho: const Size(420, 900));
    // As abas trazem o dia e a data; a matriz de seis colunas não existe aqui.
    expect(find.textContaining('Ter '), findsOneWidget);
    expect(
      find.text('9/10'),
      findsNothing,
      reason: 'terça não é a aba inicial',
    );
    await tester.tap(find.textContaining('Ter '));
    await carregar(tester);
    expect(find.text('9/10'), findsOneWidget);
  });
}
