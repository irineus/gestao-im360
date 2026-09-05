import 'package:supabase_flutter/supabase_flutter.dart';

// `dashboard.dart` reexporta `CelulaGrade` e o resto do modelo de turmas.
import 'dashboard.dart';

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

  /// Os alunos contados por status e por método (card 8.7).
  Future<List<AlunosMetodo>> alunosPorMetodo();

  /// As alocações ativas por tipo e por método (card 8.7).
  Future<List<TiposBloco>> tiposPorBloco();

  /// As conclusões previstas, por método e por semestre (card 8.7).
  Future<List<ConclusaoSemestre>> conclusoesPrevistas();
}

class DashboardRepositorioSupabase implements DashboardRepositorio {
  DashboardRepositorioSupabase(this._cliente);

  final SupabaseClient _cliente;

  /// As colunas de `fn_grade_semana` **menos o professor**, porque o dashboard
  /// não o mostra.
  ///
  /// ⚠️ A ausência é decisão de 04/09/2026 (revisão da fase 05, decisão de
  /// Irineu). `professor_id`/`professor_nome` eram lidos à toa, e a
  /// `views-leitura.md` §11 chegava a declarar `professores.ler` para esta
  /// view — permissão que a rota do dashboard nunca exigiu. Das duas saídas —
  /// mostrar o professor e exigir a permissão, ou parar de lê-lo —, exigir
  /// tiraria o dashboard de quem não tem `professores.ler`, e o professor já
  /// aparece na tela de Turmas, cuja rota o exige. O modelo continua sendo o
  /// mesmo `CelulaGrade`; `professorNome` fica nulo, e nada nesta tela o lê.
  static const _colunas =
      'bloco_id, dia_semana, hora_inicio, data_referencia, metodo_id, '
      'metodo_codigo, sala_id, sala_nome, '
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

  /// ⚠️ **Três leituras e não uma**, e não há como ser diferente: são três
  /// views distintas, cada uma com o seu `group by`, e o PostgREST lê uma
  /// relação por requisição. O que **não** se faz é derivar uma da outra em
  /// Dart — os alunos por status e as alocações por tipo são perguntas
  /// diferentes sobre tabelas diferentes (card 2.3 §4.1).
  ///
  /// As três regiões falham de forma independente de propósito: a de vagas
  /// cair não pode levar embora os alunos por método, que é a regra do
  /// design-system §7.2 para o dashboard.
  @override
  Future<List<AlunosMetodo>> alunosPorMetodo() async {
    final linhas = await _cliente
        .from('v_dashboard_alunos_metodo')
        .select(
          'metodo_id, metodo_codigo, ativos, acelerar, standby, trancados, '
          'cancelados, formados, em_ultimo_livro, em_fim, sem_previsao',
        );
    return linhas.map(AlunosMetodo.deLinha).toList();
  }

  @override
  Future<List<TiposBloco>> tiposPorBloco() async {
    final linhas = await _cliente
        .from('v_dashboard_tipos_bloco')
        .select('metodo_id, metodo_codigo, rem, pre, rep, novo, alocacoes');
    return linhas.map(TiposBloco.deLinha).toList();
  }

  /// Ordenado no **banco**, por ano e semestre: é o eixo do tempo, e ordenar
  /// depois em Dart daria o mesmo resultado com uma segunda regra para manter.
  @override
  Future<List<ConclusaoSemestre>> conclusoesPrevistas() async {
    final linhas = await _cliente
        .from('v_dashboard_conclusoes_semestre')
        .select(
          'metodo_id, metodo_codigo, ano, semestre, qtd_alunos, qtd_vencidas',
        )
        .order('ano', ascending: true)
        .order('semestre', ascending: true);
    return linhas.map(ConclusaoSemestre.deLinha).toList();
  }
}
