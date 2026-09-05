import 'package:gestao_im360/erros/erro_app.dart';
import 'package:gestao_im360/turmas/modular.dart';
import 'package:gestao_im360/turmas/modular_repositorio.dart';

/// Repositório em memória das turmas Modular — o teste injeta **dados**, não um
/// cliente HTTP falso (card 2.8 §9.3).
///
/// A forma é a da camada `modular` da escola-fixture (card 7.1,
/// `supabase/seed.sql`): duas turmas de Eletricista, a `2026.1` com cronograma
/// de três módulos e Eduarda Lima dentro, a `2025.2` VAZIA e com o módulo
/// corrente vencido. Os ids de aluno, curso e sala são os do `AlunosFalso`, do
/// `CatalogoFalso` e do `InfraestruturaFalso` — os repositórios falsos descrevem
/// a MESMA escola, e ids divergentes fariam a busca de candidatos nunca casar
/// com ninguém.
///
/// Mais dois casos que a fixture do banco não tem e a tela precisa: uma turma
/// **acima da capacidade** (o ⚠ vermelho) e uma turma **sem cronograma nenhum**
/// (o aviso do wireframe §8 e o `[Avançar módulo]` desabilitado com motivo).
///
/// ⚠️ Ele **reproduz as funções** do card 7.2: admitir acrescenta o aluno e sobe
/// a lotação, remover desativa a linha gravando o motivo, avançar conclui o
/// corrente e abre o seguinte. Sem isso os testes mediriam um mundo em que
/// salvar não muda nada — a lição que o card 5.4 escreveu.
class ModularFalso implements ModularRepositorio {
  ModularFalso({
    List<TurmaModular>? turmas,
    List<TurmaModular>? inativas,
    List<ModuloDaTurma>? cronograma,
    List<AlunoDaTurmaModular>? alunos,
    this.atrasoLeitura = Duration.zero,
  }) : turmas_ = List.of(turmas ?? const []),
       inativas_ = List.of(inativas ?? const []),
       cronograma_ = List.of(cronograma ?? const []),
       alunos_ = List.of(alunos ?? const []);

  /// Um repositório em que **toda leitura falha** — é como se exercita o quarto
  /// estado do wireframe §2.3.
  factory ModularFalso.queFalha({ErroApp? erro}) => ModularFalso.fixture()
    ..erroDeLeitura =
        erro ??
        const ErroApp(
          mensagem:
              'Não foi possível falar com o servidor. Verifique a conexão e '
              'tente de novo.',
          traduzido: true,
        );

