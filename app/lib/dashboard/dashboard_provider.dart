import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../sessao/sessao_provider.dart';
import '../turmas/modular.dart';
import '../turmas/modular_provider.dart';
import 'dashboard.dart';
import 'dashboard_repositorio.dart';

/// Repositório do dashboard — sobrescrito nos widget tests com dados
/// (card 2.8 §9.3).
final dashboardRepositorioProvider = Provider<DashboardRepositorio>(
  (ref) => DashboardRepositorioSupabase(ref.watch(clienteSupabaseProvider)),
);

/// Traduz **uma vez**, no provider — cada rebuild não reenvia o mesmo erro ao
/// Sentry (card 3.12).
Future<T> _traduzindo<T>(Future<T> Function() acao) async {
  try {
    return await acao();
  } catch (erro) {
    throw traduzirErro(erro);
  }
}

/// As vagas da semana corrente.
///
/// Sem o guarda de permissão que os providers dos cards 5.7 e 5.8 carregam, e
/// de propósito: aqueles são observados **fora** da rota deles — o contador de
/// pendências mora no shell, a coluna Turmas mora na lista de alunos —, e ali
/// uma consulta que a RLS esvazia vira número errado com cara de certo. Este
/// provider só é lido pela tela do dashboard, cuja rota já exige o conjunto
/// inteiro que a view precisa (`turmas.ler`, `salas.ler` e `materiais.ler`,
/// docs/permissoes-matriz.md §6): quem chega até aqui lê a grade completa, e
/// quem não chega vê a tela "Sem acesso" dizendo o que falta.
final vagasSemanaProvider = FutureProvider<List<CelulaGrade>>(
  (ref) => _traduzindo(ref.watch(dashboardRepositorioProvider).vagasDaSemana),
);

/// Os totais por método, derivados da mesma consulta — o dashboard faz **uma**
/// leitura e a apresenta de duas formas.
final totaisPorMetodoProvider = Provider<List<TotalMetodo>>(
  (ref) => totaisPorMetodo(ref.watch(vagasSemanaProvider).value ?? const []),
);

/// O método cuja grade está aberta. Nulo = ainda não houve escolha, e aí vale o
/// primeiro (ver [metodoVisivelProvider]).
///
/// Estado no provider e não no widget porque a escolha precisa sobreviver ao
/// rebuild que a própria recarga da consulta provoca (design-system §5.3).
class MetodoDoDashboard extends Notifier<String?> {
  @override
  String? build() => null;

  void escolher(String metodoId) => state = metodoId;
}

final metodoDashboardProvider = NotifierProvider<MetodoDoDashboard, String?>(
  MetodoDoDashboard.new,
);

/// O método que a grade mostra de fato — o escolhido, ou o primeiro.
final metodoVisivelProvider = Provider<TotalMetodo?>(
  (ref) => metodoVisivel(
    ref.watch(totaisPorMetodoProvider),
    ref.watch(metodoDashboardProvider),
  ),
);

/// A lotação Modular por curso (card 7.4), derivada de `turmasModularProvider`.
///
/// ⚠️ **Nenhum repositório novo, e é decisão.** A fonte é a mesma
/// `v_turma_modular_lotacao` que a tela 5 já lê (card 7.3): um segundo
/// repositório com uma segunda leitura da mesma view daria à mesma pergunta
/// duas respostas capazes de divergir — e o `DashboardRepositorio` existe para
/// a grade, cuja view é outra. Reusar também herda o `versaoModularProvider`:
/// admitir alguém na tela 5 e voltar ao dashboard mostra o número novo.
///
/// Sem guarda de permissão: a rota do dashboard exige `turmas.ler` +
/// `salas.ler` + `materiais.ler` (docs/permissoes-matriz.md §6), que é
/// exatamente o conjunto desta view (`views-leitura.md` §11) — quem chega aqui
/// lê a lotação inteira. É o oposto de `alunosModularProvider`, cuja permissão
/// a rota **não** exige.
final lotacaoModularProvider = Provider<List<LotacaoCurso>>(
  (ref) => lotacaoPorCurso(
    ref.watch(turmasModularProvider).value ?? const <TurmaModular>[],
  ),
);

// ---------------------------------------------------------------------------
// Alunos por método, tipos na turma e conclusões por semestre — card 8.7
// ---------------------------------------------------------------------------

/// Os alunos por status e por método (`v_dashboard_alunos_metodo`).
///
/// Sem guarda de permissão, pela mesma razão de [vagasSemanaProvider]: só a
/// tela do dashboard o lê, e a rota dela já exige `alunos.ler` **e**
/// `materiais.ler` (docs/permissoes-matriz.md §6) — que é exatamente o conjunto
/// desta view (docs/views-leitura.md §11). Quem chega aqui lê as contagens
/// inteiras; quem não chega vê a tela "Sem acesso" dizendo o que falta.
final alunosPorMetodoProvider = FutureProvider<List<AlunosMetodo>>(
  (ref) => _traduzindo(ref.watch(dashboardRepositorioProvider).alunosPorMetodo),
);

/// As alocações ativas por tipo (`v_dashboard_tipos_bloco`). Conjunto da view:
/// `turmas.ler` + `materiais.ler`, também subconjunto da rota.
final tiposPorBlocoProvider = FutureProvider<List<TiposBloco>>(
  (ref) => _traduzindo(ref.watch(dashboardRepositorioProvider).tiposPorBloco),
);

/// As conclusões previstas (`v_dashboard_conclusoes_semestre`).
final conclusoesPrevistasProvider = FutureProvider<List<ConclusaoSemestre>>(
  (ref) =>
      _traduzindo(ref.watch(dashboardRepositorioProvider).conclusoesPrevistas),
);

/// Os cartões por método: as contagens de aluno com os tipos na turma ao lado.
///
/// ⚠️ **A junção espera os alunos, não os tipos.** Enquanto
/// [tiposPorBlocoProvider] não voltou — ou se ele falhar —, `tipos` fica nulo e
/// a linha REM/PRE/REP/NOVO **some**, em vez de aparecer zerada: `.value ?? []`
/// aqui faria toda a escola parecer sem alocação nenhuma, que é o defeito B1 do
/// card 5.11 (`AsyncValue` que decide texto precisa dos três estados).
final paineisMetodoProvider = Provider<List<PainelMetodo>>(
  (ref) => paineisPorMetodo(
    ref.watch(alunosPorMetodoProvider).value ?? const <AlunosMetodo>[],
    ref.watch(tiposPorBlocoProvider).value ?? const <TiposBloco>[],
  ),
);

/// Os semestres com os métodos somados e a quebra por método ao lado.
final semestresConclusaoProvider = Provider<List<SemestreConclusoes>>(
  (ref) => conclusoesPorSemestre(
    ref.watch(conclusoesPrevistasProvider).value ?? const <ConclusaoSemestre>[],
  ),
);

/// A grade de vagas do método visível, já montada em dia × horário.
///
/// A semana sai de `data_referencia`, isto é, do **banco** — ver
/// [segundaDaGrade]. Sem linha nenhuma não há semana a afirmar, e aí a tela cai
/// no estado vazio antes de precisar de rótulo.
final gradeVagasProvider = Provider<GradeSemana?>((ref) {
  final metodo = ref.watch(metodoVisivelProvider);
  if (metodo == null) return null;
  final todas = ref.watch(vagasSemanaProvider).value ?? const <CelulaGrade>[];
  final segunda = segundaDaGrade(todas);
  if (segunda == null) return null;
  return montarGrade(segunda, celulasDoMetodo(todas, metodo.metodoId));
});
