/// Observabilidade do app — Sentry (card 3.12).
///
/// Duas responsabilidades, e a segunda é a que dá trabalho:
///
///   1. **ligar**, e só quando há `SENTRY_DSN` (`iniciarObservabilidade`);
///   2. **não vazar dado de aluno** para um serviço de terceiro.
///
/// A segunda existe porque o caminho natural do SDK vaza sem avisar. O
/// `supabase_flutter` fala com o PostgREST, e no PostgREST **o filtro vai na
/// query string**: `?nome=ilike.*Maria*`, `?codigo_sgf=eq.3527`. Um breadcrumb
/// de HTTP com a URL inteira leva o nome do aluno junto — e o mesmo vale pelo
/// `request` do evento. Por isso toda URL é cortada no `?` antes de sair, nos
/// dois caminhos, e as funções que fazem isso são puras e testadas
/// (`app/test/observabilidade_test.dart`): é a única parte deste arquivo que
/// dá para exercitar sem rede.
///
/// ⚠️ A CSP de `web/_headers` precisa deixar passar o host de ingestão. Sem
/// isso o navegador bloqueia os envios **em silêncio** — o sintoma é um Sentry
/// que não recebe nada, que é indistinguível de "não houve erro". O
/// `deploy-web` confere as duas pontas antes de publicar (card 3.9).
library;

import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../config/ambiente.dart';
import '../erros/erro_app.dart';

/// Ligada só quando o build recebeu o DSN.
bool get observabilidadeLigada => Ambiente.sentryDsn.isNotEmpty;

/// Sobe o Sentry (quando há DSN) e roda o app dentro dele.
///
/// `appRunner` é o que captura erro não tratado: o SDK instala o
/// `FlutterError.onError` e a zona de erro em volta do `runApp`. Sem DSN, o app
/// roda igual e nada é enviado — `flutter run` e a suíte não falam com a rede.
Future<void> iniciarObservabilidade(FutureOr<void> Function() rodarApp) async {
  if (!observabilidadeLigada) {
    await rodarApp();
    return;
  }

  // Erro tratado não passa pelo `appRunner`: ele vira tela de erro e morre ali.
  // O gancho é o que o traz — o card 3.7 já deixou `ErroApp.original` guardado
  // esperando por este card.
  aoTraduzirErro = _relatarErroTratado;

  await SentryFlutter.init((opcoes) {
    opcoes.dsn = Ambiente.sentryDsn;
    opcoes.environment = Ambiente.ambiente;

    // --- o que NÃO sai daqui -------------------------------------------------
    // Os dois já são o default do SDK; ficam escritos porque um default que
    // muda numa atualização vira vazamento sem commit nenhum. A screenshot é o
    // caso extremo: uma tela de Alunos inteira, com nomes, dentro do Sentry.
    //
    // `attachViewHierarchy` fica de fora de propósito: o default também é
    // `false`, mas a opção é marcada como experimental no SDK e `flutter
    // analyze --fatal-infos` (card 3.9) reprova o uso — declarar o default de
    // uma API experimental custaria um `ignore` e não compraria proteção
    // nenhuma. Quem protege de verdade, aqui, é `beforeSend`.
    opcoes.sendDefaultPii = false;
    opcoes.attachScreenshot = false;

    // Este NÃO é default (`true` no SDK), e é o que mais importa desligar: o
    // breadcrumb de interação registra o RÓTULO do widget tocado, e no Gestão
    // IM360 o rótulo de um item de lista é o nome de um aluno. Tocar na ficha
    // da Maria mandaria "Maria ..." para o Sentry sem que nada no código
    // dissesse isso.
    opcoes.enableUserInteractionBreadcrumbs = false;

    // Sem tracing. A cota do free tier é o recurso escasso, e o que este card
    // quer é o erro que ninguém viu — não o desempenho, que ainda não tem
    // pergunta a responder. `tracesSampleRate` nulo já desliga a amostragem.
    opcoes.tracesSampleRate = null;

    // --- as duas peneiras ----------------------------------------------------
    opcoes.beforeBreadcrumb = (breadcrumb, hint) =>
        sanitizarBreadcrumb(breadcrumb);
    opcoes.beforeSend = (evento, hint) => sanitizarEvento(evento);
  }, appRunner: rodarApp);
}

