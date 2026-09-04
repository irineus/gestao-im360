import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../sessao/sessao_provider.dart';
import 'turmas.dart';
import 'turmas_repositorio.dart';

/// Repositório das turmas — sobrescrito nos widget tests com dados
/// (card 2.8 §9.3).
final turmasRepositorioProvider = Provider<TurmasRepositorio>(
  (ref) => TurmasRepositorioSupabase(
    ref.watch(clienteSupabaseProvider),
    unidadeId: ref.watch(unidadeAtualProvider) ?? '',
  ),
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

/// Versão das turmas em memória: toda leitura a observa e toda escrita a
/// incrementa, recarregando a tela depois de salvar (mesmo desenho da
/// `VersaoCatalogo` do card 4.4).
class VersaoTurmas extends Notifier<int> {
  @override
  int build() => 0;

  void incrementar() => state++;
}

final versaoTurmasProvider = NotifierProvider<VersaoTurmas, int>(
  VersaoTurmas.new,
);

TurmasRepositorio _repositorio(Ref ref) {
  ref.watch(versaoTurmasProvider);
  return ref.watch(turmasRepositorioProvider);
}

/// A semana visível, sempre pela segunda-feira. Estado no provider e não no
/// widget para a semana sobreviver a abrir e fechar o painel de um bloco
/// (design-system §5.3) — voltar sempre para a semana corrente depois de editar
/// um bloco de outra semana esconderia o resultado da própria edição.
///
/// A semana corrente sai de [hojeSaoPaulo], nunca de `DateTime.now()`: quem
/// decide qual é "esta semana" é o banco, com `fn_hoje()` (São Paulo), e o
/// relógio do aparelho pode estar em outro fuso — a grade certa sob a semana
/// errada é a família de falha calada que este projeto cataloga.
class SemanaNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => segundaDe(hojeSaoPaulo());

  void mover(int semanas) =>
      state = DateTime(state.year, state.month, state.day + 7 * semanas);

  void hoje() => state = segundaDe(hojeSaoPaulo());

  /// Ir para a semana de uma data — é o que o atalho da célula do dashboard
  /// usa para abrir Turmas na **mesma** semana que o dashboard rotulou, que vem
  /// de `data_referencia` e não do relógio.
  void definir(DateTime data) => state = segundaDe(data);
}

final semanaProvider = NotifierProvider<SemanaNotifier, DateTime>(
  SemanaNotifier.new,
);

/// A grade da semana visível. Depende de [semanaProvider], então mudar de
/// semana recarrega sozinho.
final gradeProvider = FutureProvider<List<CelulaGrade>>((ref) {
  final semana = ref.watch(semanaProvider);
  return _traduzindo(() => _repositorio(ref).grade(semana));
});

/// A grade da **semana corrente**, independente de [semanaProvider].
///
/// ⚠️ Existe porque [gradeProvider] carrega o estado da tela de Turmas, que
/// sobrevive à navegação: quem foi ver dezembro lá e depois abriu o seletor de
/// bloco da virada REP via as vagas de dezembro sob o texto "nesta semana"
/// (achado da revisão da fase 05). A virada é alocação **permanente**, e a vaga
/// que decide é a de agora.
final gradeCorrenteProvider = FutureProvider<List<CelulaGrade>>(
  (ref) => _traduzindo(() => _repositorio(ref).grade(hojeSaoPaulo())),
);

final blocosProvider = FutureProvider<List<BlocoHorario>>(
  (ref) => _traduzindo(_repositorio(ref).blocos),
);

/// Os desativados, derivados de [blocosProvider] — uma consulta só serve às
/// duas telas, e "inativo" é um filtro, não outra fonte.
final blocosInativosProvider = Provider<List<BlocoHorario>>((ref) {
  final blocos = ref.watch(blocosProvider).value ?? const <BlocoHorario>[];
  return [
    for (final b in blocos)
      if (!b.ativo) b,
  ];
});

/// `bloco_horario.id` → bloco, para nomear o bloco de uma reposição na ficha do
/// aluno sem uma segunda consulta.
final blocosPorIdProvider = Provider<Map<String, BlocoHorario>>((ref) {
  final blocos = ref.watch(blocosProvider).value ?? const <BlocoHorario>[];
  return {
    for (final b in blocos)
      if (b.id != null) b.id!: b,
  };
});

class FiltroGradeNotifier extends Notifier<FiltroGrade> {
  @override
  FiltroGrade build() => const FiltroGrade();

  void definir(FiltroGrade filtro) => state = filtro;

  void limpar() => state = FiltroGrade.semFiltro;
}

final filtroGradeProvider = NotifierProvider<FiltroGradeNotifier, FiltroGrade>(
  FiltroGradeNotifier.new,
);

// ---------------------------------------------------------------------------
// Card 5.7
// ---------------------------------------------------------------------------

/// Um bloco numa data — a chave do painel de alunos do bloco. A data faz parte
/// da identidade porque a lotação é de um dia (card 2.1 §8).
@immutable
class BlocoNaData {
  const BlocoNaData(this.blocoId, this.data);

  final String blocoId;
  final DateTime data;

  @override
  bool operator ==(Object other) =>
      other is BlocoNaData &&
      other.blocoId == blocoId &&
      other.data.year == data.year &&
      other.data.month == data.month &&
      other.data.day == data.day;

  @override
  int get hashCode => Object.hash(blocoId, data.year, data.month, data.day);
}

final alunosDoBlocoProvider =
    FutureProvider.family<List<AlunoDoBloco>, BlocoNaData>(
      (ref, chave) => _traduzindo(
        () => _repositorio(ref).alunosDoBloco(chave.blocoId, chave.data),
      ),
    );

/// Todas as alocações ativas da unidade, do lado do aluno.
///
/// Devolve vazio para quem não tem `turmas.ler` em vez de deixar a RLS o fazer
/// em silêncio: a lista de alunos exige só `alunos.ler` + `materiais.ler`
/// (card 2.4 §6), então um perfil sem `turmas.ler` chega até aqui, e uma lista
/// vazia vinda da RLS marcaria **todo mundo** com o ⚠ de "sem turma". Quem
/// esconde a coluna é a tela; este provider não finge que consultou.
final turmasProvider = FutureProvider<List<TurmaDoAluno>>((ref) {
  if (!ref.watch(permissoesProvider).contains('turmas.ler')) {
    return Future.value(const <TurmaDoAluno>[]);
  }
  return _traduzindo(_repositorio(ref).turmas);
});

/// `aluno_id` → turmas dele, já ordenadas.
final turmasPorAlunoProvider = Provider<Map<String, List<TurmaDoAluno>>>((ref) {
  final turmas = ref.watch(turmasProvider).value ?? const <TurmaDoAluno>[];
  return agruparPorAluno(turmas);
});

/// Os alunos que estão em pelo menos uma turma que existe — o complemento
/// disto, entre os ATIVO/ACELERAR, é o ⚠ da lista (card 5.7).
final alunosEmTurmaProvider = Provider<Set<String>>(
  (ref) => alunosEmTurma(ref.watch(turmasProvider).value ?? const []),
);

final reposicoesAlunoProvider =
    FutureProvider.family<List<ReposicaoAluno>, String>(
      (ref, alunoId) =>
          _traduzindo(() => _repositorio(ref).reposicoesDoAluno(alunoId)),
    );

final situacaoRepProvider = FutureProvider.family<SituacaoRep, String>(
  (ref, alunoId) => _traduzindo(() => _repositorio(ref).situacaoRep(alunoId)),
);
