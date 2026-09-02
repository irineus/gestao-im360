import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/catalogo/catalogo.dart';

import 'apoio/catalogo_falso.dart';

/// A lógica pura do catálogo (card 4.4): filtros da tela e o plano de gravação
/// de uma sequência ordenada — o que se prova sem rede e sem Supabase.
void main() {
  final fixture = CatalogoFalso.fixture();
  final materiais = fixture.materiais_;

  group('filtros', () {
    test('sem filtro além do padrão, tudo o que é ativo aparece', () {
      expect(filtrarMateriais(materiais, const FiltroCatalogo()), materiais);
    });

    test('"só ativos" vem ligado por padrão e esconde o inativo', () {
      final comInativo = [
        ...materiais,
        const MaterialDidatico(
          id: 'x',
          metodoId: 'm-int',
          codigo: '99',
          nome: 'Aposentada',
          categoria: 'APOSTILA',
          ativo: false,
        ),
      ];
      expect(
        filtrarMateriais(comInativo, const FiltroCatalogo()).length,
        materiais.length,
      );
      expect(
        filtrarMateriais(comInativo, FiltroCatalogo.semFiltro).length,
        materiais.length + 1,
      );
    });

    test('busca casa código e nome, sem distinguir caixa', () {
      expect(
        filtrarMateriais(
          materiais,
          const FiltroCatalogo(busca: 'english'),
        ).map((m) => m.id),
        ['mat-ing-01', 'mat-ing-02'],
      );
      // "01" existe nos três métodos de propósito (card 4.1): a busca por
      // código não pode devolver um só.
      expect(
        filtrarMateriais(materiais, const FiltroCatalogo(busca: '01')).length,
        3,
      );
    });

    test('método e categoria restringem em conjunto', () {
      expect(
        filtrarMateriais(
          materiais,
          const FiltroCatalogo(metodoId: 'm-mod', categoria: 'LIVRO'),
        ).single.id,
        'mat-mod-01',
      );
      expect(
        filtrarMateriais(
          materiais,
          const FiltroCatalogo(metodoId: 'm-mod', categoria: 'APOSTILA'),
        ),
        isEmpty,
      );
    });

    test('o contador de filtros ligados conta o "só ativos"', () {
      expect(const FiltroCatalogo().ativos, 1);
      expect(FiltroCatalogo.semFiltro.ativos, 0);
      expect(
        const FiltroCatalogo(busca: 'a', metodoId: 'm', categoria: 'c').ativos,
        4,
      );
    });

    test('copiar troca só o que foi pedido, inclusive para nulo', () {
      const base = FiltroCatalogo(busca: 'x', metodoId: 'm-int');
      final semMetodo = base.copiar(metodoId: () => null);
      expect(semMetodo.busca, 'x');
      expect(semMetodo.metodoId, isNull);
      expect(base.copiar(soAtivos: false).metodoId, 'm-int');
    });

    test('categorias em uso saem ordenadas e sem repetição', () {
      expect(categoriasDe(materiais), ['APOSTILA', 'LIVRO']);
    });

    test('cursos e combos filtram por nome, método e ativo', () {
      expect(
        filtrarCursos(
          fixture.cursos_,
          const FiltroCatalogo(metodoId: 'm-int'),
        ).map((c) => c.id),
        ['c-av', 'c-ess'],
      );
      expect(
        filtrarCombos(
          fixture.combos_,
          const FiltroCatalogo(busca: 'kids'),
        ).single.id,
        'cb-kids',
      );
    });
  });

  group('plano de gravação da sequência', () {
    const atuais = [
      LinhaOrdenada(id: 'l1', filhoId: 'a', ordem: 1),
      LinhaOrdenada(id: 'l2', filhoId: 'b', ordem: 2),
      LinhaOrdenada(id: 'l3', filhoId: 'c', ordem: 3),
    ];

    PlanoSequencia planejar(List<String> desejados) => planejarSequencia(
      atuais: atuais,
      desejados: desejados,
      unidadeId: 'u',
      colunaPai: 'curso_id',
      paiId: 'curso',
      colunaFilho: 'material_id',
    );

    test('sem mudança, nada a gravar', () {
      expect(planejar(['a', 'b', 'c']).vazio, isTrue);
    });

    test(
      'trocar duas posições é UM lote de atualização — o caso do deferrable',
      () {
        final plano = planejar(['b', 'a', 'c']);
        expect(plano.apagar, isEmpty);
        expect(plano.inserir, isEmpty);
        expect(plano.atualizar.map((l) => l['id']), ['l2', 'l1']);
        expect(plano.atualizar.map((l) => l['ordem']), [1, 2]);
        // As linhas atualizadas carregam a unidade: a política de update do
        // card 4.1 exige `unidade_id = fn_unidade_atual()` no with check.
        expect(plano.atualizar.first['unidade_id'], 'u');
        expect(plano.atualizar.first['curso_id'], 'curso');
      },
    );

    test('remover do meio apaga a linha e reposiciona as seguintes', () {
      final plano = planejar(['a', 'c']);
      expect(plano.apagar, ['l2']);
      expect(plano.atualizar.single['id'], 'l3');
      expect(plano.atualizar.single['ordem'], 2);
      expect(plano.inserir, isEmpty);
    });

    test('acrescentar no fim insere sem id e sem tocar nas outras', () {
      final plano = planejar(['a', 'b', 'c', 'd']);
      expect(plano.apagar, isEmpty);
      expect(plano.atualizar, isEmpty);
      final nova = plano.inserir.single;
      expect(nova.containsKey('id'), isFalse);
      expect(nova['material_id'], 'd');
      expect(nova['ordem'], 4);
      expect(nova['unidade_id'], 'u');
    });

    test('inserir no início desloca todas as existentes', () {
      final plano = planejar(['z', 'a', 'b', 'c']);
      expect(plano.inserir.single['ordem'], 1);
      expect(plano.atualizar.map((l) => l['ordem']), [2, 3, 4]);
    });

    test('esvaziar a sequência apaga tudo', () {
      final plano = planejar([]);
      expect(plano.apagar, ['l1', 'l2', 'l3']);
      expect(plano.atualizar, isEmpty);
      expect(plano.inserir, isEmpty);
    });

    test('um filho repetido é erro de programação, não de dado', () {
      expect(() => planejar(['a', 'a']), throwsAssertionError);
    });
  });

  group('modelos', () {
    test('deLinha/paraLinha são simétricos e não levam o id no corpo', () {
      final linha = {
        'id': 'x',
        'metodo_id': 'm',
        'codigo': '01',
        'nome': 'N',
        'categoria': 'C',
        'estoque_minimo': 3,
        'ativo': false,
      };
      final material = MaterialDidatico.deLinha(linha);
      expect(material.id, 'x');
      expect(material.estoqueMinimo, 3);
      expect(material.ativo, isFalse);
      final corpo = material.paraLinha('u');
      expect(corpo.containsKey('id'), isFalse);
      expect(corpo['unidade_id'], 'u');
      expect(corpo['estoque_minimo'], 3);
    });

    test('só o MODULAR tem módulos', () {
      expect(fixture.metodos_.where((m) => m.modular).single.id, 'm-mod');
    });

    test('o método só expõe nome e ativo para gravação', () {
      expect(
        const Metodo(id: 'i', codigo: 'INGLES', nome: 'Inglês').paraLinha(),
        {'nome': 'Inglês', 'ativo': true},
      );
    });
  });
}
