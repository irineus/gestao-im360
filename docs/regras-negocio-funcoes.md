# Regras de negócio como funções, triggers e rotinas

**Card 2.2 — Fase 2 (Planejamento e Design).** Última atualização: 01/09/2026 (ajustes do card 2.5).

Este documento diz **onde vive cada regra da seção 6 do plano** e qual é a **assinatura** de cada
objeto de banco que a implementa. É design, não implementação: nenhum arquivo de
`supabase/migrations/` é criado aqui. Cada card das Fases 3 a 8 recorta a sua parte
(ver §13, mapa função → card).

> **Conferido contra o DDL.** Os nomes de tabela, coluna e restrição usados aqui foram verificados
> um a um contra `docs/modelagem-dados-ddl.md` (card 2.1). Onde esta especificação **exige alteração
> no DDL** — tipos de pendência novos, um valor de status a mais em `bloco_aluno_reposicao` — isso
> está consolidado em §14, para entrar na migração da fase correspondente. Nenhuma alteração de DDL
> é feita por conta própria aqui.

---

## 1. Princípios: onde uma regra pode viver

Quatro camadas, nesta ordem de preferência. Uma regra desce de camada só quando a de cima não
consegue expressá-la.

| Camada | Quando usar | Custo de violar |
|---|---|---|
| **1. Restrição** (`check`, `unique`, `foreign key`, índice único parcial) | A regra é uma verdade estrutural sobre uma linha ou um conjunto | Impossível violar, inclusive por migração e por `psql` |
| **2. Trigger** | A regra depende de outras linhas/tabelas, ou precisa valer mesmo quando alguém escreve direto na tabela | Impossível violar por PostgREST ou SQL ad hoc |
| **3. Função de aplicação** (`fn_*`, chamada por RPC) | A operação é composta (vários `INSERT`/`UPDATE` que precisam ser atômicos) ou precisa devolver um resultado ao cliente | Violável só se alguém escrever direto nas tabelas — e aí a camada 2 barra |
| **4. Rotina agendada** (`rt_*` via `pg_cron`) | A regra é sobre a passagem do tempo, não sobre um evento (STANDBY prolongado, previsão vencida) | Detecção atrasada em até 24 h |

**Consequência de projeto:** toda operação composta tem *as duas* camadas — a função de
aplicação, que é o caminho normal e devolve um resultado usável na tela, e o trigger, que é a
garantia. Registrar entrega, por exemplo, é `fn_registrar_entrega` (camada 3) sobre uma
`movimento_estoque` que já é imutável por trigger e por ausência de política de RLS (camadas 1 e 2).

### 1.1 Convenções

| Prefixo | Significado |
|---|---|
| `fn_` | função de infraestrutura ou de aplicação (chamável por RPC quando tem `grant` para `authenticated`) |
| `fn_` | também a função de trigger (`returns trigger`) — o DDL já usa `fn_movimento_imutavel()` |
| `tg_` | o trigger em si (`tg_<tabela>_<regra>`) — prefixo já estabelecido pelo DDL do card 2.1 |
| `rt_` | rotina agendada, chamada só pelo `pg_cron` |
| `tp_` | tipo composto de retorno |
| `v_` | view de leitura (card 2.3) |

- **Toda** função declara `set search_path = public, pg_temp`. Sem isso, `security definer` é um
  buraco de segurança conhecido.
- Funções de aplicação são **`security invoker`** (o padrão): a RLS do usuário se aplica dentro
  delas. Uma função que precisa enxergar além da RLS é exceção documentada em §2.2.
- `revoke execute on function ... from public;` em tudo; `grant execute ... to authenticated`
  apenas nas funções de aplicação. Rotinas `rt_*` não recebem `grant` nenhum.
- Volatilidade explícita: `immutable` nas tabelas de decisão puras, `stable` nas de leitura,
  `volatile` (padrão) nas que escrevem. Uma função de leitura marcada errado é bug de performance
  e de correção dentro de uma mesma transação.

### 1.2 Erros: código, mensagem e status HTTP

Toda violação de regra de negócio é levantada assim:

```sql
raise exception using
  errcode = 'PT409',                               -- PostgREST devolve HTTP 409
  message = 'Bloco lotado: 10 de 10 vagas ocupadas em 02/09/2026.',
  detail  = '{"codigo":"BLOCO_LOTADO","bloco_id":"…","capacidade":10,"ocupacao":10}',
  hint    = 'Remova um aluno do bloco ou use outro horário.';
```

- **`errcode`**: SQLSTATE no formato `PT<status>` — o PostgREST lê os três dígitos e devolve esse
  status HTTP. `PT403` (sem permissão), `PT404` (não encontrado), `PT409` (conflito de estado:
  lotado, sem estoque, transição inválida), `PT422` (dado incoerente).
- **`detail`**: JSON com `codigo` (constante estável, em MAIÚSCULAS) e os dados que a tela precisa
  para montar a mensagem. **O Flutter trata pelo `codigo`, nunca pelo texto da mensagem.**
- **`message`**: português, para o usuário final, já com os números do caso.

Catálogo de códigos em §12.

### 1.3 O que **não** é exceção

Quando a operação falha mas o sistema precisa **registrar** o que aconteceu (uma pendência, um
histórico), levantar exceção é errado: o `raise` derruba a transação inteira e apaga o registro
junto. Nesses casos a função **retorna um status** e persiste o efeito colateral.

O caso concreto é a entrega sem nenhum estoque na trilha (§6.2): a função devolve
`status = 'BLOQUEADA_SEM_ESTOQUE'` e **grava a pendência de compra**. Se levantasse exceção, a
pendência morreria no rollback e ninguém compraria a apostila.

---

## 2. Infraestrutura comum

### 2.1 Já definidas no DDL (card 2.1)

| Função | Papel |
|---|---|
| `fn_auditoria()` | trigger `before insert or update` em toda tabela: preenche `criado_em/por`, `atualizado_em/por` |
| `fn_unidade_atual() → uuid` | unidade do usuário autenticado; usada em toda política de RLS |
| `tem_permissao(p_codigo text) → boolean` | `usuario_perfil` → `perfil_permissao` → `permissao`; usada em RLS e nos guards do Flutter |
| `fn_movimento_imutavel()` | função do trigger `tg_movimento_imutavel`, que barra `update`/`delete` em `movimento_estoque` |

Ambas as duas do meio são `security definer` com `search_path` fixo, para não recursarem na RLS
de `usuario_perfil`.

### 2.2 Novas: contexto de rotina

**Problema.** O DDL fechou `enable` + **`force`** row level security em todas as tabelas. `force`
aplica RLS **inclusive ao dono da tabela** — então uma rotina `pg_cron` rodando como `postgres`,
mesmo `security definer`, enxerga zero linhas: sem `auth.uid()`, `fn_unidade_atual()` devolve
`null` e toda política reprova. Sem resolver isso, nenhuma rotina diária funciona.

**Solução — contexto de rotina explícito, por unidade:**

```sql
create function fn_contexto_rotina() returns boolean
  language sql stable set search_path = public, pg_temp
as $$ select coalesce(current_setting('app.rotina', true), '') = 'on' $$;
```

- `fn_unidade_atual()` passa a devolver `current_setting('app.rotina_unidade', true)::uuid`
  quando `fn_contexto_rotina()` é verdadeiro, e a unidade do usuário autenticado caso contrário.
- `tem_permissao(codigo)` devolve `true` quando `fn_contexto_rotina()` é verdadeiro.
- As duas GUCs só são escritas por `set_config(..., is_local => true)` **dentro** das funções
  `rt_*`, que são `security definer` e **sem `grant execute` para `anon`/`authenticated`**. O
  PostgREST só expõe funções com `grant`; um cliente não tem como entrar nesse contexto.
- `is_local => true` amarra o contexto à transação: ele evapora no `commit`, mesmo se a rotina
  falhar no meio.

Cada `rt_*` faz `for r in select id from unidade where ativo loop … end loop`, setando as GUCs no
início de cada volta. **Multi-unidade sai de graça** — a rotina já nasce correta para a segunda
unidade da Fase 11.

> **Decisão nova, para as Decisões vigentes:** `fn_unidade_atual()` e `tem_permissao()` ganham o
> desvio de contexto de rotina. É a única forma de conciliar `force row level security` com
> `pg_cron` sem depender de `BYPASSRLS` (atributo que o Supabase não concede ao papel `postgres`).

### 2.3 Leitura de parâmetros

```sql
fn_param_int(p_chave text, p_default integer default null) → integer   -- stable
fn_param_txt(p_chave text, p_default text    default null) → text      -- stable
```

Lê `parametro` da unidade corrente; erro `PT422 / PARAMETRO_AUSENTE` se não houver valor nem
default. Toda constante de negócio (`projecao_horizonte_dias`, `standby_alerta_dias`,
`ritmo_padrao_dias_<METODO>`) passa por aqui — nenhum número mágico dentro de função.

```sql
fn_exige_permissao(p_codigo text) → void   -- raise PT403 / SEM_PERMISSAO se tem_permissao() for falso
```

Usada no topo de toda função de aplicação. A RLS já barraria a escrita, mas o erro dela é opaco
("nenhuma linha afetada"); `fn_exige_permissao` dá ao usuário a mensagem certa e o código estável.

---

## 3. Alunos e status

### 3.1 Transições permitidas

Tabela de decisão pura, em função `immutable` — testável sem banco de dados carregado:

```sql
create function fn_aluno_transicao_valida(p_de text, p_para text) returns boolean
  language sql immutable set search_path = public, pg_temp
as $$
  select (p_de, p_para) in (
    ('ATIVO','ACELERAR'), ('ACELERAR','ATIVO'),
    ('ATIVO','STANDBY'),  ('ACELERAR','STANDBY'),
    ('STANDBY','ATIVO'),  ('STANDBY','ACELERAR'), ('STANDBY','TRANCADO'),
    ('TRANCADO','ATIVO'), ('TRANCADO','ACELERAR'),
    ('ATIVO','FORMADO'),  ('ACELERAR','FORMADO')
  ) or p_para = 'CANCELADO';                       -- qualquer origem → CANCELADO
$$;
```

Duas leituras deliberadas do plano, que ele não fecha:
- **TRANCADO → ATIVO/ACELERAR é permitido** (reativação de matrícula trancada). O plano só
  descreve a ida; barrar a volta obrigaria a recadastrar o aluno e perder o histórico.
- **FORMADO e CANCELADO são terminais** — sair deles exige estorno explícito pela direção
  (`fn_aluno_reverter_status`, §3.4), não uma transição comum.

### 3.2 Triggers em `aluno`

