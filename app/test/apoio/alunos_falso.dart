import 'package:gestao_im360/alunos/alunos.dart';
import 'package:gestao_im360/alunos/alunos_repositorio.dart';
import 'package:gestao_im360/util/datas.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repositório em memória — o teste injeta **dados**, não um cliente HTTP
/// falso (card 2.8 §9.3). A forma dos dados é a da camada `alunos` da
/// escola-fixture (card 4.2, `supabase/seed.sql`): doze alunos, um por caso
/// que alguma decisão criou, com os seis status representados; os ids de
/// método e combo são os do `CatalogoFalso`.
///
/// As duas funções de status reproduzem **o que o banco responde** — os
/// mesmos `codigo` de `fn_aluno_alterar_status`/`fn_aluno_reverter_status`,
/// no mesmo formato de `DETAIL` —, porque é isso que a tela traduz. Não é
/// uma segunda implementação da regra: é o contrato de erro, do lado de cá.
class AlunosFalso implements AlunosRepositorio {
  AlunosFalso({
    List<Aluno>? alunos,
    Map<String, List<TransicaoStatus>>? historicos,
  }) : alunos_ = List.of(alunos ?? const []),
       historicos = {
         for (final e in (historicos ?? const {}).entries)
           e.key: List.of(e.value),
       };

  factory AlunosFalso.fixture() {
    final hoje = soData(DateTime.now());
    Aluno aluno(
      String id,
      String nome,
      String? codigo,
      String metodo,
      String? combo,
      String status,
      int statusHa,
      int? prevEm,
      int inicioHa,
    ) => Aluno(
      id: id,
      nome: nome,
      codigoSgf: codigo,
      metodoId: metodo,
      comboId: combo,
      status: status,
      statusDesde: hoje.subtract(Duration(days: statusHa)),
      prevConclusaoCurso: prevEm == null
          ? null
          : hoje.add(Duration(days: prevEm)),
      dataInicio: hoje.subtract(Duration(days: inicioHa)),
    );
    return AlunosFalso(
      alunos: [
        aluno(
          'al-3001',
          'Ana Paula Ribeiro',
          '3001',
          'm-int',
          'cb-info',
          'ATIVO',
          180,
          null,
          180,
        ),
        aluno(
          'al-3002',
          'Bruno Carvalho',
          '3002',
          'm-int',
          'cb-info',
          'ATIVO',
          90,
          90,
          90,
        ),
        aluno(
          'al-3003',
          'Carla Menezes',
          '3003',
          'm-int',
          'cb-info',
          'ATIVO',
          10,
          null,
          10,
        ),
        aluno(
          'al-3004',
          'Diego Alves',
          '3004',
          'm-int',
          'cb-info',
          'ATIVO',
          120,
          -15,
          120,
        ),
        aluno(
          'al-3005',
          'Eduarda Lima',
          '3005',
          'm-mod',
          'cb-ele',
          'ATIVO',
          60,
          null,
          60,
        ),
        aluno(
          'al-3006',
          'Felipe Nunes',
          '3006',
          'm-ing',
          'cb-kids',
          'ACELERAR',
          30,
          60,
          150,
        ),
        aluno(
          'al-3007',
          'Gabriela Souza',
          '3007',
          'm-ing',
          'cb-kids',
          'STANDBY',
          45,
          null,
          200,
        ),
        aluno(
          'al-3008',
          'Henrique Dias',
          '3008',
          'm-int',
          'cb-info',
          'TRANCADO',
          75,
          null,
          300,
        ),
        aluno(
          'al-isabela',
          'Isabela Rocha',
          null,
          'm-int',
          'cb-info',
          'CANCELADO',
          20,
          null,
          100,
        ),
        aluno(
          'al-3010',
          'João Pedro Martins',
          '3010',
          'm-int',
          'cb-info',
          'FORMADO',
          5,
          null,
          400,
        ),
        aluno(
          'al-karina',
          'Karina Bastos',
          null,
          'm-int',
          null,
          'ATIVO',
          15,
          null,
          15,
        ),
        aluno(
          'al-lucas',
          'Lucas Ferreira',
          null,
          'm-int',
          'cb-info',
          'ATIVO',
          50,
          null,
          50,
        ),
      ],
      historicos: {
        'al-3007': [
          TransicaoStatus(
            id: 'h-gabriela',
            statusAnterior: 'ATIVO',
            statusNovo: 'STANDBY',
            ocorridoEm: hoje.subtract(const Duration(days: 45)),
            motivo: 'viagem de trabalho',
          ),
        ],
        'al-isabela': [
          TransicaoStatus(
            id: 'h-isabela',
            statusAnterior: 'ATIVO',
            statusNovo: 'CANCELADO',
            ocorridoEm: hoje.subtract(const Duration(days: 20)),
            usuarioNome: 'Diretora Escola A',
            motivo: 'desistiu do curso',
          ),
        ],
        'al-3010': [
          TransicaoStatus(
            id: 'h-joao',
            statusAnterior: 'ATIVO',
            statusNovo: 'FORMADO',
            ocorridoEm: hoje.subtract(const Duration(days: 5)),
            usuarioNome: 'Diretora Escola A',
          ),
        ],
      },
    );
  }