/// Manda para o Sentry o erro que o app **não soube explicar**.
///
/// O filtro é [deveRelatar], e ele é o que impede a cota de virar ruído.
void _relatarErroTratado(ErroApp erro) {
  if (!deveRelatar(erro)) return;
  unawaited(
    Sentry.captureException(
      erro.original ?? erro,
      stackTrace: StackTrace.current,
      withScope: (escopo) async {
        escopo.level = SentryLevel.warning;
        await escopo.setTag('origem', 'erro_tratado');
        // O código, quando existe, é o que agrupa — nunca a mensagem, que é
        // texto de tela e muda sem aviso (card 2.2 §1.2).
        final codigo = erro.codigo;
        if (codigo != null) await escopo.setTag('codigo', codigo);
      },
    ),
  );
}

/// Vale a pena relatar?
///
/// **Sim** para o que o catálogo do card 2.7 §7.1 não conhece — a definição
/// operacional de "algo que ninguém previu".
///
/// **Não** em dois casos, os dois pelo mesmo motivo (evento previsto esgotando
/// a cota e ensinando a ignorar o painel, que é o desfecho de não ter painel):
///
///   * erro **traduzido**: os 25 códigos do catálogo são resultados de regra de
///     negócio, não defeitos. `BLOCO_LOTADO` é a turma cheia, e a turma encher
///     é o sistema funcionando;
///   * erro de **Auth**: senha errada é o evento mais frequente que existe num
///     sistema com senha, e não há nada a investigar nele. O catálogo não cobre
///     os códigos do GoTrue (pendência registrada para o card 4.7), então sem
///     esta cláusula eles passariam pela primeira.
bool deveRelatar(ErroApp erro) =>
    !erro.traduzido && erro.original is! AuthException;

/// Corta a URL no `?`, deixando esquema, host e caminho.
///
/// No PostgREST o **filtro** é a query string, e filtro deste sistema é dado de
/// aluno: `nome=ilike.*Maria*`, `codigo_sgf=eq.3527`, `email=eq....`. O caminho
/// (`/rest/v1/aluno`) é o que serve para depurar e não identifica ninguém.
///
/// Corta também o fragmento, que é onde o Auth devolve `access_token` nos links
/// gerados pelo painel (card 3.8) — um token de sessão inteiro numa URL.
String? limparUrl(String? url) {
  if (url == null || url.isEmpty) return url;
  final corte = url.indexOf(RegExp(r'[?#]'));
  return corte == -1 ? url : url.substring(0, corte);
}

/// Peneira do breadcrumb. Devolver `null` descarta.
Breadcrumb? sanitizarBreadcrumb(Breadcrumb? breadcrumb) {
  if (breadcrumb == null) return null;

  final dados = breadcrumb.data;
  if (dados != null) {
    final limpo = Map<String, dynamic>.of(dados);
    // `url` é do breadcrumb de HTTP; os outros dois são o que o SDK separa
    // quando a URL já vem partida — e é onde o filtro do PostgREST cai.
    if (limpo['url'] is String) {
      limpo['url'] = limparUrl(limpo['url'] as String);
    }
    limpo.remove('http.query');
    limpo.remove('http.fragment');
    breadcrumb.data = limpo;
  }

  // Breadcrumb de navegação carrega a rota; as rotas deste app não têm id de
  // aluno no caminho hoje, mas terão na Fase 4 (`/alunos/<id>`) — cortar a
  // query já agora evita ter de lembrar disso lá.
  final mensagem = breadcrumb.message;
  if (mensagem != null && mensagem.contains('?')) {
    breadcrumb.message = limparUrl(mensagem);
  }

  return breadcrumb;
}

/// Peneira do evento. Devolver `null` descarta.
SentryEvent? sanitizarEvento(SentryEvent evento) {
  final requisicao = evento.request;
  if (requisicao != null) {
    // Reconstruído em vez de `copyWith`: o `copyWith` do SDK usa `??`, então
    // passar `null` NÃO apaga campo nenhum — ele mantém o valor antigo. Zerar
    // com `copyWith` seria uma limpeza que não limpa, em silêncio.
    evento.request = SentryRequest(
      url: limparUrl(requisicao.url),
      method: requisicao.method,
    );
  }

  // Quem está logado é a equipe da escola, e o id basta para responder "só
  // aconteceu com uma pessoa ou com todas?". E-mail, nome e IP não respondem
  // pergunta nenhuma que o id não responda.
  //
  // Sem id não sobra nada de útil, só PII — e `SentryUser` tem um `assert` que
  // exige pelo menos um dos quatro campos: construí-lo vazio derrubaria o
  // próprio `beforeSend` em debug. Nesse caso o usuário sai inteiro.
  final usuario = evento.user;
  if (usuario != null) {
    final id = usuario.id;
    evento.user = id == null ? null : SentryUser(id: id);
  }

  return evento;
}
