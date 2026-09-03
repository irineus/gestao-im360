# Administração: usuários, perfis, matriz, parâmetros e histórico — cards 4.7 e 4.7.5

**Fonte da tela de Administração, da Edge Function do convite e do histórico da matriz.** Fecha a
tela 12 do wireframe (`docs/wireframes.md` §15), o contrato do convite que o card 3.5 deixou fixado
(`docs/acesso-autenticacao.md` §3.2) e a pendência do card 2.4 §10.2 (log de alteração da matriz),
que as Decisões vigentes §4 pedem como mitigação do risco de permissões mal definidas exporem dados.

Ler junto: `docs/permissoes-matriz.md` (o catálogo e a matriz que a tela edita),
`docs/acesso-autenticacao.md` (convite, sessão, desativar × banir), `docs/seed-inicial.md` (os
parâmetros e o contrato de idempotência que o histórico muda).

---

## 1. O que a tela é — e o que ela não decide

Quatro abas, guardadas pela rota `admin.ler` (só a direção na matriz inicial):

| Aba | Fonte de dados | Ação | Permissão da ação |
|---|---|---|---|
| Usuários | `usuario` + `usuario_perfil` | convidar, editar nome/ativo, atribuir e retirar perfis | `admin.gerir_usuarios` |
| Perfis e matriz | `perfil`, `permissao`, `perfil_permissao` | criar/editar perfil, marcar e desmarcar | `admin.gerir_perfis` |
| Parâmetros | `parametro` | criar/editar valor | `parametros.gerir` |
| Histórico | `perfil_permissao_hist` (card 4.7.5) | só leitura | `admin.ler` |

Como nas telas 4.4 e 4.5, **a tela não decide regra**: submete pelo PostgREST e traduz o erro pelo
`codigo` (card 2.6 decisão 2). Quem diz se a secretaria pode marcar `estoque.ajustar` é a política
de `perfil_permissao`; quem diz se um perfil desativado concede algo é `tem_permissao` (card 3.4).
Botão sem permissão **não é renderizado**; a matriz sem `admin.gerir_perfis` aparece com as caixas
desabilitadas, porque ver a matriz é `admin.ler` e mudar é outra coisa.

Cursos, combos, módulos e professores, que o plano §7 listava aqui, moram nas telas de Materiais e
de Salas, junto do uso (card 2.6, apontamento 1). Unidade não se edita nesta fase: o nome da unidade
é dado de configuração de uma unidade só, e a tela de unidades é da Fase 11.

### 1.1 Usuários — o que a tela passou a mostrar

O ajuste que o card 3.7 pediu: **quem está sem perfil aparece**. Até aqui isso só se descobria quando
a pessoa tentava entrar e caía em `SessaoSemPerfil`; quem convidou não tinha como saber que faltou
atribuir. Agora a coluna de perfis diz `⚠ sem perfil`, o filtro "Sem perfil (n)" isola essas
linhas e a barra de filtros traz o aviso *"n usuários ativos sem perfil: entram e não veem nada
até receber um perfil"*. Desativado sem perfil não conta — não entra de qualquer jeito.

**Quem ainda não aceitou o convite também aparece (card 4.7,7).** A coluna "Situação" diz `Convite
pendente` — e a ficha da pessoa traz a ação **"Reenviar convite"**. O reenvio já funcionava desde o
4.7 (convidar de novo com o mesmo e-mail devolve o mesmo `usuario_id` e dispara e-mail novo), mas
nada na tela contava isso: em 03/09/2026, ao preparar o marco 4.8, Irineu procurou como reenviar e
concluiu que não dava. **O defeito era de descoberta, não de comportamento** — e o lugar onde se
procura por "reenviar" é a linha da pessoa, não um botão chamado "Convidar usuário". O formulário de
convite também passou a dizer, em uma frase, que usar o mesmo e-mail reenvia.

O estado vem de `fn_convites_pendentes()` (migração `20260903170000`), função `security definer`
porque `auth.users.email_confirmed_at` — onde ele mora — nenhum papel do app alcança. Três decisões:

- **`email_confirmed_at`, e não "nunca entrou"**: é literalmente o pivô do GoTrue entre reenviar e
  recusar com `email_exists`. O que a função devolve não é uma aproximação de "ainda não aceitou": é
  a resposta a *"para quem o botão funciona"*. Medido contra o stack local — convite deixa
  `email_confirmed_at` nulo e o id aparece; reenviar devolve o **mesmo** id e ele continua na lista;
  confirmar o e-mail tira o id da lista **e** faz o convite seguinte devolver 422 `email_exists`.
  Os dois lados do par, exercitados.
