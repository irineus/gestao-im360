# Backup e restauração — card 3.11

Fonte do backup, como `docs/worker-vigia.md` é a do vigia e `docs/ci-cd.md` a do pipeline.

Entregáveis: `.github/workflows/backup-semanal.yml`, `backup/restaurar.sh` e
`backup/conferir-restauracao.sh`.

---

## 1. O que ele é, e o que ele também é

Um workflow agendado que, todo domingo às 06:30 de São Paulo, tira um dump do projeto Supabase de
**produção**, **restaura esse dump num banco vazio e confere o resultado**, e só então publica os
arquivos num bucket R2, mantendo as 12 cópias mais recentes.

O segundo papel é o que o card 3.10 registrou e não deve se perder: **este backup é o segundo
observador do vigia**. O vigia mora no Cloudflare e olha os dois Supabase todo dia, mas *vigia que
morre não avisa* — Worker apagado, cron parado, problema na conta, e o silêncio é idêntico ao de
tudo funcionando. O backup roda em **outra infraestrutura** (GitHub) e fala com produção por **outro
caminho** (Postgres pelo pooler, não PostgREST). Por isso:

> ⚠️ Quando o `backup-semanal` fica vermelho, a leitura não é "o backup não saiu". É **"o backup não
> saiu **e** produção pode ter pausado"**. Confira as duas coisas, nesta ordem: painel do Supabase
> primeiro, log do workflow depois.

É um observador **fraco** de propósito: semanal, e só de produção (homologação fica com o vigia). Um
*dead man's switch* de verdade continua fora do escopo da v1.

---

## 2. O que se copia — e a divergência com a nota do card

A nota do board pede `pg_dump`. O que o workflow roda é **`supabase db dump`**, que é o `pg_dump`
rodando dentro de um contêiner com a versão de servidor certa. Dois motivos, os dois medidos em
outros cards deste projeto:

1. **Versão do cliente.** O Ubuntu do runner traz cliente PostgreSQL 16; produção é 17. `pg_dump` 16
   contra servidor 17 **recusa de saída** — não é silencioso, mas é um dia de trabalho para
   descobrir que a correção é instalar o PGDG.
2. **Uma ferramenta só.** O card 3.9 fixou que "a mesma versão do CLI roda a suíte e aplica a
   migração, porque testar com um CLI e aplicar com outro é testar outro caminho". Backup com uma
   terceira ferramenta seria o mesmo erro. `supabase db dump` também resolve sozinho o endereço do
   pooler (IPv4) que a nota do card pedia à mão, pelo mesmo `supabase link --project-ref` que o
   `db-migrations` já usa contra produção com sucesso desde 01/09/2026 — **nenhum secret de conexão
   novo**.

São três arquivos, que é o caminho de backup documentado pelo Supabase:

| Arquivo | Conteúdo | Papel na restauração |
|---|---|---|
| `roles.sql.gz` | papéis **próprios** do banco — hoje **nenhum**, ver §8 | só se o destino for um Postgres cru, fora do Supabase |
| `schema.sql.gz` | estrutura dos schemas de aplicação | aplicado primeiro |
| `data.sql.gz` | dados (`COPY`) | aplicado por último |
| `MANIFESTO.txt` | data, commit de `main`, migrações, tamanhos, resultado do ensaio | leitura humana |

### O schema já tinha backup; o dado é que não tinha

Vale dizer em voz alta, porque muda a leitura do risco: **a estrutura deste sistema já está copiada
em três lugares** — `supabase/migrations/` no Git, no GitHub e em qualquer clone. O que o R2 guarda e
o Git não guarda é **o dado**. O `schema.sql` vai junto mesmo assim, e não por simetria: ele é a foto
do que estava *realmente* em produção naquele domingo, e o dia em que ele divergir das migrações é o
dia em que alguém aplicou SQL à mão — exatamente o que a conferência do §4 denuncia.

