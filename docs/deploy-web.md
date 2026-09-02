# Publicação web no Cloudflare Pages — card 3.8

> **Fonte do deploy web.** O que este documento decide vale para os dois ambientes e para o
> workflow do card 3.9, que automatiza exatamente o que está aqui.
>
> Entradas: `app/README.md` (como o app é construído), `docs/acesso-autenticacao.md` §5 e §7 (o que
> o Auth precisa da URL pública), `docs/identidade-visual.md` (ícones e favicon).

O card entrega **o artefato e o contrato**: como o build é feito, o que o Pages tem de servir, o que
os dois projetos Supabase precisam ter no painel e como se confere que ficou certo. A criação dos
dois projetos de Pages e a visita ao painel do Supabase são de Irineu — a sessão não tem ferramenta
de Pages no conector do Cloudflare (só Workers, KV, R2, D1 e Hyperdrive) e o painel do Auth não é
versionado (§4).

> ✅ **Executado em 01–02/09/2026.** Os dois ambientes estão no ar: **`app.gestaoim360.com`** e
> **`homolog.gestaoim360.com`**, por *direct upload* (o build automatizado é o card 3.9). Painel do
> Auth preenchido nos dois projetos e **SMTP próprio no ar** — Resend com `gestaoim360.com`
> verificado, remetente `nao-responda@gestaoim360.com` (§11). O roteiro do §10 foi rodado contra os
> dois endereços, com o fluxo de recuperação exercitado por e-mail real.

---

## 1. O artefato

```bash
cd app
flutter build web --release --no-web-resources-cdn \
  --dart-define=SUPABASE_URL=<url do projeto> \
  --dart-define=SUPABASE_ANON_KEY=<chave publicável do projeto> \
  --dart-define=APP_URL_BASE=<url pública deste ambiente>
```

Saída: `app/build/web`, **46 arquivos, 42 MB**, maior arquivo `canvaskit/canvaskit.wasm` com 6,9 MiB.
Os limites do Pages são 20.000 arquivos e **25 MiB por arquivo** — folga larga nos dois.

### `--no-web-resources-cdn` não é otimização, é disponibilidade

Sem a opção, o build de release carrega o CanvasKit de `https://www.gstatic.com/flutter-canvaskit/…`
em vez da pasta `canvaskit/` que ele mesmo gerou. **Medido em 01/09/2026:** com o gstatic
inalcançável, o app não desenha nada — página branca, sem erro na tela e sem nada no console além de
um `Failed to fetch`. Não é hipótese de laboratório: rede de escola com filtro, proxy corporativo e
qualquer bloqueio de terceiros produzem a mesma tela. Com a opção, tudo é servido da própria origem,
e a CSP do §5 pode fechar `script-src` em `'self'`.

Um segundo pedido externo continua existindo e é inofensivo: a engine busca a **Roboto** em
`fonts.gstatic.com` como fonte de último recurso. Falha em warning, não em tela branca — a Inter vai
empacotada (card 2.7).

### Os três `--dart-define`

| Valor | dev (`ncdfolxdupbbfvtydngx`) | prod (`aqfuawrygxsiopyppjza`) |
|---|---|---|
| `SUPABASE_URL` | `https://ncdfolxdupbbfvtydngx.supabase.co` | `https://aqfuawrygxsiopyppjza.supabase.co` |
| `SUPABASE_ANON_KEY` | chave publicável do projeto dev | chave publicável do projeto prod |
| `APP_URL_BASE` | URL pública do Pages de homologação | URL pública do Pages de produção |

`SUPABASE_ANON_KEY` é **pública por desenho** — vai dentro do bundle, que qualquer visitante baixa.
Quem protege os dados é a RLS, e é por isso que o cadastro público está fechado (card 3.5 §2). A
*service key* nunca entra aqui: `service_role` tem `BYPASSRLS` (card 3.3).

`APP_URL_BASE` erra baixo e cala: ele monta o `redirectTo` da recuperação de senha. Apontando para o
outro ambiente, o link do e-mail de produção leva a pessoa para a homologação — e ninguém percebe,
porque as duas telas são idênticas.

---

## 2. Os dois projetos no Cloudflare Pages

