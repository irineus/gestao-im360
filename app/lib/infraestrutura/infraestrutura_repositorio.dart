import 'package:supabase_flutter/supabase_flutter.dart';

import '../erros/erro_app.dart';
import 'infraestrutura.dart';

/// Acesso à infraestrutura física (card 4.5). Interface para o teste injetar
/// **dados**, nunca um cliente HTTP falso (card 2.8 §9.3).
///
/// Lê e escreve **nas tabelas** do card 4.3, pelo PostgREST; a credencial do
/// PC passa só pelas duas funções do card 2.9 (`fn_pc_credencial_ler` /
/// `fn_pc_credencial_gravar`), porque nenhuma tabela a devolve em claro. Quem
/// decide o que cada perfil pode é a RLS — a tela só não oferece o que vai
/// falhar (docs/wireframes.md §2.2).
abstract interface class InfraestruturaRepositorio {
  Future<List<Sala>> salas();
  Future<Sala> salvarSala(Sala sala);
  Future<void> excluirSala(String id);

  /// Todos os PCs da unidade — a tela agrupa por sala.
  Future<List<Pc>> pcs();
  Future<Pc> salvarPc(Pc pc);
  Future<void> excluirPc(String id);

  /// Todas as manutenções da unidade; a tela deriva a aberta de cada PC.
  Future<List<PcManutencao>> manutencoes();

  /// Insere (sem `id`) ou atualiza — encerrar é atualizar `data_fim`. Não há
  /// exclusão: manutenção registrada é histórico (card 4.3 (a)).
  Future<PcManutencao> salvarManutencao(PcManutencao manutencao);

  Future<List<Professor>> professores();

  /// Professor não se exclui, inativa-se (card 2.4 §3.3).
  Future<Professor> salvarProfessor(Professor professor);

  /// Devolve o par, ou nulo sem credencial. **Cada chamada grava uma linha de
  /// acesso** no banco antes de devolver — chamar só quando a pessoa pediu.
  Future<CredencialPc?> lerCredencial(String pcId);

  Future<void> gravarCredencial(
    String pcId, {
    required String usuario,
    required String senha,
  });
}

class InfraestruturaRepositorioSupabase implements InfraestruturaRepositorio {
  InfraestruturaRepositorioSupabase(this._cliente, {required this.unidadeId});

  final SupabaseClient _cliente;

  /// A unidade do usuário — toda escrita a carrega (card 2.1).
  final String unidadeId;

  static const _colunasSala = 'id, nome, tipo, capacidade_nominal, ativo';
  static const _colunasPc =
      'id, sala_id, identificador, status, observacao, credencial_em';
  static const _colunasManutencao =
      'id, pc_id, tipo, data_inicio, data_fim, descricao, pc_substituto_id';
  static const _colunasProfessor = 'id, nome, ativo';

  // --- salas ----------------------------------------------------------------

  @override
  Future<List<Sala>> salas() async {
    final linhas = await _cliente
        .from('sala')
        .select(_colunasSala)
        .order('nome', ascending: true);
    return linhas.map(Sala.deLinha).toList();
  }

  @override
  Future<Sala> salvarSala(Sala sala) async {
    final linha = sala.paraLinha(unidadeId);
    final id = sala.id;
    final gravada = id == null
        ? await _inserir('sala', linha, _colunasSala)
        : await _atualizar('sala', id, linha, _colunasSala);
    return Sala.deLinha(gravada);
  }

  @override
  Future<void> excluirSala(String id) => _excluir('sala', id);

  // --- PCs ------------------------------------------------------------------

  @override
  Future<List<Pc>> pcs() async {
    final linhas = await _cliente
        .from('pc')
        .select(_colunasPc)
        .order('identificador', ascending: true);
    return linhas.map(Pc.deLinha).toList();
  }

  @override
  Future<Pc> salvarPc(Pc pc) async {
    final linha = pc.paraLinha(unidadeId);
    final id = pc.id;
    final gravada = id == null
        ? await _inserir('pc', linha, _colunasPc)
        : await _atualizar('pc', id, linha, _colunasPc);
    return Pc.deLinha(gravada);
  }

  @override
  Future<void> excluirPc(String id) => _excluir('pc', id);

  // --- manutenções ----------------------------------------------------------

  @override
  Future<List<PcManutencao>> manutencoes() async {
    final linhas = await _cliente
        .from('pc_manutencao')
        .select(_colunasManutencao)
        .order('data_inicio', ascending: false);
    return linhas.map(PcManutencao.deLinha).toList();
  }

  @override
  Future<PcManutencao> salvarManutencao(PcManutencao manutencao) async {
    final linha = manutencao.paraLinha(unidadeId);
    final id = manutencao.id;
    final gravada = id == null
        ? await _inserir('pc_manutencao', linha, _colunasManutencao)
        : await _atualizar('pc_manutencao', id, linha, _colunasManutencao);
    return PcManutencao.deLinha(gravada);
  }

  // --- professores ----------------------------------------------------------

  @override
  Future<List<Professor>> professores() async {
    final linhas = await _cliente
        .from('professor')
        .select(_colunasProfessor)
        .order('nome', ascending: true);
    return linhas.map(Professor.deLinha).toList();
  }

  @override
  Future<Professor> salvarProfessor(Professor professor) async {
    final linha = professor.paraLinha(unidadeId);
    final id = professor.id;
    final gravada = id == null
        ? await _inserir('professor', linha, _colunasProfessor)
        : await _atualizar('professor', id, linha, _colunasProfessor);
    return Professor.deLinha(gravada);
  }

  // --- credencial (card 2.9) — só pelas funções, nunca pela tabela ----------

  @override
  Future<CredencialPc?> lerCredencial(String pcId) async {
    final resultado = await _cliente.rpc<dynamic>(
      'fn_pc_credencial_ler',
      params: {'p_pc_id': pcId},
    );
    if (resultado == null) return null;
    final mapa = resultado as Map<String, dynamic>;
    return CredencialPc(
      usuario: '${mapa['usuario']}',
      senha: '${mapa['senha']}',
    );
  }

  @override
  Future<void> gravarCredencial(
    String pcId, {
    required String usuario,
    required String senha,
  }) => _cliente.rpc<dynamic>(
    'fn_pc_credencial_gravar',
    params: {'p_pc_id': pcId, 'p_usuario': usuario, 'p_senha': senha},
  );

  // --- primitivas (as mesmas do catálogo, card 4.4) --------------------------

  Future<Map<String, dynamic>> _inserir(
    String tabela,
    Map<String, dynamic> linha,
    String colunas,
  ) => _cliente.from(tabela).insert(linha).select(colunas).single();

  /// `.single()` de propósito: `update` sem política devolve zero linhas e
  /// nenhum erro (card 3.4 (d)); com ele, zero linhas vira exceção.
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
}
