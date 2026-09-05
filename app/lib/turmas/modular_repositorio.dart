import 'package:supabase_flutter/supabase_flutter.dart';

import '../erros/erro_app.dart';
import 'modular.dart';

/// Acesso às turmas Modular (card 7.3). Interface para o teste injetar **dados**,
/// nunca um cliente HTTP falso (card 2.8 §9.3).
///
/// A divisão entre `from(...)` e `rpc(...)` não é estilo, é a matriz do card 2.4
/// §4 posta em código:
///
///   • **turma e cronograma são tabela**, com RLS por `turmas.criar` /
///     `turmas.editar` / `turmas.excluir`. O card 2.2 não especifica função de
///     aplicação para nenhum dos dois, e inventá-la seria regra nova num card de
///     tela. Quem recusa apagar turma com histórico é
///     `tg_turma_modular_exclusao_valida` (`TURMA_COM_ALUNO`, card 7.1);
///
///   • **alocação e avanço são FUNÇÃO**, e é onde vivem o `pg_advisory_xact_lock`
///     da capacidade, a reativação em vez de duplicata e o cálculo do passo do
///     cronograma (card 7.2). Nada disso se reescreve aqui: a tela orquestra.
abstract interface class ModularRepositorio {
  /// As turmas ATIVAS com lotação e módulo corrente (`v_turma_modular_lotacao`).
  Future<List<TurmaModular>> turmas();

  /// **Todas** as turmas, ativas e inativas — a view de lotação só traz ativas
  /// (`where t.ativo`), e sem esta leitura desativar seria porta de mão única:
  /// a turma sumiria da única tela que fala de turma Modular. Mesma decisão dos
  /// blocos inativos do card 5.6.
  Future<List<TurmaModular>> turmasInativas();

  /// Grava a turma. **[dataInicio] só é aceita na criação** e é obrigatória
  /// nela; na edição fica nula e a coluna **não é enviada**.
  ///
  /// ⚠️ Não é elegância: enquanto o `update` reenviava `data_inicio`, salvar a
  /// turma sem mudar nada reescrevia a data real de início para hoje — medido,
  /// "Eletricista 2025.2" foi de 2025-11-09 para 2026-09-05 num clique em
  /// Salvar. É dado que o importador do card 9.1 traz da planilha e que a
  /// projeção Modular (8.1) e a lotação leem (item A2).
  Future<String> salvarTurma({
    String? id,
    required String nome,
    required String cursoId,
    required String salaId,
    required int capacidade,
    DateTime? dataInicio,
    required bool ativo,
  });

  /// Só turma sem histórico de aluno é apagável — quem recusa é
  /// `tg_turma_modular_exclusao_valida` (PT409 / `TURMA_COM_ALUNO`, card 7.1).
  Future<void> excluirTurma(String id);

  /// O cronograma de **todas** as turmas (`v_turma_modular_cronograma`): a tela
  /// mostra a faixa de módulos dentro de cada cartão, e uma consulta por turma
  /// aberta faria a lista disparar N chamadas ao expandir.
  Future<List<ModuloDaTurma>> cronograma();

  /// Acrescenta módulos ao cronograma da turma, sem datas — é o "Montar
  /// cronograma" do wireframe §8. Grava direto em `turma_modular_modulo`, cujo
  /// `insert` exige `turmas.editar` (permissoes-matriz §4).
  Future<void> incluirModulos({
    required String turmaId,
    required List<String> moduloIds,
  });

  /// Edita as datas de uma linha do cronograma (wireframe §8: "cronograma de
  /// módulos com datas editáveis"). `update` por `turmas.editar`.
  ///
  /// ⚠️ Os dois campos são **nuláveis de propósito e enviados sempre**: limpar
  /// uma previsão é uma edição legítima ("ainda não sabemos"), e omitir a coluna
  /// faria o formulário nunca conseguir apagá-la.
  Future<void> salvarDatasModulo({
    required String cronogramaId,
    DateTime? dataInicio,
    DateTime? prevConclusao,
  });

  /// Remove uma linha do cronograma. `delete` por `turmas.excluir`.
  Future<void> excluirModulo(String cronogramaId);

