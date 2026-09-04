import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/alunos/alunos_provider.dart';
import 'package:gestao_im360/erros/erro_app.dart';
import 'package:go_router/go_router.dart';
import 'package:gestao_im360/pendencias/pendencias.dart';
import 'package:gestao_im360/pendencias/pendencias_provider.dart';
import 'package:gestao_im360/rotas/rotas.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/pendencias/formularios.dart';
import 'package:gestao_im360/turmas/turmas_widgets.dart';
import 'package:gestao_im360/telas/pendencias/painel_pendencia.dart';
import 'package:gestao_im360/telas/pendencias/tela_pendencias.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/turmas/turmas.dart';
import 'package:gestao_im360/turmas/turmas_provider.dart';
import 'package:gestao_im360/widgets/formulario.dart';
import 'package:gestao_im360/widgets/shell_im360.dart';

import 'apoio/alunos_falso.dart';
import 'apoio/app_de_teste.dart';
import 'apoio/carregar.dart';
import 'apoio/pendencias_falso.dart';
import 'apoio/turmas_falso.dart';

/// A central de pendências (card 5.8, wireframe §14). A obrigação de teste de
/// um card de **Tela** (card 2.8 §13): ocultação por permissão e estado vazio
/// com o texto do card 2.7. Mais o que esta tela tem de próprio:
///
///   • **referência oculta pela RLS degrada para "—" e a linha CONTINUA** — o
///     modo de falha que o `left join` da view existe para impedir;
///   • **ignorar não promete silêncio permanente** (card 5.5 c);
///   • **`REP_VIRADA` é executada daqui**, com o seletor de bloco de um lado e a
///     volta a pontual do outro — as duas funções que o card 5.7 entregou sem
///     chamador;
///   • **marcar presença** numa reposição chama `fn_reposicao_registrar` e
///     mostra o veredito na hora;
///   • **o contador do menu conta só ALTA**.
void main() {
  const leitura = {'pendencias.ler', 'alunos.ler', 'materiais.ler'};
  const comTurmas = {...leitura, 'turmas.ler', 'salas.ler', 'professores.ler'};
  const secretaria = {...comTurmas, 'pendencias.resolver', 'turmas.alocar'};

  // As descrições da fixture. O painel se abre por elas, e não pelo rótulo do
  // tipo: `REP_VIRADA` aparece duas vezes, uma por sentido, e é justamente o par
  // que este arquivo precisa distinguir.
  const descSemTurma = 'Aluno ATIVO sem nenhuma turma.';
  const descCapacidade = '11 alunos para capacidade de 10.';
  const descRepContinuo = '3 aulas a repor; cabem 2 até 12/10.';
  const descRepVolta = 'Sem débito há 34 dias; pode voltar a pontual.';
  const descAcelerar = 'Aluno ACELERAR com um bloco só.';
  const descRotina = 'rt_rep_avaliar: division by zero';

  Future<(PendenciasFalso, TurmasFalso)> montar(
    WidgetTester tester, {
    PendenciasFalso? pendencias,
    TurmasFalso? turmas,
    Set<String> permissoes = secretaria,
    Size tamanho = const Size(1400, 900),
  }) async {
    final repoPendencias = pendencias ?? PendenciasFalso.fixture();
    final repoTurmas = turmas ?? TurmasFalso.fixture();
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: semRetryAutomatico,
        overrides: [
          pendenciasRepositorioProvider.overrideWithValue(repoPendencias),
          turmasRepositorioProvider.overrideWithValue(repoTurmas),
          alunosRepositorioProvider.overrideWithValue(AlunosFalso.fixture()),
          permissoesProvider.overrideWithValue(permissoes),
          unidadeAtualProvider.overrideWithValue('unidade-teste'),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          home: const Scaffold(body: TelaPendencias()),
        ),
      ),
    );
    await carregar(tester);
    return (repoPendencias, repoTurmas);
  }

  Future<void> abrir(WidgetTester tester, String descricao) async {
    await tester.tap(find.text(descricao));
    await carregar(tester);
  }

  /// Os três filtros da barra, na ordem do wireframe §14.1.
  Future<void> filtrar(
    WidgetTester tester, {
    required int indice,
    required String opcao,
  }) async {
    await tester.tap(find.byType(DropdownMenu<String>).at(indice));
    await carregar(tester);
    await tester.tap(find.text(opcao).last);
    await carregar(tester);
  }

  group('a lista', () {
    testWidgets('mostra severidade, tipo, descrição, referência e idade', (
      tester,
    ) async {
      await montar(tester);

      expect(find.text('ALTA'), findsWidgets);
      expect(find.text('Aluno sem turma'), findsOneWidget);
      expect(find.text(descCapacidade), findsOneWidget);
      expect(find.text('Eduarda Lima (3005)'), findsOneWidget);
      expect(find.text('Qui 09:30 · Laboratório 1'), findsOneWidget);
      expect(find.text('há 2 dias'), findsOneWidget);
      expect(find.text('hoje'), findsWidgets);
    });

    testWidgets('referência que a RLS ocultou vira "—" e a linha continua', (
      tester,
    ) async {
      await montar(tester);
      // A pendência do aluno oculto está na tela, com a descrição inteira…
      expect(find.text(descAcelerar), findsOneWidget);
      // …e o "—" no lugar do nome que este perfil não pode ler. Com `join`
      // interno na view, a linha inteira teria sumido e a central diria
      // "nenhuma pendência" (card 2.3 §9).
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('a fila abre por severidade: ALTA antes de MÉDIA e BAIXA', (
      tester,
    ) async {
      await montar(tester);
      final alta = tester.getTopLeft(find.text(descSemTurma)).dy;
      final media = tester.getTopLeft(find.text(descRepVolta)).dy;
      final baixa = tester.getTopLeft(find.text(descAcelerar)).dy;
      expect(alta, lessThan(media));
      expect(media, lessThan(baixa));
    });

    testWidgets('dentro da severidade, a mais antiga primeiro', (tester) async {
      await montar(tester);
      expect(
        tester.getTopLeft(find.text(descRepVolta)).dy,
        lessThan(tester.getTopLeft(find.text(descRepContinuo)).dy),
      );
    });

    testWidgets('central vazia é boa notícia, e o texto diz isso', (
      tester,
    ) async {
      // Sem esse texto, uma tela sem linhas seria indistinguível de uma rotina
      // que não rodou — a confusão que `ROTINA_FALHOU` existe para desfazer.
      await montar(tester, pendencias: PendenciasFalso(pendencias: const []));
      expect(find.text(vazioPendencias), findsOneWidget);
    });

    testWidgets('filtro que não casa oferece Limpar filtros', (tester) async {
      await montar(tester);
      await filtrar(tester, indice: 2, opcao: 'há 7 dias ou mais');
      expect(find.text(descAcelerar), findsOneWidget);
      expect(find.text(descSemTurma), findsNothing);

      // A única que sobrou é BAIXA; pedir ALTA esvazia.
      await filtrar(tester, indice: 0, opcao: 'ALTA');
      expect(find.text(vazioPendenciasFiltro), findsOneWidget);

      await tester.tap(find.text('Limpar filtros'));
      await carregar(tester);
      expect(find.text(descSemTurma), findsOneWidget);
    });

    testWidgets('o menu de tipos só oferece os tipos que estão na lista', (
      tester,
    ) async {
      // Oferecer os quinze do `check` produziria treze escolhas que esvaziam a
      // tela sem que nada explique por quê.
      await montar(tester);
      await tester.tap(find.byType(DropdownMenu<String>).at(1));
      await carregar(tester);
      expect(find.text('Aluno sem turma'), findsWidgets);
      expect(
        find.text(rotuloTipoPendencia('COMPRA_SEM_ESTOQUE')),
        findsNothing,
      );
    });
  });

  group('o painel', () {
    testWidgets('diz quando a pendência fecha sozinha', (tester) async {
      await montar(tester);
      await abrir(tester, descSemTurma);
      expect(
        find.textContaining('Fecha sozinha na próxima execução da rotina'),
        findsOneWidget,
      );
    });

    testWidgets('referência oculta ganha frase, não só o traço', (
      tester,
    ) async {
      // "—" sozinho pareceria dado faltando no banco em vez de permissão
      // faltando no perfil.
      await montar(tester);
      await abrir(tester, descAcelerar);
      expect(find.text(avisoReferenciaOculta), findsOneWidget);
    });

    testWidgets('sem pendencias.resolver não há Resolver nem Ignorar', (
      tester,
    ) async {
      await montar(tester, permissoes: comTurmas);
      await abrir(tester, descSemTurma);
      expect(find.text('Resolver'), findsNothing);
      expect(find.text('Ignorar'), findsNothing);
      // E o detalhe continua legível: ler pendência é do conjunto da rota.
      expect(find.text(descSemTurma), findsWidgets);
    });

    testWidgets('ROTINA_FALHOU não oferece ação de tela', (tester) async {
      await montar(tester);
      await abrir(tester, descRotina);
      expect(find.text('Ver aluno'), findsNothing);
      expect(find.text('Executar'), findsNothing);
      expect(find.text('Resolver'), findsOneWidget);
    });

    testWidgets('a ação contextual só aparece com a tela de destino aberta', (
      tester,
    ) async {
      // `BLOCO_ACIMA_CAPACIDADE` leva a Turmas, cujo conjunto mínimo inclui
      // `professores.ler` — sem ele o botão levaria a "Sem acesso", e um botão
      // que leva a lugar nenhum ensina a não clicar nos outros.
      await montar(tester);
      await abrir(tester, descCapacidade);
      expect(find.text('Ver turma'), findsOneWidget);
    });

    testWidgets('sem a tela de destino, nem o botão', (tester) async {
      await montar(
        tester,
        permissoes: const {'pendencias.ler', 'pendencias.resolver'},
      );
      await abrir(tester, descCapacidade);
      expect(find.text('Ver turma'), findsNothing);
      expect(find.text('Resolver'), findsOneWidget);
    });
  });

  group('fechar a pendência', () {
    testWidgets('ignorar avisa que ela VOLTA, e grava a justificativa', (
      tester,
    ) async {
      final (pendencias, _) = await montar(tester);
      await abrir(tester, descSemTurma);
      await tester.tap(find.text('Ignorar'));
      await carregar(tester);

      expect(find.text(avisoIgnorar), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'pedagógico já está realocando',
      );
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      expect(pendencias.fechadas, [
        'p-sem-turma|IGNORADA|pedagógico já está realocando',
      ]);
      expect(
        find.textContaining('ela volta enquanto a condição valer'),
        findsOneWidget,
      );
    });

    testWidgets('resolver manda justificativa nula quando ninguém escreveu', (
      tester,
    ) async {
      final (pendencias, _) = await montar(tester);
      await abrir(tester, descSemTurma);
      await tester.tap(find.text('Resolver'));
      await carregar(tester);
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      expect(pendencias.fechadas, ['p-sem-turma|RESOLVIDA|']);
      expect(find.text('Pendência resolvida.'), findsOneWidget);
    });

    testWidgets('a tela NÃO pré-valida a justificativa do ignorar', (
      tester,
    ) async {
      // Quem a exige é `fn_pendencia_resolver_id` (PT422/MOTIVO_OBRIGATORIO).
      // Uma validação local aqui seria a segunda implementação de uma regra do
      // banco, livre para divergir dele (card 2.6 decisão 2).
      final (pendencias, _) = await montar(tester);
      await abrir(tester, descSemTurma);
      await tester.tap(find.text('Ignorar'));
      await carregar(tester);
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);
      expect(pendencias.fechadas, ['p-sem-turma|IGNORADA|']);
    });
  });

  group('REP_VIRADA — a virada executada da pendência', () {
    TurmasFalso comDebito() => TurmasFalso.fixture()
      ..situacao = SituacaoRep(
        debito: 3,
        aulaMaisAntiga: DateTime(2026, 9, 12),
        prazoFinal: DateTime(2026, 10, 12),
        semanasUteis: 2,
        capacidade: 1,
        faltasRecentes: 0,
        veredito: 'SUGERIR_CONTINUO',
      );

    testWidgets('mostra os números do critério e as reposições previstas', (
      tester,
    ) async {
      // "sugerido virar contínuo" não é acionável; "3 aulas em aberto, prazo
      // até 12/10, cabem 2" é (card 5.3).
      await montar(tester, turmas: comDebito());
      await abrir(tester, descRepContinuo);

      expect(
        find.textContaining('3 aula(s) a repor em aberto'),
        findsOneWidget,
      );
      expect(find.textContaining('cabem 2 até lá'), findsOneWidget);
      expect(find.text('07/09/2026 · Seg 08:00'), findsOneWidget);
      expect(find.text('Veio'), findsOneWidget);
      expect(find.text('Faltou'), findsOneWidget);
    });

    testWidgets('marcar presença chama a função e mostra o veredito', (
      tester,
    ) async {
      final turmas = comDebito()..veredito = 'SUGERIR_CONTINUO';
      await montar(tester, turmas: turmas);
      await abrir(tester, descRepContinuo);
      await tester.tap(find.text('Veio'));
      await carregar(tester);

      expect(turmas.presencas, ['rep-al-lucas|VEIO']);
      // Resultado que muda a próxima ação é diálogo, nunca snackbar (2.7 f).
      expect(find.text('Presença registrada'), findsOneWidget);
      expect(find.textContaining('não cabem mais no prazo'), findsOneWidget);
    });

    testWidgets('veredito MANTER também é dito — sem ele, silêncio', (
      tester,
    ) async {
      final turmas = comDebito()..veredito = 'MANTER';
      await montar(tester, turmas: turmas);
      await abrir(tester, descRepContinuo);
      await tester.tap(find.text('Faltou'));
      await carregar(tester);

      expect(turmas.presencas, ['rep-al-lucas|FALTOU']);
      expect(find.text('Falta registrada'), findsOneWidget);
      expect(find.text(avisoVereditoManter), findsOneWidget);
    });

    testWidgets(':CONTINUO abre o seletor de bloco e chama virarContinuo', (
      tester,
    ) async {
      final (_, turmas) = await montar(tester, turmas: comDebito());
      await abrir(tester, descRepContinuo);
      await tester.tap(find.text('Executar'));
      await carregar(tester);

      expect(find.text(avisoVirarContinuo), findsOneWidget);
      // Lucas é do método Interativo: o bloco de Inglês não é oferecido, e o
      // bloco cheio (0 vagas) também não.
      expect(find.textContaining('Seg 08:00 · Laboratório 1'), findsOneWidget);
      expect(find.textContaining('Qua 08:00 · Laboratório 1'), findsNothing);
      expect(find.textContaining('Laboratório 2'), findsNothing);

      await tester.tap(find.textContaining('Seg 08:00 · Laboratório 1'));
      await carregar(tester);
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      expect(turmas.viradas, ['al-lucas|b-vazio|']);
      expect(find.text('Virada executada.'), findsOneWidget);
    });

    testWidgets('sem escolher bloco é erro do formulário, não do banco', (
      tester,
    ) async {
      final (_, turmas) = await montar(tester, turmas: comDebito());
      await abrir(tester, descRepContinuo);
      await tester.tap(find.text('Executar'));
      await carregar(tester);
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);
      expect(find.text(escolhaBloco), findsOneWidget);
      expect(turmas.viradas, isEmpty);
    });

    testWidgets(':VOLTA pede motivo e chama voltarPontual', (tester) async {
      final (_, turmas) = await montar(tester);
      await abrir(tester, descRepVolta);
      await tester.tap(find.text('Executar'));
      await carregar(tester);

      expect(find.text(avisoVoltarPontual), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'em dia');
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      expect(turmas.voltas, ['al-3004|em dia']);
      expect(turmas.viradas, isEmpty, reason: 'volta não é ida');
    });

    testWidgets('sem turmas.alocar não há Executar, Veio nem Faltou', (
      tester,
    ) async {
      await montar(
        tester,
        turmas: comDebito(),
        permissoes: {...comTurmas, 'pendencias.resolver'},
      );
      await abrir(tester, descRepContinuo);
      expect(find.text('Executar'), findsNothing);
      expect(find.text('Veio'), findsNothing);
      expect(find.text('Faltou'), findsNothing);
      // Resolver continua: quem pode resolver pode encerrar a sugestão.
      expect(find.text('Resolver'), findsOneWidget);
    });

    testWidgets('sem turmas.ler o bloco REP diz o que falta, e não some', (
      tester,
    ) async {
      // Sem a permissão, os números viriam vazios pela RLS e "nenhuma reposição
      // prevista" seria indistinguível de "você não pode ver".
      await montar(
        tester,
        permissoes: const {'pendencias.ler', 'pendencias.resolver'},
      );
      await abrir(tester, descRepContinuo);
      expect(find.text(avisoSemTurmasLer), findsOneWidget);
      expect(find.textContaining('a repor em aberto'), findsNothing);
    });
  });

  group('o contador do menu', () {
    Future<void> montarShell(
      WidgetTester tester, {
      required PendenciasFalso pendencias,
      Set<String> permissoes = secretaria,
    }) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: semRetryAutomatico,
          overrides: [
            pendenciasRepositorioProvider.overrideWithValue(pendencias),
            permissoesProvider.overrideWithValue(permissoes),
            resumoUsuarioProvider.overrideWithValue(
              const ResumoUsuario(nome: 'Direção', unidade: 'Matriz'),
            ),
          ],
          child: appDeTeste(
            rotaInicial: '/pendencias',
            construtor: (filho) => ShellIm360(filho: filho),
          ),
        ),
      );
      await carregar(tester);
    }

    testWidgets('conta só as ALTA abertas', (tester) async {
      // Seis pendências na fixture, três ALTA. O total seria "6" e o sino
      // dispararia sempre (card 2.6 decisão f).
      await montarShell(tester, pendencias: PendenciasFalso.fixture());
      expect(find.text('3'), findsOneWidget);
      expect(find.text('6'), findsNothing);
    });

    testWidgets('sem ALTA aberta não há badge nenhum', (tester) async {
      await montarShell(
        tester,
        pendencias: PendenciasFalso(pendencias: const []),
      );
      expect(find.byType(Badge), findsNothing);
      expect(find.text('Pendências'), findsWidgets);
    });

    testWidgets('sem pendencias.ler não há item nem consulta', (tester) async {
      // O provider nem chega ao repositório: um contador "0" para quem não pode
      // ler pendência nenhuma seria número errado com cara de certo.
      await montarShell(
        tester,
        pendencias: PendenciasFalso.fixture(),
        permissoes: const {'alunos.ler', 'materiais.ler'},
      );
      expect(find.text('Pendências'), findsNothing);
      expect(find.byType(Badge), findsNothing);
    });

    test('a rota de Pendências exige só pendencias.ler', () {
      final rota = rotasAplicacao.firstWhere((r) => r.id == 'pendencias');
      expect(rota.exige, {'pendencias.ler'});
      expect(idsBarraInferior, contains('pendencias'));
    });
  });

  // -------------------------------------------------------------------------
  // Card 5.11 — o rótulo, o caminho com o id, e o caminho vermelho
  // -------------------------------------------------------------------------

  /// Harness com `GoRouter` de **verdade**: o anterior era um `MaterialApp`
  /// sem rotas, e nele "Ver turma" não tinha para onde ir — a navegação era a
  /// metade que nenhum teste media (revisão da fase 05, grupo G).
  Future<GoRouter> montarComRotas(
    WidgetTester tester, {
    PendenciasFalso? pendencias,
    TurmasFalso? turmas,
    Set<String> permissoes = secretaria,
  }) async {
    final roteador = GoRouter(
      initialLocation: '/pendencias',
      routes: [
        GoRoute(
          path: '/pendencias',
          builder: (_, _) => const Scaffold(body: TelaPendencias()),
        ),
        GoRoute(
          path: '/turmas',
          builder: (_, _) => const Scaffold(body: Text('tela de turmas')),
        ),
        GoRoute(
          path: '/salas',
          builder: (_, _) => const Scaffold(body: Text('tela de salas')),
        ),
        GoRoute(
          path: '/materiais',
          builder: (_, _) => const Scaffold(body: Text('tela de materiais')),
        ),
        GoRoute(
          path: '/alunos/:id',
          builder: (_, _) => const Scaffold(body: Text('ficha do aluno')),
        ),
      ],
    );
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: semRetryAutomatico,
        overrides: [
          pendenciasRepositorioProvider.overrideWithValue(
            pendencias ?? PendenciasFalso.fixture(),
          ),
          turmasRepositorioProvider.overrideWithValue(
            turmas ?? TurmasFalso.fixture(),
          ),
          alunosRepositorioProvider.overrideWithValue(AlunosFalso.fixture()),
          permissoesProvider.overrideWithValue(permissoes),
          unidadeAtualProvider.overrideWithValue('unidade-teste'),
        ],
        child: MaterialApp.router(routerConfig: roteador, theme: temaClaro()),
      ),
    );
    await carregar(tester);
    return roteador;
  }

  group('a ação contextual leva o ID e a ABA', () {
    test('cada tipo tem o rótulo do que se vai FAZER, não do destino', () {
      // "Ver aluno" para os oito tipos que apontam para a ficha é o oposto de
      // uma fila de trabalho (wireframe §14.3).
      expect(rotuloAcaoPendencia('ALUNO_SEM_TURMA'), 'Alocar');
      expect(rotuloAcaoPendencia('SUGERIR_FORMADO'), 'Formar');
      expect(rotuloAcaoPendencia('CERTIFICADO_INCONSISTENTE'), 'Ver checklist');
      expect(rotuloAcaoPendencia('BLOCO_ACIMA_CAPACIDADE'), 'Ver turma');
      expect(rotuloAcaoPendencia('ROTINA_FALHOU'), '');
    });

    test('a aba da ficha é a do problema, e não sempre a primeira', () {
      expect(abaDaFicha('ALUNO_SEM_TURMA'), 'turmas');
      expect(abaDaFicha('ACELERAR_SEM_2O_BLOCO'), 'turmas');
      expect(abaDaFicha('CERTIFICADO_INCONSISTENTE'), 'certificado');
      expect(abaDaFicha('TRILHA_DIVERGENTE_COMBO'), 'trilha');
      expect(abaDaFicha('SUGERIR_FORMADO'), 'dados');
      // E o índice sai da MESMA lista que a ficha usa para montar as abas.
      expect(indiceAbaFicha('turmas'), abasFicha.indexOf('turmas'));
      expect(indiceAbaFicha('inexistente'), 0, reason: 'cai na primeira');
    });

    test('as duas metades do REP_VIRADA têm rótulos diferentes', () {
      // Um rótulo só para as duas fazia a lista, o título do painel e a
      // confirmação dizerem a mesma coisa em dois casos contrários.
      Pendencia rep(String sufixo) => pendenciaFalsa(
        id: 'p-$sufixo',
        tipo: 'REP_VIRADA',
        severidade: 'MEDIA',
        descricao: 'x',
        chaveDedup: 'REP:al-1:$sufixo',
        alunoId: 'al-1',
        alunoNome: 'Alguém',
      );
      expect(
        rotuloPendencia(rep('CONTINUO')),
        contains('virada para contínuo'),
      );
      expect(rotuloPendencia(rep('VOLTA')), contains('volta para pontual'));
      // O menu de FILTRO continua com o rótulo do tipo: lá se filtra por tipo.
      expect(rotuloTipoPendencia('REP_VIRADA'), tiposPendencia['REP_VIRADA']);
    });

    test('referência oculta pela RLS não vira botão — nos quatro destinos', () {
      // O id chega por `left join` mesmo quando o nome não chega (card 2.3 §9):
      // é exatamente o caso de quem não pode ler a tabela de destino, e a
      // regra vale para os quatro, não só para o aluno.
      final oculta = pendenciaFalsa(
        id: 'p',
        tipo: 'PC_SEM_SUBSTITUTO',
        severidade: 'ALTA',
        descricao: 'x',
        chaveDedup: 'PC:pc-1',
        pcId: 'pc-1',
      );
      expect(referenciaDaAcaoPresente(oculta), isFalse);

      final visivel = pendenciaFalsa(
        id: 'p',
        tipo: 'PC_SEM_SUBSTITUTO',
        severidade: 'ALTA',
        descricao: 'x',
        chaveDedup: 'PC:pc-1',
        pcId: 'pc-1',
        pcIdentificador: 'LAB1-03',
      );
      expect(referenciaDaAcaoPresente(visivel), isTrue);
      expect(idDaAcao(visivel), 'pc-1');
      expect(parametroDaAcao(acaoDe(visivel.tipo)), 'pc');
    });

    testWidgets('"Ver turma" navega para /turmas COM o id do bloco', (
      tester,
    ) async {
      final roteador = await montarComRotas(tester);
      await abrir(tester, descCapacidade);
      await tester.tap(find.text('Ver turma'));
      await carregar(tester);

      final uri = roteador.state.uri;
      expect(uri.path, '/turmas');
      expect(
        uri.queryParameters['bloco'],
        'b-acima',
        reason: 'sem o id, a tela de destino abre a grade inteira',
      );
    });

    testWidgets('"Alocar" abre a ficha na aba Turmas', (tester) async {
      final roteador = await montarComRotas(tester);
      await abrir(tester, descSemTurma);
      await tester.tap(find.text('Alocar'));
      await carregar(tester);

      final uri = roteador.state.uri;
      expect(uri.path, '/alunos/al-3005');
      expect(uri.queryParameters['aba'], 'turmas');
    });
  });

  group('os caminhos vermelhos', () {
    testWidgets('marcar presença que falha vira BANNER, e não exceção crua', (
      tester,
    ) async {
      final turmas = TurmasFalso.fixture()
        ..situacao = SituacaoRep(
          debito: 3,
          aulaMaisAntiga: DateTime(2026, 9, 12),
          prazoFinal: DateTime(2026, 10, 12),
          semanasUteis: 2,
          capacidade: 1,
          faltasRecentes: 0,
          veredito: 'SUGERIR_CONTINUO',
        )
        ..erroAoRegistrar = const ErroApp(
          codigo: 'REPOSICAO_NAO_PREVISTA',
          mensagem: 'Esta reposição já não está prevista.',
          traduzido: true,
        );
      await montar(tester, turmas: turmas);
      await abrir(tester, descRepContinuo);
      await tester.tap(find.text('Veio'));
      await carregar(tester);

      expect(find.text('Esta reposição já não está prevista.'), findsOneWidget);
      expect(find.text('Presença registrada'), findsNothing);
    });

    testWidgets('PENDENCIA_JA_RESOLVIDA recarrega a lista e fecha o '
        'formulário — "atualize a tela" só vale se a tela atualizar', (
      tester,
    ) async {
      final pendencias = PendenciasFalso.fixture()
        ..erroAoResolver = const ErroApp(
          codigo: 'PENDENCIA_JA_RESOLVIDA',
          mensagem: 'Esta pendência já foi encerrada.',
          traduzido: true,
        );
      final (repo, _) = await montar(tester, pendencias: pendencias);
      final antes = repo.leituras;
      await abrir(tester, descSemTurma);
      await tester.tap(find.text('Resolver'));
      await carregar(tester);
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      expect(repo.leituras, greaterThan(antes), reason: 'a lista recarregou');
      expect(find.byKey(chaveBotaoSalvar), findsNothing);
    });
  });

  testWidgets('o cabeçalho traz a contagem do §14.1', (tester) async {
    await montar(tester);
    expect(find.text(tituloPendencias(6)), findsOneWidget);
  });

  testWidgets('a severidade aparece UMA vez no cabeçalho do painel', (
    tester,
  ) async {
    await montar(tester);
    await abrir(tester, descSemTurma);
    expect(find.textContaining('ALTA · aberta'), findsNothing);
    expect(find.textContaining('Aberta há 2 dias'), findsOneWidget);
  });
}
