import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/dashboard/dashboard.dart';
import 'package:gestao_im360/dashboard/dashboard_provider.dart';
import 'package:gestao_im360/pendencias/pendencias.dart';
import 'package:gestao_im360/pendencias/pendencias_provider.dart';
import 'package:gestao_im360/pendencias/pendencias_repositorio.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/dashboard/grade_vagas.dart';
import 'package:gestao_im360/telas/dashboard/lotacao_modular.dart';
import 'package:gestao_im360/telas/dashboard/pendencias_abertas.dart';
import 'package:gestao_im360/telas/dashboard/tela_dashboard.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/turmas/modular_provider.dart';
import 'package:gestao_im360/turmas/turmas_provider.dart';

import 'apoio/app_de_teste.dart';
import 'apoio/carregar.dart';
import 'apoio/dashboard_falso.dart';
import 'apoio/modular_falso.dart';
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
    ModularFalso? modular,
    Set<String> permissoes = comTurmas,
    Size tamanho = const Size(1400, 900),
  }) async {
    final dashboard = repositorio ?? DashboardFalso();
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: semRetryAutomatico,
        overrides: [
          dashboardRepositorioProvider.overrideWithValue(dashboard),
          pendenciasRepositorioProvider.overrideWithValue(
            pendencias ?? PendenciasFalso.fixture(),
          ),
          // A lotação Modular (card 7.4) lê a MESMA `v_turma_modular_lotacao`
          // da tela 5, pelo repositório dela — não há um segundo repositório.
          modularRepositorioProvider.overrideWithValue(
            modular ?? ModularFalso.fixture(),
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
    expect(
      find.text('30 de 40 ocupados · 4 blocos de horário'),
      findsOneWidget,
    );
    expect(find.text('1 acima da capacidade'), findsOneWidget);
    expect(find.text('4 de 6 ocupados · 1 bloco de horário'), findsOneWidget);
  });

  testWidgets('tocar o cartão do outro método troca a grade', (tester) async {
    await montar(tester);
    expect(find.text('1/10'), findsOneWidget);

    await tester.tap(find.text('4 de 6 ocupados · 1 bloco de horário'));
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
    // Restrito à região: o cartão de Depilação, ao lado, também mostra um zero
    // (nenhuma vaga livre), e contar zeros da tela inteira mediria outra coisa.
    expect(
      find.descendant(
        of: find.byType(PendenciasAbertas),
        matching: find.text('0'),
      ),
      findsNWidgets(3),
    );
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

  // A forma do mobile passou a ser a MESMA da tela de Turmas — abas Seg–Sáb,
  // abrindo no dia de hoje (decisão de Irineu, 04/09/2026). Antes era lista
  // vertical por dia aqui e abas lá, com as duas specs se contradizendo.
  testWidgets('no celular a grade vira abas por dia, abrindo em hoje', (
    tester,
  ) async {
    await montar(tester, tamanho: const Size(599, 900));

    // Uma aba por dia, com o dia curto e a data.
    expect(find.textContaining('Seg '), findsOneWidget);
    expect(find.textContaining('Sáb '), findsOneWidget);

    // O conteúdo à vista é o de HOJE, e só o dele: numa matriz os quatro
    // apareceriam juntos.
    const vagasDoDia = {1: '10/10', 2: '1/10'};
    final hoje = hojeSaoPaulo().weekday;
    for (final entrada in vagasDoDia.entries) {
      expect(
        find.text(entrada.value),
        entrada.key == hoje ? findsOneWidget : findsNothing,
        reason: 'só o dia de hoje está à vista',
      );
    }

    // Trocar de aba mostra o outro dia.
    // A barra de abas rola sozinha até hoje, então a aba de terça pode estar
    // fora da vista — sem isto o toque cai no vazio e o teste "passa" testando
    // nada.
    await tester.ensureVisible(find.textContaining('Ter '));
    await carregar(tester);
    await tester.tap(find.textContaining('Ter '));
    await carregar(tester);
    expect(find.text('1/10'), findsOneWidget);
  });

  testWidgets('a célula é atalho e leva à MESMA semana e ao MESMO método', (
    tester,
  ) async {
    final container = ProviderContainer(
      retry: semRetryAutomatico,
      overrides: [
        dashboardRepositorioProvider.overrideWithValue(DashboardFalso()),
        modularRepositorioProvider.overrideWithValue(ModularFalso.fixture()),
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
    // A semana é a que o BANCO devolveu (`data_referencia`), e não a do
    // relógio do aparelho.
    expect(container.read(semanaProvider), segundaDe(hojeSaoPaulo()));
  });

  // -------------------------------------------------------------------------
  // Card 5.11 — a região que falha não leva a tela junto
  // -------------------------------------------------------------------------

  testWidgets('vagas falhando: a tela CONTINUA com as pendências e o erro fica '
      'na região', (tester) async {
    await montar(tester, repositorio: DashboardFalso.queFalha());

    // A regra do design-system §7.2 para o dashboard é "região nunca some", e
    // ela vale também quando a região FALHA: as pendências e o rodapé não
    // dependem da consulta de vagas.
    expect(find.text('Pendências abertas'), findsOneWidget);
    expect(find.text(textoRestanteDoDashboard), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);

    // E nada de contagem inventada: "0 blocos ativos" seria número errado com
    // cara de certo.
    expect(find.textContaining('blocos de horário ativos'), findsNothing);
  });

  testWidgets('o EstadoErro é ESTÁVEL — não pisca entre erro e esqueleto', (
    tester,
  ) async {
    // ⚠️ É o teste da política de `retry` do projeto: com a repetição
    // automática do Riverpod 3 ligada, o estado voltaria a `AsyncLoading` e a
    // tela terminaria em "Carregando…" para sempre (medido no card 5.9).
    await montar(tester, repositorio: DashboardFalso.queFalha());
    expect(find.text('Tentar de novo'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 30));
    expect(
      find.text('Tentar de novo'),
      findsOneWidget,
      reason: 'o erro continua em tela; nada o substituiu por um esqueleto',
    );
  });

  testWidgets('cada severidade das pendências é atalho para a central JÁ '
      'filtrada', (tester) async {
    final container = ProviderContainer(
      retry: semRetryAutomatico,
      overrides: [
        dashboardRepositorioProvider.overrideWithValue(DashboardFalso()),
        pendenciasRepositorioProvider.overrideWithValue(
          PendenciasFalso.fixture(),
        ),
        modularRepositorioProvider.overrideWithValue(ModularFalso.fixture()),
        permissoesProvider.overrideWithValue(comTurmas),
        unidadeAtualProvider.overrideWithValue('unidade-teste'),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1400, 900);
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

    // O número é botão: tocá-lo abre a central filtrada por aquela severidade
    // (wireframes §5 e §3.3). Antes ele dizia quantas são e mandava
    // procurá-las de novo.
    await tester.tap(find.text('ALTA'));
    await carregar(tester);
    expect(container.read(filtroPendenciasProvider).severidade, 'ALTA');
  });

  testWidgets('a célula anuncia dia, hora e o que o número significa', (
    tester,
  ) async {
    final semantica = tester.ensureSemantics();
    await montar(tester);

    // Sem a coordenada, o leitor de tela anuncia "1 vaga livre de 10" sem
    // dizer QUANDO — e quem lê assim não tem a coluna nem a linha à vista.
    expect(
      find.bySemanticsLabel(RegExp('^Terça 08:00, 1 vaga livre de 10')),
      findsOneWidget,
    );
    // A célula VAZIA também é anunciada: antes ficava fora do `Semantics`.
    expect(find.bySemanticsLabel(RegExp('sem turma')), findsWidgets);
    semantica.dispose();
  });

  // -------------------------------------------------------------------------
  // Card 7.4 — a lotação Modular por curso
  // -------------------------------------------------------------------------

  testWidgets('a lotação Modular soma as turmas por CURSO', (tester) async {
    await montar(tester);

    expect(find.text(tituloLotacaoModular), findsOneWidget);
    expect(find.text('Eletricista Instalador'), findsOneWidget);
    expect(find.text('Depilação'), findsOneWidget);

    // Eletricista tem TRÊS turmas de 15 com uma aluna só; Depilação, uma de 15
    // com dezesseis.
    expect(find.text('1 de 45 ocupados · 3 turmas'), findsOneWidget);
    expect(find.text('16 de 15 ocupados · 1 turma'), findsOneWidget);

    // A ocupação sai por extenso, e não como `1/45`: a grade acima diz `n/m`
    // com n sendo VAGA — a leitura oposta, na mesma tela.
    expect(find.text('1/45'), findsNothing);
    expect(find.text('16/15'), findsNothing);
  });

  testWidgets('turma acima da capacidade e módulo atrasado são DITOS', (
    tester,
  ) async {
    await montar(tester);

    // Vermelho é dado inconsistente (16 numa turma de 15); âmbar é previsão
    // vencida, com a turma funcionando. Nenhum dos dois é só cor: cada um tem
    // ícone e texto (design-system §8.2).
    expect(find.text('1 turma acima da capacidade'), findsOneWidget);
    expect(find.text('1 turma com módulo atrasado'), findsOneWidget);
    expect(
      find.text('1 acima da capacidade'),
      findsOneWidget,
      reason: 'esse é o cartão do MÉTODO, que conta blocos de horário',
    );
  });

  testWidgets('a vaga do curso é a SOMA, e nunca capacidade − alocados', (
    tester,
  ) async {
    await montar(tester);

    // 15 − 16 daria −1. A view tem piso zero (card 7.3), e a região soma as
    // parcelas: o curso lotado mostra 0, não um número negativo.
    expect(
      find.descendant(
        of: find.byType(LotacaoModular),
        matching: find.text('-1'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(LotacaoModular),
        matching: find.text('44'),
      ),
      findsOneWidget,
      reason: 'Eletricista: 14 + 15 + 15',
    );
  });

  testWidgets('falha ao ler a lotação NÃO vira zero', (tester) async {
    // Mesma razão das pendências: uma região do dashboard é número reportado, e
    // "0 ocupados" por falha de rede faz a direção ler "as turmas estão vazias".
    await montar(tester, modular: ModularFalso.queFalha());

    expect(find.text(erroLotacaoModular), findsOneWidget);
    expect(find.text('Eletricista Instalador'), findsNothing);
    // E a região vizinha continua inteira.
    expect(find.text('Pendências abertas'), findsOneWidget);
  });

  testWidgets('sem turma Modular a região DIZ por que não há número', (
    tester,
  ) async {
    await montar(tester, modular: ModularFalso());

    expect(find.text(vazioLotacaoModular), findsOneWidget);
    expect(
      find.text(tituloLotacaoModular),
      findsOneWidget,
      reason: 'a região não some: espaço em branco no dashboard parece defeito',
    );
  });

  testWidgets('o cartão é atalho e leva à tela 5 FILTRADA pelo curso', (
    tester,
  ) async {
    final container = ProviderContainer(
      retry: semRetryAutomatico,
      overrides: [
        dashboardRepositorioProvider.overrideWithValue(DashboardFalso()),
        pendenciasRepositorioProvider.overrideWithValue(
          PendenciasFalso.fixture(),
        ),
        modularRepositorioProvider.overrideWithValue(ModularFalso.fixture()),
        permissoesProvider.overrideWithValue(comTurmas),
        unidadeAtualProvider.overrideWithValue('unidade-teste'),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1400, 900);
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

    // O cartão é de um CURSO, então o destino é a tela 5 filtrada por ele — e
    // não uma turma eleita em silêncio entre as três (divergência com o §5,
    // registrada em wireframes §17).
    await tester.tap(find.text('1 de 45 ocupados · 3 turmas'));
    await carregar(tester);
    expect(container.read(filtroTurmasModularProvider).cursoId, 'c-ele');
  });

  testWidgets('o cartão do curso anuncia o que cada número significa', (
    tester,
  ) async {
    final semantica = tester.ensureSemantics();
    await montar(tester);

    // Sem isto a leitura de tela anuncia "Depilação 0 16 de 15 ocupados" em
    // sequência, sem separar o que é o quê.
    expect(
      find.bySemanticsLabel(
        'Depilação, 0 vagas livres, 16 de 15 ocupados, 1 turma, '
        '1 turma acima da capacidade',
      ),
      findsOneWidget,
    );
    semantica.dispose();
  });

  testWidgets('o rodapé conta BLOCOS DE HORÁRIO — o mesmo nome do cartão', (
    tester,
  ) async {
    await montar(tester);
    expect(
      find.textContaining('blocos de horário ativos nesta semana.'),
      findsOneWidget,
      reason:
          'o cartão dizia "4 turmas" e o rodapé "4 blocos ativos" — o '
          'mesmo objeto com dois nomes na mesma tela',
    );
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
