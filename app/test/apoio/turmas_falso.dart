import 'package:gestao_im360/turmas/turmas.dart';
import 'package:gestao_im360/turmas/turmas_repositorio.dart';

/// Repositório em memória — o teste injeta **dados**, não um cliente HTTP falso
/// (card 2.8 §9.3). A forma dos dados é a da camada `turmas` da escola-fixture
/// (card 5.1, `supabase/seed.sql`): três blocos no Laboratório 1 às 08:00, com
/// 0, 9 e 10 alunos para capacidade 10, e o de 10 **sem professor**.
///
/// Mais dois casos que a fixture do banco não tem e a tela precisa: um bloco
/// acima da capacidade (o ⚠ vermelho) e um segundo bloco no mesmo dia e horário
/// em outra sala — a `unique` é por sala, e a célula é uma lista.
class TurmasFalso implements TurmasRepositorio {
  TurmasFalso({
    List<CelulaGrade>? celulas,
    List<BlocoHorario>? inativos,
    this.atrasoLeitura = Duration.zero,
  }) : celulas_ = List.of(celulas ?? const []),
       inativos_ = List.of(inativos ?? const []);

  factory TurmasFalso.fixture() => TurmasFalso(
    celulas: [
      // Segunda 08:00 — vazio, com professor.
      _celula(
        blocoId: 'b-vazio',
        dia: 1,
        metodo: 'INTERATIVO',
        sala: 'Laboratório 1',
        salaId: 's-lab1',
        professor: 'Marcos Vieira',
        ocupacao: 0,
      ),
      // Terça 08:00 — quase cheio.
      _celula(
        blocoId: 'b-quase',
        dia: 2,
        metodo: 'INTERATIVO',
        sala: 'Laboratório 1',
        salaId: 's-lab1',
        professor: 'Renata Alves',
        ocupacao: 9,
      ),
      // Quarta 08:00 — cheio e SEM professor: é a célula que reprova a grade
      // escrita com join interno em professor.
      _celula(
        blocoId: 'b-cheio',
        dia: 3,
        metodo: 'INTERATIVO',
        sala: 'Laboratório 1',
        salaId: 's-lab1',
        ocupacao: 10,
      ),
      // Quarta 08:00 em OUTRA sala: mesmo cruzamento da grade, dois blocos.
      _celula(
        blocoId: 'b-ingles',
        dia: 3,
        metodo: 'INGLES',
        sala: 'Laboratório 2',
        salaId: 's-lab2',
        professor: 'Paula Nunes',
        ocupacao: 4,
        capacidade: 6,
      ),
      // Quinta 09:30 — acima da capacidade.
      _celula(
        blocoId: 'b-acima',
        dia: 4,
        hora: '09:30',
        metodo: 'INTERATIVO',
        sala: 'Laboratório 1',
        salaId: 's-lab1',
        professor: 'Marcos Vieira',
        ocupacao: 11,
        acima: true,
      ),
    ],
    inativos: const [
      BlocoHorario(
        id: 'b-inativo',
        diaSemana: 5,
        horaInicio: '14:00',
        metodoId: 'm-int',
        salaId: 's-lab1',
        ativo: false,
      ),
    ],
  );

  final List<CelulaGrade> celulas_;
  final List<BlocoHorario> inativos_;

  /// O card 4.4 mediu que teste instantâneo não constrói a tela no estado em
  /// que o banco a apanha: durante a recarga o `AsyncValue` ainda carrega o
  /// valor anterior. O atraso é o que permite reproduzir isso.
  final Duration atrasoLeitura;

  /// A última semana pedida — é como o teste confere a navegação sem espionar
  /// o provider.
  DateTime? ultimaSemana;

  final List<BlocoHorario> salvos = [];
  final List<String> excluidos = [];

  @override
  Future<List<CelulaGrade>> grade(DateTime segunda) async {
    if (atrasoLeitura > Duration.zero) {
      await Future<void>.delayed(atrasoLeitura);
    }
    final base = segundaDe(segunda);
    ultimaSemana = base;
    return [
      for (final c in celulas_)
        CelulaGrade(
          blocoId: c.blocoId,
          diaSemana: c.diaSemana,
          horaInicio: c.horaInicio,
          dataReferencia: DateTime(
            base.year,
            base.month,
            base.day + (c.diaSemana - 1),
          ),
          metodoId: c.metodoId,
          metodoCodigo: c.metodoCodigo,
          salaId: c.salaId,
          salaNome: c.salaNome,
          professorId: c.professorId,
          professorNome: c.professorNome,
          capacidadeOverride: c.capacidadeOverride,
          capacidade: c.capacidade,
          ocupacao: c.ocupacao,
          vagasLivres: c.vagasLivres,
          acimaCapacidade: c.acimaCapacidade,
        ),
    ];
  }

  @override
  Future<List<BlocoHorario>> blocosInativos() async {
    if (atrasoLeitura > Duration.zero) {
      await Future<void>.delayed(atrasoLeitura);
    }
    return List.of(inativos_);
  }

  @override
  Future<BlocoHorario> salvarBloco(BlocoHorario bloco) async {
    salvos.add(bloco);
    return bloco;
  }

  @override
  Future<void> excluirBloco(String id) async => excluidos.add(id);
}

/// A célula-modelo: `dataReferencia` é recalculada em [TurmasFalso.grade] para
/// a semana pedida, então aqui ela é só um marcador.
final _epoca = DateTime.utc(2026, 1, 1);

CelulaGrade _celula({
  required String blocoId,
  required int dia,
  String hora = '08:00',
  required String metodo,
  required String sala,
  required String salaId,
  String? professor,
  required int ocupacao,
  int capacidade = 10,
  bool acima = false,
}) => CelulaGrade(
  blocoId: blocoId,
  diaSemana: dia,
  horaInicio: hora,
  dataReferencia: _epoca,
  // Os mesmos ids do `CatalogoFalso` e do `InfraestruturaFalso`: os três
  // repositórios falsos descrevem a MESMA escola-fixture, e ids divergentes
  // fariam o filtro de método da tela nunca casar com nada.
  metodoId: metodo == 'INGLES' ? 'm-ing' : 'm-int',
  professorId: switch (professor) {
    'Marcos Vieira' => 'prof-1',
    'Renata Alves' => 'prof-2',
    _ => null,
  },
  metodoCodigo: metodo,
  salaId: salaId,
  salaNome: sala,
  professorNome: professor,
  capacidade: capacidade,
  ocupacao: ocupacao,
  vagasLivres: ocupacao >= capacidade ? 0 : capacidade - ocupacao,
  acimaCapacidade: acima,
);
