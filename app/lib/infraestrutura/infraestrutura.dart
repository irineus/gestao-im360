/// A infraestrutura física como o app a vê (card 4.5): os modelos das quatro
/// tabelas do card 4.3 que a tela lê e escreve (`sala`, `pc`, `pc_manutencao`,
/// `professor`) e a lógica **pura** da tela — capacidade efetiva da sala,
/// manutenção em aberto, ação contextual de cada PC, datas e filtros.
///
/// Pura de propósito: é o que se testa sem rede e sem cliente Supabase
/// (card 2.8 §9.3). Regra de negócio continua no banco; aqui só há forma. O
/// que a tela deriva (capacidade, manutenção aberta) é **informativo**: quem
/// decide capacidade de bloco é `fn_capacidade_efetiva` (card 5.2) e quem
/// amarra `pc.status` a `pc_manutencao` é o card 5.4.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../util/datas.dart';

export '../util/datas.dart';

/// Conjuntos fechados no `check` das colunas (card 4.3) e como aparecem em
/// tela. A chave é o valor do banco; o app nunca compara pelo rótulo.
const tiposSala = <String, String>{
  'LABORATORIO': 'Laboratório',
  'SALA_MODULAR': 'Sala modular',
};

const statusPc = <String, String>{
  'OPERACIONAL': 'Operacional',
  'MANUTENCAO': 'Em manutenção',
  'DESATIVADO': 'Desativado',
};

const tiposManutencao = <String, String>{
  'PREVENTIVA': 'Preventiva',
  'CORRETIVA': 'Corretiva',
  'CONFIGURACAO': 'Configuração',
};

String rotuloTipoSala(String tipo) => tiposSala[tipo] ?? tipo;
String rotuloStatusPc(String status) => statusPc[status] ?? status;
String rotuloTipoManutencao(String tipo) => tiposManutencao[tipo] ?? tipo;

// ---------------------------------------------------------------------------
// Modelos
// ---------------------------------------------------------------------------

@immutable
class Sala {
  const Sala({
    this.id,
    required this.nome,
    required this.tipo,
    required this.capacidadeNominal,
    this.ativo = true,
  });

  factory Sala.deLinha(Map<String, dynamic> linha) => Sala(
    id: '${linha['id']}',
    nome: '${linha['nome']}',
    tipo: '${linha['tipo']}',
    capacidadeNominal: (linha['capacidade_nominal'] as num).toInt(),
    ativo: linha['ativo'] as bool? ?? true,
  );

  /// Nulo = ainda não gravada.
  final String? id;
  final String nome;
  final String tipo;

  /// Teto físico. A capacidade **efetiva** é derivada — ver [resumirSalas].
  final int capacidadeNominal;
  final bool ativo;

  Map<String, dynamic> paraLinha(String unidadeId) => {
    'unidade_id': unidadeId,
    'nome': nome,
    'tipo': tipo,
    'capacidade_nominal': capacidadeNominal,
    'ativo': ativo,
  };
}

@immutable
class Pc {
  const Pc({
    this.id,
    required this.salaId,
    required this.identificador,
    this.status = 'OPERACIONAL',
    this.deProfessor = false,
    this.observacao,
    this.credencialEm,
  });

  factory Pc.deLinha(Map<String, dynamic> linha) => Pc(
    id: '${linha['id']}',
    salaId: '${linha['sala_id']}',
    identificador: '${linha['identificador']}',
    status: '${linha['status']}',
    deProfessor: linha['de_professor'] as bool? ?? false,
    observacao: linha['observacao'] as String?,
    credencialEm: linha['credencial_em'] == null
        ? null
        : DateTime.parse('${linha['credencial_em']}').toLocal(),
  );

  final String? id;
  final String salaId;
  final String identificador;
  final String status;

  /// A máquina do professor (`pc.de_professor`, card 9.2,77): não é lugar de
  /// aluno e não conta na capacidade efetiva — nem na do banco
  /// (`fn_capacidade_efetiva`) nem na que a tela deriva ([resumirSalas]).
  final bool deProfessor;
  final String? observacao;

  /// Carimbo da credencial no Vault (`pc.credencial_em`), legível com
  /// `salas.ler` (docs/politica-credenciais-pcs.md §8). Nulo = sem credencial.
  final DateTime? credencialEm;

  bool get operacional => status == 'OPERACIONAL';
  bool get temCredencial => credencialEm != null;

