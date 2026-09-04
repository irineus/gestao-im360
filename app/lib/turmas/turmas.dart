/// As turmas como o app as vê (cards 5.6 e 5.7): o modelo do bloco de horário
/// (`bloco_horario`, card 5.1), a célula da grade que `fn_grade_semana` devolve,
/// os alunos do bloco (`fn_bloco_alunos`) e as turmas de um aluno
/// (`v_bloco_alunos`), mais a lógica **pura** das duas telas — a semana, a
/// montagem da grade, os alertas de cada bloco, os filtros e os rótulos.
///
/// Pura de propósito: é o que se testa sem rede e sem cliente Supabase
/// (card 2.8 §9.3). Regra de negócio continua no banco; aqui só há forma.
/// Capacidade, ocupação e vagas **não são calculadas aqui** — chegam prontas da
/// grade, porque o card 5.2 é o dono da fórmula e uma segunda conta em Dart
/// divergiria em silêncio (docs/views-leitura.md §7).
library;

import 'package:flutter/foundation.dart';

import '../util/datas.dart';

export '../util/datas.dart';

/// Dias como o banco os numera: ISO, 1 = segunda … 7 = domingo, a mesma
/// numeração de `bloco_horario.dia_semana` e de `DateTime.weekday`.
const nomesDia = <int, String>{
  1: 'Segunda',
  2: 'Terça',
  3: 'Quarta',
  4: 'Quinta',
  5: 'Sexta',
  6: 'Sábado',
  7: 'Domingo',
};

const nomesDiaCurto = <int, String>{
  1: 'Seg',
  2: 'Ter',
  3: 'Qua',
  4: 'Qui',
  5: 'Sex',
  6: 'Sáb',
  7: 'Dom',
};

/// Os dias que a grade sempre mostra (docs/wireframes.md §7.1): Seg a Sáb.
/// Domingo entra só quando existe bloco nele — ver [diasDaGrade].
const diasPadrao = <int>[1, 2, 3, 4, 5, 6];

String nomeDia(int dia) => nomesDia[dia] ?? 'Dia $dia';
String nomeDiaCurto(int dia) => nomesDiaCurto[dia] ?? '$dia';

// ---------------------------------------------------------------------------
// Semana
// ---------------------------------------------------------------------------

/// A segunda-feira da semana que contém [dia].
///
/// Escrito com o construtor de `DateTime` e não com `subtract(Duration(days:))`:
/// `Duration` é tempo absoluto, e num dia de mudança de horário a subtração cai
/// às 23h do dia anterior — o que deslocaria a semana inteira em um dia, uma vez
/// por ano, sem nada na tela dizendo. O construtor normaliza o dia do mês.
DateTime segundaDe(DateTime dia) =>
    DateTime(dia.year, dia.month, dia.day - (dia.weekday - 1));

/// Rótulo da faixa de datas da semana: `31/08 a 05/09`. Vai até sábado, que é
/// o fim da semana da escola; com bloco no domingo, até domingo — senão o
/// rótulo diria uma coisa e a grade mostraria outra.
String rotuloSemana(DateTime segunda, {bool incluiDomingo = false}) {
  final inicio = segundaDe(segunda);
  final fim = DateTime(
    inicio.year,
    inicio.month,
    inicio.day + (incluiDomingo ? 6 : 5),
  );
  return '${formatarDataCurta(inicio)} a ${formatarDataCurta(fim)}';
}

/// `HH:MM` a partir do `HH:MM:SS` que o PostgREST devolve para `time`. Sem
/// isto a grade mostraria `08:00:00` em toda célula.
String horaHhMm(String hora) {
  final partes = hora.split(':');
  if (partes.length < 2) return hora;
  return '${partes[0].padLeft(2, '0')}:${partes[1].padLeft(2, '0')}';
}

/// Validação local só de formato (design-system §5.4). O horário é livre: a
/// escola pode criar o bloco que quiser, e quem recusa o duplicado é a `unique`
/// do banco.
final _formatoHora = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

String? validarHora(String? valor) {
  final texto = valor?.trim() ?? '';
  if (texto.isEmpty) return 'Campo obrigatório.';
  return _formatoHora.hasMatch(texto) ? null : 'Informe um horário como hh:mm.';
}

// ---------------------------------------------------------------------------
// Modelos
// ---------------------------------------------------------------------------

