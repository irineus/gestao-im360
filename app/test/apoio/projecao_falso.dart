import 'package:gestao_im360/projecao/projecao.dart';
import 'package:gestao_im360/projecao/projecao_repositorio.dart';

/// Repositório em memória — o teste injeta **dados**, não um cliente HTTP falso
/// (card 2.8 §9.3).
///
/// ⚠️ **O detalhe é derivado da grade, não escrito à parte.** É a propriedade
/// que a tela 8 inteira depende: o total da grade e a contagem do drill-down
/// fecham célula por célula (`082_projecao_views_tela` §3.1). Duas listas
/// escritas à mão ficariam livres para divergir dentro do próprio teste — e o
/// teste passaria a medir o contrário do que existe para medir.
///
/// A forma dos dados é a da fixture do banco depois de `rt_projecao_demanda`
/// (medida em 05/09/2026, `supabase/seed.sql`):
///
///   • `02` em outubro, 3 exemplares por `MEDIA_METODO` — a célula simples;
///   • `04` em novembro, 2 por `MEDIA_METODO` **e** 1 por `RITMO_ALUNO` — a
///     célula de **duas regras**, que é o caso "Várias" da coluna Regra;
///   • `03` sem linha em outubro — o mês vazio, que a tela mostra como traço e
///     não como zero;
///   • um aluno por `PREVISAO_CURSO`, com `ritmo_dias` **nulo** — o degrau em
///     que a data não vem de ritmo nenhum.
class ProjecaoFalso implements ProjecaoRepositorio {
  ProjecaoFalso({
    required List<CelulaProjecao> grade,
    required List<DetalheProjecao> detalhe,
    this.rotinaFalhou_ = false,
  }) : grade_ = List.of(grade),
       detalhe_ = List.of(detalhe);

  /// A projeção que nunca rodou: grade vazia. Com [rotinaFalhou] verdadeiro é o
  /// vazio que aponta a pendência; sem ele, o vazio neutro do horizonte.
  factory ProjecaoFalso.vazio({bool rotinaFalhou = false}) => ProjecaoFalso(
    grade: const [],
    detalhe: const [],
    rotinaFalhou_: rotinaFalhou,
  );

  factory ProjecaoFalso.fixture() {
    final calculadoEm = DateTime(2026, 9, 6, 3, 12);
    final outubro = DateTime(2026, 10);
    final novembro = DateTime(2026, 11);

    CelulaProjecao celula(
      String materialId,
      String codigo,
      String nome,
      String categoria,
      String metodoId,
      DateTime mes,
      int quantidade,
      String regra,
    ) => CelulaProjecao(
      materialId: materialId,
      metodoId: metodoId,
      codigo: codigo,
      nome: nome,
      categoria: categoria,
      mes: mes,
      quantidade: quantidade,
      regra: regra,
      calculadoEm: calculadoEm,
    );

    final grade = [
      celula(
        'mat-02',
        '02',
        'Informática Essencial 2',
        'APOSTILA',
        'm-int',
        outubro,
        3,
        'MEDIA_METODO',
      ),
      celula(
        'mat-03',
        '03',
        'Informática Avançada 1',
        'APOSTILA',
        'm-int',
        novembro,
        2,
        'PREVISAO_CURSO',
      ),
      celula(
        'mat-04',
        '04',
        'Informática Avançada 2',
        'LIVRO',
        'm-ing',
        novembro,
        2,
        'MEDIA_METODO',
      ),
      celula(
        'mat-04',
        '04',
        'Informática Avançada 2',
        'LIVRO',
        'm-ing',
        novembro,
        1,
        'RITMO_ALUNO',
      ),
    ];

    // Um aluno por exemplar, com a mesma regra e o mesmo mês — é o que faz o
    // total fechar com a contagem.
    var n = 0;
    final detalhe = <DetalheProjecao>[];
    for (final c in grade) {
      for (var i = 0; i < c.quantidade; i++) {
        n++;
        detalhe.add(
          DetalheProjecao(
            alunoId: 'aluno-$n',
            alunoNome: 'Aluno $n',
            codigoSgf: '${3000 + n}',
            alunoStatus: 'ATIVO',
            materialId: c.materialId,
            codigo: c.codigo,
            materialNome: c.nome,
            mes: c.mes,
            dataPrevista: DateTime(c.mes.year, c.mes.month, 4 + i),
            regra: c.regra,
            // Nulo nos degraus em que a data não vem de ritmo — é o `—` da
            // última coluna do drill-down.
            ritmoDias: switch (c.regra) {
              'MEDIA_METODO' => 30,
              'RITMO_ALUNO' => 60,
              _ => null,
            },
            k: 2 + i,
            pendentes: 5,
          ),
        );
      }
    }

    return ProjecaoFalso(grade: grade, detalhe: detalhe);
  }

  final List<CelulaProjecao> grade_;
  final List<DetalheProjecao> detalhe_;
  final bool rotinaFalhou_;

  /// Erro a levantar na próxima leitura da grade — para exercitar o quarto
  /// estado (design-system §5.6).
  Object? erroDaGrade;

  /// Erro a levantar na próxima leitura do detalhe.
  Object? erroDoDetalhe;

  @override
  Future<List<CelulaProjecao>> grade() async {
    final erro = erroDaGrade;
    if (erro != null) throw erro;
    return List.of(grade_);
  }

  @override
  Future<List<DetalheProjecao>> detalhe(
    String materialId, {
    DateTime? mes,
  }) async {
    final erro = erroDoDetalhe;
    if (erro != null) throw erro;
    return [
      for (final d in detalhe_)
        if (d.materialId == materialId && (mes == null || d.mes == mes)) d,
    ];
  }

  @override
  Future<bool> rotinaFalhou() async => rotinaFalhou_;
}
