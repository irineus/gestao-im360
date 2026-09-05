/// O dashboard como o card 5.9 o entrega — a **v1**, que é vaga e nada mais:
/// vagas livres por método e por dia/horário, na semana corrente.
///
/// Este card é **consumidor, não criador**. A fonte é `v_bloco_vagas_semana`,
/// que nasceu no card 5.6 junto com `fn_grade_semana` (docs/views-leitura.md §7),
/// e nada aqui recalcula capacidade, ocupação ou vaga: o card 5.2 é o dono da
/// fórmula e uma segunda conta em Dart divergiria em silêncio. O que este
/// arquivo faz é **somar parcelas que já vieram prontas** e escolher como
/// apresentá-las.
///
/// Lógica pura de propósito: é o que se testa sem rede e sem cliente Supabase
/// (card 2.8 §9.3).
library;

import 'package:flutter/foundation.dart';

import '../pendencias/pendencias.dart';
import '../turmas/modular.dart';
import '../turmas/turmas.dart';

export '../turmas/turmas.dart'
    show
        CelulaGrade,
        GradeSemana,
        formatarDataCurta,
        montarGrade,
        nomeDia,
        nomeDiaCurto,
        rotuloSemana,
        segundaDe;

// ---------------------------------------------------------------------------
// A semana que a grade descreve
// ---------------------------------------------------------------------------

/// A segunda-feira da semana que o **banco** devolveu, lida de
/// `data_referencia`.
///
/// Não sai de `DateTime.now()`: `v_bloco_vagas_semana` fixa a semana com
/// `fn_hoje()`, que é a data de São Paulo (card 2.3 §3.3), e o relógio do
/// aparelho pode estar em outro fuso — ou simplesmente errado. Rotular com o
/// relógio local mostraria a grade **certa** sob a semana **errada**, que é a
/// família de falha calada que este projeto cataloga: número plausível, sem
/// nada em tela dizendo que a fonte é outra.
///
/// Nula quando não veio linha nenhuma — aí não há semana a afirmar, e quem
/// chama decide o que dizer.
DateTime? segundaDaGrade(Iterable<CelulaGrade> celulas) {
  for (final c in celulas) {
    final d = c.dataReferencia;
    return DateTime(d.year, d.month, d.day - (c.diaSemana - 1));
  }
  return null;
}

// ---------------------------------------------------------------------------
// Totais por método
// ---------------------------------------------------------------------------

/// As vagas de um método na semana, somadas dos blocos dele.
@immutable
class TotalMetodo {
  const TotalMetodo({
    required this.metodoId,
    required this.metodoCodigo,
    required this.blocos,
    required this.capacidade,
    required this.ocupacao,
    required this.vagasLivres,
    required this.blocosLotados,
    required this.blocosAcimaCapacidade,
  });

  final String metodoId;

  /// O código vem da **própria view** (`metodo_codigo`), não do catálogo em
  /// memória: o cartão não pode ficar sem nome porque outra consulta não voltou.
  final String metodoCodigo;

  final int blocos;
  final int capacidade;
  final int ocupacao;
  final int vagasLivres;
  final int blocosLotados;
  final int blocosAcimaCapacidade;

  bool get temAlerta => blocosAcimaCapacidade > 0;

  String get vagasTexto =>
      '$vagasLivres ${vagasLivres == 1 ? 'vaga livre' : 'vagas livres'}';

  /// "30 de 40 ocupados". Por extenso, e não `30/40`: no cartão este número
  /// fica 24 px acima de células que também dizem `n/m` — e ali `n/m` são
  /// **vagas**, a leitura oposta. A barra convidava a ler as duas do mesmo
  /// jeito (achado da revisão da fase 05).
  String get ocupacaoPorExtenso => '$ocupacao de $capacidade ocupados';

