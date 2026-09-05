# Importação — card 9.1

Como a planilha entra no sistema: o **formato do arquivo**, as **dezesseis verificações** da
validação, o que a aplicação escreve e em que ordem, e as decisões que sustentam as três
propriedades exigidas pelo plano §8 — **reexecutável**, **auditável** e **ensaiada**.

Fonte deste documento: `docs/plano-projeto-sistema.md` §8 (o mapeamento fonte → destino),
`docs/wireframes.md` §16 (a tela 13), `docs/permissoes-matriz.md` §6 linha 13 e §7 item 4 (a rota),
`docs/estrategia-testes.md` §13 e §14. O código é
`supabase/migrations/20260906120000_importacao.sql`, `app/lib/importacao/` e
`app/lib/telas/importacao/`; a suíte é `supabase/tests/100_importacao.sql` (33 asserções) mais
`app/test/importacao_test.dart` e `app/test/tela_importacao_test.dart`.

**É a única porta pela qual dado da planilha entra** (decisão de 02/09/2026). Carga não é arquivo em
`supabase/migrations/`: migração vai a produção sozinha no merge em `main`, e o que esta tela faz é
operação de tempo de execução, disparada por uma pessoa, contra o ambiente em que essa pessoa está
logada. Até a virada (card 9.7) ela só é exercitada no projeto dev/homolog.

---

## 1. A ideia central

**A importação não reimplementa regra nenhuma.** Ela empurra as linhas para as tabelas de negócio,
sob RLS, e deixa os triggers que já existem decidirem — `fn_bloco_aluno_admissao` (capacidade,
método, aluno ativo), `fn_aluno_status_valida`, `fn_composicao_metodo_coerente`,
`tg_pc_manutencao_status`, `tg_pc_revalida_blocos`, `tg_aluno_trilha_inicial`. O que ela acrescenta é
o que faltava: a **transação** (tudo ou nada) e o **relatório**.

É o §4.1 do card 2.3 aplicado ao maior candidato a segunda implementação do projeto. Um importador
que conferisse capacidade por conta própria teria duas contas de vaga no sistema, e a que erra em
silêncio é sempre a segunda.

A validação não contradiz isso: ela confere **o arquivo contra si mesmo** (o aluno alocado consta
como ATIVO no mesmo arquivo? o material referenciado existe?) e contra o que já está no banco.
Nenhuma das dezesseis verificações decide regra de negócio — elas antecipam, todas de uma vez, o que
o banco recusaria uma a uma. É a diferença entre um relatório com quarenta linhas e quarenta uploads.

---

## 2. Decisões e divergências

### 2.1 O formato é JSON, não CSV

O plano §8 escreveu "CSVs normalizados" em 30/08/2026, quando a carga ainda seria um script na linha
de comando. Com a decisão de 02/09/2026 ela virou tela, e o formato mudou por três razões:

1. são **dezoito entidades** — em CSV, dezoito arquivos (ou um zip, que o navegador não abre sem
   dependência nova);
2. **CSV não carrega tipo**: `10` e `"10"` viram a mesma célula, e a conversão passa a ser
   adivinhação de quem lê;
3. o produtor do arquivo é **nosso** (card 9.2), então não há formato de terceiro a respeitar.

Consequência para o card 9.2: ele passa a gerar **um** arquivo JSON no formato do §3 abaixo. O
relatório de inconsistências que ele produz continua sendo dele — são as verificações que só a
planilha responde (grafias duplicadas, códigos divergentes resolvidos por nome).

### 2.2 O que NÃO se importa, e por quê

- **`certificado_checklist`** — contra a linha "Certificados → certificado_checklist" do plano §8.
  Quem decidiu foi o card 8.3, no comentário da própria tabela: *"NÃO se migra da planilha: a aba
  Certificados não guarda quem marcou nem quando, que é justamente o que esta tabela existe para
  guardar"*. Importar aquilo criaria quatro pares quem/quando nulos com cara de checklist trabalhado.
  O caminho certo existe e é a tela 9 (card 8.6), que abre o checklist à mão.