Consequência prática, hoje: produção contém **só dado de configuração** (decisão de 02/09/2026), todo
ele vindo de migração. Enquanto isso durar, uma restauração de verdade é "projeto novo + migrações
pelo CI". O backup passa a valer de verdade **depois do cutover** (card 9.7), quando a carga da
planilha entrar em produção.

---

## 3. Onde vai parar

- Bucket R2 `gestao-im360-backup`, prefixo `producao/<AAAA-MM-DD>/`.
- Retenção: **12 cópias semanais ≈ 3 meses**. Corrupção silenciosa não se descobre na semana em que
  acontece; um mês de histórico devolveria só cópias já contaminadas.
- Acesso pela API S3 do R2 (`aws s3`), e não por `wrangler r2 object put`: o wrangler publica objeto
  mas **não lista** objeto, e sem listar não há retenção.
- ⚠️ O aws-cli v2 recente manda cabeçalhos de checksum que o R2 recusa, com um erro de assinatura que
  não fala de checksum nenhum. Por isso o workflow exporta
  `AWS_REQUEST_CHECKSUM_CALCULATION=when_required` e `AWS_RESPONSE_CHECKSUM_VALIDATION=when_required`.

---

## 4. O ensaio de restauração — toda semana, não uma vez por ano

O card 2.8 §15 pôs "backup restaurado em teste" como pré-condição do go-live, com a frase que
resume tudo: **backup nunca restaurado não é backup**. Aqui isso deixa de ser ritual e vira asserção
semanal, no mesmo job que produz o backup:

1. `supabase start` + `supabase db reset` → um Postgres do Supabase com as migrações de `main`
   aplicadas. **Este é o alvo**, e é o destino real de uma restauração neste projeto: projeto novo,
   migrações pelo CI, dado por cima. Dele sai também a **lista de tabelas que o repositório diz que
   produção tem**.
2. `backup/conferir-schema.sh` → o `schema.sql` é **conferido, não aplicado** (ver o porquê logo
   abaixo).
3. `truncate` em todas as tabelas de `public`, em `auth.users` e em
   `supabase_migrations.schema_migrations` → o alvo fica **vazio**. Sem isso, uma tabela que o dump
   *não* trouxesse continuaria com as linhas do seed e passaria na conferência.
4. `backup/restaurar.sh dump <url> --somente-dados` → `data.sql`, com `ON_ERROR_STOP=1` e
   `--single-transaction`: ou entra tudo, ou não entra nada. Restauração parcial é a pior das três
   hipóteses, porque parece sucesso.
5. `backup/conferir-restauracao.sh` → as asserções.

### Por que `schema.sql` é conferido e `data.sql` é restaurado

Porque **a estrutura já tem backup e o dado não tinha** (§2). A restauração de verdade parte de um
projeto Supabase novo com as migrações aplicadas, e o que falta ali é exatamente o que o Git não
guarda. Aplicar o `schema.sql` num banco criado do zero não é sequer possível — ele conta com a
casca do Supabase (`extensions`, `auth`, `storage`, `vault`), que é criada **por banco** e não por
cluster; foi assim que a primeira versão deste ensaio morreu (§8).

E o `schema.sql` continua tendo uma asserção própria, que é para o que ele serve: comparado com as
migrações de `main`, ele denuncia **tabela que existe em produção e não vem de migração nenhuma** —
SQL aplicado à mão, contra a regra inegociável do `CLAUDE.md`, e não há mais nada no projeto que
denunciaria isso.

**As asserções são positivas**, pela mesma razão que o vigia não se contenta com "não deu erro" e
que o card 2.8 (b) recusa "a view não levantou exceção":

| # | Asserção | Sobre o quê | O que ela pega |
|---|---|---|---|
| 1 | `schema.sql` declara tabela em `public` | o backup | dump que saiu com 0 e trouxe só o cabeçalho |
| 2 | **comparação simétrica** entre `schema.sql` e as migrações de `main` | o backup | schema truncado (falta) **e** SQL aplicado à mão em produção (sobra) |
| 3 | `data.sql` restaura sem erro num alvo vazio | o backup | dump inconsistente, ordem de FK quebrada, arquivo truncado no meio |
| 4 | `unidade`, `perfil`, `permissao`, `perfil_permissao` e `parametro` com linha **depois do truncate** | o backup | dump de schema sem dado — o jeito mais comum de um backup ser inútil |
| — | contagem de `auth.users`, `usuario` e `supabase_migrations` | medição | responde o §5: zero em `supabase_migrations` significa que o histórico não vem no dump |

