# Turma Modular em rodízio

**Fonte do modelo da turma Modular em rodízio.** Card 9.2,87 (especificação). Parte 2 da proposta
aprovada pelo dono do produto em 10/11/2026; é a entrada dos cards **9.2,88** (banco), **9.2,89**
(projeção), **9.2,90** (telas) e **9.2,91** (extrator e importador). A Parte 1 — o aviso de troca
de módulo — está em `aviso-troca-modulo.md`.

> ⚠️ **Este documento revoga uma premissa do card 2.2 §9** (`regras-negocio-funcoes.md` §9): a de
> que a turma Modular começa, percorre os módulos uma vez e termina, com todos os alunos juntos.
> **As turmas são cíclicas**: seguem em rodízio pelos módulos do curso, e quem entra e sai são os
> alunos (dono do produto, 10/11/2026). O que continua valendo do §9 está no §9 daqui.

## 1. De onde veio

Áudios do dono do produto de 06/11/2026, sobre as abas de turma da planilha:

- "tem alguém que vai começar em Regata, então Blusa e Camiseta vai ser o último módulo dela";
- "a partir do momento que eu cadastro o aluno e coloco o módulo que ele vai começar, ele reajuste
  automaticamente todos os outros módulos";
- "os alunos que estão ativos e dentro da turma já recebam esse módulo automaticamente";
- "eu preciso saber qual o módulo certinho que ele fez, para poder definir o prazo de conclusão do
  curso dele";
- "ele pode indicar que o próximo livro vai ser utilizado […] o que vai mudar é a urgência".

E as onze regras aprovadas em 10/11/2026 (na nota do card 9.2,87), que os §3 a §7 implementam.

## 2. A ideia central: a sequência do aluno não se guarda — deriva-se

A planilha guarda, por aluno, a lista ordenada dos módulos que ele vai fazer. Aqui **não**: guarda-se
só o que é fato, e a sequência sai de uma conta.

| O que é fato (guardado) | Onde |
|---|---|
| A ordem dos módulos do curso | `modulo.ordem` — o catálogo, como hoje |
| Em que módulo a turma está, e as datas | `turma_modular_modulo` — o cronograma, agora com `ciclo` |
| Em que módulo o aluno entrou | `turma_modular_aluno.modulo_entrada_id` |
| Que módulos o aluno **já fez**, e quando | `aluno_modulo` — tabela nova |

| O que é derivado | Como |
|---|---|
| Módulos que **faltam** ao aluno | módulos do curso − `aluno_modulo` |
| A **ordem** em que ele os fará | a ordem do rodízio da turma, a partir do módulo corrente |
| A **previsão de conclusão** dele | a data em que a turma termina o último módulo que lhe falta |
| Quando ele precisa de cada **livro** | a data em que a turma entra no primeiro módulo, dos que lhe faltam, daquele livro |

Por que assim, e não a lista por aluno:

1. **As regras 5 e 6 saem de graça.** O aluno que ficou em STANDBY e perdeu um módulo simplesmente
   continua com ele em "faltam" — e, como a ordem é a do rodízio, o módulo perdido cai onde a turma
   voltar a passar por ele: **no fim da sequência dele**. Nenhum código reordena nada. A exceção à
   mão (regra 6) é marcar ou desmarcar um módulo em `aluno_modulo`.
2. **Mudar uma data da turma muda a previsão de todos** (regra 8) sem tocar em linha de aluno.
3. **Uma definição só** (card 2.3 §4.1). Uma lista por aluno seria a segunda fonte da ordem, livre
   para divergir do cronograma da turma na primeira edição.

No exemplo aprovado (Chef Profissional + Panificação, turma em Massas e Molhos):

| | Entrou em Garde Manger, já fez 3 | Entrou agora, em Massas e Molhos |
|---|---|---|
| Faltam | Massas e Molhos, Fermentos, Massas Levedadas | os seis |
| Ordem (rodízio a partir do corrente) | Massas e Molhos → Fermentos → Levedadas | Massas e Molhos → Fermentos → Levedadas → Garde Manger → Carnes → Peixes |
| Conclui quando a turma terminar | Massas Levedadas | Peixes e Frutos do Mar |
| Precisa do livro Panificação | na próxima troca | na próxima troca |

## 3. Modelo de dados (card 9.2,88)

### 3.1 `turma_modular_modulo` ganha `ciclo`

```sql
alter table turma_modular_modulo add column ciclo integer not null default 1 check (ciclo > 0);
-- a unique passa de (turma_id, modulo_id) para (turma_id, modulo_id, ciclo)
```

