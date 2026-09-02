# Vigia — Worker Cloudflare agendado (card 3.10)

Fonte do vigia, como `docs/ci-cd.md` é a fonte do pipeline e `docs/deploy-web.md` a do contrato de
publicação. Código em `worker-vigia/`, publicação em `.github/workflows/deploy-worker-vigia.yml`.

---

## 1. O que ele faz, e por que é uma coisa só

Projeto Supabase do plano gratuito **pausa depois de 7 dias sem atividade** (Decisões vigentes §1,
"Free tier"; risco 1 do plano §4). Projeto pausado não é banco indisponível: é o **app fora do ar** —
login, telas, tudo. A mitigação decidida no plano é uma requisição leve por dia.

O vigia faz essa requisição e, com a **mesma** requisição, vigia:

| | |
|---|---|
| **Mantém acordado** | um `select` por dia em cada um dos dois projetos conta como atividade |
| **Vigia** | se a resposta não for a esperada, manda e-mail |

As duas metades não são funcionalidades separadas empilhadas por conveniência. Elas se verificam:
**se o `select` diário não estiver evitando a pausa, quem descobre é o próprio vigia**, no dia em que
a resposta deixar de vir. Não há como a mitigação falhar em silêncio — que é o desfecho normal de uma
mitigação que ninguém confere, e que este projeto já catalogou meia dúzia de vezes.

Existe **um** vigia para os **dois** ambientes, e não um por ambiente: o que se vigia é o par. Por
isso ele é publicado só a partir de `main`, com o portão humano do environment `prod`.

---

## 2. A sonda: o que ela pergunta, e o que a resposta prova

```
GET https://<projeto>.supabase.co/rest/v1/parametro?select=chave&limit=1
     apikey: <chave publicável>
     Authorization: Bearer <chave publicável>
```

**A resposta certa é `[]`, e isso é a especificação, não um sintoma.** O papel `anon` não satisfaz
nenhuma política de `select` (card 3.4), então a RLS devolve zero linhas — como devolve para qualquer
não-autenticado, em qualquer tabela. O que a resposta prova é o que interessa aqui: **o PostgREST
executou uma consulta num Postgres vivo**. Sem banco de pé ele não responde 200 — devolve 503 —, e
projeto pausado não responde nem isso.

Medido em 02/09/2026, contra o projeto de desenvolvimento:

| Requisição | Resposta | Vem de onde |
|---|---|---|
| sonda com chave válida | `200` `[]` | Postgres (a RLS avaliou e devolveu zero linhas) |
| chave inválida | `401` `{"message":"Invalid API key"}` | gateway |
| sem chave nenhuma | `401` `{"message":"No API key found in request"}` | gateway |
| tabela inexistente | `404` `PGRST205` | cache de schema do PostgREST — **não** toca o banco |
| `rpc/fn_hoje` com `anon` | `401` `42501 permission denied for function` | Postgres |

A última linha explica por que a sonda é um `select` e não uma RPC: **todas** as funções do projeto
são `revoke ... from anon` por decisão do card 3.4, e está certo que sejam. Abrir uma função só para
o vigia seria abrir a primeira porta anônima do sistema para ganhar um `"2026-09-02"` em vez de um
`[]` — preço alto por uma asserção um pouco mais bonita.

**A asserção é positiva: `200` *e* corpo que é uma lista JSON.** É a diferença que faz o vigia valer
alguma coisa. Um vigia que aceitasse "não deu erro" passaria numa página de manutenção servida com
200 por um intermediário — e modo de falha que ninguém previu continua reprovando aqui, porque não
precisa ser previsto.

Cabeçalhos: os dois de propósito. A chave publicável (`sb_publishable_…`, que é a que os dois
ambientes usam hoje) funciona só com `apikey`; a chave legada é um JWT e é o `Authorization` que lhe
dá o papel. Mandar os dois vale para as duas — medido.

**Três tentativas, 1,5 s entre elas**, antes de considerar falha. Uma falha isolada de rede não é
notícia, e e-mail que chega sem motivo é e-mail que se aprende a ignorar — o mesmo desfecho de não
ter alerta nenhum.