| | Homologação | Produção |
|---|---|---|
| Projeto | `gestao-im360-homolog` | `gestao-im360` |
| Endereço público | `homolog.gestaoim360.com` | `app.gestaoim360.com` |
| Endereço do Pages (sempre existe) | `gestao-im360-homolog.pages.dev` | `gestao-im360.pages.dev` |
| Branch de produção do projeto | `develop` | `main` |
| Diretório de saída | `app/build/web` | `app/build/web` |
| Supabase | dev | prod |

O domínio `gestaoim360.com` foi registrado em 01/09/2026 e está na mesma conta Cloudflare, então o
`Custom domains` de cada projeto cria o DNS sozinho. O `APP_URL_BASE` de cada ambiente é o
**endereço público**, não o `pages.dev` — os dois continuam servindo o app, mas é do `APP_URL_BASE`
que sai o `redirectTo` do e-mail, e link de recuperação apontando para `pages.dev` numa escola que
conhece o app por `app.gestaoim360.com` parece phishing.

**Dois projetos, não dois ambientes de um projeto.** O Pages tem "Preview" e "Production" dentro do
mesmo projeto, e seria tentador usar `develop` como preview de `gestao-im360`. Não: as URLs de
preview do Pages mudam a cada deploy (`<hash>.<projeto>.pages.dev`), e cada URL nova teria de entrar
nas Redirect URLs do Supabase para o link de recuperação funcionar (§4). Endereço estável por
ambiente é o que torna a configuração do Auth possível.

O build não roda no Pages: o Flutter não está no ambiente de build do Cloudflare. Quem constrói é o
GitHub Actions (card 3.9), que publica o diretório pronto com `wrangler pages deploy`. Enquanto o
3.9 não existe, o mesmo diretório pode ser arrastado para a tela de upload do Pages.

⚠️ A conta do Cloudflare já tem `entrelares-site` e `entrelares-site-preview`, do **outro projeto de
Irineu** (conferido em 01/09/2026 com `workers_list`). Nada deste sistema encosta neles.

> **Se um dia isto virar Worker com assets.** O Cloudflare passou a recomendar
> *Workers static assets* no lugar de Pages. A migração é possível, com **uma armadilha**: o Pages
> *deduz* que o projeto é uma SPA; o Worker não deduz nada. Sem
> `assets.not_found_handling = "single-page-application"` no `wrangler.toml`, todo link direto
> (`/alunos`, `/redefinir-senha`) passa a responder 404.

---

## 3. Roteamento: por que não existe `_redirects`

O app usa **estratégia de URL por caminho** (`usePathUrlStrategy()`, em
`app/lib/config/estrategia_url.dart`) — `/alunos`, não `/#/alunos`. A troca foi feita neste card e
não é estética: **o fragmento da URL é do Supabase**, e o §6 conta o que acontecia quando a rota
disputava esse espaço.

Com a rota no caminho, `GET /alunos` chega ao servidor e precisa devolver o `index.html`. No
Cloudflare Pages **isso já é o comportamento nativo**: sem um `404.html` no topo, o Pages assume que
o projeto é uma single-page application e responde qualquer caminho não casado com o `index.html`.
O build do Flutter não gera `404.html`. Não há nada a configurar.

E há uma coisa a **não** fazer. A regra que todo tutorial de SPA manda pôr num `_redirects`:

```
/*  /index.html  200      ← NUNCA neste projeto
```

No Pages, "os redirects são sempre seguidos, exista ou não um asset para a requisição". Essa linha
não seria um *fallback*: seria a resposta de **todas** as requisições, `main.dart.js` e
`canvaskit.wasm` inclusive. O app abriria em branco, e o `_redirects` é o último lugar onde alguém
procuraria.

As duas proibições são asserção em `app/test/publicacao_web_test.dart`, que reprova se
`web/404.html` aparecer ou se um `_redirects` ganhar regra curinga.

---

## 4. O que Irineu configura no painel do Supabase — nos dois projetos

Não é lista de desejos: sem isto, **o convite e a recuperação de senha não funcionam**, e a falha é
silenciosa. `supabase/config.toml` não alcança os projetos remotos (o projeto não usa
`supabase config push`, para não apagar o SMTP — lição do Desmalha).

Em **Authentication → URL Configuration**:

