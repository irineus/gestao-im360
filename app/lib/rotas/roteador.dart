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
import '../telas/compras/tela_compras.dart';
import '../telas/dashboard/tela_dashboard.dart';
import '../telas/em_construcao.dart';
import '../telas/login.dart';
import '../telas/materiais/tela_materiais.dart';
import '../telas/pendencias/tela_pendencias.dart';
import '../telas/redefinir_senha.dart';
import '../telas/salas/tela_salas.dart';
import '../telas/selecao_unidade.dart';
import '../telas/turmas/tela_turmas.dart';
import '../telas/turmas/tela_turmas_modular.dart';
import '../telas/sem_acesso.dart';
import '../widgets/estados.dart';
import '../widgets/shell_im360.dart';
import 'rotas.dart';

/// Rota interna do estado de sessão bloqueado (sem espelho, sem perfil, erro).
const _caminhoAcesso = '/acesso';

/// As telas já entregues, por id de rota. O que não está aqui abre o
/// placeholder que diz qual card entrega.
///
/// Recebem o `GoRouterState` por causa dos **atalhos da central de pendências**
/// (wireframe §14.3): `?bloco=`, `?pc=` e `?material=` levam o id da referência
/// para a tela de destino abrir já no que a pendência descreve. Sem o
/// parâmetro, "Ver turma" levava à grade inteira e a pessoa procurava de novo o
/// que a lista já sabia.
final _telaDaRota = <String, Widget Function(GoRouterState)>{
  'dashboard': (_) => const TelaDashboard(),
  'alunos': (_) => const TelaAlunos(),
  'materiais': (estado) =>
      TelaMateriais(materialId: estado.uri.queryParameters['material']),
  'salas': (estado) => TelaSalas(pcId: estado.uri.queryParameters['pc']),
  // `?pedido=` segue o desenho de `?material=` e `?bloco=`: a tela abre já na
  // aba Pedidos, com o pedido escolhido no painel. Quem o usa hoje é o próprio
  // app, ao criar um rascunho a partir do pedido sugerido.
  'compras': (estado) =>
      TelaCompras(pedidoId: estado.uri.queryParameters['pedido']),
  'turmas': (estado) =>
      TelaTurmas(blocoId: estado.uri.queryParameters['bloco']),
  // `?turma=` segue o desenho de `?bloco=`: a tela 5 abre já com a turma
  // expandida. Quem o usará é a pendência `TURMA_MODULAR_SEM_CRONOGRAMA`
  // (card 8.1), e ele existe desde já porque "Ver turma" sem o id larga a
  // pessoa na lista inteira.
  'turmas_modular': (estado) =>
      TelaTurmasModular(turmaId: estado.uri.queryParameters['turma']),
  'pendencias': (_) => const TelaPendencias(),
  'administracao': (_) => const TelaAdministracao(),
  // A rota 3b (card 2.4 §6) desde o card 6.6: `/alunos/:id/trilha` é o
  // deep-link para a aba Trilha, e não uma tela separada. Ele existe como rota
  // própria porque o conjunto mínimo dele tem `estoque.ler` a mais que o da
  // ficha — quem chega aqui sem a permissão vê a tela "sem acesso" com o
  // diagnóstico, em vez de a ficha abrir e a aba mentir com saldo 0.
  'aluno_trilha': (estado) =>
      FichaAluno(alunoId: estado.pathParameters['id']!, aba: 'trilha'),
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
        estado: estado,
        // `?aba=` abre a ficha na aba em que o problema se resolve — é como a
        // central de pendências manda "Alocar" para Turmas e "Formar" para
        // Dados, em vez de largar todo mundo na primeira aba.
        construtor: (estado) => FichaAluno(
          alunoId: estado.pathParameters['id']!,
          aba: estado.uri.queryParameters['aba'],
        ),
      ),
    ),
  ],
  _ => const [],
};

/// Cards que entregam cada tela — o placeholder diz o seu, para não virar
/// destino permanente (docs/wireframes.md §18).
const _cardDaRota = <String, String>{
  // O dashboard saiu daqui no card 5.9: a tela existe, e é **parcial** — quem
  // nomeia o card do que falta é a própria tela, em rodapé, e não um
  // placeholder que esconderia a metade já entregue.
  // Turmas Modular saiu daqui no card 7.3: a tela existe.
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
              builder: (_, estado) => _TelaGuardada(rota: rota, estado: estado),
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
  const _TelaGuardada({
    required this.rota,
    required this.estado,
    this.construtor,
  });

  final Rota rota;

  /// A rota como o `GoRouter` a leu — é de onde saem os parâmetros de caminho
  /// e de consulta que as telas de destino usam.
  final GoRouterState estado;

  /// A tela, quando não é a de `_telaDaRota` — a ficha do aluno, que
  /// precisa do parâmetro da rota.
  final Widget Function(GoRouterState estado)? construtor;

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
    if (construtor != null) return construtor(estado);
    return TelaEmConstrucao(rota: rota, card: _cardDaRota[rota.id] ?? '—');
  }
}
