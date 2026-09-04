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
///
/// Do card 5.7 em diante ele também **reproduz as funções de alocação**: admitir
/// acrescenta à lista do bloco e desmarca a reposição de origem; remover tira.
/// Sem isso os testes mediriam um mundo em que salvar não muda nada — a mesma
/// lição que o card 5.4 escreveu ao fazer o repositório falso reproduzir o
/// trigger de status do PC.
class TurmasFalso implements TurmasRepositorio {
  TurmasFalso({
    List<CelulaGrade>? celulas,
    List<BlocoHorario>? blocos,
    Map<String, List<AlunoDoBloco>>? alunos,
    List<TurmaDoAluno>? turmas,
    List<ReposicaoAluno>? reposicoes,
    this.situacao,
    this.atrasoLeitura = Duration.zero,
  }) : celulas_ = List.of(celulas ?? const []),
       blocos_ = List.of(blocos ?? const []),
       alunos_ = {
         for (final entrada in (alunos ?? const {}).entries)
           entrada.key: List.of(entrada.value),
       },
       turmas_ = List.of(turmas ?? const []),
       reposicoes_ = List.of(reposicoes ?? const []);

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
    blocos: const [
      BlocoHorario(
        id: 'b-vazio',
        diaSemana: 1,
        horaInicio: '08:00',
        metodoId: 'm-int',
        salaId: 's-lab1',
      ),
      BlocoHorario(
        id: 'b-quase',
        diaSemana: 2,
        horaInicio: '08:00',
        metodoId: 'm-int',
        salaId: 's-lab1',
      ),
      BlocoHorario(
        id: 'b-cheio',
        diaSemana: 3,
        horaInicio: '08:00',
        metodoId: 'm-int',
        salaId: 's-lab1',
      ),
      BlocoHorario(
        id: 'b-inativo',
        diaSemana: 5,
        horaInicio: '14:00',
        metodoId: 'm-int',
        salaId: 's-lab1',
        ativo: false,
      ),
    ],
    // O bloco vazio tem UMA reposição pontual no dia — é a forma da fixture do
    // banco (Lucas Ferreira em `fn_hoje() + 3`), e é o caso que separa as duas
    // metades do REP híbrido numa lista só.
    // Os ids são os do `AlunosFalso`: os três repositórios falsos descrevem a
    // MESMA escola-fixture, e ids divergentes fariam a coluna Turmas da lista
    // de alunos nunca casar com ninguém.
    alunos: {
      'b-cheio': [
        alocacaoFalsa(
          alunoId: 'al-3001',
          nome: 'Ana Paula Ribeiro',
          codigoSgf: '3001',
          tipo: 'REM',
        ),
        alocacaoFalsa(
          alunoId: 'al-3004',
          nome: 'Diego Alves',
          codigoSgf: '3004',
          tipo: 'PRE',
        ),
        alocacaoFalsa(
          alunoId: 'al-karina',
          nome: 'Karina Bastos',
          tipo: 'NOVO',
        ),
      ],
      'b-vazio': [reposicaoFalsa()],
    },
    turmas: [
      turmaFalsa(alunoId: 'al-3001', blocoId: 'b-cheio', tipo: 'REM'),
      turmaFalsa(alunoId: 'al-3004', blocoId: 'b-cheio', tipo: 'PRE'),
      turmaFalsa(alunoId: 'al-karina', blocoId: 'b-cheio', tipo: 'NOVO'),
      // Alocação ÓRFÃ: Eduarda segue alocada num bloco desativado, e para o
      // sistema ela está sem turma (o ajuste que o card 5.6 deixou para o 5.7).
      turmaFalsa(
        alunoId: 'al-3005',
        blocoId: 'b-inativo',
        tipo: 'REM',
        diaSemana: 5,
        horaInicio: '14:00',
        blocoAtivo: false,
      ),
    ],
    reposicoes: [
      reposicaoDoAlunoFalsa(),
      reposicaoDoAlunoFalsa(
        id: 'rep-antiga',
        data: DateTime(2026, 8, 20),
        status: 'FALTOU',
      ),
    ],
  );

  final List<CelulaGrade> celulas_;
  final List<BlocoHorario> blocos_;
  final Map<String, List<AlunoDoBloco>> alunos_;
  final List<TurmaDoAluno> turmas_;
  final List<ReposicaoAluno> reposicoes_;

  /// O que `fn_rep_situacao` devolve. Nulo = "MANTER sem débito", que é o caso
  /// da maioria dos alunos e faz a seção sumir da ficha. Mutável para o teste da
  /// central (card 5.8) montar a fixture e depois pôr o aluno em débito.
  SituacaoRep? situacao;

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
  Future<List<BlocoHorario>> blocos() async {
    if (atrasoLeitura > Duration.zero) {
      await Future<void>.delayed(atrasoLeitura);
    }
    return List.of(blocos_);
  }

  @override
  Future<BlocoHorario> salvarBloco(BlocoHorario bloco) async {
    salvos.add(bloco);
    return bloco;
  }

  @override
  Future<void> excluirBloco(String id) async => excluidos.add(id);

  // --- card 5.7 ------------------------------------------------------------

  final List<String> admitidos = [];
  final List<String> removidos = [];
  final List<String> reposicoesLancadas = [];
  final List<String> canceladas = [];

  /// O veredito que `fn_reposicao_registrar` devolve — é o que a tela mostra na
  /// hora (ajuste 7 do card 2.2 §14).
  String veredito = 'MANTER';

  @override
  Future<List<AlunoDoBloco>> alunosDoBloco(
    String blocoId,
    DateTime data,
  ) async {
    if (atrasoLeitura > Duration.zero) {
      await Future<void>.delayed(atrasoLeitura);
    }
    return List.of(alunos_[blocoId] ?? const []);
  }

  @override
  Future<List<TurmaDoAluno>> turmas() async {
    if (atrasoLeitura > Duration.zero) {
      await Future<void>.delayed(atrasoLeitura);
    }
    return List.of(turmas_);
  }

  @override
  Future<List<ReposicaoAluno>> reposicoesDoAluno(String alunoId) async {
    if (atrasoLeitura > Duration.zero) {
      await Future<void>.delayed(atrasoLeitura);
    }
    return [
      for (final r in reposicoes_)
        if (r.alunoId == alunoId) r,
    ];
  }

  @override
  Future<SituacaoRep> situacaoRep(String alunoId) async =>
      situacao ??
      const SituacaoRep(
        debito: 0,
        semanasUteis: 0,
        capacidade: 1,
        faltasRecentes: 0,
        veredito: 'MANTER',
      );

  @override
  Future<String> admitir({
    required String blocoId,
    required String alunoId,
    required String tipo,
    DateTime? dataInicioPrevista,
  }) async {
    admitidos.add('$blocoId|$alunoId|$tipo');
    (alunos_[blocoId] ??= []).add(
      alocacaoFalsa(alunoId: alunoId, nome: alunoId, tipo: tipo),
    );
    turmas_.add(turmaFalsa(alunoId: alunoId, blocoId: blocoId, tipo: tipo));
    return 'alocacao-$alunoId';
  }

  @override
  Future<void> remover({
    required String blocoId,
    required String alunoId,
    String? motivo,
  }) async {
    removidos.add('$blocoId|$alunoId|${motivo ?? ''}');
    alunos_[blocoId]?.removeWhere(
      (a) => a.alunoId == alunoId && !a.ehReposicao,
    );
    turmas_.removeWhere((t) => t.alunoId == alunoId && t.blocoId == blocoId);
  }

  @override
  Future<String> agendarReposicao({
    required String blocoId,
    required String alunoId,
    required DateTime data,
    String? blocoOrigemId,
    DateTime? dataOrigem,
    String? observacao,
  }) async {
    reposicoesLancadas.add('$blocoId|$alunoId|${dataIso(data)}');
    return 'reposicao-$alunoId';
  }

  @override
  Future<String> registrarReposicao(
    String reposicaoId, {
    required bool veio,
  }) async {
    presencas.add('$reposicaoId|${veio ? 'VEIO' : 'FALTOU'}');
    return veredito;
  }

  @override
  Future<void> cancelarReposicao(String reposicaoId, String observacao) async {
    canceladas.add('$reposicaoId|$observacao');
    for (final lista in alunos_.values) {
      lista.removeWhere((a) => a.ehReposicao && a.registroId == reposicaoId);
    }
  }

  // --- card 5.8 ------------------------------------------------------------

  final List<String> viradas = [];
  final List<String> voltas = [];
  final List<String> presencas = [];

  @override
  Future<String> virarContinuo({
    required String alunoId,
    required String blocoId,
    String? observacao,
  }) async {
    viradas.add('$alunoId|$blocoId|${observacao ?? ''}');
    // Reproduz o efeito da função: o aluno passa a ter alocação REP no bloco e
    // as reposições PREVISTA são canceladas. Sem isso os testes mediriam um
    // mundo em que executar a virada não muda nada — a lição do card 5.4.
    (alunos_[blocoId] ??= []).add(
      alocacaoFalsa(alunoId: alunoId, nome: alunoId, tipo: 'REP'),
    );
    turmas_.add(turmaFalsa(alunoId: alunoId, blocoId: blocoId, tipo: 'REP'));
    reposicoes_.removeWhere((r) => r.alunoId == alunoId && r.prevista);
    return 'alocacao-$alunoId';
  }

  @override
  Future<void> voltarPontual({
    required String alunoId,
    required String motivo,
  }) async {
    voltas.add('$alunoId|$motivo');
    turmas_.removeWhere((t) => t.alunoId == alunoId && t.tipo == 'REP');
    for (final lista in alunos_.values) {
      lista.removeWhere(
        (a) => a.alunoId == alunoId && !a.ehReposicao && a.tipo == 'REP',
      );
    }
  }
}

