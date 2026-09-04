/// A central de pendências como o app a vê (card 5.8): o modelo de uma linha de
/// `v_pendencias_abertas` (card 5.5), os rótulos dos 15 tipos e das três
/// severidades, os filtros da tela, a ordenação e o mapa **tipo → ação
/// contextual** do wireframe §14.3.
///
/// Pura de propósito: é o que se testa sem rede e sem cliente Supabase
/// (card 2.8 §9.3). Regra de negócio continua no banco — abrir e fechar
/// pendência é de `fn_pendencia_abrir`/`fn_pendencia_resolver_id`, e nada aqui
/// decide se uma pendência existe.
library;

import 'package:flutter/foundation.dart';

import '../turmas/turmas.dart' show rotuloBloco;

export '../util/datas.dart';

/// Os quinze tipos do `check` de `pendencia.tipo` (card 5.5), com o rótulo que
/// a tela mostra. A chave é o valor do banco; o app nunca compara pelo rótulo —
/// mesma convenção de `statusAluno` (card 4.6) e `tiposNaTurma` (card 5.7).
///
/// Os nove das fases 6 e 8 estão aqui porque o `check` já os aceita: uma
/// pendência de tipo desconhecido cairia no `??`, e o dia em que a fase 6 abrir
/// a primeira `COMPRA_SEM_ESTOQUE` a central mostraria o código cru no lugar do
/// nome — sem erro nenhum, que é a família de falha que este projeto cataloga.
const tiposPendencia = <String, String>{
  // card 5.5 — os três do título, mais os dois que a rotina e o 5.4 abrem
  'ALUNO_SEM_TURMA': 'Aluno sem turma',
  'BLOCO_ACIMA_CAPACIDADE': 'Bloco acima da capacidade',
  'ACELERAR_SEM_2O_BLOCO': 'Aceleração sem segundo bloco',
  'REP_VIRADA': 'Reposição — virada sugerida',
  'ROTINA_FALHOU': 'Rotina diária falhou',
  // card 5.4
  'PC_SEM_SUBSTITUTO': 'PC parado sem substituto',
  // fase 6
  'COMPRA_SEM_ESTOQUE': 'Entrega bloqueada — sem estoque',
  'ESTOQUE_ZERO': 'Estoque zerado',
  'ESTOQUE_ABAIXO_MINIMO': 'Estoque abaixo do mínimo',
  'TRILHA_DIVERGENTE_COMBO': 'Trilha divergente do combo',
  'CERTIFICADO_INCONSISTENTE': 'Certificado inconsistente',
  // fase 8
  'STANDBY_PROLONGADO': 'STANDBY prolongado',
  'PREVISAO_VENCIDA': 'Previsão de conclusão vencida',
  'ALUNO_ULTIMO_LIVRO': 'Aluno na última apostila',
  'SUGERIR_FORMADO': 'Aluno pronto para formar',
};

String rotuloTipoPendencia(String tipo) => tiposPendencia[tipo] ?? tipo;

/// O rótulo de **uma** pendência — igual ao do tipo, menos no `REP_VIRADA`.
///
/// ⚠️ As duas metades da virada são o mesmo tipo e pedem ações opostas: uma
/// põe o aluno em vaga fixa, a outra a devolve. Um rótulo só para as duas
/// ("Reposição — virada sugerida") faz a lista, o título do painel e a
/// confirmação dizerem a mesma coisa em dois casos contrários — e quem lê
/// decide qual é pelo texto da descrição, quando devia decidir pelo nome.
/// O menu de **filtro** continua com o rótulo do tipo: lá se filtra por tipo.
String rotuloPendencia(Pendencia p) => switch (p.sentido) {
  SentidoVirada.continuo => 'REP: sugerida virada para contínuo',
  SentidoVirada.volta => 'REP: sugerida volta para pontual',
  null => rotuloTipoPendencia(p.tipo),
};

/// As três do `check` de `pendencia.severidade`. `INFO` **não existe** — o
/// ajuste 4 do card 2.3, que o card 5.5 aplicou.
const severidadesPendencia = <String, String>{
  'ALTA': 'ALTA',
  'MEDIA': 'MÉDIA',
  'BAIXA': 'BAIXA',
};