1. **Site URL** = a URL pública daquele ambiente (`https://gestao-im360.pages.dev` ou o domínio do
   §7). É dela que o Auth constrói o link do convite.
2. **Redirect URLs**: acrescentar `<url pública>/**`.

A regra por trás do item 2, **medida em 01/09/2026** contra o Auth de verdade:

| `redirect_to` pedido | Lista tinha | Resultado |
|---|---|---|
| `…:3000/redefinir-senha` | `…:3000` **como Site URL** | ✅ honrado |
| `…:3000/redefinir-senha` (outro host) | `…:3000` como Redirect URL | ❌ caiu na Site URL |
| `…:3000/redefinir-senha` (outro host) | `…:3000/**` | ✅ honrado |
| host não autorizado | — | ❌ caiu na Site URL |

Duas consequências. A lista casa por **igualdade**, não por prefixo: `https://app.exemplo` não
autoriza `https://app.exemplo/redefinir-senha` — quem autoriza caminho é o `/**`. E o destino
recusado **não devolve erro**: a pessoa é mandada para a Site URL, entra no sistema e nunca vê a
tela de nova senha. Um link que "quase funciona" é o pior caso possível, porque ninguém abre
chamado.

Caminho sob a própria **Site URL** funciona sem entrada extra — mas a entrada `/**` fica escrita
assim mesmo: no dia em que o domínio do §7 entrar e a Site URL mudar, a lista continua certa.

Ainda no painel, na mesma visita:

3. ⚠️ **SMTP próprio** (`Authentication → Emails → SMTP Settings`), nos dois projetos. Sem ele o
   Supabase usa o serviço interno, com teto de poucos e-mails por hora e **sem garantia de
   entrega** — e convite e recuperação vivem de e-mail. Fica **só no painel**, nunca no
   repositório.
4. **Rate limits**: conferir o teto de e-mails por hora antes de um dia de cadastro da equipe. O
   local é 2/h (`config.toml`), e ele foi atingido durante os testes deste card — a tela mostra
   `over_email_send_rate_limit` e a pessoa não entende que só precisa esperar (ajuste 3 do §8).
5. **Sign In / Providers → Email**: conferir que `Allow new users to sign up` continua desabilitado
   (card 3.5 §2).

---

## 5. Cabeçalhos: `app/web/_headers`

O Pages lê o arquivo do diretório publicado e não o serve como asset. Limites: 100 regras, 2.000
caracteres por cabeçalho.

| Cabeçalho | Por quê |
|---|---|
| `X-Content-Type-Options: nosniff` | impede que o navegador adivinhe o tipo de um arquivo |
| `X-Frame-Options: DENY` + `frame-ancestors 'none'` | o sistema não é para ser embutido em iframe; o par cobre navegador antigo e novo |
| `Referrer-Policy: strict-origin-when-cross-origin` | a URL de recuperação carrega um `?code=` de uso único — cruzando origem, só a origem viaja |
| `Permissions-Policy` | câmera, microfone, localização, pagamento e USB negados: nada disso é usado |
| `Cross-Origin-Opener-Policy: same-origin` | isola a janela de quem a abriu |
| `Cache-Control: public, max-age=0, must-revalidate` | ver abaixo |
| `Content-Security-Policy` | ver abaixo |

**Cache.** O Flutter web **não versiona os nomes dos arquivos**: `main.dart.js` se chama assim em
todo build. Cache longo aqui não é economia, é a garantia de que alguém vai continuar rodando a
versão da semana passada sem saber. `must-revalidate` faz cada pedido revalidar por ETag (respostas
304, baratas), a borda do Cloudflare continua servindo, e o service worker do Flutter cuida do uso
offline.

**CSP.** `script-src 'self' 'wasm-unsafe-eval'` (o `wasm-unsafe-eval` é o CanvasKit; sem ele o app
não desenha), `worker-src 'self' blob:`, `style-src 'self' 'unsafe-inline'` (a engine injeta estilo
inline), e `connect-src` restrito aos **dois hosts do Supabase**. Verificado em 01/09/2026 servindo
o build de release com estes cabeçalhos: login, navegação e recuperação de senha, **zero violação de
CSP** no console.

`connect-src` é a linha que mais vai doer se for esquecida:

