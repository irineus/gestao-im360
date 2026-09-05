# Catálogo de permissões e matriz inicial perfil × permissão — card 2.4

> **Fonte do catálogo de permissões.** O card 2.1 fixou o *formato* (`<dominio>.<acao>` na política
> de RLS) e deixou o catálogo para este card; o card 2.2 entregou as 15 permissões de **ação** que
> as funções exigem; o card 2.3 entregou as 9 de **leitura** que as views exigem. Aqui o catálogo
> fecha: quais códigos existem, o que cada política de cada tabela exige, quem recebe o quê na
> matriz inicial e qual conjunto guarda cada rota do Flutter.
>
> Entrada direta para o **card 3.6** (seed de perfis, permissões e matriz) e para o **card 3.4**
> (RLS e `tem_permissao`). Nenhuma migração é escrita aqui — migração só via CI/CD, e o SQL de
> criação é dos cards das Fases 3 a 8.

Data: 01/09/2026. Base: `docs/plano-projeto-sistema.md` §3 e §7, `docs/modelagem-dados-ddl.md` §4 e
§5, `docs/regras-negocio-funcoes.md` §12.1, `docs/views-leitura.md` §11.

---

## 1. Convenções

1. **Código = `<dominio>.<acao>`**, tudo em `snake_case`, sem acento. `permissao.codigo` guarda o par
   completo; `permissao.dominio` guarda só o domínio.
2. **Domínio no plural** — `alunos`, `turmas`, `materiais`. Fecha o ajuste #7 do card 2.3: o
   comentário do DDL exemplificava singular (`aluno.editar`), o card 2.2 já tinha fixado plural, e
   duas convenções vivas produzem `alunos.ler` e `aluno.ler` na mesma matriz, que é o tipo de bug
   que ninguém encontra porque as duas linhas parecem certas.
3. **O código verifica permissão, nunca perfil.** Perfil é só um agrupamento editável na tela de
   Administração; nenhuma função, política ou rota do Flutter cita `DIRECAO` ou `MONITOR`.
4. **Verbo é o que o usuário faz, não o que o SQL faz.** `estoque.lancar_saida` existe;
   `estoque.criar` não, porque não há "criar movimento" na cabeça de ninguém — há entregar apostila,
   receber pedido, ajustar e estornar.
5. **Código sem consumidor não entra no catálogo.** Um código que nenhuma política, função ou rota
   exige é decoração: aparece marcado na matriz, dá sensação de controle e não controla nada.
   Por isso não existem `alunos.excluir` (aluno vira CANCELADO, não some) nem
   `estoque.lancar_entrada` (entrada é sempre recebimento de pedido — Decisões vigentes, §2).
6. **Permissão é por unidade.** `permissao`, `perfil` e `perfil_permissao` têm `unidade_id`; o seed
   do card 3.6 cria o catálogo inteiro para a unidade única da v1, e a segunda unidade da Fase 11
   recebe uma cópia, não um `null`.

---

## 2. Domínios e as 33 tabelas do DDL

A política de RLS do card 2.1 é **por tabela** e cita `<dominio>.<acao>`; logo toda tabela pertence a
exatamente um domínio. São **12 domínios** cobrindo as 33 tabelas:

| Domínio | Tabelas |
|---|---|
| `admin` | `usuario`, `perfil`, `permissao`, `perfil_permissao`, `usuario_perfil` |
| `unidades` | `unidade` |
| `parametros` | `parametro` |
| `materiais` | `metodo`, `material`, `curso`, `curso_material`, `modulo`, `combo`, `combo_curso` |
| `alunos` | `aluno`, `aluno_status_hist`, `aluno_material`, `aluno_material_hist` |
| `salas` | `sala`, `pc`, `pc_manutencao` |
| `professores` | `professor` |
| `turmas` | `bloco_horario`, `bloco_aluno`, `bloco_aluno_reposicao`, `turma_modular`, `turma_modular_modulo`, `turma_modular_aluno` |
| `estoque` | `movimento_estoque` |
| `compras` | `pedido_compra`, `pedido_item` |
| `certificados` | `certificado_checklist` |
| `pendencias` | `pendencia` |

`professores` fica **fora** de `salas` mesmo compartilhando a tela do card 4.5: `salas.ler` como
guarda do nome do professor seria um nome mentindo sobre o que protege, e o custo de ter o domínio é
três linhas de seed. `metodo`, `curso`, `modulo` e `combo` ficam em `materiais` porque são o mesmo
catálogo curricular — e porque, como o §5 mostra, `materiais.ler` acaba sendo permissão de todo
mundo.

---

## 3. Catálogo — 49 códigos

Legenda da coluna **Origem**: `2.2` = card 2.2 (funções), `2.3` = card 2.3 (views), `2.4` = novo
aqui.

### 3.1 `admin` (3)

| Código | Origem | O que autoriza |
|---|---|---|
| `admin.ler` | 2.3 | Ler `usuario`, `perfil`, `permissao`, `perfil_permissao`, `usuario_perfil` |
| `admin.gerir_usuarios` | 2.4 | Criar/editar `usuario`; atribuir e remover perfis (`usuario_perfil`) |
| `admin.gerir_perfis` | 2.4 | Criar/editar `perfil`; marcar e desmarcar a matriz (`perfil_permissao`) |

