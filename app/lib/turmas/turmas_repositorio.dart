import 'package:supabase_flutter/supabase_flutter.dart';

import '../erros/erro_app.dart';
import 'turmas.dart';

/// Acesso às turmas (cards 5.6 e 5.7). Interface para o teste injetar **dados**,
/// nunca um cliente HTTP falso (card 2.8 §9.3).
///
/// A grade vem da **função** `fn_grade_semana`, e não da view
/// `v_bloco_vagas_semana`: a tela navega semanas, e a view é a semana corrente
/// (card 2.3 §7). A view continua existindo — é o contrato do dashboard do card
/// 5.9 — e o teste 095 assere que as duas devolvem as mesmas linhas na semana
/// corrente, o que é o que impede uma de divergir da outra.
///
/// O cadastro do bloco vai direto na tabela `bloco_horario` pelo PostgREST: não
/// há função de aplicação para ele (card 2.2 não especifica nenhuma), e quem
/// decide o que cada perfil pode é a RLS. **A alocação é o oposto**: admitir,
/// remover, agendar, registrar e cancelar passam pelas funções do card 5.3, que
/// é onde vivem o advisory lock, a checagem de vaga e o veredito da virada REP.
/// A tela orquestra; nada disso se reescreve aqui.
abstract interface class TurmasRepositorio {
  /// A grade da semana que contém [segunda]. A normalização é do banco — a
  /// função responde pela semana de qualquer data que receba.
  Future<List<CelulaGrade>> grade(DateTime segunda);

  /// **Todos** os blocos, ativos e inativos. Os inativos não estão na grade
  /// (ela é das vagas, e bloco inativo não tem vaga a oferecer), e sem eles
  /// desativar seria porta de mão única; os ativos servem de dicionário para
  /// nomear o bloco de uma reposição na ficha do aluno.
  Future<List<BlocoHorario>> blocos();

  Future<BlocoHorario> salvarBloco(BlocoHorario bloco);

  /// Só bloco sem histórico é apagável — quem recusa é
  /// `tg_bloco_exclusao_valida` (PT409 / `BLOCO_COM_ALOCACAO`, card 5.1).
  Future<void> excluirBloco(String id);

  // --- card 5.7 ------------------------------------------------------------

  /// A lotação do bloco **naquela data**: alocações ativas mais as reposições
  /// PREVISTAS do dia (`fn_bloco_alunos`). A data importa porque a alocação
  /// vale toda semana e a reposição vale só no dia (card 2.1 §8).
  Future<List<AlunoDoBloco>> alunosDoBloco(String blocoId, DateTime data);

  /// Todas as alocações ativas da unidade, do lado do aluno (`v_bloco_alunos`).
  /// É o que a coluna Turmas da lista de alunos resume e o que o ⚠ de "sem
  /// turma" consulta.
  Future<List<TurmaDoAluno>> turmas();

  /// As reposições do aluno, da mais recente para a mais antiga — inclusive as
  /// já quitadas, porque é delas que o débito do card 2.5 se compõe.
  Future<List<ReposicaoAluno>> reposicoesDoAluno(String alunoId);

  /// `fn_rep_situacao` — os números do critério do card 2.5 §3 e o veredito.
  Future<SituacaoRep> situacaoRep(String alunoId);

  /// `fn_bloco_admitir`. Devolve o id da alocação; `BLOCO_LOTADO`,
  /// `METODO_INCOMPATIVEL` e `ALUNO_INATIVO` vêm do trigger, já traduzidos.
  Future<String> admitir({
    required String blocoId,
    required String alunoId,
    required String tipo,
    DateTime? dataInicioPrevista,
  });

  /// `fn_bloco_remover` — desativa a alocação e grava o motivo.
  Future<void> remover({
    required String blocoId,
    required String alunoId,
    String? motivo,
  });

  /// `fn_reposicao_agendar`. Data no passado exige
  /// `turmas.lancar_reposicao_retroativa`, e quem cobra é o trigger.
  Future<String> agendarReposicao({
    required String blocoId,
    required String alunoId,
    required DateTime data,
    String? blocoOrigemId,
    DateTime? dataOrigem,
    String? observacao,
  });

