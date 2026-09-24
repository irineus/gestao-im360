import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Card 5.5,5 — portões nascidos da revisão do card 5.11.
///
/// As duas classes abaixo têm a mesma natureza: **passam por todo teste e por
/// todo CI**, porque `flutter test` não desenha glifo e `analyze` não lê
/// português. Só aparecem quando alguém abre a tela — e, na cadeia de execução
/// headless, ninguém abre. Foram achadas por uma revisão manual depois de
/// quatro telas prontas; viram asserção para não custar a quinta.
void main() {
  final literaisPorArquivo = <String, List<_Literal>>{
    for (final f in _arquivosDart(Directory('lib')))
      f.path.replaceAll(r'\', '/'): _literais(f.readAsStringSync()),
  };

  group('glifos que a fonte do app não tem', () {
    // O app empacota **só** Inter e Roboto. Faltando o glifo, o Flutter web
    // tenta baixar Noto Color Emoji de `fonts.gstatic.com` — e a CSP de
    // `web/_headers` bloqueia, de propósito (cards 3.8/3.9: não depender de
    // terceiro). O usuário vê uma CAIXA VAZIA, e o console repete três
    // tentativas até `permanently unavailable`. Medido na homologação em
    // 04/09/2026: `'Nenhuma pendência aberta. 🎉'` e três `'⚠ sem …'`.
    //
    // Emoji, símbolos diversos (inclui ⚠ U+26A0), setas decorativas e afins.
    // Acentuação, `—`, `·`, `…` e `≥` ficam de fora da proibição: Inter tem.
    final proibidos = RegExp(r'[☀-➿⬀-⯿️]|[\uD83C-\uDBFF][\uDC00-\uDFFF]');

    test('nenhum literal de string em lib/ usa glifo fora de Inter/Roboto', () {
      final achados = <String>[];
      literaisPorArquivo.forEach((arquivo, literais) {
        for (final l in literais) {
          if (proibidos.hasMatch(l.texto)) {
            achados.add('$arquivo:${l.linha}  "${l.texto}"');
          }
        }
      });

      expect(
        achados,
        isEmpty,
        reason:
            'Glifo que Inter/Roboto não têm vira caixa vazia na tela, e a CSP '
            'impede o download da fonte de emoji. Use um Icon do Material em '
            'vez do caractere.\n${achados.join('\n')}',
      );
    });
  });

  test('interpolação com aspas dentro não fecha o literal (card 9.2,72)', () {
    // O `_csv` da importação: sem pular o `${…}`, a aspa de dentro fechava o
    // literal cedo e o COMENTÁRIO da linha de baixo virava texto de tela.
    final literais = _literais(
      "final x = '\"\${valor.replaceAll('\"', '\"\"')}\"';\n"
      '// card 9.2,65 — comentário, não texto\n',
    );
    expect(literais, hasLength(1));
    expect(literais.single.texto, '"\$"');
  });

  group('jargão interno em texto de usuário', () {
    // A secretaria não sabe o que é um card do board nem o que é
    // `turmas.ler`. Referência a card envelhece junto com o board; código de
    // permissão entre crases é vocabulário de quem escreveu o sistema, não de
    // quem o usa. Cinco textos assim chegaram às telas da fase 05.
    // ⚠️ `card \d` deixava passar a INTERPOLAÇÃO: `'$nome — aba do card
    // $card.'` da ficha do aluno rendia "Certificado — aba do card 8.6." na
    // tela e nada no portão (item C1). Agora `card` seguido de dígito **ou**
    // de interpolação reprova.
    final referenciaACard = RegExp(r'card (\d|\$)', caseSensitive: false);
    // Card 9.2,72: "Fase N" chegava à tela ("A trilha do aluno nasce do combo
    // na matrícula (Fase 6).") e o portão não via — é o mesmo vocabulário de
    // board que a referência a card.
    final referenciaAFase = RegExp(r'\bFase \d');
    final codigoDePermissao = RegExp(r'`[a-z_]+\.[a-z_]+`');

    // Card 9.2,72: `lib/` inteiro, e não só `lib/telas/` — texto de tela mora
    // também em lib/widgets, lib/erros e nos arquivos de domínio
    // (`rotuloSituacao` em lib/trilha, as mensagens do catálogo de erros).
    test('nenhum literal em lib/ cita card do board, fase ou permissão', () {
      final achados = <String>[];
      literaisPorArquivo.forEach((arquivo, literais) {
        for (final l in literais) {
          final citaCard = referenciaACard.hasMatch(l.texto);
          final citaFase = referenciaAFase.hasMatch(l.texto);
          final citaPermissao = codigoDePermissao.hasMatch(l.texto);
          if (citaCard || citaFase || citaPermissao) {
            achados.add('$arquivo:${l.linha}  "${l.texto}"');
          }
        }
      });

      expect(
        achados,
        isEmpty,
        reason:
            'Texto de tela fala a língua de quem usa. Card do board e código '
            'de permissão ficam no comentário, não na tela.\n'
            '${achados.join('\n')}',
      );
    });
  });
}

class _Literal {
  const _Literal(this.texto, this.linha);
  final String texto;
  final int linha;
}

List<File> _arquivosDart(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// Extrai os literais de string do código, **ignorando comentários**.
///
/// A distinção é o ponto do teste, não um detalhe de implementação: este
/// projeto usa `⚠️` em comentário o tempo todo, de propósito, e é assim que
/// deve continuar. O que não pode carregar o glifo é o texto que chega à tela.
/// Um `grep` no arquivo inteiro reprovaria o repositório inteiro e o teste
/// seria desligado na primeira semana.
List<_Literal> _literais(String fonte) {
  final saida = <_Literal>[];
  var i = 0;
  var linha = 1;
  final n = fonte.length;

  void avancar() {
    if (fonte[i] == '\n') linha++;
    i++;
  }

  while (i < n) {
    final c = fonte[i];

    if (c == '/' && i + 1 < n && fonte[i + 1] == '/') {
      while (i < n && fonte[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < n && fonte[i + 1] == '*') {
      i += 2;
      while (i + 1 < n && !(fonte[i] == '*' && fonte[i + 1] == '/')) {
        avancar();
      }
      i += 2;
      continue;
    }
    if (c == "'" || c == '"') {
      final aspa = c;
      final linhaInicio = linha;
      final buffer = StringBuffer();
      avancar();
      while (i < n && fonte[i] != aspa) {
        if (fonte[i] == r'\' && i + 1 < n) {
          buffer.write(fonte[i + 1]);
          avancar();
          avancar();
          continue;
        }
        // Card 9.2,72: interpolação `${…}` pode conter ASPAS — o `_csv` da
        // importação tem `'"${valor.replaceAll('"', '""')}"'`. Sem pular o
        // bloco inteiro, a aspa de dentro fechava o literal cedo e o resto do
        // arquivo virava "texto" (um comentário com "card 9.2,65" reprovou
        // assim). O bloco entra no buffer como `$`, que é o que a regra de
        // referência a card procura.
        if (fonte[i] == r'$' && i + 1 < n && fonte[i + 1] == '{') {
          buffer.write(r'$');
          avancar();
          avancar();
          var profundidade = 1;
          while (i < n && profundidade > 0) {
            final d = fonte[i];
            if (d == "'" || d == '"') {
              final interna = d;
              avancar();
              while (i < n && fonte[i] != interna) {
                if (fonte[i] == r'\' && i + 1 < n) avancar();
                avancar();
              }
              if (i < n) avancar();
              continue;
            }
            if (d == '{') profundidade++;
            if (d == '}') profundidade--;
            avancar();
          }
          continue;
        }
        buffer.write(fonte[i]);
        avancar();
      }
      if (i < n) avancar();
      saida.add(_Literal(buffer.toString(), linhaInicio));
      continue;
    }
    avancar();
  }
  return saida;
}