Ponto de referência do que essas asserções esperam encontrar, medido no projeto **dev** em
02/09/2026 (produção tem as mesmas quatro migrações aplicadas): 7 tabelas em `public`, `permissao`
50, `perfil_permissao` 123, `parametro` 16, `perfil` 4, `unidade` 1, `auth.users` 1 e
`supabase_migrations.schema_migrations` 4. Nenhum desses números está escrito no script — todos são
lidos do próprio banco restaurado e comparados com o repositório, senão a conferência ficaria
vermelha no dia em que a fase 4 criar a primeira tabela de negócio.

**A ordem dos passos é decisão, não acaso: dump → ensaio → publicação.** Publicar antes de conferir
faria um dump quebrado ocupar uma das 12 vagas da retenção e, semana após semana, **empurrar para
fora as cópias boas** — o backup se destruiria sozinho, em silêncio. Um ensaio reprovado custa a
cópia daquela semana e um e-mail de falha; as 11 anteriores continuam lá.

⚠️ E **nenhum passo deste workflow usa `|| true`**. Erro engolido produz backup vazio publicado com
cara de sucesso, que é pior do que não ter backup — porque ninguém procura o que acredita ter.

### Por que a conferência é contra `main`, sempre

O workflow faz `checkout` com `ref: main`, inclusive num `workflow_dispatch` disparado de outra
branch. Produção é `main`, e este projeto vive com `develop` à frente: comparar um backup de produção
contra uma branch com migração ainda não promovida ficaria vermelho por um motivo que não tem nada a
ver com o backup — e alarme falso recorrente é como se ensina a ignorar o alerta de verdade.

---

## 5. Restaurar de verdade

O procedimento **é o mesmo script** que roda no ensaio de domingo, e é isso que o impede de
envelhecer calado: se ele parar de funcionar, o backup fica vermelho antes de alguém precisar dele.

```bash
# 1. Baixar a cópia desejada do R2
aws s3 cp s3://gestao-im360-backup/producao/2026-10-04/ ./restauracao/ --recursive \
  --endpoint-url "https://<CLOUDFLARE_ACCOUNT_ID>.r2.cloudflarestorage.com"
cat restauracao/MANIFESTO.txt   # confira data, commit e o resultado do ensaio daquele dia

# 2. Criar um projeto Supabase NOVO e aplicar as migrações nele pelo CI
#    (supabase link --project-ref <ref-novo> && supabase db push) — a ESTRUTURA
#    vem do Git, sempre; o backup traz o DADO.

# 3. Restaurar o dado por cima (nunca por cima de um banco que já tenha dado)
backup/restaurar.sh restauracao "postgresql://postgres.<ref>:<senha>@<pooler>:5432/postgres" --somente-dados

# 4. Conferir
backup/conferir-restauracao.sh "postgresql://postgres.<ref>:<senha>@<pooler>:5432/postgres"
```

Depois disso, apontar o app para o projeto novo é trocar `SUPABASE_URL`/`SUPABASE_ANON_KEY` nos
secrets e republicar (`docs/ci-cd.md` §7), e refazer no painel do Auth a lista de Site URL e Redirect
URLs (`docs/deploy-web.md` §4) e o SMTP — **configuração de painel não está em backup nenhum**.

Três coisas que o dump não traz e que precisam de um passo humano:

- **Configuração do painel do Auth e SMTP** (acima).
- **Segredos do Vault** (credenciais de PC, card 2.9): `vault.secrets` é cifrado com uma chave do
  projeto, então cópia restaurada em projeto novo não decifra. Na prática isso não é perda: a
  política do card 2.9 já prevê rotação das contas nas máquinas, e o §6 daquele documento registra
  que a cifra protege backup e vazamento, não o administrador do banco.