| Objeto | Momento | Faz |
|---|---|---|
| `tg_aluno_status_valida` | `before update of status on aluno for each row` | recusa transição fora de `fn_aluno_transicao_valida` (`PT409 / TRANSICAO_INVALIDA`); exige o gate de FORMADO (§3.3); grava `new.status_desde = current_date` |
| `tg_aluno_status_hist` | `after update of status on aluno for each row` | insere `aluno_status_hist` (`status_anterior`, `status_novo`, `ocorrido_em`, `usuario_id`, `motivo`) |
| `tg_aluno_status_desaloca` | `after update of status on aluno for each row` | se o novo status **não** é ATIVO/ACELERAR: `bloco_aluno.ativo = false`, `turma_modular_aluno.ativo = false` e cancela `bloco_aluno_reposicao` com data futura (§4.4) |
| `tg_aluno_trilha_inicial` | `after insert on aluno for each row` | se `combo_id` não é nulo, chama `fn_trilha_gerar` (§5.1) |
| `tg_aluno_combo_alterado` | `after update of combo_id on aluno for each row` | **não** regenera a trilha: abre pendência `TRILHA_DIVERGENTE_COMBO` |

**O motivo da transição** chega ao trigger por `set_config('app.motivo_status', …, true)` feito
dentro de `fn_aluno_alterar_status`; num `UPDATE` direto ele fica nulo e o histórico registra
"alteração direta". O histórico nunca deixa de existir.

**Por que a mudança de combo não regenera a trilha:** trilha regenerada apaga entregas já feitas
ou duplica saídas de estoque. A pendência põe um humano na decisão, e a UI oferece o botão de
regeneração (`fn_trilha_gerar(..., p_substituir => true)`), que só é aceito enquanto não houver
nenhum item entregue.

### 3.3 O gate de FORMADO

`ATIVO`/`ACELERAR` → `FORMADO` só passa se **uma** das condições valer:

1. existe `certificado_checklist` do aluno com `certificado_status = 'ENTREGUE'`; **ou**
2. `tem_permissao('alunos.formar_sem_certificado')` — a "confirmação da direção" das Decisões
   vigentes, expressa como permissão e não como perfil, e registrada no motivo do histórico.

Caso contrário: `PT409 / FORMATURA_SEM_CERTIFICADO`.

### 3.4 Funções de aplicação

```sql
fn_aluno_alterar_status(p_aluno_id uuid, p_status text, p_motivo text) → void
  -- exige alunos.alterar_status; set_config do motivo; UPDATE aluno SET status = …
  -- devolve os erros dos triggers já traduzidos

fn_aluno_reverter_status(p_aluno_id uuid, p_status_destino text, p_motivo text) → void
  -- exige alunos.reverter_status (só direção na matriz inicial)
  -- único caminho para sair de FORMADO/CANCELADO; grava motivo obrigatório (não nulo, não vazio)
```

`p_motivo` é obrigatório nas duas para STANDBY, TRANCADO e CANCELADO (`PT422 / MOTIVO_OBRIGATORIO`).

---

## 4. Vagas e capacidade

### 4.1 Capacidade efetiva

```sql
create function fn_capacidade_efetiva(p_bloco_id uuid, p_data date default current_date)
  returns integer language sql stable set search_path = public, pg_temp
as $$
  select coalesce(
    b.capacidade_override,
    least(
      (select count(*) from pc p
        where p.sala_id = b.sala_id
          and p.status = 'OPERACIONAL'
          and not exists (                                   -- em manutenção sem substituto na data
            select 1 from pc_manutencao m
             where m.pc_id = p.id
               and m.pc_substituto_id is null
               and p_data between m.data_inicio and coalesce(m.data_fim, 'infinity'::date))),
      s.capacidade_nominal))
  from bloco_horario b join sala s on s.id = b.sala_id
  where b.id = p_bloco_id;
$$;
```

