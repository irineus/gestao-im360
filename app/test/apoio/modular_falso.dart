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
/// corrente e abre o seguinte — e, fechado o último módulo, abre o ciclo
/// seguinte, porque a turma é cíclica (card 9.2,88). Sem isso os testes mediriam um mundo em que
/// salvar não muda nada — a lição que o card 5.4 escreveu.
class ModularFalso implements ModularRepositorio {
  ModularFalso({
    List<TurmaModular>? turmas,
    List<TurmaModular>? inativas,
    List<ModuloDaTurma>? cronograma,
    List<AlunoDaTurmaModular>? alunos,
    List<ProgressoAlunoModular>? progresso,
    this.atrasoLeitura = Duration.zero,
  }) : turmas_ = List.of(turmas ?? const []),
       progresso_ = List.of(progresso ?? const []),
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
        proximoModuloId: 'mod-3',
        proximoModuloNome: 'Módulo 3 — Projetos',
      ),
      // Vazia e com o módulo corrente VENCIDO — é o `modulo_atrasado` com o
      // outro valor, a mesma escolha do seed. Cronograma PARCIAL (só o módulo
      // 1): é a turma do "Acrescentar 2 módulos".
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
        // O início REAL da turma, que a view de lotação traz desde o 9.2,7.
        dataInicio: DateTime(2025, 11, 9),
        proximoModuloId: 'mod-2',
        proximoModuloNome: 'Módulo 2 — Instalações prediais',
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

  /// Só a leitura das inativas falha (card 9.2,62).
  Object? falhaInativas;
  final List<ModuloDaTurma> cronograma_;
  final List<AlunoDaTurmaModular> alunos_;

  /// `v_aluno_modular_progresso` (card 9.2,90).
  final List<ProgressoAlunoModular> progresso_;

  /// `v_aluno_modular_agenda`, pela chave `turma|módulo`: a quem o módulo
  /// ainda falta. **Sem entrada = falta a todo aluno ativo da turma** — é o
  /// caso da turma em que ninguém fez módulo nenhum.
  final Map<String, Set<String>> aQuemFalta = {};

  /// Só a leitura de `alunosAQuemFalta` falha.
  ErroApp? erroAQuemFalta;

  /// O catálogo que `fn_turma_modular_avancar` e `fn_turma_modular_abrir_ciclo`
  /// leem para completar e abrir ciclos — o mesmo do `CatalogoFalso`.
  static const _catalogo = <String, List<(String, String, int)>>{
    'c-ele': [
      ('mod-1', 'Módulo 1 — Comandos elétricos', 1),
      ('mod-2', 'Módulo 2 — Instalações prediais', 2),
      ('mod-3', 'Módulo 3 — Projetos', 3),
    ],
    'c-dep': [('mod-dep-1', 'Técnicas básicas', 1)],
  };

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

  /// `aluno_modulo` por aluno (card 9.2,905) — o que cada um já fez.
  final Map<String, List<ModuloFeito>> feitos_ = {};

  /// As linhas NÃO feitas de `v_aluno_modular_modulo` por aluno, na ordem da
  /// turma. Vazio para quem não está em turma.
  final Map<String, List<ModuloAFazer>> aFazer_ = {};

  /// `aluno|módulo|data|observação` de cada `registrarModulo`.
  final List<String> modulosRegistrados = [];

  /// `aluno|módulo|motivo` de cada `removerModulo`.
  final List<String> modulosTirados = [];

  /// O erro que `registrarModulo` levanta — `MODULO_JA_REGISTRADO`,
  /// `SEM_PERMISSAO`. Nulo = caminho feliz.
  ErroApp? erroAoRegistrarModulo;

  /// O `ciclo` de cada `incluirModulos`, na ordem das chamadas (card 9.2,90).
  final List<int> ciclosIncluidos = [];

  /// O `p_modulo_entrada_id` de cada `admitir` — nulo = o atual da turma.
  final List<String?> entradas = [];

  /// `turma|data` de cada `abrirCiclo`.
  final List<String> ciclosAbertos = [];

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
    final falha = falhaInativas;
    if (falha != null) throw falha;
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
  Future<List<ProgressoAlunoModular>> progresso() async {
    await _lerOuFalhar();
    return List.of(progresso_);
  }

  @override
  Future<Set<String>> alunosAQuemFalta({
    required String turmaId,
    required String moduloId,
  }) async {
    await _lerOuFalhar();
    final erro = erroAQuemFalta;
    if (erro != null) throw erro;
    return aQuemFalta['$turmaId|$moduloId'] ??
        {
          for (final a in alunos_)
            if (a.turmaId == turmaId && a.ativo) a.alunoId,
        };
  }

  @override
  Future<List<ModuloFeito>> modulosFeitos(String alunoId) async {
    await _lerOuFalhar();
    return List.of(feitos_[alunoId] ?? const []);
  }

  @override
  Future<List<ModuloAFazer>> modulosAFazer(String alunoId) async {
    await _lerOuFalhar();
    return List.of(aFazer_[alunoId] ?? const []);
  }

  @override
  Future<void> registrarModulo({
    required String alunoId,
    required String moduloId,
    required DateTime dataConclusao,
    String? observacao,
  }) async {
    modulosRegistrados.add(
      '$alunoId|$moduloId|${dataIso(dataConclusao)}|${observacao ?? ''}',
    );
    final erro = erroAoRegistrarModulo;
    if (erro != null) throw erro;
    // Reproduz `fn_aluno_modulo_registrar`: o módulo deixa de faltar e passa a
    // constar como feito, com origem MANUAL.
    final faltavam = aFazer_[alunoId] ?? <ModuloAFazer>[];
    final era = faltavam.where((m) => m.moduloId == moduloId).firstOrNull;
    aFazer_[alunoId] = [
      for (final m in faltavam)
        if (m.moduloId != moduloId) m,
    ];
    (feitos_[alunoId] ??= []).add(
      ModuloFeito(
        moduloId: moduloId,
        moduloNome: era?.moduloNome ?? moduloId,
        moduloOrdem: era?.moduloOrdem ?? 0,
        cursoNome: '',
        dataConclusao: dataConclusao,
        origem: 'MANUAL',
        observacao: observacao,
      ),
    );
  }

  @override
  Future<void> removerModulo({
    required String alunoId,
    required String moduloId,
    required String motivo,
  }) async {
    modulosTirados.add('$alunoId|$moduloId|$motivo');
    feitos_[alunoId] = [
      for (final m in feitos_[alunoId] ?? const <ModuloFeito>[])
        if (m.moduloId != moduloId) m,
    ];
  }

  @override
  Future<String> salvarTurma({
    String? id,
    required String nome,
    required String cursoId,
    required String salaId,
    required int capacidade,
    DateTime? dataInicio,
    required bool ativo,
  }) async {
    salvas.add('${id ?? 'nova'}|$nome|$capacidade|$ativo');
    // ⚠️ Guarda a data COMO O BANCO guardaria: a criação grava, e a edição só
    // grava se alguém mandar uma — que é justamente o que não pode acontecer
    // (item A2). Sem reproduzir isso aqui, o teste mediria um mundo em que
    // `update` nunca toca a coluna.
    final chave = id ?? 'turma-nova';
    if (dataInicio != null) datasInicio[chave] = dataInicio;
    return chave;
  }

  /// A `data_inicio` de cada turma como o falso a tem — é o que o teste da
  /// edição relê para provar que salvar sem mudar nada não a moveu.
  final Map<String, DateTime> datasInicio = {};

  @override
  Future<void> excluirTurma(String id) async => excluidas.add(id);

  @override
  Future<void> incluirModulos({
    required String turmaId,
    required List<String> moduloIds,
    int ciclo = 1,
  }) async {
    modulosIncluidos.add('$turmaId|${moduloIds.join(',')}');
    ciclosIncluidos.add(ciclo);
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
          ciclo: ciclo,
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
        ciclo: m.ciclo,
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
    String? moduloEntradaId,
  }) async {
    admitidos.add('$turmaId|$alunoId');
    entradas.add(moduloEntradaId);
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

    // Reproduz `fn_turma_modular_avancar` (card 9.2,88): conclui o corrente
    // com a data REAL, completa o ciclo com os módulos seguintes do catálogo e,
    // fechado o último, abre o ciclo seguinte. A turma é cíclica: só devolve
    // nulo quando não há o que abrir (curso fora do catálogo do falso).
    final naoConcluidos = _naoConcluidos(turmaId);
    if (naoConcluidos.isEmpty) return null;
    final corrente = naoConcluidos.first;
    final i = cronograma_.indexWhere((m) => m.id == corrente.id);
    cronograma_[i] = _copiar(
      corrente,
      concluido: true,
      corrente: false,
      prevConclusao: dataConclusao,
    );

    final catalogo = _catalogoDa(turmaId);
    _incluirDoCatalogo(
      turmaId,
      corrente.ciclo,
      catalogo.where((m) => m.$3 > corrente.moduloOrdem),
    );
    if (_naoConcluidos(turmaId).isEmpty) {
      _incluirDoCatalogo(turmaId, corrente.ciclo + 1, catalogo);
    }
    return _abrir(turmaId);
  }

  @override
  Future<String> abrirCiclo({
    required String turmaId,
    required DateTime dataInicio,
  }) async {
    ciclosAbertos.add('$turmaId|${dataIso(dataInicio)}');
    final ultimo = cronograma_
        .where((m) => m.turmaId == turmaId)
        .fold<int>(0, (maior, m) => m.ciclo > maior ? m.ciclo : maior);
    _incluirDoCatalogo(turmaId, ultimo + 1, _catalogoDa(turmaId));
    final primeiro = _naoConcluidos(turmaId).first;
    final i = cronograma_.indexWhere((m) => m.id == primeiro.id);
    cronograma_[i] = _copiar(primeiro, dataInicio: dataInicio);
    return _abrir(turmaId)!;
  }

  /// As linhas não concluídas da turma por (ciclo, ordem) — a ordem com que o
  /// banco escolhe o corrente.
  List<ModuloDaTurma> _naoConcluidos(String turmaId) =>
      [
        for (final m in cronograma_)
          if (m.turmaId == turmaId && !m.concluido) m,
      ]..sort((a, b) {
        final ciclo = a.ciclo.compareTo(b.ciclo);
        return ciclo != 0 ? ciclo : a.moduloOrdem.compareTo(b.moduloOrdem);
      });

  /// Os módulos do curso da turma: o catálogo do falso e, para curso que ele
  /// não conhece, os módulos que o cronograma da turma já tem.
  List<(String, String, int)> _catalogoDa(String turmaId) {
    final turma = turmas_.where((t) => t.id == turmaId).firstOrNull;
    final doCatalogo = _catalogo[turma?.cursoId];
    if (doCatalogo != null) return doCatalogo;
    final vistos = <String, (String, String, int)>{};
    for (final m in cronograma_) {
      if (m.turmaId == turmaId) {
        vistos[m.moduloId] = (m.moduloId, m.moduloNome, m.moduloOrdem);
      }
    }
    return vistos.values.toList()..sort((a, b) => a.$3.compareTo(b.$3));
  }

  void _incluirDoCatalogo(
    String turmaId,
    int ciclo,
    Iterable<(String, String, int)> modulos,
  ) {
    for (final (id, nome, ordem) in modulos) {
      final existe = cronograma_.any(
        (m) => m.turmaId == turmaId && m.moduloId == id && m.ciclo == ciclo,
      );
      if (existe) continue;
      cronograma_.add(
        moduloDaTurmaFalso(
          id: 'cr-$turmaId-$id-c$ciclo',
          turmaId: turmaId,
          moduloId: id,
          nome: nome,
          ordem: ordem,
          ciclo: ciclo,
        ),
      );
    }
  }

  /// Marca o primeiro não concluído como corrente e reflete na lotação.
  String? _abrir(String turmaId) {
    final abertos = _naoConcluidos(turmaId);
    final proximo = abertos.isEmpty ? null : abertos.first;
    if (proximo != null) {
      final i = cronograma_.indexWhere((m) => m.id == proximo.id);
      cronograma_[i] = _copiar(proximo, corrente: true);
    }
    _mexerModuloCorrente(turmaId, proximo);
    return proximo?.moduloId;
  }

  void _mexerLotacao(String turmaId, int delta) {
    for (var i = 0; i < turmas_.length; i++) {
      final t = turmas_[i];
      if (t.id != turmaId) continue;
      turmas_[i] = _copiarTurma(t, alocados: t.alocados + delta);
    }
  }

  void _mexerModuloCorrente(String turmaId, ModuloDaTurma? corrente) {
    for (var i = 0; i < turmas_.length; i++) {
      final t = turmas_[i];
      if (t.id != turmaId) continue;
      // O próximo do rodízio: o de ordem seguinte e, depois do último, o
      // primeiro. Nulo em curso de um módulo só — como a view.
      final catalogo = _catalogoDa(turmaId);
      (String, String, int)? proximo;
      if (corrente != null && catalogo.length > 1) {
        final depois = catalogo.where((m) => m.$3 > corrente.moduloOrdem);
        proximo = depois.isEmpty ? catalogo.first : depois.first;
      }
      turmas_[i] = turmaModularFalsa(
        id: t.id,
        nome: t.nome,
        cursoId: t.cursoId,
        cursoNome: t.cursoNome,
        salaId: t.salaId,
        salaNome: t.salaNome,
        capacidade: t.capacidade,
        alocados: t.alocados,
        dataInicio: t.dataInicio,
        moduloCorrenteId: corrente?.moduloId,
        moduloCorrenteNome: corrente?.moduloNome,
        moduloCorrenteOrdem: corrente?.moduloOrdem,
        moduloCorrenteInicio: corrente?.dataInicio,
        moduloCorrentePrevConclusao: corrente?.prevConclusao,
        moduloCorrenteCiclo: corrente?.ciclo,
        proximoModuloId: proximo?.$1,
        proximoModuloNome: proximo?.$2,
      );
    }
  }
}

