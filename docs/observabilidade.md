# Observabilidade — Sentry e os logs do Supabase (card 3.12)

**Fonte da observabilidade.** O que o sistema sabe sobre os próprios defeitos, onde isso mora e o
que deliberadamente **não** é enviado.

Ligado em 02/09/2026, fechando o último card da Fase 3.

---

## 1. O que se quer saber, e por que não bastava o que já existia

Antes deste card, um erro no app terminava numa tela de erro e **acabava ali**. O card 2.7 fechou o
catálogo de mensagens e o 3.7 fez cada modo de falha ter a sua tela — as duas coisas cuidam de quem
está na frente do computador, e nenhuma das duas conta a ninguém que aconteceu. Numa escola com uma
secretaria, um pedagógico e um monitor, o caminho do defeito até quem pode corrigi-lo é alguém se
lembrar de avisar.

Os três observadores do projeto cobrem coisas diferentes, e é útil dizer qual cobre o quê:

| Observador | O que enxerga | Cadência | Card |
|---|---|---|---|
| Vigia (Worker) | os dois Supabase estão de pé; o backup está saindo | diária, 06:00 | 3.10 / 3.12 |
| Backup semanal | produção pode ser restaurada | domingo, 06:30 | 3.11 |
| **Sentry** | **o que quebrou na frente de uma pessoa** | tempo real | **3.12** |

O Sentry é o único que fala do **uso**. Os outros dois respondem "a infraestrutura está viva?"; este
responde "alguém tentou fazer o trabalho e não conseguiu?".

---

## 2. Onde vive

| Peça | Arquivo |
|---|---|
| Inicialização, peneiras e filtro | `app/lib/observabilidade/observabilidade.dart` |
| Gancho que captura o erro tratado | `app/lib/erros/erro_app.dart` (`aoTraduzirErro`) |
| DSN e rótulo do ambiente | `app/lib/config/ambiente.dart` |
| `connect-src` da CSP | `app/web/_headers` |
| Injeção do DSN e conferência da CSP | `.github/workflows/deploy-web.yml` |
| Testes das peneiras e do filtro | `app/test/observabilidade_test.dart` |

Projeto no Sentry: **`irineu-pinheiro/gestao-im360`** (região US), criado em 02/09/2026. **Um projeto
para os dois ambientes**, separados por `environment` (`homologacao` / `producao`): o free tier tem
cota única de eventos, e dois projetos duplicariam regra de alerta sem separar nada que o filtro de
environment não separe.

---

## 3. Sem DSN, não inicializa — e isso é o contrato

`SENTRY_DSN` entra por `--dart-define`, como os outros três valores de ambiente (`app/README.md`).
Sem ele, `iniciarObservabilidade` roda o app e mais nada: `flutter run`, `flutter test` e um build de
emergência não falam com terceiro nenhum.

`SENTRY_DSN` é o **único** valor de configuração que o `deploy-web` trata como opcional: ele **avisa**
em vez de reprovar. A diferença é deliberada — build sem Supabase é um build quebrado (o card 3.8
mediu: ele sobe numa tela dizendo o que falta, e seria publicado assim mesmo); build sem Sentry é um
build pior, que funciona. O que **não** pode acontecer é a ausência passar calada, e é por isso que
existe o `::warning` no log e a linha no resumo do job.

O DSN é público por desenho, como a chave anônima do Supabase: ele vai no bundle que qualquer
visitante baixa, e o que autoriza é **escrever** evento no projeto — nunca ler. Fica em secret pelo
mesmo motivo prático do card 3.9: rotacionar não pode exigir um commit.

---

## 4. A CSP, e a falha silenciosa que este card quase repetiu

⚠️ **Host de ingestão fora do `connect-src` é envio bloqueado pelo navegador em silêncio.** Sem
exceção, sem log, sem nada diferente na tela: o painel do Sentry simplesmente não recebe nada — e
"não recebeu nada" é indistinguível de "não houve erro", que é exatamente o que se quer acreditar. É
a mesma família de falha calada que este projeto já catalogou em RLS que reduz linhas, em view sem
`security_invoker`, em Redirect URL recusada e em `--exclude` com chave desconhecida. A diferença é
que esta apaga junto o que a denunciaria.

Por isso o host entrou no **mesmo commit** que ligou o SDK, e por isso há **duas** asserções, uma de
cada lado:

* `app/test/publicacao_web_test.dart` exige que o `connect-src` cite `ingest.us.sentry.io` — pega
  quem enxugar a CSP num card futuro;