  /// **"bloco de horário"**, e não "turma": o sistema chamava o mesmo objeto de
  /// dois nomes na mesma tela — "3 turmas" no cartão, "3 blocos ativos" no
  /// rodapé —, e turma é o que a escola chama de outra coisa no Modular.
  String get blocosTexto =>
      '$blocos ${blocos == 1 ? 'bloco de horário' : 'blocos de horário'}';
}

/// Um total por método, do **maior para o menor** em número de turmas, com o
/// código desempatando.
///
/// A ordem não é alfabética de propósito, e não é enfeite: ela decide qual
/// grade abre primeiro ([metodoVisivel]). Alfabética abriria o dashboard desta
/// escola em `INGLES`, que tem uma turma, e não em `INTERATIVO`, que tem
/// dezenas — e é a ordem por tamanho que o wireframe §5 já desenha
/// (INTERATIVO, INGLÊS, MODULAR).
///
/// ⚠️ **`vagasLivres` é a SOMA das parcelas, nunca `capacidade − ocupacao`.**
/// As duas contas divergem no instante em que um bloco está acima da
/// capacidade: `fn_vagas_livres` já devolve `0` ali (card 5.2 recusa negativo),
/// e recalcular pela diferença faria o excesso de uma turma **abater** a vaga
/// real de outra — um bloco com 11/10 apagaria a vaga livre de um bloco com
/// 9/10 e o método apareceria sem vaga nenhuma, com dois números plausíveis do
/// lado. É a mesma razão de a grade do card 5.6 não recalcular nada.
List<TotalMetodo> totaisPorMetodo(Iterable<CelulaGrade> celulas) {
  final porId = <String, TotalMetodo>{};
  for (final c in celulas) {
    final atual = porId[c.metodoId];
    porId[c.metodoId] = TotalMetodo(
      metodoId: c.metodoId,
      metodoCodigo: c.metodoCodigo,
      blocos: (atual?.blocos ?? 0) + 1,
      capacidade: (atual?.capacidade ?? 0) + c.capacidade,
      ocupacao: (atual?.ocupacao ?? 0) + c.ocupacao,
      vagasLivres: (atual?.vagasLivres ?? 0) + c.vagasLivres,
      blocosLotados: (atual?.blocosLotados ?? 0) + (c.lotado ? 1 : 0),
      blocosAcimaCapacidade:
          (atual?.blocosAcimaCapacidade ?? 0) + (c.acimaCapacidade ? 1 : 0),
    );
  }
  return porId.values.toList()..sort((a, b) {
    final tamanho = b.blocos.compareTo(a.blocos);
    return tamanho != 0 ? tamanho : a.metodoCodigo.compareTo(b.metodoCodigo);
  });
}

/// O método que a grade mostra: o escolhido, ou o primeiro quando não há
/// escolha — ou quando a escolha deixou de existir (o último bloco daquele
/// método foi desativado enquanto a tela estava aberta).
TotalMetodo? metodoVisivel(List<TotalMetodo> totais, String? escolhidoId) {
  if (totais.isEmpty) return null;
  for (final t in totais) {
    if (t.metodoId == escolhidoId) return t;
  }
  return totais.first;
}

List<CelulaGrade> celulasDoMetodo(
  Iterable<CelulaGrade> celulas,
  String metodoId,
) => [
  for (final c in celulas)
    if (c.metodoId == metodoId) c,
];

// ---------------------------------------------------------------------------
// A célula da grade de vagas
// ---------------------------------------------------------------------------

/// Um cruzamento dia × horário do **mesmo método**, com os blocos somados.
///
/// Somar blocos aqui é legítimo e somar métodos não é — ver [vagasDa].
@immutable
class VagasNaCelula {
  const VagasNaCelula({
    required this.blocos,
    required this.capacidade,
    required this.vagasLivres,
    required this.acimaCapacidade,
    required this.salas,
  });

  static const vazia = VagasNaCelula(
    blocos: 0,
    capacidade: 0,
    vagasLivres: 0,
    acimaCapacidade: false,
    salas: 0,
  );

  final int blocos;
  final int capacidade;

