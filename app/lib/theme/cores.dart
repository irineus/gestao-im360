// Copiado do apêndice §10 de docs/design-system.md (card 2.7) — o card 3.7
// traz o lib/theme/ inteiro como está. Alterar aqui exige alterar lá.

import 'package:flutter/material.dart';

/// Tokens de cor — fonte: docs/identidade-visual.md + docs/design-system.md §2.
/// Nenhum componente usa hex direto: sempre um papel daqui ou do ColorScheme.
abstract final class Cores {
  // marca e ação
  static const marca = Color(
    0xFFE2620F,
  ); // só logotipo — reprova AA como texto/botão
  static const acao = Color(0xFFBE4E08);
  static const acaoHover = Color(0xFF973E09);
  static const acaoEscuro = Color(0xFFF2803F);
  static const acaoEscuroHover = Color(0xFFFBA36F);

  // grafite (estrutura, tema claro)
  static const grafite50 = Color(0xFFF6F7F9);
  static const grafite100 = Color(0xFFECEEF2);
  static const grafite200 = Color(0xFFD9DDE5);
  static const grafite400 = Color(0xFF8B94A6);
  static const grafite500 = Color(0xFF656F82);
  static const grafite700 = Color(0xFF3A4252);
  static const grafite800 = Color(0xFF262D3A);
  static const grafite900 = Color(0xFF171C26);

  // seleção (claro)
  static const selecao50 = Color(0xFFFFF4EC);
  static const selecao100 = Color(0xFFFFE3D0);

  // semânticos — claro (texto / fundo tonal)
  static const sucesso = Color(0xFF1E7A46);
  static const sucessoFundo = Color(0xFFE6F4EC);
  static const atencao = Color(0xFF8A5A06);
  static const atencaoFundo = Color(0xFFFCF3E0);
  static const erro = Color(0xFFB42318);
  static const erroFundo = Color(0xFFFEF3F2);
  static const info = Color(0xFF1B5FA8);
  static const infoFundo = Color(0xFFEAF2FB);

  // tema escuro — estrutura
  static const fundoEscuro = Color(0xFF12161F);
  static const superficieEscura = Color(0xFF1B2130);
  static const superficieElevada = Color(0xFF262D3A);
  static const divisorEscuro = Color(0xFF333B4B);
  static const textoEscuroPrim = Color(0xFFE7EAF0);
  static const textoEscuroSec = Color(0xFFA7B0C0);
  static const desabilitadoEscuro = Color(0xFF5D6678);
  static const selecaoEscura = Color(0xFF33241A);

  // semânticos — escuro
  static const sucessoEscuro = Color(0xFF5FD08C);
  static const atencaoEscuro = Color(0xFFE5B65C);
  static const erroEscuro = Color(0xFFF87A6E);
  static const infoEscuro = Color(0xFF7FB4F0);

  /// Fundo tonal de erro no tema escuro — o mesmo do badge CANCELADO escuro,
  /// cujo contraste com [erroEscuro] já está verificado (§2.3). Existe para o
  /// `errorContainer` do esquema escuro não cair no `error`, que igualaria
  /// fundo e texto.
  static const erroFundoEscuro = Color(0xFF3D212B);

  /// Fundo tonal de ATENÇÃO no tema escuro — o mesmo do badge STANDBY escuro,
  /// cujo contraste com [atencaoEscuro] já está verificado (§2.3: 7,4:1).
  /// Existe pela mesma razão do [erroFundoEscuro]: sem ele o
  /// `tertiaryContainer` do esquema cai no `secondary`, e toda superfície
  /// tonal de atenção sai grafite (revisão das telas 06/07, item A1).
  static const atencaoFundoEscuro = Color(0xFF332E27);

  // FORMADO (violeta própria — card 1.9 §6)
  static const formado = Color(0xFF4C3FA8);
  static const formadoEscuro = Color(0xFFB3A6F2);
}

/// Par texto/fundo de um badge de status, por tema. Contrastes AA verificados
/// (docs/design-system.md §2.3).
class ParBadge {
  final Color texto, fundo;
  const ParBadge(this.texto, this.fundo);
}

abstract final class BadgesStatus {
  static const claro = {
    'ATIVO': ParBadge(Color(0xFF1E7A46), Color(0xFFE6F4EC)),
    'ACELERAR': ParBadge(Color(0xFF973E09), Color(0xFFFFF0E4)),
    'STANDBY': ParBadge(Color(0xFF8A5A06), Color(0xFFFCF3E0)),
    'TRANCADO': ParBadge(Color(0xFF3A4252), Color(0xFFECEEF2)),
    'CANCELADO': ParBadge(Color(0xFFB42318), Color(0xFFFEF3F2)),
    'FORMADO': ParBadge(Color(0xFF4C3FA8), Color(0xFFEEEBFA)),
  };
  static const escuro = {
    'ATIVO': ParBadge(Color(0xFF5FD08C), Color(0xFF1C3535)),
    'ACELERAR': ParBadge(Color(0xFFF5A468), Color(0xFF3A2826)),
    'STANDBY': ParBadge(Color(0xFFE5B65C), Color(0xFF332E27)),
    'TRANCADO': ParBadge(Color(0xFFA7B0C0), Color(0xFF262D3A)),
    'CANCELADO': ParBadge(Color(0xFFF87A6E), Color(0xFF3D212B)),
    'FORMADO': ParBadge(Color(0xFFB3A6F2), Color(0xFF27284E)),
  };
}

abstract final class BadgesTipo {
  static const claro = {
    'NOVO': Color(0xFF1E7A46),
    'REM': Color(0xFF656F82),
    'PRE': Color(0xFF1B5FA8),
    'REP': Color(0xFF8A5A06),
  };
  static const escuro = {
    'NOVO': Color(0xFF5FD08C),
    'REM': Color(0xFFA7B0C0),
    'PRE': Color(0xFF7FB4F0),
    'REP': Color(0xFFE5B65C),
  };
}
