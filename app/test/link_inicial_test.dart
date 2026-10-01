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

  group('card 9.2,80 — o que o link PRODUZIU, e a guarda da troca', () {
    setUp(LinkInicial.consumir);
    tearDown(LinkInicial.consumir);

    test('erro na URL: query (PKCE) ou fragmento (implícito)', () {
      expect(
        erroDaUrl(
          Uri.parse(
            'https://app/redefinir-senha?error=access_denied'
            '&error_code=otp_expired',
          ),
        ),
        'otp_expired',
      );
      expect(
        erroDaUrl(Uri.parse('https://app/#error=access_denied')),
        'access_denied',
      );
      expect(
        erroDaUrl(Uri.parse('https://app/#error_description=x')),
        codigoLinkInvalido,
      );
      expect(erroDaUrl(Uri.parse('https://app/#type=invite')), isNull);
    });

    test('retorno do Auth: token, código ou erro; nada mais', () {
      expect(ehRetornoDoAuth(Uri.parse('https://app/#access_token=a')), isTrue);
      expect(ehRetornoDoAuth(Uri.parse('https://app/?code=c')), isTrue);
      expect(ehRetornoDoAuth(Uri.parse('https://app/#error=x')), isTrue);
      expect(ehRetornoDoAuth(Uri.parse('https://app/alunos?aba=x')), isFalse);
      expect(ehRetornoDoAuth(Uri.parse('https://app/#sb')), isFalse);
    });

    test('link que valeu autoriza SÓ a sessão que ele criou', () async {
      LinkInicial.registrar(
        Uri.parse('https://app/#access_token=a&type=recovery'),
      );
      await LinkInicial.trocarPorSessao((_) async => 'u-link');
      expect(LinkInicial.pendente, isTrue);
      expect(LinkInicial.autorizaTroca('u-link'), isTrue);
      expect(LinkInicial.autorizaTroca('u-outra-pessoa'), isFalse);
      expect(LinkInicial.autorizaTroca(null), isFalse);
      LinkInicial.consumir();
      expect(LinkInicial.autorizaTroca('u-link'), isFalse);
      expect(LinkInicial.pendente, isFalse);
    });

    test('sem link, nada autoriza — nem a sessão de quem está logado', () {
      LinkInicial.registrar(Uri.parse('https://app/redefinir-senha'));
      expect(LinkInicial.pendente, isFalse);
      expect(LinkInicial.autorizaTroca('u-qualquer'), isFalse);
    });

    test(
      'magic link (type que não é de senha) cria sessão e não autoriza',
      () async {
        LinkInicial.registrar(
          Uri.parse('https://app/#access_token=a&type=magiclink'),
        );
        await LinkInicial.trocarPorSessao((_) async => 'u-link');
        expect(LinkInicial.pendente, isFalse);
        expect(LinkInicial.autorizaTroca('u-link'), isFalse);
      },
    );

    test(
      'URL com erro: a troca NEM é tentada, e o link fica pendente',
      () async {
        LinkInicial.registrar(
          Uri.parse('https://app/#error=access_denied&error_code=otp_expired'),
        );
        var chamadas = 0;
        await LinkInicial.trocarPorSessao((_) async {
          chamadas++;
          return 'u-x';
        });
        expect(chamadas, 0);
        expect(LinkInicial.erro, 'otp_expired');
        expect(LinkInicial.pendente, isTrue);
        expect(LinkInicial.autorizaTroca('u-x'), isFalse);
      },
    );

    test('troca que falha: ?code= é link de outro navegador; o resto leva o '
        'código do servidor, ou link_invalido', () async {
      LinkInicial.registrar(Uri.parse('https://app/redefinir-senha?code=c'));
      await LinkInicial.trocarPorSessao(
        (_) async => throw StateError('sem verificador'),
      );
      expect(LinkInicial.erro, codigoLinkOutroNavegador);

      LinkInicial.registrar(
        Uri.parse('https://app/#access_token=a&type=recovery'),
      );
      await LinkInicial.trocarPorSessao(
        (_) async => throw StateError('403'),
        codigoDoErro: (_) => 'bad_jwt',
      );
      expect(LinkInicial.erro, 'bad_jwt');
      expect(LinkInicial.usuarioId, isNull);

      LinkInicial.registrar(
        Uri.parse('https://app/#access_token=a&type=recovery'),
      );
      await LinkInicial.trocarPorSessao((_) async => throw StateError('x'));
      expect(LinkInicial.erro, codigoLinkInvalido);
    });
  });
}
