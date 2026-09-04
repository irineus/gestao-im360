// Copiado do apêndice §10 de docs/design-system.md (card 2.7) — o card 3.7
// traz o lib/theme/ inteiro como está. Alterar aqui exige alterar lá.

import 'package:flutter/material.dart';

import 'cores.dart';
import 'dimensoes.dart';
import 'tipografia.dart';

/// ColorScheme montado à mão (não fromSeed): os hex são os verificados
/// em docs/identidade-visual.md — a semente geraria tons não auditados.
const _esquemaClaro = ColorScheme.light(
  primary: Cores.acao,
  onPrimary: Colors.white,
  secondary: Cores.grafite700,
  onSecondary: Colors.white,
  surface: Colors.white,
  onSurface: Cores.grafite900,
  surfaceContainerHighest: Cores.grafite100,
  onSurfaceVariant: Cores.grafite500,
  outline: Cores.grafite200,
  error: Cores.erro,
  onError: Colors.white,
  errorContainer: Cores.erroFundo,
  onErrorContainer: Cores.erro,
);

const _esquemaEscuro = ColorScheme.dark(
  primary: Cores.acaoEscuro,
  onPrimary: Cores.grafite900,
  secondary: Cores.textoEscuroSec,
  onSecondary: Cores.grafite900,
  surface: Cores.superficieEscura,
  onSurface: Cores.textoEscuroPrim,
  surfaceContainerHighest: Cores.superficieElevada,
  onSurfaceVariant: Cores.textoEscuroSec,
  outline: Cores.divisorEscuro,
  error: Cores.erroEscuro,
  onError: Cores.grafite900,
  // ⚠️ Sem estes dois o Flutter devolve `error` no lugar de `errorContainer`, e
  // toda superfície tonal de erro do tema escuro fica com fundo, borda e texto
  // na MESMA cor — ilegível, e sem erro nenhum em teste ou em `analyze`
  // (medido na revisão da fase 05: a célula "acima da capacidade" das duas
  // grades e o `AvisoTonal(erro: true)`). O par é o CANCELADO escuro de
  // `BadgesStatus.escuro`, cujo contraste já foi verificado.
  errorContainer: Cores.erroFundoEscuro,
  onErrorContainer: Cores.erroEscuro,
);

ThemeData _tema(
  ColorScheme esquema, {
  required bool escuro,
  required bool compacto,
}) {
  final foco = escuro
      ? Cores.acaoEscuro
      : Cores.grafite700; // anel de foco — card 1.9 §7
  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: escuro ? Cores.fundoEscuro : Cores.grafite50,
    fontFamily: 'Inter',
    visualDensity: compacto ? VisualDensity.compact : VisualDensity.standard,
    focusColor: foco,
    dividerTheme: DividerThemeData(
      color: esquema.outline,
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: Size(
          64,
          compacto ? Dim.alturaBotao : Dim.alturaBotaoMobile,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dim.raio),
        ),
        textStyle: Tipografia.rotulo,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: escuro ? Cores.superficieElevada : Cores.grafite100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Dim.raio),
        borderSide: BorderSide(color: esquema.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Dim.raio),
        borderSide: BorderSide(color: esquema.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Dim.raio),
        borderSide: BorderSide(color: esquema.error, width: 2),
      ),
      labelStyle: Tipografia.rotulo,
      helperStyle: Tipografia.apoio,
      errorStyle: Tipografia.apoio,
    ),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: Tipografia.cabecalhoTabela,
      headingRowColor: WidgetStatePropertyAll(esquema.surfaceContainerHighest),
      dataTextStyle: Tipografia.corpoTabela,
      dataRowMinHeight: compacto ? Dim.alturaLinha : Dim.alturaLinhaMobile,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Dim.raioDialogo),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Dim.raio),
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
  );
}

ThemeData temaClaro({bool compacto = true}) =>
    _tema(_esquemaClaro, escuro: false, compacto: compacto);
ThemeData temaEscuro({bool compacto = true}) =>
    _tema(_esquemaEscuro, escuro: true, compacto: compacto);
