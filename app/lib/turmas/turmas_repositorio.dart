import 'package:supabase_flutter/supabase_flutter.dart';

import '../erros/erro_app.dart';
import 'turmas.dart';

/// Acesso às turmas (card 5.6). Interface para o teste injetar **dados**, nunca
/// um cliente HTTP falso (card 2.8 §9.3).
///
/// A grade vem da **função** `fn_grade_semana`, e não da view
/// `v_bloco_vagas_semana`: a tela navega semanas, e a view é a semana corrente
/// (card 2.3 §7). A view continua existindo — é o contrato do dashboard do card
/// 5.9 — e o teste 095 assere que as duas devolvem as mesmas linhas na semana
/// corrente, o que é o que impede uma de divergir da outra.
///
/// O cadastro do bloco vai direto na tabela `bloco_horario` pelo PostgREST: não
/// há função de aplicação para ele (card 2.2 não especifica nenhuma), e quem
/// decide o que cada perfil pode é a RLS.
abstract interface class TurmasRepositorio {
  /// A grade da semana que contém [segunda]. A normalização é do banco — a
  /// função responde pela semana de qualquer data que receba.
  Future<List<CelulaGrade>> grade(DateTime segunda);

  /// Os blocos desativados. Não estão na grade (ela é das vagas, e bloco
  /// inativo não tem vaga a oferecer), e sem esta lista desativar seria porta
  /// de mão única.
  Future<List<BlocoHorario>> blocosInativos();

  Future<BlocoHorario> salvarBloco(BlocoHorario bloco);

  /// Só bloco sem histórico é apagável — quem recusa é
  /// `tg_bloco_exclusao_valida` (PT409 / `BLOCO_COM_ALOCACAO`, card 5.1).
  Future<void> excluirBloco(String id);
}

class TurmasRepositorioSupabase implements TurmasRepositorio {
  TurmasRepositorioSupabase(this._cliente, {required this.unidadeId});

  final SupabaseClient _cliente;

  /// A unidade do usuário — toda escrita a carrega (card 2.1).
  final String unidadeId;

  static const _colunasBloco =
      'id, dia_semana, hora_inicio, metodo_id, sala_id, professor_id, '
      'capacidade_override, ativo';

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
  Future<List<BlocoHorario>> blocosInativos() async {
    final linhas = await _cliente
        .from('bloco_horario')
        .select(_colunasBloco)
        .eq('ativo', false)
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
}
