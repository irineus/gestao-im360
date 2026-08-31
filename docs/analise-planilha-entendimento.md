# Análise da planilha "Gestão Interativo" — entendimento inicial

Data da análise: 29/08/2026. Arquivo: `Gestão Interativo.xlsx` (26 abas).

## 1. Visão geral

A planilha é o "sistema" de gestão pedagógica e de material didático de uma escola que opera três métodos de ensino:

| Método | Cadastro de alunos | Catálogo/estoque de apostilas | Turmas |
|---|---|---|---|
| Interativo (informática, design, programação, administrativo, kids) | `Gerência` (161 alunos; 117 ATIVO, 41 ACELERAR, 1 TRANCADO) | `Ger. Apost` (115 títulos) | Abas `Segunda`…`Sábado` |
| Inglês (4 livros: Check-In, Take Off, Inflight, Sky) | `Ger. Inglês` (71 alunos) | `Apost. Inglês` | Blocos específicos nas abas de dia (Quinta, Sexta 20h, Sábado manhã) |
| Modular (cursos profissionalizantes) | `Ger. Modular` (33 alunos) + uma aba por curso (Massagem, Manicure, Chef+Panificação, Combo Beleza, Violão, Pizzaiolo, Eletricista, Corte e Costura, Depilação) | `Apost. Modular` (21 títulos) + `Base Modular` (curso → livro → módulos) | Uma turma por curso (vagas fixas no Dashboard) |

Abas de apoio: `Dashboard` (painel consolidado), `Pedidos` (lista de compra por categoria), `Certificados` (checklist de formatura), `PCS` (manutenção e credenciais dos computadores do laboratório).

## 2. Modelo de dados implícito

**Aluno**: código numérico (parece vir de outro sistema — matrícula), nome, previsão de conclusão do curso, status (ATIVO, CANCELADO, ACELERAR, STANDBY, TRANCADO, FORMADO), flag "CONFER." (SIM/NÃO). No Modular há também o campo Curso.

**Apostila (livro)**: código, nome, estoque atual (= entradas − saídas), demanda, pedido (= demanda − estoque, se positivo). Catálogos separados por método, com códigos que se repetem entre métodos (código 1 = "Windows 11" no Interativo e "Inglês - Check-In" no Inglês).

**Trilha do aluno (currículo)**: em `Gerência` cada aluno tem até 17 posições "APOSTILA 01..17", cada uma com código, nome (lookup) e flag Entregue (SIM/NÃO). A maioria dos alunos tem 5 a 7 apostilas (85 alunos com 7). Além disso há "Livro Atual" e "Próximo Livro" (o valor especial "FIM" indica último livro).

**Movimentação de estoque** (`Ger. Apost`, blocos SAÍDAS e ENTRADAS): saída = data, apostila, qtd, código do aluno (234 registros); entrada = data, apostila, qtd (110 registros). O estoque é sempre calculado por diferença.

**Turma (Interativo/Inglês)**: aba por dia da semana, 6 blocos de horário (8h, 10h, 14h, 16h, 18h, 20h; sábado 8h, 10h, 13h30, 15h30), cada bloco com 10 linhas = 10 vagas, professor no cabeçalho (Claudir, Lindomar, Gilberto, Leonardo). Cada linha: código, nome, previsão de conclusão, tipo de presença (REM, PRE, REP, R, NOVO). Os dados dos alunos nas turmas são **digitados** (não há fórmula ligando à `Gerência`), então nome e previsão podem divergir.

**Modular por curso**: aba por curso com: livro atual + módulo atual + previsão; próximo livro; livros 01..05 com flag Entrega; módulos 01..11 com "Início" (SIM/NÃO) e previsão de conclusão. A lista de módulos válidos está em `Base Modular` e nas validações de dados de cada aba.

## 3. Regras de negócio observadas