  Pc copiar({String? status, DateTime? credencialEm}) => Pc(
    id: id,
    salaId: salaId,
    identificador: identificador,
    status: status ?? this.status,
    deProfessor: deProfessor,
    observacao: observacao,
    credencialEm: credencialEm ?? this.credencialEm,
  );

  /// As três colunas de credencial ficam de fora de propósito: só
  /// `fn_pc_credencial_gravar` as escreve, e `pc_credencial_ck` recusaria
  /// metade delas.
  Map<String, dynamic> paraLinha(String unidadeId) => {
    'unidade_id': unidadeId,
    'sala_id': salaId,
    'identificador': identificador,
    'status': status,
    'de_professor': deProfessor,
    'observacao': (observacao == null || observacao!.trim().isEmpty)
        ? null
        : observacao!.trim(),
  };
}

@immutable
class PcManutencao {
  const PcManutencao({
    this.id,
    required this.pcId,
    required this.tipo,
    required this.dataInicio,
    this.dataFim,
    this.descricao,
    this.pcSubstitutoId,
    this.criadoPor,
    this.criadoPorNome,
    this.criadoEm,
  });

  factory PcManutencao.deLinha(Map<String, dynamic> linha) => PcManutencao(
    id: '${linha['id']}',
    pcId: '${linha['pc_id']}',
    tipo: '${linha['tipo']}',
    dataInicio: DateTime.parse('${linha['data_inicio']}'),
    dataFim: linha['data_fim'] == null
        ? null
        : DateTime.parse('${linha['data_fim']}'),
    descricao: linha['descricao'] as String?,
    pcSubstitutoId: linha['pc_substituto_id'] == null
        ? null
        : '${linha['pc_substituto_id']}',
    criadoPor: linha['criado_por'] == null ? null : '${linha['criado_por']}',
    criadoPorNome:
        (linha['autor'] as Map<String, dynamic>?)?['nome'] as String?,
    criadoEm: linha['criado_em'] == null
        ? null
        : DateTime.parse('${linha['criado_em']}').toLocal(),
  );

  final String? id;
  final String pcId;
  final String tipo;
  final DateTime dataInicio;

  /// Fim da manutenção — **o dia em que o PC volta a operar**, não o último dia
  /// parado. Nulo = sem previsão. É a leitura do card 4.5 (c), e desde o card
  /// 5.4 é também a do banco: `fn_capacidade_efetiva` e
  /// `fn_pc_status_sincronizar` cobrem `[data_inicio, data_fim)`. Antes disso o
  /// banco lia o intervalo fechado, e encerrar a manutenção hoje deixaria o PC
  /// em MANUTENCAO até amanhã.
  final DateTime? dataFim;
  final String? descricao;
  final String? pcSubstitutoId;

  /// Quem registrou (`criado_por`, carimbado pelo `fn_auditoria`) e o nome
  /// dele, que vem de `fn_usuarios_nomes()` e não do embed em `usuario` — o
  /// embed devolve nulo para quem não tem `admin.ler`, e o histórico sairia sem
  /// o "quem" para três dos quatro perfis (card 9.2,74). Só a leitura do
  /// histórico os preenche (card 9.2,78); nulos nas demais.
  final String? criadoPor;
  final String? criadoPorNome;
  final DateTime? criadoEm;

  /// Em aberto em [hoje]: já começou e o fim ainda não chegou. Fim igual a hoje
  /// é encerrada — é o que "Encerrar" grava —, e é a mesma condição que o banco
  /// aplica desde o card 5.4.
  bool abertaEm(DateTime hoje) {
    final fim = dataFim;
    final dia = soData(hoje);
    return !soData(dataInicio).isAfter(dia) &&
        (fim == null || soData(fim).isAfter(dia));
  }

  PcManutencao copiar({DateTime? dataFim}) => PcManutencao(
    id: id,
    pcId: pcId,
    tipo: tipo,
    dataInicio: dataInicio,
    dataFim: dataFim ?? this.dataFim,
    descricao: descricao,
    pcSubstitutoId: pcSubstitutoId,
    criadoPor: criadoPor,
    criadoPorNome: criadoPorNome,
    criadoEm: criadoEm,
  );

