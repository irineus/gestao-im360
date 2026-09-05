import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/certificados/certificados.dart';
import 'package:gestao_im360/util/datas.dart';

/// A lógica **pura** da tela 9 (card 8.6): a leitura de `v_certificado_fila`, a
/// do checklist com "quem/quando", os rótulos, o filtro e a ordem da fila.
///
/// Sem rede e sem cliente Supabase (card 2.8 §9.3) — o que precisa de banco
/// está em `supabase/tests/083_certificado_fila.sql`.
void main() {
  LinhaFilaCertificado linha({
    required String id,
    String situacao = situacaoFim,
    bool? pedagogico,
    bool? financeiro,
    bool? formatura,
    String? status,
    DateTime? fimCurso,
    String nome = 'Aluno',
    String metodoId = 'm-int',
    String? sgf = '1000',
  }) => LinhaFilaCertificado(
    alunoId: id,
    alunoNome: nome,
    codigoSgf: sgf,
    alunoStatus: 'ATIVO',
    metodoId: metodoId,
    metodoNome: 'Interativo',
    situacao: situacao,
    itensPendentes: situacao == situacaoFim ? 0 : 1,
    checklistId: status == null ? null : 'cc-$id',
    dataFimCurso: fimCurso,
    pedagogicoOk: pedagogico,
    financeiroOk: financeiro,
    formatura: formatura,
    certificadoStatus: status,
  );

  group('leitura de v_certificado_fila', () {
    test(
      'as cinco colunas do checklist chegam NULAS quando ele não existe',
      () {
        // Nulo não é `false`: "ninguém abriu o checklist deste aluno" e "o
        // pedagógico ainda não assinou" são coisas diferentes, e é a diferença
        // que decide se a tela desenha um traço ou uma caixa vazia.
        final l = LinhaFilaCertificado.deLinha({
          'aluno_id': 'a1',
          'aluno_nome': 'Ana',
          'codigo_sgf': '4433',
          'aluno_status': 'ATIVO',
          'metodo_id': 'm-int',
          'metodo_nome': 'Interativo',
          'situacao': 'ULTIMO_LIVRO',
          'itens_pendentes': 1,
          'checklist_id': null,
          'data_fim_curso': null,
          'pedagogico_ok': null,
          'financeiro_ok': null,
          'formatura': null,
          'certificado_status': null,
        });

        expect(l.temChecklist, isFalse);
        expect(l.marca(ItemChecklist.pedagogico), isNull);
        expect(l.certificadoStatus, isNull);
        expect(resumoChecklist(l), semChecklist);
        // E o status não vira "Não pedido": afirmar isso diria que alguém já
        // olhou o caso.
        expect(rotuloStatusDaLinha(l), '—');
      },
    );

    test('com checklist, o resumo diz item por item', () {
      final l = linha(
        id: 'a2',
        pedagogico: true,
        financeiro: false,
        formatura: false,
        status: 'PEDIDO',
        fimCurso: DateTime(2026, 8, 18),
      );

      expect(l.temChecklist, isTrue);
      expect(resumoChecklist(l), 'P ok · F pendente · Fo pendente');
      expect(rotuloStatusDaLinha(l), 'Pedido');
    });

    test('o rótulo do aluno traz o código SGF quando existe', () {
      expect(linha(id: 'a', nome: 'Ana').rotuloAluno, 'Ana (1000)');
      expect(linha(id: 'a', nome: 'Ana', sgf: null).rotuloAluno, 'Ana');
    });
  });

  group('rótulos', () {
    test('as duas situações do card 2.3 §8.1 têm nomes distintos', () {
      // Juntá-las numa palavra só seria perder a diferença que faz a fila útil:
      // no último livro ainda dá tempo de pedir o certificado.
      expect(rotuloSituacao(situacaoUltimoLivro), 'Último livro');
      expect(rotuloSituacao(situacaoFim), 'Fim do curso');
      expect(
        rotuloSituacao(situacaoUltimoLivro) == rotuloSituacao(situacaoFim),
        isFalse,
      );
    });

    test('situação desconhecida volta como veio', () {
      // Inventar um rótulo bonito para um valor que o banco passou a usar
      // esconderia justamente a novidade.
      expect(rotuloSituacao('COISA_NOVA'), 'COISA_NOVA');
    });

    test('os três status do certificado', () {
      expect(statusDoCertificado, ['NAO_PEDIDO', 'PEDIDO', 'ENTREGUE']);
      expect(rotuloStatusCertificado('NAO_PEDIDO'), 'Não pedido');
      expect(rotuloStatusCertificado('ENTREGUE'), 'Entregue');
      expect(rotuloStatusCertificado('OUTRO'), 'OUTRO');
    });

    test('cada item do checklist tem a permissão do próprio item', () {
      // A separação é o que faz a jornada nº 2 do monitor existir: marcar
      // "financeiro OK" é a única marca do checklist que ele faz (card 2.4 §5.1).
      expect(
        ItemChecklist.financeiro.permissao,
        'certificados.marcar_financeiro',
      );
      // Formatura anda com pedagógico — os dois são do pedagógico (card 2.2 §8).
      expect(
        ItemChecklist.formatura.permissao,
        ItemChecklist.pedagogico.permissao,
      );
      expect(ItemChecklist.values.map((i) => i.codigo), [
        'PEDAGOGICO',
        'FINANCEIRO',
        'FORMATURA',
      ]);
    });
  });

  group('checklist com quem e quando', () {
    test('lê os quatro embeds de usuário, e o nome pode faltar', () {
      // A política de `usuario` exige `admin.ler` ou ser a própria linha: quem
      // não tem recebe o embed nulo. A tela mostra só a data nesse caso.
      final c = ChecklistCertificado.deLinha({
        'id': 'cc-1',
        'aluno_id': 'a1',
        'data_fim_curso': '2026-08-18',
        'pedagogico_ok': true,
        'pedagogico_em': '2026-08-20T12:00:00Z',
        'pedagogico_usuario': {'nome': 'Paula'},
        'financeiro_ok': true,
        'financeiro_em': '2026-08-22T12:00:00Z',
        'financeiro_usuario': null,
        'formatura': false,
        'formatura_em': null,
        'formatura_usuario': null,
        'certificado_status': 'PEDIDO',
        'certificado_em': '2026-08-23T12:00:00Z',
        'certificado_usuario': {'nome': 'Caio'},
      });

      expect(c.marca(ItemChecklist.pedagogico), isTrue);
      expect(c.autoria(ItemChecklist.pedagogico).nome, 'Paula');
      expect(c.autoria(ItemChecklist.financeiro).nome, isNull);
      expect(c.autoria(ItemChecklist.financeiro).quando, isNotNull);
      expect(c.autoria(ItemChecklist.formatura).vazia, isTrue);
      expect(c.autoriaStatus.nome, 'Caio');
      expect(c.completo, isFalse);
    });

    test('completo é a condição exata do gatilho que sugere FORMADO', () {
      // Os três itens **e** o certificado entregue (card 8.3). Faltando um, o
      // banco não abre a sugestão — e a tela não pode dizer que abriu.
      ChecklistCertificado montar({
        required bool formatura,
        required String status,
      }) => ChecklistCertificado(
        id: 'cc',
        alunoId: 'a',
        dataFimCurso: DateTime(2026, 8, 18),
        pedagogicoOk: true,
        financeiroOk: true,
        formatura: formatura,
        certificadoStatus: status,
      );

      expect(montar(formatura: true, status: 'ENTREGUE').completo, isTrue);
      expect(montar(formatura: false, status: 'ENTREGUE').completo, isFalse);
      expect(montar(formatura: true, status: 'PEDIDO').completo, isFalse);
    });

    test('rotuloAutoria: com nome, sem nome e vazia', () {
      expect(
        rotuloAutoria(
          AutoriaItem(nome: 'Paula', quando: DateTime(2026, 8, 20)),
          formatarData,
        ),
        'por Paula, 20/08/2026',
      );
      expect(
        rotuloAutoria(AutoriaItem(quando: DateTime(2026, 8, 20)), formatarData),
        '20/08/2026',
      );
      expect(rotuloAutoria(const AutoriaItem(), formatarData), '—');
    });
  });

  group('filtro da fila', () {
    final fila = [
      linha(id: 'a1', situacao: situacaoUltimoLivro, nome: 'Ana', sgf: '4433'),
      linha(
        id: 'a2',
        nome: 'Bianca',
        sgf: '4501',
        pedagogico: true,
        financeiro: false,
        formatura: false,
        status: 'NAO_PEDIDO',
        fimCurso: DateTime(2026, 8, 18),
      ),
      linha(
        id: 'a3',
        nome: 'Caio',
        sgf: '4102',
        metodoId: 'm-ing',
        pedagogico: true,
        financeiro: true,
        formatura: true,
        status: 'ENTREGUE',
        fimCurso: DateTime(2026, 7, 2),
      ),
    ];

    test('busca por nome e por código SGF', () {
      expect(
        filtrarFila(
          fila,
          const FiltroCertificados(busca: 'bian'),
        ).map((l) => l.alunoId),
        ['a2'],
      );
      expect(
        filtrarFila(
          fila,
          const FiltroCertificados(busca: '4102'),
        ).map((l) => l.alunoId),
        ['a3'],
      );
    });

    test('método e situação', () {
      expect(
        filtrarFila(
          fila,
          const FiltroCertificados(metodoId: 'm-ing'),
        ).map((l) => l.alunoId),
        ['a3'],
      );
      expect(
        filtrarFila(
          fila,
          const FiltroCertificados(situacao: situacaoFim),
        ).map((l) => l.alunoId),
        ['a2', 'a3'],
      );
    });

    test('"financeiro pendente" inclui quem ainda NÃO tem checklist', () {
      // A jornada nº 2 do monitor. Deixar de fora quem não tem checklist
      // esconderia dele exatamente quem precisa de uma ação a mais — o
      // financeiro desse aluno está tão pendente quanto o do outro.
      expect(
        filtrarFila(
          fila,
          const FiltroCertificados(soFinanceiroPendente: true),
        ).map((l) => l.alunoId),
        ['a1', 'a2'],
      );
    });

    test(
      'a contagem de filtros ativos alimenta o "Filtrar (n)" do celular',
      () {
        expect(const FiltroCertificados().ativos, 0);
        expect(
          const FiltroCertificados(
            busca: 'ana',
            metodoId: 'm-int',
            situacao: situacaoFim,
            soFinanceiroPendente: true,
          ).ativos,
          4,
        );
        // Busca só de espaços não conta: o filtro não está ligado.
        expect(const FiltroCertificados(busca: '   ').ativos, 0);
      },
    );

    test('copiar apaga o valor quando a função devolve nulo', () {
      const cheio = FiltroCertificados(metodoId: 'm-int', situacao: 'FIM');
      expect(cheio.copiar(metodoId: () => null).metodoId, isNull);
      expect(cheio.copiar(metodoId: () => null).situacao, 'FIM');
    });

    test('o filtro só oferece as situações que existem na fila', () {
      // Escolher um degrau que não existe e receber lista vazia ensina a não
      // usar o filtro.
      expect(situacoesPresentes(fila), [situacaoFim, situacaoUltimoLivro]);
      expect(situacoesPresentes([fila.first]), [situacaoUltimoLivro]);
    });
  });

  group('ordem da fila', () {
    test('FIM na frente, e dentro dele o fim de curso mais antigo', () {
      final ordenada = ordenarFila([
        linha(id: 'a1', situacao: situacaoUltimoLivro, nome: 'Ana'),
        linha(
          id: 'a2',
          nome: 'Bianca',
          status: 'NAO_PEDIDO',
          fimCurso: DateTime(2026, 8, 18),
        ),
        linha(
          id: 'a3',
          nome: 'Caio',
          status: 'ENTREGUE',
          fimCurso: DateTime(2026, 7, 2),
        ),
      ]);

      expect(ordenada.map((l) => l.alunoId), ['a3', 'a2', 'a1']);
    });

    test('sem data de fim de curso vai para o fim do próprio grupo', () {
      // Ordenar nulo como "muito antigo" poria na frente da fila exatamente
      // quem ninguém ainda começou a preparar.
      final ordenada = ordenarFila([
        linha(id: 'sem', nome: 'Zena'),
        linha(
          id: 'com',
          nome: 'Aline',
          status: 'PEDIDO',
          fimCurso: DateTime(2026, 8, 18),
        ),
      ]);

      expect(ordenada.map((l) => l.alunoId), ['com', 'sem']);
    });

    test('empate de data desempata por nome, e a ordem é estável', () {
      final ordenada = ordenarFila([
        linha(
          id: 'z',
          nome: 'Zeca',
          status: 'PEDIDO',
          fimCurso: DateTime(2026, 8, 18),
        ),
        linha(
          id: 'a',
          nome: 'Aline',
          status: 'PEDIDO',
          fimCurso: DateTime(2026, 8, 18),
        ),
      ]);

      expect(ordenada.map((l) => l.alunoId), ['a', 'z']);
    });
  });
}