- `capacidade_override` **vence sempre** — é o escape manual da secretaria.
- `least(pcs_operacionais, capacidade_nominal)` é a leitura literal do plano ("nº de PCs
  OPERACIONAIS da sala, mín. com capacidade nominal").
- Um PC em manutenção **com** substituto não reduz a capacidade (regra do plano, §6/PCs).
- O parâmetro `p_data` é o que permite avaliar admissão futura e reposição agendada.

> ✅ **Fechada em 03/09/2026 pelo card 5.2**, em `supabase/migrations/20260903210000_capacidade_vagas.sql`
> — o corpo acima era o ponto de partida e **tinha dois furos**, os dois só visíveis ao ler este §4.1
> junto com o §4.6 (cada metade, sozinha, parece certa):
>
> 1. **`status = 'OPERACIONAL'` mata o substituto.** O §4.6 manda `tg_pc_manutencao_status`
>    (card 5.4) pôr o PC em `MANUTENCAO` enquanto a manutenção estiver aberta, **com substituto ou
>    sem**. No dia em que aquele trigger existir, o filtro por `OPERACIONAL` derruba também o PC
>    substituído, o `not exists` vira letra morta e "um `pc_substituto_id` mantém a capacidade"
>    (plano, §6) deixa de valer — **em silêncio, e num card que não fala de capacidade**.
> 2. **Substituto da própria sala não cria máquina.** Apontar `pc_substituto_id` para um PC que já
>    está na sala somaria a mesma máquina duas vezes: dez PCs físicos valendo onze vagas, com a cara
>    de um número certo.
>
> **A fórmula final.** Um PC da sala conta na data quando: (1) não está `DESATIVADO`; (2) não tem
> manutenção cobrindo a data **sem substituto válido**; e (3) está `OPERACIONAL` **ou** tem
> manutenção cobrindo a data **com** substituto válido. *Substituto válido* é o que está em **outra
> sala** — o da própria já estava contado. Capacidade = `coalesce(override, least(esses PCs,
> capacidade_nominal))`.
>
> A cláusula (2) é o que faz a função responder por uma **data** e não por "agora" (o `status` é
> estado do presente); a (3) é o que impede o mundo **pré-5.4** de mentir na direção oposta — PC
> marcado `MANUTENCAO` à mão, sem linha em `pc_manutencao`, não conta. As duas junto tornam a fórmula
> correta antes e depois do card 5.4, que é o requisito de verdade.
>
> ⚠️ **CORREÇÃO DE FATO (03/09/2026, card 5.4) — o intervalo é `[data_inicio, data_fim)`.** O corpo
> entregue pelo card 5.2 usava `p_data between data_inicio and coalesce(data_fim, 'infinity')`,
> intervalo fechado, e este §4.6 dizia "ao fechar (`data_fim` preenchida e **passada**)". O app lê o
> contrário desde o card 4.5 (c): *`data_fim` é previsão; manutenção aberta = sem fim ou fim à frente
> de hoje, e "Encerrar" grava o fim de **hoje**"*. Duas leituras da mesma coluna, que nunca se
> encontravam — até o status passar a ser derivado. Sob a leitura fechada, encerrar a manutenção hoje
> deixaria o PC em MANUTENCAO até amanhã: a turma da noite perderia uma vaga por uma máquina que já
> voltou, e a linha da tela mostraria "Em manutenção" sem manutenção aberta ao lado. **Resolvido a
> favor do app**, que é quem produz o único "encerrar" do sistema: `data_fim` é o dia em que o PC
> **volta a operar**. As duas bordas viraram asserção no teste `041`.
>
> ⚠️ **Limite conhecido, registrado e não resolvido:** o PC emprestado continua contando na **sala de
> origem**. `pc.sala_id` diz onde a máquina está cadastrada, não onde ela está hoje, e conservar
> máquinas entre salas exigiria modelar a mudança de lugar — decisão que não é deste card e que
> ninguém pediu. Enquanto isso, emprestar um PC infla a capacidade da sala que emprestou.

### 4.2 Ocupação e vagas

```sql
fn_ocupacao_bloco(p_bloco_id uuid, p_data date default current_date) → integer   -- stable
```

Conforme a decisão de 31/08/2026 (REP híbrido), a lotação numa data é

```
count(bloco_aluno            where bloco_id = X and ativo)
+ count(bloco_aluno_reposicao where bloco_id = X and data = p_data and status = 'PREVISTA')
```

```sql
fn_vagas_livres(p_bloco_id uuid, p_data date default current_date) → integer     -- stable
  -- greatest(fn_capacidade_efetiva - fn_ocupacao_bloco, 0); alimenta o dashboard (card 5.9)
```

> ✅ **As três entregues em 03/09/2026 pelo card 5.2**, e não pelo 5.3 como diz o mapa de §13 —
> divergência registrada. Três documentos posteriores mandaram: a Nota do card 5.2 ("vagas livres =
> capacidade − alocados ativos"), o §10 (#3) do card 2.3, que nomeia o **5.2** como dono da mudança
> para `security definer` das **duas** primeiras, e o comentário (d) da fixture do card 5.1, que
> descreve a reposição `PREVISTA` no bloco vazio como "a asserção que reprova uma `fn_ocupacao_bloco`
> (card 5.2) que somou só `bloco_aluno`". Capacidade sem ocupação não vira vaga, e nenhuma das três
> tem como ser exercitada sozinha.
>
> Três decisões do corpo, todas com `p_data default public.fn_hoje()` (ajuste 1 do card 2.3):
>
> - **Nenhum filtro por `tipo`.** REM, PRE, REP e NOVO ocupam vaga igual. Aluno remoto ocupa vaga
>   (Nota do card), e `NOVO` também — a vaga está reservada desde a `data_inicio_prevista`, senão a
>   secretaria a vende duas vezes.
> - **Zero e nulo dizem coisas diferentes.** `0` é "bloco seu, e vazio"; **nulo** é "não é da sua
>   unidade / não existe". As duas primeiras filtram `b.unidade_id = fn_unidade_atual()` no corpo — é
>   o preço do `definer`, que roda com `BYPASSRLS` e não tem RLS para lhe segurar a mão.
> - ⚠️ **`greatest(null, 0)` devolve `0`**, porque o `greatest` **ignora nulos**. Escrita como o
>   comentário acima sugere, `fn_vagas_livres` responderia "0 vagas livres" para um bloco de outra
>   unidade — mentira plausível, e na direção que ninguém confere ("lotado"). O corpo usa `case`
>   explícito para preservar o nulo. `fn_vagas_livres` **não** é `definer`: não lê tabela nenhuma, só
>   compõe as duas de cima (mesma decisão que deixou `fn_pc_exclusao_valida` fora da lista do C8).

### 4.3 Admissão

| Objeto | Momento | Faz |
|---|---|---|
| `tg_bloco_aluno_admissao` | `before insert or update of ativo, bloco_id on bloco_aluno` | valida, quando a linha fica ativa: aluno em ATIVO/ACELERAR (`PT409 / ALUNO_INATIVO`); método do aluno = método do bloco (`PT422 / METODO_INCOMPATIVEL`); ocupação < capacidade (`PT409 / BLOCO_LOTADO`) |
| `tg_reposicao_admissao` | `before insert or update on bloco_aluno_reposicao` | mesma checagem, **na data da reposição**; data no passado só com `turmas.lancar_reposicao_retroativa` |

```sql
fn_bloco_admitir(p_bloco_id uuid, p_aluno_id uuid, p_tipo text,
                 p_data_inicio_prevista date default null) → uuid
fn_bloco_remover(p_bloco_id uuid, p_aluno_id uuid, p_motivo text default null) → void
```

`fn_bloco_admitir` exige `turmas.alocar`, faz `pg_advisory_xact_lock` no bloco (§4.5), reativa a
alocação existente se já houver uma inativa (em vez de criar linha duplicada — a unicidade parcial
`bloco_aluno_ativo_uk` proíbe a duplicata ativa) e devolve o `id` da alocação.

`p_tipo` ∈ (REM, PRE, REP, NOVO); `data_inicio_prevista` é obrigatória para NOVO
(`PT422 / DATA_PREVISTA_OBRIGATORIA`).

> ✅ **Entregues em 03/09/2026 pelo card 5.3**, em
> `supabase/migrations/20260903230000_admissao_lotacao_rep.sql`. Quatro decisões do corpo:
>
> - **Nulo é erro, não "sem opinião".** `fn_capacidade_efetiva` e `fn_ocupacao_bloco` devolvem
>   **nulo** para bloco de outra unidade (card 5.2), e `ocupacao >= null` é **nulo** — um
>   `if ... then raise` escrito sem contar com isso não dispara, e a lotação passa **em silêncio**
>   justamente na escrita que não deveria existir. O trigger levanta `PT404 / BLOCO_INEXISTENTE`.
>   Medido: sem essa guarda, um `insert` como `postgres` (que tem BYPASSRLS) entra sem checagem de
>   vaga nenhuma.
> - **A vaga só é disputada quando a linha ENTRA na conta** — `insert` ativo, volta de inativa para
>   ativa, ou troca de bloco. Conferir em todo `update` faria mudar só o `tipo` de uma alocação já
>   ativa responder `BLOCO_LOTADO` num bloco que não mudou de tamanho, e a virada REP dentro do
>   próprio bloco do aluno ficaria impossível.
> - **`fn_bloco_remover` ganhou onde gravar o motivo.** A coluna `bloco_aluno.motivo_saida` nasce
>   aqui porque `p_motivo` (§4.3) e o `MOTIVO_OBRIGATORIO` de `fn_rep_voltar_pontual` (card 2.5 §5.2)
>   exigiam do usuário um dado que se descartava. `tg_aluno_status_desaloca` passou a escrever nela
>   o status que tirou o aluno da turma, que é o caso mais comum de saída.
> - **Remover quem não está na turma DÓI** (`PT404 / ALOCACAO_INEXISTENTE`): silêncio ali é a tela
>   dizendo "removido" sobre uma turma em que o aluno continua.
>
> Quatro códigos novos no catálogo de §12 — `BLOCO_INEXISTENTE`, `ALOCACAO_INEXISTENTE`,
> `REPOSICAO_INEXISTENTE` e `REPOSICAO_NAO_PREVISTA` (contrato de 28 → 32) —, todos pelo precedente
> de `PC_INEXISTENTE` (card 2.9) e `ALUNO_INEXISTENTE` (card 4.2).

### 4.4 Reposição (metade pontual do REP)

```sql
fn_reposicao_agendar(p_aluno_id uuid, p_bloco_id uuid, p_data date,
                     p_bloco_origem_id uuid default null, p_data_origem date default null,
                     p_observacao text default null) → uuid
fn_reposicao_registrar(p_reposicao_id uuid, p_compareceu boolean) → void   -- PREVISTA → REALIZADA | FALTOU
fn_reposicao_cancelar(p_reposicao_id uuid, p_observacao text) → void       -- PREVISTA → CANCELADA
```

`bloco_id` é o bloco **onde o aluno vai repor**; `bloco_origem_id` e `data_origem` guardam a aula
perdida. A unicidade `(bloco_id, aluno_id, data)` do DDL já impede agendar a mesma reposição duas
vezes.

Só `status = 'PREVISTA'` ocupa vaga. `REALIZADA`, `FALTOU` e `CANCELADA` saem da conta de
lotação — o passado não bloqueia o presente.

> ⚠️ **Exige alteração no DDL (§14):** o `check` atual de `bloco_aluno_reposicao.status` aceita só
> `PREVISTA`, `REALIZADA` e `CANCELADA`. Falta **`FALTOU`** — sem ele, o aluno que não comparece à
> reposição fica indistinguível de quem a cancelou com antecedência, e é exatamente essa diferença
> que o critério do card 2.5 mede (§3.4 de `docs/regra-virada-rep.md`).

> ✅ **A virada pontual → REP contínuo foi fechada pelo card 2.5** (01/09/2026), em
> `docs/regra-virada-rep.md`. O ponto de extensão foi honrado: `fn_rep_avaliar_virada(p_aluno_id uuid)
> → text` continua com a mesma assinatura e os mesmos três valores `'MANTER'` / `'SUGERIR_CONTINUO'` /
> `'SUGERIR_VOLTA'`; só o corpo deixou de ser `'MANTER'` fixo. O critério é aritmético (débito de
> aulas em aberto × capacidade semanal × semanas até o prazo, com gatilho independente por
> reincidência de `FALTOU`), a virada é **sugerida por pendência e executada por uma pessoa**, e as
> funções de execução são `fn_rep_virar_continuo` / `fn_rep_voltar_pontual`. Aquele card acrescenta
> seis ajustes a esta especificação, todos consolidados em §14 (itens 5 a 10).

### 4.5 Concorrência: por que o advisory lock

Duas secretarias admitindo o último aluno ao mesmo tempo passariam as duas pela checagem de
capacidade (`read committed` não enxerga a linha ainda não commitada da outra) e o bloco ficaria
com 11 alunos em 10 PCs. Nenhuma constraint pega isso — é uma regra de **agregado**, não de linha.

Toda função que admite alguém num bloco começa com

```sql
perform pg_advisory_xact_lock(hashtextextended(p_bloco_id::text, 0));
```

serializando só as admissões daquele bloco. O lock é liberado no fim da transação, sem
`unlock` explícito. Mesmo padrão em `fn_turma_modular_admitir` e, com a chave do material, em
`fn_registrar_entrega`.

> ✅ **Exercitado de verdade em 03/09/2026 (card 5.3)**, em
> `supabase/tests_concorrencia/admissao_ultima_vaga.sh`: duas sessões `psql` simultâneas admitindo
> alunos diferentes no bloco de 9/10 — uma passa, a outra recebe `BLOCO_LOTADO`, e o bloco fecha em
> 10, nunca 11. **A contraprova foi vista**: removido o `pg_advisory_xact_lock`, as duas admissões
> passam e o bloco fica com **11 alunos em 10 PCs**, com o script reprovando por contagem (e não por
> *timeout*, que é o que o §7 do card 2.8 exige). Sem essa contraprova, um teste de concorrência que
> nunca reprova é indistinguível de um que não testa nada.
>
> Nota operacional: o script usa `psql` quando ele existe no PATH e cai para o `psql` de dentro do
> container do stack local quando não existe — teste que só roda no CI é teste que ninguém roda
> antes de abrir o PR.

### 4.6 Manutenção de PC

| Objeto | Momento | Faz |
|---|---|---|
| `tg_pc_manutencao_status` | `after insert or update on pc_manutencao` | `pc.status = 'MANUTENCAO'` enquanto a manutenção estiver aberta e `current_date` dentro da janela; ao fechar (`data_fim` preenchida e passada), volta a `OPERACIONAL` — nunca mexe em PC `DESATIVADO` |
| `tg_pc_revalida_blocos` | `after insert or update on pc_manutencao`, `after update of status, sala_id on pc` | chama `fn_revalidar_blocos_sala(sala_id)` |

```sql
fn_revalidar_blocos_sala(p_sala_id uuid) → integer   -- nº de blocos com pendência aberta
```

Para cada `bloco_horario` ativo da sala: se `fn_ocupacao_bloco > fn_capacidade_efetiva`, abre
`BLOCO_ACIMA_CAPACIDADE` (severidade ALTA); senão, resolve a pendência aberta desse bloco.

**Nunca remove aluno.** É a regra explícita do plano: a turma cheia não encolhe; ela vira
pendência, e novas admissões ficam bloqueadas pelo `tg_bloco_aluno_admissao` até normalizar —
o que já acontece naturalmente, já que a capacidade caiu abaixo da ocupação.

> ✅ **Fechado em 03/09/2026 pelo card 5.4**, em
> `supabase/migrations/20260904010000_manutencao_pc_capacidade.sql`, com os dois triggers, a função
> e mais três coisas que o quadro acima não previa.
>
> **1. `pc.status` passou a ser DERIVADO, e a regra mora numa função só.**
> `fn_pc_status_sincronizar(pc)` decide o status a partir de **todas** as manutenções do PC — não da
> linha que disparou o trigger. Um PC pode ter duas em aberto (a corretiva de ontem e a preventiva de
> hoje), e encerrar uma delas não devolve a máquina: um trigger que decidisse pelo `new` a devolveria,
> com a capacidade da sala subindo por engano e a vaga sendo vendida. A mesma função serve ao trigger
> (evento) e a `rt_pcs_normaliza` (passagem do tempo), porque **duas cópias divergiriam para o lado
> silencioso** — o trigger acertando e a rotina desfazendo de madrugada.
>
> **2. `rt_pcs_normaliza` existe porque o tempo passar NÃO É EVENTO**, e faz as duas direções. O §11
> a descreve como "fecha manutenções com data_fim vencida; devolve PCs a OPERACIONAL"; **divergência
> registrada nas duas metades**. Não há manutenção a "fechar": com `data_fim` no passado ela já está
> fechada pelas próprias datas, e escrever em `pc_manutencao` inventaria histórico que ninguém
> registrou. E "devolver a OPERACIONAL" é só metade da regra — uma manutenção **agendada** que começa
> hoje não dispara nada, e sem a outra direção o PC ficaria OPERACIONAL enquanto estivesse parado,
> que é o erro na direção que vende vaga inexistente.
>
> **3. `PC_SEM_SUBSTITUTO` usa o MESMO "sem substituto" da fórmula da capacidade** (§4.1, decisão (b)
> do card 5.2): substituto da **própria sala** não repõe máquina nenhuma, logo não fecha a pendência.
> Uma condição escrita como "tem substituto?" em vez de "tem substituto que reponha?" fecharia
> dizendo "resolvido" exatamente enquanto a capacidade seguisse caída.
>
> **4. `BLOCO_ACIMA_CAPACIDADE` voltou ao dono que o §10.1 sempre lhe deu.** O card 5.5 a tinha posto
> em `rt_pendencias_diaria` (divergência registrada lá, porque a função ainda não existia); mantê-la
> nos dois lugares seria manter **duas implementações da mesma comparação**, com o mesmo `format` e a
> mesma severidade, livres para divergir na primeira vez que alguém mexesse numa só — a terceira
> implementação que o card 2.3 §4.1 proíbe. O caminho diário passa a ser `rt_capacidades`, que
> `rt_diaria` executa **antes** de `rt_pendencias_diaria`; o caminho por evento é
> `tg_pc_revalida_blocos`; e os dois usam a **mesma** `chave_dedup`, de modo que convergem na dedup.
>
> **A admissão bloqueada não precisou de código novo, e isso foi CONFERIDO antes de escrever.**
> `tg_bloco_aluno_admissao` compara `ocupacao >= capacidade` desde o card 5.3, e bloco acima da
> capacidade satisfaz `>=` com folga. Uma segunda guarda a partir da **pendência** teria modo de falha
> próprio: pendência é estado gravado, e um bloco já normalizado continuaria bloqueado até alguém
> fechá-la. Virou asserção (seção 4 do teste `091`), não frase de relatório.
>
> **Divergência benigna com o quadro:** `tg_pc_revalida_blocos` revalida **as duas** salas quando um
> PC muda de `sala_id` — a de destino ganha máquina e a de origem perde, e o singular do quadro não
> tinha como dizer de qual das duas falava.
>
> ⚠️ **Duas contraprovas saíram VERDES e corrigiram o que estava escrito**, as duas registradas na
> migração: (a) `fn_pc_status_sincronizar` nasceu `security definer` com a justificativa da RLS, e a
> sabotagem que devia prová-la passou — quem atravessa a RLS é o trigger `definer` que a chama, e ela
> virou `invoker` pelo precedente de `fn_pendencias_fechar_ausentes`; (b) a **ordem** entre os dois
> triggers de `pc_manutencao` parecia decisiva e **não é**, porque o `update` de `pc.status` dispara
> `tg_pc_revalida_blocos` em `pc` e revalida a sala de novo — a independência vem da redundância entre
> os dois gatilhos, e quem remover o trigger de `pc` por achá-lo redundante traz a dependência de
> volta, calada.

---

## 5. Trilha do aluno

### 5.1 Geração pelo combo

```sql
fn_trilha_gerar(p_aluno_id uuid, p_combo_id uuid default null,
                p_substituir boolean default false) → integer   -- nº de itens criados
```

1. `p_combo_id` default = `aluno.combo_id`; sem combo, `PT422 / ALUNO_SEM_COMBO`.
2. Se já existe trilha e `p_substituir` é falso → `PT409 / TRILHA_JA_EXISTE`.
3. Se `p_substituir` e **algum item já entregue** → `PT409 / TRILHA_COM_ENTREGA` (a trilha com
   histórico de entrega é editada item a item, nunca substituída em bloco).
4. Materiais em `combo_curso.ordem` → `curso_material.ordem`, numerados de 10 em 10 (espaço para
   inserção manual sem renumerar).
5. Material repetido entre cursos do combo entra **uma vez**, na primeira posição em que aparece.
6. `origem = 'COMBO'` em todos.

✅ **Implementada em 04/09/2026 (card 6.2)**, com quatro coisas que a especificação deixava em
aberto e que o código teve de fechar:

- **Permissão: `alunos.editar_trilha` ∨ `alunos.criar`**, e não uma das duas sozinha. É a mesma
  condição da política de `insert` de `aluno_material` (card 6.1 §8.1) e pelo mesmo motivo escrito
  lá: a trilha nasce na matrícula, dentro da transação de quem cadastrou o aluno, e a regeneração
  pelo botão do card 6.6 é edição de trilha. Exigir só a primeira faria a matrícula falhar para um
  perfil que pode matricular.
- **A geração grava `aluno_material_hist`** (`GERACAO_COMBO`, uma linha por item), que é o que dá
  base de comparação a toda reordenação futura — e é o que obrigou a corrigir o `insert` de
  `aluno_material_hist` (achado 13 do §7 de `permissoes-matriz.md`). Na substituição, a trilha antiga
  sai com uma linha `REMOCAO` por item.
- **A função fecha a pendência `TRILHA_DIVERGENTE_COMBO`** do aluno (`fn_pendencia_resolver`), porque
  regenerar é exatamente a ação que a pendência pede. Pendência que ninguém fecha é a central do card
  5.8 perdendo credibilidade.
- **Aluno inexistente é `PT404 / ALUNO_INEXISTENTE`**, pelo precedente do card 4.2: a leitura é
  `invoker`, então aluno de outra unidade e aluno inexistente respondem a mesma coisa — quem não pode
  ver não descobre que existe.

### 5.2 Consulta

```sql
fn_trilha_proximo_material(p_aluno_id uuid) → uuid    -- stable; menor ordem com entregue = false; null = FIM
fn_trilha_atual(p_aluno_id uuid)          → uuid      -- stable; sinônimo — "livro atual" do plano
fn_trilha_em_fim(p_aluno_id uuid)         → boolean   -- stable; nenhum item pendente
```

"Livro atual" e "próximo" **não são colunas** — são derivados da trilha a cada consulta. Coluna
denormalizada aqui seria uma segunda fonte da verdade, que sai de sincronia no primeiro estorno.

✅ **Implementadas em 04/09/2026 (card 6.2)**, `stable` e `security invoker`. Duas consequências
escritas na migração porque são reais:

- **`fn_trilha_em_fim` devolve `true` para aluno SEM trilha nenhuma**, e é de propósito: é a mesma
  leitura da coluna `em_fim` de `v_dashboard_alunos_metodo` (card 2.3 §8.1, `pend.qtd = 0`). Manter
  as duas iguais é o que impede o dashboard e a ficha de discordarem sobre o mesmo aluno.
- **Sob RLS, "não tenho `alunos.ler`" e "a trilha acabou" respondem a mesma coisa** (nulo / `true`) —
  a redução silenciosa do card 2.3 §3.4. Aceito de propósito: `security definer` faria a função
  responder sobre alunos que o chamador não pode ver. Quem protege a tela é a guarda de rota do card
  2.4 §6; quem protege a escrita é `fn_exige_permissao` nas funções de §5.3, que é onde o dano
  existiria.

### 5.3 Edição manual

```sql
fn_trilha_inserir(p_aluno_id uuid, p_material_id uuid, p_apos_material_id uuid default null) → uuid
fn_trilha_remover(p_aluno_id uuid, p_material_id uuid, p_motivo text) → void
fn_trilha_reordenar(p_aluno_id uuid, p_material_id uuid, p_nova_ordem integer) → void

-- card 6.3: a mecânica da reposição, extraída de fn_trilha_reordenar e compartilhada com a entrega
fn_trilha_reposicionar(p_aluno_id uuid, p_material_id uuid, p_posicao integer,
                       p_motivo text, p_marcar_manual boolean default false) → void
```

Todas exigem `alunos.editar_trilha`, marcam `origem = 'MANUAL'`, recusam mexer em item já
entregue (`PT409 / ITEM_JA_ENTREGUE`) e gravam `aluno_material_hist` (`ordem_anterior`,
`ordem_nova`, `usuario_id`). O `motivo` é o enum fechado do DDL — `MANUAL` na edição pela tela,
`REMOCAO` na retirada, `GERACAO_COMBO` na geração inicial e `SEM_ESTOQUE` no reordenamento
automático de §6.2. ~~**Não há coluna de texto livre nessa tabela** (§14).~~ O
`unique (aluno_id, ordem) deferrable initially deferred` do DDL permite reordenar num único
`UPDATE`, sem passar por valores temporários.

✅ **Implementadas em 04/09/2026 (card 6.2)**, com três decisões de contrato que a assinatura acima
não fixava e que a tela do card 6.6 precisa conhecer:

- **`p_motivo` de `fn_trilha_remover` NÃO é o `motivo` da tabela.** O `motivo` da tabela é o `check`
  fechado e vale `REMOCAO` ali, sempre; o parâmetro é o **texto livre** que vai para
  `aluno_material_hist.observacao` — a coluna do ajuste 4 do §14, criada por este card. É a leitura
  que resolve a colisão de nome entre a assinatura daqui e a coluna de lá, e é por isso que o ajuste
  4 estava atribuído a este card. O motivo é **obrigatório** (`PT422 / MOTIVO_OBRIGATORIO`), pelo
  precedente de `fn_estornar_entrega` e `fn_rep_voltar_pontual`.
- **`p_nova_ordem` de `fn_trilha_reordenar` é a POSIÇÃO na trilha (1 = primeiro), não o valor bruto
  da coluna `ordem`.** A tela arrasta um item para "a terceira linha", não para "a ordem 30"; a
  numeração de 10 em 10 é artefato interno da geração, e contrato que vaza artefato interno obriga a
  tela a conhecê-lo. Posição fora das bordas é **grampeada** (arrastar para além do fim significa
  "põe no fim"), e não erro. A escrita é um único `UPDATE` renumerando de 10 em 10.
- **`fn_trilha_inserir` usa o ESPAÇO da numeração e renumera quando ele acaba.** Quatro inclusões
  seguidas na mesma fresta esgotam o intervalo (10 → 5 → 2 → 1); sem o ramo de renumeração a quinta
  cairia em cima da ordem existente. ⚠️ Achado da contraprova: por a `unique` ser **`DEFERRABLE
  INITIALLY DEFERRED`**, a colisão **não** levanta exceção no statement — ela só apareceria no
  `commit`. Um `lives_ok` sozinho passa verde com o ramo sabotado; quem acusa é a asserção que **lê a
  trilha de volta**. Erro novo: **`MATERIAL_JA_NA_TRILHA`** (409), sem o qual a segunda inclusão da
  mesma apostila chega à tela como um `23505` cru.

✅ **`fn_trilha_reposicionar` acrescentada em 04/09/2026 (card 6.3).** `fn_trilha_reordenar` passou a
ser a permissão mais uma chamada a ela; o contrato externo não mudou em nada (mesma assinatura,
mesmos códigos, mesma posição como parâmetro, mesmo `origem = 'MANUAL'` na linha movida). Ela **não
tem `fn_exige_permissao` própria** — quem a protege é `tg_aluno_material_colunas_permitidas`, que
alcança qualquer caminho até a coluna `ordem`, inclusive uma chamada RPC direta. As duas coisas que
ela garante sozinha, e por isso vivem nela e não nos chamadores, são as que uma chamada direta não
poderia pular: **item entregue não se move** e **toda reposição deixa linha em
`aluno_material_hist`**. O `p_motivo` é restrito a `MANUAL` e `SEM_ESTOQUE`: `GERACAO_COMBO` e
`REMOCAO` são de outros caminhos, e aceitá-los aqui deixaria o histórico contar uma história que não
aconteceu.

---

## 6. Entrega de apostila

A regra mais delicada do sistema: é onde a trilha, o estoque e a política de 31/08/2026 se
encontram, e onde a decisão de "não bloquear" pode virar estoque negativo se for mal escrita.

### 6.1 Tipo de retorno

```sql
create type tp_entrega_resultado as (
  status              text,     -- ENTREGUE | REORDENADA | BLOQUEADA_SEM_ESTOQUE
  material_id         uuid,     -- o que efetivamente saiu (null se bloqueada)
  material_solicitado uuid,     -- o que a trilha mandava entregar
  movimento_id        uuid,
  proximo_material_id uuid,     -- já recalculado
  em_fim              boolean
);
```

Três status, porque a tela precisa reagir diferente a cada um: confirmação simples, aviso de que a
trilha foi reordenada, ou alerta de compra.

### 6.2 A função

```sql
fn_registrar_entrega(p_aluno_id uuid, p_material_id uuid default null,
                     p_observacao text default null) → tp_entrega_resultado
```

1. `fn_exige_permissao('estoque.lancar_saida')`.
2. `select … from aluno where id = p_aluno_id for update` — serializa entregas do mesmo aluno.
3. Aluno precisa estar em ATIVO ou ACELERAR (`PT409 / ALUNO_INATIVO`).
4. `alvo := coalesce(p_material_id, fn_trilha_proximo_material(p_aluno_id))`;
   se nulo → `PT409 / TRILHA_EM_FIM`. Se `p_material_id` foi informado e não está pendente na
   trilha do aluno → `PT422 / MATERIAL_FORA_DA_TRILHA`.
5. `pg_advisory_xact_lock(hashtextextended(alvo::text, 0))` — serializa o par
   (checar saldo, gravar saída) daquele material. Sem isso, duas entregas simultâneas do último
   exemplar produzem saldo −1.
6. **Se `fn_saldo_material(alvo) <= 0`:** procura, em ordem de trilha, o próximo item pendente com
   saldo > 0.
   - **Achou** → `fn_trilha_reordenar` põe esse material na posição do pulado, grava
     `aluno_material_hist` com `motivo = 'SEM_ESTOQUE'` (o pulado continua pendente e volta a ser
     "próximo" quando houver estoque), abre pendência `ESTOQUE_ZERO` do material pulado, e segue
     com `status = 'REORDENADA'`.
   - **Não achou** (nenhum item pendente da trilha tem estoque) → abre pendência
     `COMPRA_SEM_ESTOQUE` (severidade ALTA) e **retorna** `status = 'BLOQUEADA_SEM_ESTOQUE'`
     **sem levantar exceção** (§1.3), para que a pendência sobreviva ao commit. Nada de estoque é
     movimentado.
7. `insert into movimento_estoque (tipo, quantidade, material_id, aluno_id, ocorrido_em, observacao)
   values ('SAIDA', -1, …)` — quantidade **com sinal**, e `movimento_sinal_ck` já garante o sinal
   por tipo. A autoria não é coluna própria: vem de `criado_por`, preenchido por `fn_auditoria()`.
8. `update aluno_material set entregue = true, data_entrega = current_date,
   movimento_estoque_id = <novo>`.
9. Se a trilha ficou em FIM: `fn_certificado_abrir(p_aluno_id)` e pendência `ALUNO_ULTIMO_LIVRO`.
10. Monta o retorno com `proximo_material_id` e `em_fim` já recalculados — a tela não precisa de
    uma segunda ida ao banco.

Os passos 7 a 9 são **um ato só**, na mesma transação: é a "ação única" do plano. Ou os três
acontecem, ou nenhum.

✅ **Implementada em 04/09/2026 (card 6.3)**, com quatro coisas que a especificação acima não podia
saber e que o código teve de fechar:

- **A incompatibilidade `REORDENADA` × permissão do monitor foi resolvida por EXCEÇÃO NOMEADA, e a
  outra saída não existia.** ~~As saídas visíveis são duas: `fn_registrar_entrega` como `security
  definer`, ou uma exceção explícita e nomeada na guarda.~~ ⚠️ `security definer` **não resolveria**:
  ele troca o papel do banco (e com ele a RLS, porque o dono tem `BYPASSRLS`), mas **não troca
  `auth.uid()`** — e `tem_permissao` (card 3.4) é escrita sobre `auth.uid()`, não sobre
  `current_user`. `fn_exige_permissao('alunos.editar_trilha')` continuaria levantando `PT403` dentro
  de uma função definer, exatamente como levanta fora dela. A barreira aqui é de **permissão de
  aplicação**, não de RLS, e não se atravessa mudando de dono. Escolher a saída errada teria custado
  caro e em silêncio: `fn_registrar_entrega` entraria na lista fechada do C8, deixaria de passar pela
  política `insert` **por tipo** de `movimento_estoque` (achado 9 do card 2.4) e o defeito continuaria
  lá.

  A exceção é a GUC de transação **`app.entrega_reordenacao`**, lida por `fn_contexto_entrega()` —
  mesma forma do contexto de rotina do card 2.2 §2.2 — e ela é estreita nas quatro dimensões: vale só
  para a coluna `ordem` (aluno, material e `origem` continuam exigindo a permissão **sempre**), só
  dentro do contexto, que `fn_registrar_entrega` liga e desliga em volta da única escrita que precisa
  dele; não se forja de fora, porque `set_config` mora em `pg_catalog` e o PostgREST não a expõe; e a
  reposição continua **gravando histórico** (`motivo = 'SEM_ESTOQUE'`), que é o que a guarda existe
  para proteger — o mal que ela impede não é "a ordem mudou", é "a ordem mudou e nada explica por
  quê". Afrouxar a guarda para `estoque.lancar_saida` — a terceira saída, que ninguém listou — daria
  ao monitor um `PATCH` livre em `ordem` pelo PostgREST, sem histórico nenhum.

- ~~**Passo 2: `select … from aluno … for update`.**~~ **Não dá, e o motivo é o mesmo perfil.** Sob
  RLS, `SELECT … FOR UPDATE` exige que a linha passe **também** pela `using` da política de UPDATE, e
  `aluno_upd` (card 4.2) pede `alunos.editar` ∨ `alunos.alterar_status` ∨ `alunos.reverter_status` —
  o monitor não tem nenhuma das três, e a entrega morreria com um erro de RLS numa tela que não fala
  de cadastro. A serialização por aluno passou a ser `pg_advisory_xact_lock(aluno)`, a **mesma**
  ferramenta do §4.5, tomada sempre **antes** do lock do material (ordem fixa nas duas sessões, que é
  o que impede o abraço mortal).

- **A mecânica da reposição virou `fn_trilha_reposicionar` (§5.3), com um dono só.** O passo 6 manda
  chamar `fn_trilha_reordenar`, e ela faz três coisas que a entrega não quer: exige
  `alunos.editar_trilha`, marca `origem = 'MANUAL'` e grava `motivo = 'MANUAL'`. Copiar o `UPDATE`
  para dentro da entrega daria duas implementações da mesma renumeração, e o dia em que uma mudasse a
  outra ficaria errada em silêncio.

- **Passo 9 pela metade, de propósito:** a pendência `ALUNO_ULTIMO_LIVRO` existe; `fn_certificado_abrir`
  é do card 8.3, porque `certificado_checklist` não existe. O teste `052_trilha_entrega` §11 é o
  portão que reprova a suíte no dia em que a tabela nascer sem `fn_registrar_entrega` e
  `fn_estornar_entrega` a citarem — mesma forma do gate de FORMADO (card 4.2). E `data_entrega` é
  `fn_hoje()`, não a data do servidor: o Postgres do Supabase roda em UTC, e depois das 21h a entrega
  cairia no dia seguinte, falseando o intervalo que a projeção do card 8.1 mede.

### 6.3 Estorno

```sql
fn_estornar_entrega(p_movimento_id uuid, p_motivo text) → uuid   -- id do movimento de estorno
```

1. Exige `estoque.estornar`; `p_motivo` obrigatório.
2. O movimento precisa ser `SAIDA` e ainda não estornado — o índice único parcial
   `movimento_estorno_uk` garante a unicidade mesmo sob concorrência.
3. Insere `ESTORNO` com `quantidade = +1` e `estorno_de_id` apontando para a saída. **O movimento
   original nunca é apagado nem alterado** (`tg_movimento_imutavel` + ausência de política de
   `update`/`delete` na RLS).
4. Desmarca `aluno_material` (`entregue = false`, `data_entrega = null`,
   `movimento_estoque_id = null`).
5. Se havia `certificado_checklist` aberto e o aluno saiu de FIM: apaga o checklist **se nenhum
   item tiver sido marcado**; se algum já estava marcado, mantém e abre pendência
   `CERTIFICADO_INCONSISTENTE` — apagar um checklist que a secretaria já trabalhou é perda de
   informação.
6. Um estorno **não reverte** o reordenamento da trilha por falta de estoque: o histórico em
   `aluno_material_hist` continua contando o que aconteceu.

✅ **Implementada em 04/09/2026 (card 6.3)**, com três acréscimos ao que está escrito acima:

- **`MOVIMENTO_INEXISTENTE` (404) é o único código novo do card** (§12; contrato de 41 → 42). Vale
  também para movimento de outra unidade — a leitura é `invoker`, então quem não pode ver não
  descobre que existe (precedente de `PC_INEXISTENTE`, `ALUNO_INEXISTENTE`, `BLOCO_INEXISTENTE` e
  `PENDENCIA_INEXISTENTE`). Reaproveitar `MOVIMENTO_NAO_ESTORNAVEL` diria "este movimento não pode
  ser estornado" sobre algo que o usuário não tem, mandando procurar o problema no lugar errado.
- **O estorno fecha `ALUNO_ULTIMO_LIVRO`** quando o aluno sai do FIM. O catálogo do §10.1 já dizia
  "fechada por … estorno que tira do FIM"; sem a chamada, a linha do catálogo seria só uma promessa.
- **`pg_advisory_xact_lock` no movimento**, além da unique parcial `movimento_estorno_uk`. A unique
  já garante que um movimento só se estorna uma vez, mas sozinha ela entrega a corrida à tela como um
  `23505` cru — o que o §1.2 proíbe. Com o lock, a segunda sessão espera e sai com
  `MOVIMENTO_JA_ESTORNADO`.
- **O passo 5 (checklist do certificado) fica com o card 8.3**, pelo mesmo motivo do passo 9 do §6.2,
  e com o mesmo portão no teste `052_trilha_entrega` §11.

---

## 7. Estoque e compras

```sql
fn_saldo_material(p_material_id uuid) → integer   -- stable; sum(quantidade) com sinal
fn_ajustar_estoque(p_material_id uuid, p_quantidade integer, p_motivo text) → uuid
  -- exige estoque.ajustar; motivo obrigatório; movimento AJUSTE (sinal livre)
```

`fn_saldo_material` é a mesma conta de `v_estoque_atual` (card 2.3); a view serve listagem, a
função serve decisão dentro de outra função. **Nenhuma das duas cacheia** — estoque é sempre
`sum(quantidade)`, jamais uma coluna.

✅ **`fn_saldo_material` implementada em 04/09/2026 (card 6.3)**, `stable` e `security invoker`, com
`coalesce(sum(…), 0)`: soma de conjunto vazio é **nula**, não zero (card 2.3 §3.1), e material
recém-cadastrado tem de valer 0 — senão `0 <= 0` vira nulo e o passo 6 da entrega não entra em ramo
nenhum.

✅ **`fn_ajustar_estoque` implementada em 04/09/2026 (card 6.5)**, migração
`20260904210000_pedidos_compra_estoque.sql`, com **uma condição que este documento não previa**:
recusa (`PT409 / SALDO_INSUFICIENTE`) o ajuste que deixaria o saldo negativo. "Sinal livre" é sobre a
**direção** do ajuste, não sobre o saldo — saldo negativo reprova o critério (4) do marco 6.9 e é um
número que ninguém consegue explicar. Também recusa `0` antes de o `check (quantidade <> 0)` chegar
cru à tela (`QUANTIDADE_INVALIDA`) e material inexistente ou de outra unidade
(`PT404 / MATERIAL_INEXISTENTE`), e serializa o material com `pg_advisory_xact_lock`.

### 7.1 Ciclo do pedido de compra

✅ **Implementado em 04/09/2026 (card 6.5)**, `20260904210000_pedidos_compra_estoque.sql`. O
documento previa só o recebimento; o ciclo inteiro do card ("criação, envio e recebimento", mais o
cancelamento da nota) precisou das outras três, e a tela do card 6.8 (`docs/wireframes.md` §10.2) é a
consumidora delas.

```sql
fn_pedido_criar(p_itens jsonb, p_fornecedor text default null,
                p_observacao text default null) → uuid
-- p_itens: [{"material_id": "…", "qtd_pedida": 10}, …]; exige compras.criar E compras.ler
fn_pedido_enviar(p_pedido_id uuid, p_data_envio date default null) → void   -- compras.editar
fn_pedido_cancelar(p_pedido_id uuid, p_motivo text) → void                  -- compras.editar
fn_pedido_receber(p_pedido_id uuid, p_itens jsonb) → integer   -- nº de movimentos ENTRADA criados
-- p_itens: [{"pedido_item_id": "…", "quantidade": 30}, …]
```

- **`fn_pedido_criar`** monta o RASCUNHO e numera `AAAA-NNN` por unidade e ano, serializando com
  `pg_advisory_xact_lock`. Exige **`compras.ler` além de `compras.criar`** porque o número é derivado
  da leitura dos pedidos da unidade: sob RLS, quem não lê conta zero e repete um número já usado — a
  redução silenciosa do card 2.3 §3.4 chegando à tela como `23505`. Recusa lista vazia
  (`PEDIDO_SEM_ITEM`), material repetido (`MATERIAL_JA_NO_PEDIDO`, no molde do `MATERIAL_JA_NA_TRILHA`
  do card 6.2), quantidade ≤ 0 (`QUANTIDADE_INVALIDA`) e material inexistente (`MATERIAL_INEXISTENTE`).
- **`fn_pedido_enviar`** só aceita `RASCUNHO` (`PEDIDO_NAO_ENVIAVEL`) e exige ao menos um item
  (`PEDIDO_SEM_ITEM`): enviado, o pedido passa a abater a parcela "já pedida" de `v_pedido_sugerido`,
  e um pedido sem item nunca sairia de `ENVIADO`, porque o status é recalculado a partir dos itens.
  `data_envio` sai de `fn_hoje()`, nunca do relógio do servidor.
- **`fn_pedido_cancelar`** exige motivo e recusa `RECEBIDO` e `CANCELADO` (`PEDIDO_NAO_CANCELAVEL`).
  Pedido **não se apaga** — não há política de `delete` (card 2.4 §3.5) —, e o motivo é acrescentado a
  `observacao`. `RECEBIDO` não se cancela por uma razão física: as `ENTRADA` já estão no estoque e são
  imutáveis; o desfazer certo é o estorno delas.

`fn_pedido_receber`, passo a passo:

1. Exige `compras.receber`; pedido em `ENVIADO` ou `PARCIAL` (`PT409 / PEDIDO_NAO_RECEBIVEL`).
   Serializa o pedido com `pg_advisory_xact_lock` — dois recebimentos parciais simultâneos leem
   `qtd_recebida` antes de a outra transação escrever, e o total ultrapassa `qtd_pedida` sem que
   nenhuma das duas tenha visto o excedente. É regra de **agregado**, como o saldo: nenhuma constraint
   pega.
2. Por item: `qtd_recebida + quantidade <= qtd_pedida`, salvo `tem_permissao('compras.receber_excedente')`
   (`PT422 / RECEBIMENTO_EXCEDE_PEDIDO`). Quantidade tem de ser positiva (`QUANTIDADE_INVALIDA`), e o
   item tem de ser **daquele** pedido (`ITEM_FORA_DO_PEDIDO`).
3. Insere `ENTRADA` com `quantidade = +q` e `pedido_item_id` preenchido — o vínculo entre a compra
   e o estoque, que a planilha não tinha.
4. Atualiza `pedido_item.qtd_recebida` e recalcula o status do pedido:
   todos os itens completos → `RECEBIDO`; algum parcial → `PARCIAL`.

⚠️ **A exceção do passo 2 obrigou a mexer no DDL, e é a decisão mais cara do card.**
`pedido_item_recebido_ck` (`qtd_recebida <= qtd_pedida`, card 6.1) valia para **todo mundo**: um
`check` não conhece permissão, então a direção com `compras.receber_excedente` levaria um `23514` cru
e `RECEBIMENTO_EXCEDE_PEDIDO` seria um código inalcançável. A constraint foi **removida** e a regra
virou `tg_pedido_item_recebimento`, que recusa com o código do catálogo e distingue quem pode. Ver
`docs/modelagem-dados-ddl.md` §10.

| Objeto | Momento | Faz |
|---|---|---|
| `tg_movimento_valida_sinal` | `before insert on movimento_estoque` (só `ESTORNO` **com origem**) | o estorno tem de ter **sinal oposto, mesma magnitude, mesmo material e mesma unidade** do movimento em `estorno_de_id`. ENTRADA > 0, SAIDA < 0, `quantidade <> 0` e "ESTORNO ⟺ `estorno_de_id`" **já são `check` no DDL** (`movimento_sinal_ck`, `movimento_estorno_ck`) — o trigger só cobre o que depende da outra linha, e o `when` exige `estorno_de_id not null` para não roubar a mensagem da camada 1 |
| `tg_movimento_resolve_pendencia` | `after insert on movimento_estoque` (**todo movimento positivo**) | se o saldo do material voltou a ser > 0, resolve `ESTOQUE_ZERO` daquele material e `COMPRA_SEM_ESTOQUE` de cada aluno que ainda deve receber essa apostila |

⚠️ **Duas divergências registradas neste segundo trigger (card 6.5).** (a) O nome era
`tg_movimento_estorno_sinal` neste parágrafo e `tg_movimento_valida_sinal` no §13 e no portão do teste
`050`; venceu o do portão. (b) O gatilho era "ENTRADA/AJUSTE positivo" e passou a ser **todo
movimento positivo**: a condição que importa é a que a coluna ao lado já dizia — "se o saldo voltou a
ser > 0" —, e o `ESTORNO` de uma `SAIDA` devolve exemplar à prateleira exatamente como uma `ENTRADA`.
Deixá-lo de fora manteria a pendência aberta com o material disponível, que é o mal que o trigger
existe para impedir. `AJUSTE` negativo segue de fora, porque não repõe nada.

⚠️ **`COMPRA_SEM_ESTOQUE` é dedupada por ALUNO** (`COMPRA_SEM_ESTOQUE:<aluno>`, card 6.3), não por
material, então o trigger só a fecha para o aluno que **ainda deve aquela apostila** — pelo vínculo
com `aluno_material` pendente. Sem esse vínculo, uma entrada de INGLÊS fecharia a pendência de um
aluno de INTERATIVO: pendência fechada sem o problema ter sumido é pior do que pendência aberta.
O trigger é **`security definer`** com filtro de unidade no corpo, pela razão de
`fn_revalidar_blocos_sala` (card 5.4): quem recebe compra pode não ter `pendencias.ler` nem
`alunos.ler`, e a RLS nega linha em vez de devolver erro.

O segundo trigger fecha o ciclo aberto em §6.2: a apostila que faltou gerou pendência; a chegada
do pedido a resolve sozinha, sem ninguém precisar lembrar de limpar a lista.

---

## 8. Certificados

```sql
fn_certificado_abrir(p_aluno_id uuid, p_data_fim_curso date default current_date) → uuid
  -- idempotente: insert … on conflict (aluno_id) do nothing
  -- data_fim_curso é NOT NULL no DDL: default = data da última entrega da trilha
fn_certificado_marcar(p_aluno_id uuid, p_item text, p_valor boolean) → void
  -- p_item ∈ (PEDAGOGICO, FINANCEIRO, FORMATURA)
fn_certificado_status(p_aluno_id uuid, p_status text) → void
  -- NAO_PEDIDO | PEDIDO | ENTREGUE; exige certificados.alterar_status
```

- Permissão **por item**: `FINANCEIRO` exige `certificados.marcar_financeiro` (monitor, na matriz
  inicial); `PEDAGOGICO` e `FORMATURA` exigem `certificados.marcar_pedagogico`.
- `tg_certificado_quem_quando` (`before update on certificado_checklist`) grava
  `<item>_por = auth.uid()` e `<item>_em = now()` a cada mudança de valor — a exigência de
  "quem e quando" do plano vale mesmo em `UPDATE` direto. O DDL tem os três pares
  `pedagogico_por/_em`, `financeiro_por/_em` e `certificado_por/_em`; **`formatura` não tem par**
  (§14).
- `tg_certificado_sugere_formado` (`after update on certificado_checklist`): com os três itens OK
  e `certificado_status = 'ENTREGUE'`, abre pendência `SUGERIR_FORMADO` (severidade BAIXA). É
  **sugestão**, não automação: quem forma o aluno é uma pessoa, por `fn_aluno_alterar_status`.

---

## 9. Modular

Detalhamento na Fase 7; as assinaturas ficam aqui para o resto do sistema poder contar com elas.

```sql
fn_turma_modular_admitir(p_turma_id uuid, p_aluno_id uuid) → uuid
fn_turma_modular_remover(p_turma_id uuid, p_aluno_id uuid, p_motivo text) → void
fn_turma_modular_ocupacao(p_turma_id uuid) → integer            -- stable
fn_turma_modular_avancar(p_turma_id uuid, p_data_conclusao date default current_date) → uuid
  -- id do módulo que passou a ser o corrente
fn_turma_modular_modulo_corrente(p_turma_id uuid) → uuid        -- stable
```

- Admissão respeita `turma_modular.capacidade` (mesmo advisory lock de §4.5) e exige aluno
  ATIVO/ACELERAR do método MODULAR.
- `fn_turma_modular_avancar`: marca o módulo corrente como `concluido`, grava a data, abre o
  próximo e ajusta a `prev_conclusao` dele a partir da duração planejada. **A ordem não é coluna de
  `turma_modular_modulo`**: vem de `modulo.ordem`, via join — o cronograma da turma herda a
  sequência do catálogo. **A turma avança em conjunto** — não existe avanço por aluno.
- Quando o módulo que abre é o **primeiro de um livro novo**, aquele livro passa a ser demanda da
  turma inteira: é o gancho da projeção Modular (card 8.1), que lê `turma_modular_modulo`, não o
  ritmo individual.

---

## 10. Pendências

Uma pendência é a forma que este sistema tem de dizer "isto está errado, mas eu não vou decidir
por você". Todas passam por duas funções, e nenhum outro código insere em `pendencia` direto.

```sql
fn_pendencia_abrir(p_tipo text, p_chave_dedup text, p_descricao text,
                   p_severidade text default 'MEDIA',
                   p_aluno_id uuid default null, p_bloco_id uuid default null,
                   p_material_id uuid default null, p_pc_id uuid default null) → uuid
-- insert … on conflict (unidade_id, chave_dedup) where resolvida_em is null do nothing
-- devolve o id da pendência aberta (nova ou preexistente)

fn_pendencia_resolver(p_chave_dedup text) → integer
-- fechamento automático: resolvida_em = now(), resolucao = 'RESOLVIDA', resolvida_por = null

fn_pendencia_resolver_id(p_pendencia_id uuid, p_resolucao text,
                         p_justificativa text default null) → void
-- fechamento humano; exige pendencias.resolver; p_resolucao ∈ (RESOLVIDA, IGNORADA)
```

`resolucao` **não é opcional**: `pendencia_resolucao_ck` exige que `resolvida_em` e `resolucao`
andem juntos, e `pendencia_ignorada_ck` exige justificativa quando a resolução é `IGNORADA`. Por
isso o fechamento automático e o humano são funções separadas — a rotina não tem justificativa a
dar, e a pessoa que ignora uma pendência tem de escrever o porquê.

O índice único parcial do DDL (`pendencia_aberta_uk`) faz a deduplicação: a rotina diária tenta
inserir todo dia e o banco simplesmente ignora a repetida enquanto a anterior estiver aberta.
**A rotina não precisa perguntar "já existe?"** — e por isso é reexecutável e não tem condição de
corrida com a interface.

### 10.1 Catálogo

| Tipo | `chave_dedup` | Severidade | Aberta por | Fechada por |
|---|---|---|---|---|
| `ALUNO_SEM_TURMA` | `ALUNO_SEM_TURMA:<aluno_id>` | ALTA | `rt_pendencias_diaria` | alocação em bloco/turma, ou saída de ATIVO/ACELERAR |
| `STANDBY_PROLONGADO` | `STANDBY:<aluno_id>` | MEDIA | `rt_pendencias_diaria` (`status_desde` + `standby_alerta_dias`) | mudança de status |
| `PREVISAO_VENCIDA` | `PREVISAO:<aluno_id>` | MEDIA | `rt_pendencias_diaria` | nova `prev_conclusao_curso` ou formatura |
| `ACELERAR_SEM_2O_BLOCO` | `ACELERAR:<aluno_id>` | **BAIXA** (INFO não existe no `check` do DDL — card 2.3 §10 #4, corrigido no 5.5) | `rt_pendencias_diaria` | 2º bloco ativo, ou volta a ATIVO |
| `BLOCO_ACIMA_CAPACIDADE` | `CAPACIDADE:<bloco_id>` | ALTA | `fn_revalidar_blocos_sala` | a própria função, quando normaliza |
| `COMPRA_SEM_ESTOQUE` | `COMPRA_SEM_ESTOQUE:<aluno_id>` | ALTA | `fn_registrar_entrega` (trilha sem estoque nenhum) | `tg_movimento_resolve_pendencia` |
| `ALUNO_ULTIMO_LIVRO` | `ULTIMO_LIVRO:<aluno_id>` | BAIXA | `fn_registrar_entrega` | formatura, ou estorno que tira do FIM |
| `PC_SEM_SUBSTITUTO` | `PC_SEM_SUBST:<pc_id>` | MEDIA | `fn_revalidar_blocos_sala` | fim da manutenção, ou substituto informado |
| **novos — ver §14** | | | | |
| `ESTOQUE_ZERO` | `ESTOQUE_ZERO:<material_id>` | MEDIA | `fn_registrar_entrega` (item pulado) | `tg_movimento_resolve_pendencia` |
| `ESTOQUE_ABAIXO_MINIMO` | `MINIMO:<material_id>` | BAIXA | `rt_pendencias_diaria` | saldo ≥ mínimo |
| `SUGERIR_FORMADO` | `FORMADO:<aluno_id>` | BAIXA | `tg_certificado_sugere_formado` | aluno vira FORMADO |
| `TRILHA_DIVERGENTE_COMBO` | `TRILHA_COMBO:<aluno_id>` | MEDIA | `tg_aluno_combo_alterado` | resolução manual |
| `CERTIFICADO_INCONSISTENTE` | `CERT_INCONS:<aluno_id>` | MEDIA | `fn_estornar_entrega` | resolução manual |
| `REP_VIRADA` | `REP:<aluno_id>:CONTINUO` | MEDIA | `rt_rep_avaliar` (card 2.5) | `fn_rep_virar_continuo`, a rotina, ou resolução manual |
| `REP_VIRADA` | `REP:<aluno_id>:VOLTA` | BAIXA | `rt_rep_avaliar` (card 2.5) | `fn_rep_voltar_pontual`, a rotina, ou resolução manual |
| `ROTINA_FALHOU` | `ROTINA_FALHOU:<nome>` | ALTA | `rt_diaria` (bloco `exception`) | execução seguinte bem-sucedida |

Os oito primeiros são os que o `check` de `pendencia.tipo` já aceita — dois deles com o nome que o
DDL escolheu, e que esta especificação adota: **`COMPRA_SEM_ESTOQUE`** (não "COMPRA_URGENTE") e
**`PC_SEM_SUBSTITUTO`**, que o desenho original não tinha previsto e que se encaixa em
`fn_revalidar_blocos_sala`: um PC em manutenção sem substituto é a causa da queda de capacidade, e
merece pendência própria além da do bloco. Os sete seguintes exigem `alter table` no `check` —
consolidados em §14.

---

## 11. Rotinas agendadas (`pg_cron`)

**Um único job diário**, que chama uma rotina orquestradora. Vários jobs concorrentes sobre as
mesmas tabelas só criariam ordem de execução implícita e difícil de depurar.

```sql
select cron.schedule('gi_rotina_diaria', '10 6 * * *', $$ select rt_diaria(); $$);
```

> **`pg_cron` agenda em UTC.** `10 6 * * *` = **03:10 em São Paulo** (UTC−3), fora do horário de
> uso da escola. Registrar isso na migração; um `06:10` lido como horário local seria o meio do
> expediente.

```sql
rt_diaria() → void          -- security definer; itera unidades ativas (§2.2) e chama, em ordem:
  rt_pcs_normaliza()        -- ✅ 5.4 — põe pc.status em dia com pc_manutencao, NAS DUAS DIREÇÕES
  rt_capacidades()          -- ✅ 5.4 — fn_revalidar_blocos_sala em todas as salas, mais a varredura
                            --    das pendências de bloco que deixou de ser ativo
  rt_pendencias_diaria()    -- abre/fecha as pendências de tempo do catálogo §10.1
  rt_rep_avaliar()          -- fn_rep_avaliar_virada por aluno com reposição aberta ou alocação REP;
                            -- abre E fecha as pendências REP_VIRADA (card 2.5)
  rt_projecao_demanda()     -- refresh da projeção (card 8.1)
```

Cada `rt_*` é isolada num bloco `begin … exception when others then` que registra a falha em
`pendencia` (`ROTINA_FALHOU:<nome>`, severidade ALTA) e **segue para a próxima**. Uma unidade com
dado corrompido não pode impedir o alerta de STANDBY das outras.

`rt_pendencias_diaria` abre **e fecha**: toda pendência de tempo é reavaliada todo dia, então a
lista nunca acumula item que já deixou de ser verdade.

---

## 12. Catálogo de erros

| `codigo` | HTTP | Onde nasce |
|---|---|---|
| `SEM_PERMISSAO` | 403 | `fn_exige_permissao` |
| `TRANSICAO_INVALIDA` | 409 | `tg_aluno_status_valida` |
| `FORMATURA_SEM_CERTIFICADO` | 409 | `tg_aluno_status_valida` |
| `MOTIVO_OBRIGATORIO` | 422 | `fn_aluno_alterar_status`, `fn_estornar_entrega`, `fn_ajustar_estoque` |
| `ALUNO_INATIVO` | 409 | admissão em bloco/turma, `fn_registrar_entrega` |
| `METODO_INCOMPATIVEL` | 422 | `tg_bloco_aluno_admissao` |
| `BLOCO_LOTADO` | 409 | `tg_bloco_aluno_admissao`, `tg_reposicao_admissao` |
| `DATA_PREVISTA_OBRIGATORIA` | 422 | `fn_bloco_admitir` (tipo NOVO) |
| `TRILHA_JA_EXISTE` / `TRILHA_COM_ENTREGA` | 409 | `fn_trilha_gerar` |
| `ALUNO_SEM_COMBO` | 422 | `fn_trilha_gerar` |
| `ITEM_JA_ENTREGUE` | 409 | edição de trilha |
| `MATERIAL_JA_NA_TRILHA` | 409 | `fn_trilha_inserir` (card 6.2) — sem ele, a segunda inclusão da mesma apostila chega à tela como um `23505` cru da `aluno_material_uk` |
| `TRILHA_EM_FIM` | 409 | `fn_registrar_entrega` |
| `MATERIAL_FORA_DA_TRILHA` | 422 | `fn_registrar_entrega` |
| `MOVIMENTO_JA_ESTORNADO` / `MOVIMENTO_NAO_ESTORNAVEL` | 409 | `fn_estornar_entrega` |
| `MOVIMENTO_INEXISTENTE` | 404 | `fn_estornar_entrega` (card 6.3) — vale também para movimento de outra unidade, pelo precedente de `PC_INEXISTENTE`; sem ele, "não existe" chegaria à tela como "não pode ser estornado" |
| `PEDIDO_NAO_RECEBIVEL` | 409 | `fn_pedido_receber` |
| `RECEBIMENTO_EXCEDE_PEDIDO` | 422 | `fn_pedido_receber` **e** `tg_pedido_item_recebimento` (card 6.5) — a mesma frase nas duas camadas |
| `PEDIDO_INEXISTENTE` | 404 | `fn_pedido_enviar` / `_cancelar` / `_receber` (card 6.5) — vale também para pedido de outra unidade |
| `MATERIAL_INEXISTENTE` | 404 | `fn_pedido_criar`, `fn_ajustar_estoque` (card 6.5) — idem |
| `PEDIDO_NAO_ENVIAVEL` | 409 | `fn_pedido_enviar` (card 6.5) — só `RASCUNHO` se envia |
| `PEDIDO_NAO_CANCELAVEL` | 409 | `fn_pedido_cancelar` (card 6.5) — `RECEBIDO` se corrige por estorno |
| `PEDIDO_SEM_ITEM` | 422 | `fn_pedido_criar`, `fn_pedido_enviar`, `fn_pedido_receber` (card 6.5) |
| `MATERIAL_JA_NO_PEDIDO` | 409 | `fn_pedido_criar` (card 6.5) — senão a `pedido_item_uk` chega crua à tela |
| `ITEM_FORA_DO_PEDIDO` | 422 | `fn_pedido_receber` (card 6.5) |
| `QUANTIDADE_INVALIDA` | 422 | `fn_pedido_criar`, `fn_pedido_receber`, `fn_ajustar_estoque` (card 6.5) |
| `ESTORNO_SINAL_INVALIDO` | 422 | `tg_movimento_valida_sinal` (card 6.5) — camada 2 do estorno |
| `SALDO_INSUFICIENTE` | 409 | `fn_ajustar_estoque` (card 6.5) — "sinal livre" não é "saldo livre" |
| `PARAMETRO_AUSENTE` | 422 | `fn_param_int` / `fn_param_txt` |
| `BLOCO_INEXISTENTE` | 404 | `tg_bloco_aluno_admissao`, `tg_reposicao_admissao`, `fn_bloco_admitir`, `fn_reposicao_agendar` (card 5.3) |
| `ALOCACAO_INEXISTENTE` | 404 | `fn_bloco_remover` (card 5.3) |
| `REPOSICAO_INEXISTENTE` / `REPOSICAO_NAO_PREVISTA` | 404 / 409 | `fn_reposicao_registrar`, `fn_reposicao_cancelar` (card 5.3) |
| `REP_JA_CONTINUO` / `REP_NAO_CONTINUO` | 409 | `fn_rep_virar_continuo`, `fn_rep_voltar_pontual` (cards 2.5 e 5.3) |

`BLOQUEADA_SEM_ESTOQUE` **não** está aqui de propósito: é status de retorno, não erro (§1.3).

### 12.1 Permissões novas usadas por estas funções → **card 2.4**

`alunos.alterar_status`, `alunos.reverter_status`, `alunos.formar_sem_certificado`,
`alunos.editar_trilha`, `turmas.alocar`, `turmas.lancar_reposicao_retroativa`,
`estoque.lancar_saida`, `estoque.estornar`, `estoque.ajustar`, `compras.receber`,
`compras.receber_excedente`, `certificados.marcar_pedagogico`, `certificados.marcar_financeiro`,
`certificados.alterar_status`, `pendencias.resolver`.

Três delas são de exceção e, na matriz inicial, ficam **só com a direção**:
`alunos.formar_sem_certificado`, `alunos.reverter_status`, `compras.receber_excedente`.

---

## 13. Mapa função → card

| Objetos | Card |
|---|---|
| `fn_contexto_rotina`, desvio de rotina em `fn_unidade_atual`/`tem_permissao`, `fn_param_int/txt`, `fn_exige_permissao` | 3.4 |
| `fn_aluno_transicao_valida`, triggers de status, `fn_aluno_alterar_status`, `fn_aluno_reverter_status` | 4.2 |
| `tg_pc_manutencao_status`, `tg_pc_revalida_blocos` | 4.3 |
| `fn_capacidade_efetiva`, `fn_ocupacao_bloco`, `fn_vagas_livres` — as três juntas, ver §4.2 | 5.2 |
| `tg_bloco_aluno_admissao`, `fn_bloco_admitir/remover`, reposições | 5.3 ✅ |
| `fn_revalidar_blocos_sala` | 5.4 |
| `fn_pendencia_abrir/resolver/resolver_id`, `fn_pendencias_fechar_ausentes`, `rt_pendencias_diaria`, `rt_diaria` e o job `pg_cron` | 5.5 ✅ |
| `fn_trilha_gerar`, `fn_trilha_proximo_material`, edição da trilha, `tg_aluno_trilha_inicial`, `tg_aluno_combo_alterado` | 6.2 ✅ |
| `tp_entrega_resultado`, `fn_registrar_entrega`, `fn_estornar_entrega`, `fn_saldo_material`, mais `fn_contexto_entrega` e `fn_trilha_reposicionar` (as duas nasceram da decisão do card — ver §6.2) | 6.3 ✅ |
| `fn_pedido_criar`, `fn_pedido_enviar`, `fn_pedido_cancelar`, `fn_pedido_receber`, `fn_ajustar_estoque`, `tg_movimento_valida_sinal`, `tg_movimento_resolve_pendencia`, `tg_pedido_item_recebimento` | 6.5 ✅ |
| Funções Modular | 7.2 |
| `rt_projecao_demanda` | 8.1 |
| `fn_certificado_*`, `tg_certificado_*` | 8.3 |
| `tp_rep_situacao`, `fn_rep_situacao`, `fn_rep_avaliar_virada`, `fn_rep_virar_continuo`, `fn_rep_voltar_pontual` (critério fechado no card 2.5) | 5.3 ✅ |
| `rt_rep_avaliar` | 5.5 ✅ |

Ordem de dependência igual à das migrações: 3.4 → 4.2 → 4.3 → 5.2 → 5.3 → 5.4 → 5.5 → 6.2 → 6.3 →
6.5 → 7.2 → 8.1 → 8.3.

---

## 14. Ajustes que esta especificação exige no DDL

Nada aqui é alteração feita por conta própria: é a lista do que a migração de cada fase precisa
acrescentar ao DDL do card 2.1 para que estas funções possam existir. Todos são `alter table`
simples — que é exatamente por que o card 2.1 escolheu `text` + `check` em vez de `enum`.

| # | Ajuste | Onde | Card |
|---|---|---|---|
| 1 | `bloco_aluno_reposicao.status`: acrescentar **`FALTOU`** ao `check` | `drop constraint` / `add constraint` | 5.1 |
| 2 | `pendencia.tipo`: acrescentar `ESTOQUE_ZERO`, `ESTOQUE_ABAIXO_MINIMO`, `SUGERIR_FORMADO`, `TRILHA_DIVERGENTE_COMBO`, `CERTIFICADO_INCONSISTENTE`, `REP_VIRADA`, `ROTINA_FALHOU` ao `check` | idem | 5.5 ✅ (**sem `alter`**: a tabela nasceu no próprio card, então os quinze tipos entraram direto no `check` — divergência registrada) |
| 3 | `certificado_checklist`: acrescentar `formatura_por` / `formatura_em` | `add column` | 8.3 |
| 4 | `aluno_material_hist`: acrescentar `observacao text` | `add column` | 6.2 ✅ (04/09/2026, e o card 6.1 a deixou de fora de propósito: acrescentá-la lá daria uma coluna sem escritor) |
| 5 | `bloco_aluno`: acrescentar `tipo_desde date not null default current_date` + trigger `tg_bloco_aluno_tipo_desde` | `add column` + trigger | 5.1 |
| 6 | `rt_pendencias_diaria`: a contagem de blocos para `ACELERAR_SEM_2O_BLOCO` filtra `tipo <> 'REP'` | corpo da rotina | 5.5 ✅ (com **contraprova** no teste 090: os mesmos dois blocos, os dois de aula, fecham a pendência) |
| 7 | `fn_reposicao_registrar` devolve `text` (o veredito da virada) em vez de `void` | assinatura | 5.1 → **5.3** ✅ (a função não existia no 5.1: nasceu devolvendo `text`) |
| 8 | Tipo composto novo `tp_rep_situacao` — passam a ser dois, com `tp_entrega_resultado` | `create type` | 5.3 ✅ |
| 9 | Erros novos: `REP_JA_CONTINUO` (409) e `REP_NAO_CONTINUO` (409) | catálogo §12 | 5.3 ✅ |
| 10 | Parâmetros novos no seed: `rep_prazo_dias`, `rep_capacidade_semanal`, `rep_faltas_max`, `rep_janela_volta_dias` | seed | 3.6 |

**Sobre o 3:** o DDL dá par "quem/quando" a `pedagogico`, `financeiro` e `certificado`, mas não a
`formatura`. O plano exige que **cada item** do checklist registre quem marcou e quando; sem as duas
colunas, `formatura` é o único item sem rastro.

**Sobre o 4:** `aluno_material_hist.motivo` é um `check` fechado de quatro valores, e não há campo
de texto livre. O reordenamento automático não precisa de um (`SEM_ESTOQUE` já diz tudo), mas a
edição manual precisa: "por que este aluno pulou a apostila 7" é justamente o que alguém vai
perguntar três meses depois.

Os dois primeiros são bloqueantes — sem eles as funções não gravam. Os dois seguintes são perda de
informação, não erro de execução: dá para adiar, desde que conscientemente.

**Os itens 5 a 10 vêm do card 2.5** (01/09/2026), com a justificativa de cada um em §8 de
`docs/regra-virada-rep.md`. Bloqueantes ali: o 5 (sem `tipo_desde` não há como cortar o relógio do
débito na virada, e o aluno convertido nunca poderia voltar a pontual) e o 10 (parâmetro ausente é
`PARAMETRO_AUSENTE`, por decisão de §2.3 — não há `default` escondido no código).

---

## 15. O que fica em aberto

1. ~~**Critério da virada REP pontual → contínuo (card 2.5).**~~ **Fechado em 01/09/2026** —
   `docs/regra-virada-rep.md`. `fn_rep_avaliar_virada` manteve a assinatura reservada aqui. Segue em
   aberto só a **calibração** dos quatro parâmetros `rep_*`, que depende de histórico de uso
   (revisar no card 11.2, junto com a projeção de demanda).
2. ~~**Fórmula final da capacidade efetiva (card 5.2).**~~ **Fechada em 03/09/2026** — §4.1. O
   isolamento numa função só pagou o que prometia: os dois furos do ponto de partida (substituto
   morto pelo `status`, substituto da própria sala contado duas vezes) se corrigiram sem tocar em
   mais nada do sistema. Segue em aberto o **limite** ali registrado: PC emprestado continua contando
   na sala de origem, porque `pc.sala_id` diz onde a máquina está cadastrada e não onde ela está.
3. **Códigos de permissão (card 2.4).** A lista de §12.1 é a entrada; o card fecha o catálogo e a
   matriz.
4. **Views de leitura (card 2.3).** `v_estoque_atual`, `v_demanda_imediata`, `v_pendencias_abertas`
   e as do dashboard consomem estas funções; nenhuma view repete lógica que já está aqui.
5. **Algoritmo da projeção de demanda (card da Fase 2, Ordem 5 → implementação no 8.1).**
   `rt_projecao_demanda` está reservada como ponto de chamada; o corpo é daquele card.
   ⚠️ Cuidado com a ambiguidade de nome no board: "2.5" nas Decisões vigentes é sempre o card de
   **Ordem 2.5 (virada REP)**; o de projeção é o de **Ordem 5**.
6. **Estratégia de teste (card 2.8).** Recomendação já derivada deste desenho: pgTAP sobre as
   funções puras (`fn_aluno_transicao_valida`, `fn_capacidade_efetiva`, `fn_ocupacao_bloco`) e
   testes de transação sobre as compostas (`fn_registrar_entrega` em cinco cenários: normal,
   reordenada, bloqueada, concorrente, estorno).
