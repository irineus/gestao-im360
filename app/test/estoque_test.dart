import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/estoque/estoque.dart';

import 'apoio/estoque_falso.dart';

/// A lógica **pura** da tela 6 (card 6.7): situação do material, filtros e os
/// rótulos de origem — testável sem rede e sem cliente Supabase (card 2.8 §9.3).
void main() {
  final fixture = EstoqueFalso.fixture();
  MaterialEstoque material(String id) =>
      fixture.materiais_.firstWhere((m) => m.materialId == id);

  group('situação do material', () {
    test('saldo negativo é ERRO, e vence "abaixo do mínimo"', () {
      // `INGLES 02` tem saldo −2 e mínimo 2: as duas condições valem, e a que
      // aparece é a pior. Se `abaixoMinimo` viesse primeiro, o saldo negativo —
      // que é sintoma de AJUSTE errado (card 2.3 §4.1) — seria exibido como um
      // aviso âmbar de rotina e ninguém iria atrás dele.
      final ingles = material('mat-ing-02');
      expect(ingles.abaixoMinimo, isTrue, reason: 'as duas condições valem');
      expect(situacaoEstoqueDe(ingles), SituacaoEstoque.negativo);
      expect(rotuloSituacaoEstoque(ingles), 'saldo negativo');
    });

    test('abaixo do mínimo é ATENÇÃO, e saldo zero com mínimo zero é normal', () {
      expect(
        situacaoEstoqueDe(material('mat-int-02')),
        SituacaoEstoque.abaixoMinimo,
        reason: 'saldo 0, mínimo 1',
      );
      expect(rotuloSituacaoEstoque(material('mat-int-02')), 'abaixo do mínimo');
      // Zerado não é o mesmo que "falta": com mínimo 0 o material zerado é
      // normal, e alertar sobre ele encheria a lista de aviso que ninguém pode
      // resolver.
      const semMinimo = MaterialEstoque(
        materialId: 'x',
        metodoId: 'm-int',
        codigo: '90',
        nome: 'Sem mínimo',
        categoria: 'APOSTILA',
        estoqueMinimo: 0,
        saldo: 0,
      );
      expect(situacaoEstoqueDe(semMinimo), SituacaoEstoque.normal);
      expect(rotuloSituacaoEstoque(semMinimo), isNull);
    });

    test('material sem movimento nenhum aparece na lista, com saldo 0', () {
      // `v_estoque_atual` faz `left join` em `movimento_estoque` (card 6.4):
      // material recém-cadastrado aparece com saldo 0 e zero movimentos, e não
      // some da lista — que é o que a tela de compras precisa ver.
      final semHistoria = material('mat-ing-01');
      expect(semHistoria.qtdMovimentos, 0);
      expect(semHistoria.saldo, 0);
      expect(semHistoria.ultimoMovimentoEm, isNull);
    });

    test('a situação sai de `abaixoMinimo`, que vem da VIEW', () {
      // A tela não recalcula `saldo < mínimo`: a conta é a da view (card 6.4).
      // Este teste prende a decisão — com a coluna dizendo `false`, a situação
      // é normal mesmo que os números sugiram o contrário.
      const discordante = MaterialEstoque(
        materialId: 'x',
        metodoId: 'm',
        codigo: '99',
        nome: 'Discordante',
        categoria: 'APOSTILA',
        estoqueMinimo: 5,
        saldo: 1,
      );
      expect(situacaoEstoqueDe(discordante), SituacaoEstoque.normal);
    });
  });

  group('filtro da lista', () {
    test('"só ativos" está ligado por padrão e é desligável', () {
      final comInativo = [
        ...fixture.materiais_,
        const MaterialEstoque(
          materialId: 'x',
          metodoId: 'm-int',
          codigo: '99',
          nome: 'Aposentada',
          categoria: 'APOSTILA',
          estoqueMinimo: 0,
          saldo: 0,
          ativo: false,
        ),
      ];
      expect(filtrarEstoque(comInativo).length, fixture.materiais_.length);
      expect(
        filtrarEstoque(comInativo, soAtivos: false).length,
        comInativo.length,
      );
    });

    test('"só abaixo do mínimo" inclui o saldo NEGATIVO', () {
      // O negativo é o caso mais urgente da lista, e ele não satisfaz
      // "saldo < mínimo" quando o mínimo é 0 — deixá-lo de fora esconderia o
      // pior material justamente no filtro que existe para achar problema.
      final abaixo = filtrarEstoque(
        fixture.materiais_,
        soAbaixoMinimo: true,
      ).map((m) => m.materialId).toSet();
      expect(abaixo, contains('mat-int-02'), reason: 'saldo 0, mínimo 1');
      expect(abaixo, contains('mat-ing-02'), reason: 'saldo −2');
      expect(abaixo, contains('mat-ing-01'), reason: 'sem movimento, mínimo 1');
      expect(abaixo, isNot(contains('mat-int-01')));
      expect(abaixo, isNot(contains('mat-mod-01')));
    });

    test('busca casa código e nome, e método e categoria acumulam', () {
      expect(filtrarEstoque(fixture.materiais_, busca: 'english').length, 2);
      expect(
        filtrarEstoque(fixture.materiais_, busca: '03').single.codigo,
        '03',
      );
      expect(filtrarEstoque(fixture.materiais_, metodoId: 'm-int').length, 3);
      expect(
        filtrarEstoque(fixture.materiais_, categoria: 'LIVRO').single.nome,
        'Eletricista Instalador',
      );
      expect(
        filtrarEstoque(
          fixture.materiais_,
          metodoId: 'm-int',
          soAbaixoMinimo: true,
        ).single.codigo,
        '02',
      );
    });

    test('categoriasDoEstoque devolve as categorias em uso, ordenadas', () {
      expect(categoriasDoEstoque(fixture.materiais_), ['APOSTILA', 'LIVRO']);
    });
  });

  group('filtro do painel de movimentações', () {
    final hoje = DateTime(2026, 9, 4);
    final movimentos = fixture.movimentos_['mat-int-01']!;

    test('o padrão é TUDO — o painel abre com a história inteira', () {
      const filtro = FiltroMovimento();
      expect(filtro.ativos, 0);
      expect(
        filtrarMovimentos(movimentos, filtro, hoje: hoje).length,
        movimentos.length,
      );
    });

    test('o período corta pela data do movimento, não pelo relógio local', () {
      // `hoje` entra por parâmetro (card 5.9): o corte é uma data, e data neste
      // app não vem do aparelho.
      const filtro = FiltroMovimento(periodo: PeriodoMovimento.noventaDias);
      final dentro = filtrarMovimentos(movimentos, filtro, hoje: hoje);
      expect(dentro.map((m) => m.movimentoId), ['mv-sai-oculta']);
      expect(filtro.ativos, 1);

      // Um ano depois, nada mais cabe na janela de 90 dias — e a lista não
      // "some" por bug, some por período.
      expect(
        filtrarMovimentos(movimentos, filtro, hoje: DateTime(2027, 9, 4)),
        isEmpty,
      );
    });

    test('o tipo filtra e acumula com o período', () {
      expect(
        filtrarMovimentos(
          movimentos,
          const FiltroMovimento(tipo: 'SAIDA'),
          hoje: hoje,
        ).length,
        2,
      );
      const ambos = FiltroMovimento(
        periodo: PeriodoMovimento.umAno,
        tipo: 'ENTRADA',
      );
      expect(ambos.ativos, 2);
      expect(
        filtrarMovimentos(movimentos, ambos, hoje: hoje).single.movimentoId,
        'mv-ent-01',
      );
    });

    test(
      'copiar limpa o tipo com a função, e mantém o que não foi passado',
      () {
        const filtro = FiltroMovimento(
          periodo: PeriodoMovimento.trintaDias,
          tipo: 'AJUSTE',
        );
        expect(filtro.copiar(tipo: () => null).tipo, isNull);
        expect(
          filtro.copiar(tipo: () => null).periodo,
          PeriodoMovimento.trintaDias,
        );
        expect(filtro.copiar(periodo: PeriodoMovimento.todos).tipo, 'AJUSTE');
      },
    );
  });

  group('origem e autor de um movimento', () {
    final movimentos = {
      for (final lista in fixture.movimentos_.values)
        for (final m in lista) m.movimentoId: m,
    };

    test('entrega mostra o aluno com o código', () {
      expect(
        origemDoMovimento(movimentos['mv-sai-ana']!),
        'Ana Paula Ribeiro (4433)',
      );
    });

    test('aluno que existe e não é legível NÃO vira traço', () {
      // A view traz `aluno_id` ao lado do nome justamente para isto (card 6.7):
      // um traço faria uma SAIDA de entrega parecer um ajuste sem dono, que é a
      // mentira que o card 4.6 recusou na ficha (pendência 9.13).
      final oculto = movimentos['mv-sai-oculta']!;
      expect(oculto.alunoId, isNotNull);
      expect(oculto.alunoNome, isNull);
      expect(origemDoMovimento(oculto), 'Aluno não visível para o seu perfil');
    });

    test('pedido: com número, e sem número quando falta compras.ler', () {
      expect(origemDoMovimento(movimentos['mv-ent-01']!), 'Pedido 2026-001');
      final semNumero = movimentos['mv-ent-sem-numero']!;
      expect(semNumero.pedidoItemId, isNotNull);
      expect(
        origemDoMovimento(semNumero),
        'Recebimento de pedido (número não visível para o seu perfil)',
      );
    });

    test('estorno diz o que estornou e quando', () {
      expect(
        origemDoMovimento(movimentos['mv-est-mod']!),
        // O aluno vem antes: o estorno da fixture tem os dois, e quem lê o
        // painel procura a pessoa, não o movimento anterior.
        'Eduarda Lima',
      );
      final soEstorno = MovimentoMaterial(
        movimentoId: 'x',
        materialId: 'mat-mod-01',
        tipo: 'ESTORNO',
        quantidade: 1,
        ocorridoEm: DateTime(2026, 7, 20),
        estornoDeId: 'mv-anterior',
        estornoDeTipo: 'SAIDA',
        estornoDeOcorridoEm: DateTime(2026, 7, 15),
      );
      expect(origemDoMovimento(soEstorno), 'Estorno de saida de 15/07/2026');
    });

    test('ajuste sem vínculo nenhum é "Lançamento manual"', () {
      expect(origemDoMovimento(movimentos['mv-aju-ing']!), 'Lançamento manual');
    });

    test('o autor é OMITIDO quando não é legível, nunca "por —"', () {
      expect(autorDoMovimento(movimentos['mv-sai-ana']!), 'por Débora');
      expect(autorDoMovimento(movimentos['mv-aju-ing']!), isNull);
    });
  });

  group('quantidade com sinal', () {
    test('o sinal vem da COLUNA, e o texto o mostra sempre', () {
      // A tela não deriva o sinal do tipo: seria recriar em Dart o `case` por
      // tipo que o card 2.1 tirou do banco de propósito (card 6.1).
      final entrada = MovimentoMaterial(
        movimentoId: 'a',
        materialId: 'm',
        tipo: 'ENTRADA',
        quantidade: 10,
        ocorridoEm: DateTime(2026, 7, 15),
      );
      final ajusteNegativo = MovimentoMaterial(
        movimentoId: 'b',
        materialId: 'm',
        tipo: 'AJUSTE',
        quantidade: -5,
        ocorridoEm: DateTime(2026, 7, 15),
      );
      expect(entrada.quantidadeFormatada, '+10');
      expect(ajusteNegativo.quantidadeFormatada, '−5');
    });
  });
}
