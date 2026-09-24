import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/erros/catalogo_erros.dart';

/// O lado Dart do contrato do card 2.8 §10.
///
/// O outro lado é o C12 (SQL): o conjunto de `codigo` que aparece no DETAIL das
/// funções é exatamente o do mesmo arquivo. Um card que cria erro novo toca
/// três arquivos e os dois testes reprovam enquanto faltar um.
void main() {
  final fixture = File('../test/fixtures/codigos_erro.txt');

  late List<String> codigos;

  setUpAll(() {
    expect(
      fixture.existsSync(),
      isTrue,
      reason:
          'o fixture de contrato mora na raiz do repositório, em '
          'test/fixtures/codigos_erro.txt — os dois consumidores são o banco e '
          'o app, e ele não é de nenhum dos dois sozinho',
    );
    codigos = fixture
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();
  });

  test('todo código do fixture tem mensagem no catálogo', () {
    final semMensagem = codigos
        .where((c) => !CatalogoErros.mensagens.containsKey(c))
        .toList();
    expect(
      semMensagem,
      isEmpty,
      reason:
          'código sem tradução aparece em tela como "não foi possível '
          'concluir", que tem cara de problema de rede',
    );
  });

  test('o catálogo não tem mensagem para código que não existe mais', () {
    final orfaos = CatalogoErros.mensagens.keys
        .where((c) => !codigos.contains(c))
        .toList();
    expect(
      orfaos,
      isEmpty,
      reason:
          'mensagem sem código correspondente é código morto — e esconde '
          'um erro de digitação no nome',
    );
  });

  // Card 9.2,73: o elo que faltava. O banco não lê o fixture, então o pgTAP
  // `012_catalogo_contratos` compara o que as funções levantam com uma lista
  // própria; este teste amarra essa lista ao fixture. Com os dois, código
  // novo no banco e esquecido aqui reprova — antes chegava à tela como o texto
  // cru do Postgres.
  test('a lista do pgTAP 012 é o fixture, código por código', () {
    final sql = File('../supabase/tests/012_catalogo_contratos.sql')
        .readAsStringSync()
        .replaceAll(String.fromCharCode(13), '');
    final inicio = sql.indexOf('-- <catalogo>');
    final fim = sql.indexOf('-- </catalogo>');
    expect(inicio, greaterThan(-1), reason: 'marca <catalogo> sumiu do 012');
    expect(fim, greaterThan(inicio), reason: 'marca </catalogo> sumiu do 012');
    final daLista = RegExp(r"'([A-Z0-9_]+)'")
        .allMatches(sql.substring(inicio, fim))
        .map((m) => m.group(1)!)
        .toSet();
    expect(daLista, codigos.toSet());
  });

  test('o fixture não tem código repetido', () {
    expect(codigos.toSet().length, codigos.length);
  });

  test('código não mapeado cai no fallback E exibe o código', () {
    final texto = CatalogoErros.mensagem('CODIGO_QUE_NAO_EXISTE');
    expect(texto, contains('CODIGO_QUE_NAO_EXISTE'));
    expect(CatalogoErros.mapeado('CODIGO_QUE_NAO_EXISTE'), isFalse);
  });

  test('código nulo (erro sem DETAIL) ainda produz mensagem legível', () {
    expect(CatalogoErros.mensagem(null), isNot(contains('{codigo}')));
  });

  test('PARAMETRO_AUSENTE diz qual chave falta', () {
    final texto = CatalogoErros.mensagem(
      'PARAMETRO_AUSENTE',
      valores: {'chave': 'rep_prazo_dias'},
    );
    expect(texto, contains('rep_prazo_dias'));
    expect(texto, isNot(contains('{chave}')));
  });

  test('nenhuma mensagem fica com marcação {…} por preencher', () {
    // Exceto as que dependem de valor do DETAIL, declaradas aqui de propósito:
    // esquecer de preencher uma marcação exibe "{chave}" ao usuário.
    const comMarcacaoEsperada = {'PARAMETRO_AUSENTE'};
    for (final entrada in CatalogoErros.mensagens.entries) {
      if (comMarcacaoEsperada.contains(entrada.key)) continue;
      expect(
        entrada.value,
        isNot(contains('{')),
        reason: '${entrada.key} tem marcação que ninguém preenche',
      );
    }
  });
}