- **Histórico de migrações** (`supabase_migrations.schema_migrations`) — **medido em 02/09/2026: não
  vem no dump.** Isso deixou de ser um problema no momento em que o passo 2 acima passou a ser
  "aplicar as migrações pelo CI": é o próprio `db push` que grava o histórico, então ele nasce certo
  no projeto novo. Só faria falta em quem tentasse restaurar aplicando o `schema.sql` — e é
  justamente esse caminho que este documento não recomenda. A conferência semanal continua imprimindo
  a contagem, porque o dia em que ela deixar de ser zero é o dia em que este parágrafo virou obsoleto.
- **`storage`** — o dump **traz** as tabelas de `storage`, mas nunca os arquivos: eles vivem fora do
  Postgres. Hoje isso não custa nada, porque este sistema não usa Supabase Storage; ver o limite no §7.

---

## 6. O que só Irineu configura

| Onde | Nome | Para quê |
|---|---|---|
| Cloudflare R2 | bucket `gestao-im360-backup` | destino das cópias (grátis até 10 GB) |
| Secret do repositório | `R2_ACCESS_KEY_ID` | token R2 com *Object Read & Write*, escopo do bucket |
| Secret do repositório | `R2_SECRET_ACCESS_KEY` | idem — só aparece uma vez, na criação |

Reaproveitados, já existentes: `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD_PROD` e
`CLOUDFLARE_ACCOUNT_ID` (que também é o subdomínio do endpoint S3 do R2).

Enquanto os três não existirem, o workflow **falha no primeiro passo**, nomeando exatamente o que
criar — o mesmo padrão do `deploy-web` e do `deploy-worker-vigia`.

⚠️ O token do R2 é **outro** token, e não o `CLOUDFLARE_API_TOKEN` de Pages e Workers: o R2 emite um
par de chaves no formato S3, que é o que o `aws s3` consome.

### Este workflow não passa pelo environment `prod` — de propósito

O *required reviewer* do environment `prod` é o portão certo para tudo que **muda** produção:
migração, deploy do app, publicação do vigia. Backup só **lê**. Posto atrás do portão, todo domingo
de manhã o job ficaria em `waiting` esperando um clique que ninguém dá no fim de semana, e **backup
que espera aprovação é backup que não acontece**. A senha de produção é secret do repositório, então
nada aqui depende de environment.

---

## 7. Limites assumidos

- ⚠️ **O observador tem o seu próprio modo de falha silencioso.** O GitHub **desativa workflow
  agendado em repositório com 60 dias sem commit** — avisa por e-mail uma vez e o backup
  simplesmente deixa de acontecer, sem nada vermelho em lugar nenhum. Hoje o repositório tem commit
  todo dia e o risco é teórico; ele vira real justamente quando o desenvolvimento parar, isto é,
  quando o sistema estiver em produção e o backup importar. Mitigação de verdade seria alguém de
  fora olhar a idade do objeto mais novo no R2 — anotado como ajuste para o card 3.12.
- **Semanal, e só de produção.** Perda máxima aceita: 7 dias. Homologação não é copiada: o dado dela
  é recarregável pelo importador do card 9.1.
- **Aviso de falha é o e-mail padrão do GitHub** para workflow agendado que falha, e ele chega a
  quem alterou o cron por último — não a uma lista. Enquanto o projeto tiver um mantenedor só, isso
  basta; quando tiver mais, vira card.
- **A janela entre o dump e a conferência.** As contagens são lidas do banco restaurado, não de
  produção, então não há corrida — mas o dump em si não é um instantâneo transacional dos três
  arquivos: `schema.sql` e `data.sql` são duas conexões. Com escrita concorrente rara (uma escola,
  domingo de manhã) o risco é aceito e escrito aqui em vez de resolvido.
