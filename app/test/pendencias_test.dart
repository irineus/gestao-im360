import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/pendencias/pendencias.dart';
import 'package:gestao_im360/rotas/rotas.dart';

import 'apoio/pendencias_falso.dart';

/// A lógica **pura** da central (card 5.8): ordenação, referência degradada,
/// filtros, contador e o mapa tipo → ação contextual. Sem rede e sem cliente
/// Supabase (card 2.8 §9.3) — a tela está em `tela_pendencias_test.dart`.
void main() {
  group('ordenação', () {
    test('ALTA vem antes de BAIXA — a ordenação alfabética inverteria', () {
      // 'ALTA' < 'BAIXA' < 'MEDIA' em texto: ordenar pela palavra poria a
      // BAIXA no meio e a MEDIA no fim. É por isso que a view calcula
      // `ordem_severidade` numérica (card 5.5), e é ela que se usa aqui.
      final ordenada = ordenarPendencias([
        pendenciaFalsa(
          id: 'c',
          tipo: 'ESTOQUE_ABAIXO_MINIMO',
          severidade: 'BAIXA',
          descricao: 'baixa',
          chaveDedup: 'x:1',
        ),
        pendenciaFalsa(
          id: 'b',
          tipo: 'REP_VIRADA',
          severidade: 'MEDIA',
          descricao: 'média',
          chaveDedup: 'x:2',
        ),
        pendenciaFalsa(
          id: 'a',
          tipo: 'ALUNO_SEM_TURMA',
          severidade: 'ALTA',
          descricao: 'alta',
          chaveDedup: 'x:3',
        ),
      ]);
      expect(ordenada.map((p) => p.severidade), ['ALTA', 'MEDIA', 'BAIXA']);
    });

    test('na mesma severidade, a mais antiga primeiro', () {
      final ordenada = ordenarPendencias([
        pendenciaFalsa(
          id: 'nova',
          tipo: 'ALUNO_SEM_TURMA',
          severidade: 'ALTA',
          descricao: '',
          chaveDedup: 'a',
          diasAberta: 1,
        ),
        pendenciaFalsa(
          id: 'velha',
          tipo: 'ALUNO_SEM_TURMA',
          severidade: 'ALTA',
          descricao: '',
          chaveDedup: 'b',
          diasAberta: 30,
        ),
      ]);
      expect(ordenada.map((p) => p.id), ['velha', 'nova']);
    });

    test('empate total desempata pelo id — a ordem sobrevive à recarga', () {
      // Sem o terceiro critério, duas linhas iguais em severidade e idade
      // trocariam de lugar entre duas leituras e a pessoa perderia a linha que
      // estava lendo.
      Iterable<String> ordem(List<String> ids) => ordenarPendencias([
        for (final id in ids)
          pendenciaFalsa(
            id: id,
            tipo: 'ALUNO_SEM_TURMA',
            severidade: 'MEDIA',
            descricao: '',
            chaveDedup: id,
          ),
      ]).map((p) => p.id);

      expect(ordem(['b', 'a', 'c']), ['a', 'b', 'c']);
      expect(ordem(['c', 'b', 'a']), ['a', 'b', 'c']);
    });
  });

  group('referência', () {
    test('id sem nome degrada para "—" e a pendência CONTINUA na lista', () {
      // O `left join` da view existe para isto (card 2.3 §9): com join interno,
      // quem não pode ler a referência perderia a linha inteira e a central
      // diria "nenhuma pendência" em vez de "uma que você não pode detalhar".
      final oculta = pendenciaFalsa(
        id: 'p',
        tipo: 'ALUNO_SEM_TURMA',
        severidade: 'ALTA',
        descricao: 'x',
        chaveDedup: 'k',
        alunoId: 'al-1',
      );
      expect(oculta.referencia, '—');
      expect(oculta.referenciaOculta, isTrue);
      expect(filtrarPendencias([oculta], FiltroPendencias.semFiltro), [oculta]);
    });

    test('aluno com código, bloco com sala e PC saem legíveis', () {
      expect(
        pendenciaFalsa(
          id: 'p',
          tipo: 'ALUNO_SEM_TURMA',
          severidade: 'ALTA',
          descricao: '',
          chaveDedup: 'k',
          alunoId: 'a',
          alunoNome: 'Afonso',
          codigoSgf: '4433',
        ).referencia,
        'Afonso (4433)',
      );
      expect(
        pendenciaFalsa(
          id: 'p',
          tipo: 'BLOCO_ACIMA_CAPACIDADE',
          severidade: 'ALTA',
          descricao: '',
          chaveDedup: 'k',
          blocoId: 'b',
          blocoDiaSemana: 1,
          blocoHoraInicio: '08:00',
          blocoSalaNome: 'Laboratório 1',
        ).referencia,
        'Seg 08:00 · Laboratório 1',
      );
      expect(
        pendenciaFalsa(
          id: 'p',
          tipo: 'PC_SEM_SUBSTITUTO',
          severidade: 'MEDIA',
          descricao: '',
          chaveDedup: 'k',
          pcId: 'pc',
          pcIdentificador: 'LAB1-05',
        ).referencia,
        'LAB1-05',
      );
    });

    test('pendência sem referência nenhuma também é "—"', () {
      final rotina = pendenciaFalsa(
        id: 'p',
        tipo: 'ROTINA_FALHOU',
        severidade: 'ALTA',
        descricao: 'rt_diaria: boom',
        chaveDedup: 'ROTINA_FALHOU:rt_diaria',
      );
      expect(rotina.referencia, '—');
      expect(rotina.referenciaOculta, isFalse, reason: 'não há o que ocultar');
    });
  });

  group('REP_VIRADA — o sentido só existe na chave_dedup', () {
    test('o sufixo separa as duas metades da sugestão', () {
      expect(sentidoVirada('REP:al-1:CONTINUO'), SentidoVirada.continuo);
      expect(sentidoVirada('REP:al-1:VOLTA'), SentidoVirada.volta);
      expect(sentidoVirada('ALUNO_SEM_TURMA:al-1'), isNull);
    });

    test('só REP_VIRADA tem sentido', () {
      final outra = pendenciaFalsa(
        id: 'p',
        tipo: 'ALUNO_SEM_TURMA',
        severidade: 'ALTA',
        descricao: '',
        // Mesmo com um sufixo que se pareça, o tipo é quem manda.
        chaveDedup: 'ALUNO_SEM_TURMA:al-1:VOLTA',
      );
      expect(outra.sentido, isNull);
    });
  });

  group('ação contextual (wireframe §14.3)', () {
    test('cada tipo tem a ação da tabela do wireframe', () {
      expect(acaoDe('REP_VIRADA'), AcaoPendencia.executarVirada);
      expect(acaoDe('ALUNO_SEM_TURMA'), AcaoPendencia.verAluno);
      expect(acaoDe('BLOCO_ACIMA_CAPACIDADE'), AcaoPendencia.verBloco);
      expect(acaoDe('PC_SEM_SUBSTITUTO'), AcaoPendencia.verPc);
      expect(acaoDe('COMPRA_SEM_ESTOQUE'), AcaoPendencia.verMaterial);
      // "(sem ação de tela) — detalhe técnico p/ direção".
      expect(acaoDe('ROTINA_FALHOU'), AcaoPendencia.nenhuma);
    });

    test('a rota de destino existe no catálogo de rotas', () {
      // Se o id da rota mudar em `rotas.dart`, o botão navegaria para lugar
      // nenhum sem erro nenhum — daí a asserção contra o catálogo, e não contra
      // uma lista escrita à mão.
      // Percorre o CATÁLOGO, e não um conjunto escrito à mão aqui: uma lista
      // repetida no teste envelhece junto com a de `rotas.dart` e deixa de
      // acusar exatamente o dia em que uma delas muda.
      final ids = {for (final rota in rotasAplicacao) rota.id};
      for (final acao in AcaoPendencia.values) {
        final rotaId = rotaDaAcao(acao);
        if (rotaId == null) continue;
        expect(ids, contains(rotaId));
      }
    });

    test('sem a referência a ação não é oferecida', () {
      Pendencia com({String? alunoNome}) => pendenciaFalsa(
        id: 'p',
        tipo: 'ALUNO_SEM_TURMA',
        severidade: 'ALTA',
        descricao: '',
        chaveDedup: 'k',
        alunoId: 'al-1',
        alunoNome: alunoNome,
      );
      expect(referenciaDaAcaoPresente(com(alunoNome: 'Ana')), isTrue);
      expect(referenciaDaAcaoPresente(com()), isFalse);
    });

    test('REP_VIRADA sem sentido não oferece Executar', () {
      // Chave malformada não deve virar uma virada sem direção: chamar
      // fn_rep_virar_continuo por engano criaria alocação permanente.
      expect(
        referenciaDaAcaoPresente(
          pendenciaFalsa(
            id: 'p',
            tipo: 'REP_VIRADA',
            severidade: 'MEDIA',
            descricao: '',
            chaveDedup: 'REP:al-1',
            alunoId: 'al-1',
          ),
        ),
        isFalse,
      );
    });
  });

  group('filtros', () {
    final todas = PendenciasFalso.fixture().pendencias_;

    test('severidade, tipo e idade mínima', () {
      expect(
        filtrarPendencias(
          todas,
          const FiltroPendencias(severidade: 'ALTA'),
        ).length,
        3,
      );
      expect(
        filtrarPendencias(
          todas,
          const FiltroPendencias(tipo: 'REP_VIRADA'),
        ).map((p) => p.id),
        ['p-rep-volta', 'p-rep-continuo'],
        reason: 'mesma severidade: a mais antiga primeiro',
      );
      expect(
        filtrarPendencias(
          todas,
          const FiltroPendencias(diasMinimos: 7),
        ).map((p) => p.id),
        ['p-acelerar'],
      );
    });

    test('o filtro devolve ordenado, não na ordem de entrada', () {
      final invertida = todas.reversed.toList();
      expect(
        filtrarPendencias(
          invertida,
          FiltroPendencias.semFiltro,
        ).map((p) => p.ordemSeveridade),
        [1, 1, 1, 2, 2, 3],
      );
    });

    test('ativos conta quantos filtros estão ligados', () {
      expect(FiltroPendencias.semFiltro.ativos, 0);
      expect(
        const FiltroPendencias(severidade: 'ALTA', diasMinimos: 3).ativos,
        2,
      );
    });

    test('copiar apaga com a função que devolve nulo', () {
      const cheio = FiltroPendencias(severidade: 'ALTA', tipo: 'REP_VIRADA');
      expect(cheio.copiar(tipo: () => null).tipo, isNull);
      expect(
        cheio.copiar(tipo: () => null).severidade,
        'ALTA',
        reason: 'o que não é citado não muda',
      );
    });
  });

  group('contador do menu', () {
    test('conta só as ALTA abertas, não o total', () {
      // Card 2.6 decisão (f): um sino que dispara sempre é ignorado.
      final todas = PendenciasFalso.fixture().pendencias_;
      expect(todas.length, 6);
      expect(contarAltas(todas), 3);
    });

    test('lista vazia é zero', () => expect(contarAltas(const []), 0));
  });

  group('textos', () {
    test('os quinze tipos do check têm rótulo', () {
      // O `check` de `pendencia.tipo` aceita quinze; os nove das fases 6 e 8 já
      // estão aqui para a primeira COMPRA_SEM_ESTOQUE da fase 6 não aparecer
      // como código cru na tela, sem erro nenhum.
      expect(tiposPendencia.length, 15);
      expect(
        rotuloTipoPendencia('COMPRA_SEM_ESTOQUE'),
        isNot('COMPRA_SEM_ESTOQUE'),
      );
      expect(rotuloTipoPendencia('INVENTADO'), 'INVENTADO');
    });

    test('só as três severidades do check — INFO não existe', () {
      expect(severidadesPendencia.keys, ['ALTA', 'MEDIA', 'BAIXA']);
      expect(rotuloSeveridade('MEDIA'), 'MÉDIA');
    });

    test('a idade tem singular, plural e "hoje"', () {
      expect(rotuloIdade(0), 'hoje');
      expect(rotuloIdade(1), 'há 1 dia');
      expect(rotuloIdade(12), 'há 12 dias');
    });

    test('ignorar NÃO promete silêncio permanente (card 5.5 c)', () {
      // `pendencia_aberta_uk` é único parcial: fechada, a rotina reabre. O
      // diálogo que prometesse "não me avise mais" mentiria todo dia às 03:10.
      expect(avisoIgnorar, contains('não silencia para sempre'));
      expect(avisoIgnorar, contains('03:10'));
    });

    test('quem fecha sozinha diz quando, e o resto não inventa', () {
      expect(fechamentoAutomatico('ALUNO_SEM_TURMA'), isNotNull);
      expect(fechamentoAutomatico('REP_VIRADA'), isNotNull);
      expect(fechamentoAutomatico('ROTINA_FALHOU'), isNotNull);
      expect(fechamentoAutomatico('COMPRA_SEM_ESTOQUE'), isNull);
    });
  });
}