  factory ModularFalso.fixture() => ModularFalso(
    turmas: [
      // Cronograma COMPLETO (os três módulos de `c-ele` no `CatalogoFalso`):
      // é a turma em que "Acrescentar módulo" não aparece.
      turmaModularFalsa(
        id: 't-2026',
        nome: 'Eletricista 2026.1',
        alocados: 1,
        moduloCorrenteId: 'mod-2',
        moduloCorrenteNome: 'Módulo 2 — Instalações prediais',
        moduloCorrenteOrdem: 2,
        moduloCorrenteInicio: DateTime(2026, 8, 11),
        moduloCorrentePrevConclusao: DateTime(2026, 10, 10),
      ),
      // Vazia e com o módulo corrente VENCIDO — é o `modulo_atrasado` com o
      // outro valor, a mesma escolha do seed. Cronograma PARCIAL (só o módulo
      // 1): é a turma do "Acrescentar 2 módulo(s)".
      turmaModularFalsa(
        id: 't-2025',
        nome: 'Eletricista 2025.2',
        alocados: 0,
        moduloCorrenteId: 'mod-1',
        moduloCorrenteNome: 'Módulo 1 — Comandos elétricos',
        moduloCorrenteOrdem: 1,
        moduloCorrenteInicio: DateTime(2025, 11, 10),
        moduloCorrentePrevConclusao: DateTime(2026, 7, 26),
        moduloAtrasado: true,
      ),
      // Acima da capacidade: 16 numa turma de 15. Estado real — o importador do
      // card 9.1 pode trazer uma —, e `vagas_livres` tem piso zero.
      turmaModularFalsa(
        id: 't-cheia',
        nome: 'Depilação 2026.1',
        cursoId: 'c-dep',
        cursoNome: 'Depilação',
        alocados: 16,
        moduloCorrenteId: 'mod-dep-1',
        moduloCorrenteNome: 'Técnicas básicas',
        moduloCorrenteOrdem: 1,
      ),
      // SEM cronograma: nenhuma linha em `cronograma_` aponta para ela, e o
      // módulo corrente vem nulo — é o caso do aviso do §8, do
      // `[Avançar módulo]` desabilitado com motivo e do "Montar cronograma".
      turmaModularFalsa(id: 't-nova', nome: 'Eletricista 2026.2', alocados: 0),
    ],
    inativas: [
      // Vinda da TABELA e não da view: sem curso nem sala resolvidos, que é
      // exatamente o que `turmasInativas` devolve.
      turmaModularFalsa(
        id: 't-antiga',
        nome: 'Eletricista 2024.1',
        alocados: 0,
        cursoNome: '',
        salaNome: '',
      ),
    ],
    cronograma: [
      moduloDaTurmaFalso(
        id: 'cr-1',
        turmaId: 't-2026',
        moduloId: 'mod-1',
        nome: 'Módulo 1 — Comandos elétricos',
        ordem: 1,
        dataInicio: DateTime(2026, 6, 12),
        prevConclusao: DateTime(2026, 8, 10),
        concluido: true,
      ),
      moduloDaTurmaFalso(
        id: 'cr-2',
        turmaId: 't-2026',
        moduloId: 'mod-2',
        nome: 'Módulo 2 — Instalações prediais',
        ordem: 2,
        dataInicio: DateTime(2026, 8, 11),
        prevConclusao: DateTime(2026, 10, 10),
        corrente: true,
      ),
      // O terceiro sem datas: é a forma da fixture do banco, e é o que o avanço
      // preenche com o passo médio da turma.
      moduloDaTurmaFalso(
        id: 'cr-3',
        turmaId: 't-2026',
        moduloId: 'mod-3',
        nome: 'Módulo 3 — Projetos',
        ordem: 3,
      ),
      moduloDaTurmaFalso(
        id: 'cr-4',
        turmaId: 't-2025',
        moduloId: 'mod-1',
        nome: 'Módulo 1 — Comandos elétricos',
        ordem: 1,
        dataInicio: DateTime(2025, 11, 10),
        prevConclusao: DateTime(2026, 7, 26),
        corrente: true,
        atrasado: true,
      ),
      moduloDaTurmaFalso(
        id: 'cr-5',
        turmaId: 't-cheia',
        moduloId: 'mod-dep-1',
        nome: 'Técnicas básicas',
        ordem: 1,
        corrente: true,
      ),
    ],
    alunos: [
      alunoDaTurmaFalso(
        alocacaoId: 'tma-1',
        turmaId: 't-2026',
        alunoId: 'al-3005',
        nome: 'Eduarda Lima',
        codigoSgf: '3005',
        dataEntrada: DateTime(2026, 7, 6),
      ),
      // Uma saída, para `motivo_saida` ter onde ser lido — é a única leitura do
      // sistema que responde "por que fulano não está mais aqui".
      alunoDaTurmaFalso(
        alocacaoId: 'tma-2',
        turmaId: 't-2026',
        alunoId: 'al-saiu',
        nome: 'Rafael Souza',
        dataEntrada: DateTime(2026, 3, 2),
        ativo: false,
        motivoSaida: 'mudou de cidade',
      ),
      for (var i = 1; i <= 16; i++)
        alunoDaTurmaFalso(
          alocacaoId: 'tma-cheia-$i',
          turmaId: 't-cheia',
          alunoId: 'al-cheia-$i',
          nome: 'Aluna Depilação $i',
          dataEntrada: DateTime(2026, 2, 10),
        ),
    ],
  );

  final List<TurmaModular> turmas_;
  final List<TurmaModular> inativas_;
  final List<ModuloDaTurma> cronograma_;
  final List<AlunoDaTurmaModular> alunos_;

  /// O card 4.4 mediu que teste instantâneo não constrói a tela no estado em que
  /// o banco a apanha: durante a recarga o `AsyncValue` ainda carrega o valor
  /// anterior. O atraso é o que permite reproduzir isso.
  final Duration atrasoLeitura;