- **O ensaio restaura `public` e `auth`, não `storage`.** O arquivo do backup continua completo — o
  que é filtrado é o que se aplica no ensaio. O alvo do CI não hospeda o schema `storage` (o
  `supabase start` deste workflow exclui o `storage-api`), e incluí-lo só trocaria esse erro por uma
  divergência de versão entre o storage de produção e o da imagem fixada, que ficaria vermelha sem
  dizer nada sobre o backup. Não é perda hoje: este sistema **não usa Supabase Storage**, e um dump
  SQL de `storage.objects` é metadado de arquivos que o dump não carrega — ensaiá-lo daria a ilusão
  de cobrir o que ele não cobre. ⚠️ **No dia em que o sistema passar a guardar arquivo, isto vira
  dívida**: o backup de Storage é outro mecanismo, não este.
- **Restauração não é ensaiada contra o Supabase de verdade**, só contra um Postgres do stack local
  com os mesmos papéis e a mesma versão maior (17). Um projeto Supabase novo tem mais coisa
  (extensões pré-instaladas, `auth` já criado pelo GoTrue); o ensaio prova que os arquivos são
  aplicáveis e completos, não que o painel do projeto novo estará configurado.

---

## 8. O que a estreia ensinou (02/09/2026)

Primeiro `workflow_dispatch`, run `33628486024`, logo depois de Irineu criar o bucket e os dois
secrets.

**O que funcionou de primeira, e não era pouco.** O `supabase link --project-ref` alcançou produção,
o CLI baixou a imagem `ghcr.io/supabase/postgres:17.6.1.166` — a mesma versão do servidor, que é
justamente o problema que o §2 explica — e os três dumps saíram limpos. Ou seja: a conexão pelo
pooler, as credenciais e a versão do cliente, que eram as três incógnitas técnicas do card, estão
resolvidas e medidas.

**⚠️ `--role-only` num projeto Supabase não dumpa os papéis da plataforma — e o piso reprovou um
fato.** `roles.sql` saiu com **370 bytes**, só cabeçalho, e o passo de piso de tamanho, com um limite
único de 512 bytes para os três arquivos, marcou a execução como vermelha. O arquivo está **certo**:
`--role-only` dumpa os papéis **próprios** do banco, e este projeto não criou nenhum — `anon`,
`authenticated`, `service_role` e `supabase_admin` são geridos pela plataforma e não pertencem a
este backup (num destino Supabase eles já existem, que é o motivo pelo qual o ensaio do §4 não
aplica `roles.sql`).

A lição não é "afrouxar o piso": é que **um piso genérico não sabe o que cada arquivo significa**, e
uma guarda que não distingue verdade de defeito produz alarme falso — o mesmo desfecho de não ter
guarda, porque se aprende a ignorá-la. O piso passou a ser **por arquivo**, com o significado escrito
ao lado: `schema.sql` e `data.sql` mantêm os 512 bytes, e `roles.sql` só precisa existir. Ele
continua no backup porque o dia em que crescer é o dia em que alguém criou um papel próprio — e aí
ele passa a ser necessário para restaurar.

Segundo ajuste do mesmo passo: o laço **parava no primeiro arquivo**, então o log da estreia mostrou
370 bytes de `roles.sql` e nada sobre os outros dois. Relatório que esconde o estado do resto obriga
a rodar de novo só para saber o resto; agora ele mede os três e reprova no fim.

**⚠️ Segunda execução: um banco criado do zero não é um projeto Supabase novo.** Com o piso
corrigido, o ensaio rodou pela primeira vez e morreu em
`psql:dump/schema.sql:20: ERROR: schema "extensions" does not exist`.

O erro desmonta uma premissa que estava escrita neste próprio documento: *"os papéis já existem,
porque papel é objeto de cluster"*. Verdade para **papéis** — e falso para **schemas**. `extensions`,
`auth`, `storage`, `graphql` e `vault` são criados **por banco**, não por cluster, então um
`createdb` dentro do Postgres do Supabase é um banco **cru** dentro de um projeto Supabase, e não um
projeto novo. O `schema.sql` do CLI, por sua vez, é escrito para um destino que já tem essa casca:
ele emite `CREATE EXTENSION … WITH SCHEMA "extensions"` e não cria o schema. (Conferido no dev:
`pgcrypto`, `uuid-ossp` e `pg_stat_statements` moram em `extensions`; `supabase_vault`, em `vault`.)

