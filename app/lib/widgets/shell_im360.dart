import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../pendencias/pendencias_provider.dart';
import '../rotas/rotas.dart';
import '../sessao/sessao_provider.dart';
import '../theme/dimensoes.dart';
import '../theme/preferencia_tema.dart';
import '../theme/tipografia.dart';
import 'marca.dart';

/// O shell é **um componente** — dono da navegação, do cabeçalho e do menu do
/// usuário; as telas só entregam conteúdo (docs/design-system.md §3).
///
/// A faixa vem da **largura disponível**, nunca da plataforma: um navegador
/// estreitado vira `mobile`, e é assim que se testa a ergonomia do monitor no
/// desktop.
class ShellIm360 extends ConsumerWidget {
  const ShellIm360({super.key, required this.filho});

  final Widget filho;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissoes = ref.watch(permissoesProvider);
    final itens = menuPara(permissoes);
    final atual = _rotaAtual(context, itens);
    // O contador do menu (card 2.6 decisão f, card 5.8). Zero para quem não tem
    // `pendencias.ler` — e para esse perfil o item de menu também não existe.
    final altas = ref.watch(pendenciasAltasProvider);

    return LayoutBuilder(
      builder: (context, restricoes) {
        final faixa = faixaDe(restricoes.maxWidth);
        return switch (faixa) {
          Faixa.desktop => _comMenuLateral(context, ref, itens, atual, altas),
          Faixa.tablet => _comTrilho(context, ref, itens, atual, altas),
          Faixa.mobile => _comBarraInferior(context, ref, itens, atual, altas),
        };
      },
    );
  }

  Rota? _rotaAtual(BuildContext context, List<Rota> itens) {
    final caminho = GoRouterState.of(context).uri.path;
    Rota? achada;
    for (final rota in itens) {
      final casa = rota.caminho == '/'
          ? caminho == '/'
          : caminho == rota.caminho || caminho.startsWith('${rota.caminho}/');
      if (casa &&
          (achada == null || rota.caminho.length > achada.caminho.length)) {
        achada = rota;
      }
    }
    return achada;
  }

  Widget _conteudo(BuildContext context) => Center(
    child: ConstrainedBox(
      // Em monitor ultrawide a tabela não vira uma tira de 3 000 px.
      constraints: const BoxConstraints(maxWidth: Dim.larguraConteudoMax),
      child: filho,
    ),
  );

  Widget _comMenuLateral(
    BuildContext context,
    WidgetRef ref,
    List<Rota> itens,
    Rota? atual,
    int altas,
  ) {
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: Dim.larguraMenu,
            child: _MenuLateral(itens: itens, atual: atual, altas: altas),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _Cabecalho(titulo: atual?.titulo ?? 'Gestão IM360'),
                const Divider(height: 1),
                Expanded(child: _conteudo(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _comTrilho(
    BuildContext context,
    WidgetRef ref,
    List<Rota> itens,
    Rota? atual,
    int altas,
  ) {
    return Scaffold(
      appBar: _barra(context, atual?.titulo ?? 'Gestão IM360'),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: atual == null ? null : itens.indexOf(atual),
            onDestinationSelected: (i) => context.go(itens[i].caminho),
            labelType: NavigationRailLabelType.none,
            destinations: [
              for (final rota in itens)
                NavigationRailDestination(
                  icon: iconeComContador(rota, altas),
                  label: Text(rota.titulo),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _conteudo(context)),
        ],
      ),
    );
  }

  /// Barra inferior: Alunos · Turmas · Pendências · Mais — a jornada do monitor
  /// primeiro (docs/wireframes.md §3.2). Itens a que o usuário não tem acesso
  /// não aparecem; "Mais" abre a gaveta com o resto, Dashboard incluído.
  Widget _comBarraInferior(
    BuildContext context,
    WidgetRef ref,
    List<Rota> itens,
    Rota? atual,
    int altas,
  ) {
    final fixos = [
      for (final id in idsBarraInferior)
        ...itens.where((rota) => rota.id == id),
    ];
    final naGaveta = itens.where((rota) => !fixos.contains(rota)).toList();
    final indice = atual == null ? null : fixos.indexOf(atual);

    return Scaffold(
      appBar: _barra(context, atual?.titulo ?? 'Gestão IM360'),
      endDrawer: naGaveta.isEmpty
          ? null
          : Drawer(
              child: SafeArea(
                child: ListView(
                  children: [
                    for (final rota in naGaveta)
                      ListTile(
                        leading: iconeComContador(rota, altas),
                        title: Text(rota.titulo, style: Tipografia.corpo),
                        minTileHeight: Dim.alvoMobile,
                        onTap: () {
                          Navigator.of(context).pop();
                          context.go(rota.caminho);
                        },
                      ),
                  ],
                ),
              ),
            ),
      body: _conteudo(context),
      bottomNavigationBar: fixos.isEmpty && naGaveta.isEmpty
          ? null
          : NavigationBar(
              selectedIndex: (indice ?? -1) >= 0 ? indice! : fixos.length,
              onDestinationSelected: (i) {
                if (i < fixos.length) {
                  context.go(fixos[i].caminho);
                } else {
                  Scaffold.of(context).openEndDrawer();
                }
              },
              destinations: [
                for (final rota in fixos)
                  NavigationDestination(
                    icon: iconeComContador(rota, altas),
                    label: rota.titulo,
                  ),
                const NavigationDestination(
                  icon: Icon(Icons.menu),
                  label: 'Mais',
                ),
              ],
            ),
    );
  }

  PreferredSizeWidget _barra(BuildContext context, String titulo) => AppBar(
    title: Text(titulo, style: Tipografia.subtitulo),
    actions: const [_MenuUsuario()],
  );
}

/// O ícone do item de menu, com o contador quando ele existe.
///
/// **Só o item de Pendências, e só severidade ALTA** (card 2.6 decisão f): um
/// sino que dispara sempre não é avisado, é ignorado — e o total incluiria as
/// `BAIXA` de estoque abaixo do mínimo, que ficam abertas por semanas e
/// esconderiam a entrega bloqueada que apareceu hoje.
///
/// O número **não** é o único portador do significado: o `Semantics` diz o que
/// ele conta, senão a leitura de tela anuncia "Pendências, 3" sem dizer 3 do quê.
Widget iconeComContador(Rota rota, int altas) {
  if (rota.id != 'pendencias' || altas <= 0) return Icon(rota.icone);
  return Semantics(
    label:
        '$altas ${altas == 1 ? 'pendência' : 'pendências'} de severidade '
        'alta em aberto',
    child: Badge(label: Text('$altas'), child: Icon(rota.icone)),
  );
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Dim.e24, vertical: Dim.e12),
    child: Row(
      children: [
        Expanded(child: Text(titulo, style: Tipografia.titulo)),
        const _MenuUsuario(),
      ],
    ),
  );
}

