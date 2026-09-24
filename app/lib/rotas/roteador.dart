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
import '../telas/certificados/tela_certificados.dart';
import '../telas/compras/tela_compras.dart';
import '../telas/dashboard/tela_dashboard.dart';
import '../telas/importacao/tela_importacao.dart';
import '../telas/login.dart';
import '../telas/materiais/tela_materiais.dart';
import '../telas/pendencias/tela_pendencias.dart';
import '../telas/projecao/tela_projecao.dart';
import '../telas/redefinir_senha.dart';
import '../telas/salas/tela_salas.dart';
import '../telas/selecao_unidade.dart';
import '../telas/turmas/tela_turmas.dart';
import '../telas/turmas/tela_turmas_modular.dart';
import '../telas/sem_acesso.dart';
import '../theme/dimensoes.dart';
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
/// Há tela para a rota [id]? Para o `guardas_rota_test` conferir que nenhuma
/// rota do menu cai no erro abaixo (card 9.2,76).
@visibleForTesting
bool temTelaDaRota(String id) => _telaDaRota.containsKey(id);

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
  // `?material=` segue o desenho da tela 6 e da 7: a Projeção abre já com o
  // drill-down daquele material, em vez de largar a pessoa na grade inteira.
  'projecao': (estado) =>
      TelaProjecao(materialId: estado.uri.queryParameters['material']),
  // `?aluno=` segue o desenho de `?material=` e `?turma=`: a tela 9 abre já com
  // o checklist daquele aluno. Quem o usa é a pendência
  // `CERTIFICADO_INCONSISTENTE` quando o destino for a fila, e não a ficha.
  'certificados': (estado) =>
      TelaCertificados(alunoId: estado.uri.queryParameters['aluno']),
  'administracao': (_) => const TelaAdministracao(),
  'importacao': (_) => const TelaImportacao(),
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

final roteadorProvider = Provider<GoRouter>((ref) {
  final controlador = ref.watch(sessaoProvider.notifier);

  // A primeira navegação com sessão ativa ainda não aconteceu: é nela que o
  // app, aberto na rota inicial, vai para a tela de partida do dispositivo
  // (card 9.2,64). Depois disso, "/" é o Dashboard que a pessoa escolheu abrir.
  var partidaResolvida = false;

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
        SessaoAtiva(:final sessao) => () {
          final mobile =
              faixaDe(MediaQuery.sizeOf(context).width) == Faixa.mobile;
          final aberturaDoApp =
              !partidaResolvida &&
              caminho == rotasAplicacao.first.caminho &&
              estadoRota.uri.queryParameters.isEmpty;
          partidaResolvida = true;
          if (aberturaDoApp) {
            final partida = primeiraRotaPermitida(
              sessao.permissoes,
              mobile: mobile,
            );
            if (partida != null && partida.caminho != caminho) {
              return partida.caminho;
            }
          }
          return _destinoComSessao(caminho, sessao, mobile: mobile);
        }(),
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
String? _destinoComSessao(
  String caminho,
  Sessao sessao, {
  bool mobile = false,
}) {
  final permitido = primeiraRotaPermitida(sessao.permissoes, mobile: mobile);
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
    // ⚠️ Card 9.2,63: enquanto a sessão carrega, as permissões são o conjunto
    // VAZIO — e a guarda abaixo mostrava "Sem acesso" com TODAS as permissões
    // "faltando", por um segundo ou dois a cada abertura do app. A tela
    // afirmava o que não sabia. Carregando é carregando.
    if (ref.watch(sessaoProvider) is SessaoCarregando) {
      return const EstadoCarregando(linhas: 4);
    }
    final permissoes = ref.watch(permissoesProvider);
    if (!podeAbrir(rota, permissoes)) {
      return TelaSemAcesso(
        faltando: permissoesFaltantes(rota, permissoes),
        paraOndeIr: primeiraRotaPermitida(permissoes)?.caminho,
      );
    }
    // Card 9.2,76: toda rota do app tem tela desde o card 9.1, e o
    // placeholder "em construção" (e o mapa `_cardDaRota` que o alimentava)
    // saiu. Rota nova sem tela é defeito de quem a criou — e o
    // `guardas_rota_test` reprova antes de chegar aqui.
    final construtor = this.construtor ?? _telaDaRota[rota.id];
    if (construtor == null) {
      throw StateError('A rota "${rota.id}" não tem tela em _telaDaRota.');
    }
    return construtor(estado);
  }
}
