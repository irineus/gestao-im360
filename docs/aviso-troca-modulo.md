# Aviso de troca de módulo (Modular)

**Fonte do aviso de troca de módulo.** Card 9.2,85 (banco) e 9.2,86 (telas). Parte 1 da proposta
aprovada pelo dono do produto em 10/11/2026; a Parte 2 — a turma em rodízio — é dos cards 9.2,87 a
9.2,91 e **não** está aqui.

## 1. De onde veio

Na planilha, o quadro "Troca de módulo" mostra a previsão de conclusão do módulo atual de cada
curso Modular e pinta a data: **laranja** quando faltam 10 dias ou menos, **vermelho** no dia ou
depois. O dono do produto pediu o mesmo no sistema (vídeo e áudios de 06/11/2026) e fechou as regras
em 10/11/2026:

| Pergunta | Decisão |
|---|---|
| Quantos dias antes o laranja começa? | 10, ajustável em Parâmetros |
| Vermelho no próprio dia? | Sim — "o ideal é não chegar no vermelho" |
| Por turma ou por curso? | Por turma (a Massagem tem duas) |
| Quem vê e resolve a pendência? | Direção e Pedagógico (decisão de Irineu) |
| Trocar de módulo é trocar de livro? | Nem sempre. Só quando o próximo módulo é de outro livro |

O que o aviso protege, nas palavras dele: **nenhum módulo começa sem alinhamento com o professor**.
A pendência "deve ser resolvida antes da troca de módulo".

## 2. O que existe no banco (card 9.2,85)

Migração `20261110120000_aviso_troca_modulo.sql`, teste `104_aviso_troca_modulo`.

### 2.1 A situação — colunas novas de `v_turma_modular_lotacao`

Entraram **no fim** da view (card 9.2,7), e é dela que o Dashboard, a tela 5 e a rotina leem:

| Coluna | O que é |
|---|---|
| `modulo_corrente_cronograma_id` | a linha de `turma_modular_modulo` do módulo corrente |
| `proximo_modulo_id`, `proximo_modulo_nome` | o primeiro módulo do **catálogo** do curso, depois do corrente, que a turma ainda não concluiu |
| `proximo_material_id`, `proximo_material_nome` | o livro do próximo módulo |
| `troca_de_livro` | o próximo módulo é de **outro** material. Nulo sem próximo módulo |
| `dias_para_troca` | `prev_conclusao − fn_hoje()`. Zero é hoje; negativo, vencida; nulo sem previsão |
| `situacao_troca` | `EM_DIA`, `PROXIMA`, `HOJE_OU_VENCIDA` ou `SEM_PREVISAO`; nulo sem módulo corrente |

- **`PROXIMA`** (laranja): `0 < dias_para_troca <= troca_modulo_alerta_dias`.
- **`HOJE_OU_VENCIDA`** (vermelho): `dias_para_troca <= 0` — **já no dia**.

⚠️ **`modulo_atrasado` não mudou.** Continua `prev_conclusao < fn_hoje()` (card 7.4) e é o que o
cartão de lotação do Dashboard conta. As duas colunas convivem com bordas diferentes de propósito:
uma diz "passou da data", a outra "a troca chegou". O teste 104 §1 mede as duas na mesma linha.

⚠️ **O próximo módulo vem do catálogo, não do cronograma.** O cronograma pode ainda não ter a linha
seguinte (a tela 5 oferece acrescentá-la), e a troca de livro precisa aparecer antes disso.

A janela é o parâmetro **`troca_modulo_alerta_dias`** (10 — o 17º de `seed-inicial.md` §3), lido por
`fn_param_int` **sem default**: ausente, a view levanta `PARAMETRO_AUSENTE` em vez de inventar um 10.

### 2.2 A pendência — `TROCA_MODULO_ALINHAR`

Aberta por `rt_pendencias_diaria` (o sexto bloco), que lê `situacao_troca` da view — a comparação
não se repete na rotina, como `abaixo_minimo` no bloco de estoque.

| | |
|---|---|
| Chave | `TROCA_MODULO:<turma_id>:<cronograma_id>` |
| Severidade | **MEDIA** em `PROXIMA`, **ALTA** em `HOJE_OU_VENCIDA` — a mesma linha sobe |
| Abre | quando o módulo corrente entra na janela |
| Fecha sozinha | só quando a troca **deixa de estar próxima**: previsão adiada para além da janela, turma desativada ou linha removida do cronograma |

Três regras a separam de todos os outros tipos da rotina, e as três são a decisão do card:

1. **Resolvida por gente não reabre.** "Resolvida" quer dizer "o alinhamento foi feito", e a
   condição (a troca está próxima) continua verdadeira até o dia. O que distingue é
   `resolucao = 'RESOLVIDA'` com `resolvida_por` preenchido. **Ignorada** continua voltando (card
   5.5), e o fechamento automático também.
2. **Avançar o módulo não fecha.** Se a turma trocou de módulo sem o alinhamento registrado, a
   pendência fica — em ALTA, dizendo "foi concluído sem o alinhamento com o professor registrado".
3. **A descrição carrega a troca de livro**, quando há: "o próximo módulo, X, é de outro livro (Y)".

A turma vai na **chave** porque `pendencia` não tem coluna de turma Modular; é o precedente de
`REP:<aluno>:CONTINUO`, que a central também lê da chave.

