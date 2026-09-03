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

- **P50** = velocidade central medida (líquida de escopo novo — ver §6b), latência parcialmente
  paralela.
- **P80** = velocidade do P50 **dividida por 1,5**, latência integral. O divisor não é pessimismo
  decorativo: ele precifica o que ainda **não foi medido**, e por isso encolhe quando algo passa a
  ser medido. Era **2** enquanto as telas de negócio eram o grande vão; virou **1,5** em 03/09/2026,
  quando quatro telas de negócio saíram no tamanho atribuído (§6a). O que o 1,5 ainda cobre é a fase
  09 e a fase 10, sem medição nenhuma. **Rever o divisor a cada rodada, para cima ou para baixo,
  conforme o que ainda estiver por medir** — divisor que não se mexe vira superstição.

⚠️ **Se a consulta ao board falhar por cota** ("usage limit for Query Data Source"), os mesmos
números saem de uma visão agrupada do board na UI do Notion, por `Tipo` e por `Concluído em`.
Não é motivo para pular a rodada.

## 4. O que este método NÃO resolve

**A maior incerteza é sempre o que ainda não foi medido, e ela se desloca a cada rodada.** Esta
seção é reescrita por cada recalibração, com o alvo da vez.

~~**A maior incerteza não é a velocidade — é o dimensionamento das telas.**~~ — **respondido em
03/09/2026 pelo card 4.9** (ver §6). Enunciado original preservado, porque é ele que justificava o
P80 = metade do P50: na primeira rodada (02/09/2026), `Tela` respondia por **107 dos 225 pontos de
esforço restantes até o go-live (48%)**, e o único card de `Tela` medido era o 3.7 (esqueleto do app
com login, 8 pontos) — que não é uma tela de negócio com CRUD, filtros, validação e permissões.
Metade do trabalho restante estava apoiada em uma medição de outra natureza. Era por isso que o card
**4.9** era o mais importante da série. A banda **encolheu**, como se esperava, e não foi preciso
quebrar os `GG` em cards menores.

⚠️ **A maior incerteza agora é a tabela de blocos de latência do §3** — os 31 dias corridos até o
go-live. Ela foi escrita de uma vez, por analogia, e **nunca foi medida contra a realidade**: nenhum
marco de validação, revisão de terceiro ou treinamento aconteceu ainda. Desde 03/09/2026 a latência
é maior que o esforço no P50, ou seja, **o número menos confiável do modelo passou a ser o que mais
pesa na data**. O primeiro teste é o marco 4.8 (bloco declarado de 4 dias): ao fechá-lo, anotar
quantos dias corridos ele de fato consumiu e comparar com o bloco. O mesmo vale para 6.9, 8.8, 9.3,
9.4, 9.6 e 9.7 — sem essa anotação, a próxima rodada recalibra a velocidade e deixa intacta a
metade da conta que hoje pesa mais.

## 5. Primeira estimativa (02/09/2026)

> **Superada pela rodada de 03/09/2026 (card 4.9).** Fica aqui como registro — a estimativa vigente
> está na subpágina Notion "Estimativa de entrega" do card 3.13, e o que mudou no método está no §6.

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
negócio custam o que o dimensionamento diz.

**Uma premissa a menos (02/09/2026, resposta de Irineu):** ~~nenhuma janela do calendário escolar
proíbe a virada na data resultante~~ — **não há janela de calendário escolar; a virada pode cair em
qualquer data.** Isso importa mais do que parece: a data do go-live passa a ser determinada só por
esforço e latência, sem precisar esperar início de semestre ou fim de bimestre. Não há o que
perguntar sobre isso nas próximas rodadas.

## 6. Segunda rodada (03/09/2026, card 4.9) — o que mudou no método

Os **números** desta e das próximas rodadas moram na subpágina Notion "Estimativa de entrega" do
card 3.13, nunca aqui. O que fica registrado neste documento são as mudanças de **método** — método
que muda sem registro é método que ninguém consegue repetir.

**(a) O P80 deixa de ser metade do P50 e passa a ser P50 ÷ 1,5.** O §3 dizia que a metade não era
pessimismo decorativo: era o preço de as telas de negócio não estarem medidas. Quatro telas de
negócio foram medidas (cards 4.4, 4.5, 4.6 e 4.7) e saíram **no tamanho atribuído**, com duas telas
`GG` entregues no mesmo dia. Retirar do P80 um risco que foi medido e não apareceu é executar o
método, não redecidi-lo — o próprio §4 previa a banda encolher aqui. O ÷ 1,5 que sobra cobre o que
segue sem medição nenhuma: a fase 09 (importação e extração, dois `GG` de natureza inédita no
projeto) e a fase 10 inteira.

**(b) A velocidade publicada passa a ser líquida de escopo novo.** A premissa "escopo do board
congelado" era falsa, e agora está medida: **25 pontos de cards que não existiam quando o board foi
criado, em 6 dias — ~4,2 pts/dia-pleno**. Em vez de manter no papel uma premissa que se sabe falsa,
o desconto entra na velocidade: bruta menos taxa de descoberta. Nas próximas rodadas, recalcular a
taxa somando os cards de `Ordem` decimal criados desde a rodada anterior.

**(c) Fica declarada a convenção de denominador**, que estava implícita e é o que mais facilmente se
perde entre sessões: o divisor é o **dia de calendário em que houve entrega**, contado como um
dia-pleno. Mudar a régua no meio da série destrói a comparabilidade, que é o único ativo do método.

**(d) O passo 2 tem um viés a vigiar, e ele apareceu já na primeira vez que o passo foi executado.**
Das oito mudanças de tamanho desta rodada (saldo +9 pontos), o único grupo redimensionado **para
cima por medição direta** foi o dos seis cards de recalibração — justamente os que esta sessão
executou, e que o card 3.13 tinha criado como `P`. Todos os outros foram julgados por analogia, que
é sistematicamente mais gentil: telas e schemas "se sustentaram". Pode ser verdade, e as telas de
fato saíram no tamanho atribuído; mas **um passo 2 cujo saldo dá perto de zero merece desconfiança
— ou o board está bem dimensionado, ou o passo não foi feito de verdade.** Nas próximas rodadas,
começar o passo 2 pelos cards da fase que acabou de fechar, que são os únicos com medição direta.

**Fato estrutural registrado nesta rodada, e que muda onde se ganha a data:** com o esforço restante
caindo de 225 para 177 pontos e a velocidade subindo de 18 para 26, **a latência passou o esforço**
— no P50 são ~16 dias corridos de esforço contra ~19 de latência. Subir a capacidade semanal de 3,0
para 7,0 dias-plenos (o ritmo de fato observado de 29/08 a 03/09) antecipa o P50 em apenas 9 dias.
Daqui em diante a data se ganha encurtando marco de validação, revisão do pedagógico e treinamento
— não codando mais rápido.