---

## 3. Configuração — o que só Irineu faz

| Onde | Nome | Para quê |
|---|---|---|
| Secret do repositório | `CLOUDFLARE_API_TOKEN` | ⚠️ o token do card 3.9 foi criado para o Pages; precisa **ganhar** a permissão *Workers Scripts — Edit* |
| Secret do repositório | `CLOUDFLARE_ACCOUNT_ID` | já existe (card 3.9) |
| Secret do repositório | `SUPABASE_ANON_KEY_DEV` | chave publicável do projeto dev |
| Secret do repositório | `SUPABASE_ANON_KEY_PROD` | chave publicável do projeto prod |
| Secret do repositório | `RESEND_API_KEY` | conta Resend do card 3.8, para o alerta |

As duas chaves publicáveis são as **mesmas** que já estão nos environments `dev` e `prod` como
`SUPABASE_ANON_KEY`. Aqui precisam de nome distinto e escopo de repositório por um motivo prático:
**um job enxerga um environment só**, e este precisa das duas ao mesmo tempo. São públicas por
desenho (vão no bundle que qualquer visitante baixa) e ficam em secret pelo mesmo motivo do card 3.9:
rotacionar não pode exigir um commit.

Sem qualquer uma delas o workflow **falha no primeiro passo**, nomeando o que criar. Sem a permissão
de Workers no token, quem falha é o `wrangler deploy`, com um `Authentication error [code: 10000]`
que não diz o que falta — por isso está escrito aqui.

`ALERTA_PARA` **não** é segredo: está em `wrangler.toml`, com o mesmo endereço que o seed do card 3.6
já grava em `parametro.direcao_inicial_email`, num repositório público.

---

## 4. O alerta

Sai **um e-mail por execução** (não um por tentativa nem um por ambiente), pelo Resend, de
`Gestão IM360 (Vigia) <nao-responda@gestaoim360.com>` — o nome distingue o vigia do app, como o nome
do remetente já distingue dev de prod na caixa de entrada (card 3.8 §11).

O texto carrega o que a sonda viu (status e corpo de cada tentativa), a hora **em São Paulo** — hora
em UTC mandaria alguém procurar log na hora errada — e o que verificar, nesta ordem:

1. **projeto pausado?** Painel do Supabase → *Restore project*. Pausado é o app fora do ar;
2. **chave rotacionada?** Então o alerta é falso e o secret `SUPABASE_ANON_KEY_*` precisa ser
   atualizado junto com o bundle publicado;
3. fora isso, indisponibilidade do Supabase.

Três decisões sobre o alerta, todas do mesmo tipo — preferir o barulho ao silêncio:

- **`RESEND_API_KEY` é conferida no início de TODA execução**, e não quando faz falta. Ausente, a
  execução falha alto no primeiro dia. Conferida só na hora de alertar, a ausência apareceria
  justamente no dia em que o alerta precisasse sair.
- **Alerta que não sai derruba a execução**, com as duas informações na mensagem (o que falhou e por
  que o e-mail não foi). Das duas falhas, essa é a cara: a primeira alguém ainda descobre abrindo o
  app, a segunda ninguém descobre nunca.
- **Falha deixa a execução vermelha no painel do Cloudflare**, mesmo com o e-mail enviado — segundo
  sinal, para o caso de o e-mail se perder.

Enquanto o problema durar, chega um e-mail por dia por ambiente. É deliberado: silêncio no dia
seguinte é o sinal de que voltou. O vigia **não guarda estado** — não avisa recuperação e não sabe há
quantos dias está ruim.

---

## 5. Rodar e conferir na máquina

```bash
# suíte (sem dependência nenhuma: não há npm install)
node --test "worker-vigia/test/**/*.test.mjs"

# as duas sondas de verdade, com as chaves na mão
SUPABASE_ANON_KEY_DEV=… SUPABASE_ANON_KEY_PROD=… node worker-vigia/conferir.mjs

# o Worker de verdade, no workerd
cd worker-vigia
printf 'SUPABASE_ANON_KEY_DEV=…\nSUPABASE_ANON_KEY_PROD=…\n' > .dev.vars   # ignorado pelo git
npx wrangler@4.128.0 dev
curl http://127.0.0.1:8787/                       # roda as sondas, NUNCA manda e-mail
curl http://127.0.0.1:8787/cdn-cgi/local/scheduled # roda o cron
```

