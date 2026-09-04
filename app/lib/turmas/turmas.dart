/// As turmas como o app as vê (card 5.6): o modelo do bloco de horário
/// (`bloco_horario`, card 5.1), a célula da grade que `fn_grade_semana` devolve
/// e a lógica **pura** da tela — a semana, a montagem da grade, os alertas de
/// cada bloco e os filtros.
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
  bool get lotado => vagasLivres == 0 && !acimaCapacidade;

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
