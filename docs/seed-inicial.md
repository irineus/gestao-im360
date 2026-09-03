# Seed inicial — unidade, catálogo, matriz, parâmetros e o primeiro acesso (card 3.6)

> **Fonte do seed.** O catálogo de permissões e a matriz continuam sendo de `docs/permissoes-matriz.md`
> (§3 e §5) — este documento **não os repete**. O que está aqui é o que só passou a existir quando o
> seed virou código: o **contrato de idempotência** (o que volta e o que não volta quando o seed roda
> de novo), a **tabela consolidada dos 15 parâmetros** hoje espalhada por três documentos, e o
> **bootstrap do primeiro usuário de direção**.
>
> Implementação: `supabase/migrations/20260901200000_seed_inicial_acesso.sql`.
> Suíte: `supabase/tests/022_seed_inicial.sql`.

Data: 01/09/2026. Entradas: `docs/permissoes-matriz.md` §3, §5, §8 e §9; `docs/regra-virada-rep.md` §4;
`docs/projecao-demanda.md` §3; `docs/modelagem-dados-ddl.md` §5; `docs/acesso-autenticacao.md` §3 e §9.

---

## 1. O que este seed é

**É migração.** Roda pelo CI (`db-migrations`) em dev no merge para `develop` e em produção na
promoção para `main`. Não confundir com `supabase/seed.sql`, que é infraestrutura de teste e nunca
sai do stack local (card 2.8, ajuste 6).

Sem ele o sistema **sobe e não funciona**, sem erro nenhum: `tem_permissao()` consulta uma matriz
vazia e devolve falso para todo mundo, e as telas ficam ocultas ou vazias. É o modo de falha que
este projeto já catalogou nos cards 2.3, 2.4, 3.4 e 3.5.

| Objeto | Conteúdo |
|---|---|
| `unidade` | Uma linha: `codigo = 'MATRIZ'`, `nome = 'Instituto Mix Charqueadas'` |
| `permissao` | 50 códigos — as 49 do card 2.4 §3 e `salas.acessar_credencial` do card 2.9 |
| `perfil` | DIRECAO, PEDAGOGICO, SECRETARIA, MONITOR |
| `perfil_permissao` | Matriz do card 2.4 §5 — direção 50, secretaria 37, pedagógico 22, monitor 14 |
| `parametro` | 15 parâmetros de negócio (§3) + `direcao_inicial_email` |
| `usuario_perfil` | O primeiro usuário de direção, por bootstrap (§4) |

`codigo` é a chave natural criada pelo card 3.3 exatamente para isto: `nome` é editável na tela de
Administração por quem tem `unidades.gerir`, e um seed idempotente por nome inseriria uma segunda
unidade em silêncio no dia em que alguém corrigisse o cabeçalho. **O nome real da escola foi
confirmado por Irineu em 01/09/2026; trocá-lo é um clique na tela, não uma migração.**

---

## 2. Idempotência — o que volta e o que não volta

O seed roda em **toda** promoção. O erro que ele pode cometer não aparece no dia em que é escrito:
aparece meses depois, quando a direção configura alguma coisa na tela e o deploy seguinte desfaz.

| Tabela | Conflito | Por quê |
|---|---|---|
| `permissao` | `do update` (descrição, domínio, `ativo = true`) | O catálogo é **código**: a tabela não tem política de escrita nenhuma (card 2.4 (e)), então a única origem possível de uma descrição errada é a migração — e corrigi-la tem de valer no deploy |
| `perfil` | `do nothing` | O nome é editável na tela |
| `perfil_permissao` | **só distribui código que ainda não tem linha nenhuma na unidade** | §2.1 |
| `parametro` | `do nothing` | Valor ajustado pela escola não pode voltar ao default no deploy seguinte |

Nada é apagado pelo seed, em nenhuma tabela.

### 2.1 Correção ao contrato do card 2.4 §8 (achado deste card)

O card 2.4 §8 escreveu: *"Sem `delete`: o seed nunca tira o que a direção marcou na tela depois.
Reexecutar o seed acrescenta o que faltar e não desfaz configuração."* **As duas metades da frase se
contradizem.** A direção desmarca `compras.receber` da secretaria; a linha some; "acrescentar o que
faltar" a devolve no deploy seguinte — sem erro, sem log, e sem ninguém ligar uma coisa à outra. Não
ter `delete` protege apenas quem marca **a mais**; quem **desmarca** ficava desprotegido, e desmarcar
é o lado que importa para segurança (é assim que se tira `compras.receber_excedente` de alguém).

O guarda adotado é **por código**, não por linha nem por unidade: o seed só distribui um código que
ainda não tem **nenhuma** linha na matriz daquela unidade.

