import 'package:gestao_im360/dashboard/dashboard.dart';
import 'package:gestao_im360/erros/erro_app.dart';
import 'package:gestao_im360/dashboard/dashboard_repositorio.dart';

import 'turmas_falso.dart';

/// Repositório em memória do dashboard — o teste injeta **dados**, não um
/// cliente HTTP falso (card 2.8 §9.3).
///
/// A fixture delega ao [TurmasFalso], e isso é decisão: no banco a view
/// `v_bloco_vagas_semana` **é** `fn_grade_semana` na semana corrente (asserido
/// linha por linha no teste 095), então dois falsos com escolas diferentes
/// fariam os testes das duas telas concordarem sobre mundos que não coexistem.
///
/// A escola que sai daí tem exatamente a divergência que o dashboard existe
/// para não esconder: em INTERATIVO a soma das vagas é **11** e
/// `capacidade − ocupação` dá **10**, porque um bloco está acima da capacidade
/// e `fn_vagas_livres` não devolve negativo (card 5.2).
class DashboardFalso implements DashboardRepositorio {
  DashboardFalso({
    TurmasFalso? turmas,
    List<CelulaGrade>? celulas,
    List<AlunosMetodo>? alunos,
    List<TiposBloco>? tipos,
    List<ConclusaoSemestre>? conclusoes,
    this.atrasoLeitura = Duration.zero,
  }) : _turmas = celulas == null ? (turmas ?? TurmasFalso.fixture()) : null,
       _celulas = celulas == null ? null : List.of(celulas),
       _alunos = List.of(alunos ?? alunosDeFixture),
       _tipos = List.of(tipos ?? tiposDeFixture),
       _conclusoes = List.of(conclusoes ?? conclusoesDeFixture);

  /// Sem nenhum bloco ativo — o estado vazio da região de vagas. As três
  /// leituras do card 8.7 continuam com a escola cheia de propósito: é o que
  /// prova que uma região vazia não apaga as outras (design-system §7.2).
  factory DashboardFalso.vazio() => DashboardFalso(celulas: const []);

  /// Sem aluno, sem alocação e sem previsão — o estado vazio das duas regiões
  /// do card 8.7.
  factory DashboardFalso.semAlunos() =>
      DashboardFalso(alunos: const [], tipos: const [], conclusoes: const []);

  /// A leitura que **falha** — é como se exercita o quarto estado do wireframe
  /// §2.3 nesta tela, que o card 5.9 escreveu e nenhum teste cobria (revisão
  /// da fase 05, grupo G).
  factory DashboardFalso.queFalha() => DashboardFalso()
    ..erro = const ErroApp(
      mensagem:
          'Não foi possível falar com o servidor. Verifique a conexão e tente '
          'de novo.',
      traduzido: true,
    );

  final TurmasFalso? _turmas;
  final List<CelulaGrade>? _celulas;
  final List<AlunosMetodo> _alunos;
  final List<TiposBloco> _tipos;
  final List<ConclusaoSemestre> _conclusoes;

  /// O card 4.4 mediu que teste instantâneo não constrói a tela no estado em que
  /// o banco a apanha.
  final Duration atrasoLeitura;

  int leituras = 0;

  /// Quando não nulo, a leitura levanta este erro.
  ErroApp? erro;

  /// Quando não nulo, **só** a leitura de alunos por método levanta este erro —
  /// é como se exercita a independência entre as regiões.
  ErroApp? erroAlunos;

  /// Idem para as conclusões previstas.
  ErroApp? erroConclusoes;

  /// Idem para os tipos na turma, que é a leitura cuja falha **não pode** virar
  /// linha zerada no cartão (a linha some).
  ErroApp? erroTipos;

  int leiturasAlunos = 0;

  @override
  Future<List<CelulaGrade>> vagasDaSemana() async {
    if (atrasoLeitura > Duration.zero) {
      await Future<void>.delayed(atrasoLeitura);
    }
    leituras++;
    final falha = erro;
    if (falha != null) throw falha;
    final fixas = _celulas;
    if (fixas != null) return List.of(fixas);
    // Aqui o relógio é o do teste porque não há outro; no banco quem fixa a
    // semana é `fn_hoje()`, e é justamente por isso que a tela lê a semana de
    // `data_referencia` e não do aparelho (ver `segundaDaGrade`).
    return _turmas!.grade(segundaDe(DateTime.now()));
  }

  @override
  Future<List<AlunosMetodo>> alunosPorMetodo() async {
    if (atrasoLeitura > Duration.zero) {
      await Future<void>.delayed(atrasoLeitura);
    }
    leiturasAlunos++;
    final falha = erroAlunos;
    if (falha != null) throw falha;
    return List.of(_alunos);
  }

  @override
  Future<List<TiposBloco>> tiposPorBloco() async {
    if (atrasoLeitura > Duration.zero) {
      await Future<void>.delayed(atrasoLeitura);
    }
    final falha = erroTipos;
    if (falha != null) throw falha;
    return List.of(_tipos);
  }