  /// ⚠️ **Não há `ocupacao` aqui, de propósito.** A célula do dashboard lê
  /// vagas livres / capacidade; a ocupação nunca foi mostrada nem lida, e um
  /// campo somado que ninguém consome é um convite a recalcular a vaga por
  /// `capacidade − ocupacao` — a conta que esta classe existe para não fazer.
  final int vagasLivres;

  /// Verdadeiro quando **algum** bloco do cruzamento está acima da capacidade —
  /// o mesmo estado da pendência `BLOCO_ACIMA_CAPACIDADE` (card 5.5). Não se
  /// dilui na soma: uma turma com 11 em 10 continua sendo um problema mesmo
  /// que a sala ao lado tenha folga.
  final bool acimaCapacidade;

  /// Quantas salas ocupam este cruzamento. Mais de uma é o caso normal da
  /// `unique` de `bloco_horario`, que é por `(unidade, sala, dia, hora)`.
  final int salas;

  bool get semBloco => blocos == 0;

  /// ⚠️ Exige **capacidade maior que zero**, pela mesma razão de
  /// `CelulaGrade.lotado`: todos os PCs em manutenção dão `0/0`, e sem esta
  /// condição a célula aparecia como lotada — o oposto do que houve, e ainda
  /// contando em `blocosLotados` no cartão do método.
  bool get lotada =>
      !semBloco && capacidade > 0 && vagasLivres == 0 && !acimaCapacidade;

  /// Sem nenhum lugar a oferecer — é o fato que `PC_SEM_SUBSTITUTO` descreve.
  bool get semCapacidade => !semBloco && capacidade == 0 && !acimaCapacidade;

  /// `2/10` — **vagas livres / capacidade**, e não alocados/capacidade.
  ///
  /// ⚠️ É a leitura OPOSTA à da célula da tela de Turmas (card 5.6), que mostra
  /// `ocupacao/capacidade`. As duas nascem da mesma view e por isso nunca
  /// divergem em número; o que pode divergir é quem lê. Por isso a grade daqui
  /// nunca aparece sem a legenda, e o `Semantics` de cada célula diz "N vagas
  /// de M" por extenso.
  String get texto => '$vagasLivres/$capacidade';
}

/// Soma os blocos de um cruzamento.
///
/// ⚠️ Só é chamada com blocos **do mesmo método**, e é por isso que a tela
/// escolhe um método antes de desenhar a grade: **vaga de Inglês não serve a
/// aluno de Interativo** — quem recusa é `METODO_INCOMPATIVEL` no trigger de
/// admissão (card 5.3) —, então "3 vagas na quarta às 08:00" somando os dois
/// métodos é um número que ninguém pode usar e que leva a secretaria a
/// prometer uma vaga que não existe para aquele aluno. Divergência registrada
/// com o wireframe §5, que desenha uma grade só para "Interativo e Inglês".
VagasNaCelula vagasDa(List<CelulaGrade> blocos) {
  if (blocos.isEmpty) return VagasNaCelula.vazia;
  var capacidade = 0;
  var vagas = 0;
  var acima = false;
  final salas = <String>{};
  for (final b in blocos) {
    capacidade += b.capacidade;
    vagas += b.vagasLivres;
    acima = acima || b.acimaCapacidade;
    salas.add(b.salaId);
  }
  return VagasNaCelula(
    blocos: blocos.length,
    capacidade: capacidade,
    vagasLivres: vagas,
    acimaCapacidade: acima,
    salas: salas.length,
  );
}

// ---------------------------------------------------------------------------
// Pendências abertas por severidade
// ---------------------------------------------------------------------------

/// Quantas pendências abertas há em cada severidade.
@immutable
class TotalSeveridade {
  const TotalSeveridade({required this.severidade, required this.qtd});

  /// `ALTA` / `MEDIA` / `BAIXA` — o valor do banco, nunca o rótulo.
  final String severidade;
  final int qtd;

  String get rotulo => rotuloSeveridade(severidade);
}