/// O bloco como a tabela `bloco_horario` o guarda — é o que o formulário grava.
/// A grade **não** é feita disto: ela vem de [CelulaGrade], que já traz as
/// parcelas do card 5.2 medidas na data.
@immutable
class BlocoHorario {
  const BlocoHorario({
    this.id,
    required this.diaSemana,
    required this.horaInicio,
    required this.metodoId,
    required this.salaId,
    this.professorId,
    this.capacidadeOverride,
    this.ativo = true,
  });

  factory BlocoHorario.deLinha(Map<String, dynamic> linha) => BlocoHorario(
    id: '${linha['id']}',
    diaSemana: (linha['dia_semana'] as num).toInt(),
    horaInicio: horaHhMm('${linha['hora_inicio']}'),
    metodoId: '${linha['metodo_id']}',
    salaId: '${linha['sala_id']}',
    professorId: linha['professor_id'] == null
        ? null
        : '${linha['professor_id']}',
    capacidadeOverride: (linha['capacidade_override'] as num?)?.toInt(),
    ativo: linha['ativo'] as bool? ?? true,
  );

  /// Nulo = ainda não gravado.
  final String? id;
  final int diaSemana;

  /// `HH:MM` — o formato que a tela mostra e que o Postgres aceita em `time`.
  final String horaInicio;
  final String metodoId;
  final String salaId;
  final String? professorId;

  /// Teto manual. Nulo é o caso normal: a capacidade sai dos PCs da sala
  /// (`fn_capacidade_efetiva`, card 5.2). Nunca 0 — bloco fechado é
  /// `ativo = false`, e o `check` do banco recusa 0.
  final int? capacidadeOverride;
  final bool ativo;

  Map<String, dynamic> paraLinha(String unidadeId) => {
    'unidade_id': unidadeId,
    'dia_semana': diaSemana,
    'hora_inicio': horaInicio,
    'metodo_id': metodoId,
    'sala_id': salaId,
    'professor_id': professorId,
    'capacidade_override': capacidadeOverride,
    'ativo': ativo,
  };
}

/// Uma linha de `fn_grade_semana`: o bloco **numa data**, com as três parcelas
/// do card 5.2 já medidas nela.
@immutable
class CelulaGrade {
  const CelulaGrade({
    required this.blocoId,
    required this.diaSemana,
    required this.horaInicio,
    required this.dataReferencia,
    required this.metodoId,
    required this.metodoCodigo,
    required this.salaId,
    required this.salaNome,
    this.professorId,
    this.professorNome,
    this.capacidadeOverride,
    required this.capacidade,
    required this.ocupacao,
    required this.vagasLivres,
    required this.acimaCapacidade,
  });

  factory CelulaGrade.deLinha(Map<String, dynamic> linha) => CelulaGrade(
    blocoId: '${linha['bloco_id']}',
    diaSemana: (linha['dia_semana'] as num).toInt(),
    horaInicio: horaHhMm('${linha['hora_inicio']}'),
    dataReferencia: DateTime.parse('${linha['data_referencia']}'),
    metodoId: '${linha['metodo_id']}',
    metodoCodigo: '${linha['metodo_codigo']}',
    salaId: '${linha['sala_id']}',
    salaNome: '${linha['sala_nome']}',
    professorId: linha['professor_id'] == null
        ? null
        : '${linha['professor_id']}',
    professorNome: linha['professor_nome'] as String?,
    capacidadeOverride: (linha['capacidade_override'] as num?)?.toInt(),
    capacidade: (linha['capacidade'] as num?)?.toInt() ?? 0,
    ocupacao: (linha['ocupacao'] as num?)?.toInt() ?? 0,
    vagasLivres: (linha['vagas_livres'] as num?)?.toInt() ?? 0,
    acimaCapacidade: linha['acima_capacidade'] as bool? ?? false,
  );

  final String blocoId;
  final int diaSemana;
  final String horaInicio;
  final DateTime dataReferencia;
  final String metodoId;
  final String metodoCodigo;
  final String salaId;
  final String salaNome;
  final String? professorId;

  /// Nulo tem **dois** significados e a tela não os separa: bloco sem professor
  /// definido (a planilha tem vários) e professor que o leitor não pode ler.
  /// O segundo não acontece com a matriz inicial — `professores.ler` é dos
  /// quatro perfis exatamente por isto (card 2.4) —, e o teste 095 é quem
  /// guarda essa premissa do lado do banco.
  final String? professorNome;