  /// Sem as colunas de auditoria: quem as escreve é o `fn_auditoria`.
  Map<String, dynamic> paraLinha(String unidadeId) => {
    'unidade_id': unidadeId,
    'pc_id': pcId,
    'tipo': tipo,
    'data_inicio': dataIso(dataInicio),
    'data_fim': dataFim == null ? null : dataIso(dataFim!),
    'descricao': (descricao == null || descricao!.trim().isEmpty)
        ? null
        : descricao!.trim(),
    'pc_substituto_id': pcSubstitutoId,
  };
}

@immutable
class Professor {
  const Professor({this.id, required this.nome, this.ativo = true});

  factory Professor.deLinha(Map<String, dynamic> linha) => Professor(
    id: '${linha['id']}',
    nome: '${linha['nome']}',
    ativo: linha['ativo'] as bool? ?? true,
  );

  final String? id;
  final String nome;
  final bool ativo;

  Map<String, dynamic> paraLinha(String unidadeId) => {
    'unidade_id': unidadeId,
    'nome': nome,
    'ativo': ativo,
  };
}

/// O par que `fn_pc_credencial_ler` devolve. Vive só no diálogo que o exibe:
/// nunca em provider, em `shared_preferences`, em log nem em breadcrumb
/// (docs/politica-credenciais-pcs.md §8). O `toString` não imprime a senha,
/// para que um `print` distraído ou um evento do Sentry não a levem junto.
@immutable
class CredencialPc {
  const CredencialPc({required this.usuario, required this.senha});

  final String usuario;
  final String senha;

  @override
  String toString() => 'CredencialPc(usuario: $usuario, senha: •••)';
}

// ---------------------------------------------------------------------------
// Derivações — informativas, nunca regra (card 2.6 decisão 2)
// ---------------------------------------------------------------------------

/// O que o cartão da sala mostra: quantos PCs tem, quantos operam e a
/// capacidade efetiva — PCs de ALUNO operacionais até o teto nominal, a mesma
/// conta que `fn_capacidade_efetiva` (card 5.2) faz por bloco, sem o override.
/// O PC do professor opera mas não é vaga (card 9.2,77): entra em
/// `operacionais` e fica fora de `efetiva`.
@immutable
class ResumoSala {
  const ResumoSala({
    required this.total,
    required this.operacionais,
    required this.efetiva,
  });

  static const vazio = ResumoSala(total: 0, operacionais: 0, efetiva: 0);

  final int total;
  final int operacionais;
  final int efetiva;
}

int capacidadeEfetiva({required int nominal, required int operacionais}) =>
    math.max(0, math.min(nominal, operacionais));

Map<String, ResumoSala> resumirSalas(Iterable<Sala> salas, Iterable<Pc> pcs) {
  final total = <String, int>{};
  final operacionais = <String, int>{};
  final deAluno = <String, int>{};
  for (final pc in pcs) {
    total[pc.salaId] = (total[pc.salaId] ?? 0) + 1;
    if (pc.operacional) {
      operacionais[pc.salaId] = (operacionais[pc.salaId] ?? 0) + 1;
      if (!pc.deProfessor) {
        deAluno[pc.salaId] = (deAluno[pc.salaId] ?? 0) + 1;
      }
    }
  }
  return {
    for (final sala in salas)
      if (sala.id != null)
        sala.id!: ResumoSala(
          total: total[sala.id] ?? 0,
          operacionais: operacionais[sala.id] ?? 0,
          efetiva: capacidadeEfetiva(
            nominal: sala.capacidadeNominal,
            operacionais: deAluno[sala.id] ?? 0,
          ),
        ),
  };
}

/// A manutenção em aberto de cada PC (`pc_id` → manutenção), a mais recente
/// quando houver mais de uma. É o que a linha do PC mostra e o que decide
/// entre "Manutenção" e "Encerrar".
Map<String, PcManutencao> manutencoesAbertas(
  Iterable<PcManutencao> manutencoes,
  DateTime hoje,
) {
  final abertas = <String, PcManutencao>{};
  for (final m in manutencoes) {
    if (!m.abertaEm(hoje)) continue;
    final atual = abertas[m.pcId];
    if (atual == null || m.dataInicio.isAfter(atual.dataInicio)) {
      abertas[m.pcId] = m;
    }
  }
  return abertas;
}

/// A ação contextual da linha do PC (docs/wireframes.md §13): com manutenção
/// aberta, encerrar; desativado, reativar; senão, abrir manutenção.
enum AcaoPc { registrarManutencao, encerrarManutencao, reativar }

