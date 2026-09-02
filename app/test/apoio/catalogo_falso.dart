import 'package:gestao_im360/catalogo/catalogo.dart';
import 'package:gestao_im360/catalogo/catalogo_repositorio.dart';

/// Repositório em memória — o teste injeta **dados**, não um cliente HTTP
/// falso (card 2.8 §9.3). A forma dos dados é a da escola-fixture do card 4.1
/// (`supabase/seed.sql`): códigos de material repetidos entre métodos, o combo
/// de Informática com dois cursos, três módulos sobre o mesmo livro.
class CatalogoFalso implements CatalogoRepositorio {
  CatalogoFalso({
    List<Metodo>? metodos,
    List<MaterialDidatico>? materiais,
    List<Curso>? cursos,
    Map<String, List<LinhaOrdenada>>? sequencias,
    List<Modulo>? modulos,
    List<Combo>? combos,
    Map<String, List<LinhaOrdenada>>? composicoes,
  }) : metodos_ = List.of(metodos ?? const []),
       materiais_ = List.of(materiais ?? const []),
       cursos_ = List.of(cursos ?? const []),
       sequencias = {
         for (final e in (sequencias ?? const {}).entries)
           e.key: List.of(e.value),
       },
       modulos_ = List.of(modulos ?? const []),
       combos_ = List.of(combos ?? const []),
       composicoes = {
         for (final e in (composicoes ?? const {}).entries)
           e.key: List.of(e.value),
       };

  /// A escola-fixture, como o card 4.1 a escreveu.
  factory CatalogoFalso.fixture() => CatalogoFalso(
    metodos: const [
      Metodo(id: 'm-ing', codigo: 'INGLES', nome: 'Inglês'),
      Metodo(id: 'm-int', codigo: 'INTERATIVO', nome: 'Interativo'),
      Metodo(id: 'm-mod', codigo: 'MODULAR', nome: 'Modular'),
    ],
    materiais: const [
      MaterialDidatico(
        id: 'mat-int-01',
        metodoId: 'm-int',
        codigo: '01',
        nome: 'Informática Essencial 1',
        categoria: 'APOSTILA',
        estoqueMinimo: 2,
      ),
      MaterialDidatico(
        id: 'mat-int-02',
        metodoId: 'm-int',
        codigo: '02',
        nome: 'Informática Essencial 2',
        categoria: 'APOSTILA',
        estoqueMinimo: 1,
      ),
      MaterialDidatico(
        id: 'mat-int-03',
        metodoId: 'm-int',
        codigo: '03',
        nome: 'Informática Avançada 1',
        categoria: 'APOSTILA',
        estoqueMinimo: 1,
      ),
      MaterialDidatico(
        id: 'mat-ing-01',
        metodoId: 'm-ing',
        codigo: '01',
        nome: 'English Book 1',
        categoria: 'APOSTILA',
        estoqueMinimo: 1,
      ),
      MaterialDidatico(
        id: 'mat-ing-02',
        metodoId: 'm-ing',
        codigo: '02',
        nome: 'English Book 2',
        categoria: 'APOSTILA',
        estoqueMinimo: 2,
      ),
      MaterialDidatico(
        id: 'mat-mod-01',
        metodoId: 'm-mod',
        codigo: '01',
        nome: 'Eletricista Instalador',
        categoria: 'LIVRO',
        estoqueMinimo: 1,
      ),
    ],
    cursos: const [
      Curso(id: 'c-ele', metodoId: 'm-mod', nome: 'Eletricista Instalador'),
      Curso(id: 'c-av', metodoId: 'm-int', nome: 'Informática Avançada'),
      Curso(id: 'c-ess', metodoId: 'm-int', nome: 'Informática Essencial'),
      Curso(id: 'c-kids', metodoId: 'm-ing', nome: 'Inglês Kids'),
    ],
    sequencias: {
      'c-ess': const [
        LinhaOrdenada(id: 'cm-1', filhoId: 'mat-int-01', ordem: 1),
        LinhaOrdenada(id: 'cm-2', filhoId: 'mat-int-02', ordem: 2),
      ],
      'c-av': const [
        LinhaOrdenada(id: 'cm-3', filhoId: 'mat-int-03', ordem: 1),
      ],
      'c-kids': const [
        LinhaOrdenada(id: 'cm-4', filhoId: 'mat-ing-01', ordem: 1),
        LinhaOrdenada(id: 'cm-5', filhoId: 'mat-ing-02', ordem: 2),
      ],
      'c-ele': const [
        LinhaOrdenada(id: 'cm-6', filhoId: 'mat-mod-01', ordem: 1),
      ],
    },
    modulos: const [
      Modulo(
        id: 'mod-1',
        cursoId: 'c-ele',
        materialId: 'mat-mod-01',
        nome: 'Módulo 1 — Comandos elétricos',
        ordem: 1,
      ),
      Modulo(
        id: 'mod-2',
        cursoId: 'c-ele',
        materialId: 'mat-mod-01',
        nome: 'Módulo 2 — Instalações prediais',
        ordem: 2,
      ),
      Modulo(
        id: 'mod-3',
        cursoId: 'c-ele',
        materialId: 'mat-mod-01',
        nome: 'Módulo 3 — Projetos',
        ordem: 3,
      ),
    ],
    combos: const [
      Combo(id: 'cb-ele', metodoId: 'm-mod', nome: 'Eletricista Completo'),
      Combo(id: 'cb-info', metodoId: 'm-int', nome: 'Informática Completo'),
      Combo(id: 'cb-kids', metodoId: 'm-ing', nome: 'Inglês Kids Completo'),
    ],
    composicoes: {
      'cb-info': const [
        LinhaOrdenada(id: 'cc-1', filhoId: 'c-ess', ordem: 1),
        LinhaOrdenada(id: 'cc-2', filhoId: 'c-av', ordem: 2),
      ],
      'cb-kids': const [LinhaOrdenada(id: 'cc-3', filhoId: 'c-kids', ordem: 1)],
      'cb-ele': const [LinhaOrdenada(id: 'cc-4', filhoId: 'c-ele', ordem: 1)],
    },
  );

