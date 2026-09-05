# CI/CD com GitHub Actions — card 3.9

Fonte do pipeline, como `docs/estrategia-testes.md` é a fonte da estratégia de testes e
`docs/deploy-web.md` a do contrato de publicação. Este documento diz **o que roda, quando, o que
bloqueia** e **o que só Irineu configura**.

Antes deste card existia um workflow só (`db-migrations`), disparado apenas quando o push tocava
`supabase/migrations/**`. A suíte do card 2.8 estava escrita desde o card 3.3 e **nunca tinha
rodado em lugar nenhum** — portão que não reprova é exatamente a falha que aquele card combate.

---

## 1. Os cinco workflows

| Workflow | Dispara | Jobs | O que bloqueia |
|---|---|---|---|
| **`testes.yml`** | todo *pull request*; push em `develop`/`main`; e `workflow_call` | `banco` (pgTAP + concorrência), `migrações` (portão do card 4.0,5 **e a suíte do guarda de destrutivos**), `extração` (o produtor do arquivo do importador, `node --test` — card 9.2), `edge functions` (lógica pura, `node --test` — card 4.7), `app` (formatação, análise, testes) e `vigia` (`node --test`) | o merge do PR |
| **`db-migrations.yml`** | push em `develop`/`main` tocando `supabase/migrations/**`, `supabase/functions/**` ou `supabase/config.toml`; `workflow_dispatch` | `testes` (chama o de cima) → `migrate` (`db push` e, desde o card 4.7, `functions deploy --use-api` logo depois) | o `supabase db push` e a publicação das Edge Functions em dev e em prod |
| **`deploy-web.yml`** | push em `develop`/`main` tocando `app/**`, `assets/**` ou os próprios workflows; `workflow_dispatch` | `testes` → `publicar` | a publicação no Cloudflare Pages |
| **`deploy-worker-vigia.yml`** | push em **`main`** tocando `worker-vigia/**` ou os próprios workflows; `workflow_dispatch` | `testes` → `publicar` | a publicação do Worker vigia (card 3.10) |
| **`backup-semanal.yml`** | `schedule` domingo 09:30 UTC (06:30 em São Paulo); `workflow_dispatch` | `backup` (dump de produção → ensaio de restauração → R2) | nada — não é portão, é rotina (card 3.11) |

O `backup-semanal` é o único que **não chama a suíte** e o único **sem `environment`**, e as duas
coisas são decisão: ele não bloqueia entrega nenhuma, e é o único workflow que só **lê** produção.
Posto atrás do *required reviewer* do environment `prod`, ele ficaria em `waiting` todo domingo à
espera de um clique que ninguém dá no fim de semana — e backup que espera aprovação é backup que não
acontece. Detalhe em `docs/backup-restauracao.md`.

O vigia dispara só de `main` porque é **um** Worker para os **dois** ambientes — não há vigia de
homologação e vigia de produção, o que ele vigia é o par. Detalhe em `docs/worker-vigia.md`.

Os três workflows de consequência **chamam** o de testes com `uses:` e dependem dele com `needs:`.
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
| Wrangler | **4.128.0** | `deploy-web.yml` e `deploy-worker-vigia.yml` |
| Node | **24.16.0** | `testes.yml` (job `vigia`) e `deploy-worker-vigia.yml` |

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

### Job `vigia`

```bash
node --test "worker-vigia/test/**/*.test.mjs"
```

Um passo só, e **sem `npm ci`**: o Worker do card 3.10 não tem dependência nenhuma, então não há
`node_modules` para instalar nem para auditar. Os testes usam um `fetch` de mentira e não falam com
Supabase nenhum — quem faz isso é `worker-vigia/conferir.mjs`, no deploy, com as chaves na mão.

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