  final int? capacidadeOverride;
  final int capacidade;
  final int ocupacao;
  final int vagasLivres;
  final bool acimaCapacidade;

  bool get semProfessor => professorNome == null;

  /// ⚠️ Exige **capacidade maior que zero**: todos os PCs da sala em manutenção
  /// dão `0/0`, e sem esta condição o bloco aparecia como "lotado" — que é o
  /// oposto do que houve. Bloco sem capacidade não está cheio: não há o que
  /// ocupar, e é isso que a pendência `PC_SEM_SUBSTITUTO` descreve.
  bool get lotado => capacidade > 0 && vagasLivres == 0 && !acimaCapacidade;

  /// Sem nenhum lugar — a sala perdeu os PCs (card 5.4).
  bool get semCapacidade => capacidade == 0 && !acimaCapacidade;

  /// `8/10` — a leitura da célula do wireframe §7.1.
  String get ocupacaoTexto => '$ocupacao/$capacidade';

  /// O bloco como a tabela o guarda, para abrir o formulário de edição sem uma
  /// segunda consulta. `ativo` é sempre verdadeiro: a grade só traz ativos.
  BlocoHorario get bloco => BlocoHorario(
    id: blocoId,
    diaSemana: diaSemana,
    horaInicio: horaInicio,
    metodoId: metodoId,
    salaId: salaId,
    professorId: professorId,
    capacidadeOverride: capacidadeOverride,
  );
}

// ---------------------------------------------------------------------------
// Alertas da célula — o vocabulário visual do wireframe §7.1
// ---------------------------------------------------------------------------

/// Os dois estados que a célula sinaliza. `lotado` não é alerta: é o sistema
/// funcionando (card 3.12 (c)), e por isso não entra aqui.
enum AlertaBloco {
  /// Ocupação maior que a capacidade — o mesmo fato da pendência
  /// `BLOCO_ACIMA_CAPACIDADE` (card 5.5). Vermelho e ⚠.
  acimaCapacidade,

  /// Bloco sem professor definido. Âmbar e ⚠.
  semProfessor,
}

Set<AlertaBloco> alertasDo(CelulaGrade celula) => {
  if (celula.acimaCapacidade) AlertaBloco.acimaCapacidade,
  if (celula.semProfessor) AlertaBloco.semProfessor,
};

// ---------------------------------------------------------------------------
// Filtros — estado da tela, desligável e visível (design-system §5.3)
// ---------------------------------------------------------------------------

@immutable
class FiltroGrade {
  const FiltroGrade({this.metodoId, this.salaId});

  static const semFiltro = FiltroGrade();

  final String? metodoId;
  final String? salaId;

  int get ativos => (metodoId != null ? 1 : 0) + (salaId != null ? 1 : 0);

  FiltroGrade copiar({
    String? Function()? metodoId,
    String? Function()? salaId,
  }) => FiltroGrade(
    metodoId: metodoId == null ? this.metodoId : metodoId(),
    salaId: salaId == null ? this.salaId : salaId(),
  );
}

List<CelulaGrade> filtrarGrade(List<CelulaGrade> todas, FiltroGrade filtro) => [
  for (final c in todas)
    if ((filtro.metodoId == null || c.metodoId == filtro.metodoId) &&
        (filtro.salaId == null || c.salaId == filtro.salaId))
      c,
];

// ---------------------------------------------------------------------------
// Montagem da grade
// ---------------------------------------------------------------------------

/// Os dias que a grade mostra: sempre Seg–Sáb, mais domingo **quando houver
/// bloco nele**.
///
/// A coluna fixa existe para a grade não mudar de forma a cada semana; a exceção
/// do domingo existe porque `dia_semana` aceita 7 (card 5.1) e um bloco de
/// domingo desapareceria da tela sem erro nenhum — a família de falha calada que
/// este projeto cataloga.
List<int> diasDaGrade(Iterable<CelulaGrade> celulas) {
  final extras = {
    for (final c in celulas)
      if (!diasPadrao.contains(c.diaSemana)) c.diaSemana,
  };
  return [...diasPadrao, ...extras.toList()..sort()];
}

/// A grade pronta para desenhar: as linhas (horários), as colunas (dias) e o
/// que há em cada cruzamento.
@immutable
class GradeSemana {
  const GradeSemana({
    required this.segunda,
    required this.dias,
    required this.horas,
    required this.celulas,
  });

