# E-mails do Auth — convite e recuperação de senha

**Card 4.7,6 (03/09/2026).** Fonte dos dois e-mails que o sistema manda. Os arquivos
`supabase/templates/convite.html` e `supabase/templates/recuperacao-senha.html` são o conteúdo; este
documento é o porquê e a lista de conferência.

Antes deste card os dois chegavam **em inglês e sem formatação nenhuma** — o template padrão do
Supabase: "You've been invited", "Accept invitation", um link azul sublinhado. O remetente já era o
certo desde o card 3.8 (Resend, `nao-responda@gestaoim360.com`); o corpo é que nunca tinha sido
tocado.

---

## 1. Só existem dois, e isso é uma decisão

O GoTrue tem seis templates. Estes são os dois que **este** sistema dispara:

| Template | Quando sai | Traduzido |
|---|---|---|
| `invite` | direção convida alguém — pela tela de Administração (Edge Function `convidar-usuario`, card 4.7) ou pelo painel | ✅ |
| `recovery` | "Esqueci minha senha" (`resetPasswordForEmail`, card 3.5) | ✅ |
| `confirmation` | cadastro público | ❌ **não existe**: `enable_signup = false` |
| `magic_link` | login por link | ❌ o app não chama |
| `reauthentication` | reautenticação por código | ❌ o app não chama |
| `email_change` | alguém troca o e-mail de acesso | ❌ **alcançável só pelo painel** — ver §5 |

Traduzir os quatro restantes seria escrever texto que ninguém lê, e texto que ninguém lê envelhece
sem que se saiba. Os que ficaram têm o motivo registrado aqui e no `config.toml`.

---

## 2. A restrição que não se negocia: `{{ .ConfirmationURL }}`

**O link tem de ser `{{ .ConfirmationURL }}`. Nunca `{{ .Token }}` nem `{{ .TokenHash }}`.**

O convite é gerado pela Admin API e volta com a **sessão no fragmento** da URL, junto com
`type=invite`:

```
https://homolog.gestaoim360.com/redefinir-senha#access_token=…&type=invite
```

É esse `type` que `app/lib/main.dart` lê **antes** do `Supabase.initialize` — depois disso o
`supabase_flutter` consome o fragmento, limpa a URL e emite um `signedIn` comum, indistinguível de um
login (card 4.7, `app/lib/config/link_inicial.dart`). Sem ele, o roteador não leva a pessoa à tela de
definir senha, e ela entra **sem senha cadastrada**: exatamente o defeito que o card 3.8 encontrou em
homologação e o 4.7 consertou. Um link montado com token não traz fragmento nenhum.

Ou seja: trocar o link por "elegância" reabre um defeito já pago. O comentário no topo de cada
template diz isso, para quem editar não precisar reconstituir a história.

**Medido em 03/09/2026, no stack local:** o convite chegou com
`…/auth/v1/verify?token=…&type=invite&redirect_to=…` e a recuperação com `type=recovery`. Os dois
`type` presentes no HTML entregue.

---

## 3. Decisões de desenho

**HTML de e-mail não é HTML de página.** Tabelas, estilo **inline**, sem flex, grid, `position` nem
folha externa. O que está em `<head>` sobrevive na maioria dos clientes e o Gmail no Android
descarta — por isso todo estilo que importa está inline, e o `<head>` só carrega `charset`,
`viewport` e as duas dicas de esquema de cor.

**`color-scheme: light` nos dois.** Sem isso, Gmail e Outlook em modo escuro invertem as cores por
conta própria: o cartão branco vira cinza-chumbo e o laranja da marca sai da paleta. A dica resolve
nos clientes que a respeitam; nos outros a inversão continua, e é por isso que **nenhuma informação
depende de cor** nestes e-mails.

**A imagem vai não carregar, e o layout conta com isso.** O convite é o **primeiro contato** do
remetente com a pessoa, e é justamente aí que Gmail e Outlook bloqueiam imagem por padrão. Então:

- a identidade é carregada pela **barra laranja** e pelo título, não pela imagem;
- o `img` leva estilo tipográfico (`font-family`, `font-size:19px`, `font-weight:700`,
  `color:#171C26`) — **isso é para o texto alternativo**: cliente que bloqueia imagem aplica o CSS do
  `img` ao `alt`, e sem isso o nome da marca aparece na serifada padrão do cliente;
- `width` e `height` estão no atributo **e** no estilo, para o espaço não colapsar.

Nunca pôr informação só na imagem.

**A imagem é PNG, e é o wordmark de verdade.** E-mail não renderiza SVG (o Gmail remove, o Outlook
não desenha), e os três arquivos de `assets/marca/` são SVG. O card 3.8 já tinha convertido o
wordmark em contornos (`text-to-path`), então bastou rasterizar:
`app/web/marca/gestao-im360-horizontal.png`, 368×102 (2× do tamanho de exibição, 184 px), 9 KB,
renderizado do `gestao-im360-horizontal.svg` no Chromium — a mesma via dos ícones do card 3.8 §9.
Para regerar, rasterizar de novo do SVG; não editar o PNG.

