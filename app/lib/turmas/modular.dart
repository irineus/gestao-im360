/// As turmas **Modular** como o app as vê (card 7.3): a turma
/// (`v_turma_modular_lotacao`), a linha do cronograma
/// (`v_turma_modular_cronograma`), o aluno da turma (`v_turma_modular_aluno`) e
/// a lógica **pura** da tela 5 — os filtros, os rótulos e a leitura do
/// cronograma.
///
/// Pura de propósito: é o que se testa sem rede e sem cliente Supabase
/// (card 2.8 §9.3). Regra de negócio continua no banco (card 7.2); aqui só há
/// forma.
///
/// ⚠️ **Nada aqui calcula lotação, vaga ou módulo corrente.** Os três chegam
/// prontos das views: a capacidade da turma Modular é COLUNA (a sala modular não
/// tem PC, então não existe `fn_capacidade_efetiva` que a produza), e o módulo
/// corrente é o primeiro não concluído por `modulo.ordem`, definido em
/// `fn_turma_modular_modulo_corrente` (card 7.2). Uma segunda conta em Dart
/// divergiria em silêncio — card 2.3 §4.1.
library;

import 'package:flutter/foundation.dart';

import '../util/datas.dart';
import '../util/texto.dart';

export '../util/datas.dart';

// ---------------------------------------------------------------------------
// A turma
// ---------------------------------------------------------------------------

/// Uma linha de `v_turma_modular_lotacao`: a turma ATIVA com lotação e módulo
/// corrente já resolvidos.
@immutable
class TurmaModular {
  const TurmaModular({
    required this.id,
    required this.nome,
    required this.cursoId,
    required this.cursoNome,
    required this.salaId,
    required this.salaNome,
    required this.capacidade,
    required this.alocados,
    required this.vagasLivres,
    this.moduloCorrenteId,
    this.moduloCorrenteNome,
    this.moduloCorrenteOrdem,
    this.moduloCorrenteInicio,
    this.moduloCorrentePrevConclusao,
    this.moduloAtrasado = false,
  });

  factory TurmaModular.deLinha(Map<String, dynamic> linha) => TurmaModular(
    id: '${linha['turma_id']}',
    nome: '${linha['turma_nome']}',
    cursoId: '${linha['curso_id']}',
    cursoNome: '${linha['curso_nome']}',
    salaId: '${linha['sala_id']}',
    salaNome: '${linha['sala_nome']}',
    capacidade: (linha['capacidade'] as num?)?.toInt() ?? 0,
    alocados: (linha['alocados'] as num?)?.toInt() ?? 0,
    vagasLivres: (linha['vagas_livres'] as num?)?.toInt() ?? 0,
    moduloCorrenteId: linha['modulo_corrente_id'] == null
        ? null
        : '${linha['modulo_corrente_id']}',
    moduloCorrenteNome: linha['modulo_corrente_nome'] as String?,
    moduloCorrenteOrdem: (linha['modulo_corrente_ordem'] as num?)?.toInt(),
    moduloCorrenteInicio: _data(linha['modulo_corrente_inicio']),
    moduloCorrentePrevConclusao: _data(linha['modulo_corrente_prev_conclusao']),
    moduloAtrasado: linha['modulo_atrasado'] as bool? ?? false,
  );

  final String id;
  final String nome;
  final String cursoId;
  final String cursoNome;
  final String salaId;
  final String salaNome;

  /// Teto da turma — **coluna**, não conta de PC (card 7.1).
  final int capacidade;
  final int alocados;
  final int vagasLivres;

  /// Nulo tem **dois** sentidos, e a tela os separa pelo cronograma: turma com
  /// tudo concluído ("turma terminou") e turma sem cronograma nenhum. É a mesma
  /// ambiguidade que `fn_turma_modular_avancar` resolve com duas mensagens
  /// (`TURMA_SEM_MODULO_CORRENTE` × `TURMA_SEM_CRONOGRAMA`).
  final String? moduloCorrenteId;
  final String? moduloCorrenteNome;
  final int? moduloCorrenteOrdem;
  final DateTime? moduloCorrenteInicio;
  final DateTime? moduloCorrentePrevConclusao;

