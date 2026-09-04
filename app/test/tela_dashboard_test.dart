import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/dashboard/dashboard.dart';
import 'package:gestao_im360/dashboard/dashboard_provider.dart';
import 'package:gestao_im360/pendencias/pendencias.dart';
import 'package:gestao_im360/pendencias/pendencias_provider.dart';
import 'package:gestao_im360/pendencias/pendencias_repositorio.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/dashboard/grade_vagas.dart';
import 'package:gestao_im360/telas/dashboard/pendencias_abertas.dart';
import 'package:gestao_im360/telas/dashboard/tela_dashboard.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/turmas/turmas_provider.dart';

import 'apoio/app_de_teste.dart';
import 'apoio/carregar.dart';
import 'apoio/dashboard_falso.dart';
import 'apoio/pendencias_falso.dart';

/// A obrigação de teste de um card de **Tela** (card 2.8 §13): ocultação por
/// permissão e estado vazio com o texto do card 2.7 — a guarda de rota já está
/// tabelada em `guardas_rota_test.dart`. Mais o que esta tela tem de próprio, e
/// que é onde ela erraria sem dar erro:
///
///   • a célula mostra **vagas/capacidade**, e a da tela de Turmas mostra
///     alocados/capacidade — as duas saem da mesma view, então uma troca de
///     leitura produziria uma grade inteira plausível e invertida;
///   • a grade é de **um método**: no cruzamento em que Interativo e Inglês
///     dividem o horário, somar os dois daria uma vaga que ninguém pode usar.
void main() {
  // O conjunto mínimo da rota `dashboard` (docs/permissoes-matriz.md §6).
  // ⚠️ Sem `professores.ler`, que é da rota de Turmas: é o que faz o atalho
  // para lá existir ou não.
  const leitura = {
    'alunos.ler',
    'materiais.ler',
    'turmas.ler',
    'salas.ler',
    'pendencias.ler',
  };
  const comTurmas = {...leitura, 'professores.ler'};

  Future<DashboardFalso> montar(
    WidgetTester tester, {
    DashboardFalso? repositorio,
    PendenciasRepositorio? pendencias,
    Set<String> permissoes = comTurmas,
    Size tamanho = const Size(1400, 900),
  }) async {
    final dashboard = repositorio ?? DashboardFalso();
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardRepositorioProvider.overrideWithValue(dashboard),
          pendenciasRepositorioProvider.overrideWithValue(
            pendencias ?? PendenciasFalso.fixture(),
          ),
          permissoesProvider.overrideWithValue(permissoes),
          unidadeAtualProvider.overrideWithValue('unidade-teste'),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          home: const Scaffold(body: TelaDashboard()),
        ),
      ),
    );
    await carregar(tester);
    return dashboard;
  }

  testWidgets('a célula mostra VAGAS/capacidade, não alocados/capacidade', (
    tester,
  ) async {
    await montar(tester);

    // Terça tem 9 alocados em 10 lugares: aqui isso é "1/10", e na grade de
    // Turmas (card 5.6) o mesmo bloco aparece como "9/10".
    expect(find.text('1/10'), findsOneWidget);
    expect(
      find.text('9/10'),
      findsNothing,
      reason: 'seria a leitura da tela de Turmas — grade inteira invertida',
    );
    // Segunda está vazio: dez vagas de dez.
    expect(find.text('10/10'), findsOneWidget);
    // Quarta (lotado) e quinta (acima da capacidade) não têm vaga nenhuma.
    expect(find.text('0/10'), findsNWidgets(2));
    expect(find.text(rotuloLegendaVagas), findsOneWidget);
  });

  testWidgets('a grade nunca soma métodos no mesmo cruzamento', (tester) async {
    await montar(tester);

    // Quarta 08:00 tem Interativo (0 de 10) e Inglês (2 de 6) em salas
    // diferentes. Somados dariam "2/16" — uma vaga de Inglês oferecida a um
    // aluno de Interativo, que o trigger de admissão recusaria com
    // METODO_INCOMPATIVEL (card 5.3).
    expect(find.text('2/16'), findsNothing);
    expect(find.text(textoUmMetodoPorVez), findsOneWidget);
    expect(find.text('Vagas por dia e horário — INTERATIVO'), findsOneWidget);
  });

  testWidgets('os cartões somam por método e abrem no maior', (tester) async {
    await montar(tester);

    expect(find.text('INTERATIVO'), findsOneWidget);
    expect(find.text('INGLES'), findsOneWidget);
    // Interativo: 4 turmas, 30 alocados em 40 lugares, 11 vagas livres — e
    // 40 − 30 = 10, que é o número errado (card 5.2 não devolve vaga negativa).
    expect(find.text('30/40 ocupados · 4 turmas'), findsOneWidget);
    expect(find.text('1 acima da capacidade'), findsOneWidget);
    expect(find.text('4/6 ocupados · 1 turma'), findsOneWidget);
  });

  testWidgets('tocar o cartão do outro método troca a grade', (tester) async {
    await montar(tester);
    expect(find.text('1/10'), findsOneWidget);

    await tester.tap(find.text('4/6 ocupados · 1 turma'));
    await carregar(tester);

    expect(find.text('Vagas por dia e horário — INGLES'), findsOneWidget);
    expect(find.text('2/6'), findsOneWidget);
    expect(
      find.text('1/10'),
      findsNothing,
      reason: 'a grade passou a ser a do outro método',
    );
  });

  testWidgets('a semana rotulada é a que o BANCO devolveu', (tester) async {
    // Uma semana que não é a do relógio do teste: com `DateTime.now()` no lugar
    // de `data_referencia`, o rótulo diria a semana de hoje sobre a grade de
    // outra — certo em número, errado em data, e sem nada em tela dizendo.
    await montar(
      tester,
      repositorio: DashboardFalso(
        celulas: [
          vagaFalsa(
            blocoId: 'b1',
            dia: 3,
            dataReferencia: DateTime(2026, 1, 7),
            ocupacao: 4,
          ),
        ],
      ),
    );
    expect(find.text('05/01 a 10/01 · semana corrente'), findsOneWidget);
  });

  testWidgets('sem bloco nenhum a tela DIZ por que não há número', (
    tester,
  ) async {
    await montar(tester, repositorio: DashboardFalso.vazio());
    expect(find.text(vazioDashboard), findsOneWidget);
    expect(find.text('Ir para Turmas'), findsOneWidget);
  });

  testWidgets('sem professores.ler o atalho para Turmas não é oferecido', (
    tester,
  ) async {
    // A rota de Turmas exige `professores.ler` e a do dashboard não: um atalho
    // que leva a "Sem acesso" ensina a não clicar nos outros (card 5.8, dec. 1).
    await montar(
      tester,
      repositorio: DashboardFalso.vazio(),
      permissoes: leitura,
    );
    expect(find.text(vazioDashboard), findsOneWidget);
    expect(find.text('Ir para Turmas'), findsNothing);
  });

  testWidgets('a tela diz qual card entrega o resto do dashboard', (
    tester,
  ) async {
    await montar(tester);
    expect(find.text(textoRestanteDoDashboard), findsOneWidget);
  });

  testWidgets('as pendências abertas saem por severidade, com o zero real', (
    tester,
  ) async {
    // A fixture tem 3 ALTA, 2 MÉDIA e 1 BAIXA. A contagem vem do que o shell já
    // carregou (card 5.8) — nenhuma segunda consulta.
    await montar(tester);
    expect(find.text('Pendências abertas'), findsOneWidget);
    expect(find.text('ALTA'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('MÉDIA'), findsOneWidget);
    expect(find.text('BAIXA'), findsOneWidget);

    // Severidade sem pendência nenhuma continua na lista com zero, e não some:
    // no dashboard, número que desaparece parece erro (design-system §7.2).
    await montar(tester, pendencias: PendenciasFalso(pendencias: const []));
    expect(find.text('BAIXA'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(3));
  });

  testWidgets('falha ao ler pendências NÃO vira zero', (tester) async {
    // O contador do menu mostra zero no erro, de propósito (card 5.8) — é um
    // aviso de canto de tela. Uma região do dashboard é um número reportado:
    // "0 ALTA" por falha de rede faria a direção ler "está tudo em ordem".
    await montar(tester, pendencias: _PendenciasQueFalham());
    expect(find.text(erroPendenciasDashboard), findsOneWidget);
    expect(find.text('ALTA'), findsNothing);
  });

  testWidgets('a região de vagas vazia não leva a de pendências junto', (
    tester,
  ) async {
    await montar(tester, repositorio: DashboardFalso.vazio());
    expect(find.text(vazioDashboard), findsOneWidget);
    expect(find.text('Pendências abertas'), findsOneWidget);
    expect(
      find.text('3'),
      findsOneWidget,
      reason: 'as três ALTA continuam ali',
    );
  });

  testWidgets('no celular a grade vira lista por dia, sem coluna vazia', (
    tester,
  ) async {
    await montar(tester, tamanho: const Size(420, 900));

    expect(find.text('Segunda ${_hoje(1)}'), findsOneWidget);
    expect(find.text('1/10'), findsOneWidget);
    // Sexta e sábado não têm bloco de Interativo: na matriz a coluna fica (a
    // forma fixa é o que deixa comparar os dias), na lista a seção não nasce.
    expect(find.text('Sexta ${_hoje(5)}'), findsNothing);
  });

  testWidgets('a célula é atalho e leva à MESMA semana e ao MESMO método', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        dashboardRepositorioProvider.overrideWithValue(DashboardFalso()),
        permissoesProvider.overrideWithValue(comTurmas),
        unidadeAtualProvider.overrideWithValue('unidade-teste'),
      ],
    );
    addTearDown(container.dispose);

    // Alguém deixou a grade de Turmas três semanas à frente — o estado dela
    // sobrevive à navegação (card 5.6), e sem o acerto a pessoa procuraria lá
    // a célula que clicou aqui.
    container.read(semanaProvider.notifier).mover(3);

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: appDeTeste(
          // O `Scaffold` faz aqui o papel que o `ShellIm360` faz no app: as
          // células são `InkWell`, e sem `Material` acima elas não constroem.
          construtor: (filho) => Scaffold(body: filho),
          conteudo: const TelaDashboard(),
        ),
      ),
    );
    await carregar(tester);

    await tester.tap(find.text('1/10'));
    await carregar(tester);

    expect(container.read(filtroGradeProvider).metodoId, 'm-int');
    expect(container.read(semanaProvider), segundaDe(DateTime.now()));
  });
}

/// Leitura de pendências que falha — o único jeito de exercitar a diferença
/// entre "zero" e "não deu para saber".
class _PendenciasQueFalham implements PendenciasRepositorio {
  @override
  Future<List<Pendencia>> abertas() async => throw Exception('sem rede');

  @override
  Future<void> resolver(
    String pendenciaId, {
    required String resolucao,
    String? justificativa,
  }) async => throw UnimplementedError();
}

/// A data que a coluna do dia mostra nesta semana — a fixture do dashboard usa
/// a semana corrente, como a view faz no banco.
String _hoje(int diaSemana) {
  final segunda = segundaDe(DateTime.now());
  return formatarDataCurta(
    DateTime(segunda.year, segunda.month, segunda.day + (diaSemana - 1)),
  );
}
