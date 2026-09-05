# Extração da planilha — card 9.2

O produtor do arquivo que o importador do card 9.1 consome: o que sai de
`Gestão Interativo.xlsx`, o **relatório de inconsistências** que só a planilha
responde, e as quatro abas que **não foram mapeadas** e por que isso está escrito em
vez de escondido.

Fonte deste documento: `docs/plano-projeto-sistema.md` §8 (o mapeamento fonte →
destino e as limpezas), `docs/analise-planilha-entendimento.md` (as posições, lidas
célula a célula no snapshot de 29/08/2026), `docs/importacao.md` §3 (o contrato do
arquivo) e `docs/estrategia-testes.md` §13. O código é `extracao/`; a suíte é
`extracao/test/`, com **59 asserções**, e roda no job `extração` do `testes.yml`.

**Este script não escreve no banco.** Ele lê a planilha e escreve dois arquivos. A
única porta pela qual dado da planilha entra no sistema é a tela 13 (card 9.1,
decisão de 02/09/2026) — o que aqui se produz é o que alguém sobe lá.

---

## 1. O que ele produz

```
node extracao/extrair.mjs "Gestão Interativo.xlsx" --snapshot 2026-08-29 --saida saida/
```

- `saida/importacao-2026-08-29.json` — o arquivo do §3 de `docs/importacao.md`;
- `saida/inconsistencias-2026-08-29.csv` — o relatório que o card 9.3 revisa,
  separador `;` e BOM, que é o que o Excel em português espera (a mesma escolha do
  "Baixar relatório" da tela 13).

Sai **1** quando há ERRO no relatório. Não é rigor: o dry-run do card 9.4 não deve
começar por um arquivo que já se sabe incompleto, e script que sai 0 com erro no
relatório é script cujo relatório ninguém abre.

`--snapshot` é **obrigatório e não tem default de "hoje"**. A data do snapshot decide
metade do relatório (previsão vencida, ano do `(dd/mm)`), e um default faria a mesma
planilha produzir arquivos diferentes conforme o dia da extração — é a razão pela
qual o V12 do importador compara com o snapshot e não com hoje. O card 9.4 manda
registrar a data de cada rodada pelo mesmo motivo.

---

## 2. Três decisões de execução

### 2.1 JSON, e não "CSVs normalizados"

O plano §8 escreveu CSV em 30/08/2026, quando a carga ainda seria script + `psql`.
O card 9.1 já mudou isso em 06/09/2026 e o contrato está no §3 dele: dezoito
entidades em CSV são dezoito arquivos, e CSV não carrega tipo. Este card só cumpre
o contrato.

### 2.2 Node, e não Python — a divergência com a nota do card

A nota manda partir do protótipo de `docs/script-extracao-planilha.md`, que é
Python + `openpyxl`. **O mapa de colunas foi portado sem uma mudança** — é a parte
valiosa do protótipo, e é o que custou dois dias de leitura da planilha em
29–30/08/2026. A linguagem mudou, e por três razões medidas:

1. **Nenhuma ferramenta deste repositório tem dependência de terceiro.**
   `worker-vigia`, `portao-migracoes`, o guarda de destrutivos e a lógica das Edge
   Functions rodam com `node --test` e zero `npm install`. Python traria um segundo
   toolchain no CI (`setup-python` + `pip install openpyxl`) para um script só.
2. **Com `openpyxl`, a camada que abre arquivo ficaria fora do CI.** A planilha real
   não está no repositório, e instalar a dependência só para não ter o que ler é
   pagar duas vezes por nada. Em Node, escrever um `.xlsx` mínimo é ~120 linhas de
   ZIP — então a suíte constrói um arquivo de verdade e **mede o leitor**. Duas das
   seis contraprovas do §5 só existem por causa disso.
3. **A cadeia de execução não roda Python** (`.claude/settings.json` não o libera), e
   um entregável que a sessão não consegue exercitar é um entregável entregue no
   escuro.

Custo aceito: um leitor de `.xlsx` escrito à mão, com dois limites declarados —
sem ZIP64 e sem o sistema de datas 1904 do Excel para Mac. O segundo **recusa o
arquivo** em vez de converter errado: com 1904, toda data sairia quatro anos
adiantada e a conferência do 9.4 bateria os totais sem bater as datas.

### 2.3 A separação em três camadas é o que faz a suíte existir