  final DateTime segunda;
  final List<int> dias;

  /// Horários presentes, em ordem — a grade não inventa linha de horário que
  /// não tem bloco nenhum.
  final List<String> horas;

  final Map<String, List<CelulaGrade>> celulas;

  bool get vazia => horas.isEmpty;

  /// **Lista**, e não um bloco: a `unique` de `bloco_horario` é por
  /// `(unidade, sala, dia, hora)`, então duas salas podem ter aula no mesmo
  /// dia e horário (card 5.1). Uma célula que guardasse só um deles perderia a
  /// outra turma em silêncio; quem separa é o filtro de sala.
  List<CelulaGrade> em(int dia, String hora) =>
      celulas['$dia|$hora'] ?? const [];

  DateTime dataDe(int dia) =>
      DateTime(segunda.year, segunda.month, segunda.day + (dia - 1));
}

GradeSemana montarGrade(DateTime segunda, List<CelulaGrade> celulas) {
  final horas = (celulas.map((c) => c.horaInicio).toSet().toList())..sort();
  final mapa = <String, List<CelulaGrade>>{};
  for (final c in celulas) {
    (mapa['${c.diaSemana}|${c.horaInicio}'] ??= []).add(c);
  }
  for (final lista in mapa.values) {
    lista.sort((a, b) => a.salaNome.compareTo(b.salaNome));
  }
  return GradeSemana(
    segunda: segundaDe(segunda),
    dias: diasDaGrade(celulas),
    horas: horas,
    celulas: mapa,
  );
}

// ---------------------------------------------------------------------------
// Card 5.7 — os alunos do bloco e as turmas do aluno
// ---------------------------------------------------------------------------

/// Os quatro tipos do `check` de `bloco_aluno.tipo` (card 5.1) e o que cada um
/// significa em tela. A chave é o valor do banco; o app nunca compara pelo
/// rótulo — mesma convenção de [statusAluno] no card 4.6.
const tiposNaTurma = <String, String>{
  'REM': 'Remoto',
  'PRE': 'Presencial',
  'REP': 'Reposição contínua',
  'NOVO': 'Novo',
};

String rotuloTipo(String tipo) => tiposNaTurma[tipo] ?? tipo;

/// `Seg 08:00` — como um bloco se nomeia em toda tela que não é a grade
/// (coluna Turmas da lista de alunos, aba Turmas da ficha, rótulo da reposição).
String rotuloBloco(int diaSemana, String horaInicio) =>
    '${nomeDiaCurto(diaSemana)} ${horaHhMm(horaInicio)}';

/// O que uma linha da lista de alunos do bloco é: alocação (vale toda semana)
/// ou reposição pontual (vale só no dia). É a coluna `origem` de
/// `fn_bloco_alunos`, e a separação existe porque as duas metades do REP
/// híbrido (decisão de 31/08/2026) se removem por funções diferentes.
enum OrigemNoBloco { alocacao, reposicao }

OrigemNoBloco _origem(String valor) =>
    valor == 'REPOSICAO' ? OrigemNoBloco.reposicao : OrigemNoBloco.alocacao;

/// Uma linha de `fn_bloco_alunos` — o aluno **naquele bloco naquela data**.
@immutable
class AlunoDoBloco {
  const AlunoDoBloco({
    required this.origem,
    required this.registroId,
    required this.alunoId,
    required this.alunoNome,
    this.codigoSgf,
    required this.alunoStatus,
    required this.tipo,
    this.tipoDesde,
    this.dataInicioPrevista,
    this.blocoAtivo = true,
    this.data,
    this.blocoOrigemId,
    this.blocoOrigemDia,
    this.blocoOrigemHora,
    this.dataOrigem,
    this.observacao,
  });

  factory AlunoDoBloco.deLinha(Map<String, dynamic> linha) => AlunoDoBloco(
    origem: _origem('${linha['origem']}'),
    registroId: '${linha['registro_id']}',
    alunoId: '${linha['aluno_id']}',
    alunoNome: '${linha['aluno_nome']}',
    codigoSgf: linha['codigo_sgf'] as String?,
    alunoStatus: '${linha['aluno_status']}',
    tipo: '${linha['tipo']}',
    tipoDesde: _data(linha['tipo_desde']),
    dataInicioPrevista: _data(linha['data_inicio_prevista']),
    blocoAtivo: linha['bloco_ativo'] as bool? ?? true,
    data: _data(linha['data']),
    blocoOrigemId: linha['bloco_origem_id'] == null
        ? null
        : '${linha['bloco_origem_id']}',
    blocoOrigemDia: (linha['bloco_origem_dia'] as num?)?.toInt(),
    blocoOrigemHora: linha['bloco_origem_hora'] as String?,
    dataOrigem: _data(linha['data_origem']),
    observacao: linha['observacao'] as String?,
  );