* o passo **"A CSP deixa passar a ingestão do Sentry"** do `deploy-web` extrai o host do `SENTRY_DSN`
  de verdade e reprova o build quando o `connect-src` não o cobre. É a metade que o teste Dart não
  alcança, porque ele não sabe qual é o DSN.

O curinga (`https://*.ingest.us.sentry.io`) é de subdomínio e é deliberado: toda ingestão da
organização na região dos EUA é `o<id>.ingest.us.sentry.io`, e o `<id>` muda se o projeto for
recriado. Fixar o host exato compraria uma precisão que ninguém confere e venderia a falha silenciosa
de volta. O que o curinga **não** cobre — outra região (`.de.sentry.io`), Sentry próprio — é
justamente o que o passo do `deploy-web` pega, e os dois casos foram exercitados.

---

## 5. O que NÃO sai daqui

Esta é a parte que dá trabalho, porque **o caminho natural do SDK vaza sem avisar**.

O `supabase_flutter` fala com o PostgREST, e no PostgREST **o filtro vai na query string**:
`?nome=ilike.*Maria*`, `?codigo_sgf=eq.3527`. Um breadcrumb de HTTP com a URL inteira leva o nome do
aluno junto, e o mesmo vale pelo `request` do evento. Nada nisso é erro de programação — é o
comportamento correto do SDK, aplicado a um sistema cujos filtros são dados de menores de idade.

| Medida | O que evita |
|---|---|
| `limparUrl` corta no `?` e no `#` | filtro do PostgREST (nome, código SGF, e-mail); e o `access_token` que o Auth devolve no fragmento (card 3.8) |
| `beforeBreadcrumb` limpa `url`, remove `http.query` e `http.fragment` | a mesma coisa, pelo caminho do breadcrumb — inclusive quando o SDK já entrega a URL partida |
| `beforeSend` reconstrói o `request` só com `url` e `method` | query, cookies, cabeçalhos (`Authorization`!) e corpo da requisição |
| `beforeSend` reduz o usuário ao `id` | e-mail, nome e IP de quem opera |
| `enableUserInteractionBreadcrumbs = false` | o **rótulo do widget tocado** — e o rótulo de um item de lista aqui é o nome de um aluno |
| `sendDefaultPii = false`, `attachScreenshot = false` | o caso extremo: a tela de Alunos inteira, com nomes, dentro do Sentry |

Três observações que valem para quem mexer nisso depois:

1. **`enableUserInteractionBreadcrumbs` é o único que não era default.** Os outros dois ficam escritos
   mesmo sendo o default do SDK, porque um default que muda numa atualização vira vazamento sem
   commit nenhum.
2. **O ****`copyWith`**** do SDK não serve para limpar.** Ele usa `??`, então passar `null` mantém o valor
   antigo — uma limpeza que não limpa, em silêncio. Por isso o `request` é **reconstruído**.
3. **`SentryUser`**** tem um ****`assert`**** exigindo ao menos um campo.** Reduzir ao `id` quando não há `id`
   derrubaria o próprio `beforeSend` em debug; nesse caso o usuário sai inteiro, que é o certo — sem
   `id` não sobra nada de útil, só PII.

As peneiras são **funções puras** e é isso que permite exercitá-las sem rede e sem DSN
(`app/test/observabilidade_test.dart`). Vazamento de PII é a falha mais cara deste card e a mais
silenciosa: nada quebra, nada aparece na tela, e o dado do aluno passa a morar num terceiro sem que
ninguém tenha decidido isso.

---

## 6. O que vale a pena relatar

O gancho `aoTraduzirErro` mora em `traduzirErro`, e não nas cinco telas que a chamam. A razão é uma
que este projeto já pagou duas vezes: **regra que depende de alguém lembrar não serve**. Com o gancho
no ponto de tradução, toda tela da Fase 4 em diante entra coberta sem precisar saber que o Sentry
existe; com uma chamada por tela, a primeira tela nova já nasceria de fora — e a falha seria
silenciosa, porque o Sentry simplesmente não receberia nada.

Passando o gancho, `deveRelatar` decide. Vai para o Sentry **o que o app não soube explicar**:

```
!erro.traduzido && erro.original is! AuthException
```

* **Erro do catálogo não vai.** Os 25 códigos do card 2.7 §7.1 são resultados de regra de negócio, não
  defeitos: `BLOCO_LOTADO` é a turma cheia, e a turma encher é o sistema funcionando.
* **Erro de Auth não vai.** Senha errada é o evento mais frequente que existe num sistema com senha, e
  não há o que investigar nele. O catálogo não cobre os códigos do GoTrue (pendência do card 4.7), e
  sem esta cláusula eles passariam pela primeira.
