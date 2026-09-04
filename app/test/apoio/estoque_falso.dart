import 'package:gestao_im360/catalogo/catalogo.dart';
import 'package:gestao_im360/estoque/estoque.dart';
import 'package:gestao_im360/estoque/estoque_repositorio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'catalogo_falso.dart';

/// Repositório em memória — o teste injeta **dados**, não um cliente HTTP falso
/// (card 2.8 §9.3).
///
/// ⚠️ **Ele espelha `v_estoque_atual`, não uma lista à parte** (card 6.4): a
/// linha de estoque é projetada do catálogo a cada leitura, e `saldo`,
/// `abaixo_minimo`, `qtd_movimentos` e `ultimo_movimento_em` **derivam dos
/// movimentos**, como no banco. Duas consequências que o teste precisa ter:
/// material cadastrado pelo formulário aparece na lista (a view é sobre
/// `material`), e um ajuste muda o saldo pelo mesmo caminho que muda a história
/// — uma cópia de "saldo" escrita à mão deixaria os dois livres para divergirem
/// dentro do próprio teste.
///
/// A forma dos dados é a da camada `trilha_estoque` da escola-fixture
/// (`supabase/seed.sql`, card 6.1):
///
///   • `INTERATIVO 01` — entrada do pedido `2026-001` e duas saídas (saldo 24);
///   • `INTERATIVO 02` — saldo **0** com mínimo 1: o caso **abaixo do mínimo**;
///   • `INTERATIVO 03` — saldo 1, o último exemplar;
///   • `INGLES 01` — **sem movimento nenhum**: o estado vazio do painel;
///   • `INGLES 02` — saldo **−2** por um AJUSTE: o caso **negativo**, que a tela
///     destaca e nunca esconde (card 2.3 §4.1);
///   • `MODULAR 01` — o par SAÍDA + ESTORNO da fixture, mais uma entrada de
///     pedido cujo número não é legível.
///
/// ⚠️ Há um movimento com `alunoId` preenchido e `alunoNome` **nulo** de
/// propósito, e uma entrada com `pedidoItemId` e sem `pedidoNumero`: é o que a
/// view devolve a quem não tem `alunos.ler` / `compras.ler` (todo `join` de
/// rótulo é externo, card 6.7). São os dois casos que a tela precisa dizer por
/// extenso em vez de mostrar um traço.
class EstoqueFalso implements EstoqueRepositorio {
  EstoqueFalso(
    this.catalogo, {
    Map<String, List<MovimentoMaterial>>? movimentos,
  }) : movimentos_ = {
         for (final e in (movimentos ?? const {}).entries)
           e.key: List.of(e.value),
       };

  /// [catalogo] é o **mesmo** `CatalogoFalso` da tela, quando houver: é assim
  /// que salvar um material o faz aparecer na lista de estoque.
  factory EstoqueFalso.fixture([CatalogoFalso? catalogo]) {
    final hoje = DateTime(2026, 9, 4);
    MovimentoMaterial mov(
      String id,
      String material,
      String tipo,
      int quantidade,
      int diasAtras, {
      String? observacao,
      String? alunoId,
      String? alunoNome,
      String? alunoCodigoSgf,
      String? pedidoItemId,
      String? pedidoNumero,
      String? estornoDeId,
      String? estornoDeTipo,
      int? estornoDeDiasAtras,
      String? criadoPor,
      String? criadoPorNome,
    }) => MovimentoMaterial(
      movimentoId: id,
      materialId: material,
      tipo: tipo,
      quantidade: quantidade,
      ocorridoEm: hoje.subtract(Duration(days: diasAtras)),
      observacao: observacao,
      alunoId: alunoId,
      alunoNome: alunoNome,
      alunoCodigoSgf: alunoCodigoSgf,
      pedidoItemId: pedidoItemId,
      pedidoNumero: pedidoNumero,
      estornoDeId: estornoDeId,
      estornoDeTipo: estornoDeTipo,
      estornoDeOcorridoEm: estornoDeDiasAtras == null
          ? null
          : hoje.subtract(Duration(days: estornoDeDiasAtras)),
      criadoPor: criadoPor,
      criadoPorNome: criadoPorNome,
    );

    return EstoqueFalso(
      catalogo ?? CatalogoFalso.fixture(),
      movimentos: {
        'mat-int-01': [
          mov(
            'mv-ent-01',
            'mat-int-01',
            'ENTRADA',
            26,
            120,
            observacao: 'chegada do pedido 2026-001',
            pedidoItemId: 'pi-1',
            pedidoNumero: '2026-001',
            criadoPor: 'us-celia',
            criadoPorNome: 'Célia',
          ),
          mov(
            'mv-sai-ana',
            'mat-int-01',
            'SAIDA',
            -1,
            150,
            observacao: 'entrega ao aluno',
            alunoId: 'al-3001',
            alunoNome: 'Ana Paula Ribeiro',
            alunoCodigoSgf: '4433',
            criadoPor: 'us-debora',
            criadoPorNome: 'Débora',
          ),
          // Aluno que existe e cujo NOME não é legível.
          mov(
            'mv-sai-oculta',
            'mat-int-01',
            'SAIDA',
            -1,
            80,
            alunoId: 'al-3002',
          ),
        ],
        'mat-int-02': [
          mov(
            'mv-ent-02',
            'mat-int-02',
            'ENTRADA',
            1,
            118,
            observacao: 'sobra de remessa antiga',
          ),
          mov(
            'mv-sai-02',
            'mat-int-02',
            'SAIDA',
            -1,
            40,
            alunoId: 'al-3004',
            alunoNome: 'Diego Alves',
          ),
        ],
        'mat-int-03': [
          mov('mv-ent-03', 'mat-int-03', 'ENTRADA', 2, 118),
          mov(
            'mv-sai-03',
            'mat-int-03',
            'SAIDA',
            -1,
            118,
            alunoId: 'al-3003',
            alunoNome: 'Bruno Carvalho',
          ),
        ],
        'mat-ing-02': [
          mov('mv-ent-ing', 'mat-ing-02', 'ENTRADA', 3, 115),
          mov(
            'mv-aju-ing',
            'mat-ing-02',
            'AJUSTE',
            -5,
            100,
            observacao: 'conferencia de prateleira: cinco extraviados',
          ),
        ],
        'mat-mod-01': [
          // Recebimento de pedido cujo NÚMERO não é legível — é o que o monitor
          // vê, porque não tem `compras.ler`.
          mov(
            'mv-ent-sem-numero',
            'mat-mod-01',
            'ENTRADA',
            10,
            115,
            pedidoItemId: 'pi-9',
          ),
          mov(
            'mv-sai-mod',
            'mat-mod-01',
            'SAIDA',
            -1,
            50,
            alunoId: 'al-3005',
            alunoNome: 'Eduarda Lima',
          ),
          mov(
            'mv-est-mod',
            'mat-mod-01',
            'ESTORNO',
            1,
            45,
            observacao: 'estorno: livro entregue por engano',
            alunoId: 'al-3005',
            alunoNome: 'Eduarda Lima',
            estornoDeId: 'mv-sai-mod',
            estornoDeTipo: 'SAIDA',
            estornoDeDiasAtras: 50,
          ),
        ],
      },
    );
  }