  final OrigemNoBloco origem;

  /// `bloco_aluno.id` na alocação, `bloco_aluno_reposicao.id` na reposição —
  /// as duas metades se desfazem por funções diferentes, então a tela precisa
  /// saber de qual tabela a linha veio.
  final String registroId;

  final String alunoId;
  final String alunoNome;
  final String? codigoSgf;
  final String alunoStatus;

  /// REM/PRE/REP/NOVO na alocação; sempre `REP` na reposição pontual.
  final String tipo;
  final DateTime? tipoDesde;
  final DateTime? dataInicioPrevista;

  /// Falso quando o bloco foi desativado e a alocação ficou de pé (card 5.6).
  final bool blocoAtivo;

  /// A data da reposição; nula na alocação, que não é de um dia.
  final DateTime? data;

  final String? blocoOrigemId;
  final int? blocoOrigemDia;
  final String? blocoOrigemHora;
  final DateTime? dataOrigem;
  final String? observacao;

  bool get ehReposicao => origem == OrigemNoBloco.reposicao;

  /// `reposição de Qua 27/08` — o rótulo do wireframe §7.2. O bloco de origem é
  /// nulo de propósito (card 2.5 §3.1: a escola nem sempre sabe qual encontro
  /// foi perdido), e aí a linha diz o que sabe em vez de inventar.
  String? get rotuloReposicao {
    if (!ehReposicao) return null;
    final dia = blocoOrigemDia;
    final hora = blocoOrigemHora;
    final quando = dataOrigem;
    if (dia == null || hora == null) {
      return quando == null
          ? 'reposição avulsa'
          : 'reposição de ${formatarDataCurta(quando)}';
    }
    final origemBloco = rotuloBloco(dia, hora);
    return quando == null
        ? 'reposição de $origemBloco'
        : 'reposição de $origemBloco ${formatarDataCurta(quando)}';
  }
}

/// Quantos são fixos e quantos são reposição do dia — o
/// `8/10 (7 fixos + 1 reposição hoje)` do cabeçalho do wireframe §7.2.
///
/// A soma tem de bater com `ocupacao` da célula da grade, e é o banco que
/// garante isso (`fn_bloco_alunos` e `fn_ocupacao_bloco` contam o mesmo
/// conjunto, asserido no teste 043). Aqui só se conta o que veio.
String resumoLotacao(List<AlunoDoBloco> lista, {required int capacidade}) {
  final reposicoes = lista.where((a) => a.ehReposicao).length;
  final fixos = lista.length - reposicoes;
  final detalhe = reposicoes == 0
      ? '$fixos ${fixos == 1 ? 'aluno' : 'alunos'}'
      : '$fixos ${fixos == 1 ? 'fixo' : 'fixos'} + $reposicoes '
            '${reposicoes == 1 ? 'reposição' : 'reposições'} no dia';
  return 'Ocupação ${lista.length}/$capacidade ($detalhe)';
}

/// Uma linha de `v_bloco_alunos` vista **do lado do aluno**: a alocação dele
/// num bloco. É o que a aba Turmas da ficha lista e o que a coluna Turmas da
/// lista de alunos resume.
@immutable
class TurmaDoAluno {
  const TurmaDoAluno({
    required this.alocacaoId,
    required this.blocoId,
    required this.alunoId,
    required this.diaSemana,
    required this.horaInicio,
    required this.metodoId,
    required this.salaId,
    required this.blocoAtivo,
    required this.tipo,
    this.tipoDesde,
    this.dataInicioPrevista,
  });

  factory TurmaDoAluno.deLinha(Map<String, dynamic> linha) => TurmaDoAluno(
    alocacaoId: '${linha['alocacao_id']}',
    blocoId: '${linha['bloco_id']}',
    alunoId: '${linha['aluno_id']}',
    diaSemana: (linha['dia_semana'] as num).toInt(),
    horaInicio: horaHhMm('${linha['hora_inicio']}'),
    metodoId: '${linha['metodo_id']}',
    salaId: '${linha['sala_id']}',
    blocoAtivo: linha['bloco_ativo'] as bool? ?? true,
    tipo: '${linha['tipo']}',
    tipoDesde: _data(linha['tipo_desde']),
    dataInicioPrevista: _data(linha['data_inicio_prevista']),
  );