  final List<Aluno> alunos_;
  final Map<String, List<TransicaoStatus>> historicos;

  /// Se definido, toda **escrita** lança isto.
  Object? falhaAoGravar;

  /// Se definido, toda **leitura** lança isto.
  Object? falhaAoLer;

  /// Atraso de cada leitura (ver `CatalogoFalso`).
  Duration atrasoLeitura = Duration.zero;

  /// Registro do que foi chamado, na ordem.
  final chamadas = <String>[];

  int _contador = 0;

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

  static PostgrestException _erro(
    String status,
    String codigo,
    Map<String, Object?> detalhe,
  ) => PostgrestException(
    message: codigo,
    code: 'PT$status',
    details:
        '{"codigo":"$codigo"'
        '${detalhe.entries.map((e) => ',"${e.key}":"${e.value}"').join()}}',
  );

  int _indice(String id) => alunos_.indexWhere((a) => a.id == id);

  @override
  Future<List<Aluno>> alunos() => _ler('alunos', List.of(alunos_));

  @override
  Future<Aluno?> aluno(String id) {
    final i = _indice(id);
    return _ler('aluno', i < 0 ? null : alunos_[i]);
  }

  @override
  Future<Aluno> salvarAluno(Aluno aluno) => _gravar('salvarAluno', () {
    if (aluno.id == null) {
      final novo = Aluno(
        id: 'al-novo-${++_contador}',
        nome: aluno.nome.trim(),
        metodoId: aluno.metodoId,
        codigoSgf: aluno.codigoSgf?.trim().isEmpty == true
            ? null
            : aluno.codigoSgf,
        comboId: aluno.comboId,
        status: 'ATIVO',
        statusDesde: soData(DateTime.now()),
        prevConclusaoCurso: aluno.prevConclusaoCurso,
        dataInicio: aluno.dataInicio ?? soData(DateTime.now()),
        observacoes: aluno.observacoes,
      );
      alunos_.add(novo);
      return novo;
    }
    final i = _indice(aluno.id!);
    final atual = alunos_[i];
    // Como o PATCH: status e status_desde não vão na linha (ver paraLinha).
    final salvo = Aluno(
      id: atual.id,
      nome: aluno.nome.trim(),
      metodoId: aluno.metodoId,
      codigoSgf: aluno.codigoSgf?.trim().isEmpty == true
          ? null
          : aluno.codigoSgf,
      comboId: aluno.comboId,
      status: atual.status,
      statusDesde: atual.statusDesde,
      prevConclusaoCurso: aluno.prevConclusaoCurso,
      dataInicio: aluno.dataInicio ?? atual.dataInicio,
      observacoes: aluno.observacoes,
      conferido: atual.conferido,
    );
    alunos_[i] = salvo;
    return salvo;
  });

  @override
  Future<List<TransicaoStatus>> historico(String alunoId) =>
      _ler('historico', List.of(historicos[alunoId] ?? const []));

  void _mudar(String alunoId, String status, String? motivo) {
    final i = _indice(alunoId);
    final atual = alunos_[i];
    final agora = DateTime.now();
    alunos_[i] = Aluno(
      id: atual.id,
      nome: atual.nome,
      metodoId: atual.metodoId,
      codigoSgf: atual.codigoSgf,
      comboId: atual.comboId,
      status: status,
      statusDesde: soData(agora),
      prevConclusaoCurso: atual.prevConclusaoCurso,
      dataInicio: atual.dataInicio,
      observacoes: atual.observacoes,
      conferido: atual.conferido,
    );
    (historicos[alunoId] ??= []).insert(
      0,
      TransicaoStatus(
        id: 'h-novo-${++_contador}',
        statusAnterior: atual.status,
        statusNovo: status,
        ocorridoEm: agora,
        motivo: motivo,
      ),
    );
  }

  @override
  Future<void> alterarStatus(
    String alunoId, {
    required String status,
    String? motivo,
  }) => _gravar('alterarStatus', () {
    final i = _indice(alunoId);
    if (i < 0) throw _erro('422', 'ALUNO_INEXISTENTE', {'aluno': alunoId});
    final atual = alunos_[i].status;
    if (!transicoesDe(atual).contains(status)) {
      throw _erro('409', 'TRANSICAO_INVALIDA', {'de': atual, 'para': status});
    }
    if (statusComMotivo.contains(status) &&
        (motivo == null || motivo.trim().isEmpty)) {
      throw _erro('422', 'MOTIVO_OBRIGATORIO', {'status': status});
    }
    _mudar(alunoId, status, motivo?.trim());
  });

  @override
  Future<void> reverterStatus(
    String alunoId, {
    required String destino,
    required String motivo,
  }) => _gravar('reverterStatus', () {
    final i = _indice(alunoId);
    if (i < 0) throw _erro('422', 'ALUNO_INEXISTENTE', {'aluno': alunoId});
    if (motivo.trim().isEmpty) {
      throw _erro('422', 'MOTIVO_OBRIGATORIO', {'status': destino});
    }
    final atual = alunos_[i].status;
    if (!destinosReversao(atual).contains(destino)) {
      throw _erro('409', 'TRANSICAO_INVALIDA', {'de': atual, 'para': destino});
    }
    _mudar(alunoId, destino, motivo.trim());
  });
}