`conferir.mjs` importa o **mesmo** módulo que o Worker executa — sonda que mudar, muda nos dois. É
ele que o CI roda **antes** de instalar as chaves no Worker: chave trocada ou rotacionada não derruba
nada hoje, produziria um alarme falso por dia, para sempre, e alarme falso recorrente é como se
ensina todo mundo a ignorar o alerta de verdade. Reprovar no deploy é a única hora em que alguém está
olhando.

---

## 6. O que a execução ensinou (02/09/2026)

**1. O workerd recusa o Worker inteiro se o módulo de entrada exportar uma constante.** Com tudo num
arquivo só, `wrangler dev` respondeu:

```
Uncaught TypeError: Incorrect type for map entry 'CAMINHO_SONDA':
the provided value is not of type 'function or ExportedHandler'.
```

Todo export nomeado do `main` precisa ser função ou handler. Daí `src/vigia.js` (constantes e
funções, que a suíte e o `conferir.mjs` importam) e `src/index.js` (só o `export default`). **O modo
de falha é da família cara:** o vigia simplesmente não existiria, e o sintoma seria a *ausência de
e-mail* — que é exatamente o que se espera quando está tudo bem. Virou asserção: um `export const` de
volta em `src/index.js` reprova a suíte.

**2. Sair do Node no meio do desmonte do `fetch` derruba o processo no Windows** (`Assertion failed:
!(handle->flags & UV_HANDLE_CLOSING)`, código 127). `conferir.mjs` usa `process.exitCode` e deixa o
Node terminar sozinho — assim o código de saída é o da sonda, e não o do libuv, nos dois sistemas.

**3. Produção responde, e isso foi medido sem usar credencial nenhuma.** A sessão não conseguiu
sondar o projeto de produção com a chave certa, mas a rodada com chave errada de propósito devolveu
`401 Invalid API key` em ~300 ms — o que já prova que o endereço de produção está no ar e que o
caminho de reprovação funciona com o corpo de erro de verdade.

---

## 7. Limites assumidos

- **Vigia que morre não avisa.** Se o Worker for apagado, se o cron parar de disparar ou se a conta
  Cloudflare tiver problema, nada alerta e o projeto pausa em silêncio. Um *dead man's switch* de
  verdade exige um vigia externo (serviço de terceiros), e isso está fora do escopo da v1. O que
  existe hoje é um segundo observador **incidental**: o backup semanal do card 3.11 roda um `pg_dump`
  contra produção e o GitHub avisa por e-mail quando um workflow agendado falha — semanal, e só de
  produção. Registrado nas Notas do card 3.11.
- **Sem estado**: sem aviso de recuperação, sem "há N dias assim", sem silenciar temporariamente.
- **A eficácia contra a pausa não foi verificada** — só se verifica não pausando durante sete dias.
  O que existe é a decisão do plano e, principalmente, o fato de que o próprio vigia denuncia se ela
  estiver errada.
- **A sonda não mede o app**, só o Supabase. O app no Pages é estático e não pausa; se ele cair, o
  vigia continua verde.

---

## 8. Ajustes que este card deixa

| # | O quê | Onde | Bloqueante |
|---|---|---|---|
| 1 | `CLOUDFLARE_API_TOKEN` precisa da permissão *Workers Scripts — Edit* | Irineu, antes do primeiro deploy do vigia | **sim** — sem ela o `wrangler deploy` falha |
| 2 | Os três secrets novos do repositório (§3) | Irineu | **sim** — o workflow reprova no primeiro passo |
| 3 | O backup do card 3.11 é o segundo observador; anotar lá que a falha dele também significa "produção pode ter pausado" | card 3.11 | não |
| 4 | Quando o Sentry entrar (card 3.12), avaliar mandar a falha do vigia para lá além do e-mail | card 3.12 | não |
