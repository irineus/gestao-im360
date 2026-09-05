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

⚠️ **Nenhum destes blocos foi medido até o fim.** Dois estão abertos: o do card 4.8 desde
03/09/2026 e o do card 6.9 desde 04/09/2026 — ver §4. **Ao fechar cada um, anotar aqui os dias
corridos que ele de fato consumiu**, da abertura ao aceite; a coluna "Dias" acima é declaração, não
medição, e desde 03/09/2026 ela pesa mais na data do que toda a velocidade de desenvolvimento junta.

⚠️ **Os blocos 4.8 e 6.9 são seriais, não paralelos** (medido em 04/09/2026, card 6.10): o roteiro
do M2 começa em "matricular num combo", e o combo é entregável do roteiro do M1. A soma dos dois na
tabela acima está certa; o que **não** se pode assumir é que atraso no 4.8 seja absorvido pelo 6.9.

### Como sair de P50 e P80

- **P50** = velocidade central medida (líquida de escopo novo — ver §6b), latência parcialmente
  paralela.
- **P80** = velocidade do P50 **dividida por 1,5**, latência integral. O divisor não é pessimismo
  decorativo: ele precifica o que ainda **não foi medido**, e por isso encolhe quando algo passa a
  ser medido. Era **2** enquanto as telas de negócio eram o grande vão; virou **1,5** em 03/09/2026,
  quando quatro telas de negócio saíram no tamanho atribuído (§6a). O que o 1,5 ainda cobre é a fase
  09 e a fase 10, sem medição nenhuma. **Rever o divisor a cada rodada, para cima ou para baixo,
  conforme o que ainda estiver por medir** — divisor que não se mexe vira superstição. *Revisto e
  mantido em 1,5 em 04/09/2026 (card 5.10), com o motivo em §7(b): a fase 05 não encostou em nada do
  que o divisor cobre. Revisto e mantido de novo em 04/09/2026 (card 6.10), §8(f): a fase 06 mediu
  `View` pela primeira vez, e `View` não é o que o divisor precifica.*

⚠️ **A escolha entre mediana e líquida tem regra, e ela é `min` das duas** (explicitada em
04/09/2026, card 6.10, §8(b)). As rodadas de 03/09 e 04/09 adotaram a mediana porque ela estava
**abaixo** da líquida; quando a mediana fica acima, adotá-la contraria o §6(b), que manda publicar
velocidade líquida de escopo novo. **P50 = min(mediana, líquida)** reproduz as duas escolhas
anteriores sem redecidir nada.

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

⚠️ **A maior incerteza continua sendo a tabela de blocos de latência do §3** — os 31 dias corridos
até o go-live. Ela foi escrita de uma vez, por analogia, e **nunca foi medida até o fim**: nenhum
marco de validação, revisão de terceiro ou treinamento **terminou** ainda. Desde 03/09/2026 a
latência é maior que o esforço no P50; desde 04/09/2026 ela é **a maior parte dele** — ou seja, **o
número menos confiável do modelo é o que mais pesa na data**, e a distância entre os dois só cresce.

**A primeira medição está em curso e já diz alguma coisa (04/09/2026, card 5.10).** O marco 4.8
abriu em 03/09/2026 com bloco declarado de **4 dias** e, em 04/09, **continua aberto** — duas das
pré-condições que faltam são de Irineu (convidar três usuários em homologação e fazer os cadastros
do roteiro antes dos quatro logins, pendência 9.14) e a terceira é a sessão com a secretaria.
Ainda não é estouro: 2 dos 4 dias corridos. É cedo para corrigir o bloco, e cedo **não é** motivo
para não anotar — o que esta rodada registra é o relógio ligado e o ponto em que ele parou.

**Em 04/09/2026 (card 6.10) abriu o segundo, e o relógio do primeiro não andou.** A quarta rodada
caiu no **mesmo dia de calendário** da terceira, então o 4.8 segue em 2 de 4 dias e o 6.9 nasceu em
0 de 4. Nenhuma medição nova de latência — e é isso que a rodada tem a dizer sobre o assunto: **o
número que mais pesa na data continua sendo o único que ninguém conseguiu medir ainda.** No P50 de
hoje a latência responde por **79%** da data (18,6 dias corridos contra 4,9 de esforço).

⚠️ **A segunda maior incerteza mudou de lugar nesta rodada: é a taxa de descoberta de escopo.** O
§7(c) a promoveu a parâmetro depois de duas medições próximas (4,2 e 4,6). A terceira deu **7,4** —
60% acima. Ela continua sendo o único mecanismo do modelo que precifica card que ainda não existe,
mas deixou de ser um número estável, e a premissa que a chamava de "confirmada" caiu (§8(c)).

O que a mesma medição já confirmou, e isso vale mais: **a latência do 4.8 correu em paralelo com o
desenvolvimento**, que é exatamente o que a premissa dos 60% do §3 assume. Enquanto o marco esperava
gente, a cadeia entregou os cards 5.6 a 5.9. A premissa da sobreposição está certa; é a **duração**
do bloco que segue sem resposta.