- **Credenciais de PC** — nunca, em nenhum formato (card 2.9 §1.5: as atuais estão queimadas).
- **`pendencia`** — pendência é anotação do sistema; as que valem nascem da rotina diária no dia
  seguinte à carga.
- **Status de aluno em linha que já existe** — ver §5.3.

### 2.3 O conjunto exato da rota (fechando o item 4 do §7 do card 2.4)

`admin.ler` **mais os quatorze códigos de escrita** dos domínios que o arquivo traz:
`materiais.criar`, `materiais.editar`, `alunos.criar`, `alunos.editar`, `alunos.editar_trilha`,
`salas.criar`, `salas.editar`, `salas.registrar_manutencao`, `professores.criar`, `turmas.criar`,
`turmas.alocar`, `estoque.lancar_saida`, `estoque.ajustar`, `compras.receber`.

Mora em **uma** função, `fn_importacao_conjunto()`, lida pelas políticas das três tabelas de
importação (via `fn_importacao_pode()`), pelo guarda das duas funções (via `fn_importacao_exigir()`)
e copiada em `app/lib/rotas/rotas.dart` — a cópia do app é conferida pelo `guardas_rota_test`.

Duas alternativas foram consideradas e recusadas:

- **um código novo (`admin.importar`)**: o catálogo iria a 51 e o critério 1 do marco 4.8 — que está
  aguardando gente com o número **50** escrito nele — reprovaria por uma mudança que não é do marco.
  E um código que só a direção tem, guardando uma tela que só a direção abre, não decide nada que
  `admin.ler` já não decida;
- **`security definer` nas funções**: seria BYPASSRLS sobre dezessete tabelas de negócio ao mesmo
  tempo, e o filtro de unidade passaria a ser responsabilidade do corpo em cada um dos dezoito
  blocos. Como `invoker`, quem importa escreve sob a própria RLS e cada política cobra o seu código.

`admin.ler` é o que faz a tela ser **da direção**: os quatorze de escrita a secretaria também tem
(§5 da matriz). Exigi-los no topo, com `fn_exige_permissao`, troca um `42501` cru na décima sétima
entidade por `SEM_PERMISSAO` nomeando o que falta — a mesma regra do card 6.5.

### 2.4 Três tabelas fora do DDL do card 2.1

`importacao` (o lote), `importacao_ocorrencia` (o relatório, que é o entregável "auditável") e
`importacao_referencia` (chave externa → linha criada, para o que não tem chave natural). O card 2.1
lista 33 tabelas e nenhuma de importação porque, em 31/08/2026, a carga ainda era script + `psql`.
Operação de tempo de execução deixa rastro em tabela.

Nenhuma das três tem `delete`, e só `importacao` tem `update`. Apagar o relatório é apagar a
explicação de como a escola entrou no sistema; apagar o mapa de chave externa faz a **próxima**
importação duplicar movimento de estoque, que é imutável.

---

## 3. O formato do arquivo (contrato com o card 9.2)

Um objeto JSON. Cada chave é uma entidade, cada valor é um array de objetos. Chave ausente = nada a
importar daquela entidade. `snapshot_em` no topo é opcional e serve de **sugestão** para o campo da
tela — quem responde pela data do snapshot é quem importa.

As **dezoito entidades, na ordem de aplicação** (que é a ordem de dependência):