Quatro conferências ao redor do build, todas por causa de falhas que **não dão erro**:

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
4. **Depois de publicar**, o endereço público tem de servir **o arquivo que acabou de ser
   construído** (card 3.9,5). Publicar não é estar no ar: `wrangler pages deploy --branch <x>` só
   publica em produção do projeto quando `<x>` bate com a *Production branch* do painel — senão o
   deploy vira **preview**, ganha URL própria, imprime `Deployment complete`, o workflow fica verde
   e o endereço público continua na versão anterior, **que funciona**. Foi o que aconteceu do card
   3.9 ao 3.12 sem ninguém reparar: a conferência do card 3.9 mediu a coisa certa nas URLs erradas.
   O passo baixa `$APP_URL_BASE/main.dart.js` e compara o sha256 com `build/web/main.dart.js`, em
   até seis tentativas espaçadas de 10 s, com cache-buster e `curl --compressed`. Detalhe em
   `docs/deploy-web.md` §5.9.

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
| Secret do repositório | `CLOUDFLARE_API_TOKEN` | `wrangler pages deploy` — permissão *Account · Cloudflare Pages · Edit* | ✅ criado 02/09/2026 |
| Secret do repositório | `CLOUDFLARE_ACCOUNT_ID` | idem | ✅ criado 02/09/2026 |
| Secret do environment `dev` | `SUPABASE_ANON_KEY` | chave publicável do projeto dev, no bundle de homologação | ✅ criado 02/09/2026 |
| Secret do environment `prod` | `SUPABASE_ANON_KEY` | chave publicável do projeto prod, no bundle de produção | ✅ criado 02/09/2026 |
| Secret do repositório | `SENTRY_DSN` | observabilidade do app (card 3.12) — **o único opcional**: sem ele o `deploy-web` avisa e publica um bundle sem Sentry, em vez de reprovar | ⚠️ falta criar |
| Secret do repositório | `SUPABASE_ANON_KEY_DEV` | sonda do vigia no projeto dev (card 3.10) | ✅ criado 02/09/2026 |
| Secret do repositório | `SUPABASE_ANON_KEY_PROD` | sonda do vigia no projeto prod (card 3.10) | ✅ criado 02/09/2026 |
| Secret do repositório | `RESEND_API_KEY` | e-mail de alerta do vigia (card 3.10) | ✅ criado 02/09/2026 (chave `gestao-im360-vigia`, *Sending access*) |
| Token do Cloudflare | permissão *Workers Scripts — Edit* | `wrangler deploy` do vigia (card 3.10) | ✅ acrescentada ao token `gestao-im360` em 02/09/2026 — editar o token **não muda o valor**, então o secret continuou valendo |
| Cloudflare R2 | bucket `gestao-im360-backup` | destino do backup semanal (card 3.11) | ⚠️ falta criar |
| Secret do repositório | `R2_ACCESS_KEY_ID` | `aws s3` contra o R2 (card 3.11) | ⚠️ falta criar |
| Secret do repositório | `R2_SECRET_ACCESS_KEY` | idem — só aparece uma vez, na criação | ⚠️ falta criar |

| Painel do Cloudflare Pages | *Production branch* de `gestao-im360-homolog` = `develop` | sem isso o deploy do CI vira **preview** e o endereço público não muda (card 3.9,5) | ⚠️ falta configurar |
| Painel do Cloudflare Pages | *Production branch* de `gestao-im360` = `main` | idem, em produção | ⚠️ falta configurar |

⚠️ As duas últimas linhas **não são secrets** e por isso são as mais fáceis de esquecer: nada no
GitHub as menciona, e o `deploy-web` ficava verde sem elas. Desde o card 3.9,5 não fica mais — a
asserção depois de publicar reprova, e o resumo da execução traz o caminho do painel.

⚠️ O token do R2 é **outro** token, e não o `CLOUDFLARE_API_TOKEN` de Pages e Workers: o R2 emite um
par de chaves no formato S3 (*Object Read & Write*, escopo do bucket), que é o que o `aws s3`
consome. O `CLOUDFLARE_ACCOUNT_ID` é reaproveitado — ele também é o subdomínio do endpoint S3.