  final List<Metodo> metodos_;
  final List<MaterialDidatico> materiais_;
  final List<Curso> cursos_;
  final Map<String, List<LinhaOrdenada>> sequencias;
  final List<Modulo> modulos_;
  final List<Combo> combos_;
  final Map<String, List<LinhaOrdenada>> composicoes;

  /// Se definido, toda **escrita** lança isto — é como o teste simula o banco
  /// recusando (unique, FK, RLS).
  Object? falhaAoGravar;

  /// Se definido, toda **leitura** lança isto.
  Object? falhaAoLer;

  /// Atraso de cada leitura. Zero deixa a recarga terminar antes do frame
  /// seguinte — e aí a tela nunca é construída no estado "recarregando com o
  /// valor anterior", que é onde o banco de verdade a apanha.
  Duration atrasoLeitura = Duration.zero;

  /// Registro do que foi chamado, na ordem.
  final chamadas = <String>[];

  int _contador = 0;
  String _novoId(String prefixo) => '$prefixo-novo-${++_contador}';

  Future<T> _ler<T>(String nome, T valor) async {
    chamadas.add(nome);
    if (atrasoLeitura > Duration.zero) await Future.delayed(atrasoLeitura);
    final falha = falhaAoLer;
    if (falha != null) throw falha;
    return valor;
  }

  Future<T> _gravar<T>(String nome, T Function() acao) async {
    chamadas.add(nome);
    final falha = falhaAoGravar;
    if (falha != null) throw falha;
    return acao();
  }

  @override
  Future<List<Metodo>> metodos() => _ler('metodos', List.of(metodos_));

  @override
  Future<void> salvarMetodo(Metodo metodo) => _gravar('salvarMetodo', () {
    final i = metodos_.indexWhere((m) => m.id == metodo.id);
    metodos_[i] = metodo;
  });

  @override
  Future<List<MaterialDidatico>> materiais() =>
      _ler('materiais', List.of(materiais_));

  @override
  Future<MaterialDidatico> salvarMaterial(MaterialDidatico material) =>
      _gravar('salvarMaterial', () {
        if (material.id == null) {
          final novo = MaterialDidatico(
            id: _novoId('mat'),
            metodoId: material.metodoId,
            codigo: material.codigo,
            nome: material.nome,
            categoria: material.categoria,
            estoqueMinimo: material.estoqueMinimo,
            ativo: material.ativo,
          );
          materiais_.add(novo);
          return novo;
        }
        final i = materiais_.indexWhere((m) => m.id == material.id);
        materiais_[i] = material;
        return material;
      });

  @override
  Future<void> excluirMaterial(String id) => _gravar(
    'excluirMaterial',
    () => materiais_.removeWhere((m) => m.id == id),
  );