| # | Entidade | Chave natural | Campos |
|---|---|---|---|
| 1 | `professor` | `nome` | `nome`*, `ativo` |
| 2 | `sala` | `nome` | `nome`*, `tipo`* (`LABORATORIO`\|`SALA_MODULAR`), `capacidade_nominal`*, `ativo` |
| 3 | `pc` | `identificador` | `identificador`*, `sala`*, `status` (`OPERACIONAL`\|`MANUTENCAO`\|`DESATIVADO`), `observacao` |
| 4 | `pc_manutencao` | `pc` + `data_inicio` | `pc`*, `tipo`, `data_inicio`, `data_fim`, `descricao` |
| 5 | `material` | `metodo` + `codigo` | `metodo`*, `codigo`*, `nome`*, `categoria`*, `estoque_minimo`, `ativo` |
| 6 | `curso` | `metodo` + `nome` | `metodo`*, `nome`*, `ativo` |
| 7 | `curso_material` | `curso` + `material` | `metodo`*, `curso`*, `material`*, `ordem`* |
| 8 | `modulo` | `curso` + `ordem` | `metodo`*, `curso`*, `ordem`*, `nome`*, `material`* |
| 9 | `combo` | `nome` | `metodo`*, `nome`*, `ativo` |
| 10 | `combo_curso` | `combo` + `curso` | `combo`*, `metodo`*, `curso`*, `ordem`* |
| 11 | `aluno` | `codigo` (vira `codigo_sgf`) | `codigo`*, `nome`*, `metodo`*, `combo`, `status`, `data_inicio`, `prev_conclusao_curso`, `observacoes` |
| 12 | `bloco_horario` | `sala` + `dia_semana` + `hora_inicio` | `dia_semana`* (1–7, ISO), `hora_inicio`* (`HH:MM`), `metodo`*, `sala`*, `professor`, `capacidade_override`, `ativo` |
| 13 | `bloco_aluno` | `bloco` + `aluno` | `aluno`*, `sala`*, `dia_semana`*, `hora_inicio`*, `tipo`* (`REM`\|`PRE`\|`REP`\|`NOVO`), `data_inicio_prevista` |
| 14 | `turma_modular` | `nome` | `nome`*, `metodo`*, `curso`*, `sala`*, `capacidade`*, `data_inicio`, `ativo` |
| 15 | `turma_modular_modulo` | `turma` + `modulo` | `turma`*, `metodo`*, `curso`*, `modulo_ordem`*, `data_inicio`, `prev_conclusao`, `concluido` |
| 16 | `turma_modular_aluno` | `turma` + `aluno` | `turma`*, `aluno`*, `data_entrada` |
| 17 | `aluno_material` | `aluno` + `material` | `aluno`*, `metodo`*, `material`*, `ordem`*, `origem` (`COMBO`\|`MANUAL`), `entregue`, `data_entrega` |
| 18 | `movimento_estoque` | `chave` (externa) | `chave`*, `metodo`*, `material`*, `tipo`* (`ENTRADA`\|`SAIDA`\|`AJUSTE`), `quantidade`*, `ocorrido_em`, `aluno`, `observacao` |

`*` = obrigatório. Datas em `AAAA-MM-DD`. Referência a outra entidade vai pela **chave natural
dela**, nunca por id — o arquivo não conhece uuid nenhum, e é isso que o torna reexecutável.

Três detalhes que custam caro se passarem despercebidos:

- **`material` é único por MÉTODO**, não por unidade (card 4.1): toda referência a material carrega
  `metodo` junto. O mesmo vale para `curso`;
- **`quantidade` tem sinal**: `ENTRADA` positiva, `SAIDA` negativa (`movimento_sinal_ck`);
- **`chave` do movimento** é responsabilidade do card 9.2 e precisa ser **estável entre snapshots**.
  Instável, o mesmo movimento entra duas vezes — e `movimento_estoque` é imutável, então a sobra não
  se apaga, só se estorna.

Exemplo mínimo:

```json
{
  "snapshot_em": "2026-08-29",
  "material": [
    {"metodo": "INTERATIVO", "codigo": "01", "nome": "Apostila 1",
     "categoria": "APOSTILA", "estoque_minimo": 5}
  ],
  "aluno": [
    {"codigo": "4433", "nome": "Fulana de Tal", "metodo": "INTERATIVO",
     "combo": "Secretariado Executivo", "data_inicio": "2025-02-03"}
  ],
  "movimento_estoque": [
    {"chave": "SAIDA-2025-03-01-01-4433", "metodo": "INTERATIVO", "material": "01",
     "tipo": "SAIDA", "quantidade": -1, "ocorrido_em": "2025-03-01", "aluno": "4433"}
  ]
}
```

