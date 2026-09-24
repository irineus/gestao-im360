import 'package:supabase_flutter/supabase_flutter.dart';

/// O "quem" dos históricos para qualquer perfil da unidade (card 9.2,74,
/// pendência 9.13(a)).
///
/// O embed `usuario:usuario_id(nome)` do PostgREST devolvia **nulo** — não
/// erro — para quem não tem `admin.ler`: a política de `usuario` só deixa ler a
/// própria linha. A secretaria via o histórico de status sem o autor, e o
/// monitor, no checklist de certificado, só o próprio nome.
///
/// `fn_usuarios_nomes()` devolve SÓ id e nome dos usuários da unidade de quem
/// chama (decisão de Irineu, 24/09/2026 — nada além disso); e-mail e perfis
/// continuam sob a política de `usuario`.
Future<Map<String, String>> nomesDaUnidade(SupabaseClient cliente) async {
  final linhas = await cliente.rpc<List<dynamic>>('fn_usuarios_nomes');
  return {
    for (final linha in linhas.cast<Map<String, dynamic>>())
      '${linha['id']}': '${linha['nome']}',
  };
}

/// Põe o nome de cada autor na linha, no MESMO formato do embed antigo
/// (`{'nome': …}` sob [chaveEmbed]) — os `deLinha` dos modelos não mudam.
/// Autor desconhecido (sem id, ou fora do mapa) fica nulo, e a tela omite o
/// "por …", como sempre fez.
Map<String, dynamic> comNomes(
  Map<String, dynamic> linha,
  Map<String, String> nomes, {
  required Map<String, String> colunaParaEmbed,
}) {
  final saida = Map<String, dynamic>.of(linha);
  colunaParaEmbed.forEach((coluna, chaveEmbed) {
    final nome = nomes['${linha[coluna]}'];
    saida[chaveEmbed] = linha[coluna] == null || nome == null
        ? null
        : {'nome': nome};
  });
  return saida;
}