- ✅ **card 3.12 (Sentry) — feito em 02/09/2026**: `https://*.ingest.us.sentry.io` entrou no
  `connect-src` no mesmo commit que ligou o SDK, exatamente porque o evento bloqueado por CSP é
  bloqueado **em silêncio** — o Sentry não reclama, ele simplesmente não recebe nada, e isso é
  indistinguível de "não houve erro". A linha passou a ter **duas** asserções: uma no
  `publicacao_web_test.dart` (o `connect-src` cita a ingestão) e outra no `deploy-web.yml`, que
  extrai o host do `SENTRY_DSN` de verdade e reprova o build quando a CSP não o cobre. Detalhe em
  `docs/observabilidade.md` §4;
- **Realtime do Supabase**, se um dia for usado, precisa dos mesmos hosts em `wss:`.

---

## 5.9. O deploy do CI não chegava ao endereço público (card 3.9,5)

**Medido em 02/09/2026, na sessão do card 3.12; corrigido pelo card 3.9,5.** Está escrito aqui
porque este documento é a fonte do contrato de publicação, e o contrato **não estava sendo
cumprido** desde que o card 3.9 criou o pipeline.

Depois de um `deploy-web` **verde** em `develop` (run 33647857494, com `Deployment complete` do
wrangler), o `main.dart.js` servido em cada endereço:

| URL | sha1 (16) |
|---|---|
| `develop.gestao-im360-homolog.pages.dev` (o que o CI publicou) | `ac1c466c98ab1bd6` |
| `gestao-im360-homolog.pages.dev` (produção do projeto) | `95065fafef1c765f` |
| **`homolog.gestaoim360.com`** | **`95065fafef1c765f`** |
| `main.gestao-im360.pages.dev` | `b9f31c94602de060` |
| `gestao-im360.pages.dev` | `7311a8da919a3df0` |
| **`app.gestaoim360.com`** | **`7311a8da919a3df0`** |

**Os dois endereços públicos serviam um deploy que não é o do CI** — os *direct uploads* feitos à
mão no card 3.8.

**Causa:** os dois projetos nasceram por *direct upload*, e num projeto assim a *production branch*
fica com um valor que o CI nunca usa; `wrangler pages deploy --branch <x>` só publica em produção
quando `<x>` bate com ela. Como não bate, **todo deploy do CI vira preview**.

⚠️ **O sintoma é a ausência de sintoma**, de novo: o workflow fica verde, o wrangler imprime
`Deployment complete`, e o site continua no ar servindo a versão anterior — que **funciona**, o que
remove o último sinal que restaria. É a mesma família de `--exclude` com chave desconhecida (card
3.9) e de Redirect URL recusada (§4): a operação "dá certo" e não faz o que se pensa.

**A conferência do card 3.9 mediu a coisa certa nas URLs erradas.** Publicar e olhar o log não prova
nada; o roteiro do §10, feito a olho, também não — as duas telas são idênticas e a versão anterior
funciona. O que prova é comparar o que o endereço **público** devolve com o arquivo que acabou de
sair do build.

### A correção tem duas metades, e a segunda é a que dura

**1. Configuração (painel do Cloudflare, só Irineu).** Em cada projeto de Pages: Workers & Pages →
projeto → Settings → Builds & deployments → **Production branch** — `develop` no
`gestao-im360-homolog` e `main` no `gestao-im360`. Depois, um `workflow_dispatch` do `deploy-web` em
cada branch e reconferir.

**2. Asserção no `deploy-web.yml` (card 3.9,5).** Passo **depois** de publicar: baixa
`$APP_URL_BASE/main.dart.js` e exige que o sha256 seja o do `build/web/main.dart.js` que acabou de
ser construído. Sem ela a metade 1 se desfaz num clique e ninguém repara — que é exatamente como
este defeito atravessou três cards.

Três decisões do passo, todas para ele não virar um teste instável (card 2.8 §11):

- **seis tentativas com 10 s de espera** — propagação não é instantânea, e asserção que reprova por
  pressa é pior que asserção nenhuma, porque ensina a ignorar vermelho;
- **cache-buster na query** (`?deploy=<sha>&t=<epoch>-<tentativa>`), ainda que o `_headers` mande
  `must-revalidate`: o que se mede aqui é o que o Pages guarda, não o que o navegador guardaria;
