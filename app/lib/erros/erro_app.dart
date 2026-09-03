import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'catalogo_erros.dart';

/// Erro já traduzido para a tela: o `codigo` estável (quando existe) e o texto
/// em português do catálogo do card 2.7 §7.1.
///
/// A tela nunca lê `mensagem` do banco: lê daqui.
class ErroApp implements Exception {
  const ErroApp({
    required this.mensagem,
    this.codigo,
    this.original,
    bool? traduzido,
  }) : traduzidoDeclarado = traduzido;

  /// Código estável do `DETAIL` (card 2.2 §1.2), quando o erro veio de uma
  /// regra de negócio. Nulo em erro de rede, de Auth ou inesperado.
  final String? codigo;

  /// Texto pronto para exibição.
  final String mensagem;

  /// O erro original, para o Sentry (card 3.12). Nunca vai para a tela.
  final Object? original;

  /// Declarado por quem construiu o erro já com texto pronto (card 4.4);
  /// nulo = deriva do catálogo.
  final bool? traduzidoDeclarado;

  /// Verdadeiro quando o app tem tradução própria — o oposto do fallback, que
  /// a `EstadoErro` usa para decidir se mostra o código técnico em apoio e que
  /// o Sentry usa para decidir se o erro merece evento (card 3.12).
  bool get traduzido => traduzidoDeclarado ?? CatalogoErros.mapeado(codigo);

  @override
  String toString() => 'ErroApp(${codigo ?? '-'}): $mensagem';
}

/// Mensagem única de credencial inválida: nunca dizer qual campo errou
/// (docs/wireframes.md §4).
const mensagemCredencialInvalida = 'E-mail ou senha inválidos.';

const _mensagemRede =
    'Não foi possível falar com o servidor. Verifique a conexão e tente de novo.';

/// Os dois SQLSTATEs de **integridade** que uma tela de cadastro produz, e que
/// são resposta de regra (a constraint é a regra, card 2.2 §2.1), não defeito:
/// `23503` (chave estrangeira — apagar o que está em uso) e `23505` (chave
/// única — código ou nome repetido). Chegam sem `codigo` no `DETAIL`, porque
/// quem os levanta é o Postgres, não uma função do card 2.2.
///
/// Sem esta tabela cairiam no fallback com o número na cara do usuário e
/// virariam evento no Sentry a cada tentativa (card 3.12). Fica **fora** do
/// catálogo do card 2.7 §7.1 de propósito: aquele é o contrato dos códigos do
/// `DETAIL`, conferido pelo C12 contra as funções do banco, e um SQLSTATE não é
/// código de função nenhuma.
const mensagensIntegridade = <String, String>{
  '23503':
      'Este cadastro está em uso e não pode ser excluído. Marque-o como '
      'inativo em vez de excluir.',
  '23505': 'Já existe um cadastro com este código ou nome.',
};

/// Mensagem do caso em que a RLS devolve **zero linhas** numa exclusão. Sem
/// política de `delete` o Postgres não levanta erro — apaga nada e diz sucesso
/// (card 3.4 (d)); dizer "excluído" aqui seria mentir com cara de confirmação.
/// Nasceu no repositório do catálogo (card 4.4) e mora aqui desde que o da
/// infraestrutura (card 4.5) precisou da mesma frase.
const mensagemNadaExcluido =
    'Nada foi excluído: o registro não existe mais ou você não tem permissão '
    'para excluí-lo.';

/// Gancho de observabilidade (card 3.12). `main` o aponta para o Sentry; nos
/// testes e num build sem `SENTRY_DSN` ele continua nulo e nada é enviado.
///
/// Ele mora AQUI, e não nas cinco telas que hoje chamam [traduzirErro], por uma
/// razão que este projeto já pagou duas vezes: **regra que depende de alguém
/// lembrar não serve**. Com o gancho no ponto de tradução, toda tela futura
/// entra coberta sem precisar saber que o Sentry existe; com uma chamada por
/// tela, a primeira tela da Fase 4 já nasceria de fora — e a falha seria
/// silenciosa, porque o Sentry simplesmente não receberia nada.
void Function(ErroApp erro)? aoTraduzirErro;

/// Traduz qualquer exceção do Supabase para [ErroApp].
///
/// A ordem importa: um `PostgrestException` de regra de negócio carrega o
/// `codigo` no `details`; sem ele, cai no texto genérico que sempre mostra o
/// código técnico.
ErroApp traduzirErro(Object erro) {
  final traduzido = _traduzir(erro);
  aoTraduzirErro?.call(traduzido);
  return traduzido;
}

ErroApp _traduzir(Object erro) {
  if (erro is ErroApp) return erro;

  if (erro is PostgrestException) {
    final codigo = _codigoDoDetalhe(erro.details);
    final integridade = codigo == null ? mensagensIntegridade[erro.code] : null;
    if (integridade != null) {
      return ErroApp(
        codigo: erro.code,
        mensagem: integridade,
        original: erro,
        traduzido: true,
      );
    }
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