**Um endereço de imagem para os dois ambientes: o de produção.** Os templates apontam para
`https://app.gestaoim360.com/marca/gestao-im360-horizontal.png` **inclusive em dev**. Assim os dois
templates são byte a byte iguais nos dois projetos, o que torna a conferência do §4 possível — dois
arquivos por ambiente seria a divergência esperando para acontecer. Consequência aceita: **o
logotipo só aparece depois de a promoção que publica o PNG chegar a produção**; até lá sai o texto
alternativo, que é o caso para o qual o layout foi feito.

**Cores, direto do guia de identidade** (`docs/identidade-visual.md`), sem inventar nenhuma:

| Papel no e-mail | Token | Hex | Por quê |
|---|---|---|---|
| Barra do topo | `laranja-500` | `#E2620F` | é a **cor de marca**, e o guia a proíbe como texto e como fundo de botão (3,51:1 contra branco). Elemento gráfico é o papel dela |
| Botão | `laranja-600` | `#BE4E08` | é a cor de **ação** — 4,90:1 com texto branco. O guia manda **não unificar** marca e ação |
| Título | `grafite-900` | `#171C26` | 17,07:1 |
| Corpo | `grafite-700` | `#3A4252` | 10,09:1 |
| Secundário | `grafite-500` | `#656F82` | 5,06:1 |
| Rodapé, link cru | `grafite-400` | `#8B94A6` | só em texto ≥12 px de apoio |
| Fundo, borda, divisor | `grafite-50/200/100` | `#F6F7F9` `#D9DDE5` `#ECEEF2` | decorativos |

**Botão em tabela, não `<a>` com padding.** O Outlook ignora padding em link; sem a tabela o botão
vira texto laranja. Canto arredondado ele não desenha, e isso é aceito.

**O endereço em texto, embaixo.** Cliente que remove links — e webmail corporativo que reescreve
`href` — deixaria a pessoa sem caminho nenhum. Fica no menor corpo do e-mail, e é feio de propósito:
é uma saída de emergência, não um elemento de layout.

**"O link vale 24 horas."** É o `otp_expiry = 86400` do `supabase/config.toml`. ⚠️ **Se aquele número
mudar, esta frase passa a mentir** — os dois templates e o `config.toml` mudam juntos.

**O convite diz que falta definir a senha.** É a mesma correção do card 4.7, agora na única peça que
a pessoa lê antes de clicar: *"Falta um passo: definir a sua senha."* O botão se chama **"Definir
minha senha"**, não "Aceitar convite" — o rótulo diz o que vai acontecer.

**A recuperação diz que ignorar é seguro.** Pedir recuperação não exige prova de identidade nenhuma:
qualquer pessoa que saiba o endereço dispara o envio. Quem recebe sem ter pedido precisa ler que
nada aconteceu — *"sua senha continua a mesma"*.

**Saudação pelo nome, com o outro ramo escrito.** O convite usa
`{{ if .Data.nome }}Olá, {{ .Data.nome }}.{{ else }}Olá.{{ end }}` — a Edge Function sempre manda
`nome` (campo obrigatório do formulário), o painel do Supabase não manda. Sem o `else` o e-mail do
painel diria "Olá, .". **Os dois ramos foram exercitados** (§6).

---

## 4. Como isto chega a dev e a prod — e o que NUNCA fazer

`[auth.email.template]` no `config.toml` vale **só para o stack local**. O que serve `homolog` e
`app` é a cópia gravada no painel de cada projeto. Há dois caminhos.

### 4.1 O script (recomendado)

```bash
SUPABASE_ACCESS_TOKEN=sbp_... node supabase/templates/aplicar-templates.mjs ncdfolxdupbbfvtydngx
SUPABASE_ACCESS_TOKEN=sbp_... node supabase/templates/aplicar-templates.mjs aqfuawrygxsiopyppjza
```

