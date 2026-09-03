import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../administracao/administracao.dart';
import '../../administracao/administracao_provider.dart';
import '../../sessao/sessao_provider.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/tabela_im360.dart';
import 'formularios.dart';

const vazioParametros =
    'Nenhum parâmetro cadastrado. Os 16 do seed chegam pela migração do card '
    '3.6; sem eles as regras param com PARAMETRO_AUSENTE.';

/// Parâmetros da unidade (docs/wireframes.md §15): chave, valor, descrição e
/// tipo. Editar `rep_*`/`projecao_*` (e os demais que a rotina diária lê)
/// mostra o aviso do efeito. Sem exclusão, por desenho: parâmetro ausente é
/// erro `PARAMETRO_AUSENTE` (card 3.4 §8.7) — corrige-se o valor.
class AbaParametros extends ConsumerWidget {
  const AbaParametros({super.key});

  Future<void> _abrir(BuildContext context, Parametro? parametro) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioParametro(parametro: parametro),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(context, 'Parâmetro salvo.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parametros = ref.watch(parametrosProvider);
    final permissoes = ref.watch(permissoesProvider);

    return TabelaIm360<Parametro>(
      acoes: [
        BotaoAcao(
          rotulo: 'Novo parâmetro',
          icone: Icons.add,
          exigePermissao: 'parametros.gerir',
          aoTocar: () => _abrir(context, null),
        ),
      ],
      colunas: [
        ColunaIm360(
          titulo: 'Chave',
          texto: (p) => p.chave,
          flex: 3,
          larguraMin: 220,
        ),
        ColunaIm360(
          titulo: 'Valor',
          texto: exibirValorParametro,
          numerica: true,
          flex: 1,
          larguraMin: 100,
        ),
        ColunaIm360(
          titulo: 'Descrição',
          texto: (p) => p.descricao ?? '',
          flex: 5,
          prioridade: 2,
          larguraMin: 240,
        ),
        ColunaIm360(
          titulo: 'Tipo',
          texto: (p) => rotuloTipoParametro(p.tipo),
          flex: 1,
          prioridade: 3,
          larguraMin: 90,
        ),
      ],
      linhas: parametros,
      cartao: (p) => CartaoIm360(
        titulo: p.chave,
        subtitulo: p.descricao,
        destaque: exibirValorParametro(p),
      ),
      estadoVazio: EstadoVazio(
        mensagem: vazioParametros,
        rotuloAcao: permissoes.contains('parametros.gerir')
            ? '+ Novo parâmetro'
            : null,
        aoAgir: () => _abrir(context, null),
      ),
      aoTocarLinha: (p) => _abrir(context, p),
      aoRepetir: ref.read(versaoAdministracaoProvider.notifier).incrementar,
    );
  }
}
