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
| entrega com a última unidade em estoque | **6.3** | `fn_registrar_entrega` — duas saídas simultâneas do mesmo material |

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

Os dois são **pré-condição do marco 2** (card 2.8 §15).

## Onde roda

**O CI é o portão** (card 3.9): o job `banco` do `.github/workflows/testes.yml` sobe o stack e roda
esta suíte junto com a pgTAP, em todo PR e antes de todo `db push` e de todo deploy. Rodar na
máquina de quem desenvolve é opcional e usa exatamente os mesmos comandos — só depende de o daemon
do Docker estar no ar, que é a condição de `supabase start` e portanto de toda a suíte do banco, não
uma particularidade desta parte.
