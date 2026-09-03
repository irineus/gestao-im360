import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/administracao/administracao.dart';
import 'package:gestao_im360/administracao/administracao_provider.dart';
import 'package:gestao_im360/erros/catalogo_erros.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/administracao/aba_matriz.dart';
import 'package:gestao_im360/telas/administracao/aba_usuarios.dart';
import 'package:gestao_im360/telas/administracao/formularios.dart';
import 'package:gestao_im360/telas/administracao/tela_administracao.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/widgets/formulario.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'apoio/administracao_falso.dart';
import 'apoio/carregar.dart';

/// A obrigação de teste de um card de **Tela** (card 2.8 §13): ocultação por
/// permissão e os textos do card 2.7 — a guarda de rota (`admin.ler`) já está
/// tabelada em `guardas_rota_test.dart`. Mais o que esta tela tem de próprio:
/// quem está SEM PERFIL aparece (ajuste do card 3.7), o convite chega ao
/// repositório com o destino certo e já atribui perfis, a matriz marca e
/// desmarca (com o aviso de que vale na hora), o parâmetro valida pelo tipo e
/// avisa o efeito, e o histórico do card 4.7.5 lista quem fez o quê.
void main() {
  // A matriz inicial do card 2.4 §5 recortada ao que esta tela consome.
  const leitura = {'admin.ler', 'parametros.ler'};
  const direcao = {
    ...leitura,
    'admin.gerir_usuarios',
    'admin.gerir_perfis',
    'parametros.gerir',
  };

  Future<void> montar(
    WidgetTester tester, {
    required AdministracaoFalso repositorio,
    Set<String> permissoes = leitura,
    Size tamanho = const Size(1400, 900),
  }) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          administracaoRepositorioProvider.overrideWithValue(repositorio),
          permissoesProvider.overrideWithValue(permissoes),
          unidadeAtualProvider.overrideWithValue('unidade-teste'),
          resumoUsuarioProvider.overrideWithValue(
            const ResumoUsuario(nome: 'Direção A', unidade: 'Escola A'),
          ),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          home: const Scaffold(body: TelaAdministracao()),
        ),
      ),
    );
    await carregar(tester);
  }

  Future<void> aba(WidgetTester tester, String nome) async {
    await tester.tap(find.text(nome));
    await carregar(tester);
  }

  group('usuários', () {
    testWidgets('a lista mostra QUEM ESTÁ SEM PERFIL — na linha e no aviso', (
      tester,
    ) async {
      await montar(tester, repositorio: AdministracaoFalso.fixture());
      expect(find.text('Débora Lima'), findsOneWidget);
      expect(find.text('SECRETARIA'), findsOneWidget);
      expect(find.text('⚠ sem perfil'), findsOneWidget);
      expect(find.text(avisoSemPerfil(1)), findsOneWidget);
      expect(find.text('Sem perfil (1)'), findsOneWidget);
      // Desativado fica fora por padrão ("Só ativos").
      expect(find.text('Antigo Diretor'), findsNothing);
    });

    testWidgets('sem admin.gerir_usuarios não há "Convidar usuário" e a ficha '
        'abre só para ver', (tester) async {
      await montar(tester, repositorio: AdministracaoFalso.fixture());
      expect(find.text('Convidar usuário'), findsNothing);
      await tester.tap(find.text('Débora Lima'));
      await tester.pumpAndSettle();
      expect(find.text('Usuário'), findsOneWidget);
      expect(find.byKey(chaveBotaoSalvar), findsNothing);
      expect(find.text('Fechar'), findsOneWidget);
    });

    testWidgets('o filtro "Sem perfil" deixa só quem não tem', (tester) async {
      await montar(tester, repositorio: AdministracaoFalso.fixture());
      await tester.tap(find.text('Sem perfil (1)'));
      await tester.pumpAndSettle();
      expect(find.text('semperfil'), findsOneWidget);
      expect(find.text('Débora Lima'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'zzz');
      await tester.pumpAndSettle();
      expect(find.text(vazioUsuariosFiltro), findsOneWidget);
      await tester.tap(find.text('Limpar filtros'));
      await tester.pumpAndSettle();
      expect(find.text('Antigo Diretor'), findsOneWidget, reason: 'tudo');
    });

    testWidgets('editar: nome e perfis vão ao repositório como plano — inserir '
        'o que falta, remover o que sobra', (tester) async {
      final repositorio = AdministracaoFalso.fixture();
      await montar(tester, repositorio: repositorio, permissoes: direcao);
      await tester.tap(find.text('Débora Lima'));
      await tester.pumpAndSettle();
      expect(find.text(avisoEmailImutavel), findsOneWidget);
      await tester.enterText(find.byKey(chaveCampoNome), 'Débora Lima Souza');
      await tester.tap(find.byKey(const ValueKey('perfil-MONITOR')));
      await tester.tap(find.byKey(const ValueKey('perfil-SECRETARIA')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      expect(
        repositorio.chamadas,
        containsAllInOrder(['salvarUsuario', 'definirPerfis']),
      );
      final debora = repositorio.usuarios_.singleWhere(
        (u) => u.id == 'u-secretaria',
      );
      expect(debora.nome, 'Débora Lima Souza');
      expect(debora.perfisIds, {'p-monitor'});
      expect(find.text('Usuário salvo.'), findsOneWidget);
      expect(find.text('MONITOR'), findsNWidgets(2), reason: 'recarregou');
    });

    testWidgets(
      'desativar mostra o aviso do token de 1 h e grava ativo=false',
      (tester) async {
        final repositorio = AdministracaoFalso.fixture();
        await montar(tester, repositorio: repositorio, permissoes: direcao);
        await tester.tap(find.text('Caio Prado'));
        await tester.pumpAndSettle();
        expect(find.text(avisoDesativar), findsNothing);
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(find.text(avisoDesativar), findsOneWidget);
        await tester.tap(find.byKey(chaveBotaoSalvar));
        await carregar(tester);
        final caio = repositorio.usuarios_.singleWhere(
          (u) => u.id == 'u-monitor',
        );
        expect(caio.ativo, isFalse);
        expect(repositorio.chamadas, isNot(contains('definirPerfis')));
      },
    );

    testWidgets('convite: e-mail, nome e destino chegam à função, e o perfil '
        'marcado é atribuído no mesmo ato', (tester) async {
      final repositorio = AdministracaoFalso.fixture();
      await montar(tester, repositorio: repositorio, permissoes: direcao);
      await tester.tap(find.text('Convidar usuário'));
      await tester.pumpAndSettle();
      expect(find.text(avisoConvite), findsOneWidget);
      await tester.enterText(find.byKey(chaveCampoEmail), 'Nova@Escola.test');
      await tester.enterText(find.byKey(chaveCampoNome), 'Nova Pessoa');
      await tester.tap(find.byKey(const ValueKey('perfil-SECRETARIA')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);

      expect(repositorio.convites, hasLength(1));
      final (email, nome, destino) = repositorio.convites.single;
      expect(email, 'Nova@Escola.test');
      expect(nome, 'Nova Pessoa');
      expect(destino, endsWith('/redefinir-senha'));
      expect(
        repositorio.chamadas,
        containsAllInOrder(['convidar', 'definirPerfis']),
      );
      final nova = repositorio.usuarios_.singleWhere(
        (u) => u.email == 'Nova@Escola.test',
      );
      expect(nova.perfisIds, {'p-secretaria'});
      expect(find.text('Convite enviado.'), findsOneWidget);
      expect(find.text('Nova Pessoa'), findsOneWidget, reason: 'recarregou');
    });

    testWidgets('reenviar o convite a quem já existe não repete o perfil que '
        'a pessoa já tem', (tester) async {
      final repositorio = AdministracaoFalso.fixture();
      await montar(tester, repositorio: repositorio, permissoes: direcao);
      await tester.tap(find.text('Convidar usuário'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(chaveCampoEmail),
        'secretaria@escola-a.test',
      );
      await tester.enterText(find.byKey(chaveCampoNome), 'Débora Lima');
      await tester.tap(find.byKey(const ValueKey('perfil-SECRETARIA')));
      await tester.tap(find.byKey(const ValueKey('perfil-MONITOR')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);
      expect(repositorio.convites, hasLength(1), reason: 'reenviou');
      final debora = repositorio.usuarios_.singleWhere(
        (u) => u.id == 'u-secretaria',
      );
      expect(debora.perfisIds, {'p-secretaria', 'p-monitor'});
      expect(
        repositorio.usuarios_.where(
          (u) => u.email == 'secretaria@escola-a.test',
        ),
        hasLength(1),
        reason: 'não duplicou o usuário',
      );
    });

    testWidgets('a recusa da função chega como banner pelo código — o mesmo '
        'texto da RLS', (tester) async {
      final repositorio = AdministracaoFalso.fixture()
        ..falhaAoConvidar = const FunctionException(
          status: 403,
          details: {
            'codigo': 'SEM_PERMISSAO',
            'permissao': 'admin.gerir_usuarios',
          },
        );
      await montar(tester, repositorio: repositorio, permissoes: direcao);
      await tester.tap(find.text('Convidar usuário'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(chaveCampoEmail), 'x@y.test');
      await tester.enterText(find.byKey(chaveCampoNome), 'X');
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await tester.pumpAndSettle();
      expect(
        find.text(CatalogoErros.mensagens['SEM_PERMISSAO']!),
        findsOneWidget,
      );
      expect(repositorio.convites, isEmpty);
    });

    testWidgets('e-mail já cadastrado: o code do GoTrue vira texto, não código '
        'cru', (tester) async {
      final repositorio = AdministracaoFalso.fixture()
        ..falhaAoConvidar = const FunctionException(
          status: 422,
          details: {'code': 'email_exists', 'mensagem': 'already registered'},
        );
      await montar(tester, repositorio: repositorio, permissoes: direcao);
      await tester.tap(find.text('Convidar usuário'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(chaveCampoEmail), 'x@y.test');
      await tester.enterText(find.byKey(chaveCampoNome), 'X');
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await tester.pumpAndSettle();
      expect(
        find.text('Já existe um usuário com este e-mail.'),
        findsOneWidget,
      );
      expect(find.textContaining('email_exists'), findsNothing);
    });
  });

  group('perfis e matriz', () {
    testWidgets('sem admin.gerir_perfis a matriz é só leitura: caixas '
        'desabilitadas, sem "Novo perfil"', (tester) async {
      await montar(tester, repositorio: AdministracaoFalso.fixture());
      await aba(tester, 'Perfis e matriz');
      expect(find.text(cabecalhoCatalogo), findsOneWidget);
      expect(
        find.text('7 de 7 permissões marcadas para DIRECAO'),
        findsOneWidget,
      );
      expect(find.text('Novo perfil'), findsNothing);
      expect(find.text('Editar perfil'), findsNothing);
      final caixa = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('caixa-alunos.ler')),
      );
      expect(caixa.onChanged, isNull);
      expect(caixa.value, isTrue);
      // A descrição aparece ao lado do código (card 2.4 §8).
      expect(
        find.text('Ler aluno, histórico de status e trilha'),
        findsOneWidget,
      );
      // Agrupado pelos domínios, na ordem do menu.
      expect(find.text('Alunos'), findsOneWidget);
      expect(find.text('Administração'), findsOneWidget);
    });

    testWidgets('marcar grava; desmarcar pede confirmação com o aviso de que '
        'vale na hora, e então grava', (tester) async {
      final repositorio = AdministracaoFalso.fixture();
      await montar(tester, repositorio: repositorio, permissoes: direcao);
      await aba(tester, 'Perfis e matriz');

      // Troca para a SECRETARIA pelo menu.
      await tester.tap(find.byType(DropdownMenu<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SECRETARIA — Secretaria').last);
      await carregar(tester);
      expect(
        find.text('3 de 7 permissões marcadas para SECRETARIA'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('caixa-alunos.reverter_status')),
      );
      await carregar(tester);
      expect(repositorio.chamadas, contains('marcar'));
      expect(
        repositorio.matriz_['p-secretaria'],
        contains('pm-alunos-reverter'),
      );
      expect(
        find.text('4 de 7 permissões marcadas para SECRETARIA'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('caixa-estoque.ajustar')));
      await tester.pumpAndSettle();
      expect(find.text('Desmarcar estoque.ajustar?'), findsOneWidget);
      expect(find.textContaining(avisoDesmarcar), findsOneWidget);
      expect(repositorio.chamadas, isNot(contains('desmarcar')));
      await tester.tap(find.widgetWithText(FilledButton, 'Desmarcar'));
      await carregar(tester);
      expect(repositorio.chamadas, contains('desmarcar'));
      expect(
        repositorio.matriz_['p-secretaria'],
        isNot(contains('pm-estoque-ajustar')),
      );
      expect(
        find.text('3 de 7 permissões marcadas para SECRETARIA'),
        findsOneWidget,
      );
    });

    testWidgets('perfil desativado mostra o aviso; novo perfil grava e passa a '
        'ser o selecionado', (tester) async {
      final repositorio = AdministracaoFalso.fixture();
      await montar(tester, repositorio: repositorio, permissoes: direcao);
      await aba(tester, 'Perfis e matriz');
      await tester.tap(find.byType(DropdownMenu<String>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('ARQUIVADO — Perfil desativado (desativado)').last,
      );
      await carregar(tester);
      expect(find.text(avisoPerfilDesativado), findsOneWidget);

      await tester.tap(find.text('Novo perfil'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Código *'),
        'coordenacao',
      );
      await tester.enterText(find.byKey(chaveCampoNome), 'Coordenação');
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);
      final novo = repositorio.perfis_.singleWhere(
        (p) => p.nome == 'Coordenação',
      );
      expect(novo.codigo, 'COORDENACAO', reason: 'caixa alta');
      expect(find.text('Perfil salvo.'), findsOneWidget);
      expect(
        find.text('0 de 7 permissões marcadas para COORDENACAO'),
        findsOneWidget,
      );
    });
  });

  group('parâmetros', () {
    testWidgets('lista chave, valor e descrição; sem parametros.gerir a ficha '
        'só mostra — e mostra o aviso da rotina', (tester) async {
      await montar(tester, repositorio: AdministracaoFalso.fixture());
      await aba(tester, 'Parâmetros');
      expect(find.text('projecao_horizonte_dias'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('Novo parâmetro'), findsNothing);
      await tester.tap(find.text('projecao_horizonte_dias'));
      await tester.pumpAndSettle();
      expect(find.text(avisoParametroRotina), findsOneWidget);
      expect(find.byKey(chaveBotaoSalvar), findsNothing);
    });

    testWidgets('valor validado pelo tipo; o inteiro gravado como texto', (
      tester,
    ) async {
      final repositorio = AdministracaoFalso.fixture();
      await montar(tester, repositorio: repositorio, permissoes: direcao);
      await aba(tester, 'Parâmetros');
      await tester.tap(find.text('standby_alerta_dias'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo_valor')), 'abc');
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await tester.pumpAndSettle();
      expect(find.text('Informe um número inteiro.'), findsOneWidget);
      expect(repositorio.chamadas, isNot(contains('salvarParametro')));

      await tester.enterText(find.byKey(const Key('campo_valor')), '45');
      await tester.tap(find.byKey(chaveBotaoSalvar));
      await carregar(tester);
      final salvo = repositorio.parametros_.singleWhere(
        (p) => p.chave == 'standby_alerta_dias',
      );
      expect(salvo.valor, '45');
      expect(find.text('Parâmetro salvo.'), findsOneWidget);
      expect(find.text('45'), findsOneWidget, reason: 'recarregou');
    });

    testWidgets('parâmetro de texto não recebe o aviso da rotina', (
      tester,
    ) async {
      await montar(tester, repositorio: AdministracaoFalso.fixture());
      await aba(tester, 'Parâmetros');
      await tester.tap(find.text('direcao_inicial_email'));
      await tester.pumpAndSettle();
      expect(find.text(avisoParametroRotina), findsNothing);
    });
  });

  group('histórico (card 4.7.5)', () {
    testWidgets('lista quem fez o quê, e "sistema" para o seed', (
      tester,
    ) async {
      await montar(tester, repositorio: AdministracaoFalso.fixture());
      await aba(tester, 'Histórico');
      expect(find.text('compras.receber'), findsNWidgets(2));
      expect(find.text('Removida'), findsOneWidget);
      expect(find.text('Concedida'), findsOneWidget);
      expect(find.text('Direção A'), findsOneWidget);
      expect(find.text('sistema (seed)'), findsOneWidget);
      expect(find.text('03/09/2026 10:15'), findsOneWidget);
    });
  });
}
