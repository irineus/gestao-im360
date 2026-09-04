# Cadeia de execução — uma sessão por card, sem acompanhamento

> **Card de origem:** 5.5,5 (03/09/2026). **Decisão que a habilita:** merge em `develop` automático
> com o CI verde; promoção `develop` → `main` sempre manual. Ver `CLAUDE.md`, "Fluxo de entrega".

## 1. O que é

Um driver (`automacao/cadeia.ps1`) abre **uma sessão headless por card**, em sequência, lê o veredito
que cada uma imprime e decide se continua. O objetivo não é executar mais rápido — é **executar sem
Irineu de plantão**.

Contexto novo a cada card não é efeito colateral, é requisito: um card `GG` já consome sessão inteira,
e emendar quatro num contexto só degrada a partir do terceiro.

## 2. A regra que mudou, e por quê

Até 03/09/2026 toda tarefa terminava em duas `AskUserQuestion` — PR/merge em `develop`, depois
promoção para `main`. Sessão headless não tem a quem perguntar, então a cadeia **exigia** revisitar a
primeira pergunta.

O que a regra de 01/09 protegia era **o CI**: "vermelho não se mergeia". Isso continua valendo, e
agora é o CI que executa a regra em vez de um humano repetindo-a. O clique ficou onde o risco está de
verdade: **`main` aplica migração em produção**, e nenhuma sessão a promove.

> **`develop` é do CI; `main` é de Irineu.**

## 3. Onde a cadeia para

| Motivo | Como aparece |
|---|---|
| Card de `Tipo` = `Externo`, ou nota dizendo que depende de Irineu | `CADEIA_FIM` |
| CI vermelho **pela mesma razão** depois de uma correção | `CARD_PARADO` |
| Terceira tentativa de correção | `CARD_PARADO` |
| Conserto exige secret, conta externa ou decisão de produto | `CARD_PARADO` |
| Sessão terminou sem a linha de veredito | o driver para e aponta o log |
| Sessão disse `CARD_OK` mas `origin/develop` não andou | o driver para (§5) |

**Marco de validação NÃO para a cadeia** (decisão de Irineu, 03/09/2026). A sessão entrega as
pré-condições medidas e as **mensagens de WhatsApp prontas** para os usuários da escola, mantém o card
`Em andamento` com `AGUARDANDO RETORNO DOS USUÁRIOS desde <data>` e segue. Cards nesse estado são
pulados pelas sessões seguintes. O modelo das mensagens é o §9.1 da subpágina do card 4.8 — é o
melhor exemplar que o projeto tem: um passo por linha, "você não tem como estragar nada" **antes** dos
passos, e o que é normal dito antes de a pessoa reportar como defeito.

Com isso a fila automatizável vai de **5.4 até 9.2** — cerca de 30 cards — e para na revisão das
exceções da migração (9.3), que é sua.

## 4. Pré-requisitos

- **CLI do Claude Code instalada** (`claude` no PATH). O app desktop não serve: a cadeia precisa de
  processo por card.
- `gh` autenticado, `git`, `node`, e **Docker rodando** — sem ele o `supabase start` não sobe e a
  sessão gasta uma rodada descobrindo isso.
- Working tree limpo e `HEAD` fora de `main`.
- **Diretório confiado pela CLI e login feito.** Sem a confiança, a CLI **ignora o `permissions.allow`
  inteiro** do `.claude/settings.json`; sem login, `claude -p` imprime `Not logged in` e **sai com
  código 0**. As duas se resolvem rodando `claude` interativamente aqui uma vez.
- **MCP do Notion pré-autorizado.** `--permission-mode acceptEdits` cobre edição de arquivo e **não**
  ferramenta de MCP: o driver passa `--allowedTools mcp__claude_ai_Notion`. A concessão mora no
  driver, e não no `permissions.allow`, para valer **só** na cadeia — sessão interativa continua
  perguntando.

`.\automacao\cadeia.ps1 -Verificar` mede tudo isso e não executa nada. A última checagem é uma
**sonda de verdade**: abre uma sessão mínima e manda chamar o Notion, porque é a primeira coisa que
todo card faz. Ela assere por **marcador de falha** e não por token de sucesso — duas versões que
exigiam a palavra exata reprovaram com o sistema bom (a sessão devolveu uma tabela numa, e "OK" na
outra), e checagem que reprova à toa ensina a ignorar vermelho.

## 5. Por que o driver não acredita na sessão