AcaoPc acaoContextual(Pc pc, PcManutencao? aberta) {
  if (aberta != null) return AcaoPc.encerrarManutencao;
  if (pc.status == 'DESATIVADO') return AcaoPc.reativar;
  return AcaoPc.registrarManutencao;
}

/// A linha de situação do PC: o status do banco e, se houver, a manutenção em
/// aberto com o que falta nela ("sem substituto" é o que derruba a
/// capacidade, card 5.4). A máquina do professor diz que é dele e não fala de
/// substituto: parada, ela não derruba capacidade nenhuma (card 9.2,77).
String situacaoPc(Pc pc, PcManutencao? aberta) {
  final partes = [
    rotuloStatusPc(pc.status),
    if (pc.deProfessor) 'PC do professor, não conta como vaga',
  ];
  if (aberta != null) {
    partes.add(
      '${rotuloTipoManutencao(aberta.tipo).toLowerCase()} desde '
      '${formatarDataCurta(aberta.dataInicio)}',
    );
    if (aberta.dataFim != null) {
      partes.add('prevista até ${formatarDataCurta(aberta.dataFim!)}');
    }
    if (aberta.pcSubstitutoId == null && !pc.deProfessor) {
      partes.add('sem substituto');
    }
  }
  return partes.join(' · ');
}

// ---------------------------------------------------------------------------
// Datas — moram em util/datas.dart desde o card 4.6 (a ficha do aluno usa as
// mesmas funções); continuam exportadas daqui para quem já as importava.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Filtros — estado da tela, desligável e visível (design-system §5.3)
// ---------------------------------------------------------------------------

@immutable
class FiltroSalas {
  const FiltroSalas({this.busca = '', this.tipo, this.soAtivas = true});

  /// "Limpar filtros" mostra **tudo**, inclusive a inativa (card 4.4 (g)).
  static const semFiltro = FiltroSalas(soAtivas: false);

  final String busca;
  final String? tipo;
  final bool soAtivas;

  int get ativos =>
      (busca.trim().isNotEmpty ? 1 : 0) +
      (tipo != null ? 1 : 0) +
      (soAtivas ? 1 : 0);

  FiltroSalas copiar({
    String? busca,
    String? Function()? tipo,
    bool? soAtivas,
  }) => FiltroSalas(
    busca: busca ?? this.busca,
    tipo: tipo == null ? this.tipo : tipo(),
    soAtivas: soAtivas ?? this.soAtivas,
  );
}

@immutable
class FiltroProfessores {
  const FiltroProfessores({this.busca = '', this.soAtivos = true});

  static const semFiltro = FiltroProfessores(soAtivos: false);

  final String busca;
  final bool soAtivos;

  int get ativos => (busca.trim().isNotEmpty ? 1 : 0) + (soAtivos ? 1 : 0);

  FiltroProfessores copiar({String? busca, bool? soAtivos}) =>
      FiltroProfessores(
        busca: busca ?? this.busca,
        soAtivos: soAtivos ?? this.soAtivos,
      );
}

bool _casaBusca(String busca, Iterable<String> campos) {
  final termo = busca.trim().toLowerCase();
  if (termo.isEmpty) return true;
  return campos.any((c) => c.toLowerCase().contains(termo));
}

List<Sala> filtrarSalas(List<Sala> todas, FiltroSalas filtro) => [
  for (final s in todas)
    if ((!filtro.soAtivas || s.ativo) &&
        (filtro.tipo == null || s.tipo == filtro.tipo) &&
        _casaBusca(filtro.busca, [s.nome]))
      s,
];

List<Professor> filtrarProfessores(
  List<Professor> todos,
  FiltroProfessores filtro,
) => [
  for (final p in todos)
    if ((!filtro.soAtivos || p.ativo) && _casaBusca(filtro.busca, [p.nome])) p,
];

// ---------------------------------------------------------------------------
// Histórico de manutenções (card 9.2,78) — a aba "Manutenções" da tela 10
// ---------------------------------------------------------------------------

/// Os cinco filtros que o monitor pediu na rodada de 30/09/2026 — "filtrar por
/// máquina, tipo de manutenção, data, por quem e o que foi feito". Nenhum vem
/// ligado: a aba abre no histórico inteiro, da mais recente para a mais antiga.
@immutable
class FiltroManutencoes {
  const FiltroManutencoes({
    this.pcId,
    this.tipo,
    this.de,
    this.ate,
    this.autorId,
    this.busca = '',
  });

