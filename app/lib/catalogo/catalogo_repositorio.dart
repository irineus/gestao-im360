import 'package:supabase_flutter/supabase_flutter.dart';

import '../erros/erro_app.dart';
import 'catalogo.dart';

/// Acesso ao catálogo curricular. Interface para o teste injetar **dados**,
/// nunca um cliente HTTP falso (card 2.8 §9.3).
///
/// Lê e escreve **nas tabelas**, pelo PostgREST: o catálogo não tem view (as
/// views do card 2.3 são de estoque, demanda e vagas), e escrita nunca passa
/// por view. Quem decide o que cada perfil pode é a RLS do card 4.1 — a tela
/// só não oferece o que vai falhar (docs/wireframes.md §2.2).
abstract interface class CatalogoRepositorio {
  Future<List<Metodo>> metodos();
  Future<void> salvarMetodo(Metodo metodo);

  Future<List<MaterialDidatico>> materiais();
  Future<MaterialDidatico> salvarMaterial(MaterialDidatico material);
  Future<void> excluirMaterial(String id);

  Future<List<Curso>> cursos();
  Future<Curso> salvarCurso(Curso curso);
  Future<void> excluirCurso(String id);

  /// Quantas apostilas cada curso tem na sequência (`curso_id` → n).
  Future<Map<String, int>> apostilasPorCurso();
  Future<List<LinhaOrdenada>> sequenciaDoCurso(String cursoId);
  Future<void> salvarSequenciaDoCurso(String cursoId, List<String> materialIds);

  Future<List<Modulo>> modulos(String cursoId);
  Future<Modulo> salvarModulo(Modulo modulo);
  Future<void> excluirModulo(String id);
  Future<void> reordenarModulos(String cursoId, List<String> moduloIds);

  Future<List<Combo>> combos();
  Future<Combo> salvarCombo(Combo combo);
  Future<void> excluirCombo(String id);

  /// Quantos cursos cada combo tem (`combo_id` → n).
  Future<Map<String, int>> cursosPorCombo();
  Future<List<LinhaOrdenada>> cursosDoCombo(String comboId);
  Future<void> salvarCursosDoCombo(String comboId, List<String> cursoIds);
}

/// Mensagem do caso em que a RLS devolve **zero linhas** numa exclusão. Sem
/// política de `delete` o Postgres não levanta erro — apaga nada e diz sucesso
/// (card 3.4 (d)); dizer "excluído" aqui seria mentir com cara de confirmação.
const mensagemNadaExcluido =
    'Nada foi excluído: o registro não existe mais ou você não tem permissão '
    'para excluí-lo.';

class CatalogoRepositorioSupabase implements CatalogoRepositorio {
  CatalogoRepositorioSupabase(this._cliente, {required this.unidadeId});

  final SupabaseClient _cliente;

  /// A unidade do usuário. Toda escrita a carrega porque a política de
  /// `insert` exige `unidade_id = fn_unidade_atual()` e a coluna não tem
  /// default (card 2.1).
  final String unidadeId;

  static const _colunasMetodo = 'id, codigo, nome, ativo';
  static const _colunasMaterial =
      'id, metodo_id, codigo, nome, categoria, estoque_minimo, ativo';
  static const _colunasCurso = 'id, metodo_id, nome, ativo';
  static const _colunasModulo = 'id, curso_id, material_id, nome, ordem';

  // --- métodos ------------------------------------------------------------

  @override
  Future<List<Metodo>> metodos() async {
    final linhas = await _cliente
        .from('metodo')
        .select(_colunasMetodo)
        .order('codigo', ascending: true);
    return linhas.map(Metodo.deLinha).toList();
  }

  @override
  Future<void> salvarMetodo(Metodo metodo) =>
      _atualizar('metodo', metodo.id, metodo.paraLinha(), _colunasMetodo);

  // --- materiais ------------------------------------------------------------

  @override
  Future<List<MaterialDidatico>> materiais() async {
    final linhas = await _cliente
        .from('material')
        .select(_colunasMaterial)
        .order('codigo', ascending: true);
    return linhas.map(MaterialDidatico.deLinha).toList();
  }

  @override
  Future<MaterialDidatico> salvarMaterial(MaterialDidatico material) async {
    final linha = material.paraLinha(unidadeId);
    final id = material.id;
    final gravada = id == null
        ? await _inserir('material', linha, _colunasMaterial)
        : await _atualizar('material', id, linha, _colunasMaterial);
    return MaterialDidatico.deLinha(gravada);
  }

  @override
  Future<void> excluirMaterial(String id) => _excluir('material', id);

  // --- cursos ---------------------------------------------------------------

  @override
  Future<List<Curso>> cursos() async {
    final linhas = await _cliente
        .from('curso')
        .select(_colunasCurso)
        .order('nome', ascending: true);
    return linhas.map(Curso.deLinha).toList();
  }

  @override
  Future<Curso> salvarCurso(Curso curso) async {
    final linha = curso.paraLinha(unidadeId);
    final id = curso.id;
    final gravada = id == null
        ? await _inserir('curso', linha, _colunasCurso)
        : await _atualizar('curso', id, linha, _colunasCurso);
    return Curso.deLinha(gravada);
  }

  @override
  Future<void> excluirCurso(String id) => _excluir('curso', id);

  @override
  Future<Map<String, int>> apostilasPorCurso() =>
      _contarPor('curso_material', 'curso_id');

  @override
  Future<List<LinhaOrdenada>> sequenciaDoCurso(String cursoId) =>
      _ordenadas('curso_material', 'curso_id', cursoId, 'material_id');