⚠️ **Para o card 9.2,88 (rodízio):** a chave carrega a linha do cronograma. Se o rodízio **reusar**
a linha a cada volta, a regra 1 calaria o aviso da segunda volta em diante — a chave terá de ganhar
o ciclo.

### 2.3 Quem enxerga — `turmas.alinhar_modulo`

O 51º código do catálogo, na matriz inicial só de **direção e pedagógico**. As políticas de
`select` e `update` de `pendencia` o exigem **para este tipo, e só para ele**, além de
`pendencias.ler` / `pendencias.resolver`.

- A central, o contador do menu e a faixa "Atenção hoje" leem `v_pendencias_abertas`
  (`security_invoker`): quem não tem o código simplesmente não recebe a linha.
- `fn_pendencia_resolver_id` é `invoker`: a secretaria, que tem `pendencias.resolver`, recebe
  `PENDENCIA_INEXISTENTE` — o mesmo caminho que isola unidade.
- Por ser um código, a direção pode estendê-lo à secretaria na Administração, sem deploy. É a
  resposta à dúvida que o dono do produto deixou em aberto ("a Wanessa pode opinar").

A **cor** (a situação na view) não é restrita: quem lê turmas vê o laranja e o vermelho. Restrito é
o aviso que pede ação.

## 3. O que as telas fazem (card 9.2,86)

Sem migração: é consumidor do §2. Testes em `app/test/aviso_troca_modulo_test.dart` (lógica e o
painel) e em `app/test/tela_turmas_modular_test.dart` (tela 5), em desktop e em 390 px.

**Nada no app decide a situação.** Laranja e vermelho vêm de `situacao_troca`, e "quanto falta" de
`dias_para_troca` — os dois da view, com o hoje do banco. Código de situação que o app não conhece
vira nulo, nunca "em dia". E a cor nunca vai sozinha: todo aviso diz "faltam 6 dias", "hoje" ou
"atrasada há 3 dias" por extenso (design-system §8.2).

| Onde | O que mudou |
|---|---|
| **Dashboard** — região "Lotação Modular" | Painel **"Próximas trocas de módulo"** (`ProximasTrocasModulo`, em `lotacao_modular.dart`): uma linha por turma, da troca mais próxima para a mais distante — curso · turma, módulo atual → próximo, data e quanto falta, e "troca de livro: X" quando há. Tocar abre a tela 5 com a turma expandida (`?turma=`). Turma sem previsão fica de fora, e o painel diz isso em vez de sumir. Mora na região da lotação porque é a **mesma leitura** (`v_turma_modular_lotacao`): divide com ela o carregamento e o erro |
| **Dashboard** — "Atenção hoje" | Quarto número, "trocas de módulo a alinhar com o professor", **só para quem tem `turmas.alinhar_modulo`**. Para os outros a RLS não devolve a linha, e mostrar zero seria um número que ninguém mediu |
| **Pendências** | Tipo novo com rótulo "Troca de módulo — alinhar com o professor" e ação **"Ver turma"**, que abre a tela 5 na turma. A turma sai da **chave** (`turmaModularDaChave`), pelo precedente de `sentidoVirada`. O painel diz que avançar o módulo **não** fecha a pendência |
| **Turmas Modular** — cartão | Selo "troca de módulo em 6 dias" / "hoje" / "atrasada há 3 dias" (âmbar na janela, vermelho no dia), que toma o lugar de "módulo atrasado" quando existe; e o selo "troca de livro" |
| **Turmas Modular** — cronograma | A linha do módulo corrente diz "troca: faltam 6 dias", na cor da situação da **turma** |
| **Turmas Modular** — avançar módulo | Quando `troca_de_livro`, o diálogo avisa "O próximo módulo, X, é de outro livro: Y" e lista, **já marcados**, os alunos ativos da turma que têm o livro na trilha e ainda não o receberam; dá para desmarcar. Sem troca de livro, nada é oferecido |

### 3.1 A entrega no avanço — o que ela é e o que não é

- **É a entrega de sempre.** Cada aluno marcado passa por `fn_registrar_entrega`, com o livro do
  próximo módulo — as mesmas regras, o mesmo movimento de estoque, o mesmo estorno. Não há função
  nova nem "entrega em lote" no banco.
- **Vem depois do avanço, e não o desfaz.** O módulo avança; em seguida as entregas saem, uma por
  aluno. Falta de estoque ou erro numa delas não impede as outras nem volta o módulo: o resultado
  vira **diálogo** dizendo quem ficou sem o livro, com o caminho (a aba Trilha da ficha).
- **Quem é oferecido:** aluno **ativo na turma**, com o livro **na trilha** e **não entregue**
  (`v_aluno_trilha`). Quem já recebeu não aparece; quem não tem o livro na trilha também não — a
  entrega dele é assunto da ficha.
- **Quem vê a lista:** quem tem `estoque.lancar_saida`, `estoque.ler` e `alunos.ler`. Sem elas o
  diálogo mostra só o aviso do livro e diz que a entrega fica para quem registra entregas — e nem
  consulta a trilha.

⚠️ **Para o card 9.2,88 (rodízio):** "quem ainda não tem o livro" hoje é lido da trilha do aluno.
Com a sequência por aluno, o próximo módulo deixa de ser o mesmo para a turma inteira, e esta lista
passa a depender do módulo de cada um.
