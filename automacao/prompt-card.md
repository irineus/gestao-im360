Você está numa sessão **não interativa** da cadeia de execução do Gestão IM360
(`automacao/cadeia.ps1`, card 5.5,5). Ninguém está lendo em tempo real e **ninguém pode responder
pergunta**. Execute **um** card do board, do começo ao fim, e termine com a linha de veredito.

## Regras deste modo

1. **Nunca use `AskUserQuestion`.** Onde o fluxo interativo perguntaria, siga o caminho documentado
   ou pare com veredito.
2. **Não promova para `main`.** Nunca. Nem abra PR com `--base main`. Isso é de Irineu, e há hook que
   recusa.
3. **Um card só.** Terminado o card, pare — quem decide se vem outro é o driver.
4. **Não invente escopo.** Nota de card que diverge do que faz sentido: faça o coerente, registre a
   divergência nas Notas e na subpágina. É a regra que já vale para toda sessão.

## O que fazer

1. Leia `docs/README-continuidade.md`, o `CLAUDE.md` e a página Notion **Decisões vigentes**
   (`3cd2f3f4-b9b2-8106-95cd-fc8d937bd953`). Em conflito, o Notion vence.
2. Invoque a skill **`proxima-tarefa`** e siga a seção **"Modo não interativo (cadeia)"**. Escolha o
   card **sozinho**: o primeiro não concluído na ordenação
   `CAST(substr("Fase",1,2) AS INTEGER), "Ordem"`, **pulando** os `Em andamento` cuja Nota tenha
   `AGUARDANDO RETORNO DOS USUÁRIOS`.
3. Se o card for de `Tipo` = **`Externo`**, ou se a Nota disser que ele depende de ação de Irineu que
   você não pode fazer (secret, conta em serviço externo, disparo manual de workflow, decisão de
   produto): **não execute**. Termine com `CADEIA_FIM`.
4. Se for **`Marco/validação`**: faça tudo o que não depende de gente (pré-condições medidas,
   critérios pré-verificados contra o banco e o código) e **deixe as mensagens de WhatsApp prontas**,
   uma por perfil, no molde do §9.1 da subpágina do card 4.8. Depois **mantenha o card `Em andamento`**
   com a linha `AGUARDANDO RETORNO DOS USUÁRIOS desde <data>` no topo das Notas — e feche com
   `CARD_OK` normalmente, porque a parte automatizável foi entregue e a fila não deve parar.
5. Execute o card respeitando o `CLAUDE.md`: migrações só via CI/CD, regra de negócio no banco, RLS
   em toda tabela, nomes em português snake_case, credenciais nunca em texto puro. **E as
   especificações vinculantes do tipo do card, abaixo — elas não são leitura opcional.**

## Especificações vinculantes, por `Tipo` de card

⚠️ **Isto existe porque foi medido, não por precaução.** Na corrida de 04/09/2026, das quatro telas da
fase 05: o `docs/design-system.md` **não foi aberto por nenhuma delas**, o `docs/wireframes.md` foi
aberto 3, 1, 0 e 2 vezes, e a tela de pendências (5.8) **não abriu especificação alguma**. A revisão
seguinte encontrou 7 grupos de defeitos, e os grupos de texto, estado vazio, estado visual e
acessibilidade são exatamente o conteúdo do documento que ninguém leu. O modelo era o mesmo; o que
faltou foi a instrução de que estes documentos mandam.

| `Tipo` | Documentos que mandam |
|---|---|
| **Tela** | `docs/wireframes.md` **e** `docs/design-system.md` (os dois, sempre) + `docs/views-leitura.md` (contrato com o banco) + `docs/permissoes-matriz.md` (conjunto da rota) |
| **Schema/migração**, **Função/regra**, **View** | `docs/modelagem-dados-ddl.md` + `docs/estrategia-testes.md` + `docs/views-leitura.md` |
| **Infra/CI** | `docs/ci-cd.md` + `docs/estrategia-testes.md` |
| **Marco/validação** | `docs/estrategia-testes.md` §15 (critérios de aceite) |

**Como usar, e a forma importa mais que a leitura:**

1. **Antes de escrever código**, abrir os documentos do tipo, localizar as seções que descrevem *este*
   entregável e **extrair os requisitos como lista explícita** — um item por exigência, com a seção de
   origem. Ler prosa e sair construindo é o que produziu os defeitos: a exigência de três botões numa
   aba estava escrita e não foi implementada.
2. **Antes de abrir o PR**, percorrer a lista item a item contra o que ficou pronto. O que não fechou
   **não some em silêncio**: vira divergência registrada em `docs/wireframes.md` §17 ou
   `docs/design-system.md` §11, com o motivo, e é dito no corpo do PR.
3. O documento é **fonte**, não sugestão. Discordar dele é legítimo; discordar sem registrar, não.
6. **Exercite, não leia.** Suíte pgTAP (`supabase test db`) verde, `flutter test`, `flutter analyze
   --fatal-infos`, `dart format`, portão de migrações. Se o card criar regra nova, o teste que a mede
   precisa ter sido visto **vermelho** com a regra sabotada — é o padrão do projeto e é o que separa
   teste que mede de teste que acompanha.
7. Feche o card: subpágina de resultado, Notas com `CONCLUÍDO <data>:`, Decisões vigentes se houve
   decisão, `Status` e `Concluído em`.
8. Feche o Git: commit, push, PR contra `develop`, esperar o CI (`gh pr checks <n> --watch`) e
   **mergear no verde, sem perguntar**.

## Quando o CI reprovar

Corrija e empurre de novo. **Pare e não mergeie** só quando:

- a falha repetir **pela mesma razão** (mesmo job, mesma asserção ou mesmo erro) depois de uma
  tentativa de correção;
- for a **terceira** tentativa;
- o conserto exigir algo que só Irineu pode fazer.

Nesses casos, `CARD_PARADO` dizendo **qual dos três** e com o trecho do log que prova.

## A última linha da sua resposta

Exatamente uma destas, como **última linha de tudo**, sem nada depois:

```
>>> CARD_OK <fase>.<ordem> pr=<numero> merge=develop
>>> CARD_PARADO <fase>.<ordem> :: <motivo em uma linha>
>>> CADEIA_FIM :: <motivo em uma linha>
```

`CARD_OK` **só** com o merge em `develop` feito de verdade. PR aberto e não mergeado é `CARD_PARADO`
— o driver confere o SHA de `origin/develop` e um `CARD_OK` sem merge para a cadeia.
