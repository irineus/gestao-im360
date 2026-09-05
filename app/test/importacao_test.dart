import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/importacao/importacao.dart';
import 'package:gestao_im360/telas/importacao/textos_importacao.dart';

import 'apoio/importacao_falso.dart';

/// A lógica **pura** da importação (card 9.1): abrir o arquivo, contar o que
/// ele traz, ordenar o relatório e montar o CSV.
///
/// ⚠️ Nada aqui valida negócio. Quem valida é `fn_importacao_validar`, com as
/// dezesseis verificações medidas em `supabase/tests/100_importacao.sql` — este
/// arquivo mede só o que roda no navegador, que é a leitura do arquivo.
void main() {
  group('abrir o arquivo', () {
    test('um arquivo bem formado vira dados e sugere o snapshot', () {
      final lido = ArquivoImportacao.deTexto(arquivoDeTeste);
      expect(lido.valido, isTrue);
      expect(lido.erro, isNull);
      // Data LOCAL, não UTC: `2026-08-29` sem hora é uma data do calendário da
      // escola, e convertê-la para UTC a deslocaria um dia em metade do mundo —
      // a mesma armadilha das 21h que o C6 varre no banco (card 2.3 §3.3).
      expect(lido.snapshotEm, DateTime(2026, 8, 29));
      expect(lido.totalLinhas, 2);
    });

    test('as contagens saem na ordem de aplicação, não na do arquivo', () {
      // No texto, `aluno` vem antes de `material`; na ordem de dependência é o
      // contrário — e é essa que a tela mostra, porque é a ordem dos fatos.
      final lido = ArquivoImportacao.deTexto(arquivoDeTeste);
      expect(lido.contagens.map((c) => c.key), ['material', 'aluno']);
    });

    test('arquivo vazio diz que está vazio, e não "JSON inválido"', () {
      final lido = ArquivoImportacao.deTexto('   ');
      expect(lido.valido, isFalse);
      expect(lido.erro, contains('vazio'));
    });

    test('JSON quebrado informa a posição', () {
      final lido = ArquivoImportacao.deTexto('{"aluno": [');
      expect(lido.valido, isFalse);
      expect(lido.erro, contains('posição'));
    });

    test('um array na raiz é recusado — a raiz é um objeto por entidade', () {
      final lido = ArquivoImportacao.deTexto('[{"codigo": "1"}]');
      expect(lido.valido, isFalse);
      expect(lido.erro, contains('objeto JSON'));
    });

    test('objeto sem nenhuma entidade conhecida é recusado', () {
      // O caso real: o extrator do card 9.2 renomeia tudo e a importação
      // responderia "0 linhas aplicadas, tudo certo".
      final lido = ArquivoImportacao.deTexto('{"alunos": [], "materiais": []}');
      expect(lido.valido, isFalse);
      expect(lido.erro, contains('entidades conhecidas'));
    });

    test('entidade desconhecida ao lado de conhecidas é AVISO, não recusa', () {
      final lido = ArquivoImportacao.deTexto(
        '{"aluno": [{"codigo": "1"}], "aba_nova": []}',
      );
      expect(lido.valido, isTrue);
      expect(lido.entidadesDesconhecidas, ['aba_nova']);
      // `snapshot_em` é chave de contrato, não entidade: não pode aparecer aqui.
      final comSnapshot = ArquivoImportacao.deTexto(arquivoDeTeste);
      expect(comSnapshot.entidadesDesconhecidas, isEmpty);
    });

    test('entidade que veio como objeto em vez de lista não é contada', () {
      // Quem reprova isto é a verificação V1 do banco, com ERRO. Aqui ela só
      // não pode ser contada como se fosse uma lista de zero linhas.
      final lido = ArquivoImportacao.deTexto(
        '{"aluno": [{"codigo": "1"}], "material": {"codigo": "01"}}',
      );
      expect(lido.contagens.map((c) => c.key), ['aluno']);
    });
  });

  group('o relatório', () {
    test('ERRO vem antes de AVISO, e depois pela ordem de aplicação', () {
      final ordenadas = ordenarOcorrencias([
        ocorrencia(severidade: 'AVISO', entidade: 'aluno', linha: 2),
        ocorrencia(severidade: 'ERRO', entidade: 'aluno', linha: 9),
        ocorrencia(severidade: 'ERRO', entidade: 'material', linha: 1),
      ]);
      expect(ordenadas.map((o) => '${o.severidade}/${o.entidade}'), [
        'ERRO/material',
        'ERRO/aluno',
        'AVISO/aluno',
      ]);
    });

    test('o CSV escapa o que quebraria a planilha de quem o abrir', () {
      final csv = relatorioEmCsv([
        ocorrencia(
          severidade: 'ERRO',
          mensagem: 'aluno "X"; sem turma',
          linha: 3,
        ),
      ]);
      expect(
        csv,
        startsWith('severidade;entidade;linha;codigo;mensagem;valor'),
      );
      expect(csv, contains('"aluno ""X""; sem turma"'));
    });
  });

  group('os totais do passo 4', () {
    test('juntam o que veio do arquivo com o que existe no sistema', () {
      final totais = lerTotais(totaisDeTeste);
      expect(totais.map((t) => t.entidade), ['material', 'aluno']);
      final aluno = totais.firstWhere((t) => t.entidade == 'aluno');
      expect(aluno.arquivo, 1);
      expect(aluno.aplicadas, 1);
      expect(aluno.noSistema, 265);
    });

    test('lote sem totais não derruba a tela', () {
      expect(lerTotais(null), isEmpty);
      expect(lerTotais(const {'no_sistema': null}), isEmpty);
    });

    test('totais sem `no_sistema` mostram zero, e não erro', () {
      final totais = lerTotais(const {
        'aluno': {'arquivo': 3, 'aplicadas': 2, 'ignoradas': 1},
      });
      expect(totais.single.noSistema, 0);
      expect(totais.single.ignoradas, 1);
    });
  });

  group('rótulos', () {
    test('o ambiente de produção é dito em caixa alta', () {
      expect(rotuloAmbiente('producao'), 'PRODUÇÃO');
      expect(rotuloAmbiente('homologacao'), 'homologação');
      expect(rotuloAmbiente('local'), 'ambiente local');
    });

    test('ambiente desconhecido volta como veio, sem inventar rótulo', () {
      expect(rotuloAmbiente('staging'), 'staging');
    });

    test('as dezoito entidades têm rótulo em português', () {
      for (final entidade in entidadesImportacao) {
        expect(
          rotuloEntidade(entidade),
          isNot(entidade),
          reason: '$entidade apareceria em tela com o nome da tabela',
        );
      }
    });

    test('os quatro status do lote têm rótulo', () {
      for (final status in ['VALIDADA', 'REPROVADA', 'APLICADA', 'FALHOU']) {
        expect(rotuloStatusLote(status), isNot(status));
      }
    });
  });
}
