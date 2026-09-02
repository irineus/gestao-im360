import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/config/ambiente.dart';
import 'package:gestao_im360/erros/erro_app.dart';
import 'package:gestao_im360/observabilidade/observabilidade.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthApiException;

/// Card 3.12. O que se testa aqui é a peneira, não o SDK.
///
/// Vazamento de PII para um terceiro é a falha mais cara deste card e a mais
/// silenciosa: nada quebra, nada aparece na tela, e o dado do aluno passa a
/// morar no Sentry sem que ninguém tenha decidido isso. Como as duas peneiras
/// são funções puras, dá para exercitá-las sem rede e sem DSN — que é a única
/// forma de a suíte ter opinião sobre elas.
void main() {
  group('limparUrl — o filtro do PostgREST é dado de aluno', () {
    test('corta a query string, que é onde o nome do aluno viaja', () {
      expect(
        limparUrl(
          'https://x.supabase.co/rest/v1/aluno?nome=ilike.*Maria*&select=id',
        ),
        'https://x.supabase.co/rest/v1/aluno',
      );
      expect(
        limparUrl('https://x.supabase.co/rest/v1/aluno?codigo_sgf=eq.3527'),
        'https://x.supabase.co/rest/v1/aluno',
      );
    });

    test('corta o fragmento, que é onde o Auth devolve o access_token', () {
      // Card 3.8: os links gerados pelo painel voltam como `#access_token=…`.
      expect(
        limparUrl('https://app.gestaoim360.com/#access_token=eyJhbGciOi'),
        'https://app.gestaoim360.com/',
      );
    });

    test('o caminho é preservado — é ele que serve para depurar', () {
      expect(
        limparUrl('https://x.supabase.co/rest/v1/aluno'),
        'https://x.supabase.co/rest/v1/aluno',
      );
      expect(limparUrl(null), isNull);
      expect(limparUrl(''), '');
    });
  });

  group('sanitizarBreadcrumb', () {
    test('a URL do breadcrumb de HTTP perde a query', () {
      final limpo = sanitizarBreadcrumb(
        Breadcrumb(
          category: 'http',
          data: {
            'url': 'https://x.supabase.co/rest/v1/aluno?nome=eq.Maria',
            'method': 'GET',
            'status_code': 200,
          },
        ),
      );
      expect(limpo!.data!['url'], 'https://x.supabase.co/rest/v1/aluno');
      // O que não identifica ninguém continua lá: sem método e status o
      // breadcrumb não serviria para nada.
      expect(limpo.data!['method'], 'GET');
      expect(limpo.data!['status_code'], 200);
    });

    test('http.query e http.fragment são removidos, não encurtados', () {
      // O SDK às vezes já entrega a URL partida. Encurtar o que está inteiro e
      // deixar passar o que veio separado seria uma limpeza que não limpa.
      final limpo = sanitizarBreadcrumb(
        Breadcrumb(
          category: 'http',
          data: {
            'url': 'https://x.supabase.co/rest/v1/aluno',
            'http.query': 'nome=eq.Maria',
            'http.fragment': 'access_token=eyJ',
          },
        ),
      );
      expect(limpo!.data!.containsKey('http.query'), isFalse);
      expect(limpo.data!.containsKey('http.fragment'), isFalse);
    });

    test('a mensagem com query é cortada', () {
      final limpo = sanitizarBreadcrumb(
        Breadcrumb(message: '/alunos?busca=Maria'),
      );
      expect(limpo!.message, '/alunos');
    });

    test('breadcrumb sem data atravessa inteiro', () {
      final limpo = sanitizarBreadcrumb(Breadcrumb(message: 'entrou'));
      expect(limpo!.message, 'entrou');
    });
  });

  group('sanitizarEvento', () {
    test('o request perde query, cookies, headers e corpo', () {
      final evento = SentryEvent(
        request: SentryRequest(
          url: 'https://x.supabase.co/rest/v1/aluno',
          method: 'POST',
          queryString: 'nome=eq.Maria',
          cookies: 'sb-access-token=eyJ',
          headers: {'Authorization': 'Bearer eyJ'},
          data: {'nome': 'Maria', 'codigo_sgf': '3527'},
        ),
      );

      final limpo = sanitizarEvento(evento)!;
      expect(limpo.request!.url, 'https://x.supabase.co/rest/v1/aluno');
      expect(limpo.request!.method, 'POST');
      expect(limpo.request!.queryString, isNull);
      expect(limpo.request!.cookies, isNull);
      expect(limpo.request!.headers, isEmpty);
      expect(limpo.request!.data, isNull);
    });

    test('a URL do request também é cortada', () {
      final limpo = sanitizarEvento(
        SentryEvent(
          request: SentryRequest(
            url: 'https://x.supabase.co/rest/v1/aluno?nome=eq.Maria',
          ),
        ),
      )!;
      expect(limpo.request!.url, 'https://x.supabase.co/rest/v1/aluno');
    });

    test('do usuário sobra só o id', () {
      final limpo = sanitizarEvento(
        SentryEvent(
          user: SentryUser(
            id: 'abc-123',
            email: 'secretaria@escola.test',
            name: 'Fulana',
            ipAddress: '191.0.2.7',
          ),
        ),
      )!;
      expect(limpo.user!.id, 'abc-123');
      expect(limpo.user!.email, isNull);
      expect(limpo.user!.name, isNull);
      expect(limpo.user!.ipAddress, isNull);
    });

    test('usuário sem id sai inteiro — sem id sobra só PII', () {
      final limpo = sanitizarEvento(
        SentryEvent(user: SentryUser(ipAddress: '191.0.2.7')),
      )!;
      expect(limpo.user, isNull);
    });

    test('evento sem request nem user atravessa', () {
      final evento = SentryEvent(logger: 'teste');
      expect(sanitizarEvento(evento)!.logger, 'teste');
    });
  });

  group('deveRelatar — o que é defeito e o que é o sistema funcionando', () {
    test('erro do catálogo NÃO vai: é resultado de regra de negócio', () {
      // Turma cheia é a turma enchendo. Mandar os 25 códigos do catálogo para
      // o Sentry gastaria a cota do free tier com o que já tem tela própria.
      expect(
        deveRelatar(
          const ErroApp(codigo: 'BLOCO_LOTADO', mensagem: 'Turma lotada.'),
        ),
        isFalse,
      );
    });

    test('erro de Auth NÃO vai: senha errada é operação normal', () {
      final erro = traduzirErro(
        const AuthApiException('Invalid login credentials', statusCode: '400'),
      );
      expect(deveRelatar(erro), isFalse);
    });

    test('o que o catálogo não conhece VAI — é a definição de imprevisto', () {
      expect(
        deveRelatar(
          const ErroApp(codigo: 'ALGO_NOVO_DA_MIGRACAO', mensagem: 'x'),
        ),
        isTrue,
      );
      // Erro de rede também: sem código, sem tradução, e persistente é notícia.
      expect(
        deveRelatar(traduzirErro(const SocketException('sem rota'))),
        isTrue,
      );
    });
  });

  group('o gancho de traduzirErro', () {
    tearDown(() => aoTraduzirErro = null);

    test('todo erro traduzido passa pelo gancho, sem a tela pedir', () {
      // É esta propriedade que faz uma tela nova da Fase 4 entrar coberta sem
      // que ninguém se lembre do Sentry.
      final vistos = <ErroApp>[];
      aoTraduzirErro = vistos.add;

      traduzirErro(const ErroApp(codigo: 'BLOCO_LOTADO', mensagem: 'x'));
      traduzirErro(const SocketException('sem rota'));

      expect(vistos, hasLength(2));
      expect(vistos.first.codigo, 'BLOCO_LOTADO');
    });

    test('sem gancho, traduzirErro devolve o mesmo de sempre', () {
      final erro = traduzirErro(const ErroApp(codigo: 'X', mensagem: 'y'));
      expect(erro.codigo, 'X');
    });
  });

  group('ambiente derivado do projeto Supabase', () {
    test('sem SUPABASE_URL o ambiente é local, e o Sentry fica desligado', () {
      // A suíte roda sem `--dart-define`, então este é o estado de fato aqui —
      // e é o que garante que nenhum teste mande evento para lugar nenhum.
      expect(Ambiente.ambiente, 'local');
      expect(observabilidadeLigada, isFalse);
    });
  });
}
