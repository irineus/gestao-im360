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

  group('códigos do GoTrue (card 4.7, ajuste do card 3.8)', () {
    // `over_email_send_rate_limit` apareceu cru para o usuário nos testes do
    // card 3.8: o catálogo do 2.7 só cobre o DETAIL das funções do banco.
    test('rate limit de e-mail tem texto próprio e conta como traduzido', () {
      final erro = traduzirErro(
        AuthApiException(
          'email rate limit exceeded',
          statusCode: '429',
          code: 'over_email_send_rate_limit',
        ),
      );
      expect(erro.codigo, 'over_email_send_rate_limit');
      expect(erro.mensagem, mensagensAuth['over_email_send_rate_limit']);
      expect(erro.mensagem, contains('Espere alguns minutos'));
      expect(erro.traduzido, isTrue);
    });

    test('código do GoTrue que o app não conhece continua no fallback, com o '
        'código visível', () {
      final erro = traduzirErro(
        AuthApiException('?', statusCode: '400', code: 'algo_novo'),
      );
      expect(erro.traduzido, isFalse);
      expect(erro.mensagem, contains('algo_novo'));
    });

    test('credencial inválida também conta como traduzida', () {
      final erro = traduzirErro(
        AuthApiException('Invalid login', code: 'invalid_credentials'),
      );
      expect(erro.traduzido, isTrue);
    });
  });

  group('Edge Function (card 4.7)', () {
    // A função devolve o erro do banco COMO VEIO (acesso-autenticacao §3.2):
    // o `codigo` no corpo é o mesmo contrato do DETAIL.
    test('4xx com codigo no corpo cai no catálogo, com as marcações', () {
      final erro = traduzirErro(
        const FunctionException(
          status: 422,
          details: {'codigo': 'USUARIO_SEM_UNIDADE', 'unidades_ativas': 2},
        ),
      );
      expect(erro.codigo, 'USUARIO_SEM_UNIDADE');
      expect(erro.mensagem, CatalogoErros.mensagens['USUARIO_SEM_UNIDADE']);
      expect(erro.traduzido, isTrue);
    });

    test('SEM_PERMISSAO vindo da função é o mesmo texto da RLS', () {
      final erro = traduzirErro(
        const FunctionException(
          status: 403,
          details: {
            'codigo': 'SEM_PERMISSAO',
            'permissao': 'admin.gerir_usuarios',
          },
        ),
      );
      expect(erro.mensagem, CatalogoErros.mensagens['SEM_PERMISSAO']);
    });

    test('code do GoTrue repassado pela função usa a mesma tabela do Auth', () {
      final erro = traduzirErro(
        const FunctionException(
          status: 422,
          details: {'code': 'email_exists', 'mensagem': 'already registered'},
        ),
      );
      expect(erro.codigo, 'email_exists');
      expect(erro.mensagem, mensagensAuth['email_exists']);
      expect(erro.traduzido, isTrue);
    });

    test(
      'resposta sem codigo nem code: fallback com o status HTTP à vista',
      () {
        final erro = traduzirErro(
          const FunctionException(status: 500, details: 'Internal error'),
        );
        expect(erro.traduzido, isFalse);
        expect(erro.mensagem, contains('HTTP 500'));
      },
    );

    test('a função nem respondeu: erro de rede', () {
      final erro = traduzirErro(
        const FunctionsFetchException(details: 'connection refused'),
      );
      expect(erro.codigo, isNull);
      expect(erro.mensagem, contains('conexão'));
    });
  });
}
