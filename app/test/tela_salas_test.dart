import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/infraestrutura/infraestrutura.dart';
import 'package:gestao_im360/infraestrutura/infraestrutura_provider.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/salas/tela_salas.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/widgets/formulario.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'apoio/carregar.dart';
import 'apoio/infraestrutura_falso.dart';

/// A obrigação de teste de um card de **Tela** (card 2.8 §13): ocultação por
/// permissão e estado vazio com o texto do card 2.7 — a guarda de rota já está
/// tabelada em `guardas_rota_test.dart`. Mais o que esta tela tem de próprio:
/// a capacidade efetiva derivada, a ação contextual de cada PC por permissão,
/// manutenção registrada e encerrada no repositório injetado, a credencial
/// (só quem tem `salas.acessar_credencial` vê os botões) e o professor que
/// não se exclui.
void main() {
  // Os quatro conjuntos são a matriz inicial do card 2.4 §5 recortada ao que
  // esta tela consome — mesmo `salas.acessar_credencial`, que é do monitor e
  // da direção, não da secretaria.
  const leitura = {'salas.ler', 'professores.ler'};
  const monitor = {
    ...leitura,
    'salas.registrar_manutencao',
    'salas.acessar_credencial',
  };
  const secretaria = {
    ...leitura,
    'salas.criar',
    'salas.editar',
    'salas.registrar_manutencao',
    'professores.criar',
    'professores.editar',
  };
  const direcao = {...secretaria, 'salas.excluir', 'salas.acessar_credencial'};

  Future<void> montar(
    WidgetTester tester, {
    required InfraestruturaFalso repositorio,
    Set<String> permissoes = leitura,
    Size tamanho = const Size(1400, 900),
  }) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          infraestruturaRepositorioProvider.overrideWithValue(repositorio),
          permissoesProvider.overrideWithValue(permissoes),
          unidadeAtualProvider.overrideWithValue('unidade-teste'),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          home: const Scaffold(body: TelaSalas()),
        ),
      ),
    );
    await carregar(tester);
  }

  Future<void> abrirSala(WidgetTester tester, String nome) async {
    await tester.tap(find.text(nome));
    await carregar(tester);
  }

  testWidgets('a lista mostra PCs operacionais/total e a capacidade efetiva '
      'derivada — nominal, total e operacionais distintos', (tester) async {
    await montar(tester, repositorio: InfraestruturaFalso.fixture());
    expect(find.text('Laboratório 1'), findsOneWidget);
    expect(find.text('Cap. efetiva'), findsOneWidget);
    expect(find.text('10/10'), findsOneWidget, reason: 'Laboratório 1');
    expect(find.text('4/6'), findsOneWidget, reason: 'Laboratório 2');
    expect(find.text('0/0'), findsOneWidget, reason: 'Sala Eletricista');
    // Efetiva do Laboratório 2 = 4 (nominal 6, operacionais 4).
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('sem salas.criar os botões "Nova sala" e "Novo PC" não são '
      'renderizados', (tester) async {
    await montar(tester, repositorio: InfraestruturaFalso.fixture());
    expect(find.text('Nova sala'), findsNothing);
    expect(find.text('Novo PC'), findsNothing);

    await montar(
      tester,
      repositorio: InfraestruturaFalso.fixture(),
      permissoes: secretaria,
    );
    expect(find.text('Nova sala'), findsOneWidget);
    expect(find.text('Novo PC'), findsOneWidget);
  });

  testWidgets('estado vazio com o texto do card 2.7 — e a ação só para quem '
      'pode criar', (tester) async {
    await montar(tester, repositorio: InfraestruturaFalso());
    expect(find.text(vazioSalas), findsOneWidget);
    expect(find.text('+ Nova sala'), findsNothing);

    await montar(
      tester,
      repositorio: InfraestruturaFalso(),
      permissoes: secretaria,
    );
    expect(find.text('+ Nova sala'), findsOneWidget);
  });

  testWidgets('busca sem resultado: estado vazio de filtro, e "Limpar filtros" '
      'mostra tudo — inclusive a inativa', (tester) async {
    final repositorio = InfraestruturaFalso.fixture()
      ..salas_.add(
        const Sala(
          id: 's-dep',
          nome: 'Depósito',
          tipo: 'LABORATORIO',
          capacidadeNominal: 4,
          ativo: false,
        ),
      );
    await montar(tester, repositorio: repositorio);
    expect(find.text('Depósito'), findsNothing, reason: 'só ativas');

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text(vazioSalasFiltro), findsOneWidget);

    await tester.tap(find.text('Limpar filtros'));
    await tester.pumpAndSettle();
    expect(find.text('Laboratório 1'), findsOneWidget);
    expect(find.text('Depósito'), findsOneWidget);
    expect(find.text('Inativa'), findsOneWidget);
    expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, false);
  });

  group('painel da sala', () {
    testWidgets('lista os PCs com a manutenção aberta e, sem permissão, '
        'nenhuma ação', (tester) async {
      await montar(tester, repositorio: InfraestruturaFalso.fixture());
      await abrirSala(tester, 'Laboratório 2');
      expect(find.text('Computadores'), findsOneWidget);
      expect(find.text('LAB2-05'), findsOneWidget);
      expect(find.textContaining('corretiva desde'), findsOneWidget);
      expect(find.textContaining('sem substituto'), findsOneWidget);
      expect(find.text('Desativado'), findsOneWidget);
      expect(find.text('Manutenção'), findsNothing);
      expect(find.text('Encerrar'), findsNothing);
      expect(find.text('Reativar'), findsNothing);
      expect(find.text('Editar'), findsNothing);
      expect(find.text('Novo PC'), findsNothing);
    });

    testWidgets('a ação contextual segue a permissão: monitor registra e '
        'encerra, só quem edita reativa', (tester) async {
      await montar(
        tester,
        repositorio: InfraestruturaFalso.fixture(),
        permissoes: monitor,
      );
      await abrirSala(tester, 'Laboratório 2');
      expect(find.text('Manutenção'), findsNWidgets(4));
      expect(find.text('Encerrar'), findsOneWidget);
      expect(find.text('Reativar'), findsNothing);
      expect(find.text('Editar'), findsNothing);
    });

    // Teste separado, e não um segundo `montar` no mesmo: remontar o app não
    // fecha o diálogo do painel anterior, que fica por cima do novo.
    testWidgets('quem edita salas vê Reativar, Editar e Novo PC', (
      tester,
    ) async {
      await montar(
        tester,
        repositorio: InfraestruturaFalso.fixture(),
        permissoes: secretaria,
      );
      await abrirSala(tester, 'Laboratório 2');
      expect(find.text('Reativar'), findsOneWidget);
      expect(find.text('Editar'), findsOneWidget);
      expect(find.text('Novo PC'), findsWidgets);
    });

    // ⚠️ Os três testes abaixo mudaram no card 5.4, e a mudança é a mesma nos
    // três: `pc.status` deixou de ser escolha da tela e passou a ser DERIVADO de
    // `pc_manutencao` por trigger. Saíram os dois interruptores e os dois avisos
    // que diziam ao monitor que o status não mudaria — quem escreve o status
    // agora é o banco, para os dois perfis, e a tela informa em vez de oferecer
    // uma decisão que não é mais dela.
    testWidgets('o monitor registra a manutenção e o status segue sozinho', (
      tester,
    ) async {
      final repositorio = InfraestruturaFalso.fixture();
      await montar(tester, repositorio: repositorio, permissoes: monitor);
      await abrirSala(tester, 'Laboratório 2');
      await tester.tap(find.text('Manutenção').first);
      await tester.pumpAndSettle();
      expect(find.text('Registrar manutenção — LAB2-01'), findsOneWidget);
      expect(find.textContaining('automaticamente'), findsOneWidget);
      expect(find.text('Colocar o PC em manutenção'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Descrição'),
        'teclado quebrado',
      );
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      expect(repositorio.chamadas, contains('salvarManutencao'));
      // A tela NÃO escreve o status: se voltasse a escrever, o app estaria
      // disputando com o trigger uma coluna que não é mais dele.
      expect(repositorio.chamadas, isNot(contains('salvarPc')));
      final nova = repositorio.manutencoes_.where(
        (m) => m.pcId == 'pc-lab2-01',
      );
      expect(nova.single.tipo, 'CORRETIVA');
      expect(nova.single.descricao, 'teclado quebrado');
      expect(nova.single.dataFim, isNull);
      // E o PC aparece em manutenção mesmo assim — quem o pôs lá foi o banco.
      final pc = repositorio.pcs_.singleWhere((p) => p.id == 'pc-lab2-01');
      expect(pc.status, 'MANUTENCAO');
      expect(find.text('Manutenção registrada.'), findsOneWidget);
      // O painel recarregou: a linha passou a "Encerrar".
      expect(find.text('Encerrar'), findsNWidgets(2));
    });

    testWidgets('quem edita salas vê o MESMO formulário: o status não é '
        'escolha de ninguém', (tester) async {
      final repositorio = InfraestruturaFalso.fixture();
      await montar(tester, repositorio: repositorio, permissoes: secretaria);
      await abrirSala(tester, 'Laboratório 2');
      await tester.tap(find.text('Manutenção').first);
      await tester.pumpAndSettle();
      expect(find.text('Colocar o PC em manutenção'), findsNothing);
      expect(find.textContaining('automaticamente'), findsOneWidget);

      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);
      expect(repositorio.chamadas, isNot(contains('salvarPc')));
      final pc = repositorio.pcs_.singleWhere((p) => p.id == 'pc-lab2-01');
      expect(pc.status, 'MANUTENCAO');
      expect(find.textContaining('Em manutenção'), findsNWidgets(2));
    });

    testWidgets('encerrar grava só o fim — quem devolve o PC é o trigger', (
      tester,
    ) async {
      final repositorio = InfraestruturaFalso.fixture();
      await montar(tester, repositorio: repositorio, permissoes: secretaria);
      await abrirSala(tester, 'Laboratório 2');
      await tester.tap(find.text('Encerrar'));
      await tester.pumpAndSettle();
      expect(find.text('Encerrar manutenção — LAB2-05'), findsOneWidget);
      expect(find.text('Voltar o PC a operacional'), findsNothing);

      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);
      final manutencao = repositorio.manutencoes_.singleWhere(
        (m) => m.id == 'm-aberta',
      );
      // `data_fim` é o dia em que o PC VOLTA a operar, e o banco lê o intervalo
      // como `[inicio, fim)` desde o card 5.4: encerrar hoje devolve o PC HOJE.
      expect(manutencao.dataFim, soData(DateTime.now()));
      expect(repositorio.chamadas, isNot(contains('salvarPc')));
      final pc = repositorio.pcs_.singleWhere((p) => p.id == 'pc-lab2-05');
      expect(pc.status, 'OPERACIONAL');
      expect(find.text('Manutenção encerrada.'), findsOneWidget);
      expect(find.text('Encerrar'), findsNothing);
    });

    testWidgets('reativar devolve o desativado a operacional', (tester) async {
      final repositorio = InfraestruturaFalso.fixture();
      await montar(tester, repositorio: repositorio, permissoes: secretaria);
      await abrirSala(tester, 'Laboratório 2');
      await tester.tap(find.text('Reativar'));
      await tester.pumpAndSettle();
      expect(find.text('Reativar computador'), findsOneWidget);
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);
      final pc = repositorio.pcs_.singleWhere((p) => p.id == 'pc-lab2-06');
      expect(pc.status, 'OPERACIONAL');
      expect(find.text('PC reativado.'), findsOneWidget);
      expect(find.text('Desativado'), findsNothing);
    });

    testWidgets('novo PC de dentro do painel nasce na sala do painel', (
      tester,
    ) async {
      final repositorio = InfraestruturaFalso.fixture();
      await montar(tester, repositorio: repositorio, permissoes: secretaria);
      await abrirSala(tester, 'Laboratório 1');
      await tester.tap(find.text('Novo PC').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Identificador *'),
        'LAB1-11',
      );
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);
      final novo = repositorio.pcs_.singleWhere(
        (p) => p.identificador == 'LAB1-11',
      );
      expect(novo.salaId, 's-lab1');
      expect(novo.status, 'OPERACIONAL');
      expect(find.text('PC salvo.'), findsOneWidget);
      expect(find.text('LAB1-11'), findsOneWidget, reason: 'recarregou');
    });

    testWidgets('excluir PC com histórico: a recusa do banco vira banner pelo '
        'código', (tester) async {
      final repositorio = InfraestruturaFalso.fixture()
        ..falhaAoGravar = const PostgrestException(
          message: 'Este computador tem histórico e não pode ser excluído.',
          code: 'PT409',
          details: '{"codigo":"PC_COM_HISTORICO","manutencoes":1}',
        );
      await montar(tester, repositorio: repositorio, permissoes: direcao);
      await abrirSala(tester, 'Laboratório 1');
      await tester.tap(find.text('LAB1-01'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();
      expect(find.text('Excluir computador?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Excluir').last);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Este computador tem histórico e não pode ser excluído. Marque-o '
          'como desativado.',
        ),
        findsOneWidget,
      );
      expect(repositorio.pcs_.any((p) => p.id == 'pc-lab1-01'), isTrue);
    });
  });

  group('credencial do PC (card 2.9 §8)', () {
    testWidgets('o carimbo aparece para quem lê; os botões só para quem tem '
        'salas.acessar_credencial', (tester) async {
      await montar(
        tester,
        repositorio: InfraestruturaFalso.fixture(),
        permissoes: secretaria,
      );
      await abrirSala(tester, 'Laboratório 1');
      await tester.tap(find.text('LAB1-01'));
      await tester.pumpAndSettle();
      expect(find.text('Sem credencial cadastrada.'), findsOneWidget);
      expect(find.text('Gravar credencial'), findsNothing);
      expect(find.text('Ver credencial'), findsNothing);
    });

    testWidgets('gravar e depois ver: o par vai ao repositório, o carimbo '
        'aparece e a leitura é registrada', (tester) async {
      final repositorio = InfraestruturaFalso.fixture();
      await montar(tester, repositorio: repositorio, permissoes: direcao);
      await abrirSala(tester, 'Laboratório 1');
      await tester.tap(find.text('LAB1-01'));
      await tester.pumpAndSettle();
      expect(find.text('Gravar credencial'), findsOneWidget);
      expect(find.text('Ver credencial'), findsNothing, reason: 'sem par');

      await tester.tap(find.text('Gravar credencial'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Usuário *'),
        'lab1@escola',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha *'),
        'segredo-1',
      );
      await tester.tap(find.byKey(chaveBotaoSalvar).last);
      await carregar(tester);
      expect(repositorio.credenciais['pc-lab1-01']?.usuario, 'lab1@escola');
      expect(repositorio.credenciais['pc-lab1-01']?.senha, 'segredo-1');
      expect(find.text('Credencial gravada.'), findsOneWidget);
      expect(
        find.textContaining('Credencial cadastrada · atualizada em'),
        findsOneWidget,
        reason: 'a ficha recarregou o carimbo',
      );
      expect(find.text('Rotacionar credencial'), findsOneWidget);

      expect(repositorio.chamadas, isNot(contains('lerCredencial')));
      await tester.tap(find.text('Ver credencial'));
      await tester.pumpAndSettle();
      expect(find.text('Credencial de LAB1-01'), findsOneWidget);
      expect(find.text('lab1@escola'), findsOneWidget);
      expect(find.text('segredo-1'), findsOneWidget);
      expect(repositorio.chamadas.where((c) => c == 'lerCredencial'), [
        'lerCredencial',
      ], reason: 'uma leitura, uma linha de acesso');
    });
  });

  group('professores', () {
    testWidgets('a aba lista só os ativos e o botão segue professores.criar', (
      tester,
    ) async {
      await montar(tester, repositorio: InfraestruturaFalso.fixture());
      await tester.tap(find.text('Professores'));
      await carregar(tester);
      expect(find.text('Marcos Vieira'), findsOneWidget);
      expect(find.text('Renata Alves'), findsOneWidget);
      expect(find.text('Otávio Pacheco'), findsNothing);
      expect(find.text('Novo professor'), findsNothing);
    });

    testWidgets('novo professor grava; o existente abre sem "Excluir"', (
      tester,
    ) async {
      final repositorio = InfraestruturaFalso.fixture();
      await montar(tester, repositorio: repositorio, permissoes: secretaria);
      await tester.tap(find.text('Professores'));
      await carregar(tester);
      await tester.tap(find.text('Novo professor'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome *'),
        'Paula Nunes',
      );
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);
      expect(
        repositorio.professores_.any((p) => p.nome == 'Paula Nunes'),
        true,
      );
      expect(find.text('Professor salvo.'), findsOneWidget);
      expect(find.text('Paula Nunes'), findsOneWidget);

      await tester.tap(find.text('Marcos Vieira'));
      await tester.pumpAndSettle();
      expect(find.text('Professor'), findsWidgets);
      expect(find.text('Excluir'), findsNothing);
      expect(find.byKey(chaveBotaoSalvar), findsOneWidget);
    });

    testWidgets('estado vazio com o texto do card 2.7', (tester) async {
      await montar(tester, repositorio: InfraestruturaFalso());
      await tester.tap(find.text('Professores'));
      await carregar(tester);
      expect(find.text(vazioProfessores), findsOneWidget);
      expect(find.text('+ Novo professor'), findsNothing);
    });
  });

  testWidgets('no mobile a lista vira cartões com o botão Filtrar (n)', (
    tester,
  ) async {
    await montar(
      tester,
      repositorio: InfraestruturaFalso.fixture(),
      tamanho: const Size(390, 800),
    );
    expect(find.text('Filtrar (1)'), findsOneWidget);
    expect(find.text('Cap. efetiva'), findsNothing);
    expect(find.text('cap. 4'), findsOneWidget);
    expect(find.text('Laboratório · 4/6 PCs operacionais'), findsOneWidget);
  });
}
