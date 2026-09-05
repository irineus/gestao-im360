import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/compras/compras.dart';

import 'apoio/compras_falso.dart';

/// A lógica **pura** da tela 7 (card 6.8): filtros, rótulos de status, o que
/// cada estado do pedido permite e o que entra no "criar pedido com os
/// sugeridos". Sem rede e sem cliente Supabase (card 2.8 §9.3).
void main() {
  late ComprasFalso repositorio;

  setUp(() => repositorio = ComprasFalso.fixture());

  Future<List<LinhaSugerida>> sugerido() => repositorio.sugerido();
  Future<List<PedidoCompra>> pedidos() => repositorio.pedidos();

  group('o pedido sugerido, com as parcelas ao lado do total', () {
    test('a conta vem da view e a tela não a refaz', () async {
      // Card 2.3 §2.3: as parcelas ficam visíveis ao lado do total — o usuário
      // confere a conta em vez de acreditar nela. `INTERATIVO 02` tem saldo 0,
      // mínimo 1, imediata 5 e 10 a caminho: 5 + 0 + 1 − 0 − 10 dá −4, e o piso
      // zera. É o caso do wireframe §10.1, linha `INT-04`.
      final linha = (await sugerido()).firstWhere((l) => l.codigo == '02');
      expect(linha.qtdImediata, 5);
      expect(linha.qtdPedidaPendente, 10);
      expect(linha.qtdSugerida, 0, reason: 'greatest(…, 0) zera sem esconder');
    });

    test('a linha de sugestão zero CONTINUA na lista, com as parcelas', () {
      // Zerar é diferente de esconder (card 2.3 §6). Quem esconde é o filtro da
      // tela, e ele é desligável.
      const filtro = FiltroSugerido(soSugeridos: false);
      expect(filtro.ativos, 1, reason: 'desligar o chip é um desvio do padrão');
    });

    test('a coluna projetada vale zero até a projeção existir', () async {
      // Card 2.3 §6.2: a coluna nasce `0` na posição definitiva. Mostrar zero é
      // honesto; esconder a coluna faria a soma exibida não fechar com o total.
      expect((await sugerido()).every((l) => l.qtdProjetada == 0), isTrue);
    });

    test('RASCUNHO não abate: o material dele continua sendo sugerido', () async {
      // `INTERATIVO 03` está num pedido em rascunho (5 unidades) e tem saldo 1,
      // mínimo 1, imediata 4. Rascunho não foi pedido a ninguém — a parcela
      // pendente é ZERO, e a sugestão sai 4.
      final linha = (await sugerido()).firstWhere((l) => l.codigo == '03');
      expect(linha.qtdPedidaPendente, 0);
      expect(linha.qtdSugerida, 4);
    });

    test('CANCELADO e RECEBIDO também não abatem', () async {
      // `INTERATIVO 01` está num pedido RECEBIDO de 26: o material já entrou no
      // saldo, e contá-lo de novo abateria duas vezes.
      final linha = (await sugerido()).firstWhere(
        (l) => l.materialId == 'mat-int-01',
      );
      expect(linha.qtdPedidaPendente, 0);
    });
  });

  group('o filtro da aba, e o que ele esconde', () {
    test('"só sugeridos" vem ligado e é desligável', () async {
      final todas = await sugerido();
      final comFiltro = filtrarSugerido(todas, const FiltroSugerido());
      final sem = filtrarSugerido(
        todas,
        const FiltroSugerido(soSugeridos: false),
      );
      expect(comFiltro.every((l) => l.qtdSugerida > 0), isTrue);
      expect(sem.length, todas.length);
      expect(
        sem.length,
        greaterThan(comFiltro.length),
        reason: 'há material de sugestão zero, senão o filtro não prova nada',
      );
    });

    test('busca casa código e nome, e o método filtra', () async {
      final todas = await sugerido();
      expect(
        filtrarSugerido(
          todas,
          const FiltroSugerido(busca: 'english', soSugeridos: false),
        ).map((l) => l.materialId),
        ['mat-ing-01', 'mat-ing-02'],
      );
      expect(
        filtrarSugerido(
          todas,
          const FiltroSugerido(metodoId: 'm-mod', soSugeridos: false),
        ).single.materialId,
        'mat-mod-01',
      );
    });

    test('limpar filtros devolve o padrão, e o padrão TEM o chip ligado', () {
      // "Limpar" não é "mostrar tudo": a pergunta da aba continua sendo o que
      // comprar agora.
      expect(const FiltroSugerido().soSugeridos, isTrue);
      expect(const FiltroSugerido().ativos, 0);
    });
  });

  group('o que entra no "criar pedido com os sugeridos"', () {
    test('só as linhas EXIBIDAS, e só as com sugestão maior que zero', () async {
      final todas = await sugerido();
      final exibidas = filtrarSugerido(
        todas,
        const FiltroSugerido(metodoId: 'm-int'),
      );
      final itens = itensSugeridos(exibidas);

      // Com o filtro de método ligado, o botão diz "os sugeridos" e o que está
      // na frente da pessoa é um método só. Montar o pedido com o que ela não
      // vê é a mesma surpresa de uma exclusão em massa sem confirmação.
      expect(itens.map((i) => i.materialId), ['mat-int-03']);
      expect(itens.single.quantidade, 4);
      expect(
        itensSugeridos(todas).length,
        greaterThan(itens.length),
        reason: 'a lista inteira tem mais — é o que o filtro deixou de fora',
      );
    });

    test('o item vira o JSON que fn_pedido_criar espera', () {
      expect(
        const ItemNovo(materialId: 'mat-int-03', quantidade: 4).paraJson(),
        {'material_id': 'mat-int-03', 'qtd_pedida': 4},
      );
    });
  });

  group('o pedido: rótulos, resumo e agregados', () {
    test('os cinco status têm rótulo em português', () {
      expect(rotuloStatusPedido('RASCUNHO'), 'Rascunho');
      expect(rotuloStatusPedido('PARCIAL'), 'Parcial');
      expect(rotuloStatusPedido('CANCELADO'), 'Cancelado');
    });

    test('status desconhecido aparece cru, e não vira um estado conhecido', () {
      // Inventar `rascunho` para um código que o banco passou a usar seria
      // oferecer os botões errados para ele.
      expect(statusPedidoDe('EM_TRANSITO'), isNull);
      expect(rotuloStatusPedido('EM_TRANSITO'), 'EM_TRANSITO');
    });

    test('pedido SEM item conta ZERO itens — e é estado real', () async {
      // A armadilha do card 2.3 §3.2 chegando à tela: com `count(*)` sobre o
      // left join, este pedido diria "1 item".
      final vazio = (await pedidos()).firstWhere((p) => p.numero == '2026-004');
      expect(vazio.qtdItens, 0);
      expect(resumoPedido(vazio), '0 itens');
    });

    test(
      'o resumo fala de recebimento só onde recebimento é assunto',
      () async {
        final lista = await pedidos();
        final rascunho = lista.firstWhere((p) => p.numero == '2026-003');
        final enviado = lista.firstWhere((p) => p.numero == '2026-002');
        // Dizer "0 de 5 recebidos" num rascunho sugeriria uma espera que não
        // existe: ele não foi pedido a ninguém.
        expect(resumoPedido(rascunho), '1 item');
        expect(resumoPedido(enviado), '2 itens · 0 de 15 recebidos');
      },
    );
  });

  group('o que cada ESTADO permite — a metade não-permissão do §5.7', () {
    late List<PedidoCompra> lista;
    setUp(() async => lista = await pedidos());

    PedidoCompra de(String numero) =>
        lista.firstWhere((p) => p.numero == numero);

    test('rascunho: edita, envia e cancela; não recebe', () {
      final p = de('2026-003');
      expect(motivoIndisponivel(AcaoPedido.editar, p), isNull);
      expect(motivoIndisponivel(AcaoPedido.enviar, p), isNull);
      expect(motivoIndisponivel(AcaoPedido.cancelar, p), isNull);
      expect(
        motivoIndisponivel(AcaoPedido.receber, p),
        'Este pedido não está aguardando recebimento.',
      );
    });

    test('rascunho SEM item não envia, e o motivo diz por quê', () {
      // O motivo é obrigatório no contrato do botão (design-system §5.7):
      // desabilitado sem motivo é um botão que a pessoa fica tentando clicar.
      final p = de('2026-004').copiarComoRascunhoVazio();
      expect(
        motivoIndisponivel(AcaoPedido.enviar, p),
        'Um pedido sem item não pode ser enviado.',
      );
    });

    test('enviado: recebe e cancela; não edita nem reenvia', () {
      final p = de('2026-002');
      expect(motivoIndisponivel(AcaoPedido.receber, p), isNull);
      expect(motivoIndisponivel(AcaoPedido.cancelar, p), isNull);
      expect(
        motivoIndisponivel(AcaoPedido.editar, p),
        'Só pedido em rascunho pode ser editado ou enviado.',
      );
    });

    test('recebido e cancelado: nada além de olhar', () {
      for (final numero in ['2026-001', '2026-004']) {
        final p = de(numero);
        expect(motivoIndisponivel(AcaoPedido.receber, p), isNotNull);
        expect(motivoIndisponivel(AcaoPedido.cancelar, p), isNotNull);
        expect(motivoIndisponivel(AcaoPedido.editar, p), isNotNull);
      }
    });
  });

  group('o item: o piso por item e o excedente dito', () {
    test('recebido com excedente falta ZERO, e o excedente é FATO', () async {
      repositorio.permiteExcedente = true;
      await repositorio.receber('p-002', {'i-2': 12});
      final item = (await repositorio.itens('p-002'))
          .firstWhere((i) => i.itemId == 'i-2');

      // Piso por item (card 6.5): "faltam −2" não é frase de conferência.
      expect(item.qtdRecebida, 12);
      expect(item.qtdPendente, 0);
      expect(item.completo, isTrue);
      // E o excedente não é escondido: grampear o número faria o painel dizer
      // "10 de 10" com 12 na prateleira.
      expect(recebidoAcimaDoPedido(item), isTrue);
    });

    test('o total do pedido também não é grampeado', () async {
      repositorio.permiteExcedente = true;
      await repositorio.receber('p-002', {'i-2': 12});
      final pedido = (await pedidos()).firstWhere(
        (p) => p.numero == '2026-002',
      );
      expect(pedido.qtdRecebidaTotal, 12);
      expect(pedido.qtdPedidaTotal, 15);
      expect(pedido.status, 'PARCIAL', reason: 'o outro item não chegou');
    });

    test('sem a permissão, o excedente é RECUSADO pelo banco', () async {
      // A tela NÃO pré-verifica (card 2.6 decisão 2): o campo aceita, e quem
      // recusa é fn_pedido_receber, com o código do catálogo.
      expect(
        () => repositorio.receber('p-002', {'i-2': 12}),
        throwsA(
          isA<Object>().having(
            (e) => '$e',
            'contém o código',
            contains('RECEBIMENTO_EXCEDE_PEDIDO'),
          ),
        ),
      );
    });
  });

  group('os textos do card 2.7 §7.2, palavra por palavra', () {
    test('os dois vazios da tela 7', () {
      expect(
        vazioSugerido,
        'Nada a comprar agora: nenhum material com sugestão maior que zero.',
      );
      expect(vazioPedidos, 'Nenhum pedido. Crie a partir do Pedido sugerido.');
    });
  });
}

extension on PedidoCompra {
  /// Um rascunho sem item — o estado que `PEDIDO_SEM_ITEM` existe para recusar.
  PedidoCompra copiarComoRascunhoVazio() => PedidoCompra(
    pedidoId: pedidoId,
    numero: numero,
    status: 'RASCUNHO',
    dataReferencia: dataReferencia,
    qtdItens: 0,
    qtdPedidaTotal: 0,
    qtdRecebidaTotal: 0,
  );
}