- Permissão desmarcada de um perfil **não volta** — o código continua tendo linha em outro perfil.
- Código **novo**, acrescentado ao catálogo por uma migração futura, **continua sendo distribuído**
  no primeiro deploy. Era isso que "acrescenta o que faltar" queria dizer, e continua valendo.

~~⚠️ **Caso residual assumido:** um código desmarcado de **todos** os perfis volta no deploy seguinte.~~
✅ **Fechado em 03/09/2026 pelo card 4.7.5**: `fn_seed_matriz` ganhou uma cláusula — código com uma
`REMOVIDA` em `perfil_permissao_hist` foi tirado por alguém e **não volta**; código sem linha **e
sem histórico** nunca foi dado, é o código novo de uma migração futura, e continua chegando. A
suíte 022 trocou a asserção do caso residual pela nova. Detalhe em `docs/administracao.md` §4.3.
Enunciado original: sem histórico não havia como distinguir "nunca foi dado" de "foi tirado de
todo mundo".

---

## 3. Os 15 parâmetros, e de onde cada valor veio

Parâmetro ausente é erro `PARAMETRO_AUSENTE` (card 2.2 §2.3): não há default escondido no código, e o
que não estiver aqui não roda. Todos são `INTEIRO` e todos são editáveis na tela de Administração
(card 4.7).

| chave | valor | origem | o que decide |
|---|---|---|---|
| `projecao_horizonte_dias` | 60 | decisão de 31/08/2026 | Janela da projeção de demanda |
| `standby_alerta_dias` | 30 | decisão de 31/08/2026 | Dias em STANDBY até gerar pendência |
| `rep_prazo_dias` | 30 | card 2.5 §4 | Prazo para repor sem virar REP contínuo |
| `rep_capacidade_semanal` | 1 | card 2.5 §4 | Reposições por semana que o aluno consegue fazer |
| `rep_faltas_max` | 2 | card 2.5 §4 | Faltas à própria reposição que sugerem a virada |
| `rep_janela_volta_dias` | 30 | card 2.5 §4 | Carência para sugerir a volta a pontual |
| `ritmo_padrao_dias_INTERATIVO` | 30 | Ordem 5 §3 | Degrau `MEDIA_METODO`, Interativo |
| `ritmo_padrao_dias_INGLES` | 30 | Ordem 5 §3 | Degrau `MEDIA_METODO`, Inglês |
| `ritmo_padrao_dias_MODULAR` | 45 | Ordem 5 §3 | Passo do Modular sem cronograma |
| `ritmo_padrao_dias_PADRAO` | 30 | Ordem 5 §3 | Último recurso, se faltar a chave do método |
| `ritmo_janela_entregas` | 4 | Ordem 5 §3 | Entregas na média de ritmo (4 entregas = 3 intervalos) |
| `ritmo_intervalo_min_dias` | 7 | Ordem 5 §3 | Piso: abaixo disso é entrega em lote, não ritmo |
| `ritmo_intervalo_max_dias` | 120 | Ordem 5 §3 | Teto: acima disso é interrupção, não ritmo |
| `projecao_acelerar_pct` | 50 | Ordem 5 §3 | Percentual do ritmo do método para o aluno ACELERAR |
| `ritmo_calibracao_dias` | 180 | Ordem 5 §3 | Janela da mediana observada por método |

⚠️ **Nenhum destes valores é medição** — são leitura conservadora do plano. Os três
`ritmo_padrao_dias_<METODO>` são substituídos pela mediana do histórico migrado no **card 9.5**, e o
**card 11.2** repete a medição depois de três meses de uso, com os gatilhos objetivos que o card de
Ordem 5 §9 fixou.

O valor literal de cada chave está asserido em `supabase/tests/022_seed_inicial.sql`: parâmetro com
valor errado é pior que parâmetro ausente — a projeção e a virada REP **rodam**, com número errado e
cara de certo.

### 3.1 O que NÃO virou parâmetro

A nota do card pedia "política de entrega sem estoque" entre os parâmetros. **Não existe tal
parâmetro, e não deve existir:** a política foi fechada como *algoritmo* de `fn_registrar_entrega`
(card 2.2 §4 — reordena a trilha se houver outra apostila com estoque; bloqueia e abre
`COMPRA_SEM_ESTOQUE` se não houver nenhuma), e ela devolve **três status distintos** que a tela trata
um a um. Um parâmetro sem leitor seria decoração — a mesma razão pela qual o card 2.4 (a) recusa
código de permissão sem consumidor. Divergência registrada aqui e nas Notas do card.

---

## 4. O primeiro usuário de direção — as duas metades

O card 3.5 fechou o espelho `auth.users → usuario`: o convite pelo painel do Auth já cria a linha de
`usuario` sozinho. O que faltava é `usuario_perfil`. Sem ele a pessoa **entra**,
`fn_minhas_permissoes()` devolve vazio e todas as telas ficam ocultas — sem erro. Até este card **não
havia em quem logar no dev**, e o card 3.7 depende disso.

