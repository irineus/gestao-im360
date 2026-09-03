import 'package:supabase_flutter/supabase_flutter.dart';

import 'alunos.dart';

/// Acesso aos alunos (card 4.6). Interface para o teste injetar **dados**,
/// nunca um cliente HTTP falso (card 2.8 §9.3).
///
/// Lê e escreve **nas tabelas** do card 4.2, pelo PostgREST; o status passa
/// só pelas duas funções de aplicação (`fn_aluno_alterar_status` /
/// `fn_aluno_reverter_status`), porque é lá que o motivo vira histórico. Quem
/// decide o que cada perfil pode é a RLS e o trigger — a tela só não oferece
/// o que vai falhar (docs/wireframes.md §2.2).
abstract interface class AlunosRepositorio {
  Future<List<Aluno>> alunos();

  /// Nulo quando não existe — ou quando a RLS não deixa ver, que para o app
  /// é a mesma coisa (`ALUNO_INEXISTENTE` vale para aluno de outra unidade).
  Future<Aluno?> aluno(String id);

  /// Insere (sem `id`) ou atualiza os dados cadastrais. Nunca toca o status.
  Future<Aluno> salvarAluno(Aluno aluno);

  /// `aluno_status_hist` do aluno, da mais recente para a mais antiga.
  Future<List<TransicaoStatus>> historico(String alunoId);

  Future<void> alterarStatus(
    String alunoId, {
    required String status,
    String? motivo,
  });

  Future<void> reverterStatus(
    String alunoId, {
    required String destino,
    required String motivo,
  });
}

class AlunosRepositorioSupabase implements AlunosRepositorio {
  AlunosRepositorioSupabase(this._cliente, {required this.unidadeId});

  final SupabaseClient _cliente;

  /// A unidade do usuário — toda escrita a carrega (card 2.1).
  final String unidadeId;

  static const _colunas =
      'id, codigo_sgf, nome, metodo_id, combo_id, status, status_desde, '
      'prev_conclusao_curso, data_inicio, observacoes, conferido';

  /// `usuario:usuario_id(nome)` é um embed do PostgREST pela FK; quando a
  /// política de `usuario` não deixa ler a linha, vem nulo — não erro.
  static const _colunasHistorico =
      'id, status_anterior, status_novo, ocorrido_em, motivo, '
      'usuario:usuario_id(nome)';

  @override
  Future<List<Aluno>> alunos() async {
    final linhas = await _cliente
        .from('aluno')
        .select(_colunas)
        .order('nome', ascending: true);
    return linhas.map(Aluno.deLinha).toList();
  }

  @override
  Future<Aluno?> aluno(String id) async {
    final linha = await _cliente
        .from('aluno')
        .select(_colunas)
        .eq('id', id)
        .maybeSingle();
    return linha == null ? null : Aluno.deLinha(linha);
  }

  @override
  Future<Aluno> salvarAluno(Aluno aluno) async {
    final linha = aluno.paraLinha(unidadeId);
    final id = aluno.id;
    // `.single()` de propósito: `update` sem política devolve zero linhas e
    // nenhum erro (card 3.4 (d)); com ele, zero linhas vira exceção.
    final gravada = id == null
        ? await _cliente.from('aluno').insert(linha).select(_colunas).single()
        : await _cliente
              .from('aluno')
              .update(linha)
              .eq('id', id)
              .select(_colunas)
              .single();
    return Aluno.deLinha(gravada);
  }

  @override
  Future<List<TransicaoStatus>> historico(String alunoId) async {
    final linhas = await _cliente
        .from('aluno_status_hist')
        .select(_colunasHistorico)
        .eq('aluno_id', alunoId)
        .order('ocorrido_em', ascending: false);
    return linhas.map(TransicaoStatus.deLinha).toList();
  }

  @override
  Future<void> alterarStatus(
    String alunoId, {
    required String status,
    String? motivo,
  }) => _cliente.rpc<dynamic>(
    'fn_aluno_alterar_status',
    params: {'p_aluno_id': alunoId, 'p_status': status, 'p_motivo': motivo},
  );

  @override
  Future<void> reverterStatus(
    String alunoId, {
    required String destino,
    required String motivo,
  }) => _cliente.rpc<dynamic>(
    'fn_aluno_reverter_status',
    params: {
      'p_aluno_id': alunoId,
      'p_status_destino': destino,
      'p_motivo': motivo,
    },
  );
}