/// A turma com outra lotação e **todo o resto igual** — inclusive o aviso de
/// troca e o ciclo, que a versão anterior deste falso perdia.
TurmaModular _copiarTurma(TurmaModular t, {required int alocados}) =>
    turmaModularFalsa(
      id: t.id,
      nome: t.nome,
      cursoId: t.cursoId,
      cursoNome: t.cursoNome,
      salaId: t.salaId,
      salaNome: t.salaNome,
      capacidade: t.capacidade,
      alocados: alocados,
      dataInicio: t.dataInicio,
      moduloCorrenteId: t.moduloCorrenteId,
      moduloCorrenteNome: t.moduloCorrenteNome,
      moduloCorrenteOrdem: t.moduloCorrenteOrdem,
      moduloCorrenteInicio: t.moduloCorrenteInicio,
      moduloCorrentePrevConclusao: t.moduloCorrentePrevConclusao,
      moduloAtrasado: t.moduloAtrasado,
      moduloCorrenteCiclo: t.moduloCorrenteCiclo,
      proximoModuloId: t.proximoModuloId,
      proximoModuloNome: t.proximoModuloNome,
      proximoMaterialId: t.proximoMaterialId,
      proximoMaterialNome: t.proximoMaterialNome,
      trocaDeLivro: t.trocaDeLivro,
      diasParaTroca: t.diasParaTroca,
      situacaoTroca: t.situacaoTroca,
    );