  /// Quando não nulo, **toda leitura** levanta este erro.
  ErroApp? erroDeLeitura;

  /// O erro que `admitir` levanta — `TURMA_LOTADA`, `ALUNO_NAO_MODULAR`,
  /// `ALUNO_INATIVO`. Nulo = caminho feliz.
  ErroApp? erroAoAdmitir;

  /// O erro que `avancar` levanta — `TURMA_SEM_CRONOGRAMA`,
  /// `TURMA_SEM_MODULO_CORRENTE`, `SEM_PERMISSAO`. Nulo = caminho feliz.
  ErroApp? erroAoAvancar;

  final List<String> salvas = [];
  final List<String> excluidas = [];
  final List<String> admitidos = [];
  final List<String> removidos = [];
  final List<String> avancos = [];
  final List<String> modulosIncluidos = [];
  final List<String> datasSalvas = [];
  final List<String> modulosExcluidos = [];

  Future<void> _lerOuFalhar() async {
    final erro = erroDeLeitura;
    if (erro != null) throw erro;
    if (atrasoLeitura > Duration.zero) {
      await Future<void>.delayed(atrasoLeitura);
    }
  }

  @override
  Future<List<TurmaModular>> turmas() async {
    await _lerOuFalhar();
    return List.of(turmas_);
  }

  @override
  Future<List<TurmaModular>> turmasInativas() async {
    await _lerOuFalhar();
    return List.of(inativas_);
  }

  @override
  Future<List<ModuloDaTurma>> cronograma() async {
    await _lerOuFalhar();
    return List.of(cronograma_);
  }

  @override
  Future<List<AlunoDaTurmaModular>> alunos() async {
    await _lerOuFalhar();
    return List.of(alunos_);
  }

  @override
  Future<String> salvarTurma({
    String? id,
    required String nome,
    required String cursoId,
    required String salaId,
    required int capacidade,
    required DateTime dataInicio,
    required bool ativo,
  }) async {
    salvas.add('${id ?? 'nova'}|$nome|$capacidade|$ativo');
    return id ?? 'turma-nova';
  }

  @override
  Future<void> excluirTurma(String id) async => excluidas.add(id);

  @override
  Future<void> incluirModulos({
    required String turmaId,
    required List<String> moduloIds,
  }) async {
    modulosIncluidos.add('$turmaId|${moduloIds.join(',')}');
    // Reproduz o efeito: as linhas passam a existir, sem datas. Sem isto o
    // teste do "Montar cronograma" mediria um mundo em que salvar não muda nada.
    for (final moduloId in moduloIds) {
      cronograma_.add(
        moduloDaTurmaFalso(
          id: 'cr-$turmaId-$moduloId',
          turmaId: turmaId,
          moduloId: moduloId,
          nome: moduloId,
          ordem: cronograma_.length + 1,
          corrente: !cronograma_.any((m) => m.turmaId == turmaId),
        ),
      );
    }
  }

  @override
  Future<void> salvarDatasModulo({
    required String cronogramaId,
    DateTime? dataInicio,
    DateTime? prevConclusao,
  }) async {
    datasSalvas.add(
      '$cronogramaId|${dataInicio == null ? '' : dataIso(dataInicio)}'
      '|${prevConclusao == null ? '' : dataIso(prevConclusao)}',
    );
    for (var i = 0; i < cronograma_.length; i++) {
      final m = cronograma_[i];
      if (m.id != cronogramaId) continue;
      cronograma_[i] = ModuloDaTurma(
        id: m.id,
        turmaId: m.turmaId,
        moduloId: m.moduloId,
        moduloNome: m.moduloNome,
        moduloOrdem: m.moduloOrdem,
        materialId: m.materialId,
        dataInicio: dataInicio,
        prevConclusao: prevConclusao,
        concluido: m.concluido,
        corrente: m.corrente,
        atrasado: m.atrasado,
      );
    }
  }

  @override
  Future<void> excluirModulo(String cronogramaId) async {
    modulosExcluidos.add(cronogramaId);
    cronograma_.removeWhere((m) => m.id == cronogramaId);
  }