---

## 4. As dezesseis verificações

**ERRO** é o que o banco recusaria: aplicar bateria no trigger e a transação voltaria inteira. Ele
bloqueia a aplicação. **AVISO** é o que o banco aceita e uma pessoa precisa olhar — é a lista de
exceções que o card 9.3 revisa. Todas rodam em `fn_importacao_validar`, chamada por
`fn_importacao_registrar` logo depois de criar o lote.

| # | O que confere | Severidade | Código |
|---|---|---|---|
| V1 | Entidade conhecida veio como algo que não é lista | ERRO | `ENTIDADE_INVALIDA` |
| V1 | Chave que a importação não conhece | AVISO | `ENTIDADE_DESCONHECIDA` |
| V2 | Campo obrigatório vazio | ERRO | `CAMPO_OBRIGATORIO` |
| V3 | Enumeração fora do `check` da coluna (status, tipo, método) | ERRO | `VALOR_INVALIDO` |
| V4 | Data/hora preenchida que não converte | ERRO | `DATA_INVALIDA` |
| V5 | Número fora de faixa (`ordem > 0`, `quantidade <> 0`, `dia_semana` 1–7…) | ERRO | `VALOR_INVALIDO` |
| V5.1 | Sinal do movimento contra o tipo | ERRO | `VALOR_INVALIDO` |
| V6 | Mesma chave natural duas vezes **no arquivo** | ERRO | `CHAVE_DUPLICADA` |
| V7 | Referência que não existe nem no arquivo nem no banco | ERRO | `REFERENCIA_AUSENTE` |
| V8 | Método do aluno diferente do método do bloco | ERRO | `METODO_INCOMPATIVEL` |
| V9 | Aluno fora de ATIVO/ACELERAR ocupando vaga | ERRO | `ALUNO_INATIVO` |
| V10 | Saldo do material ficaria negativo | ERRO | `SALDO_NEGATIVO` |
| V11 | Aluno ativo que não aparece em turma nenhuma | AVISO | `ALUNO_SEM_TURMA` |
| V12 | Previsão de conclusão fora da janela do snapshot | AVISO | `PREVISAO_ATIPICA` |
| V13 | Trilha diz entregue e não há saída (e o contrário) | AVISO | `ENTREGA_SEM_SAIDA` / `SAIDA_SEM_ENTREGA` |
| V14 | PC em MANUTENCAO sem manutenção aberta | AVISO | `PC_SEM_MANUTENCAO` |
| V15 | Saída de estoque sem aluno | AVISO | `SAIDA_SEM_ALUNO` |
| V16 | Status do arquivo diferente do status no sistema | AVISO | `STATUS_DIVERGENTE` |

Seis decisões que estas dezesseis carregam e que não se leem no código sozinhas:

1. **V7 olha os DOIS lados** — arquivo e banco. Numa reimportação o material já está no banco e não
   precisa vir de novo no arquivo; numa carga do zero ele vem no mesmo arquivo, algumas entidades
   acima. Olhar só para um dos lados reprovaria metade das cargas legítimas.
2. **V7 é um `left join` contra a lista distinta do que existe**, e não um `exists` por linha: com 4
   mil movimentos e 200 materiais, o correlacionado é produto cartesiano e a validação estoura o
   `statement_timeout` do PostgREST antes de dizer qualquer coisa.
3. **V8 e V9 duplicam o que os triggers já fazem, de propósito.** O trigger acusa a **primeira**
   linha e aborta; a validação lista **todas**. Não é segunda implementação de regra: é a mesma
   pergunta feita ao arquivo, e quem decide continua sendo o trigger.
4. **V10 desconta o que uma importação anterior já gravou** (`importacao_referencia`). Sem isso, a
   segunda leitura do mesmo arquivo somaria ao saldo os movimentos que ele próprio produziu e
   acusaria negativo onde não há. ⚠️ Esta é a verificação cuja contraprova **passou verde** na
   primeira tentativa — ver §7.