- **Função, não coluna espelhada**: uma coluna em `usuario` exigiria mais um trigger em `auth.users`
  e poderia **divergir do Auth em silêncio** — a tela ofereceria o botão a quem já aceitou, ou o
  esconderia de quem precisa. Lido na hora, o estado não tem como divergir.
- **A marca exige `admin.ler`, o botão exige `admin.gerir_usuarios`.** Se a *marca* dependesse da
  permissão da ação, quem tem `admin.ler` e não tem `admin.gerir_usuarios` veria a lista inteira sem
  uma única marca — indistinguível de "todo mundo já aceitou". Amarrada à visibilidade da lista, ela
  é verdadeira para quem quer que enxergue a linha.

A ação não aparece para quem já definiu senha (o GoTrue recusaria, e botão que só sabe falhar é pior
que botão nenhum) nem para quem está desativado — `Desativado` vence `Convite pendente` na coluna,
porque reenviar convite a quem não pode entrar não resolve nada. E pede confirmação dizendo a
consequência que ninguém adivinha: **o link anterior deixa de valer**.

A ficha edita **nome** e **ativo** e as caixas de perfil. E-mail é só leitura, com o texto de
`EMAIL_IMUTAVEL` como apoio (é o endereço de acesso; só muda pelo Auth — card 3.5 §1). Desativar
mostra o aviso que o §6 do documento de acesso previa: *"nega tudo na hora, mas a sessão já aberta
continua até o token expirar (1 h); para cortar imediatamente, Ban user no painel"*. Perfil
desativado só aparece nas caixas se a pessoa já o tem — para poder tirá-lo.

As caixas viram um **plano** (`planejarPerfis`: inserir o que falta, apagar o que sobra), porque
`usuario_perfil` não tem `update` — é insert e delete, como o card 2.4 §4 escreve. Delete que apaga
menos linhas do que o plano pedia vira erro, e não "salvo" (card 3.4 (d): sem política, o Postgres
apaga nada e diz sucesso).

### 1.2 Perfis e matriz

Um perfil por vez, escolhido no menu; os 12 domínios como seções, na ordem do menu lateral; uma
caixa por código, com a **descrição ao lado** — é para isso que a descrição existe no seed
(card 2.4 §8). O cabeçalho diz o que a tela não faz: *o catálogo não é editável aqui; código novo
só entra por migração* (`permissao` não tem política de escrita, card 2.4 (e)).

- **Marcar** é `insert` em `perfil_permissao`; a confirmação é efêmera.
- **Desmarcar** é `delete`, e antes dele um diálogo com o texto do card 2.7 §7.3 — *"A mudança
  vale imediatamente para todos os usuários do perfil"* — e a descrição do que se está tirando. Não
  é snackbar porque muda o que a pessoa fará em seguida (design-system §5.8).
- **Perfil desativado** mostra o aviso de que as caixas marcadas não valem para ninguém: sem isso a
  matriz de um perfil desligado parece uma matriz que funciona.
- **Novo perfil** pede código (caixa alta, chave natural, imutável depois — é o que o histórico grava
  em texto), nome e ativo. Ao salvar, o perfil novo passa a ser o selecionado, com zero caixas.

### 1.3 Parâmetros

Chave, valor, descrição e tipo, na ordem das chaves. Editar um parâmetro que a rotina diária lê
(`rep_*`, `projecao_*`, `ritmo_*`, `standby_*`) mostra o aviso do card 2.7 §7.3: *"vale a partir da
próxima execução da rotina diária (madrugada)"*. A validação é **só de formato**, por tipo — inteiro,
decimal (vírgula aceita, gravado com ponto), `true`/`false`, data em `dd/mm/aaaa` (gravada em
`yyyy-mm-dd`). O que o valor significa quem confere é a função que o lê.

Não há exclusão, e não é esquecimento: parâmetro ausente é `PARAMETRO_AUSENTE` (card 3.4 §8.7), e
apagar pela tela quebraria a regra que o lê. Corrige-se o valor. "Novo parâmetro" existe porque a
mensagem de `PARAMETRO_AUSENTE` manda cadastrar aqui.

⚠️ `parametro` **nunca recebe segredo** (card 3.4): qualquer autenticado da unidade lê qualquer
chave por `fn_param_txt`. A tela não impede — é convenção, e por isso está escrita aqui de novo.

### 1.4 Histórico (card 4.7.5)