  /// Os alunos das turmas (`v_turma_modular_aluno`), ativos e inativos.
  Future<List<AlunoDaTurmaModular>> alunos();

  /// `fn_turma_modular_admitir` — devolve o id da alocação. `TURMA_LOTADA`,
  /// `ALUNO_NAO_MODULAR`, `METODO_INCOMPATIVEL` e `ALUNO_INATIVO` vêm do
  /// trigger, já traduzidos pelo código.
  Future<String> admitir({required String turmaId, required String alunoId});

  /// `fn_turma_modular_remover` — saída é `ativo = false` com o motivo gravado;
  /// a tabela não tem política de `delete` (card 2.4 §4).
  Future<void> remover({
    required String turmaId,
    required String alunoId,
    String? motivo,
  });

  /// `fn_turma_modular_avancar` — a turma INTEIRA avança (card 2.2 §9).
  ///
  /// Devolve o `modulo_id` do novo corrente, ou **nulo** quando a turma
  /// terminou. `TURMA_SEM_CRONOGRAMA` e `TURMA_SEM_MODULO_CORRENTE` distinguem
  /// os dois sentidos do fim de linha.
  Future<String?> avancar({
    required String turmaId,
    required DateTime dataConclusao,
  });
}

class ModularRepositorioSupabase implements ModularRepositorio {
  ModularRepositorioSupabase(this._cliente, {required this.unidadeId});

  final SupabaseClient _cliente;

  /// A unidade do usuário — toda escrita a carrega (card 2.1).
  final String unidadeId;

  static const _colunasLotacao =
      'unidade_id, turma_id, turma_nome, curso_id, curso_nome, sala_id, '
      'sala_nome, capacidade, alocados, vagas_livres, modulo_corrente_id, '
      'modulo_corrente_nome, modulo_corrente_ordem, modulo_corrente_inicio, '
      'modulo_corrente_prev_conclusao, modulo_atrasado';

  static const _colunasCronograma =
      'cronograma_id, turma_id, modulo_id, modulo_nome, modulo_ordem, '
      'material_id, data_inicio, prev_conclusao, concluido, corrente, atrasado';

  static const _colunasAluno =
      'alocacao_id, turma_id, aluno_id, aluno_nome, codigo_sgf, aluno_status, '
      'metodo_id, data_entrada, ativo, motivo_saida';

  @override
  Future<List<TurmaModular>> turmas() async {
    final linhas = await _cliente
        .from('v_turma_modular_lotacao')
        .select(_colunasLotacao)
        .order('curso_nome', ascending: true)
        .order('turma_nome', ascending: true);
    return linhas.map(TurmaModular.deLinha).toList();
  }

  /// As inativas saem da **tabela**, e não da view: a view filtra `t.ativo`.
  /// Sem lotação nem módulo corrente — o que a lista de inativas precisa dizer é
  /// o nome, o curso e a capacidade, e juntar curso e sala aqui só acrescentaria
  /// dois modos de a lista vir vazia (views-leitura §3.4).
  @override
  Future<List<TurmaModular>> turmasInativas() async {
    final linhas = await _cliente
        .from('turma_modular')
        .select('id, nome, curso_id, sala_id, capacidade')
        .eq('ativo', false)
        .order('nome', ascending: true);
    return [
      for (final linha in linhas)
        TurmaModular(
          id: '${linha['id']}',
          nome: '${linha['nome']}',
          cursoId: '${linha['curso_id']}',
          cursoNome: '',
          salaId: '${linha['sala_id']}',
          salaNome: '',
          capacidade: (linha['capacidade'] as num?)?.toInt() ?? 0,
          alocados: 0,
          vagasLivres: 0,
        ),
    ];
  }