String rotuloSeveridade(String severidade) =>
    severidadesPendencia[severidade] ?? severidade;

/// As duas resoluções do `check` de `pendencia.resolucao`.
const resolucaoResolvida = 'RESOLVIDA';
const resolucaoIgnorada = 'IGNORADA';

// ---------------------------------------------------------------------------
// Modelo
// ---------------------------------------------------------------------------

/// Uma linha de `v_pendencias_abertas`.
///
/// ⚠️ **As quatro referências chegam por ****`left join`**** e degradam para
/// nulo** quando o leitor não pode ler a tabela referenciada (card 2.3 §9): o
/// monitor sem `turmas.ler` recebe `bloco_id` preenchido e `dia_semana` nulo. A
/// linha continua existindo, e é isso que separa "uma pendência sobre um bloco
/// que você não pode ver" de "nenhuma pendência" — por isso [referencia] tem um
/// caso para cada metade, e nunca some com a linha.
@immutable
class Pendencia {
  const Pendencia({
    required this.id,
    required this.tipo,
    required this.severidade,
    required this.ordemSeveridade,
    required this.descricao,
    required this.chaveDedup,
    required this.criadoEm,
    required this.diasAberta,
    this.alunoId,
    this.alunoNome,
    this.codigoSgf,
    this.alunoStatus,
    this.blocoId,
    this.blocoDiaSemana,
    this.blocoHoraInicio,
    this.blocoSalaNome,
    this.materialId,
    this.materialCodigo,
    this.materialNome,
    this.pcId,
    this.pcIdentificador,
  });

  factory Pendencia.deLinha(Map<String, dynamic> linha) => Pendencia(
    id: '${linha['pendencia_id']}',
    tipo: '${linha['tipo']}',
    severidade: '${linha['severidade']}',
    ordemSeveridade: (linha['ordem_severidade'] as num?)?.toInt() ?? 9,
    descricao: '${linha['descricao']}',
    chaveDedup: '${linha['chave_dedup']}',
    // `.toLocal()` porque `criado_em` é `timestamptz` e chega em UTC: sem ele,
    // pendência aberta às 23h aparece com a data do dia seguinte. É o padrão da
    // casa desde os cards 4.5 e 4.6.
    criadoEm: DateTime.parse('${linha['criado_em']}').toLocal(),
    diasAberta: (linha['dias_aberta'] as num?)?.toInt() ?? 0,
    alunoId: linha['aluno_id'] == null ? null : '${linha['aluno_id']}',
    alunoNome: linha['aluno_nome'] as String?,
    codigoSgf: linha['codigo_sgf'] as String?,
    alunoStatus: linha['aluno_status'] as String?,
    blocoId: linha['bloco_id'] == null ? null : '${linha['bloco_id']}',
    blocoDiaSemana: (linha['dia_semana'] as num?)?.toInt(),
    blocoHoraInicio: linha['hora_inicio'] as String?,
    blocoSalaNome: linha['bloco_sala_nome'] as String?,
    materialId: linha['material_id'] == null ? null : '${linha['material_id']}',
    materialCodigo: linha['material_codigo'] as String?,
    materialNome: linha['material_nome'] as String?,
    pcId: linha['pc_id'] == null ? null : '${linha['pc_id']}',
    pcIdentificador: linha['pc_identificador'] as String?,
  );

  final String id;
  final String tipo;
  final String severidade;

  /// 1 = ALTA, 2 = MEDIA, 3 = BAIXA. **Numérica**, e é a coluna que a view
  /// calcula justamente porque `'ALTA' < 'BAIXA'` em ordenação alfabética
  /// (card 5.5) — a mesma armadilha das fases "01." a "11." do board.
  final int ordemSeveridade;

  /// O texto que a rotina escreveu, **com os números do dia**: `on conflict do
  /// update` mantém a descrição fresca (card 5.5 (b)). É o que torna a linha
  /// acionável, e por isso ela é coluna da lista e não só do detalhe.
  final String descricao;

