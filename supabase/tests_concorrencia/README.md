# Suíte de concorrência — duas sessões

Aqui moram os testes que **não cabem no pgTAP**, por decisão do card 2.8 (§7, decisão *e*): uma
suíte de conexão única jamais exercita o `pg_advisory_xact_lock` do card 2.2 (c). O que se testa é
que **duas transações simultâneas** não produzem 11 alunos em 10 PCs nem saldo de estoque negativo —
e nenhuma `constraint` protege contra isso.

## Contrato

- Um arquivo `.sh` por regra de agregado, executável com `bash <arquivo>` a partir da **raiz do
  repositório**.
- Duas conexões `psql` concorrentes contra o stack local, com `statement_timeout` — o teste falha
  por *timeout* quando o lock não existe, e é isso que se está medindo.
- Saída: `exit 0` verde, qualquer outro código reprova o job `banco` do `testes.yml`.

O workflow roda **todos** os `*.sh` deste diretório. Enquanto não houver nenhum, ele diz isso em
voz alta no log e no resumo da execução, em vez de passar calado.

## Quem entrega

| Script | Card | O que trava |
|---|---|---|
| `admissao_ultima_vaga.sh` ✅ | **5.3** (03/09/2026) | `fn_bloco_admitir` — duas admissões simultâneas no último lugar |
| `entrega_ultimo_exemplar.sh` ✅ | **6.3** (04/09/2026) | `fn_registrar_entrega` — duas saídas simultâneas do mesmo material |
| `admissao_turma_modular.sh` ✅ | **7.4,5** (05/09/2026) | `fn_turma_modular_admitir` — duas admissões simultâneas na única vaga da turma Modular |

## O que o primeiro script ensinou (card 5.3)

- **A contraprova é obrigatória, e é a parte do teste que se esquece.** Um teste de concorrência que
  nunca foi visto REPROVANDO é indistinguível de um que não testa nada. O
  `admissao_ultima_vaga.sh` foi rodado contra uma `fn_bloco_admitir` sem o
  `pg_advisory_xact_lock`: as duas admissões passaram e o bloco fechou com **11 alunos em 10 PCs**,
  com o script saindo 1 pela CONTAGEM — não por *timeout*, que é justamente o que o §7 do card 2.8
  manda evitar.
- **Cliente `psql` pode não existir na máquina de quem desenvolve.** O script usa o do PATH quando
  há um e cai para o `psql` de dentro do container do stack local quando não há (o nome do container
  sai do `project_id` de `supabase/config.toml`). Teste que só roda no CI é teste que ninguém roda
  antes de abrir o PR.
- **Sem sessão não há permissão**, e as funções de aplicação exigem `turmas.alocar`. As duas sessões
  entram no **contexto de rotina** (card 2.2 §2.2) com um `set` de sessão — o mesmo contexto em que
  a escola-fixture escreve a camada `turmas` e em que as rotinas dos cards 5.4 e 5.5 vão rodar.
- **A pré-condição é conferida antes da corrida.** Bloco de partida diferente de 9/10 reprova com a
  causa escrita: num bloco com folga as duas admissões passariam e o teste ficaria verde sem medir
  nada. E o script **limpa o que criou** — é a única suíte do projeto que não roda dentro de uma
  transação com `rollback`, por definição.

## O que o segundo script ensinou (card 6.3, 04/09/2026)

- **A contraprova saiu na segunda casa decimal do que se esperava, e é a que importa.** Com
  `fn_registrar_entrega` reaplicada **sem** os `pg_advisory_xact_lock`, as duas sessões devolveram
  `ENTREGUE`, gravaram **duas** SAIDAS do mesmo exemplar e o material fechou com **saldo −1** — e com
  o lock no lugar, `A=ENTREGUE`, `B=BLOQUEADA_SEM_ESTOQUE`, saldo 0. Nenhuma `constraint` acusa a
  primeira: `movimento_sinal_ck` continua satisfeito nas duas linhas (SAIDA < 0) e os alunos são
  diferentes, então a `aluno_material_uk` também. Saldo é regra de **agregado**.
