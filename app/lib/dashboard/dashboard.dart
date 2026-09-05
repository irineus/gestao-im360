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

// ---------------------------------------------------------------------------
// Alunos por método e tipos na turma — card 8.7
// ---------------------------------------------------------------------------

/// Uma linha de `v_dashboard_alunos_metodo` (docs/views-leitura.md §8.1).
///
/// As contagens **chegam prontas** do banco, como as vagas: somar status em
/// Dart a partir da lista de alunos daria uma segunda implementação da mesma
/// pergunta — e ela divergiria no dia em que a lista viesse paginada ou
/// filtrada pela RLS, com o número continuando plausível.
@immutable
class AlunosMetodo {
  const AlunosMetodo({
    required this.metodoId,
    required this.metodoCodigo,
    required this.ativos,
    required this.acelerar,
    required this.standby,
    required this.trancados,
    required this.cancelados,
    required this.formados,
    required this.emUltimoLivro,
    required this.emFim,
    required this.semPrevisao,
  });

  factory AlunosMetodo.deLinha(Map<String, dynamic> linha) => AlunosMetodo(
    metodoId: '${linha['metodo_id']}',
    metodoCodigo: '${linha['metodo_codigo']}',
    ativos: (linha['ativos'] as num?)?.toInt() ?? 0,
    acelerar: (linha['acelerar'] as num?)?.toInt() ?? 0,
    standby: (linha['standby'] as num?)?.toInt() ?? 0,
    trancados: (linha['trancados'] as num?)?.toInt() ?? 0,
    cancelados: (linha['cancelados'] as num?)?.toInt() ?? 0,
    formados: (linha['formados'] as num?)?.toInt() ?? 0,
    emUltimoLivro: (linha['em_ultimo_livro'] as num?)?.toInt() ?? 0,
    emFim: (linha['em_fim'] as num?)?.toInt() ?? 0,
    semPrevisao: (linha['sem_previsao'] as num?)?.toInt() ?? 0,
  );

  final String metodoId;

  /// O código vem da **própria view**, como em [TotalMetodo]: o cartão não pode
  /// ficar sem nome porque outra consulta não voltou.
  final String metodoCodigo;

  final int ativos;
  final int acelerar;
  final int standby;
  final int trancados;
  final int cancelados;
  final int formados;

  /// ⚠️ **UM item pendente** — o aluno está recebendo a última apostila e ainda
  /// tem aula pela frente. É o número que o cartão mostra (wireframes §5), e
  /// **não** [emFim], que é outra leitura (card 2.3 §8.1).
  final int emUltimoLivro;

  /// **Nenhum** item pendente. Fica fora do cartão de propósito: vale também
  /// para quem nunca teve trilha, pelo mesmo critério de `fn_trilha_em_fim`
  /// (card 6.2), e quem precisa da fila de formandos é a tela 9.
  final int emFim;

  /// ATIVO/ACELERAR sem previsão de conclusão informada. Fica ao lado das
  /// conclusões por semestre porque é ele que faz a soma dos semestres fechar
  /// com o total de ativos (docs/views-leitura.md §8.1).
  final int semPrevisao;

  /// Quem está em curso — a base que as conclusões por semestre enxergam.
  int get emCurso => ativos + acelerar;
}

/// Uma linha de `v_dashboard_tipos_bloco` (docs/views-leitura.md §8.3).
///
/// ⚠️ **São ALOCAÇÕES, não alunos**: quem está em aceleração ocupa dois blocos
/// e conta duas vezes. É o que os totais REM/PRE da planilha significam, e a
/// tela diz isso ao lado do número — sem a legenda, a soma parece contagem de
/// gente e não bate com os ativos do cartão logo acima.
@immutable
class TiposBloco {
  const TiposBloco({
    required this.metodoId,
    required this.metodoCodigo,
    required this.rem,
    required this.pre,
    required this.rep,
    required this.novo,
    required this.alocacoes,
  });

  factory TiposBloco.deLinha(Map<String, dynamic> linha) => TiposBloco(
    metodoId: '${linha['metodo_id']}',
    metodoCodigo: '${linha['metodo_codigo']}',
    rem: (linha['rem'] as num?)?.toInt() ?? 0,
    pre: (linha['pre'] as num?)?.toInt() ?? 0,
    rep: (linha['rep'] as num?)?.toInt() ?? 0,
    novo: (linha['novo'] as num?)?.toInt() ?? 0,
    alocacoes: (linha['alocacoes'] as num?)?.toInt() ?? 0,
  );

