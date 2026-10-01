import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/infraestrutura/infraestrutura.dart';
import 'package:gestao_im360/infraestrutura/infraestrutura_provider.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/salas/aba_manutencoes.dart';
import 'package:gestao_im360/telas/salas/tela_salas.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/util/async_valor.dart';
import 'package:gestao_im360/widgets/estados.dart';

import 'apoio/carregar.dart';
import 'apoio/infraestrutura_falso.dart';

/// Card 9.2,78 — o histórico de manutenções dos PCs, que o monitor procurou na
/// rodada de 30/09/2026 e não achou. O pedido, nas palavras dele: "uma tela de
/// manutenções onde possa filtrar por máquina, tipo de manutenção, data, por
/// quem e o que foi feito… começando pela mais recente".
///
/// O que se mede: a ordem decrescente, as cinco colunas, os cinco filtros, os
/// estados (carregando, vazio com motivo, vazio de filtro, erro), o "quem"
/// vindo do nome e não do embed, os 390 px do celular e que o MONITOR — só com
/// `salas.ler` — vê tudo, sem permissão nova. A guarda de rota (o "sem
/// acesso") é a da tela 10 inteira, tabelada em `guardas_rota_test.dart`.
void main() {
  final hoje = soData(DateTime.now());
  DateTime dia(int atras) => hoje.subtract(Duration(days: atras));

  // Na ordem CRESCENTE de propósito: o repositório falso devolve como guardou,
  // e só a tela ordenando faz a mais recente vir primeiro.
  List<PcManutencao> historicoCrescente() => [
    PcManutencao(
      id: 'm-antiga',
      pcId: 'pc-lab1-01',
      tipo: 'PREVENTIVA',
      dataInicio: dia(60),
      dataFim: dia(59),
      descricao: 'limpeza e atualização',
      criadoPor: 'u-secretaria',
      criadoPorNome: 'Paula Reis',
      criadoEm: dia(60),
    ),
    PcManutencao(
      id: 'm-config',
      pcId: 'pc-lab1-02',
      tipo: 'CONFIGURACAO',
      dataInicio: dia(10),
      dataFim: dia(10),
      descricao: 'instalação do pacote Office',
      criadoPor: 'u-monitor',
      criadoPorNome: 'Davi Monteiro',
      criadoEm: dia(10),
    ),
    PcManutencao(
      id: 'm-aberta',
      pcId: 'pc-lab2-05',
      tipo: 'CORRETIVA',
      dataInicio: dia(3),
      descricao: 'fonte queimada',
      criadoPor: 'u-monitor',
      criadoPorNome: 'Davi Monteiro',
      criadoEm: dia(3),
    ),
  ];

  InfraestruturaFalso repositorio({List<PcManutencao>? manutencoes}) {
    final fixture = InfraestruturaFalso.fixture();
    return InfraestruturaFalso(
      salas: fixture.salas_,
      pcs: fixture.pcs_,
      manutencoes: manutencoes ?? historicoCrescente(),
      professores: fixture.professores_,
    );
  }

  // O monitor da matriz inicial, recortado ao que a tela 10 consome: ler a
  // aba não exige nada além do que a rota já exige.
  const monitor = {
    'salas.ler',
    'professores.ler',
    'salas.registrar_manutencao',
    'salas.acessar_credencial',
  };

  Future<void> montar(
    WidgetTester tester, {
    required InfraestruturaFalso repositorio,
    Size tamanho = const Size(1400, 900),
    bool abrirAba = true,
    bool esperar = true,
  }) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final mobile = tamanho.width < 600;
    await tester.pumpWidget(
      ProviderScope(
        retry: semRetryAutomatico,
        overrides: [
          infraestruturaRepositorioProvider.overrideWithValue(repositorio),
          permissoesProvider.overrideWithValue(monitor),
          unidadeAtualProvider.overrideWithValue('unidade-teste'),
        ],
        child: MaterialApp(
          // O tema do app real no celular (armadilha do 9.2,72: o compacto em
          // 390 px mede alvo menor do que o que o monitor toca).
          theme: temaClaro(compacto: !mobile),
          home: const Scaffold(body: TelaSalas()),
        ),
      ),
    );
    await carregar(tester);
    if (abrirAba) {
      await tester.tap(find.text('Manutenções'));
      // Com a leitura pendente o esqueleto anima para sempre: só quadros.
      if (esperar) {
        await carregar(tester);
      } else {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }
    }
  }

  /// O texto À VISTA. A `DropdownMenu` monta as entradas fora da tela para
  /// medir a própria largura — "Corretiva" existe duas vezes na árvore com a
  /// tabela mostrando uma só.
  Finder visivel(String texto) => find.text(texto).hitTestable();

  Finder menu(String rotulo) => find.byWidgetPredicate(
    (w) => w is DropdownMenu<String> && (w.label as Text?)?.data == rotulo,
  );

  Future<void> escolher(
    WidgetTester tester,
    String rotulo,
    String opcao,
  ) async {
    await tester.tap(menu(rotulo));
    await tester.pumpAndSettle();
    // O item DO MENU — "Paula Reis" também é texto de célula, e a ordem na
    // árvore não diz qual dos dois é o último.
    await tester.tap(find.widgetWithText(MenuItemButton, opcao).hitTestable());
    await carregar(tester);
  }

  double alturaDe(WidgetTester tester, String texto) =>
      tester.getTopLeft(find.text(texto)).dy;

  group('lógica pura', () {
    test('a mais recente primeiro; no mesmo dia, a registrada por último', () {
      final mesmoDia = [
        PcManutencao(
          id: 'cedo',
          pcId: 'p',
          tipo: 'PREVENTIVA',
          dataInicio: dia(1),
          criadoEm: dia(1).add(const Duration(hours: 9)),
        ),
        PcManutencao(
          id: 'sem-carimbo',
          pcId: 'p',
          tipo: 'PREVENTIVA',
          dataInicio: dia(1),
        ),
        PcManutencao(
          id: 'tarde',
          pcId: 'p',
          tipo: 'PREVENTIVA',
          dataInicio: dia(1),
          criadoEm: dia(1).add(const Duration(hours: 15)),
        ),
      ];
      expect(
        ordenarHistorico([...historicoCrescente(), ...mesmoDia])
            .map((m) => m.id),
        ['tarde', 'cedo', 'sem-carimbo', 'm-aberta', 'm-config', 'm-antiga'],
      );
    });

    test('a manutenção feita e encerrada NO MESMO DIA é achada por aquele dia '
        '— as duas pontas do filtro são fechadas', () {
      final config = historicoCrescente()[1]; // início == fim == dia(10)
      expect(manutencaoNoPeriodo(config, de: dia(10), ate: dia(10)), isTrue);
      expect(manutencaoNoPeriodo(config, de: dia(9)), isFalse);
      expect(manutencaoNoPeriodo(config, ate: dia(11)), isFalse);
    });

    test('a aberta vale para qualquer dia desde o início', () {
      final aberta = historicoCrescente()[2]; // desde dia(3), sem fim
      expect(manutencaoNoPeriodo(aberta, de: hoje, ate: hoje), isTrue);
      expect(manutencaoNoPeriodo(aberta, de: dia(30), ate: dia(20)), isFalse);
      expect(manutencaoNoPeriodo(aberta), isTrue);
    });

    test('os cinco filtros, um a um', () {
      final todas = historicoCrescente();
      List<String> ids(FiltroManutencoes f) =>
          filtrarManutencoes(todas, f).map((m) => m.id!).toList();
      expect(ids(const FiltroManutencoes(pcId: 'pc-lab2-05')), ['m-aberta']);
      expect(ids(const FiltroManutencoes(tipo: 'PREVENTIVA')), ['m-antiga']);
      expect(ids(FiltroManutencoes(de: dia(12), ate: dia(5))), ['m-config']);
      expect(ids(const FiltroManutencoes(autorId: 'u-monitor')), [
        'm-config',
        'm-aberta',
      ]);
      expect(ids(const FiltroManutencoes(busca: 'OFFICE')), ['m-config']);
      expect(ids(FiltroManutencoes.semFiltro), hasLength(3));
    });

    test('"Data" conta como UM filtro, com uma ponta ou com as duas', () {
      expect(FiltroManutencoes(de: hoje).ativos, 1);
      expect(FiltroManutencoes(de: hoje, ate: hoje).ativos, 1);
      expect(
        FiltroManutencoes(
          pcId: 'p',
          tipo: 'PREVENTIVA',
          de: hoje,
          autorId: 'u',
          busca: 'x',
        ).ativos,
        5,
      );
      expect(FiltroManutencoes.semFiltro.ativos, 0);
    });

    test(
      'as opções de "Registrada por" são quem aparece, uma vez, por nome',
      () {
        final autores = autoresDoHistorico([
          ...historicoCrescente(),
          PcManutencao(pcId: 'p', tipo: 'PREVENTIVA', dataInicio: hoje),
        ]);
        expect(autores, {
          'u-monitor': 'Davi Monteiro',
          'u-secretaria': 'Paula Reis',
        });
        expect(autores.keys.first, 'u-monitor', reason: 'Davi antes de Paula');
      },
    );

    test('a linha lê o autor do mapa de nomes, e a escrita não carrega a '
        'auditoria — quem a carimba é o fn_auditoria', () {
      final m = PcManutencao.deLinha({
        'id': 'm1',
        'pc_id': 'p1',
        'tipo': 'CORRETIVA',
        'data_inicio': '2026-09-30',
        'data_fim': null,
        'descricao': 'troca de fonte',
        'pc_substituto_id': null,
        'criado_por': 'u-monitor',
        'criado_em': '2026-09-30T17:31:00+00:00',
        'autor': {'nome': 'Davi Monteiro'},
      });
      expect(m.criadoPor, 'u-monitor');
      expect(m.criadoPorNome, 'Davi Monteiro');
      expect(m.criadoEm, isNotNull);
      final linha = m.paraLinha('unidade-teste');
      expect(linha.keys.where((k) => k.startsWith('criado')), isEmpty);
      expect(linha.containsKey('autor'), isFalse);
    });
  });

  group('a aba', () {
    testWidgets('abre no histórico inteiro, da mais recente para a mais '
        'antiga, com as cinco colunas', (tester) async {
      await montar(tester, repositorio: repositorio());
      for (final titulo in [
        'Máquina',
        'Tipo',
        'Período',
        'Registrada por',
        'O que foi feito',
      ]) {
        expect(find.text(titulo), findsWidgets, reason: titulo);
      }
      expect(
        alturaDe(tester, 'fonte queimada'),
        lessThan(alturaDe(tester, 'instalação do pacote Office')),
      );
      expect(
        alturaDe(tester, 'instalação do pacote Office'),
        lessThan(alturaDe(tester, 'limpeza e atualização')),
      );
      expect(visivel('LAB2-05'), findsOneWidget);
      expect(visivel('Corretiva'), findsOneWidget);
      expect(
        find.text(formatarPeriodo(dia(3), null, DateTime.now())),
        findsOneWidget,
      );
      expect(visivel('Davi Monteiro'), findsNWidgets(2));
      expect(visivel('Paula Reis'), findsOneWidget);
    });

    testWidgets('o monitor, só com salas.ler, vê o histórico inteiro e nenhuma '
        'ação de escrita — a aba é leitura', (tester) async {
      await montar(tester, repositorio: repositorio());
      expect(find.text('fonte queimada'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('sem nome de autor (carga da fixture ou da importação) a '
        'coluna diz "—", e não um nome qualquer', (tester) async {
      await montar(
        tester,
        repositorio: repositorio(
          manutencoes: [
            PcManutencao(
              id: 'm-carga',
              pcId: 'pc-lab1-03',
              tipo: 'PREVENTIVA',
              dataInicio: dia(5),
              descricao: 'carga inicial',
            ),
          ],
        ),
      );
      expect(find.text('carga inicial'), findsOneWidget);
      expect(find.text(semAutor), findsOneWidget);
    });

    testWidgets('filtro de texto procura no que foi feito, e o vazio do filtro '
        'oferece limpar', (tester) async {
      await montar(tester, repositorio: repositorio());
      await tester.enterText(
        find.widgetWithText(TextField, 'O que foi feito'),
        'fonte',
      );
      await carregar(tester);
      expect(find.text('fonte queimada'), findsOneWidget);
      expect(find.text('limpeza e atualização'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'O que foi feito'),
        'teclado',
      );
      await carregar(tester);
      expect(find.text(vazioManutencoesFiltro), findsOneWidget);
      await tester.tap(find.text('Limpar filtros'));
      await carregar(tester);
      expect(find.text('limpeza e atualização'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'O que foi feito'),
            )
            .controller!
            .text,
        isEmpty,
        reason: 'o campo acompanha o "Limpar filtros"',
      );
    });

    testWidgets('filtro de data: um dia só acha a manutenção feita e '
        'encerrada naquele dia; data incompleta não filtra', (tester) async {
      await montar(tester, repositorio: repositorio());
      final alvo = formatarData(dia(10));
      await tester.enterText(find.widgetWithText(TextField, 'De'), alvo);
      await tester.enterText(find.widgetWithText(TextField, 'Até'), alvo);
      await carregar(tester);
      expect(find.text('instalação do pacote Office'), findsOneWidget);
      expect(find.text('fonte queimada'), findsNothing);
      expect(find.text('limpeza e atualização'), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, 'Até'), '3/1');
      await carregar(tester);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Até'))
            .decoration!
            .errorText,
        'dd/mm/aaaa',
        reason: 'o campo diz por quê',
      );
      expect(
        find.text('fonte queimada'),
        findsOneWidget,
        reason: 'sem a ponta inválida, sobra "desde o dia 10"',
      );
    });

    testWidgets('"Registrada por" oferece quem aparece no histórico e filtra', (
      tester,
    ) async {
      await montar(tester, repositorio: repositorio());
      await escolher(tester, 'Registrada por', 'Paula Reis');
      expect(find.text('limpeza e atualização'), findsOneWidget);
      expect(find.text('fonte queimada'), findsNothing);
    });

    testWidgets('"Máquina" filtra pelo PC', (tester) async {
      await montar(tester, repositorio: repositorio());
      await escolher(tester, 'Máquina', 'LAB1-02 · Laboratório 1');
      expect(find.text('instalação do pacote Office'), findsOneWidget);
      expect(find.text('fonte queimada'), findsNothing);
    });

    testWidgets('"Tipo" filtra pelo tipo', (tester) async {
      await montar(tester, repositorio: repositorio());
      await escolher(tester, 'Tipo', 'Configuração');
      expect(find.text('instalação do pacote Office'), findsOneWidget);
      expect(find.text('fonte queimada'), findsNothing);
      expect(find.text('limpeza e atualização'), findsNothing);
    });

    testWidgets('sem registro nenhum, o vazio diz onde se registra — e não '
        'oferece ação, porque a ação mora na linha do PC', (tester) async {
      await montar(tester, repositorio: repositorio(manutencoes: const []));
      expect(find.text(vazioManutencoes), findsOneWidget);
      expect(find.text('Limpar filtros'), findsNothing);
    });

    testWidgets('CARREGANDO: nenhuma linha afirmada', (tester) async {
      final repo = repositorio()..leiturasPendentes.add('historicoManutencoes');
      await montar(tester, repositorio: repo, esperar: false);
      expect(find.text('fonte queimada'), findsNothing);
      expect(find.text(vazioManutencoes), findsNothing);
    });

    testWidgets('a leitura que FALHA diz que falhou e oferece de novo — e a '
        'aba Salas e PCs continua de pé', (tester) async {
      final repo = repositorio()..leiturasQueFalham.add('historicoManutencoes');
      await montar(tester, repositorio: repo);
      expect(find.byType(EstadoErro), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
      expect(find.text(vazioManutencoes), findsNothing);

      await tester.tap(find.text('Salas e PCs'));
      await carregar(tester);
      expect(find.text('Laboratório 1'), findsOneWidget);
    });

    testWidgets(
      'PCs que FALHAM: a máquina diz "não lido", e a linha continua',
      (tester) async {
        final repo = repositorio()..leiturasQueFalham.add('pcs');
        await montar(tester, repositorio: repo);
        expect(find.text('fonte queimada'), findsOneWidget);
        expect(find.text(textoNaoLido), findsWidgets);
        expect(visivel('LAB2-05'), findsNothing);
      },
    );
  });

  group('390 px (estrategia-testes §13)', () {
    testWidgets('cartões na ordem, com período, o que foi feito e quem '
        'registrou; sem estouro', (tester) async {
      await montar(
        tester,
        repositorio: repositorio(),
        tamanho: const Size(390, 800),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Período'), findsNothing, reason: 'cartões, não tabela');
      expect(find.text('Filtrar'), findsOneWidget);
      expect(find.text('Registrada por Davi Monteiro'), findsNWidgets(2));
      expect(find.text('Registrada por Paula Reis'), findsOneWidget);
      expect(
        find.text(formatarPeriodo(dia(3), null, DateTime.now())),
        findsOneWidget,
      );
      expect(
        alturaDe(tester, 'fonte queimada'),
        lessThan(alturaDe(tester, 'limpeza e atualização')),
      );
    });

    testWidgets('a folha de filtros abre com os cinco, sem estouro', (
      tester,
    ) async {
      await montar(
        tester,
        repositorio: repositorio(),
        tamanho: const Size(390, 800),
      );
      await tester.tap(find.text('Filtrar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final rotulo in ['Máquina', 'Tipo', 'De', 'Até', 'Registrada por']) {
        expect(find.text(rotulo), findsWidgets, reason: rotulo);
      }
      expect(find.widgetWithText(TextField, 'O que foi feito'), findsOneWidget);
    });

    testWidgets('as três abas cabem em 390 px', (tester) async {
      await montar(
        tester,
        repositorio: repositorio(),
        tamanho: const Size(390, 800),
        abrirAba: false,
      );
      expect(tester.takeException(), isNull);
      for (final aba in ['Salas e PCs', 'Manutenções', 'Professores']) {
        expect(find.text(aba), findsOneWidget, reason: aba);
      }
    });
  });
}
