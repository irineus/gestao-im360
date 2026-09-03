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
    this.observacao,
    this.credencialEm,
  });

  factory Pc.deLinha(Map<String, dynamic> linha) => Pc(
    id: '${linha['id']}',
    salaId: '${linha['sala_id']}',
    identificador: '${linha['identificador']}',
    status: '${linha['status']}',
    observacao: linha['observacao'] as String?,
    credencialEm: linha['credencial_em'] == null
        ? null
        : DateTime.parse('${linha['credencial_em']}').toLocal(),
  );

  final String? id;
  final String salaId;
  final String identificador;
  final String status;
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
  );

  final String? id;
  final String pcId;
  final String tipo;
  final DateTime dataInicio;

  /// Fim da manutenção. Nulo = sem previsão; no futuro = previsão; no passado
  /// = encerrada. É a leitura que o card 5.4 dá a `data_fim` ("muda o PC para
  /// MANUTENCAO até data_fim").
  final DateTime? dataFim;
  final String? descricao;
  final String? pcSubstitutoId;

  /// Em aberto em [hoje]: sem fim, ou com o fim ainda à frente. Fim igual a
  /// hoje é encerrada — é o que "Encerrar" grava.
  bool abertaEm(DateTime hoje) {
    final fim = dataFim;
    return fim == null || soData(fim).isAfter(soData(hoje));
  }

  PcManutencao copiar({DateTime? dataFim}) => PcManutencao(
    id: id,
    pcId: pcId,
    tipo: tipo,
    dataInicio: dataInicio,
    dataFim: dataFim ?? this.dataFim,
    descricao: descricao,
    pcSubstitutoId: pcSubstitutoId,
  );

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
/// capacidade efetiva — PCs OPERACIONAIS até o teto nominal, a mesma conta
/// que `fn_capacidade_efetiva` (card 5.2) faz por bloco, sem o override.
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
  for (final pc in pcs) {
    total[pc.salaId] = (total[pc.salaId] ?? 0) + 1;
    if (pc.operacional) {
      operacionais[pc.salaId] = (operacionais[pc.salaId] ?? 0) + 1;
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
            operacionais: operacionais[sala.id] ?? 0,
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
/// capacidade, card 5.4).
String situacaoPc(Pc pc, PcManutencao? aberta) {
  final partes = [rotuloStatusPc(pc.status)];
  if (aberta != null) {
    partes.add(
      '${rotuloTipoManutencao(aberta.tipo).toLowerCase()} desde '
      '${formatarDataCurta(aberta.dataInicio)}',
    );
    if (aberta.dataFim != null) {
      partes.add('prevista até ${formatarDataCurta(aberta.dataFim!)}');
    }
    if (aberta.pcSubstitutoId == null) partes.add('sem substituto');
  }
  return partes.join(' · ');
}

// ---------------------------------------------------------------------------
// Datas — sem `intl`: o app não tem localização configurada, e dd/mm/aaaa é
// o único formato que a escola usa.
// ---------------------------------------------------------------------------

String _dois(int n) => n.toString().padLeft(2, '0');

DateTime soData(DateTime d) => DateTime(d.year, d.month, d.day);

String formatarData(DateTime d) =>
    '${_dois(d.day)}/${_dois(d.month)}/${d.year}';

String formatarDataCurta(DateTime d) => '${_dois(d.day)}/${_dois(d.month)}';

/// `yyyy-mm-dd`, o formato da coluna `date` no PostgREST.
String dataIso(DateTime d) => '${d.year}-${_dois(d.month)}-${_dois(d.day)}';

final _formatoData = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$');

/// Lê `dd/mm/aaaa`; nulo quando o texto não é uma data real (31/02 inclusive).
DateTime? lerData(String texto) {
  final casa = _formatoData.firstMatch(texto.trim());
  if (casa == null) return null;
  final dia = int.parse(casa[1]!);
  final mes = int.parse(casa[2]!);
  final ano = int.parse(casa[3]!);
  final data = DateTime(ano, mes, dia);
  if (data.day != dia || data.month != mes || data.year != ano) return null;
  return data;
}

/// Validação local só de formato (design-system §5.4): a ordem entre início e
/// fim quem confere é `pc_manutencao_periodo_ck`, no banco.
String? validarData(String? valor, {bool obrigatorio = true}) {
  final texto = valor?.trim() ?? '';
  if (texto.isEmpty) return obrigatorio ? 'Campo obrigatório.' : null;
  return lerData(texto) == null ? 'Informe uma data como dd/mm/aaaa.' : null;
}

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