| Camada | Arquivo | Regra |
|---|---|---|
| Leitura | `xlsx.mjs` | a única que abre arquivo; **não decide nada** |
| Posições | `layout.mjs` | todo número mágico mora aqui, e em nenhum outro lugar |
| Decisão | `transformacao.mjs` | puro: recebe linhas, devolve entidades e ocorrências |
| Relatório | `relatorio.mjs` | severidade, ordem e CSV |

A transformação não abre arquivo, não descompacta nada e não olha o relógio. É por
isso que ela é exercitada por uma planilha em memória e que o extrator é
determinístico — as duas coisas pela mesma decisão.

---

## 3. O mapeamento, e as quatro lacunas

### 3.1 O que está mapeado

| Aba | Entidades | Limpezas aplicadas |
|---|---|---|
| `Ger. Apost`, `Apost. Inglês`, `Apost. Modular` | `material` | descarta MSE (encerrado em 31/08/2026), "FIM" e "Não recebeu"; código único **por método** |
| `Ger. Apost` (blocos SAÍDAS/ENTRADAS) | `movimento_estoque` | saída sem aluno vira `AJUSTE`; sinal pelo tipo |
| `Gerência`, `Ger. Inglês` | `aluno`, `aluno_material` | descarta MACRO/Fake 02/BALANÇO; status desconhecido sai em branco |
| `Ger. Modular` | `aluno`, `curso` | é a fonte oficial dos alunos (resposta 9); grafia duplicada resolvida |
| `Segunda`…`Sábado` | `professor`, `sala`, `bloco_horario`, `bloco_aluno` | "R" → REP; `(dd/mm)` → NOVO + data; código divergente resolvido por nome |

### 3.2 O que NÃO está, e a diferença entre ausente e vazio

Quatro famílias de aba nunca tiveram as colunas lidas — a análise de 29–30/08/2026
mapeou as de cima, e a planilha **não está neste repositório** para mapear as
outras agora:

| Aba | Entidades que ela alimentaria |
|---|---|
| `Base Modular` | `curso_material`, `modulo` |
| abas por curso (Massagem, Manicure, Chef+Panificação, Combo Beleza, Violão, Pizzaiolo, Eletricista, Corte e Costura, Depilação) | `turma_modular`, `turma_modular_modulo`, `turma_modular_aluno` |
| `Pedidos` | `material.estoque_minimo`, `material.categoria` |
| `PCS` | `sala` (a real), `pc`, `pc_manutencao` |

⚠️ **Essas entidades ficam FORA do arquivo, e não vazias.** Ausente é "não sei";
`[]` é "não há". Emitir `[]` faria a conferência do card 9.4 comparar contra um
buraco sem perceber — que é a mesma classe de defeito do critério 1 do M1 e do
roteiro sem ator do M2. Cada uma vira um ERRO `ABA_NAO_MAPEADA` no relatório.

**Fechar a lacuna é de minutos, com a planilha aberta ao lado:**

```
node extracao/extrair.mjs "Gestão Interativo.xlsx" --mapear
```

imprime as primeiras linhas de cada aba não mapeada com a letra e o índice de cada
coluna. Preencher `extracao/layout.mjs` e tirar a entrada de `ABAS_NAO_MAPEADAS` é
o passo — o resto do código não muda de forma. Isso é trabalho do card **9.4**, que
é onde a planilha e a pessoa que a conhece estão na mesma sala.

### 3.3 O que fica de fora e NÃO é lacuna

- **`combo` e `combo_curso`** — a planilha não cadastra combo (resposta 3 da
  análise, 30/08/2026); a hierarquia combo → curso → material é do sistema novo.
  Inventá-la aqui seria escrever dado que ninguém digitou. Consequência: toda linha
  de trilha sai com `origem: "MANUAL"`, e não `COMBO` — marcar COMBO faria
  `tg_aluno_trilha_inicial` disputar a trilha com o arquivo.
- **`certificado_checklist`** — o card 8.3 decidiu no comentário da própria tabela,
  e o card 9.1 registrou em `docs/importacao.md` §2.2. Está contra a linha
  "Certificados" do plano §8, de propósito.
- **Credenciais de PC** — nunca, em nenhum formato (card 2.9 §1.5).
- **`pendencia`** — nasce da rotina diária no dia seguinte à carga.
- **A flag CONFER. da `Gerência`** — a coluna `aluno.conferido` existe no DDL e
  **não está no contrato do §3**; carregá-la em `observacoes` poluiria um campo de
  texto livre com um booleano. Fica de fora, e está dito aqui.

