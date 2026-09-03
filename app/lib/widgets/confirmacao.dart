import 'package:flutter/material.dart';

/// Confirmação efêmera (design-system §5.8): salvou, excluiu, registrou.
///
/// Só para resultado que **não** muda a próxima ação — o que muda vai em
/// diálogo (card 2.7 (f)). Nasceu na tela de Materiais (card 4.4) e passou
/// para cá no card 4.5, quando a segunda tela precisou dela.
void confirmarEfemero(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
}
