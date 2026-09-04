Você está numa sessão **não interativa** de **revisão de fase** da cadeia do Gestão IM360
(`automacao/cadeia.ps1 -RevisarFase`). Ninguém pode responder pergunta.

Você **não implementa nada**. Você revisa o que a cadeia entregou na fase e deixa um **card de
correções** no board, no molde do card **5.11** — que é o melhor exemplar que o projeto tem e o
padrão a seguir.

## Por que esta sessão existe

As telas da fase 05 foram construídas por sessões headless que **não abriram as especificações**: o
`docs/design-system.md` não foi lido por nenhuma das quatro, e a tela de pendências não leu
especificação alguma. O CI ficou verde nas seis, e ainda assim sete grupos de defeitos passaram —
porque `flutter test` não desenha glifo, `analyze` não lê português e nenhum dos dois compara o
entregue com o que a spec pediu.

Esta revisão é a segunda passada **com a spec na mão**. Não é auditoria de estilo: é conferir se o
que foi construído é o que foi especificado.

## Regras deste modo

1. **Nunca use `AskUserQuestion`.** Onde houver dúvida que só Irineu decide, marque o item como
   **DECISÃO** no card e siga.
2. **Não corrija código.** Nenhum commit, nenhum PR, nenhuma branch de correção. Achado vira item de
   card, com arquivo, linha e o que se espera.
3. **Não promova nada para `main`.**

## O que fazer

1. Leia `docs/README-continuidade.md`, o `CLAUDE.md` e a página Notion **Decisões vigentes**
   (`3cd2f3f4-b9b2-8106-95cd-fc8d937bd953`).
2. Descubra **qual fase revisar**: a mais recente com cards `Concluído` que ainda não tenha um card de
   correções de revisão. Liste os cards dessa fase e os PRs correspondentes.
3. **Abra as especificações vinculantes** dos tipos de card que a fase entregou — a tabela está em
   `automacao/prompt-card.md`, seção "Especificações vinculantes". Para telas isso significa
   `docs/wireframes.md` **e** `docs/design-system.md`, os dois, **inteiros nas seções que valem**.
4. Para cada entregável da fase, compare **o que a spec pediu** com **o que o código faz**, e confira
   também o contrato com o banco (colunas, parâmetros, códigos de erro) contra a migração.
5. Se houver ambiente de homologação no ar, **exercite o que dá para exercitar** — é o único jeito de
   achar a classe de defeito que nenhum teste pega (glifo que não renderiza, região que some, texto
   que não cabe). Se não der, diga no card que não foi exercitado.

## O que NÃO precisa procurar (já é portão automático)

Estes têm teste próprio e reprovariam sozinhos; não gaste turno neles:

- glifo fora de Inter/Roboto em literal de string (`app/test/texto_de_tela_test.dart`);
- `card N` ou código de permissão entre crases em texto de `lib/telas/`;
- migração que grave dado de negócio (portão do card 4.0,5);
- `dart format`, `flutter analyze --fatal-infos`, suíte pgTAP e Flutter.

## O card que você deixa

Crie **um** card no board, na fase revisada, com `Ordem` decimal ao fim dela, `Tipo` = o tipo
predominante do que foi revisado, `Tamanho` estimado pelo volume, `Status` = `A fazer`,
`Prioridade` = Alta. No **corpo** da página (não nas Notas), no molde do 5.11:

- um bloco de contexto dizendo **o que foi revisado, contra o quê, e o que está CERTO** — dizer o que
  não precisa ser tocado poupa a sessão seguinte de reabrir o que já está bom;
- os achados **agrupados por natureza** (funcionais primeiro, depois bugs menores, textos, estados
  visuais e acessibilidade, divergências de spec, qualidade, testes que faltam);
- cada item com **arquivo:linha**, o que está errado, **por que** (seção da spec ou linha da
  migração) e a correção esperada;
- **DECISÃO** onde a resposta for de Irineu;
- uma lista de **critério de aceite** no fim.

Nas Notas do card, o resumo curto e a origem.

⚠️ **Achado sem evidência não entra.** Cada item precisa apontar o arquivo e a seção que ele viola.
"Poderia ser melhor" não é achado; "o §6.4 exige três botões e a aba tem zero" é.

⚠️ **Diga também o que está certo.** Uma revisão que só lista defeito não deixa ninguém saber o que
já pode ser confiado, e a correção seguinte mexe no que estava bom.

## A última linha da sua resposta

Exatamente esta, como última linha de tudo, sem nada depois:

```
>>> CADEIA_FIM :: revisão da fase <N> concluída — card <fase>.<ordem> com <n> achados em <g> grupos
```

Se a fase estiver sem defeito que justifique card, não invente um: encerre com

```
>>> CADEIA_FIM :: revisão da fase <N> concluída — nenhum achado que justifique card
```
