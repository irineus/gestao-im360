import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../administracao/administracao.dart';
import '../../administracao/administracao_provider.dart';
import '../../erros/erro_app.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';
import 'formularios.dart';

/// Textos da aba (design-system §7.3 e docs/wireframes.md §15).
const cabecalhoCatalogo =
    'O catálogo de permissões não é editável aqui: código novo só entra por '
    'migração. Marque o que cada perfil pode; a caixa mostra o código e o que '
    'ele autoriza.';
const avisoDesmarcar =
    'A mudança vale imediatamente para todos os usuários do perfil.';
const avisoPerfilDesativado =
    'Perfil desativado: as permissões marcadas não valem para ninguém até ele '
    'ser reativado.';
const vazioPerfis = 'Nenhum perfil cadastrado.';

/// A matriz perfil × permissão (docs/wireframes.md §15): um perfil por vez,
/// os 12 domínios como seções, uma caixa por código com a descrição ao lado.
/// Marcar é insert e desmarcar é delete em `perfil_permissao` (card 3.4
/// §8.5); desmarcar avisa que vale na hora. O histórico é a quarta aba.
class AbaMatriz extends ConsumerStatefulWidget {
  const AbaMatriz({super.key});

  @override
  ConsumerState<AbaMatriz> createState() => _AbaMatrizState();
}

class _AbaMatrizState extends ConsumerState<AbaMatriz> {
  String? _erro;
  bool _gravando = false;

