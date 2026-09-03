/// Os alunos como o app os vê (card 4.6): o modelo das duas tabelas do card
/// 4.2 que a tela lê e escreve (`aluno`, `aluno_status_hist`) e a lógica
/// **pura** da tela — o que o menu de status oferece, filtros, rótulos.
///
/// Pura de propósito: é o que se testa sem rede e sem cliente Supabase
/// (card 2.8 §9.3). Regra de negócio continua no banco — quem decide se uma
/// transição vale é `fn_aluno_transicao_valida`, dentro do trigger; a tabela
/// daqui só diz **o que o menu mostra** (docs/wireframes.md §6.2), e um
/// `TRANSICAO_INVALIDA` vindo do banco continua sendo traduzido e exibido.
library;

import 'package:flutter/foundation.dart';

import '../util/datas.dart';

/// Os seis status do `check` de `aluno.status` (card 4.2) e o rótulo em tela.
/// A chave é o valor do banco; o app nunca compara pelo rótulo.
const statusAluno = <String, String>{
  'ATIVO': 'Ativo',
  'ACELERAR': 'Acelerar',
  'STANDBY': 'Standby',
  'TRANCADO': 'Trancado',
  'CANCELADO': 'Cancelado',
  'FORMADO': 'Formado',
};

/// Terminais: só saem por `fn_aluno_reverter_status` (card 2.2 §3.4).
const statusTerminais = <String>{'FORMADO', 'CANCELADO'};

/// Em aula: ocupam vaga em turma; sair deles remove das turmas (card 2.2).
const statusEmAula = <String>{'ATIVO', 'ACELERAR'};

/// Destinos para os quais o banco exige motivo (card 4.2 (b)). A tela **não**
/// pré-valida por isto — submete e realça o campo quando vier
/// `MOTIVO_OBRIGATORIO` (design-system §5.4); a constante só escreve a legenda.
const statusComMotivo = <String>{'STANDBY', 'TRANCADO', 'CANCELADO'};

String rotuloStatus(String status) => statusAluno[status] ?? status;

/// As transições que o menu "Alterar status" oferece a partir de [de] — a
/// tabela de decisão de `fn_aluno_transicao_valida`, na ordem em que a tela
/// as lista. Status igual não é transição; qualquer origem vai a CANCELADO,
/// inclusive FORMADO (é o que o banco aceita, teste 030); de CANCELADO só se
/// sai por reversão.
List<String> transicoesDe(String de) => switch (de) {
  'ATIVO' => const ['ACELERAR', 'STANDBY', 'FORMADO', 'CANCELADO'],
  'ACELERAR' => const ['ATIVO', 'STANDBY', 'FORMADO', 'CANCELADO'],
  'STANDBY' => const ['ATIVO', 'ACELERAR', 'TRANCADO', 'CANCELADO'],
  'TRANCADO' => const ['ATIVO', 'ACELERAR', 'CANCELADO'],
  'FORMADO' => const ['CANCELADO'],
  _ => const [],
};

/// Para onde a reversão de um terminal pode ir: qualquer status não terminal
/// (`fn_aluno_status_valida`, ramo de reversão). Vazio fora dos terminais.
List<String> destinosReversao(String de) => statusTerminais.contains(de)
    ? const ['ATIVO', 'ACELERAR', 'STANDBY', 'TRANCADO']
    : const [];

/// Sair de ATIVO/ACELERAR para qualquer outro status remove o aluno das
/// turmas — é o aviso do design-system §7.3 no diálogo de status.
bool saiDasTurmas({required String de, required String para}) =>
    statusEmAula.contains(de) && !statusEmAula.contains(para);

// ---------------------------------------------------------------------------
// Modelos
// ---------------------------------------------------------------------------

@immutable
class Aluno {
  const Aluno({
    this.id,
    required this.nome,
    required this.metodoId,
    this.codigoSgf,
    this.comboId,
    this.status = 'ATIVO',
    this.statusDesde,
    this.prevConclusaoCurso,
    this.dataInicio,
    this.observacoes,
    this.conferido = false,
  });

  factory Aluno.deLinha(Map<String, dynamic> linha) => Aluno(
    id: '${linha['id']}',
    nome: '${linha['nome']}',
    metodoId: '${linha['metodo_id']}',
    codigoSgf: linha['codigo_sgf'] as String?,
    comboId: linha['combo_id'] == null ? null : '${linha['combo_id']}',
    status: '${linha['status']}',
    statusDesde: _data(linha['status_desde']),
    prevConclusaoCurso: _data(linha['prev_conclusao_curso']),
    dataInicio: _data(linha['data_inicio']),
    observacoes: linha['observacoes'] as String?,
    conferido: linha['conferido'] as bool? ?? false,
  );

  static DateTime? _data(Object? valor) =>
      valor == null ? null : DateTime.parse('$valor');

  /// Nulo = ainda não gravado.
  final String? id;
  final String nome;

  /// O método não muda depois da matrícula (mesma decisão do card 4.4 para
  /// material, curso e combo): o combo, a trilha e as turmas são do método.
  final String metodoId;

  /// Referência externa ao SGF, opcional; única por unidade quando informada.
  /// Vazio vira nulo em [paraLinha] — string vazia colide no índice parcial.
  final String? codigoSgf;
  final String? comboId;