  /// Previsão do módulo corrente vencida — vem da **view**, medida com
  /// `fn_hoje()`. Nunca recalculado aqui: o relógio do aparelho pode estar em
  /// outro fuso, e a turma apareceria atrasada um dia antes ou depois.
  final bool moduloAtrasado;

  bool get semModuloCorrente => moduloCorrenteId == null;

  /// Ocupação maior que a capacidade. Estado real — o importador do card 9.1
  /// pode trazer uma turma assim, e `vagas_livres` tem piso zero de propósito.
  bool get acimaCapacidade => alocados > capacidade;

  bool get lotada => capacidade > 0 && vagasLivres == 0 && !acimaCapacidade;

  /// `8/10` — a leitura do cabeçalho do wireframe §8.
  String get lotacaoTexto => '$alocados/$capacidade';

  /// `3. Massoterapia` — a forma do wireframe §8. Sem ordem, só o nome.
  String? get moduloCorrenteRotulo {
    final nome = moduloCorrenteNome;
    if (nome == null) return null;
    final ordem = moduloCorrenteOrdem;
    return ordem == null ? nome : '$ordem. $nome';
  }
}

// ---------------------------------------------------------------------------
// O cronograma
// ---------------------------------------------------------------------------

/// Uma linha de `v_turma_modular_cronograma`: um módulo do cronograma da turma,
/// já na ordem do catálogo.
@immutable
class ModuloDaTurma {
  const ModuloDaTurma({
    required this.id,
    required this.turmaId,
    required this.moduloId,
    required this.moduloNome,
    required this.moduloOrdem,
    required this.materialId,
    this.dataInicio,
    this.prevConclusao,
    this.concluido = false,
    this.corrente = false,
    this.atrasado = false,
  });

  factory ModuloDaTurma.deLinha(Map<String, dynamic> linha) => ModuloDaTurma(
    id: '${linha['cronograma_id']}',
    turmaId: '${linha['turma_id']}',
    moduloId: '${linha['modulo_id']}',
    moduloNome: '${linha['modulo_nome']}',
    moduloOrdem: (linha['modulo_ordem'] as num?)?.toInt() ?? 0,
    materialId: '${linha['material_id']}',
    dataInicio: _data(linha['data_inicio']),
    prevConclusao: _data(linha['prev_conclusao']),
    concluido: linha['concluido'] as bool? ?? false,
    corrente: linha['corrente'] as bool? ?? false,
    atrasado: linha['atrasado'] as bool? ?? false,
  );

  /// `turma_modular_modulo.id` — é o que a edição de datas atualiza.
  final String id;
  final String turmaId;
  final String moduloId;
  final String moduloNome;
  final int moduloOrdem;
  final String materialId;
  final DateTime? dataInicio;
  final DateTime? prevConclusao;
  final bool concluido;

  /// O primeiro não concluído por ordem — vem da view, que usa a mesma
  /// expressão de `fn_turma_modular_modulo_corrente`.
  final bool corrente;
  final bool atrasado;

  bool get semDatas => dataInicio == null && prevConclusao == null;

  /// O marcador do wireframe §8: `✓` concluído, `►` corrente, nada nos demais.
  /// **Nunca sozinho** — a tela sempre põe o número do módulo ao lado, porque
  /// símbolo não é portador único (design-system §8.2).
  EstadoModulo get estado => concluido
      ? EstadoModulo.concluido
      : corrente
      ? EstadoModulo.corrente
      : EstadoModulo.futuro;

  /// `01/08–20/09`, `desde 01/08`, `até 20/09` ou `sem datas` — o que a linha
  /// sabe, sem inventar a metade que falta.
  ///
  /// ⚠️ O ano entra quando o intervalo cruza anos ou sai do ano corrente: sem
  /// ele, `09/11/2025 → 27/07/2026` saía como `09/11–27/07`, que se lê ao
  /// contrário (item B3). Quem decide é [formatarPeriodo].
  String get periodo {
    if (semDatas) return semDatasTexto;
    return formatarPeriodo(dataInicio, prevConclusao, hojeSaoPaulo());
  }
}

enum EstadoModulo { concluido, corrente, futuro }

const semDatasTexto = 'sem datas';

/// O rótulo completo de um módulo na faixa do cronograma: `3. Massoterapia`.
String rotuloModulo(int ordem, String nome) => '$ordem. $nome';

