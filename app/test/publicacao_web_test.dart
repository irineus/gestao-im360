import 'dart:convert';
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

    // Card 9.2,63: a abertura não é mais uma página branca muda.
    test(
      'index.html diz a língua, a cor da barra e mostra que está abrindo',
      () {
        final html = File('${web.path}/index.html').readAsStringSync();
        expect(html, contains('<html lang="pt-BR">'));
        expect(html, contains('<meta name="theme-color" content="#171C26">'));
        expect(html, contains('id="abrindo"'));
        // O indicador tem de sumir SOZINHO quando o Flutter sobe, e sem script
        // inline — a CSP (`script-src 'self'`) o bloquearia.
        expect(html, contains('body:has(flutter-view) #abrindo'));
        expect(
          RegExp(r'<script(?![^>]*\ssrc=)').hasMatch(html),
          isFalse,
          reason: 'script inline seria bloqueado pela CSP',
        );
      },
    );

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

    test('a CSP deixa passar a ingestão do Sentry', () {
      // Card 3.12. Host fora do `connect-src` é envio bloqueado pelo navegador
      // EM SILÊNCIO: nenhuma exceção, nenhuma tela diferente — só um painel do
      // Sentry que não recebe nada, e "não recebeu nada" é indistinguível de
      // "não houve erro". O erro que a asserção pega é o provável: alguém
      // enxuga a CSP num card futuro e a observabilidade morre sem barulho.
      //
      // O `deploy-web` faz a outra metade, que este teste não alcança: extrai
      // o host do `SENTRY_DSN` de verdade e confere que esta linha o cobre.
      final csp = File('${web.path}/_headers')
          .readAsLinesSync()
          .firstWhere((l) => l.contains('Content-Security-Policy:'));
      final connectSrc = csp
          .split(';')
          .firstWhere((d) => d.trim().startsWith('connect-src'));
      expect(connectSrc, contains('ingest.us.sentry.io'));
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

  // Card 10.1 (24/09/2026): o PWA instalável. O manifest é lido pelo navegador
  // na instalação e nunca mais — erro aqui não aparece em tela nenhuma, aparece
  // como app que não se oferece para instalar, que abre de lado, ou que vira
  // "outro app" (id novo) depois de uma mudança de start_url.
  group('manifest do PWA', () {
    final manifest = jsonDecode(
      File('web/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    test('identidade estável: id, escopo e início na raiz', () {
      // `id` explícito: sem ele o navegador deriva a identidade do start_url,
      // e mudar o start_url um dia faria o app instalado virar outro app.
      expect(manifest['id'], '/');
      expect(manifest['start_url'], '/');
      expect(manifest['scope'], '/');
      expect(manifest['display'], 'standalone');
    });

    test('pt-BR, nome e orientação livre', () {
      expect(manifest['lang'], 'pt-BR');
      expect(manifest['name'], 'Gestão IM360');
      expect((manifest['short_name'] as String).length, lessThanOrEqualTo(12));
      // A secretaria usa o desktop deitado, o monitor o celular em pé; travar
      // em `portrait-primary` (o padrão do template) deitava o tablet de lado.
      expect(manifest['orientation'], 'any');
    });

    test('cores da identidade visual, e a barra igual à do index.html', () {
      // grafite-900, o fundo do símbolo (docs/identidade-visual.md).
      expect(manifest['theme_color'], '#171C26');
      expect(manifest['background_color'], '#171C26');
      final index = File('web/index.html').readAsStringSync();
      expect(
        index,
        contains(
          '<meta name="theme-color" content="${manifest['theme_color']}">',
        ),
        reason: 'o meta do 9.2,63 e o manifest têm de dizer a mesma cor',
      );
      expect(index, contains('<html lang="pt-BR">'));
    });

    test(
      'ícones 192 e 512, comuns e maskable, existem e têm o tamanho dito',
      () {
        final icones = (manifest['icons'] as List).cast<Map<String, dynamic>>();
        for (final proposito in [null, 'maskable']) {
          final tamanhos = icones
              .where((i) => i['purpose'] == proposito)
              .map((i) => i['sizes'])
              .toSet();
          expect(
            tamanhos,
            containsAll(['192x192', '512x512']),
            reason: '$proposito',
          );
        }
        for (final icone in icones) {
          final bytes = File('web/${icone['src']}').readAsBytesSync();
          // PNG: largura e altura nos bytes 16..23, big-endian.
          int palavra(int i) =>
              (bytes[i] << 24) |
              (bytes[i + 1] << 16) |
              (bytes[i + 2] << 8) |
              bytes[i + 3];
          expect(
            '${palavra(16)}x${palavra(20)}',
            icone['sizes'],
            reason: '${icone['src']}',
          );
          expect(icone['type'], 'image/png');
        }
      },
    );
  });
}
