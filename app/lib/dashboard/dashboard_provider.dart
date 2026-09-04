import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../sessao/sessao_provider.dart';
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
