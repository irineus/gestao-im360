import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/catalogo/catalogo_provider.dart';
import 'package:gestao_im360/infraestrutura/infraestrutura_provider.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/turmas/grade_semanal.dart';
import 'package:gestao_im360/telas/turmas/tela_turmas.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/turmas/turmas.dart';
import 'package:gestao_im360/turmas/turmas_provider.dart';
import 'package:gestao_im360/widgets/formulario.dart';

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
    String? blocoId,
  }) async {
    final turmas = repositorio ?? TurmasFalso.fixture();
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: semRetryAutomatico,
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
          home: Scaffold(body: TelaTurmas(blocoId: blocoId)),
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
      retry: semRetryAutomatico,
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

  testWidgets('no mobile a grade vira um dia por vez, e abre no dia de hoje', (
    tester,
  ) async {
    await montar(tester, tamanho: const Size(599, 900));
    // As abas trazem o dia e a data; a matriz de seis colunas não existe aqui.
    expect(find.textContaining('Ter '), findsOneWidget);

    // A aba inicial é a de HOJE, e não sempre segunda (design-system §6): a
    // grade de segunda é a resposta errada para quem abre o app na quinta.
    const ocupacaoDoDia = {1: '0/10', 2: '9/10', 3: '10/10', 4: '11/10'};
    final hoje = hojeSaoPaulo().weekday;
    for (final entrada in ocupacaoDoDia.entries) {
      expect(
        find.text(entrada.value),
        entrada.key == hoje ? findsOneWidget : findsNothing,
        reason: 'só o dia de hoje está à vista',
      );
    }

    // A barra de abas rola sozinha até hoje, então a aba de terça pode estar
    // fora da vista — sem isto o toque cai no vazio e o teste "passa" testando
    // nada.
    await tester.ensureVisible(find.textContaining('Ter '));
    await carregar(tester);
    await tester.tap(find.textContaining('Ter '));
    await carregar(tester);
    expect(find.text('9/10'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Card 5.11 — o quarto estado, a célula vazia e o atalho da pendência
  // -------------------------------------------------------------------------

  testWidgets('a grade que falha mostra "Tentar de novo", e não uma semana '
      'vazia', (tester) async {
    await montar(tester, repositorio: TurmasFalso.queFalha());
    expect(find.text('Tentar de novo'), findsOneWidget);
    expect(
      find.text(vazioTurmas),
      findsNothing,
      reason:
          'sem isto, falha de rede seria indistinguível de escola sem '
          'bloco nenhum',
    );
  });

  testWidgets('vazio COM filtro ligado oferece "Limpar filtros", e não '
      '"nenhum bloco cadastrado"', (tester) async {
    // Um método que não existe na grade: a lista filtrada fica vazia, mas há
    // blocos cadastrados — antes a tela dizia que não havia nenhum, e não
    // oferecia a saída.
    final container = ProviderContainer(
      retry: semRetryAutomatico,
      overrides: [
        turmasRepositorioProvider.overrideWithValue(TurmasFalso.fixture()),
        catalogoRepositorioProvider.overrideWithValue(CatalogoFalso.fixture()),
        infraestruturaRepositorioProvider.overrideWithValue(
          InfraestruturaFalso.fixture(),
        ),
        permissoesProvider.overrideWithValue(secretaria),
        unidadeAtualProvider.overrideWithValue('unidade-teste'),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(filtroGradeProvider.notifier)
        .definir(const FiltroGrade(metodoId: 'm-inexistente'));

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
    expect(find.text(vazioTurmas), findsNothing);
  });

  testWidgets('célula vazia abre o formulário de bloco já com o dia e a hora '
      'daquele cruzamento', (tester) async {
    await montar(tester, permissoes: secretaria);
    // O `+` da célula vazia, e não o do botão "Novo bloco" do cabeçalho: o
    // último cruzamento sem bloco é sábado às 09:30.
    final vazias = find.descendant(
      of: find.byType(GradeSemanal),
      matching: find.byIcon(Icons.add),
    );
    expect(vazias, findsWidgets);
    await tester.tap(vazias.last);
    await carregar(tester);

    // O dia e o horário chegam pré-preenchidos: sem isso a pessoa aponta um
    // cruzamento e digita de novo o que já apontou.
    expect(find.text('09:30'), findsWidgets);
    expect(find.text('Sábado'), findsWidgets);
  });

  testWidgets('salvar e excluir o bloco chegam ao repositório', (tester) async {
    final turmas = await montar(tester, permissoes: secretaria);
    // Pelo "Editar bloco" de dentro do painel, que é onde o cadastro mora
    // (§7.2): os campos vêm preenchidos, e é o caminho real.
    await tester.tap(find.text('9/10'));
    await carregar(tester);
    await tester.tap(find.text('Editar bloco'));
    await carregar(tester);
    await tester.tap(find.byKey(chaveBotaoSalvar));
    await carregar(tester);

    expect(
      turmas.salvos,
      hasLength(1),
      reason: 'o falso registrava os salvos e nenhum teste os assertava',
    );
    expect(find.text('Bloco salvo.'), findsOneWidget);

    await tester.tap(find.text('9/10'));
    await carregar(tester);
    await tester.tap(find.text('Editar bloco'));
    await carregar(tester);
    await tester.tap(find.text('Excluir'));
    await carregar(tester);
    // Consequência dita e o botão nomeando a ação, nunca "OK" (§5.8).
    expect(find.text('Excluir bloco?'), findsOneWidget);
    await tester.tap(find.text('Excluir').last);
    await carregar(tester);

    expect(turmas.excluidos, ['b-quase']);
    expect(find.text('Bloco excluído.'), findsOneWidget);
  });

  testWidgets('os blocos inativos são alcançáveis e reativáveis — desativar '
      'não é porta de mão única', (tester) async {
    final turmas = await montar(tester, permissoes: secretaria);
    expect(find.text('Inativos (1)'), findsOneWidget);
    await tester.tap(find.text('Inativos (1)'));
    await carregar(tester);
    expect(find.textContaining('Sexta'), findsWidgets);

    // O bloco inativo se reabre e se reativa pelo interruptor "Ativo".
    await tester.tap(find.text('Abrir'));
    await carregar(tester);
    await tester.tap(find.byType(SwitchListTile));
    await carregar(tester);
    await tester.tap(find.byKey(chaveBotaoSalvar));
    await carregar(tester);

    expect(turmas.salvos.single.id, 'b-inativo');
    expect(turmas.salvos.single.ativo, isTrue);
  });

  testWidgets('o atalho da pendência abre o painel DAQUELE bloco', (
    tester,
  ) async {
    // É o `?bloco=<id>` do wireframe §14.3: sem ele "Ver turma" abria a grade
    // inteira e a pessoa procurava de novo o que a lista já sabia.
    await montar(tester, blocoId: 'b-cheio');
    expect(find.text('Ana Paula Ribeiro'), findsOneWidget);
    expect(find.textContaining('Ocupação 3/10'), findsOneWidget);
  });

  testWidgets('sem o parâmetro nenhum painel abre sozinho', (tester) async {
    await montar(tester);
    expect(find.text('Ana Paula Ribeiro'), findsNothing);
  });
}