  @override
  Future<String> salvarTurma({
    String? id,
    required String nome,
    required String cursoId,
    required String salaId,
    required int capacidade,
    DateTime? dataInicio,
    required bool ativo,
  }) async {
    final linha = {
      'unidade_id': unidadeId,
      'nome': nome,
      'curso_id': cursoId,
      'sala_id': salaId,
      'capacidade': capacidade,
      'ativo': ativo,
      // A chave existe só quando há data — no `update` ela fica FORA do mapa,
      // e é isso que preserva o início real da turma (item A2).
      if (dataInicio != null) 'data_inicio': dataIso(dataInicio),
    };
    final gravada = id == null
        ? await _cliente
              .from('turma_modular')
              .insert(linha)
              .select('id')
              .single()
        // `.single()` de propósito: `update` sem política devolve zero linhas e
        // nenhum erro (card 3.4 (d)); com ele, zero linhas vira exceção.
        : await _cliente
              .from('turma_modular')
              .update(linha)
              .eq('id', id)
              .select('id')
              .single();
    return '${gravada['id']}';
  }

  @override
  Future<void> excluirTurma(String id) async {
    final apagadas = await _cliente
        .from('turma_modular')
        .delete()
        .eq('id', id)
        .select('id');
    if (apagadas.isEmpty) {
      throw const ErroApp(mensagem: mensagemNadaExcluido, traduzido: true);
    }
  }

  @override
  Future<List<ModuloDaTurma>> cronograma() async {
    final linhas = await _cliente
        .from('v_turma_modular_cronograma')
        .select(_colunasCronograma)
        .order('modulo_ordem', ascending: true);
    return linhas.map(ModuloDaTurma.deLinha).toList();
  }

  @override
  Future<void> incluirModulos({
    required String turmaId,
    required List<String> moduloIds,
  }) async {
    if (moduloIds.isEmpty) return;
    await _cliente.from('turma_modular_modulo').insert([
      for (final moduloId in moduloIds)
        {'unidade_id': unidadeId, 'turma_id': turmaId, 'modulo_id': moduloId},
    ]);
  }

  @override
  Future<void> salvarDatasModulo({
    required String cronogramaId,
    DateTime? dataInicio,
    DateTime? prevConclusao,
  }) async {
    // `.single()` de propósito, como em `salvarBloco` (card 5.6): `update` sem
    // política devolve zero linhas e **nenhum erro** (card 3.4 (d)), e o
    // formulário fecharia dizendo "salvo" sobre datas que não mudaram.
    await _cliente
        .from('turma_modular_modulo')
        .update({
          'data_inicio': dataInicio == null ? null : dataIso(dataInicio),
          'prev_conclusao': prevConclusao == null
              ? null
              : dataIso(prevConclusao),
        })
        .eq('id', cronogramaId)
        .select('id')
        .single();
  }

  @override
  Future<void> excluirModulo(String cronogramaId) async {
    final apagadas = await _cliente
        .from('turma_modular_modulo')
        .delete()
        .eq('id', cronogramaId)
        .select('id');
    if (apagadas.isEmpty) {
      throw const ErroApp(mensagem: mensagemNadaExcluido, traduzido: true);
    }
  }

  @override
  Future<List<AlunoDaTurmaModular>> alunos() async {
    final linhas = await _cliente
        .from('v_turma_modular_aluno')
        .select(_colunasAluno)
        .order('aluno_nome', ascending: true);
    return linhas.map(AlunoDaTurmaModular.deLinha).toList();
  }

  @override
  Future<String> admitir({
    required String turmaId,
    required String alunoId,
  }) async {
    final id = await _cliente.rpc<dynamic>(
      'fn_turma_modular_admitir',
      params: {'p_turma_id': turmaId, 'p_aluno_id': alunoId},
    );
    return '$id';
  }

  @override
  Future<void> remover({
    required String turmaId,
    required String alunoId,
    String? motivo,
  }) => _cliente.rpc<dynamic>(
    'fn_turma_modular_remover',
    params: {'p_turma_id': turmaId, 'p_aluno_id': alunoId, 'p_motivo': motivo},
  );

  @override
  Future<String?> avancar({
    required String turmaId,
    required DateTime dataConclusao,
  }) async {
    final proximo = await _cliente.rpc<dynamic>(
      'fn_turma_modular_avancar',
      params: {
        'p_turma_id': turmaId,
        'p_data_conclusao': dataIso(dataConclusao),
      },
    );
    // Nulo é o **fim do cronograma**, não falha: a turma terminou. Convertê-lo
    // em string daria `'null'`, e a tela abriria o diálogo de "próximo módulo"
    // com um id que não existe.
    return proximo == null ? null : '$proximo';
  }
}