- **`curl --compressed`** — o Cloudflare comprime a resposta, e comparar bytes comprimidos com o
  arquivo do build daria diferença sempre. O `--compressed` devolve o conteúdo decodificado.

Só corre em `main` e `develop`: um `workflow_dispatch` de outra branch é preview de propósito, e ali
o endereço público servir outra coisa é o comportamento certo.

### A asserção discrimina — exercitada nos três estados (02/09/2026)

O script do passo foi extraído do YAML e rodado contra os endereços de verdade, antes de a
metade 1 existir:

| Caso | `APP_URL_BASE` | Veredito |
|---|---|---|
| endereço que **tem** o bundle | `develop.gestao-im360-homolog.pages.dev` | ✅ aprova na 1ª tentativa |
| endereço público **com o defeito** | `homolog.gestaoim360.com` | ⛔ reprova (`dea0ec22…` construído × `d2b9569b…` servido) |
| endereço que não responde | host inexistente | ⛔ reprova, com "não respondeu" no resumo |

O primeiro caso é o que importa registrar: sem ele a asserção poderia estar reprovando tudo — e uma
asserção que nunca aprova é tão inútil quanto uma que nunca reprova.

⚠️ **Enquanto a metade 1 não for feita, o `deploy-web` fica VERMELHO nas duas branches.** É
deliberado: vermelho que diz a verdade é melhor que verde que mente, e o resumo da execução traz o
caminho exato do painel. O que estava no ar continua no ar — a asserção não desfaz publicação
nenhuma, ela só recusa a fingir que houve uma.

---

## 6. O achado que mudou o app: fragmento é do Auth

O card 3.7 deixou o app com a estratégia de URL padrão do Flutter web, que põe a rota no
**fragmento** (`/#/alunos`). O Auth do Supabase, nos links que gera **fora do fluxo PKCE do próprio
app**, devolve os tokens **no fragmento**:

```
https://app/#access_token=…&expires_at=…&sb=&token_type=bearer&type=invite
```

O `supabase_flutter` cria a sessão e limpa os parâmetros de auth da URL — mas o `sb=` não está na
lista de parâmetros que ele conhece, então sobra `#sb`. Com a rota no fragmento, o `go_router` lê
`sb` como destino e a pessoa cai em **"Esta tela não existe. Código: /sb"**, já autenticada.

Isso alcança justamente o caminho da v1: **o convite é feito pelo painel** (`acesso-autenticacao.md`
§3.1), e o painel não usa PKCE. Medido em 01/09/2026, com o build de release servido:

| Link | Rota no fragmento (3.7) | Rota no caminho (3.8) |
|---|---|---|
| convite pelo painel | `/sb` → tela não existe¹ | `/acesso` → "sem perfil" ✅ |
| magic link do painel, usuário com perfil | `/sb` → **tela não existe** | `/` → entra ✅ |
| "Esqueci minha senha" no app (PKCE) | funciona | funciona ✅ |
| link direto para `/alunos` | — | abre o app ✅ |

¹ o convidado escapava por acidente: sem perfil, o roteador já o mandava para `/acesso` de qualquer
jeito. Quem **tem** perfil batia na tela de erro.

Por que o fluxo do próprio app não sofria: `resetPasswordForEmail` usa **PKCE**, que devolve
`?code=` na *query* e deixa o fragmento livre. Ou seja, o bug só aparecia no caminho que ninguém
testa — o do painel.

A correção é uma linha (`usePathUrlStrategy()`), e o preço dela é o §3: o servidor passa a precisar
devolver o `index.html` para qualquer caminho. No Pages isso é de graça.

---

## 7. Domínio

`gestaoim360.com` foi **registrado em 01/09/2026** e está na conta Cloudflare, ao lado de
`entrelares.app` e `guardacompartilhada.com`. Divisão: `app.gestaoim360.com` para produção,
`homolog.gestaoim360.com` para homologação.

Em cada projeto de Pages, **Custom domains → Set up a custom domain**. Como a zona já está na conta,
o registro DNS é criado automaticamente e o certificado sai em minutos.

A ordem importa, e é esta:

