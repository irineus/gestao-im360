/// O catálogo curricular como o app o vê (card 4.4): os modelos das sete
/// tabelas do card 4.1 e a lógica **pura** da tela — filtros e o plano de
/// gravação de uma sequência ordenada.
///
/// Pura de propósito: é o que se testa sem rede e sem cliente Supabase
/// (card 2.8 §9.3). Regra de negócio continua no banco; aqui só há forma.
library;

import 'package:flutter/foundation.dart';

/// Código do método Modular — o único cujo curso tem módulos (card 7.2). Os
/// três códigos estão fechados no `check` de `metodo.codigo` (card 4.1).
const codigoMetodoModular = 'MODULAR';

/// `Material` já é o widget do Flutter; o modelo ganha o sobrenome.
@immutable
class Metodo {
  const Metodo({
    required this.id,
    required this.codigo,
    required this.nome,
    this.ativo = true,
  });

  factory Metodo.deLinha(Map<String, dynamic> linha) => Metodo(
    id: '${linha['id']}',
    codigo: '${linha['codigo']}',
    nome: '${linha['nome']}',
    ativo: linha['ativo'] as bool? ?? true,
  );

  final String id;
  final String codigo;
  final String nome;
  final bool ativo;

  bool get modular => codigo == codigoMetodoModular;

  Metodo copiar({String? nome, bool? ativo}) => Metodo(
    id: id,
    codigo: codigo,
    nome: nome ?? this.nome,
    ativo: ativo ?? this.ativo,
  );

  /// Só o que a tela pode mudar: `codigo` é chave natural fechada no `check`.
  Map<String, dynamic> paraLinha() => {'nome': nome, 'ativo': ativo};
}

@immutable
class MaterialDidatico {
  const MaterialDidatico({
    this.id,
    required this.metodoId,
    required this.codigo,
    required this.nome,
    required this.categoria,
    this.estoqueMinimo = 0,
    this.ativo = true,
  });

  factory MaterialDidatico.deLinha(Map<String, dynamic> linha) =>
      MaterialDidatico(
        id: '${linha['id']}',
        metodoId: '${linha['metodo_id']}',
        codigo: '${linha['codigo']}',
        nome: '${linha['nome']}',
        categoria: '${linha['categoria']}',
        estoqueMinimo: (linha['estoque_minimo'] as num?)?.toInt() ?? 0,
        ativo: linha['ativo'] as bool? ?? true,
      );

  /// Nulo = ainda não gravado.
  final String? id;
  final String metodoId;
  final String codigo;
  final String nome;
  final String categoria;
  final int estoqueMinimo;
  final bool ativo;

  Map<String, dynamic> paraLinha(String unidadeId) => {
    'unidade_id': unidadeId,
    'metodo_id': metodoId,
    'codigo': codigo,
    'nome': nome,
    'categoria': categoria,
    'estoque_minimo': estoqueMinimo,
    'ativo': ativo,
  };
}

@immutable
class Curso {
  const Curso({
    this.id,
    required this.metodoId,
    required this.nome,
    this.ativo = true,
  });

  factory Curso.deLinha(Map<String, dynamic> linha) => Curso(
    id: '${linha['id']}',
    metodoId: '${linha['metodo_id']}',
    nome: '${linha['nome']}',
    ativo: linha['ativo'] as bool? ?? true,
  );

  final String? id;
  final String metodoId;
  final String nome;
  final bool ativo;

  Map<String, dynamic> paraLinha(String unidadeId) => {
    'unidade_id': unidadeId,
    'metodo_id': metodoId,
    'nome': nome,
    'ativo': ativo,
  };
}

/// Uma linha de `curso_material` ou de `combo_curso`: o pai, o filho e a
/// posição. As duas tabelas têm a mesma forma, e a tela as edita com o mesmo
/// componente.
@immutable
class LinhaOrdenada {
  const LinhaOrdenada({
    required this.id,
    required this.filhoId,
    required this.ordem,
  });

  final String id;
  final String filhoId;
  final int ordem;
}

@immutable
class Modulo {
  const Modulo({
    this.id,
    required this.cursoId,
    required this.materialId,
    required this.nome,
    required this.ordem,
  });

