# Estimativa da data de entrega — método

**Fonte do método de estimativa.** Card de origem: **3.13** (02/09/2026). Os cards de recalibração
ao fim das fases 04 a 09 **executam este documento**, sem redecidir o método.

O resultado de cada rodada — a data em si — **não mora aqui**. Mora na subpágina Notion
**"Estimativa de entrega"** do card 3.13, que guarda o histórico de todas as estimativas. Aqui fica
só a receita.

---

## 1. Por que estimar assim

O dono do produto quer uma data. Uma data chutada no começo do projeto envelhece mal e ninguém
percebe: ela é repetida em reunião até virar promessa. O antídoto não é acertar de primeira — é
**medir o que de fato aconteceu e reestimar em intervalo regular**, deixando o histórico visível.

Daí as três escolhas que o método faz, e que não devem ser desfeitas sem motivo escrito:

**(a) A unidade é ponto, não card.** O card 2.8 (957 linhas de estratégia de testes) e o card 7.4
(um card no dashboard) valem 1 cada se contarmos cards. Velocidade em cards/dia medida nas fases 1
a 3 e aplicada às fases 4 a 8 dá **6 cards/dia → 8 dias até o go-live**, que é ficção. Tamanho:
**P=1, M=3, G=5, GG=8**.

**(b) O eixo da calibração é o Tipo, não a Fase.** As fases 4 a 8 repetem o mesmo padrão —
`Schema/migração` → `Função/regra` → `Tela` → `Marco/validação`. "Quanto custa uma tela", medido na
fase 4, vale direto para as fases 5 a 8. Calibrar pela média da fase joga fora justamente a parte
transferível.

**(c) Latência não se divide por velocidade.** Marco de validação com a secretaria, revisão das
exceções pelo pedagógico, treinamento, revisão da App Store: isso é calendário de outra pessoa.
Somar esses pontos ao esforço e dividir tudo pela velocidade erra **no fim** do cronograma, que é
exatamente onde a data dói. Cards de Tipo `Marco/validação` e `Externo` entram como **blocos de dias
corridos**, não como pontos de esforço.

## 2. Instrumentação do board

Três propriedades no data source `e50abe7f-1688-402a-96b5-c6049b24ce82` (criadas em 02/09/2026):

| Propriedade | Tipo | Para que serve |
|---|---|---|
| `Concluído em` | data | série histórica real. Antes disso a data de conclusão vivia **dentro do texto das Notas** ("CONCLUÍDO 01/09/2026") — legível por gente, inútil para cálculo |
| `Tamanho` | select P/M/G/GG | 1/3/5/8 pontos |
| `Tipo` | select | `Documento/decisão`, `Schema/migração`, `Função/regra`, `View`, `Tela`, `Infra/CI`, `Marco/validação`, `Externo` |

⚠️ **Preencher `Concluído em` faz parte de encerrar a tarefa**, junto com `Status = Concluído`. Card
concluído sem data é um buraco na série, e a série é o único ativo do método.

## 3. A receita, em cinco passos

1. **Medir.** Pontos concluídos por dia e por Tipo, nas fases já fechadas. A unidade de velocidade é
   **ponto por dia-pleno** (um dia inteiro dedicado), não por dia de calendário.
2. **Redimensionar** os cards restantes. O conhecimento adquirido muda o tamanho — é para isso que
   se recalibra. Sem este passo, a rodada só reaplica a aritmética a números velhos.
3. **Separar** esforço (soma de pontos ÷ velocidade) de latência (blocos de dias corridos).
4. **Publicar P50 e P80.** Nunca uma data única: data única é lida como promessa.
5. **Registrar** a linha nova no histórico da subpágina "Estimativa de entrega". Não reescrever a
   data em outros cards — N cópias divergem.

### Capacidade semanal

Velocidade é ponto por **dia-pleno**; quantos dias-plenos cabem na semana é declaração de Irineu,
não medição. Vigente desde 02/09/2026: **fins de semana + algumas noites** = 2 dias de fim de semana
× 1,0 + ~2,5 noites × 0,4 ≈ **3,0 dias-plenos por semana**. Mudou o ritmo, muda este número — e ele
é o parâmetro mais sensível de todos.