  final String alocacaoId;
  final String blocoId;
  final String alunoId;
  final int diaSemana;
  final String horaInicio;
  final String metodoId;
  final String salaId;

  /// Falso = o bloco foi desativado e a alocação ficou órfã. A ficha mostra
  /// assim mesmo, marcada: é a única tela de onde alguém a desfaz.
  final bool blocoAtivo;

  final String tipo;
  final DateTime? tipoDesde;
  final DateTime? dataInicioPrevista;

  String get rotulo => rotuloBloco(diaSemana, horaInicio);
}

/// Os ids dos alunos que estão em pelo menos uma turma **que existe**.
///
/// É a mesma definição de `rt_pendencias_diaria` desde o card 5.7 — alocação em
/// bloco desativado não conta —, e é por isso que o ⚠ da lista e a pendência
/// `ALUNO_SEM_TURMA` dizem a mesma coisa. Duas contas diferentes divergiriam no
/// dia em que alguém mexesse numa só (card 5.4 (4)).
Set<String> alunosEmTurma(Iterable<TurmaDoAluno> turmas) => {
  for (final t in turmas)
    if (t.blocoAtivo) t.alunoId,
};

/// Turmas por aluno, na ordem em que a tela as mostra (dia, depois hora).
Map<String, List<TurmaDoAluno>> agruparPorAluno(List<TurmaDoAluno> turmas) {
  final mapa = <String, List<TurmaDoAluno>>{};
  for (final t in turmas) {
    (mapa[t.alunoId] ??= []).add(t);
  }
  for (final lista in mapa.values) {
    lista.sort((a, b) {
      final dia = a.diaSemana.compareTo(b.diaSemana);
      return dia != 0 ? dia : a.horaInicio.compareTo(b.horaInicio);
    });
  }
  return mapa;
}

/// `Seg 08:00 · Qua 08:00` — a coluna Turmas do wireframe §6.1. Vazio vira `—`,
/// e quem decide se isso merece ⚠ é [alunosEmTurma], não este rótulo.
String rotuloTurmasDoAluno(List<TurmaDoAluno> turmas) {
  final ativas = [
    for (final t in turmas)
      if (t.blocoAtivo) t.rotulo,
  ];
  return ativas.isEmpty ? '—' : ativas.join(' · ');
}

/// Uma linha de `bloco_aluno_reposicao` do aluno — a metade pontual do REP
/// híbrido, como a aba Turmas da ficha a lista.
@immutable
class ReposicaoAluno {
  const ReposicaoAluno({
    required this.id,
    required this.blocoId,
    required this.alunoId,
    required this.data,
    required this.status,
    this.blocoOrigemId,
    this.dataOrigem,
    this.observacao,
  });

  factory ReposicaoAluno.deLinha(Map<String, dynamic> linha) => ReposicaoAluno(
    id: '${linha['id']}',
    blocoId: '${linha['bloco_id']}',
    alunoId: '${linha['aluno_id']}',
    data: DateTime.parse('${linha['data']}'),
    status: '${linha['status']}',
    blocoOrigemId: linha['bloco_origem_id'] == null
        ? null
        : '${linha['bloco_origem_id']}',
    dataOrigem: _data(linha['data_origem']),
    observacao: linha['observacao'] as String?,
  );

  final String id;
  final String blocoId;
  final String alunoId;
  final DateTime data;

  /// PREVISTA / REALIZADA / FALTOU / CANCELADA (card 5.1). Só PREVISTA ocupa
  /// vaga, e só ela se cancela ou se registra.
  final String status;

  final String? blocoOrigemId;
  final DateTime? dataOrigem;
  final String? observacao;

  bool get prevista => status == 'PREVISTA';
}

const statusReposicao = <String, String>{
  'PREVISTA': 'Prevista',
  'REALIZADA': 'Realizada',
  'FALTOU': 'Faltou',
  'CANCELADA': 'Cancelada',
};

String rotuloStatusReposicao(String status) =>
    statusReposicao[status] ?? status;

