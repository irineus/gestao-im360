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
            // O trilho ganhou o rodapé com nome e unidade (revisão mobile,
            // item H2c): sem ele o tablet era a única faixa em que ninguém
            // sabia quem estava logado — o `comNome` só existia no menu
            // lateral do desktop.
            trailing: const Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: Dim.e8),
                  child: _RodapeTrilho(),
                ),
              ),
            ),
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
      // No celular o menu do usuário mora na gaveta (item H2b), então ela
      // existe mesmo quando nenhuma rota sobrou para o "Mais".
      appBar: _barra(
        context,
        atual?.titulo ?? 'Gestão IM360',
        acoes: const [_BotaoGaveta()],
      ),
      endDrawer: _GavetaMais(rotas: naGaveta, altas: altas),
      body: _conteudo(context),
      bottomNavigationBar: fixos.isEmpty && naGaveta.isEmpty
          ? null
          // ⚠️ O `Builder` não é enfeite: `Scaffold.of` procura o Scaffold
          // ANCESTRAL, e o `context` do `build` de `ShellIm360` está ACIMA do
          // Scaffold que este método devolve. Sem ele, tocar em "Mais" lançava
          // `Scaffold.of() called with a context that does not contain a
          // Scaffold` e a gaveta nunca abria — nove telas ficavam inalcançáveis
          // no celular, e nada em `analyze` ou no CI acusava (item H1).
          : Builder(
              builder: (context) => NavigationBar(
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
            ),
    );
  }

  PreferredSizeWidget _barra(
    BuildContext context,
    String titulo, {
    List<Widget> acoes = const [_MenuUsuario()],
  }) => AppBar(
    title: Text(titulo, style: Tipografia.subtitulo),
    actions: acoes,
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
      key: comNome ? null : chaveGatilhoMenuUsuario,
      tooltip: nome.isEmpty ? 'Menu do usuário' : 'Menu de $nome',
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
      // ⚠️ O alvo é do contrato, não do ícone: sem a restrição, o gatilho
      // media 24×24 px — metade do mínimo do design-system §8.4, e o menu do
      // usuário é a única saída do sistema (item H2a).
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: Dim.alvoMobile,
          minHeight: Dim.alvoMobile,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
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
      ),
    );
  }
}

/// O ícone do usuário no app bar do celular: abre a **mesma** gaveta do "Mais",
/// onde moram nome, unidade, tema e "Sair" (item H2).
class _BotaoGaveta extends ConsumerWidget {
  const _BotaoGaveta();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nome = ref.watch(resumoUsuarioProvider)?.nome ?? '';
    return IconButton(
      key: chaveGatilhoMenuUsuario,
      icon: const Icon(Icons.account_circle_outlined),
      tooltip: nome.isEmpty ? 'Menu do usuário' : 'Menu de $nome',
      // O alvo mínimo do card 2.6 (e) / design-system §8.4. O padrão do
      // `IconButton` já é 48, mas escrevê-lo aqui é o que o teste mede.
      constraints: const BoxConstraints(
        minWidth: Dim.alvoMobile,
        minHeight: Dim.alvoMobile,
      ),
      onPressed: () => Scaffold.of(context).openEndDrawer(),
    );
  }
}

/// A gaveta do "Mais": cabeçalho com quem está logado, as rotas que não coubemos
/// na barra inferior, e no fim tema e saída.
///
/// Ela existe **sempre** no celular, mesmo sem rota sobrando: desde o item H2
/// é aqui que o nome, a unidade e o "Sair" moram nessa faixa.
class _GavetaMais extends ConsumerWidget {
  const _GavetaMais({required this.rotas, required this.altas});

  final List<Rota> rotas;
  final int altas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumo = ref.watch(resumoUsuarioProvider);
    final modo = ref.watch(preferenciaTemaProvider);
    final cores = Theme.of(context).colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(Dim.e16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: cores.surfaceContainerHighest,
                    child: Text(
                      iniciaisDe(resumo?.nome ?? ''),
                      style: Tipografia.rotulo,
                    ),
                  ),
                  const SizedBox(width: Dim.e12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          resumo?.nome ?? '',
                          style: Tipografia.rotulo,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (resumo?.unidade != null)
                          Text(
                            resumo!.unidade!,
                            style: Tipografia.apoio.copyWith(
                              color: cores.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  for (final rota in rotas)
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
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                modo == ThemeMode.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
              title: Text(
                modo == ThemeMode.dark ? 'Tema claro' : 'Tema escuro',
                style: Tipografia.corpo,
              ),
              minTileHeight: Dim.alvoMobile,
              onTap: () =>
                  ref.read(preferenciaTemaProvider.notifier).alternar(),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sair', style: Tipografia.corpo),
              minTileHeight: Dim.alvoMobile,
              onTap: () => ref.read(sessaoProvider.notifier).sair(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Até duas iniciais do nome — o avatar da gaveta. Nome vazio devolve vazio, e
/// o `CircleAvatar` fica só com o fundo, que é melhor que um "?" inventado.
String iniciaisDe(String nome) {
  final partes = nome
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList(growable: false);
  if (partes.isEmpty) return '';
  if (partes.length == 1) return partes.first.characters.first.toUpperCase();
  return (partes.first.characters.first + partes.last.characters.first)
      .toUpperCase();
}

/// Chave do gatilho do menu do usuário nas três faixas — é o que o teste de
/// alvo de toque mede (item H2).
const chaveGatilhoMenuUsuario = Key('gatilho-menu-usuario');

/// O rodapé do trilho do tablet: iniciais e primeiro nome de quem está logado.
///
/// **Só a identidade, sem um segundo gatilho** — o menu do usuário já está no
/// app bar desta faixa, e dois gatilhos idênticos a 60 px um do outro ensinam
/// que um deles faz outra coisa (item H2c).
class _RodapeTrilho extends ConsumerWidget {
  const _RodapeTrilho();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumo = ref.watch(resumoUsuarioProvider);
    if (resumo == null) return const SizedBox.shrink();
    final cores = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Conectado como ${resumo.nome}',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: cores.surfaceContainerHighest,
              child: Text(iniciaisDe(resumo.nome), style: Tipografia.apoio),
            ),
            const SizedBox(height: Dim.e4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Dim.e4),
              child: Text(
                resumo.nome,
                style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