⚠️ As duas chaves publicáveis aparecem **duas vezes** na tabela de propósito: como secret de
environment (`SUPABASE_ANON_KEY`, para o build do app) e como secret de repositório com sufixo (para
o vigia). Um job enxerga **um** environment só, e o vigia precisa das duas ao mesmo tempo.

⚠️ O nome `SUPABASE_ANON_KEY` é **o mesmo nos dois environments, de propósito** — é o environment
que decide qual valor o job enxerga. Criado como secret **do repositório**, o build de produção
pegaria a chave de homologação e **ninguém veria**, porque as duas telas são idênticas. Os valores
são os que os dois sites já serviam antes do primeiro deploy automatizado, lidos do `main.dart.js`
publicado: assim o build do CI reproduz o que estava no ar, em vez de trocar a chave em silêncio.

**Enquanto os quatro não existiam, o `deploy-web` falhava no primeiro passo**, com o nome exato do
que criar no log e no resumo da execução — deliberado, e exercitado de verdade em 02/09/2026 (run
`33583326416`): publicar um bundle sem configuração seria pior, porque o build não reclama e o app
sobe dizendo que não foi configurado. `testes.yml` e `db-migrations.yml` nunca dependeram de nada
disso.

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

# vigia (nada a instalar: o Worker não tem dependência)
cd ..
node --test "worker-vigia/test/**/*.test.mjs"

# migrações (portão do card 4.0,5 — também sem dependência nenhuma)
node --test "portao-migracoes/test/**/*.test.mjs"
node portao-migracoes/varredor.mjs supabase/migrations

# guarda de destrutivos (o portão que vive fora do CI, card 5.5,5)
node .claude/hooks/guarda-destrutivos.teste.mjs

# extração da planilha (card 9.2 — também sem dependência nenhuma)
node --test "extracao/test/**/*.test.mjs"
# e, com a planilha na mão, a extração de verdade:
node extracao/extrair.mjs "Gestão Interativo.xlsx" --snapshot 2026-08-29 --saida saida/

# edge functions (card 4.7): a lógica pura, com o Node lendo .ts direto
node --test "supabase/functions/**/*.test.ts"
# a função de verdade, contra o stack local (edge-runtime + Auth + banco)
supabase functions serve
```

Com outro checkout do MESMO repositório usando o stack (duas sessões em paralelo, card 4.7), a
saída é a mesma do parágrafo abaixo: uma cópia de `supabase/` com `project_id` e portas próprias
no `config.toml` sobe um segundo stack sem encostar no primeiro — foi assim que a suíte do card
4.7 rodou (`266/266`) enquanto o card 4.6 usava o stack de sempre.

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

E no CI, que é onde o resto se prova:

- **PR #41** (run `33583171242`): os dois jobs verdes. Subiram **cinco** contêineres (`db`, `auth`,
  `kong`, `rest`, `inbucket`) — a exclusão do §3 funcionou; as quatro migrações aplicaram do zero;
  **115 PASS**; e o passo de concorrência **emitiu o aviso em vez de sair com 127**.
- **`deploy-web` sem os segredos** (run `33583326416`, primeira execução): falhou no passo 3, de
  conferência, nomeando os três que faltavam — antes de construir e antes de publicar.
- **`deploy-web` com os segredos** (mesmo run, reexecutado): verde. `homolog.gestaoim360.com` passou
  a servir um bundle construído pelo CI, conferido depois de publicado — chave publicável do dev,
  `https://ncdfolxdupbbfvtydngx.supabase.co`, `APP_URL_BASE` de homologação e `/alunos` respondendo
  200. **É o primeiro deploy automatizado do projeto**; até aqui os dois ambientes tinham subido por
  *direct upload* (card 3.8).