1. **Demanda de apostila (Interativo)** = quantidade de alunos cujo "Próximo Livro" (`Gerência!H`) é aquele código. Pedido = demanda − estoque. Ou seja, a compra é dirigida pelo próximo livro de cada aluno, não pela previsão de conclusão do módulo.
2. **Inglês**: mesma lógica, com a diferença de que `Ger. Inglês` tem "Prev. Conclusão" do livro atual (coluna H), preenchida em ~40% dos alunos.
3. **Modular**: demanda = contagem do "Próximo Livro" nas abas por curso (coluna J). `Apost. Modular` aponta para as abas de curso, mas há inconsistências (por exemplo, o código 1 "Chef Profissional" busca em Chef+Panificação, mas o "FIM" busca em `Ger. Modular`). `Pizzaiolo` não tem alunos reais (linha de cabeçalho antigo).
4. **Vagas por turma**: 10 alunos por bloco (15 para Eletricista, 6 para Depilação no modular). Dashboard mostra vagas livres por dia/horário (`10 − COUNTA(bloco)`), lotação geral, e totais de alunos REM/PRE.
5. **Mapeamento de blocos para Inglês** está embutido nas fórmulas do Dashboard: Quinta (todos os 6 blocos) + Sexta 20h + Sábado 8h e 10h são Inglês; o restante é Interativo. Os 19 blocos do Interativo × 10 = 190 vagas; 8 blocos de Inglês × 10 = 80 vagas.
6. **Previsão de conclusão do curso** é digitada manualmente (não há fórmula). Há valores claramente atípicos (2023, 2050) e datas já vencidas para alunos ativos (formatação condicional marca `D < HOJE()`).
7. **Relatório por semestre**: Dashboard conta alunos com previsão de conclusão por semestre (1º sem 26 … 2º sem 28) por método/curso.
8. **"Último livro"**: contagem de alunos com "Próximo Livro" = FIM (alunos que estão no último livro — candidatos a certificado).
9. **Certificados**: checklist por aluno formando (fim do curso, pedagógico OK/PENDENTE, financeiro OK/PENDENTE, formatura SIM/NÃO, certificado PEDIDO/NÃO PEDIDO/ENTREGUE).
10. **Pedidos**: lista de compra agrupada por categoria (Informática, Design Gráfico, Kids, Programação, Administrativo, Personalizado, Inglês, Modular), com ajustes manuais somados à fórmula (ex.: `+5`, `+7`, `+1`).

## 4. Inconsistências / fragilidades observadas (motivam o novo sistema)

- Dados de aluno replicados em 3+ lugares (cadastro, turma, certificados) sem vínculo — 37 alunos aparecem em mais de um bloco de horário (provavelmente frequentam 2x/semana, mas pode ser duplicidade).
- 23 alunos ativos na `Gerência` não estão em nenhuma turma; 4 de Inglês idem.
- Alunos de `Ger. Modular` também estão nas abas por curso (dupla manutenção).
- Códigos de apostila reutilizados entre métodos.
- Fórmulas do Dashboard com referências "hard-coded" (ranges de colunas diferentes por curso, ex. Combo Beleza usa coluna P, Pizzaiolo coluna V).
- Ajustes manuais no `Pedidos` sem histórico.
- Credenciais em texto puro na aba `PCS`.

## 5. Dúvidas em aberto (a validar com o usuário)

Foram levantadas 13 dúvidas em 29/08/2026. Respostas recebidas até agora:

### Respondidas (30/08/2026)

**1. Código do aluno / origem do cadastro.** O código vem do SGF (Sistema de Gestão de Franquia), sistema proprietário **sem integração nativa** hoje. O novo sistema deve prever, para o futuro, o recebimento de dados do SGF de forma assíncrona (importação/sincronização eventual), mas nasce como fonte própria de cadastro, guardando o código SGF como referência externa.

**2. Previsão de conclusão do curso.** Não há regra de cálculo confiável — o campo é **informado manualmente pelo usuário** no novo sistema também.

**3. Estrutura curricular do Interativo.** Existe uma hierarquia que a planilha não cadastra, mas o sistema deve modelar e normalizar:
- **Combo** (curso contratado, ex.: "Secretariado Executivo") → composto por **cursos/áreas** (ex.: Informática, Gestão Financeira) → compostos por **módulos/apostilas** (ex.: "Excel 365 InterativoIM").
- O número de apostilas por aluno varia por combo (as 17 posições da planilha são apenas o limite físico da grade; não fixar em 17).
- A trilha do aluno deriva do combo contratado.

**4. Previsão de demanda de apostilas.** Confirmado que o sistema deve **projetar a necessidade de apostilas por período**. Pontos levantados pelo usuário:
- No Interativo, a única data concreta por livro é a **data de entrega** registrada nas SAÍDAS de `Ger. Apost`; a Prev. de Conclusão do curso é apenas indicativa, sem data rígida por livro.
- O que marca que um livro foi entregue é a flag **SIM** na aba `Gerência` (coluna "Entregue" da trilha).
- Implicação de projeto: a projeção por período precisará estimar o ritmo do aluno (ex.: a partir do histórico de datas de entrega dos livros anteriores) já que não existe data prevista por livro no Interativo.

