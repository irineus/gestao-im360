import 'package:supabase_flutter/supabase_flutter.dart';

import '../turmas/turmas.dart';

/// Acesso ao dashboard (card 5.9). Interface para o teste injetar **dados**,
/// nunca um cliente HTTP falso (card 2.8 §9.3).
///
/// Uma leitura só, e ela é a **view** `v_bloco_vagas_semana` — não a função
/// `fn_grade_semana` que a tela de Turmas usa (card 5.6). A diferença é a razão
/// de as duas existirem: a tela de Turmas navega semanas e por isso precisa do
/// parâmetro; o dashboard é o retrato de **hoje**, e a semana dele é a que o
/// banco fixa com `fn_hoje()` (docs/views-leitura.md §7).
///
/// ⚠️ Ler a função com a semana do `semanaProvider` seria pior do que parece:
/// aquele estado é o da tela de Turmas e sobrevive à navegação (card 5.6), então
/// o dashboard mostraria a semana em que alguém deixou a outra tela — com o
/// rótulo "semana corrente" em cima. O teste 095 assere que a view e a função
/// devolvem as mesmas linhas na semana corrente, e é isso que garante que as
/// duas telas nunca discordem sobre a mesma semana.
///
/// Nada se escreve aqui: dashboard é leitura.
abstract interface class DashboardRepositorio {
  /// As vagas da semana corrente, um registro por bloco ativo.
  Future<List<CelulaGrade>> vagasDaSemana();
}

class DashboardRepositorioSupabase implements DashboardRepositorio {
  DashboardRepositorioSupabase(this._cliente);

  final SupabaseClient _cliente;

  /// As mesmas colunas de `fn_grade_semana`, porque a view **é** a função na
  /// semana corrente — e por isso o modelo também é o mesmo (`CelulaGrade`).
  static const _colunas =
      'bloco_id, dia_semana, hora_inicio, data_referencia, metodo_id, '
      'metodo_codigo, sala_id, sala_nome, professor_id, professor_nome, '
      'capacidade_override, capacidade, ocupacao, vagas_livres, '
      'acima_capacidade';

  @override
  Future<List<CelulaGrade>> vagasDaSemana() async {
    final linhas = await _cliente
        .from('v_bloco_vagas_semana')
        .select(_colunas)
        .order('dia_semana', ascending: true)
        .order('hora_inicio', ascending: true);
    return linhas.map(CelulaGrade.deLinha).toList();
  }
}