  /// `fn_reposicao_registrar` — PREVISTA → REALIZADA ou FALTOU. Devolve o
  /// **veredito** da virada REP, que a tela mostra na hora (ajuste 7 do card
  /// 2.2 §14).
  Future<String> registrarReposicao(String reposicaoId, {required bool veio});

  /// `fn_reposicao_cancelar` — PREVISTA → CANCELADA. A aula perdida continua em
  /// aberto: desmarcar a reposição não repõe a aula (card 2.5 §3.2).
  Future<void> cancelarReposicao(String reposicaoId, String observacao);

  // --- card 5.8: a EXECUÇÃO da virada REP ----------------------------------
  // As duas moram aqui, e não no repositório de pendências, porque exigem
  // `turmas.alocar` e delegam vaga e método a fn_bloco_admitir/fn_bloco_remover
  // (card 5.3). Quem as chama é a central de pendências, que é onde a decisão
  // acontece — a virada é SUGERIDA, nunca automática (card 2.5).

  /// `fn_rep_virar_continuo` — cancela as reposições PREVISTA do aluno, cria (ou
  /// reativa) a alocação de tipo `REP` no bloco escolhido e **fecha** a pendência
  /// `REP:<aluno>:CONTINUO` na mesma transação. Devolve o id da alocação.
  ///
  /// `BLOCO_LOTADO` e `METODO_INCOMPATIVEL` vêm do trigger de admissão, com o
  /// advisory lock, e `REP_JA_CONTINUO` da própria função — todos traduzidos.
  Future<String> virarContinuo({
    required String alunoId,
    required String blocoId,
    String? observacao,
  });

  /// `fn_rep_voltar_pontual` — desativa a alocação `REP` gravando o motivo e
  /// fecha a pendência `REP:<aluno>:VOLTA`. Motivo é obrigatório
  /// (`MOTIVO_OBRIGATORIO`), e quem cobra é a função.
  Future<void> voltarPontual({required String alunoId, required String motivo});
}

class TurmasRepositorioSupabase implements TurmasRepositorio {
  TurmasRepositorioSupabase(this._cliente, {required this.unidadeId});

  final SupabaseClient _cliente;

  /// A unidade do usuário — toda escrita a carrega (card 2.1).
  final String unidadeId;

  static const _colunasBloco =
      'id, dia_semana, hora_inicio, metodo_id, sala_id, professor_id, '
      'capacidade_override, ativo';

  static const _colunasTurma =
      'alocacao_id, bloco_id, aluno_id, dia_semana, hora_inicio, metodo_id, '
      'sala_id, bloco_ativo, tipo, tipo_desde, data_inicio_prevista';

  static const _colunasReposicao =
      'id, bloco_id, aluno_id, data, status, bloco_origem_id, data_origem, '
      'observacao';

  @override
  Future<List<CelulaGrade>> grade(DateTime segunda) async {
    final linhas = await _cliente.rpc<dynamic>(
      'fn_grade_semana',
      params: {'p_segunda': dataIso(segundaDe(segunda))},
    );
    return [
      for (final linha in (linhas as List<dynamic>? ?? const []))
        CelulaGrade.deLinha(linha as Map<String, dynamic>),
    ];
  }

  @override
  Future<List<BlocoHorario>> blocos() async {
    final linhas = await _cliente
        .from('bloco_horario')
        .select(_colunasBloco)
        .order('dia_semana', ascending: true)
        .order('hora_inicio', ascending: true);
    return linhas.map(BlocoHorario.deLinha).toList();
  }

  @override
  Future<BlocoHorario> salvarBloco(BlocoHorario bloco) async {
    final linha = bloco.paraLinha(unidadeId);
    final id = bloco.id;
    final gravada = id == null
        ? await _cliente
              .from('bloco_horario')
              .insert(linha)
              .select(_colunasBloco)
              .single()
        // `.single()` de propósito: `update` sem política devolve zero linhas e
        // nenhum erro (card 3.4 (d)); com ele, zero linhas vira exceção.
        : await _cliente
              .from('bloco_horario')
              .update(linha)
              .eq('id', id)
              .select(_colunasBloco)
              .single();
    return BlocoHorario.deLinha(gravada);
  }

  @override
  Future<void> excluirBloco(String id) async {
    final apagadas = await _cliente
        .from('bloco_horario')
        .delete()
        .eq('id', id)
        .select('id');
    if (apagadas.isEmpty) {
      throw const ErroApp(mensagem: mensagemNadaExcluido, traduzido: true);
    }
  }