### Blocos de latência (dias corridos)

| Card | Bloco | Dias |
|---|---|---|
| 4.8, 6.9, 8.8 | marco de validação com secretaria/monitor/direção | 4 cada |
| 9.3 | revisão das exceções pelo pedagógico | 7 |
| 9.4 | dry-run e conferência de totais | 3 |
| 9.6 | treinamento dos 4 perfis | 7 |
| 9.7 | janela de virada (fim de semana) | 2 |
| 10.2 | abertura das contas de desenvolvedor | 5 |
| 10.6 | revisão de Google Play e App Store | 14 por rodada |

No P50 assume-se que **60%** da latência não se sobrepõe ao desenvolvimento; no P80, **100%** (nada
se sobrepõe) e a revisão das lojas vai a **duas** rodadas.

### Como sair de P50 e P80

- **P50** = velocidade central medida, latência parcialmente paralela.
- **P80** = **metade** da velocidade do P50, latência integral. A metade não é pessimismo decorativo:
  é o cenário em que as telas custam o dobro do tamanho atribuído — e enquanto as telas de negócio
  não estiverem medidas, esse é o risco dominante (ver §4).

⚠️ **Se a consulta ao board falhar por cota** ("usage limit for Query Data Source"), os mesmos
números saem de uma visão agrupada do board na UI do Notion, por `Tipo` e por `Concluído em`.
Não é motivo para pular a rodada.

## 4. O que este método NÃO resolve

**A maior incerteza não é a velocidade — é o dimensionamento das telas.** Na primeira rodada
(02/09/2026), `Tela` responde por **107 dos 225 pontos de esforço restantes até o go-live (48%)**, e
o único card de `Tela` já medido é o 3.7 (esqueleto do app com login, 8 pontos) — que não é uma tela
de negócio com CRUD, filtros, validação e permissões. Metade do trabalho restante está apoiada em
uma medição de outra natureza.

É por isso que o card **4.9** (recalibração ao fim da fase 04) é o mais importante da série: é a
primeira vez que quatro telas de negócio reais entram na medição. Espera-se que a banda P50–P80
**encolha bastante** ali. Se não encolher, o problema é dimensionamento e não velocidade, e a
resposta é quebrar os cards `GG` em cards menores — card grande demais é card que não se sabe medir.

## 5. Primeira estimativa (02/09/2026)

Medido: **135 pontos em 5 dias** (29/08 a 02/09) — 82 de `Documento/decisão`, 27 de `Infra/CI`,
10 de `Função/regra`, 8 de `Schema/migração`, 8 de `Tela`. Por dia: 5, 11, 31, **75**, 13.
A média (27) é puxada por um único dia atípico; a mediana é 13. Adotado **P50 = 18 pts/dia-pleno**
e **P80 = 9**.

Restante até o go-live (fases 03 a 09): **252 pontos = 225 de esforço + 27 de latência**, em 49 cards.

| | Go-live (fim da fase 09) | Lojas (fim da fase 10) |
|---|---|---|
| **P50** | **20/10/2026** | 10/11/2026 |
| **P80** | **30/11/2026** | 12/01/2027 |

**Contra o alvo registrado nas Decisões vigentes (outubro/2026):** o P50 cabe, por 11 dias. O P80
não. Ou seja — outubro é alcançável, não é seguro. A leitura honesta para o dono do produto é
*"entre meados de outubro e o fim de novembro, com a resposta melhor no fim da fase 4"*, e não uma
data.

Como referência do quanto o método já mudou a conversa: o plano v1.1 falava em **~18 semanas**, que
a partir de 29/08 dariam **02/01/2027** — mais tarde que o próprio P80. As fases 1 a 3 correram bem
acima do previsto, e é isso que a medição captura e o chute inicial não capturava.

**Premissas que, se mudarem, invalidam a estimativa:** (a) ritmo de ~3,0 dias-plenos por semana;
(b) escopo do board congelado — card novo entra como pontos novos, sem exceção; (c) as telas de
negócio custam o que o dimensionamento diz; (d) nenhuma janela do calendário escolar proíbe a virada
na data resultante — **isso ainda não foi verificado com Irineu** e está anotado no card 7.5.