  @override
  Future<String> admitir({
    required String turmaId,
    required String alunoId,
  }) async {
    admitidos.add('$turmaId|$alunoId');
    final erro = erroAoAdmitir;
    if (erro != null) throw erro;
    alunos_.add(
      alunoDaTurmaFalso(
        alocacaoId: 'tma-$alunoId',
        turmaId: turmaId,
        alunoId: alunoId,
        nome: alunoId,
        dataEntrada: hojeSaoPaulo(),
      ),
    );
    _mexerLotacao(turmaId, 1);
    return 'tma-$alunoId';
  }

  @override
  Future<void> remover({
    required String turmaId,
    required String alunoId,
    String? motivo,
  }) async {
    removidos.add('$turmaId|$alunoId|${motivo ?? ''}');
    for (var i = 0; i < alunos_.length; i++) {
      final a = alunos_[i];
      if (a.turmaId != turmaId || a.alunoId != alunoId || !a.ativo) continue;
      alunos_[i] = AlunoDaTurmaModular(
        alocacaoId: a.alocacaoId,
        turmaId: a.turmaId,
        alunoId: a.alunoId,
        alunoNome: a.alunoNome,
        codigoSgf: a.codigoSgf,
        alunoStatus: a.alunoStatus,
        metodoId: a.metodoId,
        dataEntrada: a.dataEntrada,
        ativo: false,
        motivoSaida: motivo,
      );
      _mexerLotacao(turmaId, -1);
    }
  }

  @override
  Future<String?> avancar({
    required String turmaId,
    required DateTime dataConclusao,
  }) async {
    avancos.add('$turmaId|${dataIso(dataConclusao)}');
    final erro = erroAoAvancar;
    if (erro != null) throw erro;

    // Reproduz `fn_turma_modular_avancar`: conclui o corrente com a data REAL e
    // abre o seguinte por ordem. Devolve NULO quando não há seguinte — é o
    // estado "turma terminou", e é o que a tela precisa distinguir.
    final daTurma = [
      for (final m in cronograma_)
        if (m.turmaId == turmaId) m,
    ]..sort((a, b) => a.moduloOrdem.compareTo(b.moduloOrdem));
    final naoConcluidos = [
      for (final m in daTurma)
        if (!m.concluido) m,
    ];
    if (naoConcluidos.isEmpty) return null;
    final corrente = naoConcluidos.first;
    final proximo = naoConcluidos.length > 1 ? naoConcluidos[1] : null;

    for (var i = 0; i < cronograma_.length; i++) {
      final m = cronograma_[i];
      if (m.id == corrente.id) {
        cronograma_[i] = _copiar(
          m,
          concluido: true,
          corrente: false,
          prevConclusao: dataConclusao,
        );
      } else if (proximo != null && m.id == proximo.id) {
        cronograma_[i] = _copiar(m, corrente: true);
      }
    }
    _mexerModuloCorrente(turmaId, proximo);
    return proximo?.moduloId;
  }

  void _mexerLotacao(String turmaId, int delta) {
    for (var i = 0; i < turmas_.length; i++) {
      final t = turmas_[i];
      if (t.id != turmaId) continue;
      final alocados = t.alocados + delta;
      turmas_[i] = turmaModularFalsa(
        id: t.id,
        nome: t.nome,
        cursoId: t.cursoId,
        cursoNome: t.cursoNome,
        salaId: t.salaId,
        salaNome: t.salaNome,
        capacidade: t.capacidade,
        alocados: alocados,
        moduloCorrenteId: t.moduloCorrenteId,
        moduloCorrenteNome: t.moduloCorrenteNome,
        moduloCorrenteOrdem: t.moduloCorrenteOrdem,
        moduloCorrenteInicio: t.moduloCorrenteInicio,
        moduloCorrentePrevConclusao: t.moduloCorrentePrevConclusao,
        moduloAtrasado: t.moduloAtrasado,
      );
    }
  }