---

## 4. O relatório: as verificações que só a planilha responde

Duas severidades. **ERRO** é o que deixaria o arquivo errado ou incompleto; **AVISO**
é o que uma pessoa precisa olhar, e é a lista do card 9.3.

| Código | Severidade | O que é |
|---|---|---|
| `ABA_NAO_MAPEADA` | ERRO | §3.2 |
| `ABA_AUSENTE` | ERRO | aba que o mapa espera e a planilha não tem |
| `MATERIAL_DUPLICADO` / `ALUNO_DUPLICADO` | ERRO | mesmo código duas vezes na fonte |
| `MOVIMENTO_ILEGIVEL` / `MOVIMENTO_SEM_MATERIAL` | ERRO | linha de estoque que não converte, ou que aponta para material descartado |
| `MOVIMENTO_FORA_DE_GER_APOST` | ERRO | §4.1 |
| `TRILHA_SEM_MATERIAL` | ERRO | trilha apontando para código fora do catálogo |
| `HORARIO_ILEGIVEL` / `BLOCO_DUPLICADO` | ERRO | cabeçalho de bloco sem horário, ou dois blocos no mesmo horário |
| `METODO_DIVERGENTE` | ERRO | aluno de um método sentado em bloco de outro |
| `MATERIAL_DESCARTADO` / `ALUNO_DESCARTADO` | AVISO | MSE, FIM, MACRO, Fake 02 — o que foi jogado fora |
| `CODIGO_DIVERGENTE` | AVISO | §4.2 |
| `TURMA_SEM_CADASTRO` | AVISO | código na turma sem aluno correspondente |
| `ALUNO_SEM_TURMA` | AVISO | ATIVO/ACELERAR fora de bloco (23 no snapshot de 29/08) |
| `MULTI_BLOCO` | AVISO | mesmo aluno em dois blocos — aceleração, ou duplicidade |
| `PREVISAO_ATIPICA` | AVISO | 2023, 2050, ou vencida para quem está em turma |
| `STATUS_DESCONHECIDO` | AVISO | "Faltante" e afins: sai em branco, não traduzido |
| `GRAFIA_DUPLICADA` | AVISO | §4.3 |
| `TIPO_CORRIGIDO` / `TIPO_DESCONHECIDO` | AVISO | "R" lido como REP; o resto vira PRE |
| `NOVO_SEM_DATA` / `DATA_NO_NOME_IGNORADA` | AVISO | o `(dd/mm)` e a exigência do DDL |
| `SAIDA_SEM_ALUNO` | AVISO | virou AJUSTE |
| `ENTREGA_SEM_SAIDA` / `SAIDA_SEM_ENTREGA` / `TRILHA_SEM_DATA` | AVISO | §4.4 |
| `SALA_PRESUMIDA` / `CATEGORIA_PRESUMIDA` / `DATA_INICIO_AUSENTE` | AVISO | o que o extrator preencheu por não ter fonte |
| `TRILHA_MATERIAL_REPETIDO` / `DATA_ILEGIVEL` | AVISO | célula que se contradiz |

⚠️ **Isto não substitui as dezesseis verificações do importador**, e nem elas a
isto. As de lá conferem o arquivo contra si mesmo e contra o banco; as daqui
conferem a planilha — que o arquivo já não carrega. As duas listas se encontram no
dry-run do 9.4.

### 4.1 A premissa do movimento é conferida, não assumida

O plano §8 diz que o movimento de estoque está em `Ger. Apost`, e a contagem da
análise concorda (234 saídas, 110 entradas). Se um dia isso deixar de valer, o
estoque de Inglês e Modular sairia **vazio e sem erro nenhum** — então o extrator
varre as colunas de SAÍDAS/ENTRADAS das outras duas abas de catálogo só para
denunciar a premissa quebrada.

### 4.2 Código divergente resolve-se pelo nome, e só quando há um só

A turma é digitada à mão, sem fórmula ligando à `Gerência` (análise §2): o código é
a parte frágil e o nome é a confiável. Foi assim com Afonso Henrique (4433 × 3605) e
João Pedro (3527 × 4400). Quando o código da turma não existe no cadastro e o nome
bate com **exatamente um** aluno, vale o do cadastro e a troca vira linha do
relatório. Com dois homônimos ninguém decide sozinho: sai AVISO e a alocação é
descartada, para o card 9.3 resolver.

