import 'package:flutter/material.dart';

import '../config/ambiente.dart';
import '../theme/tipografia.dart';

/// O texto da versão (card 9.2,82), igual em todo lugar em que aparece.
String get textoVersao => 'Versão ${Ambiente.versao}';

/// A versão do app, discreta: rodapé da tela de entrada e da de senha, menu do
/// usuário e gaveta do celular. A cor é declarada aqui, e não herdada, porque
/// dentro de um item de menu desabilitado o texto herdaria a cor de
/// "desabilitado", que reprova o contraste AA.
class TextoVersao extends StatelessWidget {
  const TextoVersao({super.key, this.alinhamento = TextAlign.start});

  final TextAlign alinhamento;

  @override
  Widget build(BuildContext context) => Text(
    textoVersao,
    textAlign: alinhamento,
    style: Tipografia.apoio.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}
