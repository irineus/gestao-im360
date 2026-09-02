# CI/CD com GitHub Actions — card 3.9

Fonte do pipeline, como `docs/estrategia-testes.md` é a fonte da estratégia de testes e
`docs/deploy-web.md` a do contrato de publicação. Este documento diz **o que roda, quando, o que
bloqueia** e **o que só Irineu configura**.

Antes deste card existia um workflow só (`db-migrations`), disparado apenas quando o push tocava
`supabase/migrations/**`. A suíte do card 2.8 estava escrita desde o card 3.3 e **nunca tinha
rodado em lugar nenhum** — portão que não reprova é exatamente a falha que aquele card combate.

---

## 1. Os três workflows

| Workflow | Dispara | Jobs | O que bloqueia |
|---|---|---|---|
| **`testes.yml`** | todo *pull request*; push em `develop`/`main`; e `workflow_call` | `banco` (pgTAP + concorrência) e `app` (formatação, análise, testes) | o merge do PR |
| **`db-migrations.yml`** | push em `develop`/`main` tocando `supabase/migrations/**`; `workflow_dispatch` | `testes` (chama o de cima) → `migrate` | o `supabase db push` em dev e em prod |
| **`deploy-web.yml`** | push em `develop`/`main` tocando `app/**`, `assets/**` ou os próprios workflows; `workflow_dispatch` | `testes` → `publicar` | a publicação no Cloudflare Pages |

Os dois workflows de consequência **chamam** o de testes com `uses:` e dependem dele com `needs:`.
Não é redundância com o disparo por PR: o PR protege o que entra em `develop`, e o `needs:` protege
o que **sai** de `develop` para um banco ou para o ar. Sem ele, uma migração vermelha chegaria ao
banco do mesmo jeito.

Consequência aceita: um push em `develop` que toque migração **e** app roda a suíte três vezes (o
disparo próprio e as duas chamadas). O repositório é público, então minuto de Actions é livre, e
cada uma das três está protegendo uma coisa diferente. Os grupos de `concurrency` são distintos de
propósito — ver §4.

---

## 2. Versões fixas, nunca `latest`

| Ferramenta | Versão fixada | Onde |
|---|---|---|
| CLI do Supabase | **2.116.0** | `testes.yml` e `db-migrations.yml` |
| Flutter | **3.47.2** | `testes.yml` e `deploy-web.yml` |
| Wrangler | **4.128.0** | `deploy-web.yml` |

Com `latest`, uma versão nova quebra o pipeline sem que nada mude no repositório — e quebra junto a
suíte que deveria estar dizendo a verdade sobre o commit. Fixar transforma a atualização em um
commit, com PR e revisão. (Pendência técnica 2(d) das Decisões vigentes; ajuste 2 do card 2.8 §12.)

A mesma versão do CLI roda a suíte e aplica a migração: testar com um CLI e aplicar com outro é
testar outro caminho. E `3.47.2` não é escolha estética — é a versão do card 3.7, e traz o Dart
3.13.2 que `app/pubspec.yaml` exige (`sdk: ^3.13.2`). Uma versão anterior **nem resolve as
dependências**.

O terceiro item da mesma família já estava feito: `major_version = 17` em `supabase/config.toml`,
igual ao dos dois projetos remotos (ajuste 3 do card 2.8 §12).

---

## 3. Job `banco`: Postgres vazio, migrações do zero

```
supabase start -x studio,postgres-meta,imgproxy,storage-api,realtime,edge-runtime,logflare,vector,supavisor
supabase db reset        # as migrações desde a primeira + supabase/seed.sql
supabase test db         # pgTAP
supabase/tests_concorrencia/*.sh
```

**Rodar do zero, sempre.** `db reset` aplica a sequência inteira num banco vazio. É o que testa de
graça a propriedade que mais importa numa migração: que a sequência sobe limpa. `db push`
incremental nunca descobre que a migração 12 depende de algo que a 7 removeu.

