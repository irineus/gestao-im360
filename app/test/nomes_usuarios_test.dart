import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/sessao/nomes_usuarios.dart';

/// O "quem" dos históricos (card 9.2,74): o nome entra na linha no MESMO
/// formato do embed antigo, e os `deLinha` dos modelos não mudam.
void main() {
  const nomes = {'u-1': 'Débora Lima', 'u-2': 'Direção A'};

  test('o id vira o embed {nome: …} na chave pedida', () {
    final linha = comNomes(
      {'id': 'h-1', 'usuario_id': 'u-2'},
      nomes,
      colunaParaEmbed: const {'usuario_id': 'usuario'},
    );
    expect(linha['usuario'], {'nome': 'Direção A'});
    expect(linha['usuario_id'], 'u-2', reason: 'a coluna original fica');
  });

  test(
    'sem autor, ou autor fora da unidade: nulo — a tela omite o "por …"',
    () {
      final linha = comNomes(
        {'pedagogico_por': null, 'financeiro_por': 'u-de-outra-unidade'},
        nomes,
        colunaParaEmbed: const {
          'pedagogico_por': 'pedagogico_usuario',
          'financeiro_por': 'financeiro_usuario',
        },
      );
      expect(linha['pedagogico_usuario'], isNull);
      expect(linha['financeiro_usuario'], isNull);
    },
  );

  test(
    'a chave do nome nunca sobrescreve uma coluna (formatura é booleana)',
    () {
      final linha = comNomes(
        {'formatura': true, 'formatura_por': 'u-1'},
        nomes,
        colunaParaEmbed: const {'formatura_por': 'formatura_usuario'},
      );
      expect(linha['formatura'], isTrue);
      expect(linha['formatura_usuario'], {'nome': 'Débora Lima'});
    },
  );
}