- Um **ciclo** é uma volta da turma pelos módulos do curso. As linhas de ciclos passados ficam: são
  o histórico de quando a turma deu cada módulo, e é delas que sai o passo aprendido.
- **Módulo corrente** = o primeiro não concluído por `(ciclo, modulo.ordem, modulo_id)`. As três
  definições que o teste 072 §3 compara linha a linha (a função, a view de lotação e a do
  cronograma) mudam **juntas**.
- O estado "turma terminou" **deixa de existir** para turma ativa: ver §4.2.

⚠️ **A chave da pendência `TROCA_MODULO_ALINHAR` não muda.** Ela carrega a linha do cronograma
(`TROCA_MODULO:<turma>:<cronograma>`), e cada ciclo tem linhas **novas** — então "resolvida por gente
não reabre" continua valendo por módulo **e por volta**, que é o que se quer. É a resposta ao aviso
deixado no card 9.2,85.

### 3.2 `turma_modular_aluno` ganha `modulo_entrada_id`

```sql
alter table turma_modular_aluno add column modulo_entrada_id uuid references modulo(id);
```

Nulo só em linha antiga. É o que a tela mostra ("entrou em Massas e Molhos") e o que decide a regra
de §4.3 para quem entra perto de uma troca. Entra na guarda de coluna do card 7.1.

### 3.3 `aluno_modulo` — o que o aluno já fez

```sql
create table aluno_modulo (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references unidade(id),
  aluno_id   uuid not null references aluno(id) on delete cascade,
  modulo_id  uuid not null references modulo(id),
  turma_id   uuid references turma_modular(id),   -- nulo: lançado à mão ou importado
  data_conclusao date not null,
  origem text not null check (origem in ('TURMA','MANUAL','IMPORTACAO')),
  observacao text,
  criado_em …, criado_por …, atualizado_em …, atualizado_por …,
  constraint aluno_modulo_uk unique (aluno_id, modulo_id)
);
```

- **A existência da linha é o fato "fez".** Não há coluna de estado: "a fazer" é a ausência.
- `unique (aluno_id, modulo_id)`: ninguém faz o mesmo módulo duas vezes para efeito de conclusão.
  Refazer é exceção à mão — remove-se a linha (§4.5).
- **RLS** (quatro políticas, com a folga do efeito colateral — card 2.4 (b)): `select` com
  `alunos.ler`; `insert` com `turmas.editar` ∨ `alunos.editar_trilha` (o avanço grava como efeito
  colateral de quem avança); `update` e `delete` com `alunos.editar_trilha`.
- **Não se grava por migração** (card 4.0,5): é dado de negócio, vem do importador (§8).

## 4. Regras (card 9.2,88)

### 4.1 Admissão — `fn_turma_modular_admitir(p_turma_id, p_aluno_id, p_modulo_entrada_id default null)`

- `p_modulo_entrada_id` nulo = o módulo **corrente** da turma (regra 2: "vem preenchido").
- Aceita só o **corrente** ou o **próximo** do rodízio. Outro valor: `PT422` /
  `MODULO_ENTRADA_INVALIDO`. Entrada histórica (aluno que entrou há meses) é assunto do importador,
  que escreve `modulo_entrada_id` e `aluno_modulo` direto.
- Reativação (aluno que volta de STANDBY): mantém o `modulo_entrada_id` original e **não** apaga
  `aluno_modulo` — é o que faz a regra 5 valer.
- **Reordena a trilha de livros** do aluno para a ordem em que ele vai precisar deles
  (`fn_trilha_reordenar`, só itens não entregues): quem entra em Fermentos precisa do livro
  Panificação antes do Chef Profissional.
- Capacidade, advisory lock e as duas checagens de método: como hoje (card 7.2).

### 4.2 Avanço — `fn_turma_modular_avancar(p_turma_id, p_data_conclusao)`

Na mesma transação, depois de concluir o módulo corrente `M` com a data real:

1. **Grava `aluno_modulo`** (`origem = 'TURMA'`, `data_conclusao = p_data_conclusao`) para cada
   aluno **ativo na turma** — `on conflict do nothing` — **menos** quem ainda não começou: aluno sem
   nenhum módulo deste curso em `aluno_modulo` e cujo `modulo_entrada_id` **não** é `M` (entrou
   para começar no próximo).
