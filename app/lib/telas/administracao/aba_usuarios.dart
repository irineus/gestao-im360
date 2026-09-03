import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../administracao/administracao.dart';
import '../../administracao/administracao_provider.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/tabela_im360.dart';
import 'formularios.dart';

/// Estado vazio (design-system §7.2). A lista nunca fica vazia de verdade —
/// quem a abre está nela —, então "Só você por aqui" aparece como linha de
/// apoio acima da tabela quando o único usuário é quem está logado.
const vazioUsuariosFiltro = 'Nenhum usuário com esses filtros.';
const soVocePorAqui = 'Só você por aqui. Convide a equipe em Convidar usuário.';

/// O destaque que o card 3.7 pediu: quem está sem perfil entra e não vê nada,
/// e hoje isso só se descobre quando a pessoa tenta entrar.
String avisoSemPerfil(int n) => n == 1
    ? '1 usuário ativo sem perfil: entra e não vê nada até receber um perfil.'
    : '$n usuários ativos sem perfil: entram e não veem nada até receber um '
          'perfil.';

class AbaUsuarios extends ConsumerWidget {
  const AbaUsuarios({super.key});

  Future<void> _convidar(BuildContext context) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => const FormularioConvite(),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(context, 'Convite enviado.');
    }
  }

  Future<void> _abrir(BuildContext context, UsuarioAdmin usuario) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioUsuario(usuario: usuario),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(context, 'Usuário salvo.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuarios = ref.watch(usuariosAdminProvider);
    final perfis = ref.watch(perfisProvider).value ?? const <Perfil>[];
    final perfisPorId = {
      for (final p in perfis)
        if (p.id != null) p.id!: p,
    };
    final filtro = ref.watch(filtroUsuariosProvider);
    final permissoes = ref.watch(permissoesProvider);
    final sessao = ref.watch(resumoUsuarioProvider);
    final todos = usuarios.value ?? const <UsuarioAdmin>[];
    final semPerfil = contarSemPerfil(todos);
    final soEu = todos.length == 1 && todos.single.nome == sessao?.nome;

    return TabelaIm360<UsuarioAdmin>(
      filtros: FiltrosUsuarios(
        semPerfil: semPerfil,
        aviso: semPerfil > 0
            ? avisoSemPerfil(semPerfil)
            : soEu && permissoes.contains('admin.gerir_usuarios')
            ? soVocePorAqui
            : null,
        avisoErro: semPerfil > 0,
      ),
      filtrosAtivos: filtro.ativos,
      acoes: [
        BotaoAcao(
          rotulo: 'Convidar usuário',
          icone: Icons.person_add_alt_1_outlined,
          exigePermissao: 'admin.gerir_usuarios',
          aoTocar: () => _convidar(context),
        ),
      ],
      colunas: [
        ColunaIm360(
          titulo: 'Nome',
          texto: (u) => u.nome,
          flex: 3,
          larguraMin: 180,
        ),
        ColunaIm360(
          titulo: 'E-mail',
          texto: (u) => u.email,
          flex: 3,
          prioridade: 2,
          larguraMin: 200,
        ),
        ColunaIm360(
          titulo: 'Perfis',
          texto: (u) => u.ativo && u.semPerfil
              ? '⚠ sem perfil'
              : rotuloPerfis(u, perfisPorId),
          flex: 3,
          larguraMin: 160,
        ),
        ColunaIm360(
          titulo: 'Situação',
          texto: (u) => u.ativo ? 'Ativo' : 'Desativado',
          prioridade: 3,
          flex: 1,
          larguraMin: 100,
        ),
      ],
      linhas: usuarios.whenData((lista) => filtrarUsuarios(lista, filtro)),
      cartao: (u) => CartaoIm360(
        titulo: u.nome,
        subtitulo: u.email,
        apoio: u.ativo
            ? (u.semPerfil ? '⚠ sem perfil' : rotuloPerfis(u, perfisPorId))
            : 'Desativado',
      ),
      estadoVazio: EstadoVazio(
        mensagem: vazioUsuariosFiltro,
        icone: Icons.filter_alt_off_outlined,
        rotuloAcao: 'Limpar filtros',
        aoAgir: ref.read(filtroUsuariosProvider.notifier).limpar,
      ),
      aoTocarLinha: (u) => _abrir(context, u),
      aoRepetir: ref.read(versaoAdministracaoProvider.notifier).incrementar,
    );
  }
}

/// Barra de filtros da aba (design-system §5.3): busca por nome ou e-mail,
/// "Só ativos" e "Sem perfil (n)" — mais a linha de apoio que diz quantos
/// estão sem perfil. O estado mora no provider, não aqui.
class FiltrosUsuarios extends ConsumerStatefulWidget {
  const FiltrosUsuarios({
    super.key,
    this.semPerfil = 0,
    this.aviso,
    this.avisoErro = false,
  });

  final int semPerfil;
  final String? aviso;
  final bool avisoErro;

  @override
  ConsumerState<FiltrosUsuarios> createState() => _FiltrosUsuariosState();
}

class _FiltrosUsuariosState extends ConsumerState<FiltrosUsuarios> {
  late final _busca = TextEditingController(
    text: ref.read(filtroUsuariosProvider).busca,
  );

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(filtroUsuariosProvider, (_, novo) {
      if (_busca.text != novo.busca) _busca.text = novo.busca;
    });
    final filtro = ref.watch(filtroUsuariosProvider);
    final controlador = ref.read(filtroUsuariosProvider.notifier);
    final cores = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Dim.e8,
          runSpacing: Dim.e8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: _busca,
                style: Tipografia.corpo,
                decoration: InputDecoration(
                  labelText: 'Nome ou e-mail',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: filtro.busca.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar busca',
                          icon: const Icon(Icons.clear),
                          onPressed: () =>
                              controlador.definir(filtro.copiar(busca: '')),
                        ),
                ),
                onChanged: (valor) =>
                    controlador.definir(filtro.copiar(busca: valor)),
              ),
            ),
            FilterChip(
              label: const Text('Só ativos'),
              selected: filtro.soAtivos,
              onSelected: (valor) =>
                  controlador.definir(filtro.copiar(soAtivos: valor)),
            ),
            FilterChip(
              label: Text(
                widget.semPerfil > 0
                    ? 'Sem perfil (${widget.semPerfil})'
                    : 'Sem perfil',
              ),
              selected: filtro.soSemPerfil,
              onSelected: (valor) =>
                  controlador.definir(filtro.copiar(soSemPerfil: valor)),
            ),
          ],
        ),
        if (widget.aviso != null) ...[
          const SizedBox(height: Dim.e8),
          Row(
            children: [
              Icon(
                widget.avisoErro
                    ? Icons.warning_amber_outlined
                    : Icons.info_outline,
                size: 16,
                color: widget.avisoErro ? cores.error : cores.onSurfaceVariant,
              ),
              const SizedBox(width: Dim.e8),
              Expanded(
                child: Text(
                  widget.aviso!,
                  style: Tipografia.apoio.copyWith(
                    color: widget.avisoErro
                        ? cores.error
                        : cores.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