O e-mail mora no parâmetro **`direcao_inicial_email`**, não no corpo de nenhuma função: e-mail
digitado errado se corrige na tela de Administração, não numa migração nova.

São duas metades, porque a ordem entre o convite e o deploy não é controlável:

| Metade | Objeto | Cobre |
|---|---|---|
| (a) | `fn_seed_direcao_inicial(unidade)`, chamada no fim da migração | O convite **já aconteceu** quando o deploy chegou |
| (b) | `tg_usuario_direcao_inicial`, trigger `after insert on usuario` | O caso normal: a migração chega antes, o convite depois |

Com só a metade (a) o seed rodaria em produção, **não encontraria ninguém e não faria nada** — o
silêncio que este projeto já catalogou três vezes. A comparação é `lower()` dos dois lados: quem
digita um convite não pensa em maiúscula, e o GoTrue guarda o que recebe.

`fn_seed_direcao_inicial` lê `parametro` **diretamente**, e não por `fn_param_txt`: a função de
parâmetro levanta `PARAMETRO_AUSENTE`, e as unidades da escola-fixture não têm direção inicial — uma
exceção ali derrubaria a criação de todo usuário de teste. Devolve `false` em silêncio, que é o
resultado correto de "esta unidade não tem bootstrap".

⚠️ Como todo parâmetro, `direcao_inicial_email` é legível por qualquer autenticado da unidade (card
3.4). É o e-mail de quem dirige a escola, não um segredo — segredo continua indo para o Vault (card
2.9), e `parametro` **nunca** recebe segredo.

### 4.1 Sequência operacional

**Dev** (já feito no merge deste card): a migração cria `MATRIZ`; Irineu convida o e-mail pelo painel
do Auth do projeto `ncdfolxdupbbfvtydngx`; o espelho cria `usuario` e o trigger atribui `DIRECAO`. Em
dev **`MATRIZ` é a única unidade ativa**, então o convite pelo painel funciona sem metadado — é o
fallback do card 3.5 (b), que se fecha sozinho na Fase 11.

**Produção**: idêntico, depois da promoção.

Exercitado ponta a ponta no stack local em 01/09/2026 (convite pela Admin API com o e-mail em caixa
diferente, login por senha, `rpc/fn_minhas_permissoes` devolvendo **50** códigos e `/rest/v1/unidade`
devolvendo o nome real).

---

## 5. Uma fonte só para a escola-fixture

O corpo do seed é exposto como **função idempotente que recebe a unidade** (`fn_seed_acesso`), e
`supabase/seed.sql` chama exatamente a mesma função para `ESCOLA_A` e `ESCOLA_B`. É a camada
`acesso_seed_real` que o card 3.4.5 declarou e deixou devida.

Sem isso a fixture ficaria com **uma matriz de mentira ao lado da real** — parecida, e livre para
divergir. O teste de paridade do card 2.8 §6.3 compara contagem de linhas entre perfis: ele passaria
comparando a tela contra a mentira. `supabase/tests/001_infra_teste.sql` assere que o conjunto de
códigos da fixture é **idêntico** ao da unidade real; contagem igual com códigos diferentes passaria,
essa asserção não.

As seis funções `fn_seed_*` ficam sem `execute` para `public`, `anon` e `authenticated`: publicá-las
no PostgREST seria oferecer pela API uma ação que não existe em tela nenhuma.

---

## 6. O que este card fechou e o que deixou

**Fechou** (todos apontavam para o 3.6):

| Origem | Pendência |
|---|---|
| card 2.5 | Quatro parâmetros `rep_*` no seed — **bloqueante** |
| card Ordem 5 | Nove parâmetros da projeção no seed — **bloqueante** |
| card 3.4.5 | Camada `acesso_seed_real` da escola-fixture — **bloqueante para fechar verde** |
| card 3.5 | Primeiro usuário de direção ligado a `DIRECAO` — **bloqueante para o card 3.7** |
| card 2.4 §9 | Os três pontos da matriz confirmados por Irineu |
| card 2.8 §5.1 | C11 na versão **cheia**: todo código citado em política existe no catálogo gravado |

**Deixou:**

1. **Card 4.7.5 (histórico da matriz) ganha um consumidor concreto** — é ele que fecha o caso
   residual do §2.1. Enquanto não existir, o seed não sabe distinguir "nunca foi dado" de "foi tirado
   de todo mundo".
2. **Card 3.7**: os oito usuários da fixture e o usuário real do dev agora logam com perfil; a camada
   de sessão tem o que ler.
3. **Card 4.7 (tela de Administração)**: `direcao_inicial_email` aparece na lista de parâmetros como
   qualquer outro. Não é caso especial — é bootstrap que já cumpriu o papel.