ModuloDaTurma _copiar(
  ModuloDaTurma m, {
  bool? concluido,
  bool? corrente,
  DateTime? dataInicio,
  DateTime? prevConclusao,
}) => ModuloDaTurma(
  id: m.id,
  turmaId: m.turmaId,
  moduloId: m.moduloId,
  moduloNome: m.moduloNome,
  moduloOrdem: m.moduloOrdem,
  materialId: m.materialId,
  dataInicio: dataInicio ?? m.dataInicio,
  prevConclusao: prevConclusao ?? m.prevConclusao,
  concluido: concluido ?? m.concluido,
  corrente: corrente ?? m.corrente,
  atrasado: m.atrasado,
  ciclo: m.ciclo,
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
  DateTime? dataInicio,
  // card 9.2,85/9.2,86 — o aviso de troca de módulo
  String? proximoModuloNome,
  String? proximoMaterialId,
  String? proximoMaterialNome,
  bool? trocaDeLivro,
  int? diasParaTroca,
  SituacaoTroca? situacaoTroca,
  // card 9.2,88/9.2,90 — a turma em rodízio. O ciclo do corrente vem da view
  // sempre que há corrente; aqui, 1 por omissão, como a turma recém-montada.
  int? moduloCorrenteCiclo,
  String? proximoModuloId,
}) => TurmaModular(
  moduloCorrenteCiclo:
      moduloCorrenteCiclo ?? (moduloCorrenteId == null ? null : 1),
  proximoModuloId: proximoModuloId,
  dataInicio: dataInicio,
  proximoModuloNome: proximoModuloNome,
  proximoMaterialId: proximoMaterialId,
  proximoMaterialNome: proximoMaterialNome,
  trocaDeLivro: trocaDeLivro,
  diasParaTroca: diasParaTroca,
  situacaoTroca: situacaoTroca,
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
  int ciclo = 1,
}) => ModuloDaTurma(
  ciclo: ciclo,
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