/// As **três** severidades, sempre, na ordem em que a fila de trabalho as lê.
///
/// Severidade sem pendência nenhuma sai com zero em vez de sumir da lista: é a
/// regra que o design-system §7.2 escreve para o dashboard — *região mostra zero
/// real, nunca some; número que desaparece parece erro*. Uma lista que encolhe
/// também tira a referência de comparação entre um dia e o outro.
///
/// A entrada é a lista que o **shell já carregou** (`pendenciasProvider`, card
/// 5.8): o dashboard não abre uma segunda consulta para contar o que já está em
/// memória — é o ajuste que o card 5.8 deixou escrito para cá.
List<TotalSeveridade> totaisPorSeveridade(Iterable<Pendencia> abertas) {
  const ordem = ['ALTA', 'MEDIA', 'BAIXA'];
  final contagem = {for (final s in ordem) s: 0};
  for (final p in abertas) {
    contagem[p.severidade] = (contagem[p.severidade] ?? 0) + 1;
  }
  return [
    for (final s in ordem)
      TotalSeveridade(severidade: s, qtd: contagem[s] ?? 0),
  ];
}

// ---------------------------------------------------------------------------
// Lotação Modular, por curso — card 7.4
// ---------------------------------------------------------------------------

/// A lotação de **um curso** Modular: as turmas ativas dele somadas.
///
/// O card 7.4 é **consumidor e não criador**, como o 5.9 foi de
/// `v_bloco_vagas_semana`: a fonte é `v_turma_modular_lotacao`, que nasceu no
/// card 7.3 (docs/views-leitura.md §7.2), e nada aqui recalcula lotação, vaga
/// ou módulo corrente — os três chegam prontos, e uma segunda conta em Dart
/// divergiria em silêncio (card 2.3 §4.1).
@immutable
class LotacaoCurso {
  const LotacaoCurso({
    required this.cursoId,
    required this.cursoNome,
    required this.turmas,
    required this.capacidade,
    required this.alocados,
    required this.vagasLivres,
    required this.turmasAcimaCapacidade,
    required this.turmasAtrasadas,
  });

  final String cursoId;

  /// O nome vem da **própria view** (`curso_nome`), não de uma segunda consulta
  /// ao catálogo: o cartão não pode ficar sem nome porque outra leitura não
  /// voltou. Mesma razão do `metodo_codigo` em [TotalMetodo].
  final String cursoNome;

  final int turmas;
  final int capacidade;
  final int alocados;
  final int vagasLivres;

  /// Quantas turmas do curso estão **acima** da capacidade — estado real, que o
  /// importador do card 9.1 pode trazer.
  final int turmasAcimaCapacidade;

  /// Quantas estão com a previsão do módulo corrente vencida. Vem da coluna
  /// `modulo_atrasado` da view, medida com `fn_hoje()` — nunca do relógio do
  /// aparelho, que poria a turma em atraso um dia antes ou depois.
  final int turmasAtrasadas;

  bool get temAlerta => turmasAcimaCapacidade > 0;
  bool get temAtraso => turmasAtrasadas > 0;

  String get vagasTexto =>
      '$vagasLivres ${vagasLivres == 1 ? 'vaga livre' : 'vagas livres'}';

  /// "8 de 10 ocupados". Por extenso, e não `8/10` como o wireframe §5 desenha:
  /// esta região fica na mesma tela da grade de vagas, cujas células dizem
  /// `n/m` com `n` sendo **vaga livre** — a leitura oposta. É a correção que o
  /// card 5.11 já aplicou ao cartão do método, pela mesma razão e na mesma
  /// tela; divergência registrada em `docs/wireframes.md` §17.
  String get ocupacaoPorExtenso => '$alocados de $capacidade ocupados';

  String get turmasTexto => '$turmas ${turmas == 1 ? 'turma' : 'turmas'}';

  String get atrasoTexto =>
      '$turmasAtrasadas ${turmasAtrasadas == 1 ? 'turma com módulo atrasado' : 'turmas com módulo atrasado'}';