1. **rebuildar** o ambiente com o `APP_URL_BASE` do endereço definitivo (o valor entra em *build
   time*);
2. publicar esse build;
3. anexar o custom domain ao projeto;
4. só então trocar a **Site URL** no Supabase e acrescentar `https://<endereço>/**` às Redirect URLs.

Inverter 1 e 4 abre uma janela em que a Site URL nova manda a pessoa para um app que ainda monta o
`redirectTo` com o endereço velho — e o link de recuperação morre no meio do caminho, sem erro.

O endereço `*.pages.dev` **não deixa de funcionar** depois do custom domain: os dois servem o mesmo
deploy. Ele deixa de ser o endereço divulgado, e é só o `APP_URL_BASE` que precisa ser o público.

---

## 8. Ajustes que este card deixa

| # | Para | O quê | Peso |
|---|---|---|---|
| 1 | **3.9** | O workflow tem de construir com `--no-web-resources-cdn` e com os três `--dart-define` do ambiente certo, e publicar `app/build/web`. Build sem os `--dart-define` **não falha**: sobe a tela "este build não recebeu a configuração do ambiente" | bloqueante |
| 2 | ~~**3.12**~~ | ~~Acrescentar o host de ingestão do Sentry ao `connect-src` do `_headers`, no mesmo commit que ligar o Sentry — CSP bloqueia sem avisar~~ ✅ **feito em 02/09/2026**, com asserção dos dois lados (`docs/observabilidade.md` §4) | ~~bloqueante~~ |
| 3 | **2.7 / 4.7** | `over_email_send_rate_limit` chega à tela como código cru ("código over_email_send_rate_limit"). É um erro do Auth, não do banco, e o catálogo do card 2.7 §7.1 só cobre os códigos do `DETAIL`. Precisa de texto: "muitos pedidos de e-mail seguidos; espere alguns minutos" | média |
| 4 | **10.1** | Os ícones do PWA e o favicon agora saem da marca (§9). Falta o conjunto de ícones das lojas, que é outro tamanho e outra régua de safe area | baixa |
| 5 | **3.10** | O Worker de "keep alive" do free tier é do card 3.10 e não foi criado aqui; a conta só tem os Workers do Entrelares | informativo |

---

## 9. Marca: o `text-to-path` fechado

O card 1.9 deixou pendente "converter o wordmark em contornos antes de uso externo", e o card 3.7
descobriu que a pendência alcançava o uso interno: `flutter_svg` não renderiza `<text>`. Fechado
aqui, porque é o favicon e o ícone do PWA que este card publica.

Os três arquivos de `assets/marca/` passaram a ter **só geometria** — os glifos vêm da Inter
empacotada no app (`app/assets/fontes/Inter-600.ttf` e `Inter-700.ttf`), convertidos em `path`. Não
depende mais de a fonte existir em quem abre o arquivo, e agora renderizam em qualquer visualizador,
`flutter_svg` incluído. Para reeditar: mudar o texto e **regerar**, nunca editar o `d` à mão.

De `gestao-im360-simbolo.svg` saíram, renderizados em Chromium:

- `app/web/favicon.png` (32×32);
- `app/web/icons/Icon-192.png` e `Icon-512.png` — o símbolo com o quadrado arredondado;
- `app/web/icons/Icon-maskable-192.png` e `Icon-maskable-512.png` — fundo `#171C26` sangrando até a
  borda e o desenho a 78% do lado, dentro da zona segura que o Android recorta.

Os cinco eram os do `flutter create` — quadrado azul do Flutter — até este card.

---

## 10. Conferência depois de publicar

Roteiro curto, na ordem em que as coisas quebram:

1. abrir a URL pública: tem de aparecer a tela de login, **não** uma tela branca (branco = CanvasKit
   externo, §1) e **não** a tela "este build não recebeu a configuração do ambiente" (§8, ajuste 1);
2. abrir `<url>/alunos` direto na barra de endereço: tem de abrir o app (leva ao login se não houver
   sessão), **não** um 404 do Cloudflare — se der 404, apareceu um `404.html` ou um `_redirects`;
3. `curl -I <url>` e conferir `Content-Security-Policy` e `Cache-Control` na resposta;
4. entrar com um usuário de verdade e navegar duas telas, de olho no console: **nenhuma** linha
   `Refused to connect` — se houver, falta host no `connect-src`;