5. **V12 compara com o SNAPSHOT, não com hoje.** Comparar com hoje faria a mesma planilha mudar de
   veredito conforme o dia em que alguém a importa.
6. **V11 é AVISO, nunca ERRO.** Aluno sem turma é situação real da escola, e a rotina diária abre
   `ALUNO_SEM_TURMA` para ele no dia seguinte — a pendência é o destino certo, não o bloqueio.

---

## 5. A aplicação

`fn_importacao_aplicar(p_importacao_id, p_simular default true)`.

### 5.1 A simulação escreve de verdade e desfaz

O bloco `begin … exception` do PL/pgSQL abre uma **subtransação**: levantar exceção dentro dele
desfaz tudo o que ele escreveu e devolve o controle ao handler, com a transação de fora intacta. É o
"dry-run primeiro" do wireframe §16 **sem uma segunda implementação de coisa nenhuma** — o que a
simulação mede é o que os triggers reais disseram.

O mesmo bloco serve para o erro: se um trigger recusar uma linha na décima sétima entidade, tudo
volta e o motivo vira ocorrência, escrita **depois** do bloco (dentro dele seria desfeita junto). É
por isso que o handler existe em vez de deixar a exceção subir: exceção que sobe leva o relatório com
ela.

### 5.2 Idempotência

Dezessete entidades se reconhecem pela **chave natural** (`on conflict … do update`, ou
`update`+`insert` onde a única unique é `deferrable` e o Postgres não a aceita para inferência —
`modulo` e `pc_manutencao`). A décima oitava, `movimento_estoque`, não tem chave natural e é
imutável: ela se reconhece pelo mapa `importacao_referencia`, gravado no mesmo `insert` que a cria.

Reexecutar o snapshot é **enviar o arquivo de novo**: nasce outro lote, e os totais batem. Aplicar
**o mesmo lote** duas vezes é recusado (`IMPORTACAO_JA_APLICADA`) — o histórico de tentativas é o que
explica o que mudou entre uma carga e outra.

### 5.3 O que a aplicação NÃO reescreve

- **`status` de aluno que já existe.** Mudar status é transição: `tg_aluno_status_valida` a examina e
  o gate de FORMADO (card 8.3) pode recusá-la. Uma importação que reprova porque um aluno se formou
  entre dois snapshots é uma importação que não se consegue repetir. A divergência vira **V16**, e a
  mudança se faz na tela 3, que é onde a regra mora.
- **A trilha.** O aluno com combo entra e `tg_aluno_trilha_inicial` gera a trilha dele no mesmo
  `insert` (card 6.2). O que o arquivo traz em `aluno_material` é o **estado de entrega** dessas
  linhas, mais as manuais que a planilha tiver. Regerar aqui seria a segunda implementação de
  combo → curso → material.
- **Alocação com `ativo: false`.** Só alocação ativa entra; a diferença aparece na coluna
  "ignoradas" dos totais.

### 5.4 Os totais

Por entidade: `arquivo` (o que veio), `aplicadas` (o que foi escrito), `ignoradas` (a diferença) e
`no_sistema` (quantas linhas **existem** depois). A última é a que se compara com o Dashboard da
planilha no card 9.4; as outras três explicam a diferença quando ela aparece.

---

## 6. A tela (wireframes §16)

Quatro passos, e o primeiro é a **faixa do ambiente** — que não está no wireframe e entra assim
mesmo, porque a nota do card manda a tela dizer "na cara" onde está antes de aplicar. Produção usa o
par tonal de **erro**: é a única tela do app cuja ação vale a escola inteira, e as duas instalações
são idênticas na aparência (a lição do `SUPABASE_ANON_KEY` no card 3.9).

1. **Escolher o arquivo** — `<input type="file">` do navegador, via `package:web` (Dart puro, sem
   plugin; `file_picker` foi recusado por trazer código nativo de seis plataformas para uma tela que
   só a direção abre). Fora do navegador a tela **diz onde se importa** em vez de oferecer um botão
   que não abriria nada. Aqui também se informa a data do snapshot.