  final CatalogoFalso catalogo;
  final Map<String, List<MovimentoMaterial>> movimentos_;

  /// Se definido, toda **leitura** lança isto.
  Object? falhaAoLer;

  /// Se definido, só a leitura do **painel** lança isto — é como o teste
  /// verifica que o erro do painel fica dentro dele e não no lugar da tela.
  Object? falhaAoLerMovimentos;

  /// Se definido, toda **escrita** lança isto.
  Object? falhaAoGravar;

  final chamadas = <String>[];

  static PostgrestException erro(
    String status,
    String codigo, [
    Map<String, Object?> detalhe = const {},
  ]) => PostgrestException(
    message: codigo,
    code: 'PT$status',
    details:
        '{"codigo":"$codigo"'
        '${detalhe.entries.map((e) => ',"${e.key}":"${e.value}"').join()}}',
  );

  /// A projeção de `v_estoque_atual` sobre o catálogo — **derivada**, como no
  /// banco. Nenhum saldo é guardado em lugar nenhum.
  List<MaterialEstoque> get materiais_ => [
    for (final m in catalogo.materiais_) _projetar(m),
  ];

  MaterialEstoque _projetar(MaterialDidatico m) {
    final historia = movimentos_[m.id] ?? const <MovimentoMaterial>[];
    var saldo = 0;
    DateTime? ultimo;
    for (final mv in historia) {
      saldo += mv.quantidade;
      if (ultimo == null || mv.ocorridoEm.isAfter(ultimo)) {
        ultimo = mv.ocorridoEm;
      }
    }
    return MaterialEstoque(
      materialId: m.id!,
      metodoId: m.metodoId,
      codigo: m.codigo,
      nome: m.nome,
      categoria: m.categoria,
      estoqueMinimo: m.estoqueMinimo,
      saldo: saldo,
      ativo: m.ativo,
      abaixoMinimo: saldo < m.estoqueMinimo,
      qtdMovimentos: historia.length,
      ultimoMovimentoEm: ultimo,
    );
  }

  @override
  Future<List<MaterialEstoque>> estoque() async {
    chamadas.add('estoque');
    final falha = falhaAoLer;
    if (falha != null) throw falha;
    return materiais_;
  }

  @override
  Future<List<MovimentoMaterial>> movimentos(String materialId) async {
    chamadas.add('movimentos:$materialId');
    final falha = falhaAoLerMovimentos ?? falhaAoLer;
    if (falha != null) throw falha;
    return [...?movimentos_[materialId]]
      ..sort((a, b) => b.ocorridoEm.compareTo(a.ocorridoEm));
  }

  @override
  Future<void> ajustar(
    String materialId, {
    required int quantidade,
    required String motivo,
  }) async {
    chamadas.add('ajustar:$materialId:$quantidade');
    final falha = falhaAoGravar;
    if (falha != null) throw falha;
    // As recusas de `fn_ajustar_estoque` (card 6.5), na ordem em que a função
    // as faz — é o contrato que a tela lê, não uma segunda implementação da
    // regra.
    if (motivo.trim().isEmpty) {
      throw erro('422', 'MOTIVO_OBRIGATORIO', {'material': materialId});
    }
    if (quantidade == 0) {
      throw erro('422', 'QUANTIDADE_INVALIDA', {'material': materialId});
    }
    final linha = materiais_.where((m) => m.materialId == materialId);
    if (linha.isEmpty) {
      throw erro('404', 'MATERIAL_INEXISTENTE', {'material': materialId});
    }
    if (linha.single.saldo + quantidade < 0) {
      throw erro('409', 'SALDO_INSUFICIENTE', {'material': materialId});
    }
    movimentos_
        .putIfAbsent(materialId, () => <MovimentoMaterial>[])
        .add(
          MovimentoMaterial(
            movimentoId: 'mv-ajuste-${chamadas.length}',
            materialId: materialId,
            tipo: 'AJUSTE',
            quantidade: quantidade,
            ocorridoEm: DateTime(2026, 9, 4),
            observacao: motivo,
          ),
        );
  }
}