**`gotrue` não pode ser excluído.** A suíte fala com o Postgres direto, mas é o GoTrue que cria o
schema `auth`, e a escola-fixture do card 3.4.5 insere em `auth.users`. O que sai da lista são os
serviços que nenhum teste toca.

⚠️ **Chave de `--exclude` desconhecida não dá erro** — ver §8.

`db reset --linked` continua **proibido**: aplicaria pgTAP e a escola-fixture no banco remoto
(card 2.8, ajuste 5).

---

## 4. `concurrency`: por que o grupo carrega o nome do workflow

```yaml
group: testes-${{ github.workflow }}-${{ github.ref }}
cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

Num workflow reutilizável, `github.workflow` é o nome do **chamador**. Sem ele no grupo, a execução
disparada pelo push e a execução chamada pelo `db-migrations` cairiam no mesmo grupo, e o
`cancel-in-progress` mataria justamente aquela de que o `db push` depende — com o resultado
dependendo de qual das duas começou primeiro, que é a definição de teste instável (card 2.8 §11).

O `cancel-in-progress` condicional é a segunda barreira: só o PR cancela a execução anterior, porque
empurrar de novo torna a antiga inútil. Push e chamada reutilizável nunca cancelam.

---

## 5. Job `app`: os mesmos três comandos do portão local

```bash
cd app
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

São exatamente os de `app/README.md`, "Verificar antes de empurrar" — o portão do CI não pode ser
mais exigente que o da máquina, senão ninguém consegue prever o resultado antes de empurrar.

Os testes leem `test/fixtures/codigos_erro.txt`, na **raiz** do repositório: o contrato de códigos
de erro tem dois consumidores (o banco, pelo teste C12, e o app) e não é de nenhum dos dois sozinho
(card 3.7).

---

## 6. Suíte de concorrência: o CI é o portão

Decisão que este card precisava tomar (nota do board): **o CI é o portão; rodar na máquina é
opcional.**

A pergunta nasceu de a máquina de Irineu não ter o daemon do Docker no ar. Mas a dependência não é
particularidade da suíte de concorrência: `supabase start` é condição do job `banco` inteiro, pgTAP
incluído. Não há o que decidir separado — ou o Docker está no ar e roda tudo localmente, ou não está
e o CI roda tudo. Os comandos são os mesmos nos dois lugares.

Os scripts são entregáveis dos cards **5.3** (admissão concorrente em bloco lotado) e **6.3**
(entrega concorrente da última unidade em estoque), pré-condição do marco 2. O contrato do
diretório está em `supabase/tests_concorrencia/README.md`.

Enquanto não existir nenhum, o passo **diz isso em voz alta** no log e no resumo da execução, em vez
de passar calado. O laço do Apêndice B do card 2.8 fazia o contrário — ver §8.

---

## 7. Deploy web

`deploy-web.yml` faz o que o card 3.8 deixou pendente: o build não roda no Cloudflare (não há
Flutter no ambiente de build do Pages), então quem constrói é o GitHub Actions e publica o
diretório pronto com `wrangler pages deploy`.

| | `develop` | `main` |
|---|---|---|
| Projeto do Pages | `gestao-im360-homolog` | `gestao-im360` |
| Endereço | `homolog.gestaoim360.com` | `app.gestaoim360.com` |
| Supabase | dev `ncdfolxdupbbfvtydngx` | prod `aqfuawrygxsiopyppjza` |
| Environment do GitHub | `dev` | `prod` (*required reviewer*) |

**Produção tem dois portões humanos**, os mesmos da migração: o merge do PR de promoção e o
*Approve and deploy* do environment `prod`. É o segundo que mostra na tela o que está prestes a ir
ao ar.

Três conferências antes e depois do build, todas por causa de falhas que **não dão erro**:

1. **Antes de construir**, os três valores de ambiente têm de existir. Build sem `--dart-define`
   não falha: gera um bundle que sobe na tela "este build não recebeu a configuração do ambiente" —
   e seria publicado do mesmo jeito (card 3.8, ajuste 1, bloqueante). O passo falha nomeando o
   secret que falta.