class _MenuLateral extends ConsumerWidget {
  const _MenuLateral({
    required this.itens,
    required this.atual,
    required this.altas,
  });

  final List<Rota> itens;
  final Rota? atual;
  final int altas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unidade = ref.watch(resumoUsuarioProvider)?.unidade;
    final cores = Theme.of(context).colorScheme;

    GrupoMenu? anterior;
    final linhas = <Widget>[];
    for (final rota in itens) {
      if (anterior != null && rota.grupo != anterior) {
        linhas.add(
          const Divider(height: Dim.e16, indent: Dim.e16, endIndent: Dim.e16),
        );
      }
      anterior = rota.grupo;
      final selecionada = rota == atual;
      linhas.add(
        ListTile(
          leading: iconeComContador(rota, altas),
          title: Text(rota.titulo, style: Tipografia.rotulo),
          selected: selecionada,
          selectedTileColor: cores.surfaceContainerHighest,
          onTap: () => context.go(rota.caminho),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(Dim.e16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AssinaturaIm360(lado: 32),
              if (unidade != null)
                Text(
                  unidade,
                  style: Tipografia.apoio.copyWith(
                    color: cores.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: ListView(children: linhas)),
        const Divider(height: 1),
        const Padding(
          padding: EdgeInsets.all(Dim.e8),
          child: _MenuUsuario(comNome: true),
        ),
      ],
    );
  }
}

class _MenuUsuario extends ConsumerWidget {
  const _MenuUsuario({this.comNome = false});

  final bool comNome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nome = ref.watch(resumoUsuarioProvider)?.nome ?? '';
    final modo = ref.watch(preferenciaTemaProvider);

    return PopupMenuButton<String>(
      tooltip: 'Menu do usuário',
      onSelected: (opcao) async {
        switch (opcao) {
          case 'tema':
            await ref.read(preferenciaTemaProvider.notifier).alternar();
          case 'sair':
            await ref.read(sessaoProvider.notifier).sair();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'tema',
          child: Text(
            modo == ThemeMode.dark ? 'Tema claro' : 'Tema escuro',
            style: Tipografia.corpo,
          ),
        ),
        const PopupMenuItem(value: 'sair', child: Text('Sair')),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_circle_outlined),
          if (comNome) ...[
            const SizedBox(width: Dim.e8),
            Flexible(
              child: Text(
                nome,
                style: Tipografia.rotulo,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