- **`deploy-web` em `main`** (run `33583932993`): os testes verdes e o job `publicar (PRODUÇÃO)`
  parado em **`waiting`**, no environment `prod`, à espera do *Approve and deploy*. O portão duplo
  da produção, que até aqui só valia para migração, **estreou para o app**.

---

## 13. Ajustes que este card deixa

| # | Para | O quê | Peso |
|---|---|---|---|
| 1 | **Irineu** | Os quatro itens ⛔ do §10 — sem eles o `deploy-web` fica vermelho | bloqueante do deploy |
| 2 | **5.3 / 6.3** | Os dois scripts de `supabase/tests_concorrencia/` — hoje o passo roda zero e avisa | bloqueante do marco 2 |
| 3 | **3.12** | Ao ligar o Sentry, acrescentar o host de ingestão ao `connect-src` do `_headers` **no mesmo commit** — a CSP bloqueia sem avisar (herdado do card 3.8) | bloqueante |
| 4 | **todos** | Trocar uma versão fixada do §2 é um commit com PR: quem atualizar precisa rodar a suíte antes | informativo |
| 5 | ~~**Irineu**~~ | ~~Os quatro itens do §10 que o card 3.10 acrescentou~~ — ✅ **feitos em 02/09/2026**; o `deploy-worker-vigia` ficou verde na estreia e o vigia está no ar | resolvido |

---

## 14. Job `migrações`: nenhuma migração grava dado de negócio (card 4.0,5)

```bash
node --test "portao-migracoes/test/**/*.test.mjs"   # o portão sabe ler?
node portao-migracoes/varredor.mjs supabase/migrations
```

**Por que existe.** Todo `.sql` posto em `supabase/migrations/` chega a **produção sozinho** no merge
em `main`. A decisão de 02/09/2026 (Decisões vigentes §1, "Dado de negócio só em dev até a virada")
restringe o dado da planilha ao projeto dev/homolog até o cutover do card 9.7. E o card 3.6 criou o
precedente do **seed-como-migração**: depois dele, escrever a carga do catálogo como migração é o
caminho mais natural — e produção receberia dado de planilha sem ninguém decidir. As duas falhas do
projeto até aqui foram de esquecimento, não de julgamento; regra que depende de lembrar não serve.

**Lista permitida, não lista proibida.** Uma migração pode gravar em `unidade`, `perfil`,
`permissao`, `perfil_permissao`, `usuario`, `usuario_perfil`, `parametro` e `metodo` — dado de
**configuração**, que *precisa* estar em produção, senão `tem_permissao()` é falso para todo mundo.
Qualquer outra tabela reprova, **inclusive as que ainda não existem**: tabela nova nasce protegida
sem ninguém se lembrar de nada. Lista proibida deixaria de fora toda tabela futura e falharia em
silêncio. Ampliar a lista é um commit em `portao-migracoes/varredor.mjs` — que é exatamente a
conversa que o portão existe para provocar.

**O que o varredor distingue** (é o ponto delicado, onde um `grep` ingênuo se perde):

| Forma | Veredito | Por quê |
|---|---|---|
| `insert into aluno …` no nível superior | reprova | carga de dado de negócio |
| `insert into pendencia` no **corpo** de `create function` | passa | corpo é código que roda depois; é o `gerar_pendencias` do 5.5 e o `registrar_entrega` do 6.3 |
| `do $$ … insert into material … $$` | reprova | bloco `do` executa **na hora da migração** — é por onde a carga entraria disfarçada |
| `create function fn_seed_x() …; select fn_seed_x();` | reprova | a migração **chama**: o corpo passa a contar, transitivamente, e o motivo mostra o caminho `fn_a() → fn_b()` |
| `create trigger … execute function fn()` | passa | registra quem roda depois; não chama nada agora |
| `on update cascade`, `for update`, `grant insert` | passa | não são escrita; `update` só conta com `set` |
| comentário e literal que citam `insert into aluno` | passa | comentários e literais saem antes da busca |
| `execute 'insert into ' \|\| v_tabela` | reprova | comando montado em tempo de execução: o que o portão não consegue ler, reprova (fail-closed) |
| `$$` não fechado | reprova | idem — SQL ilegível não passa por não ter sido entendido |