5. "Esqueci minha senha" com um e-mail real: o link do e-mail tem de abrir **a tela de nova senha**,
   não a tela inicial. Cair na inicial é a assinatura exata de Redirect URL faltando (§4);
6. convidar um usuário pelo painel e abrir o link: tem de chegar em "seu acesso ainda não foi
   liberado", nunca em "Esta tela não existe" (§6).

O passo 5 é o que ninguém faz e o que mais dói depois — é o único que exercita a configuração que
não está no repositório.

⚠️ **Este roteiro pressupõe que o endereço público está servindo o que o CI publicou, e isso não se
supõe: se afere.** Foi essa suposição que deixou o defeito do §5.9 atravessar três cards. Quem
afere é o `deploy-web`, no passo de asserção depois de publicar — se ele ficou verde, o roteiro
acima está olhando o build certo; se ficou vermelho, **não adianta rodar o roteiro**, porque a tela
que abrir é a da versão anterior.

---

## 11. SMTP: o que ficou configurado (02/09/2026)

O item que o card 3.5 §7 marcou como pendência, fechado com **Resend** — o mesmo provedor que Irineu
já usa em outro projeto. Dois fatos que evitaram trabalho à toa:

- **O free tier aceita 3 domínios, não 1.** A conta existente comportou `gestaoim360.com` ao lado do
  domínio do outro projeto: nem conta nova, nem conector novo. Limites: 100 e-mails/dia, 3.000/mês,
  SMTP incluído.
- **Nada disso toca a raiz do domínio.** O DKIM fica em `resend._domainkey`, e o SPF e o MX em
  `send.gestaoim360.com`. Se um dia a escola puser e-mail próprio em `gestaoim360.com` (Google
  Workspace, por exemplo), os dois convivem sem conflito de SPF nem de MX.

Configuração nos dois projetos Supabase (Authentication → Emails → SMTP Settings):

```
Host:          smtp.resend.com
Port:          465
Username:      resend
Password:      <API key do Resend — só no painel, nunca no repositório>
Sender email:  nao-responda@gestaoim360.com
Sender name:   Gestão IM360        (em dev: "Gestão IM360 (Dev)")
```

O nome de remetente diferente em dev não é enfeite: os dois ambientes mandam do **mesmo endereço**, e
sem isso não há como saber, olhando a caixa de entrada, qual deles pediu a recuperação.

`nao-responda@` não precisa existir como caixa — o Resend assina pelo domínio. Quem responder ao
convite fala com o vazio; se um dia isso incomodar, o Email Routing do Cloudflare resolve de graça e
independente disto.

⚠️ **O teto de 100/dia é do Resend, e o do Auth é outro.** Não adianta o provedor aguentar se o
`Rate limits` do Supabase estiver segurando antes — conferir os dois antes de um dia de cadastro da
equipe inteira. Foi o teto do Auth, e não o do provedor, que apareceu na tela durante os testes deste
card (§8, ajuste 3).

---

## 12. O que a execução ensinou (01–02/09/2026)

Três coisas que o contrato não previa e que ficam para quem repetir isto:

1. **O custom domain não sobe junto com o deploy.** A homologação foi publicada com o bundle novo —
   que já monta o link de recuperação para `homolog.gestaoim360.com` — antes de o domínio ser
   anexado. O login por senha continuou funcionando, então **nada na tela denunciava**: só a consulta
   de DNS (NXDOMAIN) mostrou que o link do e-mail levava a lugar nenhum. A ordem do §7 existe por
   isso, e o passo 3 é o que se esquece.
2. **Projeto Supabase novo já vem com `http://localhost:3000`** na Site URL e nas Redirect URLs. Foi
   o que fez o primeiro convite de homologação apontar para a máquina local. Em produção as duas
   entradas saem.
3. **A única prova de que a lista de Redirect URLs está certa é seguir o link.** Lista errada não dá
   erro: devolve a Site URL. Na conferência, o `redirect_to` do e-mail entregue foi seguido nos dois
   ambientes e o `Location` caiu em `/redefinir-senha` — se tivesse caído na raiz, a lista estaria
   errada e a tela não diria nada.
