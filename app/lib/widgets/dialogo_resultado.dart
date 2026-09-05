import 'package:flutter/material.dart';

import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';

/// **Resultado que muda o que o usuário fará em seguida** — design-system §5.8.
///
/// Nasceu no card 6.6, com os três status de `fn_registrar_entrega`: entregar a
/// próxima, procurar a apostila pulada, abrir a pendência de compra. Os três
/// mandam a pessoa a lugares diferentes, e **snackbar some antes de ser lido** —
/// por isso o §5.8 reserva o efêmero para o que não muda a próxima ação
/// (`confirmarEfemero`) e manda o resto para cá.
///
/// **Duas formas, uma por faixa** (wireframe §6.3: "diálogos de resultado em
/// folha inferior" no mobile): no celular a folha inferior nasce perto do
/// polegar e não cobre a lista; no desktop, diálogo centrado. É a mesma
/// bifurcação de `mostrarFormulario`, e ela mora aqui para nenhuma tela ter de
/// repeti-la.
///
/// Genérico de propósito, e não "diálogo da entrega": o veredito da virada REP
/// (card 2.5) e o recebimento com excedente (card 6.5) são a mesma forma.
enum TomResultado {
  /// Deu certo e a jornada continua (entrega registrada).
  sucesso,

  /// Deu certo, mas **não** como se pediu — alguém precisa saber (trilha
  /// reordenada por falta de estoque).
  atencao,

  /// Não aconteceu, e sobrou uma pendência (entrega bloqueada).
  alerta,
}

/// Um destino oferecido pelo resultado — "Ver pendência", "Ver checklist".
@immutable
class LinkResultado {
  const LinkResultado({required this.rotulo, required this.aoTocar});

  final String rotulo;
  final VoidCallback aoTocar;
}

/// Chave do botão que fecha — os testes de tela o procuram por ela, porque
/// "Entendi" é texto e texto muda.
const chaveFecharResultado = Key('resultado_fechar');

/// Mostra o resultado e volta quando a pessoa fechar.
///
/// O link **fecha o resultado antes de navegar**: sem isso, a folha inferior
/// fica por cima da tela de destino e a pessoa chega ao lugar certo sem
/// conseguir vê-lo.
Future<void> mostrarResultado(
  BuildContext context, {
  required String titulo,
  required String mensagem,
  TomResultado tom = TomResultado.sucesso,
  List<LinkResultado> links = const [],
}) {
  final mobile = faixaDe(MediaQuery.sizeOf(context).width) == Faixa.mobile;
  final conteudo = _Resultado(
    titulo: titulo,
    mensagem: mensagem,
    tom: tom,
    links: links,
  );

  if (mobile) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(child: conteudo),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Dim.larguraFormularioMax),
        child: conteudo,
      ),
    ),
  );
}

class _Resultado extends StatelessWidget {
  const _Resultado({
    required this.titulo,
    required this.mensagem,
    required this.tom,
    required this.links,
  });

  final String titulo;
  final String mensagem;
  final TomResultado tom;
  final List<LinkResultado> links;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    // Cor NUNCA é portadora única (design-system §8.2): o ícone tem forma
    // própria e o título diz em palavras o que aconteceu.
    final (icone, cor) = switch (tom) {
      TomResultado.sucesso => (Icons.check_circle_outline, cores.primary),
      TomResultado.atencao => (Icons.swap_vert, cores.onTertiaryContainer),
      TomResultado.alerta => (Icons.error_outline, cores.error),
    };

    return Padding(
      padding: const EdgeInsets.all(Dim.e24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icone, color: cor),
              const SizedBox(width: Dim.e12),
              Expanded(child: Text(titulo, style: Tipografia.subtitulo)),
            ],
          ),
          const SizedBox(height: Dim.e12),
          Text(mensagem, style: Tipografia.corpo),
          const SizedBox(height: Dim.e24),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: Dim.e8,
            runSpacing: Dim.e8,
            children: [
              for (final link in links)
                SizedBox(
                  height: Dim.alvoMobile,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      link.aoTocar();
                    },
                    child: Text(link.rotulo),
                  ),
                ),
              SizedBox(
                height: Dim.alvoMobile,
                child: FilledButton(
                  key: chaveFecharResultado,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Entendi'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
