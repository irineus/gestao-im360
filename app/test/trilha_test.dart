import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/trilha/trilha.dart';

import 'apoio/trilha_falso.dart';

/// A lógica **pura** da aba Trilha (card 6.6, card 2.8 §9.3): situação de cada
/// item, resumo do cabeçalho, e os três textos de resultado da entrega —
/// palavra por palavra como o design-system §7.3 os escreveu.
///
/// O que estes testes protegem, e que a tela sozinha não protegeria:
///   • **os três status são tratados, e o desconhecido não vira sucesso**;
///   • **"trilha vazia" e "trilha em fim" são estados diferentes** — a confusão
///     entre os dois é a que `fn_trilha_em_fim` faz de propósito (card 6.2), e a
///     tela precisa desfazê-la;
///   • **o texto do REORDENADA nomeia as DUAS apostilas** — sem isso a pessoa
///     não sabe qual livro entregar da mão.
void main() {
  ItemTrilha item({
    int posicao = 1,
    String material = 'mat-1',
    bool entregue = false,
    bool proximo = false,
    int saldo = 0,
    DateTime? dataEntrega,
    String? movimento,
    String origem = 'COMBO',
  }) => ItemTrilha(
    itemId: 'i-$posicao',
    alunoId: 'al-1',
    materialId: material,
    ordem: posicao * 10,
    posicao: posicao,
    materialCodigo: '0$posicao',
    materialNome: 'Apostila $posicao',
    origem: origem,
    entregue: entregue,
    dataEntrega: dataEntrega,
    movimentoEstoqueId: movimento,
    proximo: proximo,
    saldo: saldo,
  );

  group('situação do item', () {
    test('entregue, próxima e pendente são os três estados do wireframe', () {
      expect(
        situacaoDe(item(entregue: true, dataEntrega: DateTime(2026, 5, 12))),
        SituacaoItem.entregue,
      );
      expect(situacaoDe(item(proximo: true)), SituacaoItem.proxima);
      expect(situacaoDe(item()), SituacaoItem.pendente);
    });

    test('a entregue mostra a data e a próxima mostra o saldo', () {
      expect(
        rotuloSituacao(
          item(entregue: true, dataEntrega: DateTime(2026, 5, 12)),
        ),
        'entregue 12/05/2026',
      );
      expect(rotuloSituacao(item(proximo: true, saldo: 7)), 'próxima · est. 7');
      expect(rotuloSituacao(item()), 'pendente');
    });

    test('entrega sem movimento vinculado não é estornável', () {
      // A fixture do card 6.1 e a importação do card 9.1 produzem linhas
      // assim: entregue de verdade, sem a SAIDA que a pagou. O botão fica
      // visível e desabilitado com o motivo, e não some.
      expect(item(entregue: true).estornavel, isFalse);
      expect(item(entregue: true, movimento: 'mv-1').estornavel, isTrue);
      expect(item(movimento: 'mv-1').estornavel, isFalse);
    });
  });

  group('resumo do cabeçalho', () {
    test('conta entregues e pendentes, com plural certo', () {
      final resumo = resumirTrilha([
        item(posicao: 1, entregue: true),
        item(posicao: 2, proximo: true),
        item(posicao: 3),
      ]);
      expect(resumo.entregues, 1);
      expect(resumo.pendentes, 2);
      expect(resumo.texto, '1 entregue, 2 pendentes');
    });

    test('trilha VAZIA não é trilha em FIM', () {
      // `fn_trilha_em_fim` devolve `true` para os dois (card 6.2). A tela tem
      // de separá-los: um manda gerar a trilha, o outro manda ao certificado.
      expect(resumirTrilha(const []).emFim, isFalse);
      expect(resumirTrilha([item(entregue: true)]).emFim, isTrue);
    });

    test('proximoDaTrilha devolve o item marcado, ou nulo', () {
      expect(proximoDaTrilha(const [])?.materialId, isNull);
      expect(proximoDaTrilha([item(entregue: true)])?.materialId, isNull);
      expect(
        proximoDaTrilha([
          item(posicao: 1, entregue: true),
          item(posicao: 2, material: 'mat-2', proximo: true),
        ])?.materialId,
        'mat-2',
      );
    });
  });

  group('candidatos para inclusão', () {
    ({String id, String metodo, bool ativo}) m(
      String id,
      String metodo, {
      bool ativo = true,
    }) => (id: id, metodo: metodo, ativo: ativo);

    test('só material ativo, do método do aluno, fora da trilha', () {
      final candidatos =
          candidatosParaTrilha<({String id, String metodo, bool ativo})>(
            [
              m('a', 'int'),
              m('b', 'int'),
              m('c', 'ing'),
              m('d', 'int', ativo: false),
            ],
            idDe: (x) => x.id,
            metodoDe: (x) => x.metodo,
            ativoDe: (x) => x.ativo,
            metodoDoAluno: 'int',
            jaNaTrilha: {'b'},
          );
      expect(candidatos.map((x) => x.id), ['a']);
    });
  });

  group('status do banco → enum', () {
    test('os três códigos do tipo tp_entrega_resultado', () {
      expect(statusEntregaDe('ENTREGUE'), StatusEntrega.entregue);
      expect(statusEntregaDe('REORDENADA'), StatusEntrega.reordenada);
      expect(
        statusEntregaDe('BLOQUEADA_SEM_ESTOQUE'),
        StatusEntrega.bloqueadaSemEstoque,
      );
    });

    test('código desconhecido cai no ALERTA, nunca no sucesso', () {
      // Se o banco ganhar um quarto status, a tela para e mostra o alerta em
      // vez de dizer "entregue" sobre o que não foi.
      expect(statusEntregaDe('QUALQUER'), StatusEntrega.bloqueadaSemEstoque);
    });

    test('deLinha lê o composto como o PostgREST o devolve', () {
      final r = ResultadoEntrega.deLinha(const {
        'status': 'REORDENADA',
        'material_id': 'mat-3',
        'material_solicitado': 'mat-2',
        'movimento_id': 'mv-9',
        'proximo_material_id': 'mat-2',
        'em_fim': false,
      });
      expect(r.status, StatusEntrega.reordenada);
      expect(r.materialId, 'mat-3');
      expect(r.materialSolicitado, 'mat-2');
      expect(r.emFim, isFalse);
    });
  });

  group('textos dos resultados — design-system §7.3', () {
    String nome(String? id) => switch (id) {
      'mat-2' => 'INT-02 Básico 2',
      'mat-3' => 'INT-03 Básico 3',
      _ => '—',
    };

    test('ENTREGUE diz qual é a próxima', () {
      final t = textoResultadoEntrega(
        const ResultadoEntrega(
          status: StatusEntrega.entregue,
          materialId: 'mat-2',
          proximoMaterialId: 'mat-3',
        ),
        nomeDoMaterial: nome,
      );
      expect(t.titulo, 'Entrega registrada');
      expect(t.mensagem, contains('INT-02 Básico 2 foi entregue'));
      expect(t.mensagem, contains('A próxima apostila é INT-03 Básico 3.'));
    });

    test('ENTREGUE em fim anuncia o checklist de certificado', () {
      final t = textoResultadoEntrega(
        const ResultadoEntrega(
          status: StatusEntrega.entregue,
          materialId: 'mat-3',
          emFim: true,
        ),
        nomeDoMaterial: nome,
      );
      // Sem o emoji do design-system §7.3: divergência registrada no §11 —
      // Inter/Roboto não têm o glifo e a CSP não deixa baixar fonte de emoji,
      // então o que apareceria é uma caixa vazia (`texto_de_tela_test`).
      expect(
        t.mensagem,
        contains('Trilha concluída — o checklist de certificado foi aberto.'),
      );
    });

    test('REORDENADA nomeia a pulada E a entregue, nessa ordem', () {
      final t = textoResultadoEntrega(
        const ResultadoEntrega(
          status: StatusEntrega.reordenada,
          materialId: 'mat-3',
          materialSolicitado: 'mat-2',
        ),
        nomeDoMaterial: nome,
      );
      expect(t.titulo, 'Trilha reordenada');
      expect(
        t.mensagem,
        'Sem estoque de INT-02 Básico 2; foi entregue INT-03 Básico 3. '
        'INT-02 Básico 2 continua pendente e volta a ser a próxima quando '
        'houver estoque.',
      );
    });

    test('BLOQUEADA diz que a entrega NÃO aconteceu', () {
      final t = textoResultadoEntrega(
        const ResultadoEntrega(status: StatusEntrega.bloqueadaSemEstoque),
        nomeDoMaterial: nome,
      );
      expect(t.titulo, 'Entrega bloqueada');
      expect(t.mensagem, contains('A entrega não foi registrada'));
      expect(t.mensagem, contains('pendência de compra'));
    });

    test(
      'os dois últimos status oferecem o link da pendência; o primeiro não',
      () {
        expect(
          resultadoTemPendencia(
            const ResultadoEntrega(status: StatusEntrega.entregue),
          ),
          isFalse,
        );
        expect(
          resultadoTemPendencia(
            const ResultadoEntrega(status: StatusEntrega.reordenada),
          ),
          isTrue,
        );
        expect(
          resultadoTemPendencia(
            const ResultadoEntrega(status: StatusEntrega.bloqueadaSemEstoque),
          ),
          isTrue,
        );
      },
    );
  });

  group('o contrato do retorno, como o falso o reproduz', () {
    test('Ana Paula tem saldo e sai ENTREGUE', () async {
      final r = await TrilhaFalso.fixture().registrarEntrega('al-3001');
      expect(r.status, StatusEntrega.entregue);
      expect(r.materialId, 'mat-int-03');
      expect(r.emFim, isTrue);
    });

    test('Diego não tem saldo no 02 e sai REORDENADA com o 03', () async {
      final r = await TrilhaFalso.fixture().registrarEntrega('al-3004');
      expect(r.status, StatusEntrega.reordenada);
      expect(r.materialSolicitado, 'mat-int-02');
      expect(r.materialId, 'mat-int-03');
    });

    test('Felipe tem um item só, sem estoque: BLOQUEADA', () async {
      final r = await TrilhaFalso.fixture().registrarEntrega('al-3006');
      expect(r.status, StatusEntrega.bloqueadaSemEstoque);
      expect(r.materialId, isNull);
    });
  });
}
