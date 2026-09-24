import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../rotina/rotina.dart';
import '../rotina/rotina_provider.dart';
import 'botoes.dart';
import 'dialogo_resultado.dart';

/// Chave do botão — os testes o procuram por ela.
const chaveRecalcularAgora = Key('recalcular_agora');

/// "Recalcular agora" — roda a rotina diária da unidade na hora (card 9.2,65).
///
/// Mora em Compras (ao lado do "Projeção calculada em …"), na Projeção e no
/// resultado da Importação aplicada: os três lugares onde a direção, depois de
/// importar, via "ainda não foi calculada" e tinha de esperar a madrugada.
///
/// Sem [permissaoRecalcular] o botão **não é renderizado** (card 2.6,
/// decisão 1). Enquanto roda, fica desabilitado com o motivo — dois cliques
/// seguidos não disparam duas rotinas (e, se dispararem de dois lugares, a
/// trava do banco devolve "já em execução").
///
/// O resultado vai em diálogo, e não em snackbar (design-system §5.8): "já está
/// recalculando" muda o que a pessoa faz em seguida — esperar.
class BotaoRecalcularAgora extends ConsumerStatefulWidget {
  const BotaoRecalcularAgora({super.key, this.nivel = NivelBotao.terciario});

  final NivelBotao nivel;

  @override
  ConsumerState<BotaoRecalcularAgora> createState() =>
      _BotaoRecalcularAgoraState();
}

class _BotaoRecalcularAgoraState extends ConsumerState<BotaoRecalcularAgora> {
  bool _ocupado = false;

  Future<void> _recalcular() async {
    setState(() => _ocupado = true);
    String titulo;
    String mensagem;
    TomResultado tom;
    try {
      final resultado = await recalcularAgora(ref);
      (titulo, mensagem, tom) = switch (resultado) {
        ResultadoRotina.executada => (
          tituloRotinaExecutada,
          mensagemRotinaExecutada,
          TomResultado.sucesso,
        ),
        ResultadoRotina.jaEmExecucao => (
          tituloRotinaEmExecucao,
          mensagemRotinaEmExecucao,
          TomResultado.atencao,
        ),
      };
    } on ErroApp catch (e) {
      (titulo, mensagem, tom) = (
        tituloRotinaNaoExecutada,
        e.mensagem,
        TomResultado.alerta,
      );
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
    if (!mounted) return;
    await mostrarResultado(
      context,
      titulo: titulo,
      mensagem: mensagem,
      tom: tom,
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: chaveRecalcularAgora,
      child: BotaoAcao(
        rotulo: _ocupado ? rotuloRecalculando : rotuloRecalcularAgora,
        icone: Icons.refresh,
        nivel: widget.nivel,
        exigePermissao: permissaoRecalcular,
        desabilitado: _ocupado
            ? const DesabilitadoCom(motivoRecalculando)
            : null,
        aoTocar: _recalcular,
      ),
    );
  }
}
