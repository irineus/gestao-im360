# Acesso e autenticação — card 3.5

Fonte do **fluxo de entrada no sistema**: como uma pessoa passa a existir, como entra, como recupera
a senha e como sai. Entrada dos cards **3.7** (tela de login e camada de sessão), **4.7** (tela de
Administração → Usuários) e **3.8** (Site URL do Cloudflare Pages).

O que este documento **não** cobre: quem pode o quê depois de entrar — isso é
`docs/permissoes-matriz.md` (catálogo e matriz) e a migração do card 3.4 (`tem_permissao`, RLS).

Entregue neste card:

| Arquivo | O que traz |
|---|---|
| `supabase/migrations/20260901180000_auth_espelhamento.sql` | `fn_usuario_espelhar`, `fn_usuario_email_sincronizar`, `fn_usuario_espelho_coerente` e os três triggers |
| `supabase/config.toml` | configuração do Auth versionada (e a lista de conferência do painel) |
| `supabase/tests/021_auth_espelhamento.sql` | 22 asserções: 18 do espelho e 4 de `fn_convites_pendentes` (card 4.7,7) |
| `supabase/seed.sql` | os oito usuários da fixture passam a **logar de verdade** no stack local |

---

## 1. O invariante

> **`public.usuario` é um espelho de `auth.users`.** Quem entra em `auth.users` ganha linha em
> `usuario` no mesmo instante, e `usuario.email` é **sempre** igual a `auth.users.email`.

As duas metades têm o mesmo motivo. Um usuário autenticado **sem** linha em `usuario` não é um
usuário sem acesso: é um usuário para quem `fn_unidade_atual()` devolve `null`, toda política de RLS
nega, e o app abre **todas as telas vazias, sem erro nenhum** — o modo de falha que os cards 2.3, 2.4
e 3.4 já catalogaram como o mais caro deste projeto. E um `usuario.email` diferente do e-mail do Auth
é uma tela mostrando um endereço com o qual ninguém consegue entrar.

Por isso o espelho é **trigger no banco**, e não uma chamada que o app faz depois do convite: entre o
convite e a chamada haveria uma janela, e a janela dura o que durar o erro de rede.

### 1.1 O que o espelho copia — e o que ele deliberadamente não copia

| Campo | Origem | Depois da criação |
|---|---|---|
| `id` | `auth.users.id` | imutável (é a PK e a FK) |
| `email` | `auth.users.email` | **segue o Auth para sempre** (trigger de update) |
| `nome` | `raw_user_meta_data.nome`, ou a parte local do e-mail | **dado do app** — a direção corrige na tela de Administração e o Auth não o reescreve mais |
| `unidade_id` | `raw_user_meta_data.unidade_id`, ou a única unidade ativa | **dado do app** |
| `ativo` | sempre `true` na criação | **dado do app** — o Auth não opina |

`nome` e `unidade_id` são copiados **só na criação**. Se o espelho os reescrevesse a cada `update` em
`auth.users`, a correção feita pela direção duraria até a próxima troca de senha da pessoa.

### 1.2 A unidade: metadado, ou a única ativa

`raw_user_meta_data.unidade_id` (uuid, em texto) tem precedência. Sem ele, o espelho usa a **única
unidade ativa**; se houver zero ou mais de uma, **recusa o convite inteiro** com
`PT422 / USUARIO_SEM_UNIDADE`.

O fallback não é conveniência: na v1 existe uma unidade só, e o convite pelo painel do Supabase — que
é o fluxo desta fase — não tem onde digitar metadado. E ele **se fecha sozinho**: no dia em que a
segunda unidade nascer (Fase 11), deixa de ser não-ambíguo e passa a exigir que quem convida diga a
unidade. Um default que expira quando deixa de ser óbvio.

Recusar o convite é melhor do que criar o `auth.users` e deixar o espelho para depois, pelo motivo do
§1. O erro **chega a quem convidou**: medido em 01/09/2026, a Admin API do GoTrue devolve o corpo do
`raise` do Postgres tal e qual, com status 422 e o `codigo` dentro de `detail` — não é um 500 opaco.

---

## 2. Configuração do Auth

