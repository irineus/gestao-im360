import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/config/ambiente.dart';

/// Card 3.8. Três decisões do deploy que **falham em silêncio** quando alguém
/// as desfaz: ninguém vê exceção, ninguém vê log — só um link que leva ao lugar
/// errado ou uma tela em branco. Por isso viram asserção.
void main() {
  group('destino do link do Auth', () {
    test('a URL de redefinição não usa fragmento', () {
      // O fragmento é do Supabase: todo link gerado fora do fluxo PKCE do app
      // (convite e magic link pelo painel) volta como `<url>#access_token=…`.
      // Com a rota no fragmento, sobra `#sb` depois da limpeza e a pessoa cai
      // em "Esta tela não existe" já autenticada — medido em 01/09/2026.
      expect(Ambiente.urlRedefinicaoSenha, isNot(contains('#')));
      expect(
        Ambiente.urlRedefinicaoSenha,
        endsWith(Ambiente.rotaRedefinicaoSenha),
      );
    });
  });

  group('o que o Cloudflare Pages lê de web/', () {
    // O teste roda com o diretório do pacote como raiz.
    final web = Directory('web');

    test('existe _headers', () {
      expect(File('${web.path}/_headers').existsSync(), isTrue);
    });

    test('NÃO existe 404.html', () {
      // Sem um 404.html no topo, o Pages trata o projeto como single-page
      // application e devolve o index.html para qualquer caminho. Criar o
      // arquivo desliga isso e quebra todo link direto — /alunos passa a
      // responder 404 em vez de abrir o app.
      expect(File('${web.path}/404.html').existsSync(), isFalse);
    });

    test('NÃO existe _redirects com regra de SPA', () {
      // No Pages "os redirects são sempre seguidos, exista ou não um asset para
      // a requisição": a regra `/*  /index.html  200` que se copia da internet
      // engoliria main.dart.js e canvaskit.wasm, e o app abriria em branco.
      final arquivo = File('${web.path}/_redirects');
      if (!arquivo.existsSync()) return;
      final linhas = arquivo
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'));
      expect(
        linhas.where((l) => l.startsWith('/*')),
        isEmpty,
        reason: 'regra curinga em _redirects engole os assets do build',
      );
    });
  });
}
