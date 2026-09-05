import 'package:supabase_flutter/supabase_flutter.dart';

import '../util/datas.dart';
import 'projecao.dart';

/// Acesso à projeção de demanda (card 8.5). Interface para o teste injetar
/// **dados**, nunca um cliente HTTP falso (card 2.8 §9.3).
///
/// **Lê por view, e só lê** (card 2.3 §1): a tela 8 não escreve nada. Não
/// poderia: `demanda_projetada` tem política de `insert`/`delete` só para
/// `fn_contexto_rotina()` e **nenhuma** de `update` (card 8.1), então nem a
/// direção, com as 50 permissões, grava ali. Quem calcula é a rotina da
/// madrugada, e a tela mostra o que ela deixou com a data em que deixou.
abstract interface class ProjecaoRepositorio {
  /// `v_projecao_material_mes` — a grade, no grão material × mês × regra.
  /// O pivô é da tela.
  Future<List<CelulaProjecao>> grade();

  /// `v_projecao_aluno_detalhe` — quem soma numa célula, **ao vivo**.
  ///
  /// [mes] nulo = todos os meses daquele material dentro do que a view devolve.
  /// É o caminho do celular, onde a linha inteira é o alvo e não há célula de
  /// mês para tocar.
  Future<List<DetalheProjecao>> detalhe(String materialId, {DateTime? mes});

  /// Há pendência `ROTINA_FALHOU` aberta para a rotina da projeção?
  ///
  /// É o que separa os **dois** vazios do design-system §7.2 — "rodou e não
  /// previu nada" de "não rodou" —, e sem ele os dois seriam a mesma tabela
  /// vazia. Ver o comentário da implementação: a resposta degrada para `false`,
  /// de propósito.
  Future<bool> rotinaFalhou();
}

class ProjecaoRepositorioSupabase implements ProjecaoRepositorio {
  ProjecaoRepositorioSupabase(this._cliente);

  final SupabaseClient _cliente;

  static const _colunasGrade =
      'material_id, metodo_id, codigo, nome, categoria, mes, quantidade, '
      'regra, calculado_em';

  static const _colunasDetalhe =
      'aluno_id, aluno_nome, codigo_sgf, aluno_status, material_id, codigo, '
      'material_nome, mes, data_prevista, regra, ritmo_dias, k, pendentes';

  /// A chave de dedução da pendência que `rt_diaria` abre quando
  /// `rt_projecao_demanda` levanta exceção (card 8.1).
  static const _chaveRotinaProjecao = 'ROTINA_FALHOU:rt_projecao_demanda';

  @override
  Future<List<CelulaProjecao>> grade() async {
    final linhas = await _cliente
        .from('v_projecao_material_mes')
        .select(_colunasGrade)
        .order('codigo', ascending: true)
        .order('mes', ascending: true);
    return linhas.map(CelulaProjecao.deLinha).toList();
  }

  @override
  Future<List<DetalheProjecao>> detalhe(
    String materialId, {
    DateTime? mes,
  }) async {
    var consulta = _cliente
        .from('v_projecao_aluno_detalhe')
        .select(_colunasDetalhe)
        .eq('material_id', materialId);
    if (mes != null) {
      // O recorte é por `mes`, a coluna, e não por um intervalo de
      // `data_prevista` montado aqui: `mes` é a MESMA expressão que a rotina
      // usa no `group by`, e é ela que faz o detalhe fechar com a célula.
      consulta = consulta.eq('mes', dataIso(mes));
    }
    final linhas = await consulta.order('data_prevista', ascending: true);
    return linhas.map(DetalheProjecao.deLinha).toList();
  }

  /// ⚠️ **Degrada para `false` em erro e em lista vazia, de propósito.**
  /// `v_pendencias_abertas` exige `pendencias.ler`, que **não** está no conjunto
  /// da rota da tela 8 (docs/permissoes-matriz.md §6, linha 8) — e acrescentá-lo
  /// fecharia a tela inteira para quem só quer ver a projeção. Sem a permissão,
  /// a RLS reduz em silêncio (card 2.3 §3.4) e a tela cai no vazio neutro, que
  /// diz menos mas não diz nada falso. Os quatro perfis de hoje têm
  /// `pendencias.ler`, então na prática o aviso aparece para todos.
  @override
  Future<bool> rotinaFalhou() async {
    try {
      final linhas = await _cliente
          .from('v_pendencias_abertas')
          .select('pendencia_id')
          .eq('chave_dedup', _chaveRotinaProjecao)
          .limit(1);
      return linhas.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