2. **Conclui quem completou** (§4.4).
3. **Abre o próximo**, como hoje (passo aprendido, datas informadas preservadas). Se `M` era o
   último do ciclo, **cria o ciclo seguinte**: uma linha por módulo do curso, a primeira com
   `data_inicio = p_data_conclusao + 1` e a previsão pelo passo, as demais sem data — a
   extrapolação de §6 as data.

Aluno em STANDBY não está ativo na turma (`tg_aluno_status_desaloca` já o desativa) e por isso não
recebe o módulo — a regra 5 não precisa de código próprio.

`TURMA_SEM_MODULO_CORRENTE` deixa de ser levantado para turma com cronograma. Turma **antiga** com
todos os módulos concluídos (estado anterior a este card) ganha `fn_turma_modular_abrir_ciclo`,
chamada pela tela 5 no lugar do aviso "turma terminou".

### 4.3 O módulo corrente conta para quem entrou no meio dele

Sim, quando o módulo de entrada é o corrente: o aluno o recebe no avanço, tenha entrado no primeiro
ou no último dia. Quem entra perto da troca e não vai aproveitar o módulo entra com o **próximo**
como módulo de entrada — é a escolha que a regra 2 dá à secretaria.

### 4.4 Conclusão do curso

O aluno conclui quando `aluno_modulo` cobre **todos** os módulos do curso da turma. No ato:

- `turma_modular_aluno.ativo = false`, `motivo_saida = 'Concluiu o curso'` — libera a vaga;
- abre o checklist de certificado, quando não resta curso Modular do combo por concluir (decisões
  D1 e D3, §10).

Não muda o status do aluno: FORMADO continua sendo decisão de gente, com o gate do certificado
(card 8.3).

### 4.5 Exceção à mão

Duas funções, `alunos.editar_trilha`, usadas pela ficha do aluno (card 9.2,90):

```sql
fn_aluno_modulo_registrar(p_aluno_id, p_modulo_id, p_data_conclusao, p_observacao) → uuid
fn_aluno_modulo_remover(p_aluno_id, p_modulo_id, p_motivo)                          → void
```

Registrar = o aluno fez o módulo por fora da turma (origem `MANUAL`). Remover = precisa refazer;
motivo obrigatório. Registrar o último módulo dispara a conclusão de §4.4.

## 5. A agenda da turma e a previsão do aluno (card 9.2,88)

### 5.1 `fn_turma_modular_agenda(p_turma_id)` → uma volta à frente

Devolve, para os próximos **N** módulos do rodízio a partir do corrente (N = módulos do curso), a
posição, o módulo, o material e as datas planejadas de início e fim. As datas saem das três regras
que a projeção já usa (`projecao-demanda.md` §5.4): a informada; senão o fim do anterior + 1; senão a
extrapolação pelo passo. É `stable`, `security definer` com filtro de unidade (decisão derivada lida
sob RLS nega linha — card 8.3).

É a **única** definição de "quando a turma dará cada módulo": a previsão do aluno, a projeção e a
tela leem dela.

### 5.2 `v_aluno_modular_progresso`

Uma linha por aluno ativo em turma Modular: turma, módulo de entrada, módulos feitos, total do
curso, próximo módulo dele e **`prev_conclusao`** = o `fim` da agenda no último módulo que lhe
falta. Nulo quando a turma não tem data nenhuma.

`v_aluno_modular_modulo`: a sequência completa do aluno para a ficha — feitos (com a data real),
depois os que faltam, na ordem da agenda, com a data planejada.

### 5.3 `aluno.prev_conclusao_curso` para o aluno em turma Modular

Deixa de ser lida para esse aluno: vale a previsão calculada de §5.2 (decisão D2, §10).

## 6. Projeção de demanda (card 9.2,89)

A regra `MODULAR` de `v_projecao_aluno` (`projecao-demanda.md` §5.4) hoje diz: o livro é necessário
quando **a turma** entra no primeiro módulo daquele livro. Passa a dizer:

> o livro é necessário quando a turma entra no **primeiro módulo, dos que faltam ao aluno**,
> daquele livro — lido de `fn_turma_modular_agenda`.

- Continua **por aluno** e continua contando só item **pendente** da trilha: quem já tem o livro não
  conta, como hoje.
- É o que dá a "urgência" pedida: dois alunos da mesma turma, o mesmo livro, meses diferentes.
- A extrapolação deixa de ser reescrita na view: passa a vir da agenda (§5.1).
- `TURMA_MODULAR_SEM_CRONOGRAMA` e a queda para `MEDIA_METODO`: sem mudança.

## 7. O aviso de troca de módulo, com o rodízio

