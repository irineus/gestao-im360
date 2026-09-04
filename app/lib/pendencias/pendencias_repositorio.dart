import 'package:supabase_flutter/supabase_flutter.dart';

import 'pendencias.dart';

/// Acesso à central de pendências (card 5.8). Interface para o teste injetar
/// **dados**, nunca um cliente HTTP falso (card 2.8 §9.3).
///
/// São duas operações e nada mais: **ler** `v_pendencias_abertas` e **fechar**
/// pela função de aplicação. A tela nunca escreve em `pendencia` pelo PostgREST
/// — `fn_pendencia_abrir`/`fn_pendencia_resolver` são o único caminho de escrita
/// (card 2.2 §10), e o fechamento humano é `fn_pendencia_resolver_id`, que é
/// `invoker` justamente para `pendencias.resolver` significar alguma coisa.
///
/// A **execução** da virada REP não mora aqui: `fn_rep_virar_continuo` e
/// `fn_rep_voltar_pontual` exigem `turmas.alocar` e delegam a
/// `fn_bloco_admitir`/`fn_bloco_remover` (card 5.3), então são do
/// `TurmasRepositorio` — a central orquestra as duas camadas, como o wireframe
/// §14.3 desenha.
abstract interface class PendenciasRepositorio {
  /// Todas as pendências **abertas** da unidade, já ordenadas por severidade e
  /// idade. A view não filtra por tipo nem por permissão de domínio: quem
  /// filtra é o usuário (card 5.5).
  Future<List<Pendencia>> abertas();

  /// `fn_pendencia_resolver_id` — exige `pendencias.resolver`.
  ///
  /// `IGNORADA` sem justificativa devolve `PT422 / MOTIVO_OBRIGATORIO`, e a
  /// tela **não** pré-valida isso: submete e trata o código (card 2.6 decisão
  /// 2). `PENDENCIA_JA_RESOLVIDA` é o caso normal de duas pessoas na mesma
  /// fila, e chega traduzido.
  Future<void> resolver(
    String pendenciaId, {
    required String resolucao,
    String? justificativa,
  });
}

class PendenciasRepositorioSupabase implements PendenciasRepositorio {
  PendenciasRepositorioSupabase(this._cliente);

  final SupabaseClient _cliente;

  static const _colunas =
      'pendencia_id, tipo, severidade, ordem_severidade, descricao, '
      'chave_dedup, criado_em, dias_aberta, '
      'aluno_id, aluno_nome, codigo_sgf, aluno_status, '
      'bloco_id, dia_semana, hora_inicio, bloco_sala_nome, '
      'material_id, material_codigo, material_nome, '
      'pc_id, pc_identificador';

  @override
  Future<List<Pendencia>> abertas() async {
    final linhas = await _cliente
        .from('v_pendencias_abertas')
        .select(_colunas)
        // Pela coluna NUMÉRICA: ordenar por `severidade` poria BAIXA antes de
        // ALTA, que é a razão de `ordem_severidade` existir (card 5.5).
        .order('ordem_severidade', ascending: true)
        .order('criado_em', ascending: true);
    return linhas.map(Pendencia.deLinha).toList();
  }

  @override
  Future<void> resolver(
    String pendenciaId, {
    required String resolucao,
    String? justificativa,
  }) => _cliente.rpc<dynamic>(
    'fn_pendencia_resolver_id',
    params: {
      'p_pendencia_id': pendenciaId,
      'p_resolucao': resolucao,
      'p_justificativa': justificativa,
    },
  );
}