2. **Validação** — o que o arquivo traz, contado por entidade **antes de subir**. É onde a aba
   renomeada pelo extrator aparece, em vez de ser descoberta depois de mandar 4 MB.
3. **Relatório** — as ocorrências do banco, ERRO primeiro, com "Baixar relatório" em CSV (separador
   `;`, que é o que o Excel em português espera).
4. **Aplicar** — **Simular** primeiro, sempre: o botão de aplicar nasce desabilitado **com o motivo**
   (design-system §5.7) e só abre depois da simulação. Aplicar pede confirmação com o ambiente no
   título.

Abaixo dos quatro, **Importações anteriores** — o histórico, que o §16 não desenha e que o princípio
"auditável" do plano §8 exige (divergência registrada em `wireframes.md` §17).

---

## 7. O que foi medido, e o que quase passou batido

**Quatro contraprovas foram vistas vermelhas** em 06/09/2026, cada uma sabotando uma regra:

1. trocar `admin.ler` por `alunos.ler` no conjunto — reprova três asserções, entre elas a paridade de
   RLS: a secretaria passa a enxergar lote;
2. a simulação **não** desfazendo (o `raise` removido) — reprova as duas contagens antes/depois;
3. a dedup de `movimento_estoque` removida — reprova a igualdade de totais entre as duas
   importações. ⚠️ **Achado**: sem o `not exists`, a segunda importação **não duplica — ela falha**,
   porque a unique de `importacao_referencia` recusa a chave repetida e a transação inteira volta. A
   duplicação é impossível por dois caminhos independentes;
4. a V10 sem consciência de reexecução — ver abaixo.

⚠️ **E uma contraprova PASSOU VERDE na primeira tentativa, o que é o achado mais útil deste card.**
A sabotagem da V10 (tirar o desconto do que já foi importado) não quebrava nada: com material
**novo**, o saldo depois da primeira carga é exatamente a soma do arquivo, e `S + S` nunca é negativo
quando `S` não é. O caso só se separa quando o material **já tem saldo de outra origem e o arquivo só
o consome** — o teste ganhou um terceiro arquivo, que zera o saldo de um material carregado antes, e
só então a sabotagem ficou vermelha.

Dois defeitos que a própria suíte pegou antes do PR:

- **`get diagnostics v_n = v_n + row_count`** não existe: o lado direito é só o nome do item. Custou
  a primeira aplicação da migração;
- **função volátil dentro de `where`** é executada **uma vez por linha**: a asserção
  `where i.id = fn_importacao_registrar(...)` criava um lote por linha de `importacao` e comparava
  com um id diferente a cada vez, devolvendo NULL. Pior: o NULL fazia a asserção falhar **com a
  sabotagem e sem ela**, e a contraprova teria "passado" pela razão errada.

E um defeito de tela que o widget test pegou: quando o trigger recusa uma linha, o lote vira FALHOU e
a tela sai do ramo que mostrava a mensagem do banco — a pessoa lia "foi desfeita por inteiro" sem
saber por quê, com um arquivo de milhares de linhas na mão.

---

## 8. Limites assumidos

- **O arquivo inteiro vai numa chamada.** Um snapshot da escola tem alguns milhares de linhas e cabe
  bem; se um dia não couber, o corte natural é por entidade, e o `importacao_referencia` já suporta
  carga em partes.
- **Não há importação parcial.** Ou o lote inteiro entra, ou nada entra. É o que a virada (card 9.7)
  precisa: conferir contagem contra o zero.
- **A tela é de navegador.** Não há seletor de arquivo no Android/iOS, e isso é decisão — a carga é
  operação de direção, em computador, contra um ambiente escolhido na hora.
- **Nada aqui roda sozinho.** Sem rotina, sem gatilho de deploy, sem agendamento: a importação só
  acontece quando alguém aperta o botão.