/// Uma alocação como `fn_bloco_alunos` a devolve.
AlunoDoBloco alocacaoFalsa({
  required String alunoId,
  required String nome,
  required String tipo,
  String? codigoSgf,
  String status = 'ATIVO',
  bool blocoAtivo = true,
}) => AlunoDoBloco(
  origem: OrigemNoBloco.alocacao,
  registroId: 'aloc-$alunoId',
  alunoId: alunoId,
  alunoNome: nome,
  codigoSgf: codigoSgf,
  alunoStatus: status,
  tipo: tipo,
  tipoDesde: DateTime(2026, 3, 12),
  dataInicioPrevista: tipo == 'NOVO' ? DateTime(2026, 9, 10) : null,
  blocoAtivo: blocoAtivo,
);

/// A reposição pontual da fixture: Lucas repõe no bloco vazio a aula que perdeu
/// na quarta. É ela que carrega o rótulo "reposição de Qua 08:00 27/08".
AlunoDoBloco reposicaoFalsa({
  String alunoId = 'al-lucas',
  String nome = 'Lucas Ferreira',
  int? blocoOrigemDia = 3,
  String? blocoOrigemHora = '08:00',
  DateTime? dataOrigem,
}) => AlunoDoBloco(
  origem: OrigemNoBloco.reposicao,
  registroId: 'rep-$alunoId',
  alunoId: alunoId,
  alunoNome: nome,
  alunoStatus: 'ATIVO',
  tipo: 'REP',
  data: DateTime(2026, 9, 7),
  blocoOrigemId: blocoOrigemDia == null ? null : 'b-cheio',
  blocoOrigemDia: blocoOrigemDia,
  blocoOrigemHora: blocoOrigemHora,
  dataOrigem: dataOrigem ?? DateTime(2026, 8, 27),
);

