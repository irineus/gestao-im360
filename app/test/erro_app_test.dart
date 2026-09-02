import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/erros/catalogo_erros.dart';
import 'package:gestao_im360/erros/erro_app.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A tradução do erro do banco para a tela. O app trata pelo `codigo` do
/// `DETAIL`, nunca pelo texto da mensagem (card 2.2 §1.2).
void main() {
  test(
    'DETAIL em JSON: o código sai de dentro e a mensagem é a do catálogo',
    () {
      // Formato medido pelo card 3.5 contra o PostgREST:
      // {"code":"PT409","details":"{\"codigo\":\"EMAIL_IMUTAVEL\",…}"}
      final erro = traduzirErro(
        const PostgrestException(
          message: 'e-mail é imutável',
          code: 'PT409',
          details: '{"codigo":"EMAIL_IMUTAVEL","email":"a@b.c"}',
        ),
      );
      expect(erro.codigo, 'EMAIL_IMUTAVEL');
      expect(erro.mensagem, CatalogoErros.mensagens['EMAIL_IMUTAVEL']);
      expect(erro.traduzido, isTrue);
    },
  );

  test('as demais chaves do DETAIL preenchem as marcações da mensagem', () {
    final erro = traduzirErro(
      const PostgrestException(
        message: 'parâmetro ausente',
        code: 'PT422',
        details: '{"codigo":"PARAMETRO_AUSENTE","chave":"rep_prazo_dias"}',
      ),
    );
    expect(erro.mensagem, contains('rep_prazo_dias'));
    expect(erro.mensagem, isNot(contains('{chave}')));
  });

  test('DETAIL em texto puro com o código sozinho também é entendido', () {
    // docs/politica-credenciais-pcs.md §3 escreve `detail = PC_INEXISTENTE`,
    // fora da convenção JSON do card 2.2 §1.2. Divergência registrada para o
    // card 4.3 corrigir na migração; até lá o app não pode traduzir esse erro
    // como "não mapeado", que tem cara de problema de rede.
    final erro = traduzirErro(
      const PostgrestException(
        message: 'PC não encontrado',
        code: 'PT404',
        details: 'PC_INEXISTENTE',
      ),
    );
    expect(erro.codigo, 'PC_INEXISTENTE');
    expect(erro.traduzido, isTrue);
  });

  test('erro do banco sem DETAIL exibe o código técnico, não some', () {
    final erro = traduzirErro(
      const PostgrestException(message: 'algo', code: '42501'),
    );
    expect(erro.traduzido, isFalse);
    expect(erro.mensagem, contains('42501'));
  });

  test(
    'credencial inválida tem mensagem única, sem dizer qual campo errou',
    () {
      final erro = traduzirErro(
        AuthApiException(
          'Invalid login credentials',
          code: 'invalid_credentials',
        ),
      );
      expect(erro.mensagem, mensagemCredencialInvalida);
      expect(erro.mensagem.toLowerCase(), isNot(contains('senha incorreta')));
    },
  );

  test('erro de rede não vira "código nulo" na cara do usuário', () {
    final erro = traduzirErro(Exception('socket'));
    expect(erro.codigo, isNull);
    expect(erro.mensagem, contains('conexão'));
  });

  test('traduzir um ErroApp devolve ele mesmo', () {
    const original = ErroApp(mensagem: 'x', codigo: 'Y');
    expect(identical(traduzirErro(original), original), isTrue);
  });

  group('integridade (card 4.4)', () {
    // Os dois SQLSTATEs que uma tela de cadastro produz chegam SEM `codigo`
    // no DETAIL, porque quem os levanta é o Postgres e não uma função do
    // card 2.2. Sem tradução própria cairiam no fallback com o número na
    // cara do usuário — e virariam evento no Sentry a cada tentativa.
    test('23503 (em uso) tem mensagem própria e conta como traduzido', () {
      final erro = traduzirErro(
        const PostgrestException(
          message: 'violates foreign key constraint',
          code: '23503',
        ),
      );
      expect(erro.codigo, '23503');
      expect(erro.mensagem, mensagensIntegridade['23503']);
      expect(erro.traduzido, isTrue);
    });

    test('23505 (duplicado) idem', () {
      final erro = traduzirErro(
        const PostgrestException(message: 'duplicate key', code: '23505'),
      );
      expect(erro.mensagem, mensagensIntegridade['23505']);
      expect(erro.traduzido, isTrue);
    });

    test('um DETAIL com codigo vence o SQLSTATE — o catálogo continua sendo '
        'a primeira fonte', () {
      final erro = traduzirErro(
        const PostgrestException(
          message: 'x',
          code: '23505',
          details: '{"codigo":"TRILHA_JA_EXISTE"}',
        ),
      );
      expect(erro.codigo, 'TRILHA_JA_EXISTE');
      expect(erro.mensagem, CatalogoErros.mensagens['TRILHA_JA_EXISTE']);
    });

    test('ErroApp construído pelo app pode se declarar traduzido', () {
      const erro = ErroApp(mensagem: 'texto pronto', traduzido: true);
      expect(erro.traduzido, isTrue);
      const derivado = ErroApp(mensagem: 'x', codigo: 'SEM_PERMISSAO');
      expect(derivado.traduzido, isTrue);
      const fallback = ErroApp(mensagem: 'x', codigo: '42501');
      expect(fallback.traduzido, isFalse);
    });
  });
}