* **O resto vai**, inclusive erro de rede — sem código e sem tradução, e persistente é notícia.

O evento é agrupado pelo **código**, nunca pela mensagem: mensagem é texto de tela e muda sem aviso
(card 2.2 §1.2). Erro não tratado — o que nem chega a `traduzirErro` — é capturado pelo `appRunner`,
que instala o `FlutterError.onError` e a zona de erro em volta do `runApp`.

⚠️ **Se a cota apertar**, o ajuste é o *rate limit* do próprio DSN, no painel do Sentry, e não
apertar o filtro no código — o filtro decide o que **merece** investigação; o rate limit decide
quanto cabe no mês. Free tier: 5.000 erros/mês.

Sem tracing (`tracesSampleRate` nulo). O que este card quer é o erro que ninguém viu, não o
desempenho — que ainda não tem pergunta a responder e consumiria a mesma cota.

---

## 7. O rótulo do ambiente, e um achado que custou uma verificação

`APP_AMBIENTE` (`homologacao` / `producao`) vira o `environment` do Sentry. É um `--dart-define`
próprio, e no `deploy-web.yml` sai da **mesma expressão** sobre `github.ref_name` que `SUPABASE_URL` e
`APP_URL_BASE` — a fonte única é a branch. Errado, ele manda investigar produção por causa de um erro
de homologação.

⚠️ **Ele foi derivado do ****`SUPABASE_URL`**** e a derivação foi desfeita (02/09/2026, medido).**
Parecia melhor: um define a menos para esquecer, e o rótulo não teria como divergir do banco de onde
o erro veio. Mas derivar exigia citar **os dois refs de projeto como literais** no Dart, e
`String.fromEnvironment` é `const` — os dois ficavam embutidos no `main.dart.js` de **todos** os
bundles. O ref é público (está no `_headers` e no `deploy-web.yml`), então não era vazamento; o dano
era outro e pior: **o card 3.9 prova que os dois bundles não se confundem justamente conferindo que o
de homologação não contém a URL de produção**, e essa contraprova passaria a falhar para sempre. Uma
conveniência de configuração teria custado um método de verificação — e o método de verificação vale
mais.

A contraprova ficou mais forte: o passo do `deploy-web` agora **exige** que o bundle não contenha o
endereço do outro ambiente, em vez de isso ser uma conferência manual de quem publica.

---

## 8. Logs do Supabase

Nada a construir, e vale dizer por quê. Os logs de Postgres, PostgREST e Auth ficam no painel do
Supabase (**Logs & Analytics**), retidos **1 dia** no free tier, por projeto. São a fonte para o
que o app não vê: erro dentro de função `security definer`, política de RLS negando, `pg_cron`
falhando às 03:10.

A retenção de 1 dia é a restrição que importa, e o desenho do projeto já a contorna sem depender de
ninguém abrir o painel a tempo:

* regra de negócio que falha **grava pendência**, que é permanente e tem tela (card 2.2);
* a rotina diária converte exceção em `ROTINA_FALHOU`, também pendência;
* o que acontece na frente de uma pessoa vira evento no Sentry, com retenção de 90 dias.

Ou seja: o log do Supabase é para **investigar**, não para **descobrir**. Quem descobre é o Sentry, a
pendência ou o vigia. ⚠️ Corolário: ao investigar, o log de mais de 24 h **não existe mais** — se o
Sentry apontar para o banco, olhar o painel no mesmo dia.

---

## 9. O vigia também olha o backup (card 3.11 vigiado daqui)

Acrescentado neste card, em `worker-vigia/src/vigia.js`: a execução diária do vigia confere a idade
da cópia mais nova no bucket R2 `gestao-im360-backup`.

**Por que existe.** O card 3.11 registrou um modo de falha silencioso do próprio backup: **o GitHub
desativa workflow agendado em repositório com 60 dias sem commit**, e o risco vira real justamente
quando o desenvolvimento parar — quando ninguém mais abre o painel de Actions. O backup pararia de
sair sem uma linha de aviso, e a descoberta seria no dia em que ele fizesse falta. Quem vigia é outra
infraestrutura, de propósito: o backup mora no GitHub, isto roda no Cloudflare.

Decisões:

* **A idade sai do prefixo de data da cópia** (`producao/YYYY-MM-DD/`), não do `uploaded` do objeto. O
  prefixo é a data do *dump*, e é essa que responde "quão velho é o dado que eu teria de volta";
  `uploaded` responde outra coisa — recopiar um backup velho o deixaria novinho, e a idade mentiria
  exatamente na hora errada.