`CARD_OK` é **relato**. Antes de seguir para o próximo card, o driver compara o SHA de
`origin/develop` antes e depois: se não andou, a cadeia para.

O modo de falha que isso pega é o pior possível numa execução sem ninguém olhando — a sessão acredita
que mergeou, o board diz `Concluído`, e `develop` está parado. O card seguinte nasceria de uma base
sem o anterior, e o erro só apareceria três cards adiante, como conflito ilegível.

## 6. O guarda de comandos

`.claude/hooks/guarda-destrutivos.mjs` (`PreToolUse` em `Bash`) recusa:

- `supabase db reset|push|dump` com **alvo remoto** (`--linked`, `--db-url`, `--project-ref`);
- `git push` mirando `main`;
- `gh pr create --base main`.

**Ele substitui uma negação que era ampla demais.** O `.claude/settings.json` negava `supabase db
reset` por prefixo — mas o `db reset` **local** é justamente o passo que o `testes.yml` roda para
provar que a sequência de migrações sobe limpa num banco vazio. Negar os dois juntos custava um clique
por sessão interativa; numa sessão headless **mata a execução no primeiro card**.

O hook fica mais restritivo que a regra antiga em dois pontos: fatia a linha nos operadores de
encadeamento antes de olhar (a negação por prefixo deixava passar
`git status && supabase db reset --linked`) e cobre `push` e `dump`, não só `reset`.

**Comando não é o texto que ele carrega.** Descoberto na estreia: a primeira tentativa de abrir o PR
do próprio card 5.5,5 foi bloqueada pelo guarda, porque o corpo do PR *descrevia* o comando perigoso
e viajava dentro de um heredoc do `gh pr create`. Por isso o corpo de `<<EOF … EOF` é apagado antes
de fatiar e o casamento é ancorado no **início** do segmento. E por isso `VAR=valor` é removido da
frente — sem esse terceiro passo a âncora seria contornável, e o conserto de um falso-positivo teria
aberto um falso-negativo. Numa cadeia sem ninguém olhando, um guarda que bloqueia demais para tudo
sem causa real; um que bloqueia de menos deixa passar o que destrói banco.

Hook com erro interno **sai com 0**. Portão quebrado que reprova tudo trava o projeto; as proteções do
`allow`/`deny` continuam de pé por baixo.

**Bateria:** `node --test .claude/hooks/guarda-destrutivos.test.mjs` — 7 testes, 18 comandos, os dois
grupos (o que tem de passar e o que tem de bloquear). Guarda sem teste apodrece: quem mexer na regex
depois não teria como saber se afrouxou. Ainda **não** roda no CI — item 4 do §9.

## 7. Uso

```powershell
.\automacao\cadeia.ps1 -Verificar        # diagnóstico, não executa
.\automacao\cadeia.ps1 -MaxCards 1       # um card (modo piloto)
.\automacao\cadeia.ps1 -MaxCards 30      # até a fila acabar ou precisar de você
```

Histórico em `automacao/logs/cadeia.jsonl` (uma linha por card) e a saída bruta de cada sessão em
`automacao/logs/card-<carimbo>.log`. Nenhum dos dois é versionado.

## 8. O que a cadeia não faz

- **Não promove para produção.** Continua sendo você, com o clique e o disparo manual do workflow.
- **Não decide escopo.** Nota de card que diverge continua virando divergência registrada, não
  invenção.
- **Não substitui os marcos.** Ela prepara a validação; quem valida é gente.

## 9. Em aberto

1. **A fila longa afasta `develop` de `main`.** Trinta cards em `develop` significam um lote grande de
   migrações na promoção seguinte. Promover ao fim de cada fase mantém o lote do tamanho de uma fase —
   é recomendação, não regra, e a decisão é de Irineu a cada promoção.
2. **Custo por card não foi medido.** A primeira corrida com `-MaxCards 1` é o que dá a primeira
   medida; anotar junto da recalibração (cards `X.10`).
3. **Sessão longa demais.** Um card `GG` com laço de CI pode passar de uma hora. Não há hoje corte por
   tempo no driver; se virar problema, o alvo é um teto por sessão, não o teto de cards.
4. **A bateria do guarda não roda no CI.** Ela existe e é verde, mas ninguém a executa fora da
   máquina de quem mexeu — e o `testes.yml` é o lugar dela. Enquanto isso não for feito, uma regex
   afrouxada passa despercebida no PR, que é exatamente o que a bateria existe para impedir.
