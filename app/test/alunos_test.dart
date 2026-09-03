import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/alunos/alunos.dart';
import 'package:gestao_im360/util/datas.dart';

/// A lógica pura da tela de Alunos (card 4.6): o que o menu de status
/// oferece — conferido contra a tabela de `fn_aluno_transicao_valida` —, os
/// filtros e a forma das linhas que vão e vêm do PostgREST.
void main() {
  group('transições que o menu oferece (docs/wireframes.md §6.2)', () {
    test('é exatamente a tabela de fn_aluno_transicao_valida', () {
      // Cópia literal do `select (p_de, p_para) in (...)` do card 4.2, mais
      // "qualquer origem vai a CANCELADO, menos CANCELADO nele mesmo" —
      // escrita à mão de propósito, para o teste não concordar consigo mesmo.
      const doBanco = {
        ('ATIVO', 'ACELERAR'),
        ('ACELERAR', 'ATIVO'),
        ('ATIVO', 'STANDBY'),
        ('ACELERAR', 'STANDBY'),
        ('STANDBY', 'ATIVO'),
        ('STANDBY', 'ACELERAR'),
        ('STANDBY', 'TRANCADO'),
        ('TRANCADO', 'ATIVO'),
        ('TRANCADO', 'ACELERAR'),
        ('ATIVO', 'FORMADO'),
        ('ACELERAR', 'FORMADO'),
        ('ATIVO', 'CANCELADO'),
        ('ACELERAR', 'CANCELADO'),
        ('STANDBY', 'CANCELADO'),
        ('TRANCADO', 'CANCELADO'),
        ('FORMADO', 'CANCELADO'),
      };
      final doApp = {
        for (final de in statusAluno.keys)
          for (final para in transicoesDe(de)) (de, para),
      };
      expect(doApp, doBanco);
    });

    test('status igual não é transição, e CANCELADO só sai por reversão', () {
      for (final s in statusAluno.keys) {
        expect(transicoesDe(s), isNot(contains(s)));
      }
      expect(transicoesDe('CANCELADO'), isEmpty);
      expect(transicoesDe('XPTO'), isEmpty);
    });

    test('a reversão sai só de terminal e só chega a não terminal', () {
      expect(destinosReversao('FORMADO'), [
        'ATIVO',
        'ACELERAR',
        'STANDBY',
        'TRANCADO',
      ]);
      expect(destinosReversao('CANCELADO'), destinosReversao('FORMADO'));
      expect(destinosReversao('ATIVO'), isEmpty);
      expect(destinosReversao('STANDBY'), isEmpty);
    });

    test('sair de ATIVO/ACELERAR remove das turmas — o aviso do §7.3', () {
      expect(saiDasTurmas(de: 'ATIVO', para: 'STANDBY'), isTrue);
      expect(saiDasTurmas(de: 'ACELERAR', para: 'FORMADO'), isTrue);
      expect(saiDasTurmas(de: 'ATIVO', para: 'ACELERAR'), isFalse);
      expect(saiDasTurmas(de: 'STANDBY', para: 'TRANCADO'), isFalse);
      expect(saiDasTurmas(de: 'STANDBY', para: 'ATIVO'), isFalse);
    });
  });

  group('linhas do PostgREST', () {
    test('deLinha lê datas e nulos; paraLinha nunca leva o status', () {
      final aluno = Aluno.deLinha({
        'id': 'a1',
        'codigo_sgf': null,
        'nome': 'Karina Bastos',
        'metodo_id': 'm-int',
        'combo_id': null,
        'status': 'ATIVO',
        'status_desde': '2026-08-19',
        'prev_conclusao_curso': null,
        'data_inicio': '2026-08-19',
        'observacoes': null,
        'conferido': false,
      });
      expect(aluno.codigoSgf, isNull);
      expect(aluno.comboId, isNull);
      expect(aluno.statusDesde, DateTime(2026, 8, 19));
      expect(aluno.emAula, isTrue);
      expect(aluno.terminal, isFalse);

      final linha = Aluno(
        id: 'a1',
        nome: '  Karina Bastos ',
        metodoId: 'm-int',
        codigoSgf: '   ',
        status: 'STANDBY',
        dataInicio: DateTime(2026, 8, 19),
        prevConclusaoCurso: DateTime(2027, 3, 1),
        observacoes: '',
      ).paraLinha('u1');
      expect(linha['unidade_id'], 'u1');
      expect(linha['nome'], 'Karina Bastos');
      // String vazia colidiria no índice parcial de codigo_sgf (card 4.2 d).
      expect(linha['codigo_sgf'], isNull);
      expect(linha['observacoes'], isNull);
      expect(linha['data_inicio'], '2026-08-19');
      expect(linha['prev_conclusao_curso'], '2027-03-01');
      expect(linha.containsKey('status'), isFalse);
      expect(linha.containsKey('status_desde'), isFalse);
    });

    test('a transição lê o nome do embed quando a RLS o deixa ver', () {
      final comNome = TransicaoStatus.deLinha({
        'id': 'h1',
        'status_anterior': 'ATIVO',
        'status_novo': 'STANDBY',
        'ocorrido_em': '2026-09-01T12:00:00+00:00',
        'motivo': 'viagem',
        'usuario': {'nome': 'Secretária'},
      });
      expect(comNome.usuarioNome, 'Secretária');
      expect(comNome.motivo, 'viagem');
      final semNome = TransicaoStatus.deLinha({
        'id': 'h2',
        'status_anterior': null,
        'status_novo': 'ATIVO',
        'ocorrido_em': '2026-09-01T12:00:00+00:00',
        'motivo': null,
        'usuario': null,
      });
      expect(semNome.usuarioNome, isNull);
      expect(semNome.statusAnterior, isNull);
    });

    test('formatarDataHora', () {
      expect(formatarDataHora(DateTime(2026, 9, 3, 7, 5)), '03/09/2026 07:05');
    });
  });

  group('filtros', () {
    const alunos = [
      Aluno(
        id: 'a',
        nome: 'Ana Paula',
        codigoSgf: '3001',
        metodoId: 'm-int',
        comboId: 'cb-info',
      ),
      Aluno(
        id: 'b',
        nome: 'Bruno',
        codigoSgf: '3002',
        metodoId: 'm-ing',
        comboId: 'cb-kids',
        status: 'STANDBY',
      ),
      Aluno(id: 'c', nome: 'Carla', metodoId: 'm-int', status: 'FORMADO'),
      Aluno(id: 'd', nome: 'Diego', metodoId: 'm-int', status: 'CANCELADO'),
    ];
    List<String> ids(FiltroAlunos f) =>
        filtrarAlunos(alunos, f).map((a) => a.id!).toList();

    test('o padrão esconde os terminais; semFiltro mostra tudo', () {
      expect(ids(const FiltroAlunos()), ['a', 'b']);
      expect(ids(FiltroAlunos.semFiltro), ['a', 'b', 'c', 'd']);
      expect(const FiltroAlunos().ativos, 1);
      expect(FiltroAlunos.semFiltro.ativos, 0);
    });

    test('busca por nome ou código SGF, sem caixa', () {
      expect(ids(const FiltroAlunos(busca: 'ana')), ['a']);
      expect(ids(const FiltroAlunos(busca: '300')), ['a', 'b']);
      expect(ids(const FiltroAlunos(busca: 'carla')), isEmpty);
      expect(
        ids(const FiltroAlunos(busca: 'carla', ocultarEncerrados: false)),
        ['c'],
      );
    });

    test('método, status e combo', () {
      expect(ids(const FiltroAlunos(metodoId: 'm-ing')), ['b']);
      expect(ids(const FiltroAlunos(status: 'STANDBY')), ['b']);
      expect(
        ids(const FiltroAlunos(status: 'FORMADO', ocultarEncerrados: false)),
        ['c'],
      );
      expect(ids(const FiltroAlunos(comboId: 'cb-info')), ['a']);
      expect(
        const FiltroAlunos(
          busca: 'x',
          metodoId: 'm',
          status: 's',
          comboId: 'c',
        ).ativos,
        5,
      );
    });

    test('copiar troca só o que foi passado, inclusive para nulo', () {
      const f = FiltroAlunos(metodoId: 'm-int', comboId: 'cb-info');
      expect(f.copiar(busca: 'a').metodoId, 'm-int');
      expect(f.copiar(comboId: () => null).comboId, isNull);
      expect(f.copiar(comboId: () => null).metodoId, 'm-int');
    });
  });
}