- **⚠️ Ao medir o saldo, esperar as DUAS sessões.** A primeira leitura da contraprova deu `0` e uma
  saída só — a sessão que segurava o lock ainda estava dentro do `pg_sleep`, e `read committed` não
  enxerga a linha não commitada. Um script que lesse o saldo antes do `wait` daria **verde na
  sabotagem**, que é o pior desfecho possível para um teste de concorrência.
- **A limpeza deste é mais cara que a do irmão, e o motivo é o assunto do card.**
  `movimento_estoque` é imutável: `tg_movimento_imutavel` recusa `DELETE` inclusive para quem tem
  `BYPASSRLS`, que é justamente o ponto dele. Um `delete` direto morreria em
  `PT409 / MOVIMENTO_IMUTAVEL` e — com `ON_ERROR_STOP=0` — a limpeza falharia **em silêncio**,
  deixando a fixture com o saldo errado para a próxima execução da suíte pgTAP na mesma máquina.
  Estornar em vez de apagar não serve: o estorno é o comportamento em teste no `052` e deixaria duas
  linhas onde a fixture espera zero. O script desliga o trigger pelo tempo do `delete`, no banco local
  descartável, e diz em voz alta que é isso que está fazendo.
- **As sessões passam o marcador por `p_observacao`**, que é parâmetro de `fn_registrar_entrega`:
  nada aqui escreve em `movimento_estoque` por fora da função, e a limpeza acha o que criou sem
  depender de `criado_em` nem de `limit`.

## O que o terceiro script ensinou (card 7.4,5, 05/09/2026)

- **A contraprova de novo, e de novo ela é a metade que quase não sai.** Com `fn_turma_modular_admitir`
  reaplicada **sem** os `pg_advisory_xact_lock`, as duas sessões devolveram um `id` de alocação e a
  turma de **uma vaga fechou com dois alunos** — o script saindo 1 pela CONTAGEM, `2 ≠ 1`, e não por
  *timeout*. Com o lock, a segunda espera, acorda vendo `1 de 1` e recebe `TURMA_LOTADA`. Nenhuma
  constraint acusa a primeira: `turma_modular_aluno_ativo_uk` é `(turma_id, aluno_id) where ativo` e
  os alunos são diferentes.
- **A capacidade aqui é COLUNA, não conta de PC.** No bloco, `capacidade + 1` alunos ainda esbarram
  em dez cadeiras que existem no mundo; numa turma Modular a capacidade é `turma_modular.capacidade`,
  e um número errado no banco não encontra nada que o desminta.
- **O que faltava era FIXTURE, e a decisão foi capacidade 1.** A corrida exige dois alunos MODULAR
  diferentes e a escola-fixture tinha um. A camada `modular` ganhou o segundo (`Aluno Modular 01`,
  sem combo — com combo ele geraria trilha e deslocaria a demanda imediata dos testes 050–062) e uma
  terceira turma, `Eletricista Individual 2026`, de **capacidade 1 e vazia**. A borda que interessa é
  ocupação = capacidade − 1: numa turma de 15 ela custaria catorze alunos de fixture para medir a
  mesma aritmética.
- **A limpeza é `delete`, não `ativo = false`.** Alocação inativa faria a execução seguinte encontrar
  a linha antiga e **reativá-la** (card 7.2 §4) em vez de inserir — a corrida passaria a medir um
  `update`, que não disputa vaga nenhuma, e o script ficaria verde sem lock nenhum.
- **A mudança de fixture reescreveu cinco asserções de premissa** (`030`, `070`, `090`), e uma delas
  é ganho: com um aluno MODULAR **sem** turma, o lado positivo de `ALUNO_SEM_TURMA` para o Modular
  passou a ser permanente na fixture — antes só existia dentro do `070` §6, desativando a turma de
  Eduarda dentro da transação.

Os três são **pré-condição do marco 2** (card 2.8 §15) — os dois primeiros já contados como cumpridos
em 04/09/2026.

## Onde roda

**O CI é o portão** (card 3.9): o job `banco` do `.github/workflows/testes.yml` sobe o stack e roda
esta suíte junto com a pgTAP, em todo PR e antes de todo `db push` e de todo deploy. Rodar na
máquina de quem desenvolve é opcional e usa exatamente os mesmos comandos — só depende de o daemon
do Docker estar no ar, que é a condição de `supabase start` e portanto de toda a suíte do banco, não
uma particularidade desta parte.
