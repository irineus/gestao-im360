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
import '../turmas/turmas.dart';

export '../turmas/turmas.dart'
    show
        CelulaGrade,
        GradeSemana,
        diasDaGrade,
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

  /// Nula quando a capacidade é zero — todos os PCs em manutenção, por exemplo.
  /// `0/0` não é "0% ocupado", é "não há o que ocupar", e uma barra em zero ali
  /// diria que há folga onde não há máquina nenhuma.
  double? get taxaOcupacao => capacidade == 0 ? null : ocupacao / capacidade;

  String get vagasTexto =>
      '$vagasLivres ${vagasLivres == 1 ? 'vaga livre' : 'vagas livres'}';

  String get ocupacaoTexto => '$ocupacao/$capacidade';

  String get blocosTexto => '$blocos ${blocos == 1 ? 'turma' : 'turmas'}';
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
    required this.ocupacao,
    required this.vagasLivres,
    required this.acimaCapacidade,
    required this.salas,
  });

  static const vazia = VagasNaCelula(
    blocos: 0,
    capacidade: 0,
    ocupacao: 0,
    vagasLivres: 0,
    acimaCapacidade: false,
    salas: 0,
  );

  final int blocos;
  final int capacidade;
  final int ocupacao;
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
  bool get lotada => !semBloco && vagasLivres == 0 && !acimaCapacidade;

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
  var ocupacao = 0;
  var vagas = 0;
  var acima = false;
  final salas = <String>{};
  for (final b in blocos) {
    capacidade += b.capacidade;
    ocupacao += b.ocupacao;
    vagas += b.vagasLivres;
    acima = acima || b.acimaCapacidade;
    salas.add(b.salaId);
  }
  return VagasNaCelula(
    blocos: blocos.length,
    capacidade: capacidade,
    ocupacao: ocupacao,
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
    if (vagas.lotada) 'lotada',
  ];
  return partes.join(', ');
}
