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
| admissão em bloco lotado | **5.3** | `fn_bloco_admitir` — duas admissões simultâneas no último lugar |
| entrega com a última unidade em estoque | **6.3** | `fn_registrar_entrega` — duas saídas simultâneas do mesmo material |

Os dois são **pré-condição do marco 2** (card 2.8 §15).

## Onde roda

**O CI é o portão** (card 3.9): o job `banco` do `.github/workflows/testes.yml` sobe o stack e roda
esta suíte junto com a pgTAP, em todo PR e antes de todo `db push` e de todo deploy. Rodar na
máquina de quem desenvolve é opcional e usa exatamente os mesmos comandos — só depende de o daemon
do Docker estar no ar, que é a condição de `supabase start` e portanto de toda a suíte do banco, não
uma particularidade desta parte.
