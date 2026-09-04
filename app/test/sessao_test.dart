import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/sessao/sessao.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/sessao/sessao_repositorio.dart';

/// A máquina de estados da sessão — o entregável central deste card.
///
/// O que se prova aqui é que **nenhum dos modos de falha vira tela vazia**
/// (docs/acesso-autenticacao.md §1 e ajuste 3): autenticado sem espelho,
/// autenticado sem perfil e falha de carga têm cada um o seu estado, e nenhum
/// deles é `SessaoAtiva` com dados pela metade.
class _RepositorioFalso implements SessaoRepositorio {
  _RepositorioFalso(this.estado);

  EstadoSessao estado;
  int cargas = 0;
  bool saiu = false;

  @override
  Future<EstadoSessao> carregar() async {
    cargas++;
    return estado;
  }

  @override
  Future<void> entrar({required String email, required String senha}) async {}

  @override
  Future<void> recuperarSenha(
    String email, {
    required String redirecionarPara,
  }) async {}

  @override
  Future<void> trocarSenha(String novaSenha) async {}

  @override
  Future<void> sair() async => saiu = true;
}

const _sessaoDirecao = Sessao(
  usuarioId: '00000000-0000-0000-0000-000000000001',
  nome: 'Direção',
  email: 'irineus@gmail.com',
  unidadeId: '00000000-0000-0000-0000-0000000000aa',
  unidadeNome: 'Instituto Mix Charqueadas',
  permissoes: {'admin.ler', 'alunos.ler'},
);

ProviderContainer _container(SessaoRepositorio repositorio) {
  final container = ProviderContainer(
    retry: semRetryAutomatico,
    overrides: [sessaoRepositorioProvider.overrideWithValue(repositorio)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('começa carregando e não em deslogado — deslogado mandaria ao login '
      'antes de saber se há sessão salva', () async {
    final container = _container(_RepositorioFalso(const SessaoDeslogada()));
    expect(container.read(sessaoProvider), isA<SessaoCarregando>());
  });

  test('sem token: deslogado', () async {
    final container = _container(_RepositorioFalso(const SessaoDeslogada()));
    await container.read(sessaoProvider.notifier).recarregar();
    expect(container.read(sessaoProvider), isA<SessaoDeslogada>());
    expect(permissoesDe(container.read(sessaoProvider)), isEmpty);
  });

  test(
    'autenticado sem linha em usuario: erro explícito, nunca sessão vazia',
    () async {
      // O Auth não sabe nada sobre o espelho; a pessoa consegue token.
      final container = _container(
        _RepositorioFalso(const SessaoSemEspelho('convidado@escola.com')),
      );
      await container.read(sessaoProvider.notifier).recarregar();

      final estado = container.read(sessaoProvider);
      expect(estado, isA<SessaoSemEspelho>());
      expect(estado, isNot(isA<SessaoAtiva>()));
      expect((estado as SessaoSemEspelho).email, 'convidado@escola.com');
    },
  );

  test('autenticado com espelho e sem perfil: estado próprio', () async {
    // Convite feito, perfil ainda não atribuído (card 3.5 §3.1). Sem este
    // estado o shell abriria sem nenhum item de menu — o mesmo silêncio.
    const semPermissao = Sessao(
      usuarioId: 'u',
      nome: 'Recém-convidada',
      email: 'nova@escola.com',
      unidadeId: 'x',
      permissoes: {},
    );
    final container = _container(
      _RepositorioFalso(const SessaoSemPerfil(semPermissao)),
    );
    await container.read(sessaoProvider.notifier).recarregar();
    expect(container.read(sessaoProvider), isA<SessaoSemPerfil>());
  });

  test('falha de carga não vira deslogado', () async {
    // Mandar de volta ao login faria a pessoa digitar a senha para reencontrar
    // o mesmo erro.
    final container = _container(
      _RepositorioFalso(const SessaoErro('Sem conexão.', codigo: null)),
    );
    await container.read(sessaoProvider.notifier).recarregar();
    expect(container.read(sessaoProvider), isA<SessaoErro>());
    expect(container.read(sessaoProvider), isNot(isA<SessaoDeslogada>()));
  });

  test('sessão ativa publica as permissões para os guards', () async {
    final container = _container(
      _RepositorioFalso(const SessaoAtiva(_sessaoDirecao)),
    );
    await container.read(sessaoProvider.notifier).recarregar();
    expect(container.read(permissoesProvider), {'admin.ler', 'alunos.ler'});
    expect(container.read(resumoUsuarioProvider)?.nome, 'Direção');
    expect(
      container.read(resumoUsuarioProvider)?.unidade,
      'Instituto Mix Charqueadas',
    );
  });

  test('nenhum estado que não seja SessaoAtiva publica permissão', () async {
    const semPermissao = Sessao(
      usuarioId: 'u',
      nome: 'n',
      email: 'e',
      unidadeId: 'x',
      permissoes: {'admin.ler'},
    );
    for (final estado in <EstadoSessao>[
      const SessaoCarregando(),
      const SessaoDeslogada(),
      const SessaoSemEspelho('a@b.c'),
      const SessaoSemPerfil(semPermissao),
      const SessaoErro('x'),
    ]) {
      expect(permissoesDe(estado), isEmpty, reason: '$estado');
    }
  });

  test('sair leva a deslogado e limpa as permissões', () async {
    final repositorio = _RepositorioFalso(const SessaoAtiva(_sessaoDirecao));
    final container = _container(repositorio);
    await container.read(sessaoProvider.notifier).recarregar();
    expect(container.read(permissoesProvider), isNotEmpty);

    await container.read(sessaoProvider.notifier).sair();
    expect(repositorio.saiu, isTrue);
    expect(container.read(sessaoProvider), isA<SessaoDeslogada>());
    expect(container.read(permissoesProvider), isEmpty);
  });

  test('entrar recarrega a sessão em vez de confiar no retorno do login', () async {
    // O login devolve token; quem diz se a pessoa existe no sistema é a carga.
    final repositorio = _RepositorioFalso(const SessaoAtiva(_sessaoDirecao));
    final container = _container(repositorio);
    await container.read(sessaoProvider.notifier).recarregar();
    final antes = repositorio.cargas;

    await container
        .read(sessaoProvider.notifier)
        .entrar(email: 'irineus@gmail.com', senha: 'x');
    expect(repositorio.cargas, greaterThan(antes));
    expect(container.read(sessaoProvider), isA<SessaoAtiva>());
  });

  test('a unidade sem nome não derruba a sessão', () async {
    // Perfil sem `unidades.ler` lê zero linhas de `unidade`: o cabeçalho
    // degrada, o app funciona.
    const semNome = Sessao(
      usuarioId: 'u',
      nome: 'Monitor',
      email: 'm@e.c',
      unidadeId: 'x',
      permissoes: {'alunos.ler'},
    );
    final container = _container(_RepositorioFalso(const SessaoAtiva(semNome)));
    await container.read(sessaoProvider.notifier).recarregar();
    expect(container.read(sessaoProvider), isA<SessaoAtiva>());
    expect(container.read(resumoUsuarioProvider)?.unidade, isNull);
  });
}