`permissao` **não tem política de escrita nenhuma**: o catálogo só muda por migração. É coerente com
a convenção 5 — um código novo só serve depois que alguma política, função ou rota passa a exigi-lo,
e isso é código, não dado. Também evita o modo de falha mais bobo possível: alguém apaga
`estoque.lancar_saida` pela tela e nenhuma entrega funciona mais.

### 3.2 `unidades` (2) e `parametros` (2)

| Código | Origem | O que autoriza |
|---|---|---|
| `unidades.ler` | 2.4 | Ler `unidade` (nome exibido no cabeçalho e na seleção de unidade) |
| `unidades.gerir` | 2.4 | Criar/editar `unidade` |
| `parametros.ler` | 2.4 | Ler `parametro` na tela de Administração |
| `parametros.gerir` | 2.4 | Criar/editar `parametro` |

⚠️ `parametros.ler` **não** é o que faz as regras enxergarem parâmetro — ver o achado #4 do §7.

### 3.3 `materiais` (4), `alunos` (7), `salas` (5), `professores` (3)

| Código | Origem | O que autoriza |
|---|---|---|
| `materiais.ler` | 2.3 | Ler método, material, curso, módulo, combo e suas composições |
| `materiais.criar` | 2.4 | Criar material, curso, módulo, combo |
| `materiais.editar` | 2.4 | Editar os mesmos; montar composição de curso e de combo |
| `materiais.excluir` | 2.4 | Remover linha de `curso_material` / `combo_curso`; excluir cadastro sem uso |
| `alunos.ler` | 2.3 | Ler `aluno`, histórico de status e trilha |
| `alunos.criar` | 2.4 | Matricular aluno |
| `alunos.editar` | 2.4 | Editar dados cadastrais, combo, previsão de conclusão |
| `alunos.alterar_status` | 2.2 | `fn_aluno_alterar_status` — transições normais |
| `alunos.reverter_status` | 2.2 | `fn_aluno_reverter_status` — sair de FORMADO/CANCELADO (terminal) |
| `alunos.formar_sem_certificado` | 2.2 | Gate de FORMADO sem certificado ENTREGUE |
| `alunos.editar_trilha` | 2.2 | Reordenar, incluir e remover item da trilha |
| `salas.ler` | 2.3 | Ler `sala`, `pc`, `pc_manutencao` |
| `salas.criar` | 2.4 | Cadastrar sala e PC |
| `salas.editar` | 2.4 | Editar sala e PC (inclusive `pc.status`) |
| `salas.excluir` | 2.4 | Excluir sala/PC sem histórico |
| `salas.registrar_manutencao` | 2.4 | Abrir e fechar `pc_manutencao` (dispara recálculo de capacidade) |
| `salas.acessar_credencial` | 2.9 | Ler **e** gravar a credencial do PC (`fn_pc_credencial_ler` / `fn_pc_credencial_gravar`) e o log `pc_credencial_acesso`. O 50º código — decidido no card 2.9, está no seed do 3.6 desde 01/09/2026 e faltava nesta tabela (acrescentado no card 4.5, 02/09/2026) |
| `professores.ler` | 2.4 | Ler `professor` (nome na grade semanal) |
| `professores.criar` | 2.4 | Cadastrar professor |
| `professores.editar` | 2.4 | Editar/inativar professor |

`salas.registrar_manutencao` é separado de `salas.editar` porque tem consequência que `editar` não
tem: `tg_pc_revalida_blocos` recalcula a capacidade de todos os blocos da sala e pode abrir
`BLOCO_ACIMA_CAPACIDADE` e `PC_SEM_SUBSTITUTO` (card 2.2, §6). Quem corrige o nome de um PC não
precisa poder derrubar a capacidade de uma turma.

Não existe `professores.excluir`: professor sai por `ativo = false`, senão a grade histórica perde o
nome de quem deu a aula.

### 3.4 `turmas` (6)

| Código | Origem | O que autoriza |
|---|---|---|
| `turmas.ler` | 2.3 | Ler blocos, alocações, reposições e turmas Modular |
| `turmas.criar` | 2.4 | Criar bloco de horário e turma Modular |
| `turmas.editar` | 2.4 | Editar bloco (professor, sala, `capacidade_override`); cronograma e avanço de módulo |
| `turmas.excluir` | 2.4 | Excluir bloco/turma sem alocação e linha de cronograma |
| `turmas.alocar` | 2.2 | `fn_bloco_admitir` / `fn_bloco_remover`, alocação Modular e `fn_reposicao_registrar` |
| `turmas.lancar_reposicao_retroativa` | 2.2 | Reposição com data no passado (`tg_reposicao_admissao`) |

