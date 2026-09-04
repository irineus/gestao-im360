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
   em toda tabela, nomes em português snake_case, credenciais nunca em texto puro.
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