  /// Escrito só pelo banco: nasce `ATIVO` e muda por `fn_aluno_alterar_status`.
  final String status;
  final DateTime? statusDesde;

  /// Informada manualmente (decisão de 30/08/2026: não há regra de cálculo).
  final DateTime? prevConclusaoCurso;
  final DateTime? dataInicio;
  final String? observacoes;

  /// Marca de conferência da migração (card 9.4). A tela só mostra.
  final bool conferido;

  bool get terminal => statusTerminais.contains(status);
  bool get emAula => statusEmAula.contains(status);

  /// Só o que a tela edita. `status` e `status_desde` ficam de fora de
  /// propósito: status muda pela função de aplicação, nunca por `PATCH`, e
  /// reenviá-lo igual seria um no-op com cara de escrita.
  Map<String, dynamic> paraLinha(String unidadeId) => {
    'unidade_id': unidadeId,
    'nome': nome.trim(),
    'metodo_id': metodoId,
    'codigo_sgf': _ouNulo(codigoSgf),
    'combo_id': comboId,
    'prev_conclusao_curso': prevConclusaoCurso == null
        ? null
        : dataIso(prevConclusaoCurso!),
    if (dataInicio != null) 'data_inicio': dataIso(dataInicio!),
    'observacoes': _ouNulo(observacoes),
  };

  static String? _ouNulo(String? texto) =>
      (texto == null || texto.trim().isEmpty) ? null : texto.trim();
}

/// Uma linha de `aluno_status_hist`, como a aba Histórico a mostra.
@immutable
class TransicaoStatus {
  const TransicaoStatus({
    required this.id,
    this.statusAnterior,
    required this.statusNovo,
    required this.ocorridoEm,
    this.usuarioNome,
    this.motivo,
  });

  factory TransicaoStatus.deLinha(Map<String, dynamic> linha) {
    final usuario = linha['usuario'];
    return TransicaoStatus(
      id: '${linha['id']}',
      statusAnterior: linha['status_anterior'] as String?,
      statusNovo: '${linha['status_novo']}',
      ocorridoEm: DateTime.parse('${linha['ocorrido_em']}').toLocal(),
      usuarioNome: usuario is Map ? usuario['nome'] as String? : null,
      motivo: linha['motivo'] as String?,
    );
  }

  final String id;
  final String? statusAnterior;
  final String statusNovo;
  final DateTime ocorridoEm;

  /// Nome de quem mudou. Nulo quando a política de `usuario` não deixa ler a
  /// linha da pessoa — só `admin.ler` e o próprio usuário leem `usuario`
  /// (card 3.4), então secretaria e pedagógico veem o nome só das próprias
  /// transições. A tela mostra "quem" quando existe e nada quando não existe.
  final String? usuarioNome;
  final String? motivo;
}

// ---------------------------------------------------------------------------
// Filtros — estado da tela, desligável e visível (design-system §5.3)
// ---------------------------------------------------------------------------

/// Os filtros do plano (método, status, combo; turma entra na Fase 5) mais a
/// busca por nome/`codigo_sgf`. "Ocultar formados e cancelados" vem ligado por
/// padrão: os terminais se acumulam e a lista do dia a dia é de quem está em
/// curso; "Limpar filtros" mostra **tudo** (card 4.4 (g)).
@immutable
class FiltroAlunos {
  const FiltroAlunos({
    this.busca = '',
    this.metodoId,
    this.status,
    this.comboId,
    this.ocultarEncerrados = true,
  });

  static const semFiltro = FiltroAlunos(ocultarEncerrados: false);

  final String busca;
  final String? metodoId;
  final String? status;
  final String? comboId;
  final bool ocultarEncerrados;

  int get ativos =>
      (busca.trim().isNotEmpty ? 1 : 0) +
      (metodoId != null ? 1 : 0) +
      (status != null ? 1 : 0) +
      (comboId != null ? 1 : 0) +
      (ocultarEncerrados ? 1 : 0);

  FiltroAlunos copiar({
    String? busca,
    String? Function()? metodoId,
    String? Function()? status,
    String? Function()? comboId,
    bool? ocultarEncerrados,
  }) => FiltroAlunos(
    busca: busca ?? this.busca,
    metodoId: metodoId == null ? this.metodoId : metodoId(),
    status: status == null ? this.status : status(),
    comboId: comboId == null ? this.comboId : comboId(),
    ocultarEncerrados: ocultarEncerrados ?? this.ocultarEncerrados,
  );
}

bool _casaBusca(String busca, Iterable<String?> campos) {
  final termo = busca.trim().toLowerCase();
  if (termo.isEmpty) return true;
  return campos.any((c) => c != null && c.toLowerCase().contains(termo));
}

List<Aluno> filtrarAlunos(List<Aluno> todos, FiltroAlunos filtro) => [
  for (final a in todos)
    if ((!filtro.ocultarEncerrados || !a.terminal) &&
        (filtro.metodoId == null || a.metodoId == filtro.metodoId) &&
        (filtro.status == null || a.status == filtro.status) &&
        (filtro.comboId == null || a.comboId == filtro.comboId) &&
        _casaBusca(filtro.busca, [a.nome, a.codigoSgf]))
      a,
];
