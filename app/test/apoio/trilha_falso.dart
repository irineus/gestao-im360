import 'package:gestao_im360/trilha/trilha.dart';
import 'package:gestao_im360/trilha/trilha_repositorio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repositório em memória — o teste injeta **dados**, não um cliente HTTP falso
/// (card 2.8 §9.3). A forma dos dados é a da camada `trilha_estoque` da
/// escola-fixture (`supabase/seed.sql`, card 6.1) e do `CatalogoFalso`:
///
///   • **Ana Paula** tem 01 e 02 entregues e o 03 como próximo, com saldo 1 —
///     é o cenário do último exemplar;
///   • **Diego** tem o 01 entregue e o 02 como próximo com saldo **0**, e ainda
///     tem o 03 adiante: é o caso `REORDENADA`;
///   • **Felipe** tem um único item pendente, sem estoque: é o caso
///     `BLOQUEADA_SEM_ESTOQUE`;
///   • **Karina**, a aluna sem combo, não tem trilha nenhuma.
///
/// `registrarEntrega` reproduz **o que o banco responde** — os três status de
/// `tp_entrega_resultado`, na mesma forma —, porque é isso que a tela lê. Não é
/// uma segunda implementação da regra: é o contrato do retorno, do lado de cá.
class TrilhaFalso implements TrilhaRepositorio {
  TrilhaFalso({Map<String, List<ItemTrilha>>? trilhas})
    : trilhas = {
        for (final e in (trilhas ?? const {}).entries) e.key: List.of(e.value),
      };

  factory TrilhaFalso.fixture() {
    final hoje = DateTime(2026, 9, 4);
    ItemTrilha item(
      String aluno,
      int posicao,
      String materialId,
      String codigo,
      String nome, {
      bool entregue = false,
      bool proximo = false,
      int saldo = 0,
      int? entregueHa,
      String? movimento,
      String origem = 'COMBO',
    }) => ItemTrilha(
      itemId: '$aluno-$materialId',
      alunoId: aluno,
      materialId: materialId,
      ordem: posicao * 10,
      posicao: posicao,
      materialCodigo: codigo,
      materialNome: nome,
      materialCategoria: 'APOSTILA',
      origem: origem,
      entregue: entregue,
      dataEntrega: entregueHa == null
          ? null
          : hoje.subtract(Duration(days: entregueHa)),
      movimentoEstoqueId: movimento,
      proximo: proximo,
      saldo: saldo,
    );

    return TrilhaFalso(
      trilhas: {
        'al-3001': [
          item(
            'al-3001',
            1,
            'mat-int-01',
            '01',
            'Informática Essencial 1',
            entregue: true,
            entregueHa: 150,
            movimento: 'mv-ana-01',
            saldo: 26,
          ),
          item(
            'al-3001',
            2,
            'mat-int-02',
            '02',
            'Informática Essencial 2',
            entregue: true,
            entregueHa: 90,
            movimento: 'mv-ana-02',
            saldo: 0,
          ),
          item(
            'al-3001',
            3,
            'mat-int-03',
            '03',
            'Informática Avançada 1',
            proximo: true,
            saldo: 1,
          ),
        ],
        'al-3004': [
          item(
            'al-3004',
            1,
            'mat-int-01',
            '01',
            'Informática Essencial 1',
            entregue: true,
            entregueHa: 100,
            movimento: 'mv-diego-01',
            saldo: 26,
          ),
          item(
            'al-3004',
            2,
            'mat-int-02',
            '02',
            'Informática Essencial 2',
            proximo: true,
          ),
          item(
            'al-3004',
            3,
            'mat-int-03',
            '03',
            'Informática Avançada 1',
            saldo: 1,
          ),
        ],
        'al-3006': [
          item(
            'al-3006',
            1,
            'mat-ing-02',
            '02',
            'English Book 2',
            proximo: true,
          ),
        ],
        // Aluno em FIM: trilha existe e nada está pendente. É diferente de
        // Karina, que não tem trilha — e é a distinção que a aba precisa fazer.
        'al-3010': [
          item(
            'al-3010',
            1,
            'mat-int-01',
            '01',
            'Informática Essencial 1',
            entregue: true,
            entregueHa: 380,
            movimento: 'mv-joao-01',
            saldo: 26,
          ),
        ],
      },
    );
  }

