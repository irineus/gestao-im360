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
  // ⚠️ Quatro desde o card 8.5 (05/09/2026), e o quarto é `turmas.ler`: a
  // parcela MODULAR da projeção lê o cronograma da turma, e `v_projecao_aluno`
  // junta `metodo` internamente. Sem ele a tela não vem errada — vem VAZIA.
  // `permissoes-matriz.md` §6 registrava três e foi corrigido no mesmo commit.
  'projecao': {'materiais.ler', 'estoque.ler', 'alunos.ler', 'turmas.ler'},
  // ⚠️ Três desde o card 8.6 (06/09/2026), e o terceiro é `materiais.ler`:
  // `v_certificado_fila` junta `metodo` internamente — é o método que a linha
  // mostra e o que o filtro do wireframe §12.1 oferece. Sem ele a fila não vem
  // errada, vem VAZIA. `permissoes-matriz.md` §6 registrava dois e foi corrigido
  // no mesmo commit; os quatro perfis já têm a permissão, então nenhum perde a
  // tela — é o que a asserção de `_matrizPerfis` abaixo confere.
  'certificados': {'certificados.ler', 'alunos.ler', 'materiais.ler'},
  'salas': {'salas.ler', 'professores.ler'},
  'pendencias': {'pendencias.ler'},
  'administracao': {'admin.ler'},
  // ⚠️ Quinze desde o card 9.1 (06/09/2026): é o "admin.ler + os domínios do
  // que se importa" que o card 2.4 §7 item 4 deixou em aberto em 01/09/2026, e
  // o card 9.1 é quem sabe o que o arquivo traz. Os quatorze de escrita estão
  // aqui porque as funções da importação são `invoker` — quem importa escreve
  // sob a própria RLS, e a política de cada tabela cobra o código dela; e
  // `admin.ler` está aqui porque é ele, e só ele, que faz a tela ser da
  // direção: os quatorze de escrita a secretaria também tem (§5).
  'importacao': {
    'admin.ler',
    'materiais.criar',
    'materiais.editar',
    'alunos.criar',
    'alunos.editar',
    'alunos.editar_trilha',
    'salas.criar',
    'salas.editar',
    'salas.registrar_manutencao',
    'professores.criar',
    'turmas.criar',
    'turmas.alocar',
    'estoque.lancar_saida',
    'estoque.ajustar',
    'compras.receber',
  },
};

/// A matriz inicial do card 2.4 §5, reduzida ao que guarda rota. Serve para a
/// asserção que interessa ao usuário: **cada perfil abre exatamente as telas
/// que o card 2.4 §6 diz que abre.**
///
/// ⚠️ Até o card 9.1 esta tabela tinha só as permissões de LEITURA, porque só
/// elas guardavam rota. A rota 13 trouxe quatorze de escrita, e com elas a
/// tabela ficou obrigada a distinguir os perfis também por escrita — do
/// contrário a asserção "só a direção abre Importação" passaria por um motivo
/// falso (a secretaria não abriria por falta de `materiais.criar`, que ela
/// tem). Os quatorze estão aqui exatamente como o §5 os distribui, e é isso que
/// faz a asserção medir o que ela diz medir: a secretaria tem os quatorze e
/// **mesmo assim** não abre, por causa de `admin.ler`.
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
    'materiais.criar',
    'materiais.editar',
    'alunos.criar',
    'alunos.editar',
    'alunos.editar_trilha',
    'salas.criar',
    'salas.editar',
    'salas.registrar_manutencao',
    'professores.criar',
    'turmas.criar',
    'turmas.alocar',
    'estoque.lancar_saida',
    'estoque.ajustar',
    'compras.receber',
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
    // Os quatorze de escrita da rota 13, todos — e nenhum `admin.ler`.
    'materiais.criar',
    'materiais.editar',
    'alunos.criar',
    'alunos.editar',
    'alunos.editar_trilha',
    'salas.criar',
    'salas.editar',
    'salas.registrar_manutencao',
    'professores.criar',
    'turmas.criar',
    'turmas.alocar',
    'estoque.lancar_saida',
    'estoque.ajustar',
    'compras.receber',
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
    'alunos.criar',
    'alunos.editar',
    'alunos.editar_trilha',
    'professores.criar',
    'turmas.criar',
    'turmas.alocar',
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
    'salas.registrar_manutencao',
    'estoque.lancar_saida',
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
