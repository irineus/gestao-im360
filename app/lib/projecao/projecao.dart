/// A projeção de demanda como o app a vê (card 8.5): o modelo de
/// `v_projecao_material_mes` (a grade) e o de `v_projecao_aluno_detalhe` (o
/// drill-down), mais a lógica **pura** da tela 8 — o pivô material × mês, os
/// filtros, os rótulos de regra e de mês e os textos de estado.
///
/// Pura de propósito: é o que se testa sem rede e sem cliente Supabase
/// (card 2.8 §9.3).
///
/// ⚠️ **Nada neste arquivo projeta nada.** Quem decide quantos exemplares e em
/// que mês é `v_projecao_aluno` (docs/projecao-demanda.md §6), e quem agrega é
/// `rt_projecao_demanda`. Aqui só se soma o que a view já devolveu por (material,
/// mês, regra) para montar a coluna Σ e a célula do pivô — uma soma de inteiros
/// que a própria tela exibe ao lado das parcelas, e não uma segunda régua.
library;

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Os quatro degraus da cascata
// ---------------------------------------------------------------------------

/// Rótulo em português do degrau que produziu a quantidade. A proveniência
/// aparece no total **e** no detalhe porque projeção sem ela não é revisável
/// (docs/views-leitura.md §5.3).
///
/// Código desconhecido volta como veio: inventar um rótulo bonito para um
/// degrau que o banco passou a usar esconderia justamente a novidade.
String rotuloRegra(String codigo) => switch (codigo) {
  'RITMO_ALUNO' => 'Ritmo do aluno',
  'PREVISAO_CURSO' => 'Previsão do curso',
  'MEDIA_METODO' => 'Média do método',
  'MODULAR' => 'Cronograma da turma',
  _ => codigo,
};

/// Os quatro, na ordem da cascata — é a ordem do filtro.
const regrasDaProjecao = <String>[
  'MODULAR',
  'RITMO_ALUNO',
  'PREVISAO_CURSO',
  'MEDIA_METODO',
];

/// Linha do pivô cuja quantidade veio de mais de um degrau. Acontece o tempo
/// todo — o mesmo material serve a um aluno Modular e a um de ritmo próprio —,
/// e dizer "várias" é mais honesto do que escolher a primeira.
const regrasMistas = 'Várias';

// ---------------------------------------------------------------------------
// Meses
// ---------------------------------------------------------------------------