  /// `<TIPO>:<id>`, com sufixo quando o tipo tem dois sentidos. É daqui que sai
  /// [sentido] — a única informação que distingue as duas metades do
  /// `REP_VIRADA`, e que a view não traz em coluna própria.
  final String chaveDedup;

  final DateTime criadoEm;
  final int diasAberta;

  final String? alunoId;
  final String? alunoNome;
  final String? codigoSgf;
  final String? alunoStatus;

  final String? blocoId;
  final int? blocoDiaSemana;
  final String? blocoHoraInicio;
  final String? blocoSalaNome;

  final String? materialId;
  final String? materialCodigo;
  final String? materialNome;

  final String? pcId;
  final String? pcIdentificador;

  /// Verdadeiro quando a pendência aponta para algo que o leitor **não pode
  /// ler**: o id veio, o nome não. A tela diz isso em vez de mostrar "—" seco,
  /// que soaria como dado faltando no banco.
  bool get referenciaOculta =>
      (alunoId != null && alunoNome == null) ||
      (blocoId != null && blocoDiaSemana == null) ||
      (materialId != null && materialNome == null) ||
      (pcId != null && pcIdentificador == null);

  /// A referência legível: `Afonso (4433)`, `Seg 08:00 · Laboratório 1`,
  /// `INT-05 — Interativo 5`, `LAB1-03`. Referência que o leitor não alcança
  /// vira `—` (card 2.3 §9); pendência sem referência nenhuma
  /// (`ROTINA_FALHOU`) também.
  String get referencia {
    final partes = <String>[
      if (alunoId != null)
        alunoNome == null
            ? '—'
            : (codigoSgf == null ? alunoNome! : '$alunoNome ($codigoSgf)'),
      if (blocoId != null)
        blocoDiaSemana == null || blocoHoraInicio == null
            ? '—'
            : [
                rotuloBloco(blocoDiaSemana!, blocoHoraInicio!),
                ?blocoSalaNome,
              ].join(' · '),
      if (materialId != null)
        materialNome == null
            ? '—'
            : (materialCodigo == null
                  ? materialNome!
                  : '$materialCodigo — $materialNome'),
      if (pcId != null) pcIdentificador ?? '—',
    ];
    return partes.isEmpty ? '—' : partes.join(' · ');
  }

  /// Só para `REP_VIRADA`; nulo em todos os outros tipos.
  SentidoVirada? get sentido =>
      tipo == 'REP_VIRADA' ? sentidoVirada(chaveDedup) : null;
}

/// As duas metades da sugestão do card 2.5 §6, que só a `chave_dedup` separa —
/// `REP:<aluno>:CONTINUO` e `REP:<aluno>:VOLTA`. Sem o sufixo o índice único
/// parcial descartaria em silêncio a sugestão de volta enquanto a de ida
/// estivesse aberta, e a central não teria como saber qual função chamar.
enum SentidoVirada { continuo, volta }

SentidoVirada? sentidoVirada(String chaveDedup) => switch (chaveDedup) {
  final chave when chave.endsWith(':CONTINUO') => SentidoVirada.continuo,
  final chave when chave.endsWith(':VOLTA') => SentidoVirada.volta,
  _ => null,
};

/// `hoje` / `há 1 dia` / `há 12 dias` — a coluna "Aberta" do wireframe §14.1.
String rotuloIdade(int diasAberta) => switch (diasAberta) {
  <= 0 => 'hoje',
  1 => 'há 1 dia',
  final dias => 'há $dias dias',
};

// ---------------------------------------------------------------------------
// Ação contextual — a pendência como fila de trabalho (wireframe §14.3)
// ---------------------------------------------------------------------------

/// Cada tipo tem **uma** ação primária que leva à tela onde o problema se
/// resolve. É o que separa fila de trabalho de relatório.
enum AcaoPendencia {
  /// `ROTINA_FALHOU` — não há tela a abrir; o detalhe técnico é a ação.
  nenhuma,
  verAluno,
  verBloco,
  verPc,
  verMaterial,

  /// `REP_VIRADA` — a virada é **sugerida, nunca automática** (card 2.5), e é
  /// aqui que uma pessoa a executa. É o caso que originou a regra: escolher o
  /// bloco é justamente a parte que o `pg_cron` não podia fazer.
  executarVirada,
}