2. **Depois de construir**, o bundle tem de conter a URL do Supabase **e** o `APP_URL_BASE` deste
   ambiente. `APP_URL_BASE` é de onde sai o `redirectTo` da recuperação de senha: o bundle de
   produção apontando para a homologação manda a pessoa para a outra tela, e as duas são idênticas.
   As constantes de `String.fromEnvironment` ficam embutidas literalmente no `main.dart.js`, então
   a conferência é um `grep` — verificada em 02/09/2026, inclusive a contraprova (a URL do outro
   ambiente **não** está no bundle, ou seja, a asserção discrimina).
3. `_headers` presente e `404.html` ausente — as duas armadilhas do Pages que o card 3.8 mediu.

`--no-web-resources-cdn` não é otimização, é disponibilidade (card 3.8 §1).

---

## 8. O que a execução ensinou (02/09/2026)

O YAML do Apêndice B do card 2.8 era um bom esqueleto e tinha **cinco defeitos**, quatro deles
capazes de quebrar ou de enganar. Foram medidos, não deduzidos:

1. **`version: 2.20.5` do `setup-cli` não existe.** A série estável do CLI está em **2.116.0**
   (a `2.20.x` é de outra época da numeração). Versão inexistente reprova o job na hora — barulhento,
   e por isso o menos grave dos cinco.
2. **`flutter-version: '3.35.0'` é anterior ao que o app exige.** `app/pubspec.yaml` pede Dart
   `^3.13.2`, que chega com o Flutter **3.47.2**; com a 3.35 o `pub get` nem resolve.
3. **Chave de `--exclude` desconhecida é aceita em silêncio.** `inbucket` era chave válida no CLI
   1.x e hoje se chama `mailpit`. Medido com o CLI 2.116.0: `supabase start -x inbucket` sai com
   **0**, sem uma linha de aviso, e simplesmente **não exclui nada**. A exclusão escrita errada
   deixa de acontecer sem que ninguém saiba — mesma família de falha silenciosa que este projeto já
   catalogou em RLS, em view e em Redirect URL. Por isso o workflow imprime os contêineres que de
   fato subiram: não é asserção, é o antídoto contra o silêncio.
4. **O laço da suíte de concorrência deixaria o CI vermelho desde o primeiro dia.** Com o diretório
   vazio ou ausente, `for s in supabase/tests_concorrencia/*.sh; do bash "$s"; done` passa o próprio
   curinga como nome de arquivo e sai com **127** (medido, inclusive sob `bash -eo pipefail`, que é
   como o GitHub roda). E o pior desfecho não seria o vermelho: seria a equipe aprender a ignorá-lo.
   Corrigido com `nullglob` mais uma mensagem explícita quando não há script.
5. **`uses: ./.github/workflows/testes.yml` exige `workflow_call` no chamado**, que o Apêndice B não
   tinha; e o `concurrency` sugerido lá faria as duas execuções se cancelarem (§4).

Um sexto ponto, de sequência: o Apêndice B mandava o job do app rodar `dart format` sobre o
repositório, e o apêndice §10 do card 2.7 (`lib/theme/`) **não é `dart format` limpo**. A
contradição já tinha sido resolvida no card 3.7 em favor do formatado — o apêndice vale pelos
valores, não pelo espaçamento —, e o portão confirma: 36 arquivos, 0 alterados.

---

## 9. Divergência registrada com a nota do board

A nota do card 3.9 pedia "push em `main` → homolog; produção por disparo explícito com aprovação".
Isso é anterior ao card **3.8**, que fechou o contrário e por um motivo escrito: **dois projetos de
Pages, não dois ambientes de um projeto**, porque as URLs de preview mudam a cada deploy e cada uma
teria de entrar nas Redirect URLs do Auth. Implementado o que o 3.8 decidiu — `develop` → homologação,
`main` → produção. A metade que continua valendo é a aprovação: produção só vai ao ar depois do
*Approve and deploy* do environment `prod`.

---

## 10. O que só Irineu configura

