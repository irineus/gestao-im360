import 'package:gestao_im360/importacao/importacao.dart';
import 'package:gestao_im360/importacao/importacao_repositorio.dart';

/// Repositório em memória — o teste injeta **dados**, não um cliente HTTP falso
/// (card 2.8 §9.3).
///
/// ⚠️ **A máquina de estados é a do banco, e é ela que este falso reproduz.**
/// Registrar cria o lote com o relatório que o teste pediu; aplicar com
/// `simular` devolve totais e NÃO muda o status; aplicar de verdade leva a
/// APLICADA. Um falso que aceitasse aplicar um lote REPROVADO faria a tela
/// passar num caminho que o banco recusa — e é justamente esse caminho que a
/// tela precisa fechar antes de chegar lá.
class ImportacaoFalso implements ImportacaoRepositorio {
  ImportacaoFalso({
    List<OcorrenciaImportacao> ocorrencias = const [],
    this.totais = const {},
    this.falhaAoAplicar,
    this.erroAoRegistrar,
  }) : ocorrencias_ = List.of(ocorrencias);

  /// O que a validação do banco devolveria para o próximo arquivo enviado.
  final List<OcorrenciaImportacao> ocorrencias_;

  /// O `jsonb` de `importacao.totais` que a simulação e a aplicação devolvem.
  final Map<String, dynamic> totais;

  /// Quando preenchido, `aplicar(simular: false)` responde como o banco
  /// responde quando um trigger recusa uma linha: status FALHOU e nada escrito.
  final String? falhaAoAplicar;

  /// Erro traduzido que `registrar` deve lançar (SEM_PERMISSAO, por exemplo).
  final Object? erroAoRegistrar;

  final _lotes = <String, LoteImportacao>{};
  var _sequencia = 0;

  /// O que a tela pediu ao banco, para o teste conferir o que foi enviado.
  Map<String, dynamic>? ultimoEnvio;
  DateTime? ultimoSnapshot;
  String? ultimoArquivo;
  final aplicacoes = <({String id, bool simular})>[];

  @override
  Future<List<LoteImportacao>> lotes() async => _lotes.values.toList();

  @override
  Future<LoteImportacao?> lote(String id) async => _lotes[id];

  @override
  Future<List<OcorrenciaImportacao>> ocorrencias(String importacaoId) async =>
      ocorrencias_;

  @override
  Future<String> registrar({
    required String arquivo,
    required DateTime snapshotEm,
    required Map<String, dynamic> dados,
  }) async {
    if (erroAoRegistrar != null) throw erroAoRegistrar!;
    ultimoEnvio = dados;
    ultimoSnapshot = snapshotEm;
    ultimoArquivo = arquivo;
    final id = 'lote-${++_sequencia}';
    final erros = ocorrencias_.where((o) => o.bloqueia).length;
    _lotes[id] = LoteImportacao(
      id: id,
      arquivo: arquivo,
      snapshotEm: snapshotEm,
      status: erros > 0 ? 'REPROVADA' : 'VALIDADA',
      erros: erros,
      avisos: ocorrencias_.length - erros,
      criadoEm: DateTime(2026, 9, 6, 10),
    );
    return id;
  }

  @override
  Future<Map<String, dynamic>> aplicar(
    String importacaoId, {
    bool simular = true,
  }) async {
    aplicacoes.add((id: importacaoId, simular: simular));
    final lote = _lotes[importacaoId]!;
    if (!simular && falhaAoAplicar != null) {
      _lotes[importacaoId] = _copiar(lote, status: 'FALHOU');
      return {
        'status': 'FALHOU',
        'codigo': 'BLOCO_LOTADO',
        'mensagem': falhaAoAplicar,
      };
    }
    if (!simular) {
      _lotes[importacaoId] = _copiar(
        lote,
        status: 'APLICADA',
        totais: totais,
        aplicadoEm: DateTime(2026, 9, 6, 10, 30),
      );
      return {'status': 'APLICADA', 'totais': totais};
    }
    return {'status': 'SIMULADA', 'totais': totais};
  }

  LoteImportacao _copiar(
    LoteImportacao lote, {
    required String status,
    Map<String, dynamic>? totais,
    DateTime? aplicadoEm,
  }) => LoteImportacao(
    id: lote.id,
    arquivo: lote.arquivo,
    snapshotEm: lote.snapshotEm,
    status: status,
    erros: lote.erros,
    avisos: lote.avisos,
    criadoEm: lote.criadoEm,
    totais: totais ?? lote.totais,
    aplicadoEm: aplicadoEm ?? lote.aplicadoEm,
    aplicadoPorNome: aplicadoEm == null ? null : 'Direção',
  );
}

/// Um arquivo mínimo e VÁLIDO, no formato de `docs/importacao.md` §3.
const arquivoDeTeste =
    '{"snapshot_em": "2026-08-29", '
    '"aluno": [{"codigo": "1", "nome": "Aluna", "metodo": "INTERATIVO"}], '
    '"material": [{"metodo": "INTERATIVO", "codigo": "01", "nome": "Apostila 1", '
    '"categoria": "APOSTILA"}]}';

/// Os totais como o banco os devolve (duas entidades, com `no_sistema`).
const totaisDeTeste = <String, dynamic>{
  'aluno': {'arquivo': 1, 'aplicadas': 1, 'ignoradas': 0},
  'material': {'arquivo': 1, 'aplicadas': 1, 'ignoradas': 0},
  'no_sistema': {'aluno': 265, 'material': 42},
};

OcorrenciaImportacao ocorrencia({
  required String severidade,
  String entidade = 'aluno',
  String codigo = 'ALUNO_SEM_TURMA',
  String mensagem = 'O aluno 1 não aparece em turma nenhuma no arquivo.',
  int? linha = 1,
}) => OcorrenciaImportacao(
  id: '$codigo-$linha',
  severidade: severidade,
  entidade: entidade,
  codigo: codigo,
  mensagem: mensagem,
  linha: linha,
);