  final String metodoId;
  final String metodoCodigo;
  final int rem;
  final int pre;

  /// A alocação REP **contínua** (card 2.5). As reposições pontuais do dia não
  /// entram aqui — elas ocupam vaga na grade, não turma fixa.
  final int rep;

  final int novo;
  final int alocacoes;

  /// `REM 15 · PRE 2 · REP 1 · NOVO 1`, na ordem do wireframe §5.
  String get resumo => 'REM $rem · PRE $pre · REP $rep · NOVO $novo';
}

/// O cartão de um método: as contagens de aluno com os tipos na turma ao lado.
///
/// Os dois lados vêm de views diferentes e podem chegar em tempos diferentes —
/// [tipos] é nulo enquanto a segunda leitura não voltou, e a linha some em vez
/// de mostrar zeros que ninguém mediu.
@immutable
class PainelMetodo {
  const PainelMetodo({required this.alunos, this.tipos});

  final AlunosMetodo alunos;
  final TiposBloco? tipos;

  String get metodoId => alunos.metodoId;
  String get metodoCodigo => alunos.metodoCodigo;
}

/// Um painel por método, do **maior para o menor** em alunos em curso, com o
/// código desempatando — a mesma ordem de [totaisPorMetodo] e do desenho do
/// wireframe §5 (INTERATIVO, INGLÊS, MODULAR).
///
/// ⚠️ A junção é por `metodo_id` e **não** posicional: as duas views agrupam
/// por método, mas `v_dashboard_tipos_bloco` só tem linha para método com
/// alocação ativa — na fixture ela devolve uma linha e a de alunos devolve
/// três. Casar por posição poria os tipos do Interativo no cartão do Inglês,
/// com números plausíveis dos dois lados.
List<PainelMetodo> paineisPorMetodo(
  Iterable<AlunosMetodo> alunos,
  Iterable<TiposBloco> tipos,
) {
  final porMetodo = {for (final t in tipos) t.metodoId: t};
  return [
    for (final a in alunos)
      PainelMetodo(alunos: a, tipos: porMetodo[a.metodoId]),
  ]..sort((a, b) {
    final tamanho = b.alunos.emCurso.compareTo(a.alunos.emCurso);
    return tamanho != 0 ? tamanho : a.metodoCodigo.compareTo(b.metodoCodigo);
  });
}

/// Quantos alunos em curso não têm previsão de conclusão informada, somando os
/// métodos. É o número que fecha a conta das conclusões por semestre.
int totalSemPrevisao(Iterable<AlunosMetodo> alunos) =>
    alunos.fold(0, (soma, a) => soma + a.semPrevisao);

/// O cartão é uma pilha de números; sem isto a leitura de tela anuncia
/// "INTERATIVO 19 1 0 1 0" sem separar o que é o quê (design-system §8.5).
String descricaoAlunosMetodo(PainelMetodo painel) {
  final a = painel.alunos;
  final tipos = painel.tipos;
  return [
    a.metodoCodigo,
    '${a.ativos} ${a.ativos == 1 ? 'ativo' : 'ativos'}',
    '${a.acelerar} em aceleração',
    '${a.standby} em standby',
    '${a.trancados} ${a.trancados == 1 ? 'trancado' : 'trancados'}',
    '${a.emUltimoLivro} no último livro',
    '${a.semPrevisao} sem previsão de conclusão',
    if (tipos != null) '${tipos.alocacoes} alocações: ${tipos.resumo}',
  ].join(', ');
}

// ---------------------------------------------------------------------------
// Conclusões previstas por semestre — card 8.7
// ---------------------------------------------------------------------------

/// Uma linha de `v_dashboard_conclusoes_semestre` (docs/views-leitura.md §8.2):
/// um método num semestre.
@immutable
class ConclusaoSemestre {
  const ConclusaoSemestre({
    required this.metodoId,
    required this.metodoCodigo,
    required this.ano,
    required this.semestre,
    required this.qtdAlunos,
    required this.qtdVencidas,
  });

