import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/rotas/rotas.dart';

/// Card 2.8 §9.1: cada uma das rotas do card 2.4 §6 abre com o conjunto mínimo
/// e é barrada faltando **qualquer uma** delas — tabelado, uma linha por rota.
///
/// A tabela abaixo é cópia literal de docs/permissoes-matriz.md §6, escrita à
/// mão de propósito: derivá-la de `rotas.dart` faria o teste concordar consigo
/// mesmo.
const _esperado = <String, Set<String>>{
  'selecao_unidade': {'unidades.ler'},
  'dashboard': {
    'alunos.ler',
    'materiais.ler',
    'turmas.ler',
    'salas.ler',
    'pendencias.ler',
  },
  'alunos': {'alunos.ler', 'materiais.ler'},
  'aluno_trilha': {'alunos.ler', 'materiais.ler', 'estoque.ler'},
  'turmas': {'turmas.ler', 'salas.ler', 'professores.ler', 'materiais.ler'},
  'turmas_modular': {'turmas.ler', 'salas.ler', 'materiais.ler'},
  'materiais': {'materiais.ler', 'estoque.ler'},
  'compras': {'materiais.ler', 'estoque.ler', 'alunos.ler', 'compras.ler'},
  'projecao': {'materiais.ler', 'estoque.ler', 'alunos.ler'},
  'certificados': {'certificados.ler', 'alunos.ler'},
  'salas': {'salas.ler', 'professores.ler'},
  'pendencias': {'pendencias.ler'},
  'administracao': {'admin.ler'},
  'importacao': {'admin.ler'},
};

/// A matriz inicial do card 2.4 §5, reduzida às permissões de leitura que
/// guardam rota. Serve para a asserção que interessa ao usuário: **cada perfil
/// abre exatamente as telas que o card 2.4 §6 diz que abre.**
const _matrizPerfis = <String, Set<String>>{
  'direcao': {
    'unidades.ler',
    'alunos.ler',
    'materiais.ler',
    'turmas.ler',
    'salas.ler',
    'professores.ler',
    'estoque.ler',
    'compras.ler',
    'certificados.ler',
    'pendencias.ler',
    'admin.ler',
  },
  'secretaria': {
    'unidades.ler',
    'alunos.ler',
    'materiais.ler',
    'turmas.ler',
    'salas.ler',
    'professores.ler',
    'estoque.ler',
    'compras.ler',
    'certificados.ler',
    'pendencias.ler',
  },
  'pedagogico': {
    'unidades.ler',
    'alunos.ler',
    'materiais.ler',
    'turmas.ler',
    'salas.ler',
    'professores.ler',
    'estoque.ler',
    'certificados.ler',
    'pendencias.ler',
  },
  'monitor': {
    'unidades.ler',
    'alunos.ler',
    'materiais.ler',
    'turmas.ler',
    'salas.ler',
    'professores.ler',
    'estoque.ler',
    'certificados.ler',
    'pendencias.ler',
  },
};

void main() {
  test('o catálogo de rotas é exatamente o do card 2.4 §6', () {
    final noCodigo = {for (final r in rotasGuardadas) r.id: r.exige};
    expect(noCodigo.keys.toSet(), _esperado.keys.toSet());
    for (final entrada in _esperado.entries) {
      expect(
        noCodigo[entrada.key],
        entrada.value,
        reason:
            'conjunto mínimo da rota ${entrada.key} divergiu do card 2.4 §6',
      );
    }
  });

  for (final rota in rotasGuardadas) {
    test('${rota.id}: abre com o conjunto mínimo', () {
      expect(podeAbrir(rota, rota.exige), isTrue);
      expect(permissoesFaltantes(rota, rota.exige), isEmpty);
    });

    test('${rota.id}: é barrada faltando qualquer uma das permissões', () {
      for (final ausente in rota.exige) {
        final parcial = rota.exige.difference({ausente});
        expect(
          podeAbrir(rota, parcial),
          isFalse,
          reason:
              'a rota ${rota.id} abriu sem $ausente — a RLS reduz linhas '
              'em silêncio, então a tela não daria erro, daria número menor',
        );
        expect(permissoesFaltantes(rota, parcial), {ausente});
      }
    });

    test('${rota.id}: é barrada sem permissão nenhuma', () {
      expect(podeAbrir(rota, const {}), isFalse);
    });
  }

  test('rota pública abre sem permissão nenhuma', () {
    expect(podeAbrir(rotaLogin, const {}), isTrue);
    expect(podeAbrir(rotaRedefinirSenha, const {}), isTrue);
  });

  group('perfis da matriz inicial (card 2.4 §5 e §6)', () {
    test('a direção abre todas as telas', () {
      final menu = menuPara(_matrizPerfis['direcao']!).map((r) => r.id);
      expect(
        menu,
        containsAll(['dashboard', 'compras', 'administracao', 'importacao']),
      );
    });

    test('só direção e secretaria abrem Compras', () {
      // A única tela com perfil de fora por decisão explícita do card 2.3: sem
      // `compras.ler` o monitor leria qtd_pedida_pendente = 0 e o sistema
      // sugeriria comprar de novo o que já está a caminho.
      for (final perfil in _matrizPerfis.entries) {
        final abre = menuPara(perfil.value).any((r) => r.id == 'compras');
        expect(
          abre,
          perfil.key == 'direcao' || perfil.key == 'secretaria',
          reason: 'Compras para ${perfil.key}',
        );
      }
    });

    test('só a direção abre Administração e Importação', () {
      for (final perfil in _matrizPerfis.entries) {
        final abre = menuPara(perfil.value)
            .any((r) => r.id == 'administracao' || r.id == 'importacao');
        expect(
          abre,
          perfil.key == 'direcao',
          reason: 'Admin para ${perfil.key}',
        );
      }
    });

    test(
      'todo perfil da matriz inicial abre o Dashboard como tela inicial',
      () {
        for (final perfil in _matrizPerfis.entries) {
          expect(
            primeiraRotaPermitida(perfil.value)?.id,
            'dashboard',
            reason: perfil.key,
          );
        }
      },
    );
  });

  test(
    'perfil enxuto cai na primeira rota que consegue abrir, não no Dashboard',
    () {
      // O Dashboard exige cinco permissões. Um perfil criado na tela de
      // Administração com só `pendencias.ler` entraria e cairia numa tela sem
      // acesso logo depois de digitar a senha certa.
      expect(primeiraRotaPermitida({'pendencias.ler'})?.id, 'pendencias');
    },
  );

  test('sem permissão nenhuma não há rota inicial nem itens de menu', () {
    expect(primeiraRotaPermitida(const {}), isNull);
    expect(menuPara(const {}), isEmpty);
  });

  test('a rota da aba Trilha exige estoque.ler além do que a lista de alunos exige', () {
    final trilha = rotasGuardadas.firstWhere((r) => r.id == 'aluno_trilha');
    final alunos = rotasGuardadas.firstWhere((r) => r.id == 'alunos');
    expect(trilha.exige.difference(alunos.exige), {'estoque.ler'});
  });

  test('todo caminho de rota é único', () {
    final caminhos = [
      rotaLogin.caminho,
      rotaRedefinirSenha.caminho,
      ...rotasGuardadas.map((r) => r.caminho),
    ];
    expect(caminhos.toSet().length, caminhos.length);
  });
}