**`turmas.alocar` cobre admitir *e* remover**, contra a sugestão do plano (§3: "alocar aluno, remover
aluno"). Dois motivos: quem pode colocar precisa poder desfazer o próprio erro, e a remoção também
acontece **sem ator** — `tg_aluno_status_desaloca` desativa as alocações quando o aluno sai de
ATIVO/ACELERAR. Um perfil que pudesse alocar mas não remover teria a mudança de status barrada pela
RLS de `bloco_aluno`, com erro opaco vindo de uma tela que não fala de turma.

### 3.5 `estoque` (4), `compras` (6), `certificados` (5), `pendencias` (2)

| Código | Origem | O que autoriza |
|---|---|---|
| `estoque.ler` | 2.3 | Ler `movimento_estoque` — e, por tabela, o saldo |
| `estoque.lancar_saida` | 2.2 | `fn_registrar_entrega` (SAIDA) |
| `estoque.estornar` | 2.2 | `fn_estornar_entrega` (ESTORNO) |
| `estoque.ajustar` | 2.2 | `fn_ajustar_estoque` (AJUSTE, motivo obrigatório) |
| `compras.ler` | 2.3 | Ler `pedido_compra` e `pedido_item` |
| `compras.criar` | 2.4 | Criar pedido em RASCUNHO e seus itens |
| `compras.editar` | 2.4 | Editar itens do rascunho, enviar e cancelar pedido |
| `compras.excluir` | 2.4 | Remover item de pedido em RASCUNHO |
| `compras.receber` | 2.2 | `fn_pedido_receber` — gera ENTRADA no estoque |
| `compras.receber_excedente` | 2.2 | Receber além de `qtd_pedida` |
| `certificados.ler` | 2.3 | Ler `certificado_checklist` |
| `certificados.criar` | 2.4 | Abrir checklist (`fn_certificado_abrir`) — ver achado #3 do §7 |
| `certificados.marcar_pedagogico` | 2.2 | Itens PEDAGOGICO e FORMATURA |
| `certificados.marcar_financeiro` | 2.2 | Item FINANCEIRO |
| `certificados.alterar_status` | 2.2 | `certificado_status`: NAO_PEDIDO → PEDIDO → ENTREGUE |
| `pendencias.ler` | 2.3 | Ler `pendencia` e a central |
| `pendencias.resolver` | 2.2 | `fn_pendencia_resolver` (resolução com justificativa) |

`pedido_compra` não tem política de `delete`: pedido enviado vira CANCELADO, não desaparece — o
histórico de compra é o que explica um saldo três meses depois.

---

## 4. O que cada política de RLS exige, tabela a tabela

O padrão do card 2.1 (quatro políticas, `<dominio>.ler|criar|editar|excluir`) vale para a maioria.
As linhas em **negrito** fogem do padrão, e o motivo está logo abaixo da tabela. Célula com `—`
significa **sem política**, e sem política é sem acesso.

Todas as políticas trazem, além do que está na coluna, o filtro `unidade_id = fn_unidade_atual()`.

| Tabela | `select` | `insert` | `update` | `delete` |
|---|---|---|---|---|
| `unidade` | `unidades.ler` | `unidades.gerir` | `unidades.gerir` | — |
| `usuario` | `admin.ler` | `admin.gerir_usuarios` | `admin.gerir_usuarios` | — |
| `perfil` | `admin.ler` | `admin.gerir_perfis` | `admin.gerir_perfis` | — |
| **`permissao`** | `admin.ler` | — | — | — |
| `perfil_permissao` | `admin.ler` | `admin.gerir_perfis` | — | `admin.gerir_perfis` |
| `usuario_perfil` | `admin.ler` | `admin.gerir_usuarios` | — | `admin.gerir_usuarios` |
| `parametro` | `parametros.ler` | `parametros.gerir` | `parametros.gerir` | — |
| `metodo` | `materiais.ler` | `materiais.criar` | `materiais.editar` | — |
| `material`, `curso`, `modulo`, `combo` | `materiais.ler` | `materiais.criar` | `materiais.editar` | `materiais.excluir` |
| `curso_material`, `combo_curso` | `materiais.ler` | `materiais.editar` | `materiais.editar` | `materiais.excluir` |
| `aluno` | `alunos.ler` | `alunos.criar` | **`alunos.editar` ∨ `alunos.alterar_status` ∨ `alunos.reverter_status`** | — |
| **`aluno_status_hist`** | `alunos.ler` | `alunos.alterar_status` ∨ `alunos.reverter_status` | — | — |
| **`aluno_material`** | `alunos.ler` | `alunos.editar_trilha` ∨ `alunos.criar` | `alunos.editar_trilha` ∨ `estoque.lancar_saida` ∨ `estoque.estornar` | `alunos.editar_trilha` |
| **`aluno_material_hist`** | `alunos.ler` | `alunos.editar_trilha` ∨ **`alunos.criar`** ∨ `estoque.lancar_saida` | — | — |
| `sala`, `pc` | `salas.ler` | `salas.criar` | `salas.editar` | `salas.excluir` |
| **`pc_manutencao`** | `salas.ler` | `salas.registrar_manutencao` | `salas.registrar_manutencao` | — |
| `professor` | `professores.ler` | `professores.criar` | `professores.editar` | — |
| `bloco_horario`, `turma_modular` | `turmas.ler` | `turmas.criar` | `turmas.editar` | `turmas.excluir` |
| `turma_modular_modulo` | `turmas.ler` | `turmas.editar` | `turmas.editar` | `turmas.excluir` |
| **`bloco_aluno`, `turma_modular_aluno`, `bloco_aluno_reposicao`** | `turmas.ler` | `turmas.alocar` | `turmas.alocar` ∨ `alunos.alterar_status` ∨ `alunos.reverter_status` | — |
| **`movimento_estoque`** | `estoque.ler` | por `tipo` (abaixo) | — | — |
| `pedido_compra` | `compras.ler` | `compras.criar` | `compras.editar` ∨ `compras.receber` | — |
| `pedido_item` | `compras.ler` | `compras.criar` ∨ `compras.editar` | `compras.editar` ∨ `compras.receber` | `compras.excluir` |
| **`certificado_checklist`** | `certificados.ler` | `certificados.criar` | `certificados.marcar_pedagogico` ∨ `certificados.marcar_financeiro` ∨ `certificados.alterar_status` | — |
| **`pendencia`** | `pendencias.ler` | *só* `unidade_id = fn_unidade_atual()` | `pendencias.resolver` | — |

**`movimento_estoque`, insert por tipo:**

```sql
with check (unidade_id = public.fn_unidade_atual() and (
     (tipo = 'ENTRADA' and public.tem_permissao('compras.receber'))
  or (tipo = 'SAIDA'   and public.tem_permissao('estoque.lancar_saida'))
  or (tipo = 'AJUSTE'  and public.tem_permissao('estoque.ajustar'))
  or (tipo = 'ESTORNO' and public.tem_permissao('estoque.estornar'))))
```

Um `estoque.criar` genérico seria uma porta aberta: "Automatically expose new tables" está ligado
nos dois projetos (Decisões vigentes, §1), então `movimento_estoque` está publicado no PostgREST, e
o monitor — que precisa gravar SAIDA — poderia `POST` uma ENTRADA de 500 unidades sem passar por
`fn_pedido_receber`. A política por tipo custa quatro linhas e fecha isso. `update`/`delete` sem
política em nenhuma hipótese: é a imutabilidade como estrutura que o card 2.1 fixou, com
`tg_movimento_imutavel` como segunda barreira.

**Por que as demais fogem do padrão** — todas pelo mesmo motivo, que é o achado central deste card:
**várias escritas acontecem como efeito colateral, dentro da transação de outro ator.** As funções
do card 2.2 são `security invoker`; a RLS que elas encontram é a de quem chamou. Um `alunos.editar`
exigido em `aluno_material` faria a entrega do monitor falhar; um `alunos.editar` exigido em
`bloco_aluno` faria a mudança de status do pedagógico falhar. O detalhe de cada caso está no §7.

`pendencia` é a única tabela cuja política de `insert` **não exige permissão de domínio nenhuma**.
Pendência é anotação do sistema: é aberta por `fn_registrar_entrega` (monitor), por
`tg_aluno_combo_alterado` (secretaria), por `fn_revalidar_blocos_sala` (quem registra manutenção) e
pelas rotinas `pg_cron`. Enumerar os autores numa cláusula `or` produziria uma lista que cresce a
cada card novo e cujo esquecimento aparece como erro opaco de RLS numa tela que não fala de
pendência. Ler continua exigindo `pendencias.ler`, e resolver continua exigindo `pendencias.resolver`
— que é onde o controle importa.

---

## 5. Matriz inicial perfil × permissão

Quatro perfis: **DIRECAO**, **PEDAGOGICO**, **SECRETARIA**, **MONITOR**. `✔` = concedida no seed do
card 3.6. Editável na tela de Administração a partir do primeiro dia — esta é a configuração
inicial, não uma regra.

| Código | DIRECAO | PEDAGOGICO | SECRETARIA | MONITOR |
|---|:--:|:--:|:--:|:--:|
| `admin.ler` | ✔ | | | |
| `admin.gerir_usuarios` | ✔ | | | |
| `admin.gerir_perfis` | ✔ | | | |
| `unidades.ler` | ✔ | ✔ | ✔ | ✔ |
| `unidades.gerir` | ✔ | | | |
| `parametros.ler` | ✔ | | | |
| `parametros.gerir` | ✔ | | | |
| `materiais.ler` | ✔ | ✔ | ✔ | ✔ |
| `materiais.criar` | ✔ | | ✔ | |
| `materiais.editar` | ✔ | | ✔ | |
| `materiais.excluir` | ✔ | | ✔ | |
| `alunos.ler` | ✔ | ✔ | ✔ | ✔ |
| `alunos.criar` | ✔ | ✔ | ✔ | |
| `alunos.editar` | ✔ | ✔ | ✔ | |
| `alunos.alterar_status` | ✔ | ✔ | ✔ | |
| `alunos.reverter_status` | ✔ | | | |
| `alunos.formar_sem_certificado` | ✔ | | | |
| `alunos.editar_trilha` | ✔ | ✔ | ✔ | |
| `salas.ler` | ✔ | ✔ | ✔ | ✔ |
| `salas.criar` | ✔ | | ✔ | |
| `salas.editar` | ✔ | | ✔ | |
| `salas.excluir` | ✔ | | | |
| `salas.registrar_manutencao` | ✔ | | ✔ | ✔ |
| `salas.acessar_credencial` | ✔ | | | ✔ |
| `professores.ler` | ✔ | ✔ | ✔ | ✔ |
| `professores.criar` | ✔ | ✔ | ✔ | |
| `professores.editar` | ✔ | ✔ | ✔ | |
| `turmas.ler` | ✔ | ✔ | ✔ | ✔ |
| `turmas.criar` | ✔ | ✔ | ✔ | |
| `turmas.editar` | ✔ | ✔ | ✔ | |
| `turmas.excluir` | ✔ | ✔ | ✔ | |
| `turmas.alocar` | ✔ | ✔ | ✔ | |
| `turmas.lancar_reposicao_retroativa` | ✔ | ✔ | ✔ | |
| `estoque.ler` | ✔ | ✔ | ✔ | ✔ |
| `estoque.lancar_saida` | ✔ | | ✔ | ✔ |
| `estoque.estornar` | ✔ | | ✔ | |
| `estoque.ajustar` | ✔ | | ✔ | |
| `compras.ler` | ✔ | | ✔ | |
| `compras.criar` | ✔ | | ✔ | |
| `compras.editar` | ✔ | | ✔ | |
| `compras.excluir` | ✔ | | ✔ | |
| `compras.receber` | ✔ | | ✔ | |
| `compras.receber_excedente` | ✔ | | | |
| `certificados.ler` | ✔ | ✔ | ✔ | ✔ |
| `certificados.criar` | ✔ | | ✔ | ✔ |
| `certificados.marcar_pedagogico` | ✔ | ✔ | | |
| `certificados.marcar_financeiro` | ✔ | | | ✔ |
| `certificados.alterar_status` | ✔ | | ✔ | |
| `pendencias.ler` | ✔ | ✔ | ✔ | ✔ |
| `pendencias.resolver` | ✔ | ✔ | ✔ | |

Totais: direção 49, secretaria 37, pedagógico 22, monitor 13 — **com `salas.acessar_credencial`
(card 2.9): direção 50, secretaria 37, pedagógico 22, monitor 14**, que é o que o seed do card 3.6
grava e a suíte `022_seed_inicial` assere.

### 5.1 Onde a matriz teve de ir além do plano, e por quê

1. **`materiais.ler` para todo mundo, monitor incluído.** Não é generosidade, é condição de
   funcionamento: cinco das dez views do card 2.3 fazem `join` **interno** em `metodo`, `curso` ou
   `modulo` (`v_bloco_vagas_semana`, `v_turma_modular_lotacao` e as três do dashboard). Com
   `security_invoker = on`, quem não lê o catálogo não recebe linha nenhuma — a grade semanal e o
   dashboard aparecem **vazios**, não errados. Ver achado #1 do §7.
2. **`estoque.ler` para o monitor.** `fn_saldo_material` continua `security invoker` (decisão do
   card 2.3: função que decide dentro de uma escrita enxerga pela RLS de quem chama). Sem
   `estoque.ler`, o saldo lido pelo monitor é **0 para todo material**, e `fn_registrar_entrega`
   devolve `BLOQUEADA_SEM_ESTOQUE` em toda entrega, abrindo pendência de compra de um estoque que
   existe. É o caso mais caro do §3.4 do card 2.3 — número errado com cara de certo.
3. **`certificados.criar` para o monitor e a secretaria.** Quem registra a entrega que fecha a
   trilha é quem abre o checklist, porque `fn_certificado_abrir` roda dentro da mesma transação.
4. **`unidades.ler` e `professores.ler` para todos.** Nome da unidade no cabeçalho e nome do
   professor na grade. Sem o segundo, o `left join` de `v_bloco_vagas_semana` degrada para nulo e a
   grade fica sem professor — não quebra, mente.
5. **`salas.registrar_manutencao` para o monitor.** Quem vê o PC quebrado é quem está no
   laboratório. É a permissão mais discutível da matriz, porque ela derruba capacidade de turma;
   fica como **ponto para o Irineu confirmar** (§9).
6. **Salas, PCs e materiais para a secretaria; professores também para o pedagógico.** O plano não
   posiciona cadastro de infraestrutura em nenhum perfil além da direção. Deixar só com a direção
   significa PC em manutenção esperando o diretor, e professor novo esperando para poder ser posto
   numa turma que o pedagógico é quem monta. Também **ponto para confirmar** (§9).
7. **`pendencias.resolver` fora do monitor.** Resolver pendência é decisão com justificativa
   registrada; o monitor as gera, não as encerra.

### 5.2 O que ficou só com a direção

As três de exceção que o card 2.2 já reservava — `alunos.formar_sem_certificado`,
`alunos.reverter_status`, `compras.receber_excedente` — mais todo o domínio `admin`, os
`parametros`, `unidades.gerir` e `salas.excluir`. São as ações que ou reescrevem história
(reverter status, receber acima do pedido) ou mudam quem pode o quê.

---

## 6. Guardas de rota — as 13 telas do plano §7

A rota é guardada pelo **conjunto mínimo** que faz a tela mostrar número certo, não pela permissão
mais óbvia. É o mesmo princípio do §3.4 do card 2.3: a RLS reduz linhas em silêncio, então uma tela
aberta com permissão parcial não dá erro — dá um número menor.

| # | Tela | Conjunto exigido | Perfis que abrem |
|---|---|---|---|
| 1 | Login / seleção de unidade | `unidades.ler` | todos |
| 2 | Dashboard | `alunos.ler` + `materiais.ler` + `turmas.ler` + `salas.ler` + `pendencias.ler` | todos |
| 3 | Alunos (lista e ficha) | `alunos.ler` + `materiais.ler` | todos |
| 3b | Ficha → aba Trilha | `alunos.ler` + `materiais.ler` + `estoque.ler` | todos |
| 4 | Turmas por horário (grade) | `turmas.ler` + `salas.ler` + `professores.ler` + `materiais.ler` | todos |
| 5 | Turmas Modular | `turmas.ler` + `salas.ler` + `materiais.ler` | todos |
| 6 | Materiais e estoque | `materiais.ler` + `estoque.ler` | todos |
| 7 | Compras | `materiais.ler` + `estoque.ler` + `alunos.ler` + `compras.ler` | direção, secretaria |
| 8 | Projeção de demanda | `materiais.ler` + `estoque.ler` + `alunos.ler` + **`turmas.ler`** | direção, pedagógico, secretaria, monitor |
| 9 | Certificados | `certificados.ler` + `alunos.ler` + **`materiais.ler`** | todos |
| 10 | Salas e PCs | `salas.ler` + `professores.ler` | todos |
| 11 | Pendências | `pendencias.ler` | todos |
| 12 | Administração | `admin.ler` | direção |
| 13 | Importação | `admin.ler` + os domínios do que se importa | direção |

⚠️ **A linha 8 ganhou `turmas.ler` em 05/09/2026 (card 8.5), e nenhum perfil perdeu a tela** — os
quatro já o têm. A correção não é formal: `v_projecao_aluno` (card 8.1) faz `join` **interno** em
`metodo` e lê `turma_modular*` para achar o cronograma do degrau MODULAR, e `v_projecao_material_mes`
junta `material`. Faltando qualquer um dos quatro códigos, a tela que decide **o que a escola compra**
não vem errada: vem **vazia**, com cara de escola que não vai precisar de apostila nenhuma. É o §3.4
do card 2.3 no pior lugar em que ele podia cair, e a nota do card de Ordem 5 da Fase 2 já o dizia
desde 01/09/2026 — esta tabela é que tinha ficado com três. O `guardas_rota_test` percorre a tabela e
foi corrigido no mesmo commit.

⚠️ **A linha 9 ganhou `materiais.ler` em 06/09/2026 (card 8.6), pelo mesmo motivo e sem perda de
perfil.** `v_certificado_fila` faz `join` **interno** em `metodo` — é o método que a linha da fila
mostra e o que o filtro `[método v]` do `wireframes.md` §12.1 oferece. Faltando o código, a fila de
formandos vem **vazia**, com cara de escola em que ninguém está terminando o curso. Os quatro perfis
já têm `materiais.ler` pelo item 1 do §5.1, então "todos" continua verdadeiro.

O botão dentro da tela é guardado pela permissão de ação (`turmas.alocar` no botão "adicionar
aluno", `estoque.lancar_saida` no "Registrar entrega"), e a função no banco repete a checagem com
`fn_exige_permissao`. A guarda do Flutter existe para não oferecer o que vai falhar; quem decide é o
banco.

A tela 7 (Compras) é a única com perfil de fora por decisão explícita do card 2.3: o monitor não tem
`compras.ler`, logo leria `qtd_pedida_pendente = 0` e o sistema sugeriria comprar de novo o que já
está a caminho.

---

## 7. Achados — o que este card encontrou ao fechar o catálogo

| # | Achado | Onde corrigir | Card | Gravidade |
|---|---|---|---|---|
| 1 | `materiais.ler` falta no conjunto declarado de `v_bloco_vagas_semana`, `v_turma_modular_lotacao`, `v_dashboard_alunos_metodo`, `v_dashboard_conclusoes_semestre` e `v_dashboard_tipos_bloco` — `join` interno em `metodo`/`curso`/`modulo` zera a view | 2.3 §11 | 5.6 / 5.9 / 7.4 / 8.7 | **bloqueante** — ✅ **tabela corrigida e `v_bloco_vagas_semana` ASSERIDA em 04/09/2026 (card 5.9)**: perfil `SEM_MATERI` no teste 095 vê a grade vazia e a recebe inteira de volta com a permissão. ✅ **`v_turma_modular_lotacao` ASSERIDA em 05/09/2026 (card 7.4)**, no mesmo perfil e no mesmo par vazia→inteira, mais a contraprova de que a direção vê turma Modular (sem ela o par compararia zero com zero); contraprova vista **vermelha** trocando o `join` interno em `curso` por `left join`. ✅ **FECHADO em 06/09/2026 (card 8.7)**, com as **três `v_dashboard_*`** no mesmo perfil e no mesmo par vazia → inteira, precedidas da contraprova de que a direção vê as três (senão o par compararia zero com zero) e com a sabotagem `left join` em `metodo` vista **vermelha**. ⚠️ **O perfil `SEM_MATERI` precisou ganhar `alunos.ler` para o par medir o que diz:** sem ele as duas views de aluno viriam vazias por falta *daquela* permissão, e a asserção passaria verde provando outra coisa; a concessão não afrouxa as duas anteriores, porque nem a grade nem a lotação Modular leem aluno. **As cinco views do achado estão medidas** |
| 2 | `professores.ler` falta no conjunto de `v_bloco_vagas_semana` (`left join` → professor nulo) | 2.3 §11 | 5.6 / 5.9 | média — ✅ **corrigido em 04/09/2026 (card 5.9)**; a asserção já existia no teste 095 desde o 5.6 |
| 3 ✅ | **Fechado em 05/09/2026 (card 8.3).** A matriz inicial já estava certa — `estoque.lancar_saida` e `certificados.criar` estão exatamente nos mesmos três perfis (direção, secretaria, monitor) —, e o que faltava era **medir isso**: o teste `081` §2 assere a interseção contra o **seed**, não contra a intenção, porque a matriz é editável na tela do card 4.7 e o modo de falha é péssimo (só aparece no ÚLTIMO livro de um aluno, meses depois, numa tela que fala de apostila). `fn_certificado_abrir` continua `invoker` e confere a permissão no topo com `fn_exige_permissao`: definer resolveria sozinho, mas tiraria `certificados.criar` de circulação e o C11 o acusaria de "catalogado e não usado" | matriz (§5) e política de insert | 8.3 | **bloqueante** |
| 4 | `fn_param_int`/`fn_param_txt` são `security invoker` e leem `parametro`: `fn_rep_situacao` (invoker, chamada pela tela) devolve `PARAMETRO_AUSENTE` para quem não tem `parametros.ler`. Passar as duas a `security definer` com `search_path` fixo — mesmo argumento do achado #3 do card 2.3 | 2.2 §2.3 | 3.4 | alta |
| 5 | `aluno_material` e `aluno_material_hist` são escritos por `fn_registrar_entrega`: política de `update`/`insert` por `alunos.editar` bloquearia o monitor | 2.1 §4 | 6.1 / 6.3 | **bloqueante** — ✅ **corrigido em 04/09/2026 (card 6.1)**: as políticas nasceram com o `or` de `estoque.lancar_saida`/`estoque.estornar`, e a folga que ele abre (RLS não é por coluna) ficou fechada por `tg_aluno_material_colunas_permitidas`. Aqui, ao contrário do card 5.1, o perfil que expõe a folga **já existe** na matriz inicial: o monitor |
| 6 ✅ | **Fechado em 05/09/2026 (card 7.1), a terceira e última tabela.** `bloco_aluno` e `bloco_aluno_reposicao` (5.1) e `turma_modular_aluno` (7.1) são desativados por `tg_aluno_status_desaloca`, e o `update` das três aceita também `alunos.alterar_status`/`alunos.reverter_status`. Nas três, a folga que o `or` abre é fechada por guarda **de coluna** no trigger — só `ativo` (e `status = 'CANCELADA'` na reposição) passa sem `turmas.alocar` | 2.1 §4 | 5.1 / 7.1 | **bloqueante** |
| 7 | `pendencia` é aberta por quase toda função de aplicação: `insert` sem exigência de domínio | 2.1 §4 | 5.5 | **bloqueante** |
| 8 ✅ | **Fechado em 05/09/2026 (card 8.3)**, exatamente como escrito: `tg_certificado_colunas_permitidas` compara OLD/NEW por grupo (pedagógico+formatura, financeiro, status, e a identidade — `aluno_id`/`unidade_id`/`data_fim_curso`, que exige `certificados.criar`) e chama `fn_exige_permissao`. ⚠️ **Contraprova vista vermelha:** com o grupo do pedagógico removido do trigger, o `update` direto do monitor em `pedagogico_ok` passa — a política aceita, porque a `using` dela é o `or` de três códigos. `observacoes` fica **fora** da lista de propósito: guardá-la exigiria um código que o catálogo do §3.5 não tem | 2.2 §9 | 8.3 | alta |
| 9 | `movimento_estoque` precisa de política de `insert` **por tipo**, não de um `estoque.criar` genérico | 2.1 §4 | 6.1 | alta — ✅ **corrigido em 04/09/2026 (card 6.1)**, com o par asserido no teste 050: o monitor grava SAIDA e recebe `42501` na ENTRADA e no AJUSTE |
| 10 | `permissao` sem política de escrita — catálogo só muda por migração | 2.1 §4 | 3.3 | baixa |
| 11 | `permissao.dominio` no plural, comentário do DDL corrigido — fecha o ajuste #7 do card 2.3 | 2.1 §5 | 3.3 | baixa (resolvido) |
| 12 | `v_demanda_imediata_aluno`/`v_demanda_imediata` declaram `materiais.ler` sem ler tabela de material; a view só precisa de `alunos.ler` (a tela precisa do nome do material, a view não) | 2.3 §11 | 6.4 | baixa — ✅ **corrigido em 04/09/2026 (card 6.4)**: a linha do §11 de `docs/views-leitura.md` ficou só com `alunos.ler`, e o teste `095` ganhou o perfil `SO_ALUNOS`, que tem **apenas** essa permissão e recebe as duas views **inteiras** (e `v_estoque_atual` vazia, que é a coerência do outro lado). A asserção cai no dia em que a view passar a citar `material` |
| 13 | O `insert` de `aluno_material_hist` não aceitava `alunos.criar`, e o da tabela-mãe `aluno_material` aceitava — assimetria sem consequência enquanto ninguém escrevia histórico na geração. A partir do card 6.2, `fn_trilha_gerar` grava uma linha `GERACAO_COMBO` por item: um perfil com `alunos.criar` e **sem** `alunos.editar_trilha` criaria o aluno e a trilha e falharia no histórico, com erro opaco de RLS numa tela de cadastro que não fala de histórico | §4 (esta tabela) | 6.2 | alta — ✅ **corrigido em 04/09/2026 (card 6.2)**: a política passou a aceitar `alunos.criar`, a mesma condição da tabela-mãe. Nenhum perfil da matriz inicial é assim, e o card 4.2 já deixou escrito que isso não é argumento |

Os itens 1, 3, 5, 6, 7 e 9 são **bloqueantes** no sentido do card 2.2: com eles errados, o sistema
compila, sobe e falha em produção na mão do usuário — vazio, opaco ou aberto demais.

---

## 8. Seed do card 3.6

O seed é **idempotente** e reexecutável, como todo o resto:

1. `insert into permissao (unidade_id, codigo, descricao, dominio)` — as 49 linhas do §3, com
   `on conflict (unidade_id, codigo) do update set descricao = excluded.descricao, dominio =
   excluded.dominio, ativo = true`. A descrição é a coluna "O que autoriza" das tabelas do §3: é
   ela que a tela de Administração mostra ao lado da caixa de marcar, e "estoque.ajustar" sozinho
   não diz a ninguém o que acontece se a caixa for marcada.
2. `insert into perfil` — DIRECAO, PEDAGOGICO, SECRETARIA, MONITOR, `on conflict do nothing`.
3. `insert into perfil_permissao` — a matriz do §5, por `select` cruzando `perfil.codigo` e
   `permissao.codigo`, `on conflict (perfil_id, permissao_id) do nothing`. **Sem `delete`**: o seed
   nunca tira o que a direção marcou na tela depois. Reexecutar o seed acrescenta o que faltar e não
   desfaz configuração.
4. Usuário de direção inicial: criado no Auth pelo Irineu, espelhado em `usuario` pelo card 3.5, e
   ligado ao perfil DIRECAO por `usuario_perfil`.

⚠️ **Ordem obrigatória:** o seed de `permissao` roda **antes** das políticas de RLS entrarem em
vigor com dado real, senão o primeiro usuário não consegue ler nem a própria matriz. Na prática o
card 3.6 roda depois do 3.3/3.4, e o `insert` do seed é feito pela migração (papel `postgres`, fora
de `authenticated`), não por usuário.

---

## 9. Pontos para o Irineu confirmar

1. **Secretaria cadastra salas, PCs, professores e materiais?** A matriz diz que sim (§5.1, itens 5
   e 6). O plano não posiciona esses cadastros; deixar só com a direção trava a operação, mas é uma
   escolha do dono do produto.
2. **Monitor abre manutenção de PC?** Ele é quem vê a máquina quebrada, mas a manutenção derruba a
   capacidade da turma e pode gerar `BLOCO_ACIMA_CAPACIDADE`. Alternativa: monitor abre uma pendência
   e a secretaria registra a manutenção.
3. **Pedagógico enxerga compras?** Hoje não (`compras.ler` fora). Ele vê estoque, como o plano pede,
   mas não o pedido em trânsito.

Nenhum dos três bloqueia os cards seguintes: os três são linhas de `perfil_permissao` no seed do
card 3.6, e mudam com um clique na tela de Administração depois.

---

## 10. O que fica em aberto

1. ~~**Permissão por coluna** (achado #8) — a solução é trigger, não RLS. O desenho fica no card 8.3,
   junto com as funções de certificado.~~ ✅ **RESOLVIDO em 05/09/2026 pelo card 8.3**:
   `tg_certificado_colunas_permitidas`, com a contraprova vermelha registrada no achado #8 acima. O
   desenho generalizou o que os cards 4.2, 5.1, 6.1 e 7.1 já faziam por tabela — onde a permissão é
   por coluna, a RLS é a segunda barreira e o trigger é a primeira.
2. ~~**Log de alteração da matriz.**~~ ✅ **RESOLVIDO em 03/09/2026 pelo card 4.7.5**:
   `perfil_permissao_hist`, escrita por trigger `security definer` em `perfil_permissao`, imutável
   por ausência de política, FKs `restrict`; e `fn_seed_matriz` deixou de devolver o código que
   alguém tirou de todos os perfis. Ficou a **tabela**, não o `ativo = false`: a segunda saída
   mudaria a política desta tabela, o join de `tem_permissao` e o guarda do seed para guardar uma
   transição só. Fonte: `docs/administracao.md` §4. Enunciado original: As Decisões vigentes (§4)
   pedem "log de alterações" como mitigação do risco de permissões mal definidas.
   `perfil_permissao` tem auditoria de `criado_em/por`, mas o `delete` (desmarcar a caixa) não
   deixa rastro.
3. **Perfil por unidade.** `perfil` tem `unidade_id`, então a segunda unidade da Fase 11 terá
   perfis próprios. Se a direção quiser um perfil global, é decisão da Fase 11, não desta.
4. **Importação (tela 13)** entra com `admin.ler` mais os domínios do que importa; o conjunto exato
   é do card 9.1, que sabe o que o arquivo traz.