  factory Modulo.deLinha(Map<String, dynamic> linha) => Modulo(
    id: '${linha['id']}',
    cursoId: '${linha['curso_id']}',
    materialId: '${linha['material_id']}',
    nome: '${linha['nome']}',
    ordem: (linha['ordem'] as num).toInt(),
  );

  final String? id;
  final String cursoId;
  final String materialId;
  final String nome;
  final int ordem;

  Map<String, dynamic> paraLinha(String unidadeId) => {
    'unidade_id': unidadeId,
    'curso_id': cursoId,
    'material_id': materialId,
    'nome': nome,
    'ordem': ordem,
  };
}

@immutable
class Combo {
  const Combo({
    this.id,
    required this.metodoId,
    required this.nome,
    this.ativo = true,
  });

  factory Combo.deLinha(Map<String, dynamic> linha) => Combo(
    id: '${linha['id']}',
    metodoId: '${linha['metodo_id']}',
    nome: '${linha['nome']}',
    ativo: linha['ativo'] as bool? ?? true,
  );

  final String? id;
  final String metodoId;
  final String nome;
  final bool ativo;

  Map<String, dynamic> paraLinha(String unidadeId) => {
    'unidade_id': unidadeId,
    'metodo_id': metodoId,
    'nome': nome,
    'ativo': ativo,
  };
}

// ---------------------------------------------------------------------------
// Filtros — estado da tela, desligável e visível (design-system §5.3)
// ---------------------------------------------------------------------------

/// O que a tela esconde. A consulta devolve tudo; quem filtra é a tela
/// (card 2.3 §2.3(h)). "Só ativos" vem ligado por padrão (wireframe §9).
@immutable
class FiltroCatalogo {
  const FiltroCatalogo({
    this.busca = '',
    this.metodoId,
    this.categoria,
    this.soAtivos = true,
    this.soAbaixoMinimo = false,
  });

  /// O estado de "Limpar filtros": mostra **tudo**, inclusive o inativo. Voltar
  /// ao padrão (só ativos) esconderia de novo o que a pessoa queria ver.
  static const semFiltro = FiltroCatalogo(soAtivos: false);

  final String busca;
  final String? metodoId;
  final String? categoria;
  final bool soAtivos;

  /// O checkbox "só abaixo do mínimo" do wireframe §9 (card 6.7). Mora aqui, e
  /// não num filtro próprio do estoque, porque a barra de filtros da tela 6 é
  /// **uma** (design-system §5: componente não se duplica); as abas Cursos e
  /// Combos simplesmente não o exibem. Desligado por padrão: a tela abre
  /// mostrando o catálogo inteiro.
  final bool soAbaixoMinimo;

  /// Quantos filtros a pessoa ligou — é o `(n)` do botão "Filtrar" no mobile.
  int get ativos =>
      (busca.trim().isNotEmpty ? 1 : 0) +
      (metodoId != null ? 1 : 0) +
      (categoria != null ? 1 : 0) +
      (soAtivos ? 1 : 0) +
      (soAbaixoMinimo ? 1 : 0);

  FiltroCatalogo copiar({
    String? busca,
    String? Function()? metodoId,
    String? Function()? categoria,
    bool? soAtivos,
    bool? soAbaixoMinimo,
  }) => FiltroCatalogo(
    busca: busca ?? this.busca,
    metodoId: metodoId == null ? this.metodoId : metodoId(),
    categoria: categoria == null ? this.categoria : categoria(),
    soAtivos: soAtivos ?? this.soAtivos,
    soAbaixoMinimo: soAbaixoMinimo ?? this.soAbaixoMinimo,
  );
}

bool _casaBusca(String busca, Iterable<String> campos) {
  final termo = busca.trim().toLowerCase();
  if (termo.isEmpty) return true;
  return campos.any((c) => c.toLowerCase().contains(termo));
}