  @override
  Future<void> salvarSequenciaDoCurso(
    String cursoId,
    List<String> materialIds,
  ) async {
    final plano = planejarSequencia(
      atuais: await sequenciaDoCurso(cursoId),
      desejados: materialIds,
      unidadeId: unidadeId,
      colunaPai: 'curso_id',
      paiId: cursoId,
      colunaFilho: 'material_id',
    );
    await _aplicar('curso_material', plano);
  }

  // --- módulos --------------------------------------------------------------

  @override
  Future<List<Modulo>> modulos(String cursoId) async {
    final linhas = await _cliente
        .from('modulo')
        .select(_colunasModulo)
        .eq('curso_id', cursoId)
        .order('ordem', ascending: true);
    return linhas.map(Modulo.deLinha).toList();
  }

  @override
  Future<Modulo> salvarModulo(Modulo modulo) async {
    final linha = modulo.paraLinha(unidadeId);
    final id = modulo.id;
    final gravada = id == null
        ? await _inserir('modulo', linha, _colunasModulo)
        : await _atualizar('modulo', id, linha, _colunasModulo);
    return Modulo.deLinha(gravada);
  }

  @override
  Future<void> excluirModulo(String id) => _excluir('modulo', id);

  @override
  Future<void> reordenarModulos(String cursoId, List<String> moduloIds) async {
    final atuais = await modulos(cursoId);
    final porId = {for (final m in atuais) m.id!: m};
    final linhas = <Map<String, dynamic>>[];
    for (var i = 0; i < moduloIds.length; i++) {
      final modulo = porId[moduloIds[i]];
      if (modulo == null || modulo.ordem == i + 1) continue;
      linhas.add({
        'id': modulo.id,
        ...modulo.paraLinha(unidadeId),
        'ordem': i + 1,
      });
    }
    // Um único upsert: as posições colidem dentro do comando e o `deferrable`
    // de `modulo_ordem_uk` as resolve no fim dele (card 4.1).
    if (linhas.isNotEmpty) await _cliente.from('modulo').upsert(linhas);
  }

  // --- combos ---------------------------------------------------------------

  @override
  Future<List<Combo>> combos() async {
    final linhas = await _cliente
        .from('combo')
        .select(_colunasCurso)
        .order('nome', ascending: true);
    return linhas.map(Combo.deLinha).toList();
  }

  @override
  Future<Combo> salvarCombo(Combo combo) async {
    final linha = combo.paraLinha(unidadeId);
    final id = combo.id;
    final gravada = id == null
        ? await _inserir('combo', linha, _colunasCurso)
        : await _atualizar('combo', id, linha, _colunasCurso);
    return Combo.deLinha(gravada);
  }

  @override
  Future<void> excluirCombo(String id) => _excluir('combo', id);

  @override
  Future<Map<String, int>> cursosPorCombo() =>
      _contarPor('combo_curso', 'combo_id');

  @override
  Future<List<LinhaOrdenada>> cursosDoCombo(String comboId) =>
      _ordenadas('combo_curso', 'combo_id', comboId, 'curso_id');

  @override
  Future<void> salvarCursosDoCombo(
    String comboId,
    List<String> cursoIds,
  ) async {
    final plano = planejarSequencia(
      atuais: await cursosDoCombo(comboId),
      desejados: cursoIds,
      unidadeId: unidadeId,
      colunaPai: 'combo_id',
      paiId: comboId,
      colunaFilho: 'curso_id',
    );
    await _aplicar('combo_curso', plano);
  }

  // --- primitivas -----------------------------------------------------------

  Future<Map<String, dynamic>> _inserir(
    String tabela,
    Map<String, dynamic> linha,
    String colunas,
  ) => _cliente.from(tabela).insert(linha).select(colunas).single();

  /// `.single()` de propósito: `update` sem política devolve zero linhas e
  /// nenhum erro (card 3.4 (d)). Com o `single`, zero linhas vira exceção —
  /// a tela nunca mostra "salvo" para o que não foi salvo.
  Future<Map<String, dynamic>> _atualizar(
    String tabela,
    String id,
    Map<String, dynamic> linha,
    String colunas,
  ) =>
      _cliente.from(tabela).update(linha).eq('id', id).select(colunas).single();

  Future<void> _excluir(String tabela, String id) async {
    final apagadas = await _cliente
        .from(tabela)
        .delete()
        .eq('id', id)
        .select('id');
    if (apagadas.isEmpty) {
      throw const ErroApp(mensagem: mensagemNadaExcluido, traduzido: true);
    }
  }

  Future<Map<String, int>> _contarPor(String tabela, String coluna) async {
    final linhas = await _cliente.from(tabela).select(coluna);
    final contagem = <String, int>{};
    for (final linha in linhas) {
      final chave = '${linha[coluna]}';
      contagem[chave] = (contagem[chave] ?? 0) + 1;
    }
    return contagem;
  }

  Future<List<LinhaOrdenada>> _ordenadas(
    String tabela,
    String colunaPai,
    String paiId,
    String colunaFilho,
  ) async {
    final linhas = await _cliente
        .from(tabela)
        .select('id, $colunaFilho, ordem')
        .eq(colunaPai, paiId)
        .order('ordem', ascending: true);
    return [
      for (final l in linhas)
        LinhaOrdenada(
          id: '${l['id']}',
          filhoId: '${l[colunaFilho]}',
          ordem: (l['ordem'] as num).toInt(),
        ),
    ];
  }

  Future<void> _aplicar(String tabela, PlanoSequencia plano) async {
    if (plano.apagar.isNotEmpty) {
      await _cliente.from(tabela).delete().inFilter('id', plano.apagar);
    }
    if (plano.atualizar.isNotEmpty) {
      await _cliente.from(tabela).upsert(plano.atualizar);
    }
    if (plano.inserir.isNotEmpty) {
      await _cliente.from(tabela).insert(plano.inserir);
    }
  }
}