/// O retorno de `fn_rep_situacao` (`tp_rep_situacao`, card 5.3): os números do
/// critério do card 2.5 §3 mais o veredito. A ficha os mostra porque
/// "sugerido virar contínuo" sozinho não é acionável — "3 aulas em aberto, a
/// mais antiga de 12/09, prazo até 12/10, cabem 2" é.
@immutable
class SituacaoRep {
  const SituacaoRep({
    required this.debito,
    this.aulaMaisAntiga,
    this.prazoFinal,
    required this.semanasUteis,
    required this.capacidade,
    required this.faltasRecentes,
    this.repDesde,
    required this.veredito,
  });

  factory SituacaoRep.deLinha(Map<String, dynamic> linha) => SituacaoRep(
    debito: (linha['debito'] as num?)?.toInt() ?? 0,
    aulaMaisAntiga: _data(linha['aula_mais_antiga']),
    prazoFinal: _data(linha['prazo_final']),
    semanasUteis: (linha['semanas_uteis'] as num?)?.toInt() ?? 0,
    capacidade: (linha['capacidade'] as num?)?.toInt() ?? 0,
    faltasRecentes: (linha['faltas_recentes'] as num?)?.toInt() ?? 0,
    repDesde: _data(linha['rep_desde']),
    veredito: '${linha['veredito']}',
  );

  final int debito;
  final DateTime? aulaMaisAntiga;
  final DateTime? prazoFinal;
  final int semanasUteis;
  final int capacidade;
  final int faltasRecentes;

  /// Não nulo = o aluno já é REP contínuo, e esta é a data em que virou.
  final DateTime? repDesde;

  /// MANTER | SUGERIR_CONTINUO | SUGERIR_VOLTA.
  final String veredito;

  bool get continuo => repDesde != null;

  /// A ficha só mostra o painel quando há o que dizer: débito em aberto, aluno
  /// já contínuo, ou um veredito diferente de "está tudo em ordem".
  bool get relevante => debito > 0 || continuo || veredito != 'MANTER';
}

/// Os números do critério do card 2.5 §3 em uma linha, na ordem em que se lê:
/// débito, aula mais antiga, prazo, quanto cabe até lá.
///
/// Mora aqui, e não na aba Turmas da ficha, porque a **central de pendências**
/// (card 5.8) mostra exatamente a mesma frase ao lado do `REP_VIRADA` — e é ela
/// que torna a sugestão acionável ("3 aulas em aberto, prazo até 12/10, cabem
/// 2" decide; "sugerido virar contínuo" não). Duas cópias divergiriam na
/// primeira vez que alguém mexesse numa só (card 5.4 (4)).
List<String> resumoSituacaoRep(SituacaoRep s) => [
  '${s.debito} aula(s) a repor em aberto',
  if (s.aulaMaisAntiga != null)
    'mais antiga em ${formatarData(s.aulaMaisAntiga!)}',
  if (s.prazoFinal != null) 'prazo até ${formatarData(s.prazoFinal!)}',
  // "cabem N até lá" só existe quando há um "lá": sem prazo (aluno contínuo em
  // dia, sem aula em aberto) a frase saía como "cabem 0 até lá", que soa a
  // impossibilidade e é só ausência de prazo.
  if (s.prazoFinal != null) 'cabem ${s.semanasUteis * s.capacidade} até lá',
  if (s.faltasRecentes > 0) '${s.faltasRecentes} falta(s) recente(s)',
  if (s.repDesde != null)
    'em reposição contínua desde ${formatarData(s.repDesde!)}',
];

/// O que cada veredito significa para quem acabou de marcar uma falta — é o
/// texto que o §7.2 manda mostrar na hora, e não no dia seguinte, quando a
/// rotina do card 5.5 abrir a pendência.
const vereditosRep = <String, String>{
  'SUGERIR_CONTINUO':
      'As aulas a repor não cabem mais no prazo. O sistema sugere passar este '
      'aluno para reposição contínua — a decisão é de uma pessoa, e a '
      'sugestão está na central de pendências.',
  'SUGERIR_VOLTA':
      'Este aluno está em dia e fora da carência. O sistema sugere devolvê-lo a '
      'reposição pontual, liberando a vaga fixa — a sugestão está na central '
      'de pendências.',
};

String? avisoVeredito(String veredito) => vereditosRep[veredito];

DateTime? _data(Object? valor) =>
    valor == null ? null : DateTime.parse('$valor');
