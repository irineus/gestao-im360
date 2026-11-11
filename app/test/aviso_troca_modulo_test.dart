import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/pendencias/pendencias.dart';
import 'package:gestao_im360/telas/dashboard/atencao_hoje.dart';
import 'package:gestao_im360/telas/dashboard/lotacao_modular.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/turmas/modular.dart';

import 'apoio/modular_falso.dart';

/// O aviso de troca de módulo no app (card 9.2,86) — a metade de tela do card
/// 9.2,85.
///
/// O que este arquivo prende e nenhum outro enxerga:
///
///   • **a tela não decide a situação**: laranja e vermelho chegam de
///     `situacao_troca`, e um código que o app não conhece vira nulo — nunca
///     "em dia";
///   • **o painel ordena pela troca mais próxima**, com a vencida antes de
///     todas, e deixa de fora quem não tem previsão;
///   • **a turma da pendência sai da chave**, e chave fora do formato não
///     oferece ação;
///   • **o item de "Atenção hoje" só existe para quem tem a permissão** — para
///     os outros a RLS não devolve a linha, e mostrar zero seria um número que
///     ninguém mediu.
void main() {
  TurmaModular turma(
    String nome, {
    String curso = 'Chef Profissional',
    int? dias,
    SituacaoTroca? situacao,
    bool? trocaDeLivro,
    String? proximo = 'Carnes, Aves e Suínos',
    bool comModulo = true,
  }) => turmaModularFalsa(
    id: 't-$nome',
    nome: nome,
    cursoNome: curso,
    moduloCorrenteId: comModulo ? 'mod-1' : null,
    moduloCorrenteNome: comModulo ? 'Garde Manger' : null,
    moduloCorrenteOrdem: comModulo ? 1 : null,
    moduloCorrentePrevConclusao: dias == null ? null : DateTime(2026, 11, 16),
    proximoModuloNome: proximo,
    proximoMaterialId: trocaDeLivro == true ? 'mat-pan' : null,
    proximoMaterialNome: trocaDeLivro == true ? 'Panificação' : null,
    trocaDeLivro: trocaDeLivro,
    diasParaTroca: dias,
    situacaoTroca: situacao,
  );

  group('a situação vem do banco', () {
    test('os quatro códigos da view viram o enum', () {
      expect(situacaoTrocaDe('EM_DIA'), SituacaoTroca.emDia);
      expect(situacaoTrocaDe('PROXIMA'), SituacaoTroca.proxima);
      expect(situacaoTrocaDe('HOJE_OU_VENCIDA'), SituacaoTroca.hojeOuVencida);
      expect(situacaoTrocaDe('SEM_PREVISAO'), SituacaoTroca.semPrevisao);
    });

    test('código desconhecido e nulo viram NULO, nunca "em dia"', () {
      expect(situacaoTrocaDe('QUINTA_SITUACAO'), isNull);
      expect(situacaoTrocaDe(null), isNull);
    });

    test('a linha da view preenche o aviso', () {
      final t = TurmaModular.deLinha({
        'turma_id': 't1',
        'turma_nome': 'Chef 2026',
        'curso_id': 'c1',
        'curso_nome': 'Chef Profissional',
        'sala_id': 's1',
        'sala_nome': 'Cozinha',
        'capacidade': 12,
        'alocados': 11,
        'vagas_livres': 1,
        'modulo_corrente_id': 'm4',
        'modulo_corrente_nome': 'Massas e Molhos',
        'modulo_corrente_ordem': 4,
        'modulo_corrente_prev_conclusao': '2026-11-16',
        'modulo_corrente_cronograma_id': 'cr4',
        'proximo_modulo_nome': 'Produção de Fermentos Naturais',
        'proximo_material_id': 'mat-pan',
        'proximo_material_nome': 'Panificação',
        'troca_de_livro': true,
        'dias_para_troca': 6,
        'situacao_troca': 'PROXIMA',
      });
      expect(t.situacaoTroca, SituacaoTroca.proxima);
      expect(t.diasParaTroca, 6);
      expect(t.trocaDeLivro, isTrue);
      expect(t.trocaEmAviso, isTrue);
      expect(t.moduloCorrenteCronogramaId, 'cr4');
      expect(
        rotuloTroca(t),
        '4. Massas e Molhos → Produção de Fermentos Naturais',
      );
      expect(
        avisoTrocaDeLivro(t),
        'O próximo módulo, Produção de Fermentos Naturais, é de outro livro: '
        'Panificação.',
      );
    });

    test('linha da view ANTERIOR ao card 9.2,85 continua lendo, sem aviso', () {
      final t = TurmaModular.deLinha({
        'turma_id': 't1',
        'turma_nome': 'Chef 2026',
        'curso_id': 'c1',
        'curso_nome': 'Chef Profissional',
        'sala_id': 's1',
        'sala_nome': 'Cozinha',
      });
      expect(t.situacaoTroca, isNull);
      expect(t.trocaEmAviso, isFalse);
      expect(seloTroca(t), isNull);
    });
  });

  group('os textos do aviso', () {
    test('quanto falta, por extenso', () {
      expect(rotuloDiasParaTroca(10), 'faltam 10 dias');
      expect(rotuloDiasParaTroca(1), 'falta 1 dia');
      expect(rotuloDiasParaTroca(0), 'hoje');
      expect(rotuloDiasParaTroca(-1), 'atrasada há 1 dia');
      expect(rotuloDiasParaTroca(-40), 'atrasada há 40 dias');
    });

    test('o selo só existe dentro do aviso', () {
      expect(
        seloTroca(turma('a', dias: 5, situacao: SituacaoTroca.proxima)),
        'troca de módulo em 5 dias',
      );
      expect(
        seloTroca(turma('a', dias: 1, situacao: SituacaoTroca.proxima)),
        'troca de módulo amanhã',
      );
      expect(
        seloTroca(turma('a', dias: 0, situacao: SituacaoTroca.hojeOuVencida)),
        'troca de módulo hoje',
      );
      expect(
        seloTroca(turma('a', dias: -3, situacao: SituacaoTroca.hojeOuVencida)),
        'troca de módulo atrasada há 3 dias',
      );
      expect(
        seloTroca(turma('a', dias: 35, situacao: SituacaoTroca.emDia)),
        isNull,
        reason: 'turma em dia não ganha selo: o aviso é o que pede ação',
      );
    });

    test('sem próximo módulo o rótulo é só o corrente', () {
      expect(
        rotuloTroca(
          turma('a', dias: 5, situacao: SituacaoTroca.proxima, proximo: null),
        ),
        '1. Garde Manger',
      );
    });

    test('a confirmação do avanço diz quantos livros saíram', () {
      expect(
        const ResultadoAvanco(terminou: false).confirmacao,
        'Módulo avançado.',
      );
      expect(
        const ResultadoAvanco(terminou: false, entregues: 1).confirmacao,
        'Módulo avançado. 1 livro entregue.',
      );
      expect(
        const ResultadoAvanco(terminou: false, entregues: 8).confirmacao,
        'Módulo avançado. 8 livros entregues.',
      );
    });
  });

  group('próximas trocas', () {
    test('da mais próxima para a mais distante, a vencida primeiro', () {
      final lista = proximasTrocas([
        turma('longe', dias: 35, situacao: SituacaoTroca.emDia),
        turma('hoje', dias: 0, situacao: SituacaoTroca.hojeOuVencida),
        turma('perto', dias: 6, situacao: SituacaoTroca.proxima),
        turma('vencida', dias: -4, situacao: SituacaoTroca.hojeOuVencida),
      ]);
      expect(
        [for (final t in lista) t.nome],
        ['vencida', 'hoje', 'perto', 'longe'],
      );
    });

    test('sem previsão e sem módulo corrente ficam de fora', () {
      final lista = proximasTrocas([
        turma('sem previsão', situacao: SituacaoTroca.semPrevisao),
        turma('terminou', dias: 3, comModulo: false),
        turma('com data', dias: 3, situacao: SituacaoTroca.proxima),
      ]);
      expect([for (final t in lista) t.nome], ['com data']);
    });

    test('empate de dias desempata por curso e turma — ordem total', () {
      final lista = proximasTrocas([
        turma('Quarta', curso: 'Massagem', dias: 5),
        turma('Terça', curso: 'Massagem', dias: 5),
        turma('2026', curso: 'Chef Profissional', dias: 5),
      ]);
      expect([for (final t in lista) t.nome], ['2026', 'Quarta', 'Terça']);
    });
  });

  group('a pendência TROCA_MODULO_ALINHAR', () {
    Pendencia pendencia(String chave) => Pendencia(
      id: 'p1',
      tipo: 'TROCA_MODULO_ALINHAR',
      severidade: 'MEDIA',
      ordemSeveridade: 2,
      descricao: 'Turma Chef 2026 (Chef Profissional): …',
      chaveDedup: chave,
      criadoEm: DateTime(2026, 11, 6),
      diasAberta: 0,
    );

    test('tem rótulo, ação e destino', () {
      expect(
        rotuloTipoPendencia('TROCA_MODULO_ALINHAR'),
        'Troca de módulo — alinhar com o professor',
      );
      expect(acaoDe('TROCA_MODULO_ALINHAR'), AcaoPendencia.verTurmaModular);
      expect(rotuloAcaoPendencia('TROCA_MODULO_ALINHAR'), 'Ver turma');
      expect(rotaDaAcao(AcaoPendencia.verTurmaModular), 'turmas_modular');
      expect(parametroDaAcao(AcaoPendencia.verTurmaModular), 'turma');
    });

    test('a turma sai da chave', () {
      final p = pendencia('TROCA_MODULO:turma-1:crono-9');
      expect(turmaModularDaChave(p.chaveDedup), 'turma-1');
      expect(idDaAcao(p), 'turma-1');
      expect(referenciaDaAcaoPresente(p), isTrue);
    });

    test('chave fora do formato não oferece ação', () {
      for (final chave in [
        'TROCA_MODULO:turma-1',
        'CRONOGRAMA:turma-1:crono-9',
        'TROCA_MODULO::crono-9',
        '',
      ]) {
        expect(turmaModularDaChave(chave), isNull, reason: chave);
        expect(referenciaDaAcaoPresente(pendencia(chave)), isFalse);
      }
    });

    test('a tela DIZ que avançar o módulo não a fecha', () {
      final texto = fechamentoAutomatico('TROCA_MODULO_ALINHAR')!;
      expect(texto, contains('Avançar o módulo não a fecha'));
      expect(texto, contains('não volta para este módulo'));
    });

    test('"Atenção hoje" só conta a troca para quem tem a permissão', () {
      final abertas = [
        pendencia('TROCA_MODULO:t1:c1'),
        pendencia('TROCA_MODULO:t2:c2'),
      ];
      final sem = itensAtencao(abertas);
      expect(sem, hasLength(3));
      expect(
        sem.any((i) => i.filtro.tipo == 'TROCA_MODULO_ALINHAR'),
        isFalse,
        reason:
            'sem turmas.alinhar_modulo a RLS não devolve a linha: um "0 trocas '
            'a alinhar" seria um zero que ninguém mediu',
      );

      final com = itensAtencao(abertas, comTrocaDeModulo: true);
      expect(com, hasLength(4));
      expect(com.last.quantidade, 2);
      expect(com.last.rotulo, 'trocas de módulo a alinhar com o professor');
      expect(com.last.filtro.tipo, 'TROCA_MODULO_ALINHAR');
    });
  });

  group('o painel do Dashboard', () {
    Future<void> montar(
      WidgetTester tester,
      List<TurmaModular> turmas, {
      Size tamanho = const Size(1400, 900),
    }) async {
      tester.view.physicalSize = tamanho;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: temaClaro(),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ProximasTrocasModulo(turmas: turmas),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    final turmas = [
      turma('Chef 2026', dias: 35, situacao: SituacaoTroca.emDia),
      turma(
        'Terça',
        curso: 'Massagem',
        dias: 6,
        situacao: SituacaoTroca.proxima,
        trocaDeLivro: true,
      ),
      turma(
        'Quarta',
        curso: 'Massagem',
        dias: 0,
        situacao: SituacaoTroca.hojeOuVencida,
      ),
    ];

    testWidgets('uma linha por turma, com o que fecha, o que abre, a data e '
        'quanto falta', (tester) async {
      await montar(tester, turmas);

      expect(find.text(tituloProximasTrocas), findsOneWidget);
      expect(find.text('Massagem · Quarta'), findsOneWidget);
      expect(find.text('Massagem · Terça'), findsOneWidget);
      expect(find.text('Chef Profissional · Chef 2026'), findsOneWidget);
      expect(
        find.text('1. Garde Manger → Carnes, Aves e Suínos'),
        findsNWidgets(3),
      );
      // A cor nunca vai sozinha (design-system §8.2): o texto diz quanto falta.
      expect(find.text('16/11/2026 · hoje'), findsOneWidget);
      expect(find.text('16/11/2026 · faltam 6 dias'), findsOneWidget);
      expect(find.text('16/11/2026 · faltam 35 dias'), findsOneWidget);
      // E a troca de livro só aparece onde há.
      expect(find.text('troca de livro: Panificação'), findsOneWidget);
    });

    testWidgets('a ordem na tela é a da troca mais próxima', (tester) async {
      await montar(tester, turmas);
      final hoje = tester.getTopLeft(find.text('Massagem · Quarta')).dy;
      final perto = tester.getTopLeft(find.text('Massagem · Terça')).dy;
      final longe = tester
          .getTopLeft(find.text('Chef Profissional · Chef 2026'))
          .dy;
      expect(hoje, lessThan(perto));
      expect(perto, lessThan(longe));
    });

    testWidgets('sem nenhuma previsão, o painel diz por quê em vez de sumir', (
      tester,
    ) async {
      await montar(tester, [
        turma('Sem data', situacao: SituacaoTroca.semPrevisao),
      ]);
      expect(find.text(tituloProximasTrocas), findsOneWidget);
      expect(find.text(vazioProximasTrocas), findsOneWidget);
    });

    testWidgets('cabe em 390 px sem estourar', (tester) async {
      await montar(tester, [
        turma(
          'Turma de nome comprido para o celular 2026.2',
          curso: 'Chef Profissional e Panificação',
          dias: 6,
          situacao: SituacaoTroca.proxima,
          trocaDeLivro: true,
          proximo: 'Produção de Fermentos Naturais',
        ),
      ], tamanho: const Size(390, 800));
      expect(tester.takeException(), isNull);
    });

    testWidgets('o leitor de tela ouve a linha inteira de uma vez', (
      tester,
    ) async {
      final t = turmas[1];
      expect(
        descricaoTroca(t),
        'Massagem, Terça, 1. Garde Manger → Carnes, Aves e Suínos, '
        'previsão 16/11/2026, faltam 6 dias, troca de livro',
      );
    });
  });
}