  @override
  Future<List<Curso>> cursos() => _ler('cursos', List.of(cursos_));

  @override
  Future<Curso> salvarCurso(Curso curso) => _gravar('salvarCurso', () {
    if (curso.id == null) {
      final novo = Curso(
        id: _novoId('c'),
        metodoId: curso.metodoId,
        nome: curso.nome,
        ativo: curso.ativo,
      );
      cursos_.add(novo);
      return novo;
    }
    final i = cursos_.indexWhere((c) => c.id == curso.id);
    cursos_[i] = curso;
    return curso;
  });

  @override
  Future<void> excluirCurso(String id) =>
      _gravar('excluirCurso', () => cursos_.removeWhere((c) => c.id == id));

  @override
  Future<Map<String, int>> apostilasPorCurso() => _ler('apostilasPorCurso', {
    for (final e in sequencias.entries) e.key: e.value.length,
  });

  @override
  Future<List<LinhaOrdenada>> sequenciaDoCurso(String cursoId) =>
      _ler('sequenciaDoCurso', List.of(sequencias[cursoId] ?? const []));

  @override
  Future<void> salvarSequenciaDoCurso(
    String cursoId,
    List<String> materialIds,
  ) => _gravar('salvarSequenciaDoCurso', () {
    sequencias[cursoId] = [
      for (var i = 0; i < materialIds.length; i++)
        LinhaOrdenada(
          id: 'cm-$cursoId-$i',
          filhoId: materialIds[i],
          ordem: i + 1,
        ),
    ];
  });

  @override
  Future<List<Modulo>> modulos(String cursoId) => _ler(
    'modulos',
    [
      for (final m in modulos_)
        if (m.cursoId == cursoId) m,
    ]..sort((a, b) => a.ordem.compareTo(b.ordem)),
  );

  @override
  Future<Modulo> salvarModulo(Modulo modulo) => _gravar('salvarModulo', () {
    if (modulo.id == null) {
      final novo = Modulo(
        id: _novoId('mod'),
        cursoId: modulo.cursoId,
        materialId: modulo.materialId,
        nome: modulo.nome,
        ordem: modulo.ordem,
      );
      modulos_.add(novo);
      return novo;
    }
    final i = modulos_.indexWhere((m) => m.id == modulo.id);
    modulos_[i] = modulo;
    return modulo;
  });

  @override
  Future<void> excluirModulo(String id) =>
      _gravar('excluirModulo', () => modulos_.removeWhere((m) => m.id == id));

  @override
  Future<void> reordenarModulos(String cursoId, List<String> moduloIds) =>
      _gravar('reordenarModulos', () {
        for (var i = 0; i < moduloIds.length; i++) {
          final j = modulos_.indexWhere((m) => m.id == moduloIds[i]);
          final m = modulos_[j];
          modulos_[j] = Modulo(
            id: m.id,
            cursoId: m.cursoId,
            materialId: m.materialId,
            nome: m.nome,
            ordem: i + 1,
          );
        }
      });

  @override
  Future<List<Combo>> combos() => _ler('combos', List.of(combos_));

  @override
  Future<Combo> salvarCombo(Combo combo) => _gravar('salvarCombo', () {
    if (combo.id == null) {
      final novo = Combo(
        id: _novoId('cb'),
        metodoId: combo.metodoId,
        nome: combo.nome,
        ativo: combo.ativo,
      );
      combos_.add(novo);
      return novo;
    }
    final i = combos_.indexWhere((c) => c.id == combo.id);
    combos_[i] = combo;
    return combo;
  });

  @override
  Future<void> excluirCombo(String id) =>
      _gravar('excluirCombo', () => combos_.removeWhere((c) => c.id == id));

  @override
  Future<Map<String, int>> cursosPorCombo() => _ler('cursosPorCombo', {
    for (final e in composicoes.entries) e.key: e.value.length,
  });

  @override
  Future<List<LinhaOrdenada>> cursosDoCombo(String comboId) =>
      _ler('cursosDoCombo', List.of(composicoes[comboId] ?? const []));

  @override
  Future<void> salvarCursosDoCombo(String comboId, List<String> cursoIds) =>
      _gravar('salvarCursosDoCombo', () {
        composicoes[comboId] = [
          for (var i = 0; i < cursoIds.length; i++)
            LinhaOrdenada(
              id: 'cc-$comboId-$i',
              filhoId: cursoIds[i],
              ordem: i + 1,
            ),
        ];
      });
}