* **Asserção positiva**, pela mesma razão que a sonda não aceita qualquer 200: prefixo que existe
  passaria com a pasta vazia. A cópia mais nova precisa ter `data.sql.gz` (a razão de o backup
  existir — dump de schema sem dado é o jeito mais comum de um backup ser inútil) **e** o
  `MANIFESTO.txt`, que marca cópia completa.
* **Limite de 9 dias.** O backup é semanal, então em operação normal a cópia mais nova tem no máximo
  7. Nove dá folga para uma execução atrasada sem alarme falso e ainda denuncia a **primeira** semana
  perdida, em vez de esperar a segunda.
* **Falhar aqui alerta, mas não cega o resto.** `conferirBackup` devolve motivo em vez de lançar,
  inclusive quando o binding R2 não existe: uma exceção derrubaria a execução **antes** das sondas do
  Supabase, trocando uma proteção que funciona por outra que acabou de nascer.
* **Um e-mail por execução** (decisão do card 3.10, preservada): dois assuntos num envelope, não dois
  envelopes. O texto do alerta nomeia a causa mais provável — *Actions → backup-semanal → Enable
  workflow*.

⚠️ O binding `BACKUP` é **pré-condição de deploy** do vigia: bucket inexistente faz o `wrangler
deploy` recusar o Worker. É deliberado, e o vigia já publicado continua no ar enquanto isso — deploy
que falha não derruba o que está rodando. O `CLOUDFLARE_API_TOKEN` precisa de **Workers R2 Storage —
Read**.

⚠️ **O que continua sem observador é o vigia**: vigia que morre não avisa, e um *dead man's switch* de
verdade exige um observador externo, fora do escopo da v1 (card 3.10).

---

## 10. O que foi exercitado, e o que não

✅ **Medido em 02/09/2026**, não lido:

* suíte Flutter **117 verdes** (98 antes; 19 novos), `flutter analyze --fatal-infos` limpo e
  `dart format` sem alteração, com Flutter 3.47.2 — a versão que o CI fixa;
* `flutter build web --release --no-web-resources-cdn` com os quatro `--dart-define`, e conferido no
  `main.dart.js`: o DSN chegou, o `APP_AMBIENTE` chegou, e o bundle de homologação **não** contém o
  endereço nem o ref de produção;
* o passo da CSP rodado contra quatro DSNs sintéticos (curinga cobre; região `.de` reprova; dois
  rótulos de subdomínio reprovam; host exato cobre) **e contra o DSN real** do projeto criado, que
  passou;
* suíte do vigia **25 verdes** (12 antes), e a vigilância do backup exercitada **no workerd de
  verdade** com `wrangler dev`: bucket local vazio reprovou com "o bucket não tem nenhuma cópia em
  `producao/`", e uma cópia completa de `2026-08-31` passou com `idadeDias: 2` — o que confirma que a
  API real do `env.BACKUP.list()` (`objects[].key`, `truncated`, `cursor`) bate com o que a suíte
  simula.

⚠️ **O que NÃO foi exercitado, e é o que falta para este card estar fechado de ponta a ponta:**
**nenhum evento chegou ao Sentry ainda.** O `SENTRY_DSN` precisa ser cadastrado como secret do
repositório (só Irineu faz isso) e um deploy precisa acontecer. Até lá, o painel vazio é o esperado —
e é justamente por ser indistinguível do painel de um sistema sem defeitos que o `deploy-web` avisa
quando o DSN está ausente. A conferência de estreia está no §11.

---

## 11. Conferência de estreia (depois que o `SENTRY_DSN` existir)

1. O `deploy-web` de `develop` passou pelo passo **"A CSP deixa passar a ingestão do Sentry"** e o log
   mostra o host — se ele não aparecer, o secret não chegou ao job.
2. Abrir `homolog.gestaoim360.com` e conferir no **console do navegador** que não há erro de CSP
   citando `ingest.us.sentry.io`. Erro de CSP aparece no console, e é a única prova barata de que o
   envio não está sendo bloqueado.
3. Provocar um erro **não previsto** (desligar a rede e recarregar uma tela que consulta) e ver o
   evento chegar em `irineu-pinheiro/gestao-im360` com `environment: homologacao`.
4. **Conferir no evento que não há PII**: `request.url` sem `?`, sem cookies, sem `Authorization`,
   usuário só com `id`. É a asserção que mais importa, e é a única que só o evento de verdade prova.
5. Errar a senha no login de propósito e conferir que **nada** chegou ao Sentry — é o filtro de
   `deveRelatar` funcionando.