const _mesesAbreviados = <String>[
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

/// `set` ou `set/26` — o ano entra **quando ele importa**, pela mesma razão de
/// `formatarPeriodo` (card 8.1,5, item B3): a janela do horizonte atravessa o
/// ano no fim de todo dezembro, e `nov · dez · jan` lê-se como se janeiro viesse
/// antes. Quando entra, entra em **todas** as colunas, senão a tabela ensina
/// duas formas de ler a mesma linha.
String rotuloMes(DateTime mes, {bool comAno = false}) {
  final nome = _mesesAbreviados[mes.month - 1];
  if (!comAno) return nome;
  return '$nome/${(mes.year % 100).toString().padLeft(2, '0')}';
}

/// O ano importa quando os meses da janela não são todos do mesmo ano.
bool mesesCruzamAno(Iterable<DateTime> meses) =>
    meses.map((m) => m.year).toSet().length > 1;

/// Os meses da projeção, em ordem, sem repetição.
///
/// ⚠️ Sai de **todas** as linhas, nunca das filtradas: com as colunas derivadas
/// do que o filtro deixou passar, escolher um método reescreveria o cabeçalho da
/// tabela e a pessoa compararia dois recortes achando que compara o mesmo.
List<DateTime> mesesDaProjecao(Iterable<CelulaProjecao> celulas) =>
    ({for (final c in celulas) c.mes}.toList()..sort());

// ---------------------------------------------------------------------------
// Grade — uma linha de v_projecao_material_mes
// ---------------------------------------------------------------------------

/// Uma célula do grão do banco: material × mês × regra.
@immutable
class CelulaProjecao {
  const CelulaProjecao({
    required this.materialId,
    required this.metodoId,
    required this.codigo,
    required this.nome,
    required this.categoria,
    required this.mes,
    required this.quantidade,
    required this.regra,
    required this.calculadoEm,
  });

  factory CelulaProjecao.deLinha(Map<String, dynamic> linha) => CelulaProjecao(
    materialId: '${linha['material_id']}',
    metodoId: '${linha['metodo_id']}',
    codigo: '${linha['codigo']}',
    nome: '${linha['nome']}',
    categoria: '${linha['categoria']}',
    mes: DateTime.parse('${linha['mes']}'),
    quantidade: (linha['quantidade'] as num?)?.toInt() ?? 0,
    regra: '${linha['regra']}',
    // `timestamptz` chega em UTC: sem `toLocal()` a rotina das 03:10 apareceria
    // como 06:10 (a mesma correção do card 8.2).
    calculadoEm: DateTime.parse('${linha['calculado_em']}').toLocal(),
  );

  final String materialId;
  final String metodoId;
  final String codigo;
  final String nome;
  final String categoria;

  /// Sempre o **dia 1** do mês de competência (docs/views-leitura.md §5.3).
  final DateTime mes;

  final int quantidade;

  /// `RITMO_ALUNO` / `PREVISAO_CURSO` / `MEDIA_METODO` / `MODULAR`.
  final String regra;

  /// Quando a rotina rodou. É o mesmo carimbo em toda linha — a rotina apaga e
  /// regrava a unidade inteira a cada execução.
  final DateTime calculadoEm;
}

/// Uma linha da grade: um material, com a quantidade de cada mês e o total.
@immutable
class LinhaProjecao {
  const LinhaProjecao({
    required this.materialId,
    required this.metodoId,
    required this.codigo,
    required this.nome,
    required this.categoria,
    required this.porMes,
    required this.regras,
  });

  final String materialId;
  final String metodoId;
  final String codigo;
  final String nome;
  final String categoria;

  /// Mês (dia 1) → exemplares previstos. Mês sem projeção **não tem chave** —
  /// a célula vazia da tela é um traço, e não um zero afirmado.
  final Map<DateTime, int> porMes;

  /// Os degraus que produziram esta linha, na ordem da cascata.
  final List<String> regras;

  int get total => porMes.values.fold(0, (soma, q) => soma + q);

  int quantidadeEm(DateTime mes) => porMes[mes] ?? 0;

  bool temMes(DateTime mes) => porMes.containsKey(mes);

  /// O rótulo da coluna Regra: o degrau quando é um só, [regrasMistas] quando
  /// são vários. É a proveniência do total, e o filtro por regra é quem a separa.
  String get rotuloProveniencia =>
      regras.length == 1 ? rotuloRegra(regras.single) : regrasMistas;

  String get rotulo => '$codigo $nome';
}

/// Agrupa as células por material, somando por mês. **Toda a soma da tela mora
/// aqui**, e é a única — a tela lê `total` e `quantidadeEm`, nunca refaz.
///
/// A ordem de saída é por código, que é a ordem em que a lista de materiais é
/// lida no resto do sistema; quem reordena por total é a tela.
List<LinhaProjecao> pivotar(Iterable<CelulaProjecao> celulas) {
  final porMaterial = <String, List<CelulaProjecao>>{};
  for (final c in celulas) {
    porMaterial.putIfAbsent(c.materialId, () => []).add(c);
  }

  final linhas = <LinhaProjecao>[];
  for (final grupo in porMaterial.values) {
    final primeira = grupo.first;
    final porMes = <DateTime, int>{};
    for (final c in grupo) {
      porMes[c.mes] = (porMes[c.mes] ?? 0) + c.quantidade;
    }
    final regras = [
      for (final r in regrasDaProjecao)
        if (grupo.any((c) => c.regra == r)) r,
      // Degrau que o banco passou a usar e este app ainda não conhece continua
      // aparecendo: some da ordem da cascata, não da lista.
      for (final r in ({for (final c in grupo) c.regra}.toList()..sort()))
        if (!regrasDaProjecao.contains(r)) r,
    ];
    linhas.add(
      LinhaProjecao(
        materialId: primeira.materialId,
        metodoId: primeira.metodoId,
        codigo: primeira.codigo,
        nome: primeira.nome,
        categoria: primeira.categoria,
        porMes: Map.fromEntries(
          (porMes.keys.toList()..sort()).map((m) => MapEntry(m, porMes[m]!)),
        ),
        regras: regras,
      ),
    );
  }
  return linhas..sort((a, b) => a.codigo.compareTo(b.codigo));
}

// ---------------------------------------------------------------------------
// Detalhe — uma linha de v_projecao_aluno_detalhe
// ---------------------------------------------------------------------------

/// Um aluno que soma na célula: qual apostila, quando e por qual regra.
@immutable
class DetalheProjecao {
  const DetalheProjecao({
    required this.alunoId,
    required this.alunoNome,
    required this.codigoSgf,
    required this.alunoStatus,
    required this.materialId,
    required this.codigo,
    required this.materialNome,
    required this.mes,
    required this.dataPrevista,
    required this.regra,
    required this.k,
    required this.pendentes,
    this.ritmoDias,
  });

  factory DetalheProjecao.deLinha(Map<String, dynamic> linha) =>
      DetalheProjecao(
        alunoId: '${linha['aluno_id']}',
        alunoNome: '${linha['aluno_nome']}',
        codigoSgf: '${linha['codigo_sgf']}',
        alunoStatus: '${linha['aluno_status']}',
        materialId: '${linha['material_id']}',
        codigo: '${linha['codigo']}',
        materialNome: '${linha['material_nome']}',
        mes: DateTime.parse('${linha['mes']}'),
        dataPrevista: DateTime.parse('${linha['data_prevista']}'),
        regra: '${linha['regra']}',
        ritmoDias: (linha['ritmo_dias'] as num?)?.toInt(),
        k: (linha['k'] as num?)?.toInt() ?? 0,
        pendentes: (linha['pendentes'] as num?)?.toInt() ?? 0,
      );

  final String alunoId;
  final String alunoNome;
  final String codigoSgf;
  final String alunoStatus;

  final String materialId;
  final String codigo;
  final String materialNome;

  final DateTime mes;
  final DateTime dataPrevista;
  final String regra;

  /// O ritmo que gerou [dataPrevista], em dias. **Nulo em `PREVISAO_CURSO` e em
  /// `MODULAR`**, onde a data não vem de ritmo nenhum: ali a previsão foi
  /// declarada por uma pessoa, ou o cronograma da turma é quem manda.
  final int? ritmoDias;

  /// Posição do item na trilha pendente. Começa em 2 — o item 1 é o próximo
  /// livro, que já é demanda imediata.
  final int k;
  final int pendentes;

  String get rotuloAluno => '$alunoNome ($codigoSgf)';
}

/// "23 d" · "—". O traço não é omissão: é o que diz que aquele degrau não usa
/// ritmo, e mostrar o do método ali seria exibir um número que não participou
/// da conta.
String rotuloRitmo(int? dias) => dias == null ? '—' : '$dias d';

/// "2º de 5 pendentes" — o que a linha do detalhe significa na trilha do aluno.
String rotuloPosicao(DetalheProjecao d) =>
    '${d.k}º de ${d.pendentes} pendentes';

// ---------------------------------------------------------------------------
// Filtro da grade — wireframe §11
// ---------------------------------------------------------------------------

bool _casaBusca(String busca, Iterable<String> campos) {
  final termo = busca.trim().toLowerCase();
  if (termo.isEmpty) return true;
  return campos.any((c) => c.toLowerCase().contains(termo));
}

@immutable
class FiltroProjecao {
  const FiltroProjecao({
    this.busca = '',
    this.metodoId,
    this.categoria,
    this.regra,
  });

  final String busca;
  final String? metodoId;
  final String? categoria;

  /// O filtro por proveniência do wireframe §11 — o que responde "quanto desta
  /// compra é chute de média e quanto é cronograma datado".
  final String? regra;

  int get ativos =>
      (busca.trim().isEmpty ? 0 : 1) +
      (metodoId == null ? 0 : 1) +
      (categoria == null ? 0 : 1) +
      (regra == null ? 0 : 1);

  FiltroProjecao copiar({
    String? busca,
    String? Function()? metodoId,
    String? Function()? categoria,
    String? Function()? regra,
  }) => FiltroProjecao(
    busca: busca ?? this.busca,
    metodoId: metodoId == null ? this.metodoId : metodoId(),
    categoria: categoria == null ? this.categoria : categoria(),
    regra: regra == null ? this.regra : regra(),
  );
}

/// Filtra **as células**, antes do pivô, e é por aí que o filtro de regra
/// funciona: com o filtro aplicado depois, um material atendido por dois
/// degraus continuaria somando os dois no total e a tela diria que 6 exemplares
/// vêm de média do método quando 4 vêm de cronograma.
List<CelulaProjecao> filtrarCelulas(
  Iterable<CelulaProjecao> todas,
  FiltroProjecao filtro,
) => [
  for (final c in todas)
    if ((filtro.metodoId == null || c.metodoId == filtro.metodoId) &&
        (filtro.categoria == null || c.categoria == filtro.categoria) &&
        (filtro.regra == null || c.regra == filtro.regra) &&
        _casaBusca(filtro.busca, [c.codigo, c.nome]))
      c,
];

List<String> categoriasProjetadas(Iterable<CelulaProjecao> celulas) =>
    ({for (final c in celulas) c.categoria}.toList()..sort());

/// As regras presentes na projeção, na ordem da cascata — o filtro só oferece o
/// que existe, senão a pessoa escolhe um degrau e recebe a lista vazia.
List<String> regrasPresentes(Iterable<CelulaProjecao> celulas) {
  final presentes = {for (final c in celulas) c.regra};
  return [
    for (final r in regrasDaProjecao)
      if (presentes.contains(r)) r,
    for (final r in (presentes.toList()..sort()))
      if (!regrasDaProjecao.contains(r)) r,
  ];
}

/// O carimbo da projeção: o mais recente entre as células lidas.
///
/// A rotina apaga e regrava a unidade a cada execução, então o carimbo é o mesmo
/// em todas — pegar o maior sobrevive a uma execução parcial mostrando a rodada
/// mais nova. Nulo = **não há projeção gravada**, e a tela diz isso com todas as
/// letras em vez de exibir um traço mudo.
DateTime? calculadoEmDe(Iterable<CelulaProjecao> celulas) {
  DateTime? maior;
  for (final c in celulas) {
    if (maior == null || c.calculadoEm.isAfter(maior)) maior = c.calculadoEm;
  }
  return maior;
}

// ---------------------------------------------------------------------------
// Textos de tela — docs/design-system.md §7.2 e §7.3, palavra por palavra
// ---------------------------------------------------------------------------

/// §7.3, "Cabeçalho da Projeção": obrigatório, e é o que dá validade ao número.
String projecaoCalculadaEm(String quando) => 'Projeção calculada em $quando.';

/// A projeção nunca foi gravada nesta unidade. Aparece no cabeçalho junto com o
/// estado vazio da tabela — **nunca um traço mudo**, pela mesma razão do card
/// 8.2: silêncio aqui pareceria uma escola que não vai precisar de apostila.
const projecaoSemCarimbo =
    'A projeção ainda não foi calculada. Ela é atualizada pela rotina da '
    'madrugada.';

/// Carimbo ilegível: a grade continua na tela, e o que falta é a validade dela.
const erroProjecaoCalculadaEm =
    'Não foi possível ler quando a projeção foi calculada.';

/// §7.3: o detalhe é lido ao vivo e o total é da madrugada — podem divergir ao
/// longo do dia, e essa divergência é esperada, não defeito.
const avisoDetalheAoVivo =
    'O detalhe é de agora e pode diferir do total da madrugada.';

/// §7.2, linha "Projeção" — rotina ok e sem linhas.
const vazioProjecao = 'Sem demanda projetada no horizonte atual.';

/// §7.2, linha "Projeção" — rotina falhou.
///
/// ⚠️ O documento escreve o código `ROTINA_FALHOU`; a tela usa o **rótulo** que
/// a central de pendências já mostra ("Rotina diária falhou"), porque código de
/// catálogo é vocabulário de quem escreveu o sistema. Divergência registrada em
/// docs/design-system.md §11.
const vazioProjecaoRotinaFalhou =
    'A projeção não foi calculada: a rotina diária falhou. Veja a pendência '
    '"Rotina diária falhou" na central de Pendências.';

const vazioProjecaoFiltro = 'Nenhum material com esses filtros.';

/// O drill-down de uma célula que não devolveu aluno nenhum. Só acontece quando
/// o total é da madrugada e o detalhe, de agora, já não tem aquele aluno — uma
/// entrega registrada hoje de manhã basta —, e é exatamente a defasagem que o
/// aviso acima descreve.
const vazioDetalheProjecao =
    'Nenhum aluno neste material agora. O total ao lado é do cálculo da '
    'madrugada e o detalhe é de agora.';