Está em `supabase/config.toml`, com a justificativa de cada chave ao lado. Duas coisas precisam ser
ditas fora do arquivo:

**(a) `supabase config push` não é usado neste projeto.** O CI roda `supabase db push` e nada mais. A
lição vem do projeto Desmalha: `config push` reescreve a configuração de Auth do projeto remoto a
partir do arquivo, e o que não estiver lá volta ao default — o **SMTP próprio**, que mora só no
painel porque tem credencial, é apagado no ato. O sintoma aparece dias depois: convite e recuperação
de senha param de chegar, sem erro em lugar nenhum. Enquanto `config push` não for usado, o arquivo é
a configuração do **stack local** e a **lista de conferência** do painel (§7).

**(b) `[auth.email] enable_signup` não é o que o nome sugere.** Medido em 01/09/2026, com o stack
local: o CLI traduz essa chave para `GOTRUE_EXTERNAL_EMAIL_ENABLED`, que liga e desliga o **provedor
de e-mail inteiro**. Com ela em `false`, o convite ainda é enviado, mas
`POST /auth/v1/token?grant_type=password` e `POST /auth/v1/recover` respondem
`400 email_provider_disabled` — *"Email logins are disabled"*. Ou seja: **ninguém entra e ninguém
recupera senha**, e a mensagem não fala de cadastro. Quem fecha o cadastro público é o
`enable_signup = false` da seção `[auth]`, e ele sozinho basta — verificado, `POST /auth/v1/signup`
devolve `422 signup_disabled` com a outra chave em `true`.

Os valores que importam:

| Chave | Valor | Por quê |
|---|---|---|
| `[auth] enable_signup` | `false` | **não há cadastro aberto ao público** — a chave anônima vai no bundle do Flutter, é pública por desenho |
| `[auth] enable_anonymous_sign_ins` | `false` | idem |
| `[auth] minimum_password_length` | `8` | com `password_requirements = "letters_digits"` |
| `[auth] jwt_expiry` | `3600` | ver §6 — é o tempo que uma desativação leva para valer de fato |
| `[auth.email] enable_signup` | `true` | **provedor** de e-mail ligado; ver (b) acima |
| `[auth.email] double_confirm_changes` | `true` | trocar o e-mail de acesso confirma nos **dois** endereços |
| `[auth.email] secure_password_change` | `true` | trocar senha exige sessão recente (máquina compartilhada de laboratório) |
| `[auth.email] otp_expiry` | `86400` | 24 h: o default de 1 h não sobrevive a um convite mandado no fim da tarde |
| `[auth.email.notification.password_changed] enabled` | `true` | aviso por e-mail depois de toda troca de senha (card 9.2,81) — `supabase/templates/senha-alterada.html` |

### 2.1 ⚠️ A tabela acima vale SÓ no stack local — medido em 01/10/2026 (card 9.2,81)

Até 01/10/2026 este documento afirmava os valores do `config.toml` como se fossem os do Auth, e
**nos projetos hospedados nenhum dos quatro valia**. Pela regra do (a) acima o arquivo não é
aplicado no dev nem no prod — e nada levava esses quatro campos ao painel, nem comparava o painel com
o arquivo. É a mesma armadilha do item 9.16 das Decisões vigentes (os templates em inglês), em outra
tela do mesmo painel.

Medido por Irineu no painel (Authentication → Sign In / Providers → Email), dev e prod iguais:

| Campo do painel | Campo da Management API | `config.toml` | Hospedado **antes** | Hospedado **depois** (01/10/2026) |
|---|---|---|---|---|
| Email OTP expiration | `mailer_otp_exp` | `86400` | `3600` (1 h) | `86400` |
| Minimum password length | `password_min_length` | `8` | `6` | `8` |
| Password requirements | `password_required_characters` | `letters_digits` | nenhum | *Letters and digits* |
| Secure password change | `security_update_password_require_reauthentication` | `true` | **desligado** | **ligado** |
| Notificação *Password changed* | `mailer_notifications_password_changed_enabled` | `true` (novo) | desligada | ligada no prod, texto colado à mão; dev a confirmar |

