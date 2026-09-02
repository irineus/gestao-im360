import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/erros/erro_app.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/widgets/botoes.dart';
import 'package:gestao_im360/widgets/formulario.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `FormularioIm360` (design-system §5.4): validação local só de formato, erro
/// de regra como banner pelo `codigo`, primário travado enquanto executa, e
/// "somente leitura" sem botão de salvar.
void main() {
  Object? resultado;

  Future<void> abrir(
    WidgetTester tester, {
    Future<Object?> Function()? aoSalvar,
    List<AcaoFormulario> acoes = const [],
    bool somenteLeitura = false,
    Set<String> permissoes = const {'materiais.excluir'},
    Size tamanho = const Size(1400, 900),
  }) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    resultado = null;
    final chave = GlobalKey<FormState>();
    final controlador = TextEditingController();
    addTearDown(controlador.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [permissoesProvider.overrideWithValue(permissoes)],
        child: MaterialApp(
          theme: temaClaro(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  resultado = await mostrarFormulario<Object>(
                    context,
                    construtor: (_) => FormularioIm360(
                      titulo: 'Teste',
                      chave: chave,
                      somenteLeitura: somenteLeitura,
                      acoes: acoes,
                      campos: [
                        TextFormField(
                          controller: controlador,
                          decoration: const InputDecoration(
                            labelText: 'Nome *',
                          ),
                          validator: validarObrigatorio,
                        ),
                      ],
                      aoSalvar: aoSalvar,
                    ),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Finder salvar() => find.byKey(chaveBotaoSalvar);

  testWidgets('validação de formato barra o envio', (tester) async {
    var salvou = false;
    await abrir(
      tester,
      aoSalvar: () async {
        salvou = true;
        return null;
      },
    );
    await tester.tap(salvar());
    await tester.pumpAndSettle();
    expect(find.text('Campo obrigatório.'), findsOneWidget);
    expect(salvou, isFalse);
    expect(find.text('* obrigatório'), findsOneWidget);
  });

  testWidgets('salvar com sucesso fecha com o resultado (true se nulo)', (
    tester,
  ) async {
    await abrir(tester, aoSalvar: () async => null);
    await tester.enterText(find.byType(TextFormField), 'x');
    await tester.tap(salvar());
    await tester.pumpAndSettle();
    expect(resultado, isTrue);
    expect(find.text('Teste'), findsNothing, reason: 'fechou');
  });

  testWidgets('erro do banco vira banner traduzido e o botão volta', (
    tester,
  ) async {
    await abrir(
      tester,
      aoSalvar: () async => throw const PostgrestException(
        message: 'duplicate key',
        code: '23505',
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'x');
    await tester.tap(salvar());
    await tester.pumpAndSettle();
    expect(find.text(mensagensIntegridade['23505']!), findsOneWidget);
    expect(find.text('Teste'), findsOneWidget, reason: 'continua aberto');
    expect(tester.widget<FilledButton>(salvar()).onPressed, isNotNull);
  });

  testWidgets('enquanto executa, o primário trava — duplo clique não grava '
      'duas vezes', (tester) async {
    final trava = Completer<void>();
    var chamadas = 0;
    await abrir(
      tester,
      aoSalvar: () async {
        chamadas++;
        await trava.future;
        return 'ok';
      },
    );
    await tester.enterText(find.byType(TextFormField), 'x');
    await tester.tap(salvar());
    await tester.pump();
    expect(tester.widget<FilledButton>(salvar()).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(salvar(), warnIfMissed: false);
    trava.complete();
    await tester.pumpAndSettle();
    expect(chamadas, 1);
    expect(resultado, 'ok');
  });

  testWidgets('somente leitura: sem Salvar, com Fechar, sem legenda', (
    tester,
  ) async {
    await abrir(tester, aoSalvar: () async => null, somenteLeitura: true);
    expect(salvar(), findsNothing);
    expect(find.text('Fechar'), findsOneWidget);
    expect(find.text('Cancelar'), findsNothing);
    expect(find.text('* obrigatório'), findsNothing);
  });

  group('ação extra', () {
    testWidgets('sem permissão a ação não é renderizada', (tester) async {
      await abrir(
        tester,
        permissoes: const {},
        acoes: [
          AcaoFormulario(
            rotulo: 'Excluir',
            exigePermissao: 'materiais.excluir',
            nivel: NivelBotao.destrutivo,
            executar: () async => 'excluido',
          ),
        ],
      );
      expect(find.text('Excluir'), findsNothing);
    });

    testWidgets('com confirmação: cancelar não executa; confirmar executa e '
        'fecha com o resultado', (tester) async {
      var executou = 0;
      await abrir(
        tester,
        acoes: [
          AcaoFormulario(
            rotulo: 'Excluir',
            exigePermissao: 'materiais.excluir',
            nivel: NivelBotao.destrutivo,
            confirmacao: const ConfirmacaoAcao(
              titulo: 'Excluir item?',
              mensagem: 'Vai sumir.',
              rotulo: 'Excluir mesmo',
            ),
            executar: () async {
              executou++;
              return 'excluido';
            },
          ),
        ],
      );
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();
      expect(find.text('Excluir item?'), findsOneWidget);
      await tester.tap(find.text('Cancelar').last);
      await tester.pumpAndSettle();
      expect(executou, 0);
      expect(find.text('Teste'), findsOneWidget);

      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir mesmo'));
      await tester.pumpAndSettle();
      expect(executou, 1);
      expect(resultado, 'excluido');
    });

    testWidgets('a ação também traduz erro para o banner', (tester) async {
      await abrir(
        tester,
        acoes: [
          AcaoFormulario(
            rotulo: 'Excluir',
            executar: () async =>
                throw const PostgrestException(message: 'fk', code: '23503'),
          ),
        ],
      );
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();
      expect(find.text(mensagensIntegridade['23503']!), findsOneWidget);
    });
  });

  group('validadores', () {
    test('obrigatório recusa vazio e espaços', () {
      expect(validarObrigatorio(null), isNotNull);
      expect(validarObrigatorio('  '), isNotNull);
      expect(validarObrigatorio('a'), isNull);
    });

    test('inteiro não negativo', () {
      expect(validarInteiroNaoNegativo(''), isNotNull);
      expect(validarInteiroNaoNegativo('-1'), isNotNull);
      expect(validarInteiroNaoNegativo('1.5'), isNotNull);
      expect(validarInteiroNaoNegativo('0'), isNull);
      expect(validarInteiroNaoNegativo('12'), isNull);
    });
  });

  testWidgets('no mobile o formulário abre em tela cheia', (tester) async {
    await abrir(
      tester,
      aoSalvar: () async => null,
      tamanho: const Size(390, 800),
    );
    expect(find.byType(Dialog), findsOneWidget);
    final dialogo = tester.getSize(find.byType(Dialog));
    expect(dialogo.width, 390);
  });
}
