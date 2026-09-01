// Copiado do apêndice §10 de docs/design-system.md (card 2.7) — o card 3.7
// traz o lib/theme/ inteiro como está. Alterar aqui exige alterar lá.

/// Espaçamento, raios e breakpoints — docs/design-system.md §2.6 e §3.
abstract final class Dim {
  // espaçamento (múltiplos de 4)
  static const e4 = 4.0,
      e8 = 8.0,
      e12 = 12.0,
      e16 = 16.0,
      e24 = 24.0,
      e32 = 32.0;

  // raios
  static const raioBadge = 6.0, raio = 8.0, raioDialogo = 12.0;

  // breakpoints (card 2.6 §2.1)
  static const bpTablet = 600.0, bpDesktop = 1024.0;
  static const larguraMenu = 240.0,
      larguraTrilho = 72.0,
      larguraConteudoMax = 1440.0;
  static const larguraFormularioMax = 560.0;

  // alvos e alturas
  static const alvoMobile = 44.0, alturaBotao = 40.0, alturaBotaoMobile = 48.0;
  static const alturaLinha = 44.0, alturaLinhaMobile = 48.0;
}

enum Faixa { mobile, tablet, desktop }

Faixa faixaDe(double largura) => largura >= Dim.bpDesktop
    ? Faixa.desktop
    : largura >= Dim.bpTablet
    ? Faixa.tablet
    : Faixa.mobile;