/// Uma linha de `bloco_aluno_reposicao` como a aba Turmas da ficha a lê.
ReposicaoAluno reposicaoDoAlunoFalsa({
  String id = 'rep-al-lucas',
  String alunoId = 'al-lucas',
  String blocoId = 'b-vazio',
  DateTime? data,
  String status = 'PREVISTA',
}) => ReposicaoAluno(
  id: id,
  blocoId: blocoId,
  alunoId: alunoId,
  data: data ?? DateTime(2026, 9, 7),
  status: status,
  blocoOrigemId: 'b-cheio',
  dataOrigem: DateTime(2026, 8, 27),
  observacao: 'faltou por doença',
);

/// Uma linha de `v_bloco_alunos` vista do lado do aluno.
TurmaDoAluno turmaFalsa({
  required String alunoId,
  required String blocoId,
  required String tipo,
  int diaSemana = 3,
  String horaInicio = '08:00',
  bool blocoAtivo = true,
}) => TurmaDoAluno(
  alocacaoId: 'aloc-$alunoId-$blocoId',
  blocoId: blocoId,
  alunoId: alunoId,
  diaSemana: diaSemana,
  horaInicio: horaInicio,
  metodoId: 'm-int',
  salaId: 's-lab1',
  blocoAtivo: blocoAtivo,
  tipo: tipo,
  tipoDesde: DateTime(2026, 3, 12),
);

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