/// Os `modulo_id` que **já estão** no cronograma da turma.
///
/// A view só lista o que já foi incluído; quem descobre o que falta é a tela,
/// comparando com o catálogo do curso (`modulo`, que ela já lê). É a diferença
/// que o botão "Montar cronograma" grava — e é a ausência dela que produz a
/// pendência `TURMA_MODULAR_SEM_CRONOGRAMA` e faz a projeção Modular cair para
/// a média do método (wireframe §8).
Set<String> modulosNoCronograma(Iterable<ModuloDaTurma> linhas) => {
  for (final m in linhas) m.moduloId,
};

// ---------------------------------------------------------------------------
// Os alunos da turma
// ---------------------------------------------------------------------------

/// Uma linha de `v_turma_modular_aluno`.
@immutable
class AlunoDaTurmaModular {
  const AlunoDaTurmaModular({
    required this.alocacaoId,
    required this.turmaId,
    required this.alunoId,
    required this.alunoNome,
    this.codigoSgf,
    required this.alunoStatus,
    required this.metodoId,
    required this.dataEntrada,
    this.ativo = true,
    this.motivoSaida,
  });

  factory AlunoDaTurmaModular.deLinha(Map<String, dynamic> linha) =>
      AlunoDaTurmaModular(
        alocacaoId: '${linha['alocacao_id']}',
        turmaId: '${linha['turma_id']}',
        alunoId: '${linha['aluno_id']}',
        alunoNome: '${linha['aluno_nome']}',
        codigoSgf: linha['codigo_sgf'] as String?,
        alunoStatus: '${linha['aluno_status']}',
        metodoId: '${linha['metodo_id']}',
        dataEntrada: DateTime.parse('${linha['data_entrada']}'),
        ativo: linha['ativo'] as bool? ?? true,
        motivoSaida: linha['motivo_saida'] as String?,
      );

  final String alocacaoId;
  final String turmaId;
  final String alunoId;
  final String alunoNome;
  final String? codigoSgf;
  final String alunoStatus;
  final String metodoId;
  final DateTime dataEntrada;

  /// Falso = saiu da turma. Pode ter saído **sem ator**, por
  /// `tg_aluno_status_desaloca`, quando deixou de ser ATIVO/ACELERAR.
  final bool ativo;
  final String? motivoSaida;
}

/// Alunos por turma, ativos primeiro e por nome dentro de cada metade.
///
/// Os inativos ficam na lista de propósito (a view os traz): `motivo_saida` é a
/// única leitura do sistema que responde "por que fulano não está mais aqui".
/// Quem ocupa vaga é só o ativo, e quem conta é a view de lotação.
Map<String, List<AlunoDaTurmaModular>> agruparPorTurma(
  Iterable<AlunoDaTurmaModular> alunos,
) {
  final mapa = <String, List<AlunoDaTurmaModular>>{};
  for (final a in alunos) {
    (mapa[a.turmaId] ??= []).add(a);
  }
  for (final lista in mapa.values) {
    lista.sort((a, b) {
      if (a.ativo != b.ativo) return a.ativo ? -1 : 1;
      return a.alunoNome.toLowerCase().compareTo(b.alunoNome.toLowerCase());
    });
  }
  return mapa;
}

/// Linhas do cronograma por turma, na ordem do catálogo.
Map<String, List<ModuloDaTurma>> agruparCronograma(
  Iterable<ModuloDaTurma> linhas,
) {
  final mapa = <String, List<ModuloDaTurma>>{};
  for (final m in linhas) {
    (mapa[m.turmaId] ??= []).add(m);
  }
  for (final lista in mapa.values) {
    lista.sort((a, b) => a.moduloOrdem.compareTo(b.moduloOrdem));
  }
  return mapa;
}

// ---------------------------------------------------------------------------
// Filtro — estado da tela, desligável e visível (design-system §5.3)
// ---------------------------------------------------------------------------

@immutable
class FiltroTurmasModular {
  const FiltroTurmasModular({this.cursoId, this.busca = ''});

  static const semFiltro = FiltroTurmasModular();

  final String? cursoId;
  final String busca;

  int get ativos => (cursoId != null ? 1 : 0) + (busca.trim().isEmpty ? 0 : 1);