  @override
  Future<List<AlunoDoBloco>> alunosDoBloco(
    String blocoId,
    DateTime data,
  ) async {
    final linhas = await _cliente.rpc<dynamic>(
      'fn_bloco_alunos',
      params: {'p_bloco_id': blocoId, 'p_data': dataIso(data)},
    );
    return [
      for (final linha in (linhas as List<dynamic>? ?? const []))
        AlunoDoBloco.deLinha(linha as Map<String, dynamic>),
    ];
  }

  @override
  Future<List<TurmaDoAluno>> turmas() async {
    final linhas = await _cliente
        .from('v_bloco_alunos')
        .select(_colunasTurma)
        .order('dia_semana', ascending: true)
        .order('hora_inicio', ascending: true);
    return linhas.map(TurmaDoAluno.deLinha).toList();
  }

  @override
  Future<List<ReposicaoAluno>> reposicoesDoAluno(String alunoId) async {
    final linhas = await _cliente
        .from('bloco_aluno_reposicao')
        .select(_colunasReposicao)
        .eq('aluno_id', alunoId)
        .order('data', ascending: false);
    return linhas.map(ReposicaoAluno.deLinha).toList();
  }

  @override
  Future<SituacaoRep> situacaoRep(String alunoId) async {
    final linha = await _cliente.rpc<dynamic>(
      'fn_rep_situacao',
      params: {'p_aluno_id': alunoId},
    );
    return SituacaoRep.deLinha(linha as Map<String, dynamic>);
  }

  @override
  Future<String> admitir({
    required String blocoId,
    required String alunoId,
    required String tipo,
    DateTime? dataInicioPrevista,
  }) async {
    final id = await _cliente.rpc<dynamic>(
      'fn_bloco_admitir',
      params: {
        'p_bloco_id': blocoId,
        'p_aluno_id': alunoId,
        'p_tipo': tipo,
        'p_data_inicio_prevista': dataInicioPrevista == null
            ? null
            : dataIso(dataInicioPrevista),
      },
    );
    return '$id';
  }

  @override
  Future<void> remover({
    required String blocoId,
    required String alunoId,
    String? motivo,
  }) => _cliente.rpc<dynamic>(
    'fn_bloco_remover',
    params: {'p_bloco_id': blocoId, 'p_aluno_id': alunoId, 'p_motivo': motivo},
  );

  @override
  Future<String> agendarReposicao({
    required String blocoId,
    required String alunoId,
    required DateTime data,
    String? blocoOrigemId,
    DateTime? dataOrigem,
    String? observacao,
  }) async {
    final id = await _cliente.rpc<dynamic>(
      'fn_reposicao_agendar',
      params: {
        'p_aluno_id': alunoId,
        'p_bloco_id': blocoId,
        'p_data': dataIso(data),
        'p_bloco_origem_id': blocoOrigemId,
        'p_data_origem': dataOrigem == null ? null : dataIso(dataOrigem),
        'p_observacao': observacao,
      },
    );
    return '$id';
  }

  @override
  Future<String> registrarReposicao(
    String reposicaoId, {
    required bool veio,
  }) async {
    final veredito = await _cliente.rpc<dynamic>(
      'fn_reposicao_registrar',
      params: {'p_reposicao_id': reposicaoId, 'p_compareceu': veio},
    );
    return '$veredito';
  }

  @override
  Future<void> cancelarReposicao(String reposicaoId, String observacao) =>
      _cliente.rpc<dynamic>(
        'fn_reposicao_cancelar',
        params: {'p_reposicao_id': reposicaoId, 'p_observacao': observacao},
      );

  @override
  Future<String> virarContinuo({
    required String alunoId,
    required String blocoId,
    String? observacao,
  }) async {
    final id = await _cliente.rpc<dynamic>(
      'fn_rep_virar_continuo',
      params: {
        'p_aluno_id': alunoId,
        'p_bloco_id': blocoId,
        'p_observacao': observacao,
      },
    );
    return '$id';
  }

  @override
  Future<void> voltarPontual({
    required String alunoId,
    required String motivo,
  }) => _cliente.rpc<dynamic>(
    'fn_rep_voltar_pontual',
    params: {'p_aluno_id': alunoId, 'p_motivo': motivo},
  );
}
