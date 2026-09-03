import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/link_inicial.dart';
import '../sessao/sessao.dart';
import '../sessao/sessao_provider.dart';
import '../telas/acesso_bloqueado.dart';
import '../telas/administracao/tela_administracao.dart';
import '../telas/alunos/ficha_aluno.dart';
import '../telas/alunos/tela_alunos.dart';
import '../telas/em_construcao.dart';
import '../telas/login.dart';
import '../telas/materiais/tela_materiais.dart';
import '../telas/redefinir_senha.dart';
import '../telas/salas/tela_salas.dart';
import '../telas/selecao_unidade.dart';
import '../telas/sem_acesso.dart';
import '../widgets/estados.dart';
import '../widgets/shell_im360.dart';
import 'rotas.dart';

/// Rota interna do estado de sessão bloqueado (sem espelho, sem perfil, erro).
const _caminhoAcesso = '/acesso';

/// As telas já entregues, por id de rota. O que não está aqui abre o
/// placeholder que diz qual card entrega.
final _telaDaRota = <String, WidgetBuilder>{
  'alunos': (_) => const TelaAlunos(),
  'materiais': (_) => const TelaMateriais(),
  'salas': (_) => const TelaSalas(),
  'administracao': (_) => const TelaAdministracao(),
};

/// Rotas filhas de uma tela — hoje só a ficha do aluno (`/alunos/:id`, card
/// 4.6), guardada pelo conjunto da própria lista. Fica **abaixo** de
/// `/alunos/:id/trilha`, que é rota própria (3b) com `estoque.ler` a mais.
List<RouteBase> _subRotas(Rota rota) => switch (rota.id) {
  'alunos' => [
    GoRoute(
      path: ':id',
      builder: (_, estado) => _TelaGuardada(
        rota: rota,
        construtor: (_) => FichaAluno(alunoId: estado.pathParameters['id']!),
      ),
    ),
  ],
  _ => const [],
};

/// Cards que entregam cada tela — o placeholder diz o seu, para não virar
/// destino permanente (docs/wireframes.md §18).
const _cardDaRota = <String, String>{
  'dashboard': '5.9 / 8.7',
  'aluno_trilha': '6.6',
  'turmas': '5.6',
  'turmas_modular': '7.3',
  'pendencias': '5.8',
  'compras': '6.8',
  'projecao': '8.5',
  'certificados': '8.6',
  'importacao': '9.1',
};

final roteadorProvider = Provider<GoRouter>((ref) {
  final controlador = ref.watch(sessaoProvider.notifier);

  return GoRouter(
    initialLocation: rotasAplicacao.first.caminho,
    // O roteador reavalia o redirect quando a sessão muda; nenhuma tela navega
    // por conta própria depois de entrar ou sair.
    refreshListenable: controlador,
    redirect: (context, estadoRota) {
      final estado = ref.read(sessaoProvider);
      final caminho = estadoRota.uri.path;

      // A redefinição de senha é pública e tem de continuar alcançável mesmo
      // com sessão: o link do Auth cria uma sessão de recuperação antes de a
      // pessoa chegar aqui.
      if (caminho == rotaRedefinirSenha.caminho) return null;

      // Chegou pelo link de convite (card 4.7): a sessão existe, a senha não.
      // Antes de qualquer outra tela, definir a senha — senão o acesso
      // seguinte falha sem que nada tenha dito que faltava um passo (achado
      // do card 3.8). Sem sessão, o link não valeu (expirado): segue para o
      // login, e o registro deixa de valer.
      if (LinkInicial.convitePendente) {
        switch (estado) {
          case SessaoCarregando():
            return null;
          case SessaoDeslogada():
            LinkInicial.consumir();
          default:
            return '${rotaRedefinirSenha.caminho}?motivo=convite';
        }
      }

      return switch (estado) {
        SessaoCarregando() => null,
        SessaoDeslogada() =>
          caminho == rotaLogin.caminho ? null : rotaLogin.caminho,
        SessaoSemEspelho() ||
        SessaoSemPerfil() ||
        SessaoErro() => caminho == _caminhoAcesso ? null : _caminhoAcesso,
        SessaoAtiva(:final sessao) => _destinoComSessao(caminho, sessao),
      };
    },
    routes: [
      GoRoute(path: rotaLogin.caminho, builder: (_, _) => const TelaLogin()),
      GoRoute(
        path: rotaRedefinirSenha.caminho,
        builder: (_, _) => const TelaRedefinirSenha(),
      ),
      GoRoute(
        path: _caminhoAcesso,
        builder: (_, _) => const TelaAcessoBloqueado(),
      ),
      GoRoute(
        path: rotaSelecaoUnidade.caminho,
        builder: (_, _) => const TelaSelecaoUnidade(),
      ),
      ShellRoute(
        builder: (_, _, filho) => ShellIm360(filho: filho),
        routes: [
          for (final rota in rotasAplicacao)
            GoRoute(
              path: rota.caminho,
              builder: (_, _) => _TelaGuardada(rota: rota),
              routes: _subRotas(rota),
            ),
        ],
      ),
    ],
    errorBuilder: (context, estadoRota) => Scaffold(
      body: EstadoErro(
        mensagem: 'Esta tela não existe.',
        codigoTecnico: estadoRota.uri.path,
        aoRepetir: () => context.go(rotasAplicacao.first.caminho),
      ),
    ),
  );
});

/// Onde a sessão ativa pode estar.
///
/// Sai do login/acesso para a primeira rota que o usuário abre — o Dashboard
/// exige cinco permissões, e um perfil enxuto entraria e cairia numa tela sem
/// acesso logo depois de digitar a senha certa.
String? _destinoComSessao(String caminho, Sessao sessao) {
  final permitido = primeiraRotaPermitida(sessao.permissoes);
  final inicio = permitido?.caminho ?? _caminhoAcesso;

  if (caminho == rotaLogin.caminho || caminho == _caminhoAcesso) return inicio;

  // Seleção de unidade: pulada em silêncio na v1 (uma unidade só).
  if (caminho == rotaSelecaoUnidade.caminho) return inicio;

  return null;
}

/// A guarda por rota. Existe além do redirect porque a permissão pode sumir com
/// a sessão aberta (a direção desmarca na matriz, e o card 2.4 registra que a
/// mudança vale imediatamente) — aí o `build` da tela é o último ponto em que
/// dá para não mostrar nada.
class _TelaGuardada extends ConsumerWidget {
  const _TelaGuardada({required this.rota, this.construtor});

  final Rota rota;

  /// A tela, quando não é a de `_telaDaRota` — a ficha do aluno, que
  /// precisa do parâmetro da rota.
  final WidgetBuilder? construtor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissoes = ref.watch(permissoesProvider);
    if (!podeAbrir(rota, permissoes)) {
      return TelaSemAcesso(
        faltando: permissoesFaltantes(rota, permissoes),
        paraOndeIr: primeiraRotaPermitida(permissoes)?.caminho,
      );
    }
    final construtor = this.construtor ?? _telaDaRota[rota.id];
    if (construtor != null) return construtor(context);
    return TelaEmConstrucao(rota: rota, card: _cardDaRota[rota.id] ?? '—');
  }
}
