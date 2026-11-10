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

Ver o card. Em resumo: painel "Próximas trocas de módulo" no Dashboard, o tipo novo na central e na
faixa "Atenção hoje", a cor no cronograma da tela 5 e, ao avançar o módulo com `troca_de_livro`, a
oferta de registrar a entrega do livro na mesma janela.