O token é o **personal access token** da conta (https://supabase.com/dashboard/account/tokens) — não
é a service key nem a chave publicável. O script faz um `PATCH` de **quatro campos** na Management
API e **lê a configuração de volta** para conferir; `--conferir <ref>` só audita, sem escrever.

A conferência é positiva de propósito, como o vigia do card 3.10 e o ensaio do backup do 3.11: nome
de campo errado na API devolveria `200` **sem mudar nada**, e "não deu erro" teria passado por
sucesso. Reprovando, o script diz que o provável é o nome do campo ter mudado.

> ⚠️ **NUNCA `supabase config push`.** Ele empurra o `config.toml` inteiro, e o que não está no
> arquivo volta ao default — `[auth.email.smtp]` está **deliberadamente fora** dele (decisão de
> 02/09/2026: o SMTP do Resend vive só no painel). Um `config push` apagaria o SMTP dos dois
> projetos, e o sintoma seria convite e recuperação **parando de chegar, em silêncio**, dias depois.

### 4.2 O painel, à mão

Em **cada** projeto, `Authentication → Emails`:

| Aba do painel | Subject | Message body |
|---|---|---|
| **Invite user** | `Seu acesso ao Gestão IM360` | conteúdo de `supabase/templates/convite.html` |
| **Reset password** | `Redefinir sua senha do Gestão IM360` | conteúdo de `supabase/templates/recuperacao-senha.html` |

Colar o arquivo **inteiro**, do `<!doctype html>` ao `</html>`.

### 4.3 Depois de aplicar

1. `node supabase/templates/aplicar-templates.mjs --conferir <ref>` nos dois — é a única prova de que
   o painel tem o que o repositório tem.
2. Um convite de verdade para um endereço seu em cada ambiente, e um "Esqueci minha senha". O que se
   olha: assunto em português, o botão levando à tela de **definir senha** (não ao Dashboard), e o
   logotipo — que em produção só aparece depois de a promoção com o PNG ter subido.

⚠️ **A divergência entre repositório e painel é possível e silenciosa** — alguém edita no painel e o
arquivo aqui fica desatualizado, ou o contrário. O `--conferir` é o antídoto, e vale rodar junto com
a conferência de painel do `docs/deploy-web.md` §4.

---

## 5. `email_change`: por que ficou de fora

`double_confirm_changes = true` faz a troca de e-mail pedir confirmação **nos dois endereços** — dois
envios, com semântica diferente do convite. Mas **o app não troca e-mail**: o campo de e-mail existe
só no formulário de convite (`app/lib/telas/administracao/formularios.dart`), e `usuario.email` é
espelho de `auth.users`. A troca é alcançável apenas por alguém editando o usuário no painel do
Supabase — isto é, por Irineu.

Deixado em inglês **de propósito**, com o motivo escrito: quem o dispara hoje é quem mantém o
sistema. No dia em que a tela de Administração ganhar troca de e-mail, este template passa a ser lido
por uma secretária e entra na mesma casca dos outros dois — e aí o card que criar a tela traz o
template junto.

---

## 6. O que foi exercitado, e não só lido

Stack local (`supabase start`, 8 migrações + `seed.sql`), envios pela mesma API que a Edge Function e
o app usam, e a leitura do que chegou pelo Mailpit:

| O que | Como | Resultado |
|---|---|---|
| Convite **com** nome | `POST /auth/v1/invite` com `data.nome`, como a Edge Function | ✅ assunto "Seu acesso ao Gestão IM360"; *"Olá, Maria Aparecida de Souza."* |
| Convite **sem** nome | `POST /auth/v1/invite` só com `unidade_id`, como o painel | ✅ *"Olá."* — o ramo `else` |
| Recuperação | `POST /auth/v1/recover`, como `resetPasswordForEmail` | ✅ assunto "Redefinir sua senha do Gestão IM360" |
| `type` no link | leitura do HTML entregue | ✅ `type=invite` e `type=recovery` presentes |
| Chave Go não resolvida | busca por `{{` no HTML entregue | ✅ nenhuma |
| Texto alternativo estilizado | busca por `font-size:19px` no HTML entregue | ✅ presente |
| Imagem bloqueada | renderização do e-mail sem a imagem | ✅ layout íntegro, `alt` legível |

### Dois achados operacionais

1. **O GoTrue lê o template no boot, não no envio.** Editar o HTML e mandar um e-mail entrega a
   versão **antiga**, sem erro nenhum. Medido: a primeira leva de testes veio sem o estilo do `alt`
   que já estava no arquivo. **Depois de editar um template, `supabase stop` + `start`** antes de
   testar — senão se depura o e-mail errado.
2. **`{{ .ConfirmationURL }}` sai com escape HTML** (`&amp;` em lugar de `&`), porque o GoTrue
   renderiza com `html/template`. No `href` é o correto; no texto visível o cliente decodifica a
   entidade e mostra `&`. Conferido na renderização: nada a corrigir — e é bom saber antes de alguém
   "consertar" o que está certo.

---

## 7. O que este card deixa em aberto

1. **Aplicar nos dois painéis** — de Irineu, §4. Enquanto não for feito, dev e prod seguem mandando
   o template padrão em inglês; o que este card entregou é o conteúdo e a ferramenta.
2. **O logotipo em produção depende da promoção** que publica `app/web/marca/`. Até lá, texto
   alternativo nos e-mails dos dois ambientes.
3. **`otp_expiry` e a frase das 24 horas** mudam juntos — não há teste que amarre os dois. Um
   assertivo em `app/test/` não alcança o `config.toml`; fica o aviso no comentário dos templates.
4. **Nenhuma versão em texto puro.** O GoTrue manda só a parte HTML, e cliente 100% texto verá o
   HTML cru. Os quatro a oito usuários da escola usam Gmail e Outlook; se um dia isso mudar, é
   `multipart/alternative` — que o GoTrue não oferece por template.