List<MaterialDidatico> filtrarMateriais(
  List<MaterialDidatico> todos,
  FiltroCatalogo filtro,
) => [
  for (final m in todos)
    if ((!filtro.soAtivos || m.ativo) &&
        (filtro.metodoId == null || m.metodoId == filtro.metodoId) &&
        (filtro.categoria == null || m.categoria == filtro.categoria) &&
        _casaBusca(filtro.busca, [m.codigo, m.nome]))
      m,
];

List<Curso> filtrarCursos(List<Curso> todos, FiltroCatalogo filtro) => [
  for (final c in todos)
    if ((!filtro.soAtivos || c.ativo) &&
        (filtro.metodoId == null || c.metodoId == filtro.metodoId) &&
        _casaBusca(filtro.busca, [c.nome]))
      c,
];

List<Combo> filtrarCombos(List<Combo> todos, FiltroCatalogo filtro) => [
  for (final c in todos)
    if ((!filtro.soAtivos || c.ativo) &&
        (filtro.metodoId == null || c.metodoId == filtro.metodoId) &&
        _casaBusca(filtro.busca, [c.nome]))
      c,
];

/// As categorias em uso, para o filtro e para a sugestão do formulário — não
/// há lista fechada no schema (`material.categoria` é texto livre, card 4.1).
List<String> categoriasDe(Iterable<MaterialDidatico> materiais) =>
    ({for (final m in materiais) m.categoria}.toList()..sort());

// ---------------------------------------------------------------------------
// Sequência ordenada — o plano de gravação
// ---------------------------------------------------------------------------

/// O que gravar para que a sequência de um pai passe a ser exatamente
/// [desejados], nessa ordem.
///
/// Três listas porque são três requisições ao PostgREST, e a ordem entre elas
/// importa: primeiro **apagar** o que saiu (libera o par único pai+filho e as
/// posições), depois **atualizar** as linhas que ficaram com as posições novas,
/// e por fim **inserir** as novas. As duas últimas não podem ir numa só: o
/// PostgREST exige que todos os objetos de um lote tenham as mesmas chaves, e
/// linha nova não tem `id`.
///
/// A troca de posições entre linhas existentes vai num único `upsert` — é
/// exatamente o caso que o `deferrable initially deferred` das constraints de
/// ordem (card 2.1 (e), asserido no card 4.1) existe para permitir: dentro de
/// um comando as posições colidem; no fim dele, não.
@immutable
class PlanoSequencia {
  const PlanoSequencia({
    required this.apagar,
    required this.atualizar,
    required this.inserir,
  });

  /// Ids de linha (`curso_material.id` / `combo_curso.id`) a apagar.
  final List<String> apagar;

  /// Linhas existentes com a posição nova — sempre com `id`.
  final List<Map<String, dynamic>> atualizar;

  /// Linhas novas — nunca com `id`.
  final List<Map<String, dynamic>> inserir;

  bool get vazio => apagar.isEmpty && atualizar.isEmpty && inserir.isEmpty;
}

PlanoSequencia planejarSequencia({
  required List<LinhaOrdenada> atuais,
  required List<String> desejados,
  required String unidadeId,
  required String colunaPai,
  required String paiId,
  required String colunaFilho,
}) {
  assert(
    desejados.toSet().length == desejados.length,
    'um filho não pode aparecer duas vezes na sequência',
  );
  final porFilho = {for (final l in atuais) l.filhoId: l};

  final apagar = [
    for (final l in atuais)
      if (!desejados.contains(l.filhoId)) l.id,
  ];
  final atualizar = <Map<String, dynamic>>[];
  final inserir = <Map<String, dynamic>>[];

  for (var i = 0; i < desejados.length; i++) {
    final filhoId = desejados[i];
    final ordem = i + 1;
    final existente = porFilho[filhoId];
    if (existente == null) {
      inserir.add({
        'unidade_id': unidadeId,
        colunaPai: paiId,
        colunaFilho: filhoId,
        'ordem': ordem,
      });
    } else if (existente.ordem != ordem) {
      atualizar.add({
        'id': existente.id,
        'unidade_id': unidadeId,
        colunaPai: paiId,
        colunaFilho: filhoId,
        'ordem': ordem,
      });
    }
  }

  return PlanoSequencia(apagar: apagar, atualizar: atualizar, inserir: inserir);
}