  /// "1 turma acima da capacidade" — com o substantivo, e não só
  /// "1 acima da capacidade" como no cartão do método: as duas regiões dividem
  /// a mesma tela, e ali o número conta **blocos de horário**.
  String get acimaTexto =>
      '$turmasAcimaCapacidade ${turmasAcimaCapacidade == 1 ? 'turma acima da capacidade' : 'turmas acima da capacidade'}';
}

/// Um total por curso, em ordem alfabética de curso.
///
/// Alfabética e não por tamanho, ao contrário de [totaisPorMetodo]: lá a ordem
/// decide **qual grade abre**, e aqui não decide nada — os cartões são todos
/// visíveis. Uma lista que se reordena a cada matrícula é uma lista que se
/// reaprende todo dia.
///
/// ⚠️ **`vagasLivres` é a SOMA das parcelas, nunca `capacidade − alocados`.**
/// É a mesma armadilha de [totaisPorMetodo], e aqui ela é ainda mais fácil de
/// cair porque a capacidade da turma Modular é **coluna**: `vagas_livres` da
/// view tem piso zero (card 7.3), então uma turma com 16 em 15 faria a
/// diferença dar **−1** e o curso apareceria devendo vaga — ou, com outra turma
/// ao lado, faria o excesso de uma **abater** a vaga real da outra.
List<LotacaoCurso> lotacaoPorCurso(Iterable<TurmaModular> turmas) {
  final porCurso = <String, LotacaoCurso>{};
  for (final t in turmas) {
    final atual = porCurso[t.cursoId];
    porCurso[t.cursoId] = LotacaoCurso(
      cursoId: t.cursoId,
      cursoNome: t.cursoNome,
      turmas: (atual?.turmas ?? 0) + 1,
      capacidade: (atual?.capacidade ?? 0) + t.capacidade,
      alocados: (atual?.alocados ?? 0) + t.alocados,
      vagasLivres: (atual?.vagasLivres ?? 0) + t.vagasLivres,
      turmasAcimaCapacidade:
          (atual?.turmasAcimaCapacidade ?? 0) + (t.acimaCapacidade ? 1 : 0),
      turmasAtrasadas:
          (atual?.turmasAtrasadas ?? 0) + (t.moduloAtrasado ? 1 : 0),
    );
  }
  return porCurso.values.toList()..sort((a, b) {
    final nome = a.cursoNome.toLowerCase().compareTo(b.cursoNome.toLowerCase());
    return nome != 0 ? nome : a.cursoId.compareTo(b.cursoId);
  });
}

/// O cartão é uma pilha de números; sem isto a leitura de tela anuncia
/// "Eletricista 44 vagas livres 1 de 45 ocupados 3 turmas" sem separar o que é
/// o quê (design-system §8.5).
String descricaoLotacaoCurso(LotacaoCurso curso) {
  final partes = <String>[
    curso.cursoNome,
    curso.vagasTexto,
    curso.ocupacaoPorExtenso,
    curso.turmasTexto,
    if (curso.temAlerta) curso.acimaTexto,
    if (curso.temAtraso) curso.atrasoTexto,
  ];
  return partes.join(', ');
}

/// O que a leitura de tela anuncia numa célula — a grade é uma matriz de
/// números, e sem isto ela anuncia "2 barra 10" sem dizer 2 do quê.
String descricaoCelula(int dia, String hora, VagasNaCelula vagas) {
  if (vagas.semBloco) return '${nomeDia(dia)} $hora, sem turma';
  final partes = <String>[
    '${nomeDia(dia)} $hora',
    '${vagas.vagasLivres} '
        '${vagas.vagasLivres == 1 ? 'vaga livre' : 'vagas livres'} '
        'de ${vagas.capacidade}',
    if (vagas.salas > 1) '${vagas.salas} salas',
    if (vagas.acimaCapacidade) 'acima da capacidade',
    if (vagas.lotada) 'lotado',
    if (vagas.semCapacidade) 'sem capacidade',
  ];
  return partes.join(', ');
}
