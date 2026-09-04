import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../administracao/administracao.dart';
import '../../administracao/administracao_provider.dart';
import '../../widgets/estados.dart';
import '../../widgets/tabela_im360.dart';

const vazioHistorico =
    'Nenhuma alteração na matriz registrada. O registro começou quando esta '
    'tela passou a existir: o que foi marcado antes não tem rastro.';

/// Histórico da matriz (card 4.7.5): toda concessão e remoção de permissão a
/// um perfil, com quem e quando — escrito por trigger, imutável, legível com
/// `admin.ler`. É a mitigação de "permissões mal definidas exporem dados" da
/// seção 4 das Decisões vigentes: três meses depois, dá para saber quem tirou
/// `estoque.ajustar` da secretaria.
class AbaHistorico extends ConsumerWidget {
  const AbaHistorico({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historico = ref.watch(historicoMatrizProvider);

    return TabelaIm360<LinhaHistoricoMatriz>(
      colunas: [
        ColunaIm360(
          titulo: 'Quando',
          texto: (l) => formatarQuando(l.em),
          numerica: true,
          flex: 2,
          larguraMin: 140,
        ),
        ColunaIm360(
          titulo: 'Perfil',
          texto: (l) => l.perfilCodigo,
          flex: 2,
          larguraMin: 130,
        ),
        ColunaIm360(
          titulo: 'Permissão',
          texto: (l) => l.permissaoCodigo,
          flex: 3,
          larguraMin: 220,
        ),
        ColunaIm360(
          titulo: 'Ação',
          texto: (l) => rotuloAcaoHistorico(l.acao),
          flex: 1,
          larguraMin: 100,
        ),
        ColunaIm360(
          titulo: 'Por',
          texto: (l) => rotuloAutorHistorico(l.porNome),
          flex: 2,
          prioridade: 2,
          larguraMin: 140,
        ),
      ],
      linhas: historico,
      cartao: (l) => CartaoIm360(
        titulo: '${l.permissaoCodigo} · ${rotuloAcaoHistorico(l.acao)}',
        subtitulo: '${l.perfilCodigo} · ${rotuloAutorHistorico(l.porNome)}',
        apoio: formatarQuando(l.em),
      ),
      estadoVazio: const EstadoVazio(
        mensagem: vazioHistorico,
        icone: Icons.history_outlined,
      ),
      aoRepetir: ref.read(versaoAdministracaoProvider.notifier).incrementar,
    );
  }
}