  final Map<String, List<ItemTrilha>> trilhas;

  /// Se definido, toda **leitura** lança isto.
  Object? falhaAoLer;

  /// Se definido, toda **escrita** lança isto.
  Object? falhaAoGravar;

  /// O que `registrarEntrega` devolve. Nulo = deduz do estado da trilha, que é
  /// o que a fixture faz; definido = o teste manda o status que quer medir.
  ResultadoEntrega? proximoResultado;

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

  Future<T> _ler<T>(String nome, T valor) async {
    chamadas.add(nome);
    final falha = falhaAoLer;
    if (falha != null) throw falha;
    return valor;
  }

  Future<T> _gravar<T>(String nome, T Function() acao) async {
    chamadas.add(nome);
    final falha = falhaAoGravar;
    if (falha != null) throw falha;
    return acao();
  }

  @override
  Future<List<ItemTrilha>> trilha(String alunoId) =>
      _ler('trilha', List.of(trilhas[alunoId] ?? const <ItemTrilha>[]));

  @override
  Future<ResultadoEntrega> registrarEntrega(
    String alunoId, {
    String? materialId,
    String? observacao,
  }) => _gravar('registrarEntrega', () {
    final combinado = proximoResultado;
    if (combinado != null) return combinado;

    final itens = trilhas[alunoId] ?? const <ItemTrilha>[];
    final proxima = proximoDaTrilha(itens);
    if (proxima == null) {
      throw erro('409', 'TRILHA_EM_FIM', {'aluno': alunoId});
    }
    // O mesmo desenho de fn_registrar_entrega: com saldo, entrega; sem saldo,
    // procura o primeiro pendente adiante que tenha; sem nenhum, bloqueia.
    if (proxima.saldo > 0) {
      return ResultadoEntrega(
        status: StatusEntrega.entregue,
        materialId: proxima.materialId,
        materialSolicitado: proxima.materialId,
        movimentoId: 'mv-novo',
        proximoMaterialId: _seguinte(itens, proxima)?.materialId,
        emFim: _seguinte(itens, proxima) == null,
      );
    }
    for (final i in itens) {
      if (!i.entregue && i.materialId != proxima.materialId && i.saldo > 0) {
        return ResultadoEntrega(
          status: StatusEntrega.reordenada,
          materialId: i.materialId,
          materialSolicitado: proxima.materialId,
          movimentoId: 'mv-novo',
          proximoMaterialId: proxima.materialId,
        );
      }
    }
    return ResultadoEntrega(
      status: StatusEntrega.bloqueadaSemEstoque,
      materialSolicitado: proxima.materialId,
      proximoMaterialId: proxima.materialId,
    );
  });

  static ItemTrilha? _seguinte(List<ItemTrilha> itens, ItemTrilha atual) {
    for (final i in itens) {
      if (!i.entregue && i.ordem > atual.ordem) return i;
    }
    return null;
  }

  @override
  Future<void> estornarEntrega(String movimentoId, {required String motivo}) =>
      _gravar('estornarEntrega', () {
        if (motivo.trim().isEmpty) {
          throw erro('422', 'MOTIVO_OBRIGATORIO', {'movimento': movimentoId});
        }
      });

  @override
  Future<int> gerarTrilha(String alunoId, {bool substituir = false}) =>
      _gravar('gerarTrilha', () {
        if ((trilhas[alunoId] ?? const []).isNotEmpty && !substituir) {
          throw erro('409', 'TRILHA_JA_EXISTE', {'aluno': alunoId});
        }
        return 3;
      });

  @override
  Future<void> inserirItem(
    String alunoId, {
    required String materialId,
    String? aposMaterialId,
  }) => _gravar('inserirItem', () {});

  @override
  Future<void> removerItem(
    String alunoId, {
    required String materialId,
    required String motivo,
  }) => _gravar('removerItem', () {
    if (motivo.trim().isEmpty) {
      throw erro('422', 'MOTIVO_OBRIGATORIO', {'material': materialId});
    }
  });

  @override
  Future<void> reordenarItem(
    String alunoId, {
    required String materialId,
    required int novaPosicao,
  }) => _gravar('reordenarItem:$novaPosicao', () {});
}