AcaoPendencia acaoDe(String tipo) => switch (tipo) {
  'REP_VIRADA' => AcaoPendencia.executarVirada,
  'ALUNO_SEM_TURMA' ||
  'ACELERAR_SEM_2O_BLOCO' ||
  'PREVISAO_VENCIDA' ||
  'TRILHA_DIVERGENTE_COMBO' ||
  'SUGERIR_FORMADO' ||
  'ALUNO_ULTIMO_LIVRO' ||
  'STANDBY_PROLONGADO' ||
  'CERTIFICADO_INCONSISTENTE' => AcaoPendencia.verAluno,
  'BLOCO_ACIMA_CAPACIDADE' => AcaoPendencia.verBloco,
  'PC_SEM_SUBSTITUTO' => AcaoPendencia.verPc,
  'COMPRA_SEM_ESTOQUE' ||
  'ESTOQUE_ZERO' ||
  'ESTOQUE_ABAIXO_MINIMO' => AcaoPendencia.verMaterial,
  _ => AcaoPendencia.nenhuma,
};

/// O rótulo do botão, **por tipo** e não por destino (wireframe §14.3).
///
/// "Ver aluno" servia aos oito tipos que levam à ficha, e isso é o oposto de
/// uma fila de trabalho: o botão precisa dizer o que se vai FAZER — alocar,
/// formar, conferir o checklist —, não para onde a tela vai. Foi o achado da
/// revisão da fase 05.
String rotuloAcaoPendencia(String tipo) => switch (tipo) {
  'ALUNO_SEM_TURMA' => 'Alocar',
  'ACELERAR_SEM_2O_BLOCO' => 'Ver turmas do aluno',
  'SUGERIR_FORMADO' => 'Formar',
  'CERTIFICADO_INCONSISTENTE' => 'Ver checklist',
  'TRILHA_DIVERGENTE_COMBO' || 'ALUNO_ULTIMO_LIVRO' => 'Ver trilha',
  'PREVISAO_VENCIDA' => 'Ver previsão',
  'STANDBY_PROLONGADO' => 'Ver aluno',
  'BLOCO_ACIMA_CAPACIDADE' => 'Ver turma',
  'PC_SEM_SUBSTITUTO' => 'Ver PC',
  'COMPRA_SEM_ESTOQUE' ||
  'ESTOQUE_ZERO' ||
  'ESTOQUE_ABAIXO_MINIMO' => 'Ver material',
  'REP_VIRADA' => 'Executar',
  _ => '',
};

/// A aba da ficha em que o problema daquele tipo se desfaz (wireframe §14.3).
///
/// ⚠️ **Trilha (card 6.6) e Certificado (8.6) ainda não existem** — as duas
/// abas estão no lugar, dizendo qual card as entrega, e a ficha abre nelas do
/// mesmo jeito: o destino certo com o conteúdo por vir é honesto; mandar para
/// Dados seria mandar para o lugar errado. Registrado no §17 do wireframe.
String abaDaFicha(String tipo) => switch (tipo) {
  'ALUNO_SEM_TURMA' || 'ACELERAR_SEM_2O_BLOCO' => 'turmas',
  'TRILHA_DIVERGENTE_COMBO' || 'ALUNO_ULTIMO_LIVRO' => 'trilha',
  'CERTIFICADO_INCONSISTENTE' => 'certificado',
  'STANDBY_PROLONGADO' => 'historico',
  _ => 'dados',
};

/// O parâmetro de consulta que leva o **id** da referência à tela de destino —
/// `?bloco=`, `?pc=`, `?material=`. Nulo quando a ação não navega, ou quando o
/// destino é a ficha do aluno, que tem rota própria.
String? parametroDaAcao(AcaoPendencia acao) => switch (acao) {
  AcaoPendencia.verBloco => 'bloco',
  AcaoPendencia.verPc => 'pc',
  AcaoPendencia.verMaterial => 'material',
  AcaoPendencia.verAluno ||
  AcaoPendencia.nenhuma ||
  AcaoPendencia.executarVirada => null,
};