`v_turma_modular_lotacao.proximo_*` (card 9.2,85) hoje procura o próximo módulo "depois do corrente,
por ordem" — e no último módulo devolve nulo. Com o rodízio o próximo do último é o **primeiro**:
as colunas passam a ler a posição 2 da agenda, e `troca_de_livro` passa a valer também na virada do
ciclo.

A entrega oferecida no avanço (card 9.2,86) passa a listar os alunos ativos a quem o **próximo
módulo falta** e que têm o livro dele pendente na trilha — quem já fez aquele módulo não entra.

## 8. Extrator e importador (card 9.2,91)

| Entidade do arquivo | Muda |
|---|---|
| `turma_modular_modulo` | ganha `ciclo` (ausente = 1) |
| `turma_modular_aluno` | ganha `modulo_entrada` (ordem do módulo no curso) |
| `aluno_modulo` (nova) | `aluno`*, `metodo`*, `curso`*, `modulo_ordem`*, `data_conclusao`*, origem `IMPORTACAO` |

A planilha tem, por aluno e por módulo, o nome do módulo, `Início` (SIM/NÃO) e a previsão de
conclusão; e a aba **Base Modular** dá a ordem dos módulos por livro. O extrator deriva:

- `modulo_entrada` = o **Módulo 01** da linha do aluno;
- `aluno_modulo` = os módulos da linha **antes** do atual que já começaram.

⚠️ **Duas perguntas que só a carga responde**, e que ficam para o card 9.2,91:

1. a Base Modular lista, no livro Panificação, "Higiene e Boas Práticas" e "Conhecimentos dos
   Ingredientes", que não aparecem na lista de módulos da aba Chef+Panificação (pergunta 5 da
   proposta);
2. a planilha marca módulo **iniciado**, não **concluído** — a data de conclusão de módulo passado
   terá de vir da previsão que ficou gravada.

## 9. O que continua valendo do card 2.2 §9

- **A turma avança em conjunto.** Não existe avanço por aluno: o que é por aluno é o **registro** do
  que ele fez.
- A ordem vem de `modulo.ordem`, nunca de coluna do cronograma.
- A data real de conclusão é gravada em `prev_conclusao` do módulo concluído.
- A capacidade é coluna da turma; admissão com advisory lock por turma.
- Laboratório (Interativo e Inglês) não muda em nada (regra 11).

## 10. Decisões tomadas

Três pontos que as onze regras aprovadas não fechavam e que mudam comportamento já entregue.
**Decididos por Irineu em 11/11/2026**, os três pela recomendação.

**D1 — O certificado do aluno Modular abre na conclusão dos módulos.** Até aqui o checklist abria
quando a **última apostila** da trilha era entregue (card 8.3) — e no Modular o último livro é
entregue meses antes do fim do curso: o aluno entraria na fila de certificados no meio dele. Para
aluno **do método MODULAR**, `fn_registrar_entrega` deixa de abrir o checklist, e quem o abre é a
conclusão de §4.4. Interativo e Inglês não mudam.

- `v_certificado_fila` (card 8.6) exige trilha em `ULTIMO_LIVRO`/`FIM`; para o Modular a situação
  passa a sair do progresso de módulos: `ULTIMO_LIVRO` lê-se "no último módulo", `FIM`, "concluiu".
- `ALUNO_ULTIMO_LIVRO` (pendência aberta por `fn_registrar_entrega`) também deixa de abrir para o
  aluno Modular na entrega; a tela 9 é quem mostra quem está no último módulo.
- O estorno de entrega (`fn_certificado_reavaliar_estorno`) não reavalia checklist de aluno
  Modular: o que o tira do `FIM` é `fn_aluno_modulo_remover` (§4.5), que passa a chamar a mesma
  reavaliação.

**D2 — A previsão de conclusão do aluno em turma Modular é só a calculada.** A ficha mostra a de
§5.2 e não deixa editar; `aluno.prev_conclusao_curso` deixa de ser lida para esse aluno.

- `PREVISAO_VENCIDA` (rotina diária, card 8.4) deixa de olhar o aluno com turma Modular ativa — o
  atraso dele aparece como troca de módulo vencida da turma (`TROCA_MODULO_ALINHAR`).
- A coluna **não** é apagada nem zerada: o importador continua a trazê-la, e ela volta a valer se o
  aluno sair da turma. Quem decide qual das duas mostrar é a view da ficha.
- A projeção não muda por isto: o degrau `MODULAR` já vem antes de `PREVISAO_CURSO` na cascata.

