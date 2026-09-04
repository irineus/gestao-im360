import 'package:gestao_im360/erros/erro_app.dart';
import 'package:gestao_im360/pendencias/pendencias.dart';
import 'package:gestao_im360/pendencias/pendencias_repositorio.dart';

/// Repositório em memória — o teste injeta **dados**, não um cliente HTTP falso
/// (card 2.8 §9.3).
///
/// A fixture descreve a mesma escola dos outros repositórios falsos (mesmos ids
/// de aluno e de bloco), com uma pendência de cada família que a central precisa
/// saber desenhar:
///
///   • uma `ALUNO_SEM_TURMA` **ALTA** e uma `BLOCO_ACIMA_CAPACIDADE` **ALTA** —
///     as duas que o contador do menu conta;
///   • um `REP_VIRADA:CONTINUO` e um `REP_VIRADA:VOLTA`, que só a `chave_dedup`
///     separa e que chamam funções diferentes;
///   • uma `ACELERAR_SEM_2O_BLOCO` **BAIXA** com a referência **oculta** (id
///     preenchido, nome nulo), que é como a view chega para quem não pode ler o
///     aluno — a linha tem de continuar existindo;
///   • uma `ROTINA_FALHOU`, que não tem referência nem tela de destino.
class PendenciasFalso implements PendenciasRepositorio {
  PendenciasFalso({List<Pendencia>? pendencias, this.atrasoLeitura})
    : pendencias_ = List.of(pendencias ?? const []);

  factory PendenciasFalso.fixture() => PendenciasFalso(
    pendencias: [
      pendenciaFalsa(
        id: 'p-sem-turma',
        tipo: 'ALUNO_SEM_TURMA',
        severidade: 'ALTA',
        descricao: 'Aluno ATIVO sem nenhuma turma.',
        chaveDedup: 'ALUNO_SEM_TURMA:al-3005',
        diasAberta: 2,
        alunoId: 'al-3005',
        alunoNome: 'Eduarda Lima',
        codigoSgf: '3005',
        alunoStatus: 'ATIVO',
      ),
      pendenciaFalsa(
        id: 'p-capacidade',
        tipo: 'BLOCO_ACIMA_CAPACIDADE',
        severidade: 'ALTA',
        descricao: '11 alunos para capacidade de 10.',
        chaveDedup: 'CAPACIDADE:b-acima',
        diasAberta: 1,
        blocoId: 'b-acima',
        blocoDiaSemana: 4,
        blocoHoraInicio: '09:30',
        blocoSalaNome: 'Laboratório 1',
      ),
      pendenciaFalsa(
        id: 'p-rep-continuo',
        tipo: 'REP_VIRADA',
        severidade: 'MEDIA',
        descricao: '3 aulas a repor; cabem 2 até 12/10.',
        chaveDedup: 'REP:al-lucas:CONTINUO',
        alunoId: 'al-lucas',
        alunoNome: 'Lucas Ferreira',
        alunoStatus: 'ATIVO',
      ),
      pendenciaFalsa(
        id: 'p-rep-volta',
        tipo: 'REP_VIRADA',
        severidade: 'MEDIA',
        descricao: 'Sem débito há 34 dias; pode voltar a pontual.',
        chaveDedup: 'REP:al-3004:VOLTA',
        diasAberta: 5,
        alunoId: 'al-3004',
        alunoNome: 'Diego Alves',
        codigoSgf: '3004',
        alunoStatus: 'ATIVO',
      ),
      // Referência OCULTA: o id veio e o nome não, que é como o `left join` da
      // view chega para quem não pode ler `aluno` (card 2.3 §9).
      pendenciaFalsa(
        id: 'p-acelerar',
        tipo: 'ACELERAR_SEM_2O_BLOCO',
        severidade: 'BAIXA',
        descricao: 'Aluno ACELERAR com um bloco só.',
        chaveDedup: 'ACELERAR:al-oculto',
        diasAberta: 12,
        alunoId: 'al-oculto',
      ),
      pendenciaFalsa(
        id: 'p-rotina',
        tipo: 'ROTINA_FALHOU',
        severidade: 'ALTA',
        descricao: 'rt_rep_avaliar: division by zero',
        chaveDedup: 'ROTINA_FALHOU:rt_rep_avaliar',
        diasAberta: 0,
      ),
    ],
  );

  final List<Pendencia> pendencias_;

  /// O card 4.4 mediu que teste instantâneo não constrói a tela no estado em que
  /// o banco a apanha.
  final Duration? atrasoLeitura;

  /// `<id>|<resolucao>|<justificativa>` — é como o teste confere a chamada.
  final List<String> fechadas = [];

  /// Quantas vezes a lista foi lida — é como se assere que a tela **recarregou**
  /// depois de uma escrita, sem espionar o provider.
  int leituras = 0;

  /// O erro que `resolver` levanta — `PENDENCIA_JA_RESOLVIDA`,
  /// `PENDENCIA_INEXISTENTE`, `MOTIVO_OBRIGATORIO`. Nulo = caminho feliz.
  ErroApp? erroAoResolver;

  @override
  Future<List<Pendencia>> abertas() async {
    leituras++;
    final atraso = atrasoLeitura;
    if (atraso != null) await Future<void>.delayed(atraso);
    return ordenarPendencias(pendencias_);
  }

  @override
  Future<void> resolver(
    String pendenciaId, {
    required String resolucao,
    String? justificativa,
  }) async {
    fechadas.add('$pendenciaId|$resolucao|${justificativa ?? ''}');
    final erro = erroAoResolver;
    if (erro != null) throw erro;
    pendencias_.removeWhere((p) => p.id == pendenciaId);
  }
}

Pendencia pendenciaFalsa({
  required String id,
  required String tipo,
  required String severidade,
  required String descricao,
  required String chaveDedup,
  int diasAberta = 0,
  String? alunoId,
  String? alunoNome,
  String? codigoSgf,
  String? alunoStatus,
  String? blocoId,
  int? blocoDiaSemana,
  String? blocoHoraInicio,
  String? blocoSalaNome,
  String? materialId,
  String? materialCodigo,
  String? materialNome,
  String? pcId,
  String? pcIdentificador,
}) => Pendencia(
  id: id,
  tipo: tipo,
  severidade: severidade,
  ordemSeveridade: switch (severidade) {
    'ALTA' => 1,
    'MEDIA' => 2,
    _ => 3,
  },
  descricao: descricao,
  chaveDedup: chaveDedup,
  criadoEm: DateTime(2026, 9, 4).subtract(Duration(days: diasAberta)),
  diasAberta: diasAberta,
  alunoId: alunoId,
  alunoNome: alunoNome,
  codigoSgf: codigoSgf,
  alunoStatus: alunoStatus,
  blocoId: blocoId,
  blocoDiaSemana: blocoDiaSemana,
  blocoHoraInicio: blocoHoraInicio,
  blocoSalaNome: blocoSalaNome,
  materialId: materialId,
  materialCodigo: materialCodigo,
  materialNome: materialNome,
  pcId: pcId,
  pcIdentificador: pcIdentificador,
);