### 4.3 Grafia duplicada: vence a mais frequente

⚠️ **A primeira versão desempatava por ordem alfabética e o teste a derrubou.** Em
ordem de code unit, `"Massagem Terapeutica"` vem **antes** de `"Massagem
Terapêutica"` — o vencedor seria sempre o sem acento, e a escola inteira entraria
com o typo, com o card 9.3 recebendo a correção aplicada ao contrário. Hoje vence a
grafia **mais frequente**, e a primeira vista no desempate; o relatório diz quantas
vezes cada uma apareceu.

### 4.4 A trilha ganha data, e é isso que o card 9.5 vai calibrar

A entrega hoje exige **dois** lançamentos manuais — a saída no estoque e o
"Entregue = SIM" na trilha (resposta 10 da análise) — e nada garante que os dois
aconteçam. O extrator cruza os dois e faz duas coisas com o resultado:

- lista a divergência dos dois lados (`ENTREGA_SEM_SAIDA`, `SAIDA_SEM_ENTREGA`), que
  é o que o plano §8 manda listar e o que o V13 do importador pergunta depois;
- **preenche `aluno_material.data_entrega` a partir da saída**. A trilha só diz
  SIM/NÃO; a data só existe nas SAÍDAS. Sem essa junção o histórico entra mudo, e o
  card 9.5 calibraria `ritmo_padrao_dias_*` sobre uma trilha sem uma única data.

Como só o Interativo tem movimento, o Inglês e o Modular entram entregues **sem**
`data_entrega`, e isso sai como um AVISO agregado por método (`TRILHA_SEM_DATA`) —
uma linha, não setenta. O 9.5 precisa saber disso antes de olhar a mediana.

---

## 5. O que foi medido

**Seis contraprovas foram vistas vermelhas** em 06/09/2026, cada uma sabotando uma
regra e derrubando a suíte:

| Sabotagem | Reprova |
|---|---|
| chave do movimento sem o ordinal | 2 asserções — as duas saídas idênticas do mesmo dia colidem |
| grafia duplicada por ordem alfabética | 1 — o typo vence |
| saída sem aluno continua `SAIDA` | 2 |
| código divergente não resolvido por nome | 4 |
| linha vazia do XML não reposta pelo leitor | 7 — tudo desloca uma linha |
| formato customizado sem limpar o que está entre aspas | 1 |

⚠️ **E uma delas PASSOU VERDE na primeira tentativa**, que é o achado mais útil do
card — a mesma família do V10 do 9.1 e da sabotagem do `mes` no 8.5. A do formato
customizado usava `#,##0.00 "kg"`: limpar ou não o que está entre aspas dá o **mesmo
resultado** quando o literal não tem `d`, `m` nem `y`, então a asserção não media
nada. Trocado para `"dias"`, uma varredura que não limpe as aspas vê o `d`, decide
que a célula é data e transforma 7,5 em 1900-01-06 — e aí a sabotagem ficou
vermelha.

**Dois defeitos que a própria suíte pegou antes do PR:**

- **o desempate alfabético da grafia** (§4.3), que fazia o sem acento vencer sempre;
- **`Date.parse` não serve de validador de data**: o V8 aceita `2026-02-30` e rola
  para 2 de março, então `--snapshot 2026-02-30` passava e o extrator rodava com
  outro dia — justamente o argumento que decide metade do relatório. A validação
  passou a fazer a volta e comparar.

---

## 6. Limites assumidos

- **As quatro abas do §3.2 não estão mapeadas.** É a lacuna maior do card e está
  declarada em três lugares: no `layout.mjs`, no relatório (ERRO) e aqui.
- **A escala não foi medida contra a planilha real** — ela não está no repositório.
  O leitor carrega o arquivo inteiro na memória; um snapshot da escola tem alguns
  milhares de linhas e cabe bem.
- **Fórmula não é lida**, só o valor calculado — a mesma escolha do `data_only=True`
  do protótipo. É o que fecha a porta para a aba `Pedidos`, cujos ajustes manuais
  moram **dentro** das fórmulas.
- **Nada aqui roda sozinho.** Sem rotina, sem gatilho, sem agendamento: a extração
  só acontece quando alguém a chama, e ela não fala com banco nenhum.