Ao fechar o 4.8 — e o 6.9, o 8.8, o 9.3, o 9.4, o 9.6 e o 9.7 — anotar **quantos dias corridos ele
de fato consumiu**, contados da abertura ao aceite, e comparar com o bloco declarado. Sem essa
anotação, cada rodada recalibra a velocidade com precisão crescente e deixa intacta a metade da
conta que hoje decide a data.

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

## 7. Terceira rodada (04/09/2026, card 5.10) — o que mudou no método

Os **números** continuam morando na subpágina Notion "Estimativa de entrega" do card 3.13. Aqui, só
o que mudou no método.

**(a) Nada mudou no método, e isso é o registro.** Nenhuma das três escolhas do §1, nenhuma das três
mudanças do §6 e nenhum parâmetro do §3 precisou ser tocado nesta rodada. É a primeira rodada em que
a receita foi apenas **executada** — e ela reproduziu, ponto a ponto, a série da rodada anterior: os
pontos por dia de 29/08 a 02/09 saíram idênticos aos publicados em 03/09 (5, 11, 31, 75, 54), o que
é a prova de que a régua não se mexeu entre sessões. Um método que dá números diferentes para os
mesmos dias não mede nada; este deu os mesmos.

**(b) O divisor do P80 fica em 1,5, e o motivo está escrito.** O §3 manda revê-lo a cada rodada,
"para cima ou para baixo, conforme o que ainda estiver por medir" — e **o que ele cobre não foi
medido nesta rodada**. A fase 05 exercitou `Schema/migração`, `Função/regra` e `Tela`, os três já
medidos na fase 04; o que o 1,5 precifica é a fase 09 (`9.1` e `9.2`, dois `GG` de natureza inédita)
e a fase 10 inteira, e nenhuma das duas encostou em nada. Baixar o divisor agora seria retirar do
preço um risco que **não foi testado**, e não um risco que foi medido e não apareceu — que foi o que
autorizou a queda de 2 para 1,5 em 03/09. ⚠️ O divisor **não** é o lugar da incerteza de latência:
essa já entra no P80 de outra forma, integral e sem sobreposição.

**(c) A taxa de descoberta de escopo se confirmou, e isso promove o §6(b) de conserto a instrumento.**
Ela foi introduzida em 03/09 medindo ~4,2 pts/dia-pleno; medida de novo em 04/09 sobre uma janela um
dia maior, deu **~4,6**. Duas medições próximas em janelas diferentes é o que separa um número de um
palpite — a taxa passa a ser tratada como parâmetro do modelo, e não como correção pontual. Regra
que fica: contam os cards de `Ordem` decimal criados desde a rodada anterior **mais** os cards
existentes cujo `Tamanho` subiu por descoberta (não por transferência documentada de escopo, que
apenas muda o ponto de lugar).

**(d) Cards de fase 11 são escopo novo, mas não entram na taxa.** Nasceram dois nesta janela (11.5,
revisar custos do Supabase; 11.6, falha do vigia para o Sentry). A fase 11 é backlog aberto e nunca
entrou em estimativa — somá-los à taxa faria a velocidade do go-live pagar por trabalho que não está
no caminho do go-live. Ficam registrados à parte, e a regra vale para as próximas rodadas.

**(e) O passo 2 saiu com saldo +2 e cinco mudanças, três para cima.** O §6(d) manda desconfiar de um
saldo perto de zero — "ou o board está bem dimensionado, ou o passo não foi feito de verdade". Este
saldo está perto de zero **por compensação**, não por imobilidade: +3 no `6.1`, +3 no `6.3` e +2 no
`7.1`, contra −3 no `6.7` e −3 no `8.7`. E as duas famílias têm origens diferentes, o que é o que
torna a compensação legível: as **subidas** vêm de escopo transferido por documento (pendência 9.11
→ `6.1`; a suíte de concorrência que a própria nota do `6.3` já exigia; pendência 9.17 → `7.1`), e
as **descidas** vêm de reúso medido (tela que se acrescenta a uma página que já existe — o mesmo
argumento que levou `6.6` de `G` a `M` na rodada anterior). ⚠️ O viés do §6(d) **continua de pé**:
as descidas seguem sendo julgadas por analogia, e analogia é gentil. A contraprova disponível é
fraca de propósito e vale dizer qual é: a fase 05 inteira saiu **no tamanho atribuído**, incluindo o
`5.7` que a rodada anterior tinha subido de `G` para `GG`.

## 8. Quarta rodada (04/09/2026, card 6.10) — o que mudou no método

Os **números** continuam morando na subpágina Notion "Estimativa de entrega" do card 3.13. Aqui, só
o que mudou no método.

