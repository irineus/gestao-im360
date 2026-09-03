import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/infraestrutura/infraestrutura.dart';

/// A lógica pura da tela de Salas e PCs (card 4.5): o que a tela deriva sem
/// rede — capacidade efetiva, manutenção em aberto, ação contextual, datas e
/// filtros. Regra de negócio continua no banco; aqui só há forma.
void main() {
  final hoje = DateTime(2026, 9, 2);

  group('capacidade efetiva da sala', () {
    test('PCs operacionais até o teto nominal — os três números da fixture '
        'do card 4.3 são distintos de propósito', () {
      const lab2 = Sala(
        id: 's-lab2',
        nome: 'Laboratório 2',
        tipo: 'LABORATORIO',
        capacidadeNominal: 6,
      );
      final pcs = [
        for (var i = 1; i <= 4; i++)
          Pc(id: 'pc-$i', salaId: 's-lab2', identificador: 'LAB2-0$i'),
        const Pc(
          id: 'pc-5',
          salaId: 's-lab2',
          identificador: 'LAB2-05',
          status: 'MANUTENCAO',
        ),
        const Pc(
          id: 'pc-6',
          salaId: 's-lab2',
          identificador: 'LAB2-06',
          status: 'DESATIVADO',
        ),
      ];
      final resumo = resumirSalas([lab2], pcs)['s-lab2']!;
      expect(resumo.total, 6);
      expect(resumo.operacionais, 4);
      expect(resumo.efetiva, 4);
    });

    test('o teto nominal vence quando há mais PCs do que vagas', () {
      expect(capacidadeEfetiva(nominal: 3, operacionais: 5), 3);
      expect(capacidadeEfetiva(nominal: 10, operacionais: 10), 10);
      expect(capacidadeEfetiva(nominal: 15, operacionais: 0), 0);
    });

    test('sala sem PC aparece no resumo com zero, não some', () {
      const ele = Sala(
        id: 's-ele',
        nome: 'Sala Eletricista',
        tipo: 'SALA_MODULAR',
        capacidadeNominal: 15,
      );
      expect(resumirSalas([ele], const [])['s-ele'], isNotNull);
      expect(resumirSalas([ele], const [])['s-ele']!.efetiva, 0);
    });
  });

  group('manutenção em aberto', () {
    PcManutencao manutencao({DateTime? fim, DateTime? inicio}) => PcManutencao(
      id: 'm',
      pcId: 'pc-1',
      tipo: 'CORRETIVA',
      dataInicio: inicio ?? hoje.subtract(const Duration(days: 3)),
      dataFim: fim,
    );

    test('sem fim, ou com o fim à frente, está aberta; fim hoje ou no '
        'passado, encerrada', () {
      expect(manutencao().abertaEm(hoje), isTrue);
      expect(
        manutencao(fim: hoje.add(const Duration(days: 3))).abertaEm(hoje),
        isTrue,
      );
      expect(manutencao(fim: hoje).abertaEm(hoje), isFalse);
      expect(
        manutencao(fim: hoje.subtract(const Duration(days: 1))).abertaEm(hoje),
        isFalse,
      );
    });

    test('manutencoesAbertas indexa por PC e fica com a mais recente', () {
      final antiga = PcManutencao(
        id: 'm-antiga',
        pcId: 'pc-1',
        tipo: 'PREVENTIVA',
        dataInicio: hoje.subtract(const Duration(days: 30)),
      );
      final recente = manutencao();
      final fechada = manutencao(
        fim: hoje.subtract(const Duration(days: 59)),
        inicio: hoje.subtract(const Duration(days: 60)),
      );
      final abertas = manutencoesAbertas([antiga, fechada, recente], hoje);
      expect(abertas.keys, ['pc-1']);
      expect(abertas['pc-1']!.id, 'm');
    });

    test('a ação contextual segue o wireframe §13', () {
      const operacional = Pc(id: 'a', salaId: 's', identificador: 'A');
      const desativado = Pc(
        id: 'b',
        salaId: 's',
        identificador: 'B',
        status: 'DESATIVADO',
      );
      expect(acaoContextual(operacional, null), AcaoPc.registrarManutencao);
      expect(
        acaoContextual(operacional, manutencao()),
        AcaoPc.encerrarManutencao,
      );
      expect(acaoContextual(desativado, null), AcaoPc.reativar);
      expect(
        acaoContextual(desativado, manutencao()),
        AcaoPc.encerrarManutencao,
        reason: 'manutenção aberta vem antes do status',
      );
    });

    test('a linha de situação diz o status, a manutenção e o que falta', () {
      const pc = Pc(
        id: 'a',
        salaId: 's',
        identificador: 'A',
        status: 'MANUTENCAO',
      );
      expect(
        situacaoPc(pc, manutencao(inicio: DateTime(2026, 8, 30))),
        'Em manutenção · corretiva desde 30/08 · sem substituto',
      );
      final comFim = PcManutencao(
        id: 'm',
        pcId: 'a',
        tipo: 'PREVENTIVA',
        dataInicio: DateTime(2026, 8, 30),
        dataFim: DateTime(2026, 9, 5),
        pcSubstitutoId: 'b',
      );
      expect(
        situacaoPc(pc, comFim),
        'Em manutenção · preventiva desde 30/08 · prevista até 05/09',
      );
      expect(situacaoPc(pc, null), 'Em manutenção');
    });
  });

  group('datas dd/mm/aaaa', () {
    test('lê e formata de volta', () {
      expect(lerData('05/09/2026'), DateTime(2026, 9, 5));
      expect(formatarData(DateTime(2026, 9, 5)), '05/09/2026');
      expect(dataIso(DateTime(2026, 9, 5)), '2026-09-05');
    });

    test('recusa data que não existe e formato fora do padrão', () {
      expect(lerData('31/02/2026'), isNull);
      expect(lerData('2026-09-05'), isNull);
      expect(lerData('5/9/2026'), isNull);
      expect(lerData(''), isNull);
    });

    test('validação local só de formato', () {
      expect(validarData(''), 'Campo obrigatório.');
      expect(validarData('', obrigatorio: false), isNull);
      expect(validarData('31/02/2026'), 'Informe uma data como dd/mm/aaaa.');
      expect(validarData('05/09/2026'), isNull);
    });
  });

  group('filtros', () {
    const salas = [
      Sala(
        id: '1',
        nome: 'Laboratório 1',
        tipo: 'LABORATORIO',
        capacidadeNominal: 10,
      ),
      Sala(
        id: '2',
        nome: 'Sala Eletricista',
        tipo: 'SALA_MODULAR',
        capacidadeNominal: 15,
      ),
      Sala(
        id: '3',
        nome: 'Depósito',
        tipo: 'LABORATORIO',
        capacidadeNominal: 4,
        ativo: false,
      ),
    ];

    test('só ativas por padrão; "Limpar filtros" mostra tudo', () {
      expect(filtrarSalas(salas, const FiltroSalas()).map((s) => s.id), [
        '1',
        '2',
      ]);
      expect(filtrarSalas(salas, FiltroSalas.semFiltro).length, 3);
      expect(FiltroSalas.semFiltro.ativos, 0);
    });

    test('tipo e busca', () {
      expect(
        filtrarSalas(salas, const FiltroSalas(tipo: 'SALA_MODULAR')).single.id,
        '2',
      );
      expect(
        filtrarSalas(salas, const FiltroSalas(busca: 'eletri')).single.id,
        '2',
      );
      expect(const FiltroSalas(busca: 'x', tipo: 'LABORATORIO').ativos, 3);
    });

    test('professores: só ativos por padrão, busca por nome', () {
      const professores = [
        Professor(id: '1', nome: 'Marcos Vieira'),
        Professor(id: '2', nome: 'Otávio Pacheco', ativo: false),
      ];
      expect(
        filtrarProfessores(professores, const FiltroProfessores()).single.id,
        '1',
      );
      expect(
        filtrarProfessores(professores, FiltroProfessores.semFiltro).length,
        2,
      );
      expect(
        filtrarProfessores(
          professores,
          const FiltroProfessores(busca: 'pacheco', soAtivos: false),
        ).single.id,
        '2',
      );
    });
  });

  test('CredencialPc não imprime a senha', () {
    const credencial = CredencialPc(usuario: 'lab1', senha: 'segredo');
    expect('$credencial', contains('lab1'));
    expect('$credencial', isNot(contains('segredo')));
  });

  test('Pc.paraLinha nunca leva as colunas de credencial', () {
    final linha = Pc(
      id: 'a',
      salaId: 's',
      identificador: 'A',
      credencialEm: DateTime(2026, 9, 2),
    ).paraLinha('u');
    expect(linha.keys, isNot(contains('credencial_em')));
    expect(linha.keys, isNot(contains('credencial_secret_id')));
  });
}
