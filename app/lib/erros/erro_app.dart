import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'catalogo_erros.dart';

/// Erro já traduzido para a tela: o `codigo` estável (quando existe) e o texto
/// em português do catálogo do card 2.7 §7.1.
///
/// A tela nunca lê `mensagem` do banco: lê daqui.
class ErroApp implements Exception {
  const ErroApp({required this.mensagem, this.codigo, this.original});

  /// Código estável do `DETAIL` (card 2.2 §1.2), quando o erro veio de uma
  /// regra de negócio. Nulo em erro de rede, de Auth ou inesperado.
  final String? codigo;

  /// Texto pronto para exibição.
  final String mensagem;

  /// O erro original, para o Sentry (card 3.12). Nunca vai para a tela.
  final Object? original;

  /// Verdadeiro quando o catálogo tem tradução própria — o oposto do fallback,
  /// que a `EstadoErro` usa para decidir se mostra o código técnico em apoio.
  bool get traduzido => CatalogoErros.mapeado(codigo);

  @override
  String toString() => 'ErroApp(${codigo ?? '-'}): $mensagem';
}

/// Mensagem única de credencial inválida: nunca dizer qual campo errou
/// (docs/wireframes.md §4).
const mensagemCredencialInvalida = 'E-mail ou senha inválidos.';

const _mensagemRede =
    'Não foi possível falar com o servidor. Verifique a conexão e tente de novo.';

/// Traduz qualquer exceção do Supabase para [ErroApp].
///
/// A ordem importa: um `PostgrestException` de regra de negócio carrega o
/// `codigo` no `details`; sem ele, cai no texto genérico que sempre mostra o
/// código técnico.
ErroApp traduzirErro(Object erro) {
  if (erro is ErroApp) return erro;

  if (erro is PostgrestException) {
    final codigo = _codigoDoDetalhe(erro.details);
    return ErroApp(
      codigo: codigo,
      mensagem: CatalogoErros.mensagem(
        codigo ?? erro.code,
        valores: _valoresDoDetalhe(erro.details),
      ),
      original: erro,
    );
  }

  if (erro is AuthApiException) {
    // Credencial inválida tem mensagem única, sem revelar qual campo errou.
    final invalida =
        erro.code == 'invalid_credentials' ||
        erro.statusCode == '400' &&
            erro.message.toLowerCase().contains('invalid login');
    return ErroApp(
      codigo: erro.code,
      mensagem: invalida
          ? mensagemCredencialInvalida
          : CatalogoErros.mensagem(erro.code),
      original: erro,
    );
  }

  if (erro is AuthException) {
    return ErroApp(
      codigo: erro.code,
      mensagem: CatalogoErros.mensagem(erro.code),
      original: erro,
    );
  }

  return ErroApp(mensagem: _mensagemRede, original: erro);
}

/// Extrai o `codigo` do `DETAIL`.
///
/// A convenção do card 2.2 §1.2 é um objeto JSON com a chave `codigo`. Aceita
/// também o `DETAIL` em texto puro com o código sozinho, porque
/// docs/politica-credenciais-pcs.md §3 escreve `detail = 'PC_INEXISTENTE'`
/// assim — divergência registrada para o card 4.3 corrigir na migração; até lá
/// o app não pode traduzir o erro como "não mapeado".
String? _codigoDoDetalhe(Object? detalhe) {
  final mapa = _mapaDoDetalhe(detalhe);
  final codigo = mapa?['codigo'];
  if (codigo is String && codigo.isNotEmpty) return codigo;

  if (detalhe is String) {
    final texto = detalhe.trim();
    if (RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(texto)) return texto;
  }
  return null;
}

/// As demais chaves do `DETAIL` viram valores das marcações `{...}` da
/// mensagem — é assim que `PARAMETRO_AUSENTE` diz *qual* chave falta.
Map<String, String> _valoresDoDetalhe(Object? detalhe) {
  final mapa = _mapaDoDetalhe(detalhe);
  if (mapa == null) return const {};
  return {
    for (final e in mapa.entries)
      if (e.key != 'codigo' && e.value != null) e.key: '${e.value}',
  };
}

Map<String, dynamic>? _mapaDoDetalhe(Object? detalhe) {
  if (detalhe is Map<String, dynamic>) return detalhe;
  if (detalhe is String) {
    try {
      final decodificado = jsonDecode(detalhe);
      if (decodificado is Map<String, dynamic>) return decodificado;
    } on FormatException {
      return null;
    }
  }
  return null;
}