Quando, perfil, permissão, ação (Concedida / Removida) e quem — `sistema (seed)` quando a linha veio
da migração. Da mais recente para a mais antiga, até 500 linhas. O que ele responde é a pergunta
que motivou o card: *três meses depois, quem tirou `estoque.ajustar` da secretaria?*

---

## 2. O convite: a única Edge Function da v1

`supabase/functions/convidar-usuario/`. É o caso indispensável que o `CLAUDE.md` prevê: criar
usuário no Auth exige a Admin API, e a **service key nunca pode chegar ao Flutter** — `service_role`
tem `BYPASSRLS` (card 3.3). Ela existe só dentro da função, na variável que a plataforma injeta.

O contrato é o que o card 3.5 fixou no §3.2, na ordem:

1. **quem chama, com o token de quem chama** — a função monta um cliente com a chave anônima e o
   `Authorization` do pedido e pergunta ao banco `tem_permissao('admin.gerir_usuarios')`. É o mesmo
   contexto que o PostgREST daria ao app: RLS forçada, a matriz de verdade. Nada do que o cliente
   mandou é acreditado; `403 / SEM_PERMISSAO` se não pode, `401` se o token não vale;
2. **a unidade é a do chamador** (`fn_unidade_atual`), não um campo do pedido: convidar é sempre
   para a própria unidade. Na v1 o espelho aceitaria convite sem metadado (única unidade ativa,
   card 3.5 §1.2); mandar a unidade deixa a função pronta para a Fase 11, quando esse fallback se
   fecha sozinho;
3. `inviteUserByEmail(email, { data: { nome, unidade_id }, redirectTo })` com a service key. O
   `nome` vai no metadado e o espelho o copia na criação (card 3.5 §1.1) — a pessoa nasce com o
   nome que a direção digitou, não com a parte local do e-mail;
4. **o erro volta como veio.** Se o espelho recusou (`USUARIO_SEM_UNIDADE`, `USUARIO_SEM_EMAIL`), o
   `codigo` do `DETAIL` vai no corpo, com o status do `PT4xx`, e a tela traduz pelo catálogo do
   card 2.7 §7.1 — o mesmo texto que a RLS daria. Se foi o GoTrue (`email_exists`,
   `over_email_send_rate_limit`), o `code` dele vai no corpo e a tela usa a tabela de mensagens do
   Auth (§3). O que a função não sabe traduzir chega com o status HTTP à vista, como todo fallback
   deste projeto.

Do lado do app, `FunctionException` entrou em `traduzirErro` ao lado de `PostgrestException` — a
mesma porta, o mesmo gancho do Sentry (card 3.12), nenhuma tela precisa saber que existe uma função.

Com o id que a função devolve, **o formulário de convite já atribui os perfis marcados** — a linha
de `usuario` existe quando a resposta chega, porque o espelho é trigger e roda dentro da chamada da
Admin API. Fecha no mesmo ato a janela "convidado sem perfil" que a aba de usuários passou a
denunciar.

### 2.1 Onde a função vive e como chega lá

- **Lógica pura em `logica.ts`**, testada com `node --test` — sem Deno, sem rede (o Node 24 lê `.ts`
  com anotações de tipo sem transpilar, como já faz o vigia e o portão de migrações). `index.ts` só
  orquestra. Job novo `edge functions (lógica)` no `testes.yml`.
- **Publicação pelo `db-migrations.yml`**, logo depois do `db push` — `supabase functions deploy
  --use-api` (empacota no servidor; sem Docker no runner). O workflow passou a disparar também
  quando só `supabase/functions/**` ou o `config.toml` mudam. Nada novo para Irineu configurar: as
  três variáveis que a função lê são injetadas pela plataforma, e o token do CLI é o mesmo do
  `db push`. Em produção continua atrás do portão do environment `prod`.
- **`verify_jwt = true`** em `[functions.convidar-usuario]` do `config.toml`: o gateway confere a
  assinatura antes de a função rodar. Duas barreiras; a segunda (a permissão no banco) é a que
  decide.
- **`[edge_runtime] enabled = true`** no `config.toml`, para `supabase functions serve` exercitar a
  função contra o stack local. O CI continua excluindo `edge-runtime` no `supabase start`: nenhum
  teste pgTAP passa por ele.
- Versão **fixa** do `supabase-js` (`npm:@supabase/supabase-js@2.114.0`), pelo mesmo motivo do CLI
  e do Flutter (card 3.9).

### 2.2 O convite não terminava em lugar nenhum — fechado