**(a) A escolha da velocidade deixou de mover a data, e este é o resultado principal da rodada.**
Três velocidades defensáveis saíram da mesma medição — bruta **46,1**, líquida **38,7**, mediana
**54** — e as três dão o mesmo P50 de go-live com **um dia** de diferença (26 ou 27/09/2026). O
motivo é aritmético e não vai se desfazer: restam **82 pontos de esforço**, que a qualquer dessas
velocidades cabem em ~5 dias corridos, contra **18,6 dias de latência** no P50. **Consequência para
as próximas rodadas: o tempo da sessão vai para os blocos de latência do §3, não para a terceira
casa da velocidade.** A receita do §3 não muda; muda onde vale a pena gastar a rodada.

**(b) A regra de desempate entre mediana e líquida fica explícita: adota-se a MENOR das duas.**
Estava implícita e ia se perder. As rodadas de 03/09 e 04/09 adotaram a mediana dizendo "abaixo da
líquida, pela mesma razão da rodada anterior" — o que funcionou porque a mediana estava **abaixo**.
Nesta rodada a mediana (54) ficou **acima** da líquida (38,7), porque o dia 04/09 entrou parcial na
rodada anterior (18 pontos) e fechado nesta (85). Adotá-la contrariaria o §6(b), que manda publicar
velocidade **líquida de escopo novo**. `P50 = min(mediana, líquida)` reproduz as duas escolhas
anteriores e resolve esta — não é método novo, é o método escrito.

**(c) A taxa de descoberta de escopo NÃO é estável, e a premissa que a dava por confirmada cai.**
Medida em 4,2 (03/09, janela de 6 dias) e 4,6 (04/09, 7 dias), o §7(c) a promoveu a parâmetro. A
terceira medição, na mesma janela de 7 dias com o último dia fechado, deu **7,4** — 52 pontos
cumulativos de escopo que não existia. A causa é legível e não é ruído: em 04/09 nasceram **20
pontos** de cards novos (`5.11`, correções da revisão das telas da fase 05, `GG`; e os quatro cards
de enxugamento `6.1,5`, `6.2,5`, `6.2,6`, `6.2,7`, `M` cada). Ela **continua** sendo descontada da
velocidade — é o único lugar do modelo onde card inexistente tem preço —, mas passa a ser publicada
com a faixa medida (4,2–7,4), e não como um número assentado.

**(d) O viés do §6(d) deixou de ser suspeita: uma descida da rodada anterior foi REFUTADA por
documento.** O `8.7` (Dashboard completo) foi baixado de `GG` para `G` em 04/09 com o argumento de
que "o card `5.9` entregou o Dashboard v1 — a página, o shell, a grade". No **mesmo dia**, a sessão
do `5.9` escreveu em `docs/views-leitura.md` §8: *"As três views desta seção são do card 8.7, e o
5.9 não tocou em nenhuma"* — a v1 saiu **sem migração**, e alunos por método, conclusões por
semestre e tipos por bloco "continuam integralmente no 8.7". A descida por analogia custou 3 pontos
em um card, e esta rodada os devolve. **Regra que fica: descida por reúso só vale quando o card que
"já construiu" tiver entregue também as views e as migrações, não só a página.** É o teste que o
`6.7` passou (a tela de Materiais existia inteira desde o `4.4`) e que o `8.7` não passava.

**(e) O passo 2 saiu com saldo +1 e, pela primeira vez, com as DUAS direções apoiadas em documento.**
O §6(d) manda desconfiar de saldo perto de zero. Este está perto de zero por compensação — `8.7`
`G` → `GG` (+3) pelo §8(d) acima, e `8.2` `M` → `P` (−2) —, mas a descida não é analogia: o card
`6.4` fechou em 04/09 a reserva da coluna `qtd_projetada` com o **teste `095`**, que assere a posição
da coluna pelo catálogo e foi visto vermelho recriando a view com a coluna no fim. Com isso o `8.2`
deixa de ser "evoluir a view" e passa a ser um `create or replace` de duas expressões, com o SQL já
escrito em `docs/views-leitura.md` §6.2, mais a coluna e o `calculado_em` numa tela de Compras que o
`6.8` já entregou. Descida apoiada em asserção vermelha é de outra natureza que descida apoiada em
semelhança.

**(f) `View` foi medido pela primeira vez e sai do modelo; `Marco/validação` segue com zero
medições.** O `6.4` era o único `View` já executado e saiu **no tamanho atribuído** (`G`); o único
que resta, o `8.2`, acabou de cair para `P`. O tipo deixa de ser fonte de incerteza. O divisor do
P80 **fica em 1,5** pelo mesmo teste do §7(b): o que ele precifica é a fase 09 (`9.1` e `9.2`) e a
fase 10, e a fase 06 não encostou em nenhuma das duas — `View` não é o que ele cobre. Já
`Marco/validação` é o tipo que mais pesa na data e **nunca teve um card fechado**: os três marcos
(`4.8`, `6.9`, `8.8`) valem 12 dos 31 dias de latência e continuam sendo declaração.
