import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/config/link_inicial.dart';

/// O reconhecimento do link de convite (card 4.7): é feito ANTES de o
/// supabase_flutter limpar a URL, e é o único momento em que o app sabe que a
/// pessoa chegou sem senha.
void main() {
  test('convite pelo painel volta no fragmento, como o card 3.8 mediu', () {
    final uri = Uri.parse(
      'https://homolog.gestaoim360.com/#access_token=abc&expires_in=3600'
      '&refresh_token=xyz&token_type=bearer&type=invite',
    );
    expect(tipoDoLink(uri), TipoLinkInicial.convite);
  });

  test('recuperação de senha e tipos desconhecidos', () {
    expect(
      tipoDoLink(Uri.parse('https://app/redefinir-senha#type=recovery&x=1')),
      TipoLinkInicial.recuperacao,
    );
    expect(
      tipoDoLink(Uri.parse('https://app/?type=magiclink')),
      TipoLinkInicial.outro,
    );
  });

  test(
    'sem type — abertura normal, deep-link, fragmento vazio ou inválido',
    () {
      expect(tipoDoLink(Uri.parse('https://app/')), TipoLinkInicial.nenhum);
      expect(
        tipoDoLink(Uri.parse('https://app/alunos')),
        TipoLinkInicial.nenhum,
      );
      expect(tipoDoLink(Uri.parse('https://app/#sb')), TipoLinkInicial.nenhum);
      expect(
        tipoDoLink(Uri.parse('https://app/#%E0%A4%A')),
        TipoLinkInicial.nenhum,
      );
    },
  );

  test('registrar e consumir', () {
    LinkInicial.registrar(Uri.parse('https://app/#type=invite'));
    expect(LinkInicial.convitePendente, isTrue);
    LinkInicial.consumir();
    expect(LinkInicial.convitePendente, isFalse);
    expect(LinkInicial.tipo, TipoLinkInicial.nenhum);
  });
}