/// O id que vai no parâmetro — o da referência daquela ação.
String? idDaAcao(Pendencia p) => switch (acaoDe(p.tipo)) {
  AcaoPendencia.verBloco => p.blocoId,
  AcaoPendencia.verPc => p.pcId,
  AcaoPendencia.verMaterial => p.materialId,
  _ => null,
};

/// O **id de rota** (docs/permissoes-matriz.md §6) da tela de destino, para a
/// central guardar a ação pelo mesmo conjunto mínimo que guarda a rota. Nulo
/// quando a ação não navega.
///
/// ⚠️ Divergência registrada com o wireframe §14.3: as três de estoque apontam
/// para **Materiais** e não para Compras, que é a tela 7 do card **6.8** e ainda
/// não existe. Os três tipos também só passam a ser abertos na fase 6, então
/// nenhuma dessas linhas tem efeito hoje; quando Compras nascer, é aqui que a
/// linha muda — em um lugar só.
String? rotaDaAcao(AcaoPendencia acao) => switch (acao) {
  AcaoPendencia.verAluno => 'alunos',
  AcaoPendencia.verBloco => 'turmas',
  AcaoPendencia.verPc => 'salas',
  AcaoPendencia.verMaterial => 'materiais',
  AcaoPendencia.nenhuma || AcaoPendencia.executarVirada => null,
};

/// A ação só é oferecida quando existe **para onde ir**.
///
/// A prova de que dá para ir é o **nome**, não o id: as quatro referências
/// chegam por `left join` e o id vem mesmo quando a RLS escondeu o resto
/// (card 2.3 §9). Id sem nome é exatamente o caso de quem não pode ler a tabela
/// de destino — oferecer o botão ali seria oferecer o que vai falhar
/// (card 4.4 (d)). A regra é a mesma para os quatro; antes era só para o aluno,
/// e a assimetria não tinha razão (revisão da fase 05).
bool referenciaDaAcaoPresente(Pendencia p) => switch (acaoDe(p.tipo)) {
  AcaoPendencia.verAluno => p.alunoNome != null,
  AcaoPendencia.verBloco => p.blocoId != null && p.blocoDiaSemana != null,
  AcaoPendencia.verPc => p.pcId != null && p.pcIdentificador != null,
  AcaoPendencia.verMaterial => p.materialId != null && p.materialNome != null,
  AcaoPendencia.executarVirada => p.alunoId != null && p.sentido != null,
  AcaoPendencia.nenhuma => false,
};

/// "Fecha automaticamente quando …" (wireframe §14.2) — para ninguém resolver à
/// mão o que o sistema encerra sozinho. Nulo quando não há promessa a fazer: os
/// tipos das fases 6 e 8 têm chamador escrito, mas a condição de fechamento é
/// deles, e escrevê-la aqui hoje seria inventar contrato de card que não veio.
String? fechamentoAutomatico(String tipo) => switch (tipo) {
  'ALUNO_SEM_TURMA' =>
    'Fecha sozinha na próxima execução da rotina diária (03:10), quando o '
        'aluno voltar a ter turma ativa — ou deixar de estar ATIVO/ACELERAR.',
  'BLOCO_ACIMA_CAPACIDADE' =>
    'Fecha sozinha quando a ocupação voltar a caber na capacidade: na hora, se '
        'a mudança vier de um PC, e na rotina diária de qualquer forma.',
  'ACELERAR_SEM_2O_BLOCO' =>
    'Fecha sozinha na rotina diária, quando o aluno tiver o segundo bloco — ou '
        'deixar de ser ACELERAR.',
  'REP_VIRADA' =>
    'Fecha no ato quando a virada é executada aqui, e na rotina diária quando '
        'o critério do débito deixar de valer.',
  'PC_SEM_SUBSTITUTO' =>
    'Fecha sozinha quando a manutenção for encerrada, ou quando o PC ganhar um '
        'substituto de OUTRA sala — substituto da própria sala não repõe '
        'máquina nenhuma.',
  'ROTINA_FALHOU' =>
    'Fecha sozinha na próxima execução em que a rotina correr sem erro.',
  _ => null,
};