  void _mexerModuloCorrente(String turmaId, ModuloDaTurma? proximo) {
    for (var i = 0; i < turmas_.length; i++) {
      final t = turmas_[i];
      if (t.id != turmaId) continue;
      turmas_[i] = turmaModularFalsa(
        id: t.id,
        nome: t.nome,
        cursoId: t.cursoId,
        cursoNome: t.cursoNome,
        salaId: t.salaId,
        salaNome: t.salaNome,
        capacidade: t.capacidade,
        alocados: t.alocados,
        moduloCorrenteId: proximo?.moduloId,
        moduloCorrenteNome: proximo?.moduloNome,
        moduloCorrenteOrdem: proximo?.moduloOrdem,
        moduloCorrenteInicio: proximo?.dataInicio,
        moduloCorrentePrevConclusao: proximo?.prevConclusao,
      );
    }
  }
}

ModuloDaTurma _copiar(
  ModuloDaTurma m, {
  bool? concluido,
  bool? corrente,
  DateTime? prevConclusao,
}) => ModuloDaTurma(
  id: m.id,
  turmaId: m.turmaId,
  moduloId: m.moduloId,
  moduloNome: m.moduloNome,
  moduloOrdem: m.moduloOrdem,
  materialId: m.materialId,
  dataInicio: m.dataInicio,
  prevConclusao: prevConclusao ?? m.prevConclusao,
  concluido: concluido ?? m.concluido,
  corrente: corrente ?? m.corrente,
  atrasado: m.atrasado,
);

/// Uma linha de `v_turma_modular_lotacao`. `vagas_livres` com piso zero, como a
/// view: turma acima da capacidade é estado real.
TurmaModular turmaModularFalsa({
  required String id,
  required String nome,
  String cursoId = 'c-ele',
  String cursoNome = 'Eletricista Instalador',
  String salaId = 's-ele',
  String salaNome = 'Sala Eletricista',
  int capacidade = 15,
  int alocados = 0,
  String? moduloCorrenteId,
  String? moduloCorrenteNome,
  int? moduloCorrenteOrdem,
  DateTime? moduloCorrenteInicio,
  DateTime? moduloCorrentePrevConclusao,
  bool moduloAtrasado = false,
}) => TurmaModular(
  id: id,
  nome: nome,
  cursoId: cursoId,
  cursoNome: cursoNome,
  salaId: salaId,
  salaNome: salaNome,
  capacidade: capacidade,
  alocados: alocados,
  vagasLivres: alocados >= capacidade ? 0 : capacidade - alocados,
  moduloCorrenteId: moduloCorrenteId,
  moduloCorrenteNome: moduloCorrenteNome,
  moduloCorrenteOrdem: moduloCorrenteOrdem,
  moduloCorrenteInicio: moduloCorrenteInicio,
  moduloCorrentePrevConclusao: moduloCorrentePrevConclusao,
  moduloAtrasado: moduloAtrasado,
);

/// Uma linha de `v_turma_modular_cronograma`.
ModuloDaTurma moduloDaTurmaFalso({
  required String id,
  required String turmaId,
  required String moduloId,
  required String nome,
  required int ordem,
  DateTime? dataInicio,
  DateTime? prevConclusao,
  bool concluido = false,
  bool corrente = false,
  bool atrasado = false,
}) => ModuloDaTurma(
  id: id,
  turmaId: turmaId,
  moduloId: moduloId,
  moduloNome: nome,
  moduloOrdem: ordem,
  materialId: 'mat-$moduloId',
  dataInicio: dataInicio,
  prevConclusao: prevConclusao,
  concluido: concluido,
  corrente: corrente,
  atrasado: atrasado,
);

/// Uma linha de `v_turma_modular_aluno`.
AlunoDaTurmaModular alunoDaTurmaFalso({
  required String alocacaoId,
  required String turmaId,
  required String alunoId,
  required String nome,
  String? codigoSgf,
  String status = 'ATIVO',
  String metodoId = 'm-mod',
  DateTime? dataEntrada,
  bool ativo = true,
  String? motivoSaida,
}) => AlunoDaTurmaModular(
  alocacaoId: alocacaoId,
  turmaId: turmaId,
  alunoId: alunoId,
  alunoNome: nome,
  codigoSgf: codigoSgf,
  alunoStatus: status,
  metodoId: metodoId,
  dataEntrada: dataEntrada ?? DateTime(2026, 7, 6),
  ativo: ativo,
  motivoSaida: motivoSaida,
);
