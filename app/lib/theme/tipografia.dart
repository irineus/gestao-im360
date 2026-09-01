// Copiado do apêndice §10 de docs/design-system.md (card 2.7) — o card 3.7
// traz o lib/theme/ inteiro como está. Alterar aqui exige alterar lá.

import 'package:flutter/material.dart';

/// Escala tipográfica — Inter empacotada como asset (card 3.7).
abstract final class Tipografia {
  static const _familia = 'Inter';

  static const titulo = TextStyle(
    fontFamily: _familia,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w700,
  );
  static const subtitulo = TextStyle(
    fontFamily: _familia,
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
  );
  static const corpo = TextStyle(
    fontFamily: _familia,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );
  static const corpoTabela = TextStyle(
    fontFamily: _familia,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );
  static const rotulo = TextStyle(
    fontFamily: _familia,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
  );
  static const cabecalhoTabela = TextStyle(
    fontFamily: _familia,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
  );
  static const apoio = TextStyle(
    fontFamily: _familia,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );
  static const badge = TextStyle(
    fontFamily: _familia,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
  );

  /// Numerais tabulares — obrigatório em tabela, grade e valor de estoque.
  static TextStyle numero(TextStyle base) =>
      base.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