**D3 — Com mais de um curso Modular no combo, o certificado só abre no fim do combo.** A conclusão
de §4.4 é por **curso/turma** e sempre libera a vaga daquela turma. O checklist abre quando
`aluno_modulo` cobre os módulos de **todos** os cursos Modular do combo do aluno
(`aluno.combo_id` → `combo_curso`); aluno sem combo conclui pelo curso da turma. O checklist continua sendo um
por aluno (card 8.3).

## 10.1 O que a implementação (card 9.2,88, 11/11/2026) mudou neste documento

Migração `20261111120000_turma_rodizio.sql`, teste `105_turma_rodizio` (43 asserções). Cinco
divergências do que os §3 a §5 escreviam, todas registradas no arquivo:

1. **A agenda devolve N + 1 posições, não N.** A posição N + 1 repete o módulo corrente, no ciclo
   seguinte. Sem ela, o aluno que entrou para começar no **próximo** módulo não tinha onde concluir:
   o corrente de hoje é o **último** da sequência dele, e só volta na outra volta. As views leem,
   para cada módulo que falta, a **primeira** posição em que a turma o dará **àquele** aluno
   (`aguardando_entrada` em `v_aluno_modular_progresso`).
2. **`aluno_modulo_hist`** — tabela que o §3 não previa. Remover módulo exige motivo (§4.5), e a
   linha removida deixa de existir: sem histórico o motivo seria um parâmetro aceito e jogado fora
   (a mesma razão de `motivo_saida` no card 7.2). Imutável, escrita só por trigger.
3. **O `select` de `aluno_modulo` aceita `turmas.editar` além de `alunos.ler`.** Quem avança o
   módulo grava ali e precisa **enxergar** o que já existe para decidir quem ainda não começou — sob
   RLS, quem não lê recebe zero linhas sem erro, e o avanço daria o módulo a quem entrou para
   começar no próximo.
4. **A conclusão é função própria e `security definer`** (`fn_aluno_modular_avaliar_conclusao`): é
   efeito colateral do avanço (`turmas.editar`), e tirar o aluno da turma exige `turmas.alocar` —
   como invoker o `update` afetaria zero linhas e o aluno concluído continuaria ocupando a vaga.
5. **O avanço completa as linhas do ciclo.** Módulo do catálogo depois do que fechou e ainda sem
   linha no ciclo entra no avanço — a turma em rodízio passa por todos. Os de ordem **menor** não
   entram: inseridos como "não concluídos", virariam o corrente.

**O que NÃO foi feito aqui, e para onde foi** (card 9.2,885): as decisões D1, D2 e D3; a reordenação
da trilha de livros na admissão (§4.1) — `fn_trilha_reordenar` pede `alunos.editar_trilha` e quem
admite tem `turmas.alocar`; e o script de concorrência admissão × avanço (§11). Neste card a
conclusão **só libera a vaga**.

⚠️ **Entre este card e o 9.2,89** a projeção lê o cronograma sem conhecer `ciclo`: turma que já
abriu o segundo ciclo teria módulos contados duas vezes. Os dois saem no mesmo lote.

## 11. Testes que o card 9.2,88 deve

| O que provar | Como |
|---|---|
| Corrente por `(ciclo, ordem)`, nas três definições | teste 072 §3, estendido |
| A virada de ciclo cria as linhas e não duplica | avançar o último módulo duas vezes seguidas |
| O avanço grava para o ativo e não para quem saiu | aluna em STANDBY no avanço; volta e o módulo é o último da agenda dela |
| Quem entrou com "próximo" não recebe o corrente | dois alunos, entradas diferentes, um avanço |
| A conclusão libera a vaga e não muda o status | turma de capacidade 1: conclui e o próximo é admitido |
| A previsão do aluno acompanha a data da turma | mover `prev_conclusao` de um módulo e reler a view |
| `MODULO_ENTRADA_INVALIDO` | entrada dois módulos à frente |
| Concorrência: admissão × avanço | script de duas sessões, como `admissao_turma_modular.sh` |
| RLS de `aluno_modulo` por perfil e por unidade | paridade (card 2.8 §6.3) |

## 12. Mapa → card

| Card | Entrega |
|---|---|
| **9.2,88** | §3, §4, §5 e §7 (as colunas `proximo_*` com o rodízio); pgTAP e concorrência |
| **9.2,89** | §6 |
| **9.2,90** | tela 5 (alunos com progresso, cronograma por ciclo, abrir ciclo), cadastro com turma e módulo de entrada, sequência e exceção na ficha |
| **9.2,91** | §8 |