A correção não foi criar os schemas que faltavam à mão — seria uma lista adivinhada, que envelhece
sem avisar. Foi trocar o alvo pelo **destino real de uma restauração neste projeto**: um banco com as
migrações de `main` aplicadas (o que `supabase db reset` produz), esvaziado, recebendo **só o
`data.sql`**. Isso alinha o ensaio com o que o §2 já dizia e ninguém tinha levado até o fim — *a
estrutura já tem backup, chama-se `supabase/migrations/`; o que o R2 guarda é o dado*. O `schema.sql`
ganhou a asserção que lhe cabe, de comparação, em `backup/conferir-schema.sh`.

**⚠️ Terceira execução: o alvo do CI não hospeda tudo o que o dump traz.** Com o alvo corrigido, o
`schema.sql` passou na comparação, o `truncate` rodou, **todas as COPYs de `auth` entraram** — o que
de passagem prova que não há divergência de versão entre o Auth de produção e o do stack local — e a
restauração parou em `relation "storage.buckets" does not exist`, porque o `supabase start` deste
workflow exclui o `storage-api`.

A saída foi filtrar o que se **aplica** no ensaio (`--apenas-schemas public,auth`) sem tocar no que
se **guarda**: o arquivo do backup continua completo. Incluir o `storage-api` no stack seria a
correção óbvia e é pior — trocaria este erro por uma divergência de versão entre o storage de
produção e o da imagem fixada, vermelha sem dizer nada sobre o backup. E não é perda: um dump SQL de
`storage.objects` é metadado de arquivos que o dump não carrega (§7).

O filtro rendeu ainda uma armadilha de escape que vale registrar, porque é da família das caladas: a
linha que encerra um bloco `COPY` é *contrabarra seguida de ponto*, e escrita como literal ela
atravessa as camadas de escape do shell, do `awk` e do YAML — bastou uma delas comê-la para o filtro
**parar de reconhecer o fim do bloco e engolir todo o resto do arquivo em silêncio**, restaurando
menos da metade dos dados sem erro nenhum. Foi pego exercitando o filtro na máquina, com um arquivo
de mentira, antes de subir. Agora o delimitador é montado com `sprintf("%c.", 92)`.

**A radiografia respondeu de graça a pergunta que estava aberta desde o §5:** `data.sql` cobre
`auth.*` (inclusive `users`), as sete tabelas de `public` e `storage.*`, e **não** cobre
`supabase_migrations`. Como o procedimento de restauração aplica as migrações pelo CI, que é quem
grava esse histórico, a ausência deixou de importar.

Entrou junto um passo de **radiografia do dump** (nomes de schema, extensão e tabela; nunca valores),
para que a próxima surpresa seja diagnosticável na mesma execução em vez de exigir uma rodada só para
descobrir o que o arquivo contém.

---

## 9. Ajustes que este card deixa

| # | O quê | Onde | Bloqueante |
|---|---|---|---|
| 1 | ~~Criar o bucket R2 e os dois secrets do §6~~ | ✅ feito 02/09/2026 por Irineu | resolvido |
| 2 | Exercitar o `workflow_dispatch` até o verde e registrar o que a execução ensinou — a estreia está no §8; falta o ensaio de restauração rodar, e com ele a resposta sobre `supabase_migrations` | card 3.11 | sim |
| 3 | Vigiar a **idade do backup mais novo no R2** a partir do vigia (Cloudflare), fechando o modo de falha do §7 — exige binding de R2 no Worker | card 3.12 | não |
| 4 | Pré-condição do go-live "backup restaurado em teste" (card 2.8 §15) passa a ser satisfeita pelo ensaio semanal; conferir a redação do critério | card 9.7 | não |
| 5 | Depois do cutover, reavaliar frequência e retenção com dado de negócio em produção | card 9.8 | não |