/// ⚠️ O texto que o diálogo de IGNORAR **precisa** dizer (card 5.5 (c)).
///
/// `pendencia_aberta_uk` é único **parcial** (`where resolvida_em is null`),
/// então a dedup só vale enquanto a pendência está aberta: fechada, a rotina
/// reabre na execução seguinte se a condição ainda valer. É decisão, não
/// defeito — silêncio permanente por chave seria a falha calada que o projeto
/// cataloga —, e por isso o diálogo não pode prometer "não me avise mais".
const avisoIgnorar =
    'Ignorar não silencia para sempre: enquanto a condição valer, a rotina '
    'diária (03:10) reabre esta pendência, com a justificativa de hoje '
    'guardada no histórico. Para deixar de ser avisado, mude o que a causa — '
    'no caso de capacidade, a capacidade manual do bloco.';

// ---------------------------------------------------------------------------
// Filtros e ordenação — estado da tela (design-system §5.3)
// ---------------------------------------------------------------------------

@immutable
class FiltroPendencias {
  const FiltroPendencias({this.severidade, this.tipo, this.diasMinimos});

  static const semFiltro = FiltroPendencias();

  final String? severidade;
  final String? tipo;

  /// O `[há quanto tempo v]` do wireframe §14.1, como idade **mínima** — o que
  /// se procura numa fila de trabalho é o que está parado há tempo demais.
  final int? diasMinimos;

  int get ativos =>
      (severidade != null ? 1 : 0) +
      (tipo != null ? 1 : 0) +
      (diasMinimos != null ? 1 : 0);

  FiltroPendencias copiar({
    String? Function()? severidade,
    String? Function()? tipo,
    int? Function()? diasMinimos,
  }) => FiltroPendencias(
    severidade: severidade == null ? this.severidade : severidade(),
    tipo: tipo == null ? this.tipo : tipo(),
    diasMinimos: diasMinimos == null ? this.diasMinimos : diasMinimos(),
  );
}

/// As opções do filtro de idade, na ordem em que aparecem.
const opcoesIdade = <int, String>{
  1: 'há 1 dia ou mais',
  3: 'há 3 dias ou mais',
  7: 'há 7 dias ou mais',
};

/// Filtra **e ordena**: a lista da tela nunca depende da ordem em que o
/// PostgREST devolveu. A view calcula `ordem_severidade` numérica, e ordenar
/// aqui pela mesma coluna é o que impede a tela de reintroduzir a ordenação
/// alfabética que põe BAIXA antes de ALTA.
List<Pendencia> filtrarPendencias(
  List<Pendencia> todas,
  FiltroPendencias filtro,
) => ordenarPendencias([
  for (final p in todas)
    if ((filtro.severidade == null || p.severidade == filtro.severidade) &&
        (filtro.tipo == null || p.tipo == filtro.tipo) &&
        (filtro.diasMinimos == null || p.diasAberta >= filtro.diasMinimos!))
      p,
]);

/// Severidade primeiro, mais antiga depois — a fila de trabalho na ordem em que
/// se trabalha. O terceiro critério é o id, para a ordem ser estável entre duas
/// leituras: sem ele, duas pendências iguais em severidade e idade trocariam de
/// lugar a cada recarga, e a pessoa perderia a linha que estava lendo.
List<Pendencia> ordenarPendencias(List<Pendencia> lista) {
  final ordenada = List.of(lista);
  ordenada.sort((a, b) {
    final severidade = a.ordemSeveridade.compareTo(b.ordemSeveridade);
    if (severidade != 0) return severidade;
    final idade = b.diasAberta.compareTo(a.diasAberta);
    return idade != 0 ? idade : a.id.compareTo(b.id);
  });
  return ordenada;
}

/// Quantas abertas de severidade **ALTA** — o contador do menu (card 2.6
/// decisão f, design-system §3.1).
///
/// Só ALTA, e não o total: um sino que dispara sempre não é avisado, é ignorado
/// — e `ESTOQUE_ABAIXO_MINIMO` de trinta apostilas manteria o contador aceso
/// para sempre, escondendo a entrega bloqueada que apareceu hoje.
int contarAltas(Iterable<Pendencia> lista) =>
    lista.where((p) => p.severidade == 'ALTA').length;