| Onde | Nome | Para quê | Estado em 02/09/2026 |
|---|---|---|---|
| Secret do repositório | `SUPABASE_ACCESS_TOKEN` | `supabase link` | ✅ existe |
| Secret do repositório | `SUPABASE_DB_PASSWORD_DEV` | `db push` no dev | ✅ existe |
| Secret do repositório | `SUPABASE_DB_PASSWORD_PROD` | `db push` no prod | ✅ existe |
| Environment `prod` | *required reviewer* | portão humano da produção | ✅ ligado (`irineus`) |
| Secret do repositório | **`CLOUDFLARE_API_TOKEN`** | `wrangler pages deploy` — permissão *Cloudflare Pages: Edit* | ⛔ **falta** |
| Secret do repositório | **`CLOUDFLARE_ACCOUNT_ID`** | idem | ⛔ **falta** |
| Secret do environment `dev` | **`SUPABASE_ANON_KEY`** | chave publicável do projeto dev, no bundle de homologação | ⛔ **falta** |
| Secret do environment `prod` | **`SUPABASE_ANON_KEY`** | chave publicável do projeto prod, no bundle de produção | ⛔ **falta** |

⚠️ **Enquanto os quatro últimos não existirem, o `deploy-web` falha** — no primeiro passo, com o
nome exato do que criar no log e no resumo da execução. É deliberado: publicar um bundle sem
configuração seria pior, porque o build não reclama e o app sobe dizendo que não foi configurado.
O `testes.yml` e o `db-migrations.yml` não dependem de nada disso e seguem verdes.

A chave publicável é **pública por desenho** — vai no bundle que qualquer visitante baixa (card 3.8
§1) — e mesmo assim fica em secret, por um motivo prático: assim rotacionar a chave não exige um
commit.

---

## 11. Rodar o mesmo portão na máquina

```bash
# banco (precisa do daemon do Docker no ar)
supabase start
supabase db reset
supabase test db

# app
cd app
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

Se outro projeto local do Supabase já estiver ocupando as portas 54321-54324, o `supabase start`
falha com `port is already allocated` e diz qual porta. Não é preciso derrubar o outro projeto:
`supabase stop` no diretório dele, ou uma cópia do repositório com portas próprias em
`config.toml`, resolvem — foi assim que este card se verificou, sem encostar no stack do outro
projeto que estava no ar.

---

## 12. Verificação deste card (02/09/2026)

Rodado de verdade, não lido — com o CLI, o Flutter e a lista de exclusão **exatos** dos workflows:

- `supabase start -x …` subiu o stack e aplicou as quatro migrações; `db reset` refez a sequência do
  zero; `supabase test db` → **6 arquivos, 115 testes, `Result: PASS`**.
- `dart format` → 36 arquivos, **0 alterados**; `flutter analyze --fatal-infos` → **No issues
  found**; `flutter test` → **98 testes verdes**.
- `flutter build web --release --no-web-resources-cdn` com os três `--dart-define` de homologação, e
  as quatro conferências do §7 passando — mais a contraprova de que a URL de produção **não** está
  naquele bundle.

O que só o CI pode provar (o `needs:` segurando o `db push`, o *required reviewer* segurando o
deploy de produção) se prova na primeira execução de verdade, e está anotado no resultado do card.

---

## 13. Ajustes que este card deixa

| # | Para | O quê | Peso |
|---|---|---|---|
| 1 | **Irineu** | Os quatro itens ⛔ do §10 — sem eles o `deploy-web` fica vermelho | bloqueante do deploy |
| 2 | **5.3 / 6.3** | Os dois scripts de `supabase/tests_concorrencia/` — hoje o passo roda zero e avisa | bloqueante do marco 2 |
| 3 | **3.12** | Ao ligar o Sentry, acrescentar o host de ingestão ao `connect-src` do `_headers` **no mesmo commit** — a CSP bloqueia sem avisar (herdado do card 3.8) | bloqueante |
| 4 | **todos** | Trocar uma versão fixada do §2 é um commit com PR: quem atualizar precisa rodar a suíte antes | informativo |