(*Email OTP length*: 6 no `config.toml`, 8 no hospedado. Irrelevante — o fluxo é por link, não por
código — e por isso fora da conferência.)

**O que os quatro custaram.** O convite do Laurence saiu em 30/09 às 16:19 UTC e foi aberto 19 h 07
depois: com 1 h, *"email link has expired"*. Foi o vencimento que levou à tentativa no desktop com a
sessão do Lindomar aberta, e à troca da senha **dele** (card 9.2,80, §5.1). E o *Secure password
change* desligado é o que deixou essa troca passar: a sessão do Lindomar tinha 21 dias, e com o campo
ligado o `updateUser` teria exigido reautenticação e falhado — exatamente o cenário de "máquina
compartilhada de laboratório" que a tabela acima dava como coberto. Ainda: o e-mail de recuperação
dizia *"O link vale 24 horas"* enquanto o projeto aplicava 1 h — e a instrução "o link vale 24 horas,
convide no dia" fez o convite sair na tarde anterior.

**Quem leva e confere agora:** `supabase/templates/aplicar-templates.mjs`, o mesmo aplicador dos
templates, que passou a gravar e auditar os cinco campos acima (`docs/emails-auth.md` §4). Os nomes
da Management API foram **conferidos**, não supostos: na spec OpenAPI pública e no código do CLI que
os grava (`apps/cli-go/pkg/config/auth.go`, inclusive na v2.116.0 que o CI fixa) — e o nome "óbvio",
`secure_password_change`, **não existe** na API. `--conferir-nomes` refaz essa checagem sem token.

**⚠️ Risco aceito — 24 h apesar do aviso do painel (decisão de 01/10/2026).** Com 86400 o painel
mostra *"OTP expiry exceeds recommended threshold — recommended less than an hour"*. Mantido de
propósito: é a razão escrita na tabela acima, agora **medida** — com 1 h o convite do Laurence
venceu. O risco aceito é o de um link interceptado ser usado em até 24 h; ele é de uso único, e o
*Secure password change* ligado fecha o caso de sessão antiga trocando senha. **Reavaliar no
go-live** se os convites passarem a sair um a um, na hora.

