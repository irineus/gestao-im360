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
| `supabase/tests/021_auth_espelhamento.sql` | 18 asserções do espelho |
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

`resetPasswordForEmail(email, redirectTo: '<site_url>/#/redefinir-senha')` → o Auth manda o link →
a pessoa volta ao app com uma sessão de recuperação → `updateUser(password: …)`.

Duas condições, as duas fora do código: a URL de destino tem de estar nas **Redirect URLs** do
projeto (§7), e a **Site URL** tem de ser a do app — é dela que o link é construído. Site URL errada
não quebra o login: quebra o link, e só se descobre quando alguém precisa dele.

Verificado local em 01/09/2026: `POST /auth/v1/recover` → 200 e o e-mail *"Reset your password"* no
Mailpit (`http://127.0.0.1:54324`), que é onde o card 3.7 testa o fluxo sem SMTP nenhum.

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
   com letras e dígitos; `Secure password change` habilitado.
2. **URL Configuration → Site URL**: a URL do Cloudflare Pages. **Só existe a partir do card 3.8** —
   até lá o link de convite e de recuperação aponta para o lugar errado. Anotado como pendência do
   3.8. **Redirect URLs**: a rota de redefinição de senha do app.
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
| 5 | Edge Function do convite, com o contrato do §3.2 (verificar `admin.gerir_usuarios` com o token do chamador) | `supabase/functions/` | **4.7** | média — até lá o painel resolve |
| 6 | Ligar `[edge_runtime]` em `config.toml` quando o item 5 acontecer | `supabase/config.toml` | 4.7 | baixa |
| 7 | Seed do card 3.6 liga o **primeiro usuário de direção** ao perfil `DIRECAO`: o convite cria o espelho, mas ninguém pode nada até existir `usuario_perfil` | migração do seed | **3.6** | **bloqueante** para o 3.7 ter em quem logar — hoje ninguém no dev tem perfil |

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