O caso limite que o portão precisa continuar aprovando é o **seed do card 3.6**: ele grava dado, e
dado permitido. A suíte exige verde nas quatro migrações que já existem **e** exige que o seed
apareça gravando exatamente em `unidade`, `parametro`, `permissao`, `perfil`, `perfil_permissao` e
`usuario_perfil` — se o portão parar de enxergar a chamada `perform fn_seed_acesso(…)`, essa
asserção cai, em vez de o portão passar a mentir de verde.

**A suíte roda antes da varredura**, de propósito: portão que parou de ler o que devia diz "verde"
sem que nada denuncie — a doença que o card 2.8 catalogou. São 18 asserções sobre 13 arquivos SQL
sintéticos em `portao-migracoes/test/casos/`, batizados `passa-` e `reprova-`, com um teste que
percorre o diretório e exige de cada um o veredito que o nome promete (caso novo entra sem precisar
de teste novo).

**Correção de fato — a definição que vale é a ÚLTIMA aplicada, não a primeira do conjunto
(02/09/2026, card 4.1).** Ao exercitar o portão contra uma migração de catálogo escrita de propósito
com a carga escondida dentro da função, o veredito saiu **verde**. A causa não estava no disfarce: o
varredor montava o mapa de funções com "a primeira definição vence", e o conjunto tinha dois arquivos
definindo a mesma função. Isso não é artefato de bancada — **`create or replace` é a forma normal
deste projeto** (foi assim que o card 4.1 escreveu `fn_seed_metodos`, como o 3.6 escreveu as
`fn_seed_*`), então a migração 1 podia definir uma função inofensiva, a migração 3 substituí-la por
uma carga do catálogo e chamá-la, e o portão continuaria lendo o corpo **antigo** — aprovando
exatamente o disfarce que ele existe para barrar, com a agravante de o corpo aprovado estar no
repositório para quem fosse conferir. O mapa passou a ser atualizado arquivo a arquivo, na ordem de
aplicação (`listarMigracoes` ordena por nome, que começa pelo timestamp), **antes** de varrer cada
arquivo: função definida e chamada no mesmo arquivo continua resolvendo, e função definida só numa
migração posterior **não** resolve — o que é correto, porque em tempo de aplicação ela ainda não
existe. As duas asserções novas são justamente essas duas metades, e a primeira foi vista **vermelha
contra o código antigo** antes de a correção entrar.

**Divergência registrada com a nota do card.** A nota lista sete tabelas permitidas e não inclui
`usuario_perfil`. Ela está na lista implementada porque `fn_seed_direcao_inicial`, chamada pelo seed
do 3.6, liga o primeiro usuário ao perfil DIRECAO — é a mesma configuração de acesso que a nota já
permite em `perfil` e `perfil_permissao`, e sem ela o seed que o próprio card manda exigir verde
ficaria vermelho. A outra diferença é de forma: o card falava em "passo novo no `testes.yml`", e
saiu um **job**, para que o vermelho apareça com nome próprio na lista de checks do PR em vez de
esconder-se dentro do job de outra coisa.

**Alcance — o portão cobre um caminho, o do repositório.** Não cobre SQL aplicado à mão em produção
(já proibido pelas regras inegociáveis) nem dado criado pela **tela** em produção; esse é coberto
pela pré-condição (10) do card 9.7, que confere por contagem que produção está vazia antes da carga.
Dentro do próprio repositório ficam de fora, assumidamente, o `create table … as select` (que não
tem como carregar tabela de negócio já criada por uma migração anterior) e o que uma extensão
externa fizesse por conta própria.