**O que o *Secure password change* muda no app:** convite e recuperação criam sessão **nova**, então
não são afetados. Troca de senha a partir de sessão comum com mais de 24 h passa a exigir
reautenticação (`400 reauthentication_needed`) — e o app não oferece esse caminho (§5.1, "fora do
escopo"): quem quer trocar usa "Esqueci minha senha". Falhar fechado é o lado certo.

---

## 3. Convite — como uma pessoa passa a existir

Não há autocadastro. A pessoa entra porque alguém a convidou, e o convite cria a linha em
`auth.users`, que cria o espelho.

### 3.1 v1: pelo painel do Supabase

Authentication → Users → **Invite user**, com o e-mail. É o fluxo desta fase, e ele funciona sem
metadado nenhum: a unidade sai do fallback (§1.2) e o `nome` vira a parte local do e-mail —
provisório e obviamente provisório, para a direção corrigir.

Depois do convite, **a pessoa ainda não pode nada**: `fn_minhas_permissoes()` devolve vazio até que
alguém atribua um perfil em `usuario_perfil` (tela de Administração, card 4.7). Isso é fail-closed
por construção, não descuido.

### 3.2 Card 4.7: o botão "Convidar usuário"

O wireframe (`docs/wireframes.md` §15) tem o botão. Criar usuário no Auth exige a **Admin API**, e a
*service key* **nunca pode chegar ao Flutter** (decisão registrada no card 3.3: `service_role` tem
`BYPASSRLS`). Então o botão precisa de uma **Edge Function** — o caso indispensável que o `CLAUDE.md`
prevê. O contrato, já fixado aqui para o 4.7 não reinventá-lo:

1. a função recebe o JWT do chamador e **verifica `tem_permissao('admin.gerir_usuarios')`** no banco,
   com o token do usuário — nunca confiando no que o cliente mandou;
2. chama `inviteUserByEmail(email, { data: { nome, unidade_id } })` com a service key, que só existe
   dentro da função;
3. devolve o erro do banco **como veio** quando o espelho recusa: o `codigo` de `detail` é o que a
   tela traduz (card 2.7 §7.1).

Enquanto o 4.7 não existir, o painel resolve — e é por isso que este card não abre a Edge Function.

✅ **Entregue em 03/09/2026 (card 4.7)**: `supabase/functions/convidar-usuario/`, com o contrato
acima como escrito e mais dois pontos que só apareceram ao exercitar contra o GoTrue local — a
unidade do metadado é a **do chamador** (`fn_unidade_atual`), e convidar de novo quem ainda não
aceitou **reenvia** o e-mail e devolve o mesmo usuário, não um erro. O convite que não terminava em
lugar nenhum (achado do card 3.8) ficou fechado pelo `type=invite` do link, lido antes do
`Supabase.initialize`. Fonte: `docs/administracao.md` §2.

✅ **Completado em 03/09/2026 (card 4.7,7)**: o reenvio deixou de ser um efeito colateral que só quem
leu o código conhecia. `fn_convites_pendentes()` diz quem ainda não aceitou — `auth.users.
email_confirmed_at is null`, que é o **mesmo pivô** que o GoTrue usa para escolher entre reenviar e
recusar com `email_exists` —, a lista marca essas linhas com `Convite pendente` e a ficha da pessoa
ganhou "Reenviar convite". Detalhe e as três decisões em `docs/administracao.md` §1.1.

---

## 4. Login e sessão

`signInWithPassword(email, senha)` → o `supabase_flutter` guarda a sessão. A camada de sessão do card
3.7 carrega, **nessa ordem**:

1. a própria linha de `usuario` (`select … from usuario where id = auth.uid()`) — nome e
   `unidade_id`. Funciona para todo perfil por causa do `or id = auth.uid()` que o card 3.4 pôs na
   política de `select`;
2. `rpc('fn_minhas_permissoes')` — a lista de códigos que decide o que aparece na tela;
3. a unidade (`v1`: uma só, seleção pulada em silêncio — card 2.6, decisão (g)).

Verificado em 01/09/2026 contra o stack local: a direção da fixture entra e recebe os sete códigos
que a matriz lhe dá; o usuário sem perfil entra e recebe `[]`.

⚠️ **Usuário sem linha em `usuario` consegue token.** O Auth não sabe nada sobre o espelho. Se um dia
existir um `auth.users` sem espelho (por exemplo, criado antes desta migração), a pessoa autentica e
o app não tem o que mostrar. O card 3.7 trata isso como **erro de sessão explícito** — "seu acesso
ainda não foi liberado; avise a direção" — e não como tela vazia. É a diferença entre um estado que
se explica e um que parece bug.

---

## 5. Recuperação de senha

`resetPasswordForEmail(email, redirectTo: '<site_url>/redefinir-senha')` → o Auth manda o link →
a pessoa volta ao app com uma sessão de recuperação → `updateUser(password: …)`.

⚠️ **Sem `#`** (corrigido no card 3.8): o app passou a usar estratégia de URL por caminho, porque o
fragmento é onde o Auth devolve os tokens dos links que ele gera fora do fluxo PKCE — convite e
magic link pelo painel. Com a rota no fragmento, esses links caíam em "Esta tela não existe".
Detalhe e medição em `docs/deploy-web.md` §6.

Duas condições, as duas fora do código: a URL de destino tem de estar nas **Redirect URLs** do
projeto (§7), e a **Site URL** tem de ser a do app — é dela que o link é construído. Site URL errada
não quebra o login: quebra o link, e só se descobre quando alguém precisa dele.

E a lista de Redirect URLs casa por **igualdade**, não por prefixo (medido no card 3.8):
`https://app.exemplo` **não** autoriza `https://app.exemplo/redefinir-senha` — quem autoriza caminho
é o curinga `/**`, e caminho sob a própria Site URL é a única exceção. Destino recusado não devolve
erro: manda a pessoa para a Site URL, que é como um link "quase certo" passa despercebido.

Verificado local em 01/09/2026: `POST /auth/v1/recover` → 200 e o e-mail *"Reset your password"* no
Mailpit (`http://127.0.0.1:54324`), que é onde o card 3.7 testa o fluxo sem SMTP nenhum.

### 5.1 Card 9.2,80 (01/10/2026): fluxo implícito, e a senha só se troca com a sessão que o link criou

**O incidente.** Em homologação, o link de convite **vencido** do Laurence foi aberto num desktop em
que a sessão do **Lindomar** estava aberta. O Auth recusou o link (`?error=access_denied&error_code=
otp_expired`), a sessão que sobrou no navegador foi a do Lindomar, e a tela `/redefinir-senha` gravou
a senha nova **nele** (`user_updated_password`, `actor = lindomarsilva.ti@gmail.com`, 200). Ele ficou
trancado para fora. A causa: `updateUser(password: …)` aplica na **sessão corrente**, seja de quem
for, e a tela nunca conferia de onde a sessão tinha vindo. Na mesma tarde, a mesma falha tentou
trocar a senha da conta principal de Irineu e só não conseguiu porque o *Secure password change*
(card 9.2,81) respondeu `400 reauthentication_needed`.

**O segundo modo de falha — PKCE.** O `supabase_flutter` 2.x usa **PKCE** por padrão: o
`resetPasswordForEmail` guarda um verificador no armazenamento local **do navegador que pediu**, e o
link volta com `?code=`. Aberto em qualquer outro contexto — o celular, a janela anônima, outro perfil
do Chrome que o Gmail escolheu —, o código não se troca por sessão, e o link (uso único) já foi gasto.
Medido duas vezes seguidas, com a instrução seguida à risca. O convite nunca sofreu disso porque o
link gerado pelo **servidor** é implícito.

**O que vale agora** (`app/lib/main.dart`, `app/lib/config/link_inicial.dart`,
`app/lib/telas/redefinir_senha.dart`):

1. **Fluxo implícito** — `FlutterAuthClientOptions(authFlowType: AuthFlowType.implicit)`, **decisão
   de Irineu** em 01/10/2026. O link de recuperação volta com a sessão no **fragmento**
   (`#access_token=…&type=recovery`) e abre em qualquer aparelho, como o convite. Custo aceito: o
   token passa pelo fragmento da URL — link de uso único, 24 h de validade, *Secure password change*
   ligado nos dois projetos. Login por senha não muda.
2. **O app troca o link por sessão por conta própria** (`detectSessionInUri: false` +
   `LinkInicial.trocarPorSessao`, logo depois do `Supabase.initialize`) e **guarda o desfecho**: de
   quem é a sessão que o link criou, ou por que ele falhou (`error_code` da URL, código do servidor, ou
   `link_outro_navegador` para um `?code=` antigo). Antes disso a troca era do `supabase_flutter`, que
   engolia a falha num log e deixava a sessão anterior de pé. A URL é limpa nos dois desfechos.
3. **A guarda** — `LinkInicial.autorizaTroca(usuarioAtual)`: link de convite ou recuperação, que
   **valeu**, e cuja sessão é **a corrente**. A tela só mostra o formulário com ela, confere de novo
   no clique, e `SessaoRepositorioSupabase.trocarSenha` recusa sem ela (segunda barreira). A
   autorização é de **uso único**: consumida quando a senha é gravada.
4. **Sem formulário, a tela explica**: link recusado ("venceu ou já foi usado — peça outro", ou "foi
   pedido antes da mudança e só abre no navegador em que foi pedido") ou nenhum link (rota aberta à
   mão, página recarregada). Havendo sessão aberta, diz **de quem é** e oferece **Sair**.
5. **O roteador** leva à tela de senha, antes de qualquer outra, todo link de convite **ou de
   recuperação** — inclusive o enviado pelo painel (*Send password recovery*), que volta na Site URL e
   antes entrava no Dashboard sem pedir senha — e todo link que o Auth recusou.

⚠️ **Fora do escopo, registrado:** não há "Trocar senha" no menu do usuário, ao contrário do que o
wireframe §3.1 prevê. Com a guarda, quem já está logado e quer mudar a senha usa "Esqueci minha
senha" — e uma troca a partir de sessão comum esbarraria no `reauthentication_needed` de qualquer
jeito.

---

## 6. Sair do sistema: desativar, banir, apagar

| Ação | Onde | Efeito |
|---|---|---|
| **Desativar** (`usuario.ativo = false`) | tela de Administração | o app nega tudo: `fn_unidade_atual()` vira `null` e `tem_permissao()` é falsa para qualquer código (card 3.4). **Não revoga o token já emitido** — a sessão aberta continua autenticando até o JWT expirar (1 h). É o caminho normal. |
| **Banir** (`Ban user`) | painel do Auth | corta a autenticação **na hora**. Para quando a saída não pode esperar uma hora. |
| **Apagar** | — | **não existe**. A FK `usuario.id → auth.users(id)` é `on delete restrict`: apagar no painel **falha** enquanto houver espelho. Quem entregou apostila, mudou status de aluno e lançou estoque está em `criado_por`/`atualizado_por` de milhares de linhas, e apagar o usuário transformaria esse rastro em uuid órfão. |

Verificado: o usuário desativado da fixture **recebe token** e lê zero linhas. O comportamento está
certo e é preciso que esteja escrito, porque "desativei e a pessoa continuou dentro por uma hora" é
uma pergunta que vai aparecer.

---

## 7. O que precisa ser configurado nos projetos remotos — para o Irineu

`config.toml` **não** é aplicado no dev nem no prod (§2a). Nos dois projetos, em Authentication:

1. **Sign In / Providers → Email**: provedor **habilitado**; **Allow new users to sign up
   DESABILITADO** (é o `enable_signup` de `[auth]`); confirmação de e-mail habilitada; senha mínima 8
   com letras e dígitos; `Secure password change` habilitado; *Email OTP expiration* `86400`.
   ⚠️ Os quatro últimos **não estavam** aplicados até 01/10/2026 (§2.1). Hoje quem os grava e confere
   é o `supabase/templates/aplicar-templates.mjs` — `--conferir <ref>` é a prova, não a tela.
2. **URL Configuration → Site URL**: a URL pública daquele ambiente — `https://app.gestaoim360.com`
   em prod, `https://homolog.gestaoim360.com` em dev. **Redirect URLs**: `<url pública>/**`. O card
   3.8 fechou o formato exato e a razão de cada linha — `docs/deploy-web.md` §4 é a lista de
   conferência do painel. ⚠️ Projeto Supabase novo já vem com `http://localhost:3000` na Site URL e
   nas Redirect URLs: **em prod, tirar as duas** — produção não autoriza redirecionamento para a
   máquina de ninguém. Em dev, o localhost pode ficar (serve o `flutter run`).
3. ⚠️ **SMTP próprio** (pendência): sem ele o Supabase usa o serviço interno, com teto de poucos
   e-mails por hora e **sem garantia de entrega** — e o convite e a recuperação de senha vivem de
   e-mail. Um provedor transacional (Resend, por exemplo) resolve. Fica **só no painel**, nunca neste
   repositório, e é exatamente o que um `config push` apagaria.
4. **Auth → Rate limits**: conferir o teto de e-mails/hora antes de um dia de cadastro da equipe.

---

## 8. Códigos de erro novos

Três, todos com `codigo` estável no `DETAIL` (card 2.2 §1.2). O fixture de contrato
`test/fixtures/codigos_erro.txt` (card 3.7) vai de **22 para 25**, e o catálogo Dart do card 2.7 §7.1
recebe as três linhas:

| `codigo` | SQLSTATE | Quando | Mensagem sugerida em tela |
|---|---|---|---|
| `USUARIO_SEM_UNIDADE` | `PT422` | convite sem unidade resolvível (nenhuma, várias, ou metadado inválido) | "Não deu para saber em que unidade cadastrar esta pessoa. Informe a unidade no convite." |
| `USUARIO_SEM_EMAIL` | `PT422` | `auth.users` sem e-mail | "Não é possível criar um usuário sem e-mail." |
| `EMAIL_IMUTAVEL` | `PT409` | tentativa de mudar `usuario.email` pelo app | "O e-mail é o endereço de acesso e só muda pelo próprio login da pessoa." |

✅ **A convenção `PT<status>` foi exercitada pelo PostgREST pela primeira vez neste card** (01/09/2026):
o `PATCH /rest/v1/usuario` com e-mail diferente devolveu **HTTP 409** com
`{"code":"PT409","details":"{\"codigo\":\"EMAIL_IMUTAVEL\",…}"}`. O card 2.2 §1.2 dizia que
funcionaria; agora está medido.

---

## 9. Ajustes que este card exige

Mesmo formato do §14 do card 2.2 e do §16 do 2.8.

| # | Ajuste | Onde | Card | Gravidade |
|---|---|---|---|---|
| 1 | Site URL e Redirect URLs dos dois projetos apontando para o app publicado | painel do Supabase | **3.8** | **bloqueante** para convite e recuperação valerem em produção — sem isso o link existe e leva ao lugar errado |
| 2 | SMTP próprio nos dois projetos; nunca em `config.toml` | painel do Supabase | 3.8 / go-live | alta — o serviço interno tem teto baixo e não garante entrega |
| 3 | Sessão que trata "autenticado sem linha em `usuario`" como erro explícito, não como tela vazia | camada de sessão | **3.7** | alta — é o único jeito de o §1 não virar tela muda |
| 4 | Os três códigos novos em `test/fixtures/codigos_erro.txt` e em `catalogo_erros.dart` (22 → 25) | repositório | 3.7 | alta — C12 reprova enquanto faltar |
| 5 | ~~Edge Function do convite, com o contrato do §3.2 (verificar `admin.gerir_usuarios` com o token do chamador)~~ — ✅ **feita em 03/09/2026 (card 4.7)**, `docs/administracao.md` §2 | `supabase/functions/` | **4.7** | média — até lá o painel resolve |
| 6 | ~~Ligar `[edge_runtime]` em `config.toml` quando o item 5 acontecer~~ — ✅ **feito no card 4.7**, com `[functions.convidar-usuario] verify_jwt = true` | `supabase/config.toml` | 4.7 | baixa |
| 7 | Seed do card 3.6 liga o **primeiro usuário de direção** ao perfil `DIRECAO`: o convite cria o espelho, mas ninguém pode nada até existir `usuario_perfil` | migração do seed | **3.6** | **bloqueante** para o 3.7 ter em quem logar — hoje ninguém no dev tem perfil |
| 8 | ✅ **Os campos do provedor Email do `config.toml` valerem também no hospedado** — `otp_expiry`, senha mínima, requisitos e *Secure password change* —, achado de 01/10/2026: **nunca tinham valido** (§2.1). Aplicados por Irineu no painel em 01/10/2026; desde o card 9.2,81 o `aplicar-templates.mjs` os grava e audita | painel do Supabase + `supabase/templates/` | **9.2,81** | **alta** — a falta dos quatro levou à troca de senha do card 9.2,80 |

⚠️ **Este documento afirmava os valores do `config.toml` como se valessem nos projetos hospedados**,
e isso só foi desmentido por medição, quatro semanas depois (§2.1). O `config.toml` é o stack local e
a lista de conferência; o que vale no dev e no prod é o que `aplicar-templates.mjs --conferir <ref>`
diz.

---

## 10. Sobre a fixture ter passado a logar

`tests.criar_usuario` (card 3.4.5) montava a linha de `auth.users` com o mínimo para os testes SQL.
Isso bastava para o pgTAP e **não bastava para o GoTrue**: sem `instance_id` a Admin API responde
*"user not found"*, e com os campos de token em `null` o login morre em
`converting NULL to string is unsupported` — um 500 que não se parece nem um pouco com a causa.

Os oito usuários da fixture agora nascem com `instance_id`, `raw_app_meta_data` de provedor e senha
`fixture-local-123`, e **logam de verdade no stack local**. É o que o card 3.7 precisa para exercitar
a tela de login contra um banco real, com um usuário por perfil, sem inventar usuário à mão.

⚠️ A senha é de fixture e só existe no stack local: `seed.sql` nunca vai para `migrations/` e
`supabase db reset --linked` é proibido (card 2.8, ajuste 5). Não é credencial de ninguém — não
confundir com a política do card 2.9.
