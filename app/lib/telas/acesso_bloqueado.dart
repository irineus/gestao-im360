import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sessao/sessao.dart';
import '../sessao/sessao_provider.dart';
import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';

/// Erro **explícito** de sessão — nunca tela vazia.
///
/// É o ajuste 3 do card 3.5 e a razão de este card existir do jeito que existe:
/// um autenticado sem espelho (ou desativado) tem token, `fn_unidade_atual()`
/// devolve `null`, toda política nega e **todas as telas ficariam vazias, sem
/// erro nenhum** (docs/acesso-autenticacao.md §1). O mesmo vale para quem tem
/// espelho e nenhum perfil: um shell sem itens é o mesmo silêncio com outra
/// roupa.
class TelaAcessoBloqueado extends ConsumerWidget {
  const TelaAcessoBloqueado({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(sessaoProvider);
    final cores = Theme.of(context).colorScheme;

    final (titulo, detalhe, mostrarSair) = switch (estado) {
      // Os dois casos são indistinguíveis pelo app: `fn_unidade_atual` e
      // `tem_permissao` exigem `usuario.ativo`, então o desativado também lê
      // zero linhas da própria linha de usuario (card 3.4). Dizer "ainda não
      // foi liberado" a quem foi desligado seria mentira com cara de bug.
      SessaoSemEspelho(:final email) => (
        'Seu acesso ainda não foi liberado',
        'A conta $email entrou, mas ainda não está habilitada nesta unidade — '
            'ou foi desativada. Avise a direção.',
        true,
      ),
      SessaoSemPerfil(:final sessao) => (
        'Seu usuário ainda não tem perfil',
        '${sessao.nome} entrou, mas nenhum perfil foi atribuído, então nenhuma '
            'tela está disponível. Peça à direção para atribuir um perfil em '
            'Administração → Usuários.',
        true,
      ),
      SessaoErro(:final mensagem, :final codigo) => (
        'Não foi possível carregar sua sessão',
        codigo == null ? mensagem : '$mensagem (código $codigo)',
        true,
      ),
      _ => ('Carregando…', '', false),
    };

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Dim.larguraFormularioMax),
          child: Padding(
            padding: const EdgeInsets.all(Dim.e24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 40,
                  color: cores.onSurfaceVariant,
                ),
                const SizedBox(height: Dim.e16),
                Text(
                  titulo,
                  style: Tipografia.subtitulo,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Dim.e8),
                Text(
                  detalhe,
                  style: Tipografia.corpo,
                  textAlign: TextAlign.center,
                ),
                if (mostrarSair) ...[
                  const SizedBox(height: Dim.e24),
                  Wrap(
                    spacing: Dim.e8,
                    children: [
                      FilledButton.tonal(
                        onPressed: () =>
                            ref.read(sessaoProvider.notifier).recarregar(),
                        child: const Text('Tentar de novo'),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.read(sessaoProvider.notifier).sair(),
                        child: const Text('Sair'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