O achado ALTA do card 3.8, medido no deploy de homologação: a pessoa abre o link do convite, ganha
sessão válida, cai dentro do app **sem senha cadastrada**, e no acesso seguinte o login por senha
não funciona sem que nada tenha dito que faltava um passo.

O que o Auth devolve no link de convite é a sessão no **fragmento** da URL, com `type=invite`. O
`supabase_flutter` cria a sessão a partir dele, emite um `signedIn` comum — indistinguível de um
login — e limpa a URL. Ou seja, **o único momento em que dá para saber que a pessoa chegou por
convite é antes do `Supabase.initialize`**. Por isso:

1. `main` lê `Uri.base` antes de qualquer outra coisa e guarda o tipo do link
   (`lib/config/link_inicial.dart`);
2. o roteador, enquanto o convite estiver pendente e houver sessão, leva a pessoa a
   `/redefinir-senha?motivo=convite` **antes de qualquer outra tela** — inclusive antes da tela de
   "sem perfil";
3. a tela de redefinir senha diz *"Defina sua senha para concluir o cadastro"* (e não "definir nova
   senha"), e depois de salvar oferece **Entrar no sistema**, que consome o registro e vai à primeira
   rota que a pessoa pode abrir;
4. link sem sessão (expirado) cai no login, e o registro deixa de valer.

Vale para o convite pela **função** (que manda `redirectTo` já apontando para `/redefinir-senha`) e
para o convite pelo **painel** (que volta à Site URL): nos dois o fragmento traz `type=invite`.
`<url pública>/**` nas Redirect URLs dos projetos (card 3.8) já cobre o destino.

O caso residual — a pessoa fechou a aba sem definir a senha — ganhou a pista que faltava no login:
com credencial inválida, a tela acrescenta *"Chegou por convite e ainda não definiu a senha? Use
'Esqueci minha senha' para criá-la"*.

---

## 3. Erros do GoTrue deixam de chegar crus

O ajuste MÉDIA do card 3.8: `over_email_send_rate_limit` apareceu para o usuário. O catálogo do card
2.7 §7.1 cobre só os códigos do `DETAIL` das exceções do banco; os do GoTrue passavam direto.

`lib/erros/erro_app.dart` ganhou `mensagensAuth` — rate limit de e-mail e de requisição, senha
fraca, senha igual à anterior, e-mail já cadastrado, link expirado, e-mail não confirmado, sessão
expirada, validação. Fica **fora** do catálogo do 2.7 pelo mesmo motivo de `mensagensIntegridade`
(card 4.4): o catálogo é o contrato do `DETAIL`, conferido pelo C12 contra as funções do banco, e um
código do GoTrue não é código de função nenhuma. Os códigos conhecidos contam como traduzidos —
nenhum merece evento no Sentry (card 3.12 (c)). Os desconhecidos continuam no fallback, com o código
à vista.

---

## 4. Histórico da matriz — o banco (card 4.7.5)

Migração `20260903100000_matriz_historico.sql`.

### 4.1 A decisão

O card 2.4 §10.2 pôs duas saídas na mesa: tabela de histórico escrita por trigger, ou trocar o
`delete` por `ativo = false` em `perfil_permissao`. Ficou a **primeira**. A segunda mudaria a
política de RLS de `perfil_permissao` (card 2.4 §4), o join de `tem_permissao` (card 3.4) e o guarda
do seed (card 3.6) — três lugares já asseridos — para guardar **uma** transição só (a linha teria
apenas o último estado). Uma tabela imutável guarda todas.

### 4.2 A forma

`perfil_permissao_hist`: `perfil_id` + `perfil_codigo`, `permissao_id` + `permissao_codigo`, `acao`
(`CONCEDIDA` / `REMOVIDA`), auditoria. Os códigos vão em **texto além dos ids**: o histórico é para
ser lido três meses depois, sem join, e o que uma pessoa reconhece é `SECRETARIA` /
`estoque.ajustar`, não um uuid. `criado_por` nulo = a migração (seed); a tela mostra `sistema`.

- **Escrita só por trigger** (`fn_perfil_permissao_historico`, `after insert or delete` em
  `perfil_permissao`, `security definer` — entra na lista C8). Dispara também na cascata: a cascata
  não passa pela RLS (card 4.3) mas passa pelo trigger, então uma remoção em massa fica registrada
  linha a linha.
- **Imutável por ausência de política**: só `select`, por `admin.ler`. Sem `insert` de propósito —
  um `POST` direto gravaria "REMOVIDA" de uma permissão que continua valendo, e histórico que mente é
  pior que histórico ausente (card 4.2). Aqui isso se resolve por construção (a tabela não aceita
  escrita de ninguém que não seja o trigger), sem precisar do trigger de coerência que
  `aluno_status_hist` precisou.
- **FKs `on delete restrict`**, não cascade: perfil com histórico **não se apaga** — nem por quem tem
  `BYPASSRLS`. Perfil sai por `ativo = false` (card 3.4), e a prova de quem mexeu na matriz dele
  fica. Uma migração que retire um código do catálogo terá de decidir, por escrito, o que faz com o
  histórico dele.

### 4.3 O que muda no seed

O guarda do card 3.6 era **por código**: o seed só distribui um código sem nenhuma linha na matriz
da unidade. Fechava "desmarquei de um perfil" e deixava aberto o caso residual "desmarquei de
todos" — sem histórico, *nunca dado* e *tirado de todo mundo* são a mesma ausência, e o deploy
seguinte devolvia o código (`docs/seed-inicial.md` §2.1).

`fn_seed_matriz` ganhou **uma** cláusula: código com uma `REMOVIDA` registrada foi tirado por alguém
e não volta. Código sem linha **e sem histórico** nunca foi dado — é o código novo de uma migração
futura, e continua chegando. A suíte 022 trocou a asserção do caso residual pela nova, e a 032 cobre
os dois lados.

⚠️ Consequência assumida: uma unidade cujo histórico seja apagado à mão (só `postgres` consegue)
volta ao comportamento do card 3.6. É o que o teste usa para simular "código novo".

### 4.4 O que ficou fora, e por quê

- **Atribuição de perfil a usuário** (`usuario_perfil`) e **ativar/desativar perfil** não entram
  neste histórico. A pergunta que o card responde é sobre a **matriz** — o que cada perfil pode.
  Quem tem qual perfil está em `usuario_perfil` com `criado_em/por`, e a remoção sem rastro ali é
  a mesma família de problema; se virar pergunta real, é card próprio, com a mesma forma.
- **Rótulo de quem mexeu** vem de `usuario.nome` no momento da leitura, não gravado no histórico:
  nome é dado editável, e o `criado_por` é o que não muda.

---

## 5. Suítes

| Suíte | O que prova |
|---|---|
| `supabase/tests/032_matriz_historico.sql` | seed deixa rastro (criado_por nulo); marcar/desmarcar registram com quem; imutabilidade (update/delete zero linhas, insert recusado pela RLS, perfil com histórico não se apaga); leitura por `admin.ler` e por unidade; o seed não devolve o removido de todos e continua distribuindo o nunca dado |
| `010`, `011`, `022` | C4 com a tabela nova (só `select`); C8 com o trigger; o caso residual do seed invertido |
| `supabase/functions/convidar-usuario/logica.test.ts` | validação do pedido, extração do `codigo` do erro do GoTrue, status e corpo da resposta de erro, CORS |
| `app/test/administracao_test.dart` | agrupamento por domínio, rótulos, plano de perfis, filtros, validação e normalização de parâmetro por tipo |
| `app/test/tela_administracao_test.dart` | sem perfil na linha e no aviso; ocultação por permissão nas quatro abas; editar usuário (plano), desativar (aviso), convite (destino, perfis, recusa pelo código, `email_exists` traduzido); matriz marca, desmarca com confirmação, perfil desativado, perfil novo; parâmetro validado pelo tipo com aviso da rotina; histórico |
| `app/test/link_inicial_test.dart` | `type=invite` no fragmento (o formato do card 3.8), recovery, sem tipo, fragmento inválido |
| `app/test/erro_app_test.dart` | códigos do GoTrue traduzidos; `FunctionException` com `codigo`, com `code` e sem nenhum |

---

## 6. Ajustes que estes cards deixam

| # | Ajuste | Card | Gravidade |
|---|---|---|---|
| 1 | O convite pelo **painel** continua possível e continua entrando sem perfil; a aba de usuários denuncia, mas quem convida pelo painel não vê a tela. Convidar pela tela é o caminho normal a partir daqui | operação | baixa |
| 2 | `usuario_perfil` sem histórico de atribuição/retirada (§4.4) — card próprio se virar pergunta | backlog | baixa |
| 3 | Seleção de unidade no convite (metadado) quando houver segunda unidade: a função manda a do chamador, e é o que a Fase 11 precisa revisar | 11.4 | baixa |