**5. Alunos × turmas.** Aluno em dois horários na semana = aluno possivelmente **acelerando o curso** (coerente com o status ACELERAR). Regra confirmada: **todo aluno ATIVO ou ACELERAR deve estar alocado em pelo menos uma turma**; STANDBY e TRANCADO ficam fora de turma. Os 23 ativos sem turma encontrados na planilha são falhas de lançamento (faltou cadastrar na turma) — o novo sistema deve apontar essa inconsistência automaticamente (alerta/lista de pendências). Achados adicionais da conferência: dois alunos estavam em turma com código divergente do cadastro (Afonso Henrique Alves 4433 vs. 3605; João Pedro Ramos de Souza 3527 vs. 4400), e as linhas "MACRO" (1000) e "Fake 02" são registros técnicos da planilha, não alunos.

**6. Tipos de presença na turma.** REM = remoto, PRE = presencial, REP = reposição, NOVO = matrícula recente ainda não iniciada (a data entre parênteses no nome é o início previsto). O valor "R" foi lançado errado — deve ser lido como **REP**. O novo sistema restringe aos valores válidos (REM, PRE, REP, NOVO).

**7. Status.** ACELERAR = aluno em ritmo acelerado (frequenta 2x/semana). STANDBY = aluno ativo no SGF que **parou de comparecer**; se persistir, vira TRANCADO. Fluxo de status a modelar: ATIVO ⇄ ACELERAR; ATIVO/ACELERAR → STANDBY → TRANCADO; → CANCELADO; → FORMADO. Alerta útil: STANDBY prolongado.

**8. Vagas.** Capacidade de 10 por bloco é física: 10 PCs no laboratório (aba PCS). **Aluno remoto ocupa vaga.** Hoje não existem blocos paralelos de professor porque há um único laboratório de informática — o modelo deve permitir mais salas no futuro sem impor essa limitação em código.

**9. Modular.** `Ger. Modular` é a **fonte oficial** dos alunos; as abas por curso são apoio operacional. A turma do curso avança **em conjunto** pelos módulos — a previsão de conclusão por módulo pertence à turma, não ao aluno individual.

**10. Estoque × trilha.** Hoje a entrega da apostila exige dois lançamentos manuais (saída no estoque + "Entregue = SIM" na trilha). No novo sistema, o registro de entrega ao aluno deve ser **um único ato** que baixa o estoque e marca a trilha. ENTRADAS = recebimentos de pedidos de compra que entram no estoque — o sistema deve acompanhar o ciclo pedido → recebimento → estoque.

**11. Certificados.** O checklist deve ser **disparado automaticamente** quando o aluno chega ao último livro ("FIM"). O item "financeiro OK" é preenchido pelo perfil **monitor**.

**12. Usuários e plataforma.** Sistema **web**, com quatro perfis: **direção, pedagógico, secretaria e monitor**. Unidade única por enquanto, mas o modelo deve **prever multi-unidade** no futuro (ex.: entidades ligadas a uma unidade desde já).

**13. Escopo.** O cadastro e a manutenção dos **PCs permanece no escopo** — inclusive para derivar as vagas do laboratório. O catálogo **MSE é encerrado em 31/08/2026** e não entra no novo sistema (apenas os títulos InterativoIM e demais ativos).

### Perguntas complementares (respondidas em 30/08/2026)

**14. Vagas × manutenção de PCs.** PC em manutenção **reduz a capacidade** do bloco, salvo se outro PC for designado no lugar. Turmas já completas **não são reduzidas automaticamente**: o sistema emite alerta e bloqueia a admissão de novos alunos enquanto não houver capacidade.

**15. Estoque mínimo.** Cada apostila terá **estoque mínimo** configurável; o pedido sugerido considera demanda + estoque mínimo − estoque atual. Os ajustes manuais nas fórmulas de `Pedidos` representavam isso.

**16. Permissões.** As permissões de cada perfil (direção, pedagógico, secretaria, monitor) devem ser **configuráveis em uma interface de administração** (matriz perfil × permissão), não fixas em código.

**17. Migração.** Haverá **migração inicial** dos dados da planilha, como **etapa separada**, após a estrutura do sistema pronta. A limpeza (códigos divergentes, registros técnicos, catálogo MSE) faz parte da migração. Os dados continuarão mudando na planilha até a virada — o processo precisa ser reexecutável a partir de um snapshot recente.

**18. Tecnologia.** Web app **publicável nas lojas Google e Apple**, custo baixo (preferencialmente zero), login por e-mail/senha com perfis. Stack preferida pelo usuário, com familiaridade prévia: **Flutter/Dart + Supabase + Cloudflare**.

> Itens 1–18 respondidos. Levantamento de requisitos concluído em 30/08/2026. Próximo artefato: `claude/plano-projeto-sistema.md`.