  @override
  Future<List<ConclusaoSemestre>> conclusoesPrevistas() async {
    if (atrasoLeitura > Duration.zero) {
      await Future<void>.delayed(atrasoLeitura);
    }
    final falha = erroConclusoes;
    if (falha != null) throw falha;
    return List.of(_conclusoes);
  }
}

/// Os números da **escola-fixture do banco** (`supabase/seed.sql`, ESCOLA_A),
/// conferidos contra as três views em 06/09/2026.
///
/// Copiados de lá de propósito: o widget test e a suíte pgTAP passam a falar da
/// mesma escola, e um número que mudar de um lado fica visivelmente diferente do
/// outro. É a mesma escolha que fez `DashboardFalso` delegar a grade ao
/// `TurmasFalso` em vez de inventar uma segunda escola.
const alunosDeFixture = [
  AlunosMetodo(
    metodoId: 'm-int',
    metodoCodigo: 'INTERATIVO',
    ativos: 19,
    acelerar: 0,
    standby: 0,
    trancados: 1,
    cancelados: 1,
    formados: 1,
    emUltimoLivro: 0,
    // ⚠️ 1, e é Karina — ATIVA e **sem combo**, logo sem trilha nenhuma. João
    // Pedro, que está de fato em FIM, é FORMADO e sai do filtro de status.
    // "Nenhum item pendente" também é verdade para quem nunca começou (card
    // 6.2), e é por isso que o cartão não mostra esta coluna.
    emFim: 1,
    semPrevisao: 16,
  ),
  AlunosMetodo(
    metodoId: 'm-ing',
    metodoCodigo: 'INGLES',
    ativos: 0,
    acelerar: 1,
    standby: 1,
    trancados: 0,
    cancelados: 0,
    formados: 0,
    emUltimoLivro: 1,
    emFim: 0,
    semPrevisao: 0,
  ),
  AlunosMetodo(
    metodoId: 'm-mod',
    metodoCodigo: 'MODULAR',
    ativos: 2,
    acelerar: 0,
    standby: 0,
    trancados: 0,
    cancelados: 0,
    formados: 0,
    emUltimoLivro: 0,
    emFim: 1,
    semPrevisao: 2,
  ),
];

/// ⚠️ **Uma linha só**, e é o ponto: na fixture apenas o INTERATIVO tem bloco de
/// horário, então os cartões de Inglês e Modular ficam **sem** a linha de tipos.
/// Uma junção posicional poria os 19 do Interativo no cartão do Inglês.
const tiposDeFixture = [
  TiposBloco(
    metodoId: 'm-int',
    metodoCodigo: 'INTERATIVO',
    rem: 15,
    pre: 2,
    rep: 1,
    novo: 1,
    alocacoes: 19,
  ),
];

/// Três linhas em dois semestres, com **uma vencida** — o Diego, cuja previsão
/// está 15 dias no passado. Ano fixo aqui porque o widget test não tem
/// `fn_hoje()`; quem prende a data ao relógio do banco é a suíte pgTAP.
const conclusoesDeFixture = [
  ConclusaoSemestre(
    metodoId: 'm-int',
    metodoCodigo: 'INTERATIVO',
    ano: 2026,
    semestre: 2,
    qtdAlunos: 2,
    qtdVencidas: 1,
  ),
  ConclusaoSemestre(
    metodoId: 'm-ing',
    metodoCodigo: 'INGLES',
    ano: 2026,
    semestre: 2,
    qtdAlunos: 1,
    qtdVencidas: 0,
  ),
  ConclusaoSemestre(
    metodoId: 'm-int',
    metodoCodigo: 'INTERATIVO',
    ano: 2027,
    semestre: 1,
    qtdAlunos: 1,
    qtdVencidas: 0,
  ),
];

/// Uma linha de `v_bloco_vagas_semana` montada à mão, para os casos que a
/// fixture da escola não tem — em especial uma semana que **não** é a do
/// relógio do teste.
CelulaGrade vagaFalsa({
  required String blocoId,
  required int dia,
  String hora = '08:00',
  required DateTime dataReferencia,
  String metodoId = 'm-int',
  String metodoCodigo = 'INTERATIVO',
  String salaId = 's-lab1',
  String salaNome = 'Laboratório 1',
  String? professorNome = 'Marcos Vieira',
  int capacidade = 10,
  int ocupacao = 0,
  int? vagasLivres,
  bool acima = false,
}) => CelulaGrade(
  blocoId: blocoId,
  diaSemana: dia,
  horaInicio: hora,
  dataReferencia: dataReferencia,
  metodoId: metodoId,
  metodoCodigo: metodoCodigo,
  salaId: salaId,
  salaNome: salaNome,
  professorNome: professorNome,
  capacidade: capacidade,
  ocupacao: ocupacao,
  // O default reproduz `fn_vagas_livres`: nunca negativo (card 5.2).
  vagasLivres:
      vagasLivres ?? (ocupacao >= capacidade ? 0 : capacidade - ocupacao),
  acimaCapacidade: acima,
);