  static const semFiltro = FiltroManutencoes();

  final String? pcId;
  final String? tipo;

  /// As duas pontas do filtro de data, cada uma opcional. Um dia só é
  /// `de == ate`.
  final DateTime? de;
  final DateTime? ate;

  /// `criado_por` — quem registrou.
  final String? autorId;

  /// Texto procurado na descrição ("o que foi feito").
  final String busca;

  /// "Data" conta como UM filtro, com uma ponta ou com as duas.
  int get ativos =>
      (pcId != null ? 1 : 0) +
      (tipo != null ? 1 : 0) +
      (de != null || ate != null ? 1 : 0) +
      (autorId != null ? 1 : 0) +
      (busca.trim().isNotEmpty ? 1 : 0);

  FiltroManutencoes copiar({
    String? Function()? pcId,
    String? Function()? tipo,
    DateTime? Function()? de,
    DateTime? Function()? ate,
    String? Function()? autorId,
    String? busca,
  }) => FiltroManutencoes(
    pcId: pcId == null ? this.pcId : pcId(),
    tipo: tipo == null ? this.tipo : tipo(),
    de: de == null ? this.de : de(),
    ate: ate == null ? this.ate : ate(),
    autorId: autorId == null ? this.autorId : autorId(),
    busca: busca ?? this.busca,
  );
}

/// A manutenção toca o período `[de, ate]`, com as DUAS pontas fechadas.
///
/// ⚠️ Não é o `[data_inicio, data_fim)` da capacidade (card 5.4): aquele
/// intervalo responde "o PC estava parado neste dia?", e este responde "o que
/// aconteceu neste dia?". Uma manutenção feita e encerrada no mesmo dia tem
/// `data_fim == data_inicio` — intervalo VAZIO na leitura do banco — e é
/// exatamente a que o monitor procura quando filtra pela data em que a fez.
bool manutencaoNoPeriodo(PcManutencao m, {DateTime? de, DateTime? ate}) {
  final inicio = soData(m.dataInicio);
  final fim = m.dataFim == null ? null : soData(m.dataFim!);
  if (ate != null && inicio.isAfter(soData(ate))) return false;
  if (de != null && fim != null && fim.isBefore(soData(de))) return false;
  return true;
}

List<PcManutencao> filtrarManutencoes(
  List<PcManutencao> todas,
  FiltroManutencoes filtro,
) => [
  for (final m in todas)
    if ((filtro.pcId == null || m.pcId == filtro.pcId) &&
        (filtro.tipo == null || m.tipo == filtro.tipo) &&
        (filtro.autorId == null || m.criadoPor == filtro.autorId) &&
        manutencaoNoPeriodo(m, de: filtro.de, ate: filtro.ate) &&
        _casaBusca(filtro.busca, [m.descricao ?? '']))
      m,
];

/// Da mais recente para a mais antiga, como o monitor pediu: pela data de
/// início e, no mesmo dia, pela hora em que foi registrada. A tela ordena
/// mesmo que o repositório já devolva ordenado — a ordem é requisito, e o
/// teste a mede aqui, sem rede.
List<PcManutencao> ordenarHistorico(Iterable<PcManutencao> manutencoes) {
  final lista = List.of(manutencoes);
  lista.sort((a, b) {
    final porData = b.dataInicio.compareTo(a.dataInicio);
    if (porData != 0) return porData;
    final ca = a.criadoEm;
    final cb = b.criadoEm;
    if (ca == null) return cb == null ? 0 : 1;
    if (cb == null) return -1;
    return cb.compareTo(ca);
  });
  return lista;
}

/// Quem aparece no histórico (`criado_por` → nome), em ordem de nome — as
/// opções do filtro "Registrada por". Só quem registrou alguma: um filtro que
/// oferece uma pessoa e devolve lista vazia é ruído.
Map<String, String> autoresDoHistorico(Iterable<PcManutencao> manutencoes) {
  final autores = <String, String>{
    for (final m in manutencoes)
      if (m.criadoPor != null && m.criadoPorNome != null)
        m.criadoPor!: m.criadoPorNome!,
  };
  final ordem = autores.keys.toList()
    ..sort((a, b) => autores[a]!.compareTo(autores[b]!));
  return {for (final id in ordem) id: autores[id]!};
}

/// O que a coluna "Registrada por" diz quando não há nome: a carga da
/// escola-fixture e a da importação não têm autor.
const semAutor = '—';