  Future<void> _alternar(
    Perfil perfil,
    Permissao permissao,
    bool marcar,
  ) async {
    if (!marcar) {
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (contexto) => AlertDialog(
          title: Text('Desmarcar ${permissao.codigo}?'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              '$avisoDesmarcar\n\n${permissao.descricao}',
              style: Tipografia.corpo,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(contexto).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(contexto).pop(true),
              child: const Text('Desmarcar'),
            ),
          ],
        ),
      );
      if (confirmou != true || !mounted) return;
    }

    setState(() {
      _gravando = true;
      _erro = null;
    });
    try {
      final repositorio = ref.read(administracaoRepositorioProvider);
      if (marcar) {
        await repositorio.marcar(perfil.id!, permissao.id);
      } else {
        await repositorio.desmarcar(perfil.id!, permissao.id);
      }
      ref.read(versaoAdministracaoProvider.notifier).incrementar();
      if (mounted) {
        confirmarEfemero(
          context,
          marcar
              ? '${permissao.codigo} concedida a ${perfil.codigo}.'
              : '${permissao.codigo} removida de ${perfil.codigo}.',
        );
      }
    } catch (erro) {
      if (mounted) setState(() => _erro = traduzirErro(erro).mensagem);
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  Future<void> _abrirPerfil(Perfil? perfil) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioPerfil(perfil: perfil),
    );
    if (resultado != null && mounted) {
      if (perfil == null) {
        ref.read(perfilSelecionadoProvider.notifier).definir(resultado);
      }
      confirmarEfemero(context, 'Perfil salvo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfis = ref.watch(perfisProvider);
    final catalogo = ref.watch(catalogoPermissoesProvider);
    final matriz = ref.watch(matrizProvider);
    final permissoesUsuario = ref.watch(permissoesProvider);
    final podeGerir = permissoesUsuario.contains('admin.gerir_perfis');
    final cores = Theme.of(context).colorScheme;

    final erro = perfis.error ?? catalogo.error ?? matriz.error;
    if (erro != null) {
      final traduzido = erro is ErroApp ? erro : traduzirErro(erro);
      return EstadoErro(
        mensagem: traduzido.mensagem,
        codigoTecnico: traduzido.traduzido ? null : traduzido.codigo,
        aoRepetir: ref.read(versaoAdministracaoProvider.notifier).incrementar,
      );
    }
    if (!perfis.hasValue || !catalogo.hasValue || !matriz.hasValue) {
      return const EstadoCarregando();
    }

    final listaPerfis = perfis.value!;
    if (listaPerfis.isEmpty) {
      return EstadoVazio(
        mensagem: vazioPerfis,
        rotuloAcao: podeGerir ? '+ Novo perfil' : null,
        aoAgir: () => _abrirPerfil(null),
      );
    }

    final selecionadoId = ref.watch(perfilSelecionadoProvider);
    final perfil = listaPerfis.firstWhere(
      (p) => p.id == selecionadoId,
      orElse: () => listaPerfis.firstWhere(
        (p) => p.ativo,
        orElse: () => listaPerfis.first,
      ),
    );
    final marcadas = matriz.value![perfil.id] ?? const <String>{};
    final grupos = agruparPorDominio(catalogo.value!);
    final total = catalogo.value!.length;
    final podeMarcar = podeGerir && !_gravando;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Dim.e16, Dim.e16, Dim.e16, Dim.e8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: Dim.e8,
                runSpacing: Dim.e8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownMenu<String>(
                    key: ValueKey('perfil-${perfil.id}'),
                    width: 260,
                    label: const Text('Perfil'),
                    textStyle: Tipografia.corpo,
                    initialSelection: perfil.id,
                    dropdownMenuEntries: [
                      for (final p in listaPerfis)
                        DropdownMenuEntry(
                          value: p.id!,
                          label: p.ativo
                              ? '${p.codigo} — ${p.nome}'
                              : '${p.codigo} — ${p.nome} (desativado)',
                        ),
                    ],
                    onSelected: (id) => ref
                        .read(perfilSelecionadoProvider.notifier)
                        .definir(id),
                  ),
                  BotaoAcao(
                    rotulo: 'Editar perfil',
                    icone: Icons.edit_outlined,
                    nivel: NivelBotao.secundario,
                    exigePermissao: 'admin.gerir_perfis',
                    aoTocar: () => _abrirPerfil(perfil),
                  ),
                  BotaoAcao(
                    rotulo: 'Novo perfil',
                    icone: Icons.add,
                    exigePermissao: 'admin.gerir_perfis',
                    aoTocar: () => _abrirPerfil(null),
                  ),
                ],
              ),
              const SizedBox(height: Dim.e8),
              Text(
                cabecalhoCatalogo,
                style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
              ),
              const SizedBox(height: Dim.e8),
              Text(
                '${marcadas.length} de $total permissões marcadas para '
                '${perfil.codigo}',
                style: Tipografia.numero(Tipografia.rotulo),
              ),
              if (!perfil.ativo) ...[
                const SizedBox(height: Dim.e8),
                const AvisoTonal(mensagem: avisoPerfilDesativado),
              ],
              if (_erro != null) ...[
                const SizedBox(height: Dim.e8),
                AvisoTonal(mensagem: _erro!, erro: true),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Dim.e16,
              Dim.e8,
              Dim.e16,
              Dim.e24,
            ),
            children: [
              for (final grupo in grupos) ...[
                const SizedBox(height: Dim.e12),
                TituloSecao(
                  texto: grupo.rotulo,
                  apoio:
                      '${grupo.permissoes.where((p) => marcadas.contains(p.id)).length}'
                      ' de ${grupo.permissoes.length}',
                ),
                for (final permissao in grupo.permissoes)
                  CheckboxListTile(
                    key: ValueKey('caixa-${permissao.codigo}'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    title: Text(
                      permissao.codigo,
                      style: Tipografia.numero(Tipografia.rotulo),
                    ),
                    subtitle: Text(
                      permissao.descricao,
                      style: Tipografia.apoio,
                    ),
                    value: marcadas.contains(permissao.id),
                    // Sem admin.gerir_perfis a caixa é só leitura: a matriz
                    // continua visível para quem tem admin.ler.
                    onChanged: podeMarcar
                        ? (valor) => _alternar(perfil, permissao, valor == true)
                        : null,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