  factory ConclusaoSemestre.deLinha(Map<String, dynamic> linha) =>
      ConclusaoSemestre(
        metodoId: '${linha['metodo_id']}',
        metodoCodigo: '${linha['metodo_codigo']}',
        ano: (linha['ano'] as num?)?.toInt() ?? 0,
        semestre: (linha['semestre'] as num?)?.toInt() ?? 0,
        qtdAlunos: (linha['qtd_alunos'] as num?)?.toInt() ?? 0,
        qtdVencidas: (linha['qtd_vencidas'] as num?)?.toInt() ?? 0,
      );

  final String metodoId;
  final String metodoCodigo;
  final int ano;

  /// 1 = janeiro a junho, 2 = julho a dezembro.
  final int semestre;

  final int qtdAlunos;

  /// Previsão que já passou. **Não** é descartada da conta: fica no semestre
  /// dela e aparece ao lado do total (wireframes §5 — "mostrar `qtd_vencidas`
  /// junto, nunca escondê-las"). É o mesmo fato da pendência de previsão
  /// vencida, visto pelo lado do planejamento.
  final int qtdVencidas;
}

/// Um semestre com os métodos somados e a quebra por método ao lado.
@immutable
class SemestreConclusoes {
  const SemestreConclusoes({
    required this.ano,
    required this.semestre,
    required this.qtdAlunos,
    required this.qtdVencidas,
    required this.porMetodo,
  });

  final int ano;
  final int semestre;
  final int qtdAlunos;
  final int qtdVencidas;

  /// A quebra por método, do maior para o menor. O título da região diz "por
  /// método" e é aqui que ele se cumpre — somar sem mostrar a quebra faria a
  /// direção comprar apostila de um método olhando o número de outro.
  final List<ConclusaoSemestre> porMetodo;

  /// `2026/2`.
  String get rotulo => '$ano/$semestre';

  bool get temVencidas => qtdVencidas > 0;

  String get vencidasTexto =>
      '$qtdVencidas ${qtdVencidas == 1 ? 'vencida' : 'vencidas'}';

  /// `INTERATIVO 2 · INGLES 1`.
  String get resumoMetodos =>
      porMetodo.map((c) => '${c.metodoCodigo} ${c.qtdAlunos}').join(' · ');
}

/// Agrupa as linhas por (ano, semestre), em ordem **cronológica**.
///
/// Cronológica e não por tamanho: aqui o eixo é o tempo, e uma barra que se
/// reordena a cada matrícula não se lê. Os semestres vencidos vêm primeiro,
/// que é onde eles precisam estar — um semestre no passado com alunos dentro é
/// exatamente o que a direção precisa ver antes de planejar o próximo.
List<SemestreConclusoes> conclusoesPorSemestre(
  Iterable<ConclusaoSemestre> linhas,
) {
  final porChave = <String, List<ConclusaoSemestre>>{};
  for (final l in linhas) {
    porChave.putIfAbsent('${l.ano}/${l.semestre}', () => []).add(l);
  }
  final saida = [
    for (final grupo in porChave.values)
      SemestreConclusoes(
        ano: grupo.first.ano,
        semestre: grupo.first.semestre,
        qtdAlunos: grupo.fold(0, (s, c) => s + c.qtdAlunos),
        qtdVencidas: grupo.fold(0, (s, c) => s + c.qtdVencidas),
        porMetodo: grupo.toList()
          ..sort((a, b) {
            final tamanho = b.qtdAlunos.compareTo(a.qtdAlunos);
            return tamanho != 0
                ? tamanho
                : a.metodoCodigo.compareTo(b.metodoCodigo);
          }),
      ),
  ];
  return saida..sort((a, b) {
    final ano = a.ano.compareTo(b.ano);
    return ano != 0 ? ano : a.semestre.compareTo(b.semestre);
  });
}

/// O que a leitura de tela anuncia num cartão de semestre.
String descricaoSemestre(SemestreConclusoes s) => [
  s.rotulo,
  '${s.qtdAlunos} ${s.qtdAlunos == 1 ? 'aluno' : 'alunos'}',
  if (s.temVencidas) '${s.vencidasTexto} — previsão no passado',
  s.resumoMetodos,
].join(', ');

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
