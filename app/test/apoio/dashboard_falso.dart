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
    this.atrasoLeitura = Duration.zero,
  }) : _turmas = celulas == null ? (turmas ?? TurmasFalso.fixture()) : null,
       _celulas = celulas == null ? null : List.of(celulas);

  /// Sem nenhum bloco ativo — o estado vazio da tela.
  factory DashboardFalso.vazio() => DashboardFalso(celulas: const []);

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

  /// O card 4.4 mediu que teste instantâneo não constrói a tela no estado em que
  /// o banco a apanha.
  final Duration atrasoLeitura;

  int leituras = 0;

  /// Quando não nulo, a leitura levanta este erro.
  ErroApp? erro;

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
}

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