  FiltroTurmasModular copiar({String? Function()? cursoId, String? busca}) =>
      FiltroTurmasModular(
        cursoId: cursoId == null ? this.cursoId : cursoId(),
        busca: busca ?? this.busca,
      );
}

/// A view devolve tudo; quem esconde é a tela (card 2.3 §2.3(h)).
List<TurmaModular> filtrarTurmas(
  List<TurmaModular> todas,
  FiltroTurmasModular filtro,
) {
  final busca = filtro.busca.trim().toLowerCase();
  return [
    for (final t in todas)
      if ((filtro.cursoId == null || t.cursoId == filtro.cursoId) &&
          (busca.isEmpty ||
              t.nome.toLowerCase().contains(busca) ||
              t.cursoNome.toLowerCase().contains(busca)))
        t,
  ];
}

/// A ordem em que a tela lista: curso, depois turma. É como a escola fala das
/// turmas ("as de Eletricista"), e não a de criação.
List<TurmaModular> ordenarTurmas(List<TurmaModular> turmas) => List.of(turmas)
  ..sort((a, b) {
    final curso = a.cursoNome.toLowerCase().compareTo(
      b.cursoNome.toLowerCase(),
    );
    return curso != 0
        ? curso
        : a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
  });

// ---------------------------------------------------------------------------
// Avanço de módulo — o texto do diálogo
// ---------------------------------------------------------------------------

/// O que o avanço vai fazer, dito antes do clique (wireframe §8: "o diálogo
/// confirma o módulo que fecha e o que abre, com datas").
///
/// A frase **não** promete a data de início do próximo: quem a calcula é
/// `fn_turma_modular_avancar`, que preserva o que já estiver informado e só
/// então aplica `data_conclusao + 1` com o passo médio da turma. Dizer aqui um
/// número que o banco pode não usar seria a segunda conta que o card 2.3 §4.1
/// proíbe.
/// ⚠️ [faltantes] é o número de módulos do curso que **ainda não estão** no
/// cronograma. Sem ele o diálogo anunciava o fim da turma olhando só o
/// cronograma — e a tela mostrava, na mesma altura, um botão "Acrescentar 2
/// módulo(s)" (item B2). A frase não pré-valida nada: o avanço continua
/// permitido, e quem decide é `fn_turma_modular_avancar`.
List<String> resumoAvanco({
  required ModuloDaTurma? corrente,
  required ModuloDaTurma? proximo,
  required DateTime dataConclusao,
  int faltantes = 0,
}) => [
  if (corrente != null)
    'Fecha ${rotuloModulo(corrente.moduloOrdem, corrente.moduloNome)} '
        'em ${formatarData(dataConclusao)}.',
  if (proximo != null)
    'Abre ${rotuloModulo(proximo.moduloOrdem, proximo.moduloNome)}'
        '${proximo.semDatas ? '' : ' (${proximo.periodo})'}.'
  else if (faltantes > 0)
    'Não há módulo seguinte no cronograma, mas o curso tem '
        '${plural(faltantes, 'módulo fora dele', 'módulos fora dele')} — '
        'acrescente-os antes de avançar, ou a turma passa a "turma terminou".'
  else
    'Não há módulo seguinte no cronograma: a turma passa ao estado '
        '"turma terminou".',
];

/// O aviso do avanço, que é a decisão do plano posta em uma linha: **a turma
/// avança em conjunto**. Não existe avanço por aluno (card 2.2 §9), e quem
/// entrar depois entra no módulo corrente.
const avisoAvancoConjunto =
    'A turma inteira avança junto: todos os alunos passam ao módulo seguinte '
    'na mesma data. Não há avanço por aluno.';

/// O aviso da turma sem cronograma (wireframe §8): sem datas, a projeção de
/// demanda dela cai para a média do método.
const avisoSemCronograma =
    'Esta turma não tem cronograma de módulos. Sem as datas, a previsão de '
    'apostilas dela cai para a média do método, e a rotina diária abre a '
    'pendência "turma modular sem cronograma".';

/// Turma cujo cronograma acabou — o estado "turma terminou" (wireframe §8).
const avisoTurmaTerminou =
    'Todos os módulos do cronograma foram concluídos. A turma continua na '
    'lista: desative-a quando ela realmente encerrar.';

DateTime? _data(Object? valor) =>
    valor == null ? null : DateTime.parse('$valor');
