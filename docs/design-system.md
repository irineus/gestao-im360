# Design system Flutter — card 2.7

> **Fonte do design system.** O card 1.9 fechou a identidade (paleta, tipografia, badges no tema
> claro); o card 2.6 fechou a estrutura das 13 telas. Este card fecha **a aplicação**: tokens
> completos nos dois temas (inclusive os badges no escuro, que o 1.9 não definiu), o `ThemeData`
> Material 3, o catálogo de componentes reutilizáveis, os **textos finais de erro e de estado
> vazio** (delegação explícita do 2.6 §1) e os breakpoints como código. Os cards de tela das
> Fases 3–9 consomem este documento e não redecideram nada disto.

Data: 01/09/2026. Base: `docs/identidade-visual.md`, `docs/wireframes.md`,
`docs/regras-negocio-funcoes.md` (§1.2, §6.1, §12), `docs/views-leitura.md` (§4.1),
`docs/permissoes-matriz.md` §6. Contrastes WCAG 2.1 recalculados para todo par novo deste
documento (mesmo método do card 1.9); valores anotados onde aparecem.

---

## 1. Escopo

**Neste documento:** tokens Dart prontos para `lib/theme/`, mapeamento para `ThemeData` (Material 3),
os componentes que o card 2.6 mandou componentizar uma vez (badges, tabela com filtros, formulários,
cards de dashboard, os quatro estados de tela), a hierarquia de botões com a regra
ocultar × desabilitar, e os textos em português de erros e estados vazios.

**Não está aqui, de propósito:**

| Assunto | Dono |
|---|---|
| Criação do projeto Flutter e empacotamento da fonte Inter | card 3.7 (esqueleto do app) |
| Ícone do app, splash e favicon nos tamanhos das lojas | fase de build (Fase 3) — `assets/marca/gestao-im360-simbolo.svg` é a fonte |
| Layout interno de cada tela (que região mostra o quê) | `docs/wireframes.md`, fechado |
| Views e funções que alimentam os componentes | cards 2.2/2.3, fechados |

O código Dart do apêndice (§10) é **especificação executável**: o card 3.7 copia os arquivos para
`lib/theme/` como estão; divergência encontrada na implementação volta como correção aqui, não como
decisão local.

---

## 2. Fundações

### 2.1 Cor — tema claro

Tokens do card 1.9, sem alteração. Papéis de uso (o componente referencia o **papel**, nunca o hex):

| Papel | Token | Hex |
|---|---|---|
| Fundo da aplicação | `grafite-50` | `#F6F7F9` |
| Superfície (card, tabela) | branco | `#FFFFFF` |
| Superfície secundária / cabeçalho de tabela | `grafite-100` | `#ECEEF2` |
| Borda e divisor | `grafite-200` | `#D9DDE5` |
| Texto primário | `grafite-900` | `#171C26` |
| Texto de corpo | `grafite-700` | `#3A4252` |
| Texto secundário | `grafite-500` | `#656F82` |
| Desabilitado / placeholder | `grafite-400` | `#8B94A6` (só ≥ 18 pt como texto informativo) |
| Ação principal / link | `laranja-600` | `#BE4E08` (4,90:1) |
| Ação hover/pressed | `laranja-700` | `#973E09` |
| Marca (nunca texto, nunca botão) | `laranja-500` | `#E2620F` |
| Seleção / realce de linha | `laranja-50` / `laranja-100` | `#FFF4EC` / `#FFE3D0` |
| Sucesso / Atenção / Erro / Info | — | `#1E7A46` / `#8A5A06` / `#B42318` / `#1B5FA8` (fundos tonais no card 1.9 §3.3) |
| FORMADO (violeta própria) | — | `#4C3FA8` |
| Barra lateral / cabeçalho | `grafite-800` | `#262D3A` |

### 2.2 Cor — tema escuro

Tokens do card 1.9 §3.4, completados aqui com os que faltavam (seleção, hover e os badges do §2.4):

| Papel | Hex |
|---|---|
| Fundo da aplicação | `#12161F` |
| Superfície | `#1B2130` |
| Superfície elevada / cabeçalho de tabela | `#262D3A` |
| Borda e divisor | `#333B4B` |
| Texto primário | `#E7EAF0` (15,02:1) |
| Texto secundário | `#A7B0C0` (8,29:1) |
| Desabilitado / placeholder | `#5D6678` (decorativo; nunca portador único de informação) |
| Ação principal / link | `#F2803F` (6,84:1); texto sobre ela `#171C26` (6,45:1) |
| Ação hover/pressed | `#FBA36F` |
| Seleção / realce de linha | `#33241A` (mistura de laranja sobre superfície; decorativo, sempre acompanhada de estado) |
| Sucesso / Atenção / Erro / Info | `#5FD08C` / `#E5B65C` / `#F87A6E` / `#7FB4F0` |
| FORMADO | `#B3A6F2` |

O tema segue o sistema operacional por padrão; o menu do usuário (card 2.6 §3.1) permite fixar
claro/escuro, persistido localmente (`shared_preferences`) — preferência de exibição não é dado de
negócio e não vai ao banco.

### 2.3 Badges de status (preenchido tonal) — dois temas

Regra do card 1.9 §6, que este documento não altera: **status do aluno = preenchido tonal; tipo na
turma = contorno**. O que faltava era o tema escuro; contrastes calculados neste card:

| Status | Claro: texto / fundo | Escuro: texto / fundo | Contraste escuro |
|---|---|---|---|
| ATIVO | `#1E7A46` / `#E6F4EC` | `#5FD08C` / `#1C3535` | 6,76:1 |
| ACELERAR | `#973E09` / `#FFF0E4` | `#F5A468` / `#3A2826` | 6,88:1 |
| STANDBY | `#8A5A06` / `#FCF3E0` | `#E5B65C` / `#332E27` | 7,16:1 |
| TRANCADO | `#3A4252` / `#ECEEF2` | `#A7B0C0` / `#262D3A` | 6,33:1 |
| CANCELADO | `#B42318` / `#FEF3F2` | `#F87A6E` / `#3D212B` | 5,51:1 |
| FORMADO | `#4C3FA8` / `#EEEBFA` | `#B3A6F2` / `#27284E` | 6,44:1 |

### 2.4 Badges de tipo (contorno) — dois temas

| Tipo | Claro (borda e texto) | Escuro (borda e texto) | Contraste escuro sobre superfície |
|---|---|---|---|
| NOVO | `#1E7A46` | `#5FD08C` | 8,33:1 |
| REM | `#656F82` | `#A7B0C0` | 7,36:1 |
| PRE | `#1B5FA8` | `#7FB4F0` | 7,41:1 |
| REP | `#8A5A06` | `#E5B65C` | 8,55:1 |

### 2.5 Tipografia

Inter variável, empacotada como asset (card 3.7), família única. Escala fechada no card 1.9 §4,
aqui mapeada para estilos nomeados — os componentes usam **o nome**, nunca tamanho avulso:

| Estilo | Tamanho/altura | Peso | Uso |
|---|---|---|---|
| `titulo` | 24/32 | 700 | título de tela |
| `subtitulo` | 20/28 | 600 | título de seção, cabeçalho de diálogo |
| `corpo` | 16/24 | 400 | formulário, texto corrido — 16 evita zoom automático no iOS |
| `corpoTabela` | 14/20 | 400 | célula de tabela e lista densa |
| `rotulo` | 14/20 | 500 | rótulo de campo, item de menu, botão |
| `cabecalhoTabela` | 14/20 | 600 | cabeçalho de tabela |
| `apoio` | 12/16 | 400 | legenda, texto de apoio, metadado ("por Débora, 30/08") |
| `numero` | herda | herda + `tnum` | **toda** célula numérica, grade, saldo, contador |

`numero` não é um tamanho: é a obrigação de `FontFeature.tabularFigures()` em tabela, grade de
vagas e valor de estoque (card 1.9 §4). No apêndice, `Tipografia.numero(TextStyle)` aplica o
feature a qualquer estilo.

### 2.6 Espaçamento, raios, elevação, ícones, movimento

- **Espaçamento** em múltiplos de 4: `4 / 8 / 12 / 16 / 24 / 32`. Padding de tela: 24 desktop,
  16 mobile. Espaço entre campos de formulário: 16. Entre cards: 16.
- **Raios:** 6 badge e chip de filtro; 8 botão, campo e card; 12 diálogo e folha inferior.
  Nada de pílula (raio total): num sistema de tabelas, cantos levemente arredondados leem melhor.
- **Elevação:** o sistema é **plano com bordas** — card e tabela com borda `1 px` na cor de
  divisor, sem sombra. Sombra só em o que flutua de verdade: menu aberto, diálogo, folha inferior
  (elevações 2/6/8 do Material). Motivo: sombra em dezenas de linhas e cards vira ruído em tela
  densa e não sobrevive ao tema escuro.
- **Ícones:** Material Symbols (rounded), a família que o Flutter embarca — nenhum pacote de ícone
  de terceiro. Tamanhos 20 (em linha/tabela) e 24 (navegação, botões). Ícone nunca sem rótulo ou
  tooltip, exceto os consagrados do shell (fechar, buscar).
- **Movimento:** transições padrão do Material 3; duração curta (150–250 ms). Skeleton pulsa
  suavemente (§5.6); nenhuma animação carrega significado sozinha.

---

## 3. Breakpoints e shell

As três faixas do card 2.6 §2.1, como código. A faixa é derivada **da largura disponível**
(`LayoutBuilder`), nunca da plataforma — um navegador estreitado vira `mobile` e é assim que se
testa a ergonomia do monitor no desktop.

```dart
enum Faixa { mobile, tablet, desktop }

Faixa faixaDe(double largura) => largura >= 1024
    ? Faixa.desktop
    : largura >= 600 ? Faixa.tablet : Faixa.mobile;
```

| Faixa | Largura | Shell |
|---|---|---|
| `desktop` | ≥ 1024 | menu lateral fixo 240 px (`NavigationDrawer` permanente) |
| `tablet` | 600–1023 | trilho de ícones 72 px (`NavigationRail`) com tooltips |
| `mobile` | < 600 | `NavigationBar` inferior — Alunos · Turmas · Pendências · Mais — + gaveta "Mais" |

- O shell é **um componente** (`ShellIm360`), dono da navegação, do cabeçalho (logotipo + nome da
  unidade) e do menu do usuário; as telas só entregam conteúdo. Itens de navegação filtrados pelo
  conjunto mínimo de cada rota (card 2.4 §6) — item sem permissão não é renderizado.
- Contador de Pendências: badge numérico no item, só severidade ALTA aberta (card 2.6 decisão 5).
- Largura máxima de conteúdo: 1440 px, centrado — em monitor ultrawide a tabela não vira uma tira
  de 3 000 px.
- **Degradação por prioridade de coluna** (card 2.6 decisão 7): cada tabela declara a prioridade
  das colunas; abaixo de um limiar por coluna, as marcadas `†` deixam de ser renderizadas e o
  conteúdo delas migra para a linha secundária do cartão (mobile) ou some (tablet). Rolagem
  horizontal de página é proibida; rolagem horizontal **dentro** de uma tabela específica só como
  último recurso e com sombra indicadora de corte.

---

## 4. Tema Flutter (Material 3)

`useMaterial3: true`, dois `ThemeData` completos gerados dos tokens (§10.4). Decisões de mapeamento
— o que difere do Material padrão e por quê:

1. **`ColorScheme` não é gerado por `ColorScheme.fromSeed`.** Seed geraria tons harmônicos mas
   não os hex verificados do card 1.9; o esquema é montado à mão com os tokens. `primary` =
   ação (`#BE4E08` claro / `#F2803F` escuro), **nunca** a cor de marca `#E2620F`, que reprova AA
   (card 1.9 §3.1) e no tema fica restrita ao logotipo.
2. **Densidade:** `VisualDensity.compact` no desktop/tablet, padrão no mobile — no balcão a
   secretaria quer linhas; no laboratório o monitor quer alvo de 44 px. A densidade vem da faixa,
   junto com o shell.
3. **Botões** (`FilledButton`/`FilledButton.tonal`/`TextButton`/vermelho destrutivo): altura mínima
   40 px desktop, 48 px mobile; raio 8; rótulo peso 500. Sem `ElevatedButton` — plano com bordas.
4. **Campos** (`InputDecorationTheme`): `filled: true` com a superfície secundária, borda 1 px na
   cor de divisor, borda de foco 2 px na cor de ação, borda de erro 2 px na cor de erro; rótulo
   flutuante; texto de apoio/erro em `apoio`. Corpo 16 px sempre (§2.5).
5. **Foco:** anel de 2 px com 2 px de deslocamento em todo controle — `grafite-700` no claro,
   `#F2803F` no escuro (card 1.9 §7). Implementado uma vez no tema (`FocusThemeData` +
   `WidgetState.focused` nos componentes), nunca `outline: none` sem substituto.
6. **`DataTableTheme`:** cabeçalho `cabecalhoTabela` sobre superfície secundária; linha 44 px
   (48 mobile); divisor 1 px; zebra desligada (o realce é de estado, não decorativo); linha
   selecionada/hover com a cor de seleção.
7. **`SnackBar`:** flutuante, raio 8, no desktop ancorada embaixo à esquerda (fora do caminho do
   mouse na tabela). Só para confirmação efêmera (§5.8); erro que exige leitura não vai em snackbar.
8. **Diálogo e folha inferior:** raio 12; no mobile, confirmações de fluxo (resultado de entrega,
   virada REP) são `BottomSheet`, não diálogo central (card 2.6 §6.3).
9. **`Tooltip`:** obrigatório em ícone sem rótulo e no motivo de botão desabilitado; delay 500 ms.

---

## 5. Catálogo de componentes

Cada componente nasce em `lib/widgets/` no card da primeira tela que o usa (§9) e **não é
duplicado** depois. Assinaturas indicativas; o contrato é o comportamento descrito.

### 5.1 `BadgeStatus` e `BadgeTipo`

```dart
BadgeStatus(StatusAluno status)   // preenchido tonal — §2.3
BadgeTipo(TipoTurma tipo)         // contorno 1.5 px, fundo transparente — §2.4
```

- Sempre com o rótulo em texto (cor nunca é o único portador — card 1.9 §7); `rotulo` 12/16
  peso 500, caixa alta, `letterSpacing 0.4`; padding 2×8; raio 6.
- As duas formas **nunca** se misturam (card 1.9 §6): um status não aparece em contorno nem um
  tipo em preenchido, mesmo onde só um dos vocabulários está presente.
- `BadgeTipo` aceita sufixo "pontual" (reposição do dia, card 2.6 §7.2) como texto de apoio ao
  lado, fora do badge.

### 5.2 `TabelaIm360` — tabela com filtros

O componente central do sistema (9 das 13 telas). Envolve a tabela, a barra de filtros e os quatro
estados (§5.6) num contrato único:

```dart
TabelaIm360<T>(
  colunas: [ColunaIm360(titulo, prioridade, numerica, larguraMin, ...)],
  linhas: AsyncValue<List<T>>,          // Riverpod: data / loading / error
  filtros: [...],                       // dropdowns, busca, checkbox — §5.3
  aoTocarLinha: (T) => ...,             // navegação — toda referência é clicável (card 2.6 §3.3)
  estadoVazio: EstadoVazio(...),        // texto específico da tela — §7.2
)
```

- **Colunas numéricas**: alinhadas à direita, `numero` (tnum). Coluna com `prioridade` baixa é a
  `†` do wireframe — some primeiro na degradação (§3).
- **Mobile**: a mesma `TabelaIm360` renderiza **cartões** (título, linha secundária, badge) quando
  a faixa é `mobile` e a tela declara o mapeamento linha→cartão; filtros migram para folha inferior
  com botão "Filtrar (n)" mostrando quantos estão ativos.
- **Linha em alerta**: fundo tonal de atenção/erro **mais ícone** na primeira célula (cor nunca
  sozinha). Saldo negativo usa o par de erro e nunca é ocultado (card 2.3 §4.1).
- **Ordenação** por coluna onde a view permite; indicador no cabeçalho; sem paginação até 500
  linhas (escala da escola) — acima disso, o card da tela decide.

### 5.3 Filtros

- Dropdowns (`[método v] [status v]`) como `DropdownMenu` compacto; busca como campo com ícone e
  limpeza; checkbox de filtro ("só abaixo do mínimo") como `FilterChip`.
- **Filtro é estado da tela, desligável e visível** — a view devolve tudo; quem esconde é a tela
  (card 2.3 §2.3(h)). O estado vazio com filtros ativos sempre oferece "Limpar filtros" (§7.2).
- Filtros ativos sobrevivem à navegação de ida e volta dentro da sessão (estado no provider da
  tela), não à troca de sessão.

### 5.4 Formulários

- Rótulo em cima (nunca placeholder como rótulo); apoio embaixo; obrigatórios marcados com `*` e a
  legenda "\* obrigatório" uma vez no rodapé.
- **Validação local só de formato** (obrigatório, e-mail, número, data): a tela **nunca**
  pré-verifica regra de negócio (card 2.6 decisão 2) — submete e trata o erro pelo `codigo` (§7.1).
  Erro de regra chega como banner no topo do formulário + realce do campo quando o código aponta um
  (`MOTIVO_OBRIGATORIO` → campo motivo).
- Botões no rodapé: primário à direita, "Cancelar" (`TextButton`) à esquerda; em execução, o
  primário mostra progresso e trava reenvio (duplo clique não lança duas entregas).
- Desktop: uma coluna, largura máxima 560 px — formulário largo demais separa rótulo do campo.
  Mobile: tela cheia ou folha inferior, botão primário fixado no rodapé, ≥ 44 px.
- Avisos de consequência (mudar combo, sair de ATIVO, override de capacidade) aparecem **dentro
  do formulário/diálogo**, no par tonal de atenção, antes do botão — texto em §7.3.

### 5.5 `CardDashboard`

Existe em `lib/widgets/card_dashboard.dart` desde 04/09/2026 (antes era privado dentro dos cartões
por método do card 5.9; o card **7.4** foi o primeiro a reusá-lo, na lotação Modular por curso, e o
card 8.7 traz mais cinco).

- Superfície com borda (sem sombra), raio 8, padding 12; título `rotulo` em texto secundário;
  valor principal `titulo` (24/700, tnum); linhas secundárias `corpoTabela` com badge/ícone de
  atenção quando houver (`9 standby ⚠`).
- **O card inteiro é clicável** e navega para a lista filtrada (card 2.6 §5); estado de foco/hover
  do tema. Números secundários com alerta também são alvos individuais.
- Grade: desktop 3 colunas (cards de método), demais blocos em 2; **mobile empilha** na ordem do
  wireframe — largura livre, e não a fixa do desktop, que punha dois cartões lado a lado numa tela
  de 430 px (corrigido em 04/09/2026).

### 5.6 Estados de tela — `EstadoCarregando`, `EstadoVazio`, `EstadoErro`, `EstadoSemAcesso`

Os quatro estados do card 2.6 §2.3, componentizados **uma vez**:

- **`EstadoCarregando`** — skeleton com a silhueta do conteúdo (linhas de tabela, cards), pulso
  suave na cor de superfície secundária; nunca spinner central sozinho em tela de tabela, nunca
  tela branca.
- **`EstadoVazio`** — ícone discreto, uma frase dizendo *por que* pode estar vazio e **uma ação**
  (limpar filtros, criar, ir à tela certa). Textos por tela em §7.2.
- **`EstadoErro`** — mapeia o `codigo` para a mensagem do §7.1; botão "Tentar de novo"; código
  técnico em `apoio` quando não mapeado. Sem stack trace em tela — isso vai ao Sentry.
- **`EstadoSemAcesso`** — tela inteira (deep-link/permissão revogada): "Você não tem acesso a esta
  tela" + o conjunto que falta em `apoio` (diagnóstico, card 2.6 §2.3.4) + botão para o Dashboard.
  Sem dado nenhum da tela por trás. **Dentro de uma aba o texto muda** (04/09/2026): a tela abriu, e
  o que não abre é aquele pedaço — o componente aceita o texto daquela região.

`AsyncValue` do Riverpod liga os quatro: `loading` → skeleton, `error` → `EstadoErro`,
`data` vazio → `EstadoVazio`, `data` → conteúdo.

⚠️ **A política de `retry` do projeto é "não repetir"** (04/09/2026, revisão da fase 05):
`ProviderScope(retry: (_, _) => null)` em `lib/main.dart`, decidido **uma vez** e não tela a tela.
O Riverpod 3 repete sozinho o provider que falhou, com espera crescente, até dez vezes — o estado
passa por `AsyncError` e volta a `AsyncLoading`, e um `.when(error:)` mostra a mensagem e some: a
tela pisca entre erro e esqueleto e termina em "Carregando…" para sempre. Medido no card 5.9.
Desligar é o certo aqui porque (a) toda tela já tem "Tentar de novo", que é o quarto estado do
card 2.6 §2.3, e (b) a falha típica deste app não é transitória — RLS, permissão revogada, erro de
regra —, e repetir esconde o diagnóstico. Com a política desligada, `.when(error:)` volta a ser
seguro; onde houver dúvida, perguntar `hasError` antes continua valendo. **O widget test que
exercita erro precisa passar a mesma política ao `ProviderScope`**, senão mede outro mundo.

### 5.7 Botões — hierarquia e a regra de exibição

| Nível | Componente | Uso |
|---|---|---|
| Primário | `FilledButton` (cor de ação) | a ação da tela (Registrar entrega, Confirmar) — um por região |
| Secundário | `FilledButton.tonal` (superfície secundária) | ações de apoio (Editar, Ver) |
| Terciário | `TextButton` | Cancelar, links de navegação |
| Destrutivo | `FilledButton` vermelho | remover, cancelar pedido, estornar — sempre com diálogo de confirmação |

**Regra única (card 2.6 decisão 1):** sem **permissão** → o botão **não é renderizado**; sem
**estado** → visível e desabilitado com o motivo em tooltip (desktop) e legenda `apoio` (mobile).
O motivo é obrigatório: `DesabilitadoCom(motivo: ...)` é parte do contrato do componente, não um
`onPressed: null` solto.

### 5.8 Confirmações e resultados

- **Confirmação efêmera** (salvou, marcou, resolveu): snackbar 4 s com desfazer quando existir
  (estorno logo após entrega).
- **Resultado que muda o que o usuário fará em seguida** — os três status da entrega
  (`ENTREGUE` / `REORDENADA` / `BLOQUEADA_SEM_ESTOQUE`, card 2.2 §6.1), o veredito da virada REP —
  é **diálogo/folha inferior**, com o texto do §7.3 e link para a pendência criada. Nunca snackbar:
  some antes de ser lido.
- **Confirmação destrutiva/consequente**: diálogo com a consequência dita ("o aluno será removido
  das turmas"), botão primário nomeando a ação ("Remover das turmas", nunca "OK").

---

## 6. Grade de vagas — célula

A grade semanal (telas 2 e 4) não é `TabelaIm360`: é um componente próprio (`GradeVagas`) porque a
célula carrega três informações e dois estados de alerta:

- Célula: método (`apoio`, caixa alta) · `ocupação/capacidade` (`numero`) · professor (`apoio`).
- Estados: normal; **lotado** (ocupação = capacidade — texto em peso 600, sem cor de alerta: lotado
  é fato, não problema); **acima da capacidade** (par de erro + ícone ⚠ — mesmo fato da pendência
  `BLOCO_ACIMA_CAPACIDADE`); **sem professor** (ícone ⚠ no par de atenção); vazia (traço, e com
  `turmas.criar` vira alvo de "criar bloco aqui").
- Numerais tabulares obrigatórios — as colunas de dias alinham.
- Mobile: um dia por vez (**abas Seg–Sáb**), células empilhadas como lista, **abrindo no dia de
  hoje** — a grade de segunda é a resposta errada para quem abre o app na quinta. Vale para as duas
  telas: desde 04/09/2026 as duas usam o mesmo `MatrizSemanal`, e o wireframe §5 (que desenhava
  lista vertical no dashboard) foi corrigido.
- A célula **vazia é alvo nas duas faixas**: no celular também, senão "criar bloco aqui" existe só
  no desktop (corrigido em 04/09/2026).

---

## 7. Textos — erros, vazios e avisos

Português direto, sem jargão técnico, sem culpar o usuário, dizendo **o que aconteceu e o que dá
para fazer**. O Flutter resolve a mensagem pelo `codigo` estável do `DETAIL` (card 2.2 §1.2) —
nunca pelo texto do banco, que pode mudar.

### 7.1 Catálogo `codigo` → mensagem

| `codigo` | Mensagem em tela |
|---|---|
| `SEM_PERMISSAO` | "Você não tem permissão para esta ação." |
| `TRANSICAO_INVALIDA` | "Essa mudança de status não é permitida a partir do status atual." |
| `FORMATURA_SEM_CERTIFICADO` | "Para formar o aluno, o checklist do certificado precisa estar como ENTREGUE — ou a direção pode confirmar mesmo assim." |
| `MOTIVO_OBRIGATORIO` | "Informe o motivo para continuar." |
| `ALUNO_INATIVO` | "Esta ação só vale para aluno ATIVO ou ACELERAR." |
| `METODO_INCOMPATIVEL` | "O método do aluno não é o método desta turma." |
| `BLOCO_LOTADO` | "Esta turma está lotada. Escolha outro horário ou verifique a capacidade da sala." |
| `DATA_PREVISTA_OBRIGATORIA` | "Aluno NOVO precisa de data prevista de início." |
| `TRILHA_JA_EXISTE` | "Este aluno já tem trilha. Para gerar de novo, use a opção de substituir." |
| `TRILHA_COM_ENTREGA` | "A trilha já tem apostila entregue e não pode ser regenerada. Edite a trilha em vez de substituí-la." |
| `ALUNO_SEM_COMBO` | "O aluno não tem combo definido. Informe o combo nos dados do aluno." |
| `ITEM_JA_ENTREGUE` | "Apostila já entregue não pode ser alterada na trilha. Para corrigir, estorne a entrega." |
| `TRILHA_EM_FIM` | "A trilha deste aluno está concluída — não há apostila pendente para entregar." |
| `MATERIAL_FORA_DA_TRILHA` | "Esta apostila não está pendente na trilha do aluno." |
| `MOVIMENTO_JA_ESTORNADO` | "Este movimento já foi estornado." |
| `MOVIMENTO_NAO_ESTORNAVEL` | "Este movimento não pode ser estornado." |
| `PEDIDO_NAO_RECEBIVEL` | "Este pedido não está aguardando recebimento." |
| `RECEBIMENTO_EXCEDE_PEDIDO` | "Quantidade acima do pedido — o recebimento com excedente requer a direção." |
| `PARAMETRO_AUSENTE` | "Um parâmetro do sistema está sem valor: {chave}. Avise a direção (tela de Administração → Parâmetros)." |
| `REP_JA_CONTINUO` | "Este aluno já está como REP contínuo." |
| `REP_NAO_CONTINUO` | "Este aluno não está como REP contínuo." |
| *não mapeado / rede* | "Não foi possível concluir. Tente de novo; se continuar, avise a direção (código {codigo})." |

Regras: mensagens de **validação de campo** aparecem no campo; as demais em banner
(formulário/diálogo) ou `EstadoErro` (tela). `{codigo}` sempre presente no caso não mapeado —
é o que a direção manda para o suporte. `RECEBIMENTO_EXCEDE_PEDIDO` é a tradução que o card 2.6
§10.2 pediu.

### 7.2 Estados vazios por tela

| Tela / região | Sem filtro ativo | Com filtro ativo (quando difere) |
|---|---|---|
| Alunos (lista) | "Nenhum aluno cadastrado. Matricule o primeiro em **+ Matricular**." | "Nenhum aluno com esses filtros — **Limpar filtros**." |
| Ficha → Trilha | "Este aluno não tem trilha. Gere a partir do combo em **Editar trilha**." | — |
| Ficha → Turmas | "O aluno não está em nenhuma turma. **+ Alocar em bloco**." (se ATIVO/ACELERAR, com o aviso de `ALUNO_SEM_TURMA`) | — |
| Ficha → Histórico | "Nenhuma mudança de status registrada." | — |
| Grade de turmas | "Nenhum bloco de horário cadastrado. **+ Novo bloco**." | "Nenhum bloco com esses filtros nesta semana — **Limpar filtros**." |
| Bloco (alunos) | "Nenhum aluno neste bloco nesta data. **+ Adicionar aluno**." (a lotação é de um dia) | — |
| Turmas Modular | "Nenhuma turma Modular. **+ Nova turma**." | idem filtros |
| Materiais/estoque | "Nenhum material cadastrado. **+ Novo material**." | idem filtros |
| Movimentações de material | "Nenhuma movimentação. Entrada de estoque acontece pelo recebimento de pedido, na tela **Compras**." | idem período/tipo |
| Compras → sugerido | "Nada a comprar agora: nenhum material com sugestão maior que zero." + filtro desligável | — |
| Compras → pedidos | "Nenhum pedido. Crie a partir do **Pedido sugerido**." | — |
| Projeção | Rotina ok e sem linhas: "Sem demanda projetada no horizonte atual." **Rotina falhou:** "A projeção não foi calculada — veja a pendência **ROTINA_FALHOU**." (nunca tabela zerada com cara de 'sem demanda' — card 2.6 §11) | — |
| Certificados | "Ninguém chegando ao fim do curso agora." | idem filtros |
| Salas e PCs | "Nenhuma sala cadastrada. **+ Nova sala**." Professores (2ª aba, card 4.5): "Nenhum professor cadastrado. **+ Novo professor**." | idem filtros (card 4.5) |
| Pendências | "Nenhuma pendência aberta." | "Nenhuma pendência com esses filtros — **Limpar filtros**." |
| Administração → usuários | "Só você por aqui. **+ Convidar usuário**." | — |
| Dashboard (região sem dado) | região mostra zero real, nunca some — número que desaparece parece erro | — |
| Dashboard (região que **falhou**) | o erro e o carregamento moram **dentro** do slot da região, nunca no lugar da tela: as pendências abertas e o rodapé não dependem da consulta de vagas (corrigido em 04/09/2026) | — |

### 7.3 Avisos e resultados padronizados

- **Entrega `REORDENADA`:** "Sem estoque de **{pulada}**; foi entregue **{entregue}**. **{pulada}**
  continua pendente e volta a ser a próxima quando houver estoque." + link "Ver pendência".
- **Entrega `BLOQUEADA_SEM_ESTOQUE`:** "Nenhuma apostila da trilha tem estoque. A entrega não foi
  registrada; foi aberta uma pendência de compra." + link.
- **Trilha fechada na entrega:** "Trilha concluída — o checklist de certificado foi aberto."
  + link para a aba Certificado. *(O 🎓 saiu em 04/09/2026, card 6.6 — divergência 13 do §11: o
  glifo não existe em Inter/Roboto e a CSP não deixa baixar fonte de emoji, então ele viraria uma
  caixa vazia. O portão que o pegou é o `texto_de_tela_test`.)*
- **Virada REP sugerida (após lançar reposição):** "Com essa falta, a reposição não cabe mais no
  prazo — foi sugerida a virada para REP contínuo. Quem decide é você, na pendência." + link
  "Executar agora".
- **Mudar combo (formulário de Dados):** "Trocar o combo **não** refaz a trilha do aluno — será
  aberta uma pendência para revisar a trilha." (texto final do apontamento 6 do card 2.6)
- **Sair de ATIVO/ACELERAR:** "O aluno será removido das turmas ao confirmar."
- **Override de capacidade:** "A capacidade calculada pelos PCs desta sala é **{n}**. O valor
  informado substitui esse cálculo."
- **Editar parâmetro `rep_*` / `projecao_*`:** "Vale a partir da próxima execução da rotina diária
  (madrugada)."
- **Desmarcar permissão na matriz:** "A mudança vale imediatamente para todos os usuários do
  perfil."
- **Cabeçalho da Projeção:** "calculada em {calculado_em}" — obrigatório (card 2.6 §11); detalhe ao
  vivo com "o detalhe é de agora e pode diferir do total da madrugada".
- **Carimbo da projeção em Compras → sugerido (card 8.2, 05/09/2026):** a mesma exigência aplicada à
  coluna Projetada, que deixou de valer zero. São **três** textos, um por estado, e a diferença é o
  que impede o zero de mentir:
  - calculada: "Projeção calculada em {dd/mm/aaaa hh:mm}.";
  - **nunca calculada:** "A projeção ainda não foi calculada, então a coluna Projetada está zerada.
    Ela é atualizada pela rotina da madrugada." — nunca um traço mudo, pela mesma razão da linha
    "Projeção" do §7.2: tabela zerada com cara de "sem demanda" é o defeito que o card 2.6 §11
    nomeou;
  - carimbo ilegível: "Não foi possível ler quando a projeção foi calculada." — a conta continua na
    tela, e o que falta é a validade dela.

  Enquanto carrega, **nada** é desenhado: piscar "ainda não foi calculada" por meio segundo diz uma
  coisa falsa. Em 390 px o texto vai num `Flexible` — a frase da projeção não calculada é a mais
  longa das três e, sem isso, estoura a `Row` pela mesma via do item 19 do §11.

---

## 8. Acessibilidade — contrato mínimo

Consolida o card 1.9 §7 no que o componente tem de garantir por construção:

1. Todo par texto/fundo destes tokens passa AA (≥ 4,5:1); os valores estão anotados nos §§2.1–2.4.
   Par novo em card futuro entra **com o contraste calculado**, como aqui.
2. Cor nunca é portador único: badge com rótulo, linha de alerta com ícone, estado com texto.
3. Foco visível em todo controle (§4.5); navegação completa por teclado no desktop (tab, setas na
   tabela, Enter abre linha).
4. Alvo ≥ 44 px em toda ação das jornadas mobile do monitor; 40 px mínimo no desktop compacto.
5. `Semantics` do Flutter: badge anuncia "status ATIVO", célula da grade anuncia "segunda 8h,
   8 de 10 vagas, professor Marcos"; skeleton marcado como carregando.
6. Texto respeita o fator de escala do sistema até 1,3× sem quebra de layout (tabelas degradam
   coluna como no §3).

---

## 9. Estrutura de arquivos e mapa componente → card

```
lib/
  theme/
    cores.dart          // §10.1 — tokens dos dois temas
    tipografia.dart     // §10.2 — estilos nomeados + tnum
    dimensoes.dart      // §10.3 — espaçamento, raios, breakpoints
    tema.dart           // §10.4 — temaClaro / temaEscuro (ThemeData M3)
  widgets/
    shell_im360.dart        // §3   — card 3.7
    badge_status.dart       // §5.1 — card 4.6
    badge_tipo.dart         // §5.1 — card 5.7
    tabela_im360.dart       // §5.2/§5.3 — card 4.4 (a primeira tabela acabou sendo o catálogo, não alunos)
    formulario.dart         // §5.4 — card 4.4
    card_dashboard.dart     // §5.5 — card 5.9
    estados.dart            // §5.6 — card 3.7 (o shell já precisa de SemAcesso)
    grade_vagas.dart        // §6   — card 5.6
    dialogo_resultado.dart  // §5.8 — card 6.6 (entrega é o caso canônico)
  erros/
    catalogo_erros.dart     // §7.1 — card 3.7 (mapa codigo → mensagem, usado por todos)
```

O card que cria cada arquivo é o **primeiro que precisa dele**; os seguintes consomem. `theme/`
inteiro nasce no 3.7 junto com o esqueleto.

---

## 10. Apêndice — tokens Dart

Substitui o apêndice §8 do card 1.9 (que era um esboço): este é o completo. O 3.7 copia como está.

### 10.1 `lib/theme/cores.dart`

```dart
import 'package:flutter/material.dart';

/// Tokens de cor — fonte: docs/identidade-visual.md + docs/design-system.md §2.
/// Nenhum componente usa hex direto: sempre um papel daqui ou do ColorScheme.
abstract final class Cores {
  // marca e ação
  static const marca       = Color(0xFFE2620F); // só logotipo — reprova AA como texto/botão
  static const acao        = Color(0xFFBE4E08);
  static const acaoHover   = Color(0xFF973E09);
  static const acaoEscuro  = Color(0xFFF2803F);
  static const acaoEscuroHover = Color(0xFFFBA36F);

  // grafite (estrutura, tema claro)
  static const grafite50  = Color(0xFFF6F7F9);
  static const grafite100 = Color(0xFFECEEF2);
  static const grafite200 = Color(0xFFD9DDE5);
  static const grafite400 = Color(0xFF8B94A6);
  static const grafite500 = Color(0xFF656F82);
  static const grafite700 = Color(0xFF3A4252);
  static const grafite800 = Color(0xFF262D3A);
  static const grafite900 = Color(0xFF171C26);

  // seleção (claro)
  static const selecao50  = Color(0xFFFFF4EC);
  static const selecao100 = Color(0xFFFFE3D0);

  // semânticos — claro (texto / fundo tonal)
  static const sucesso        = Color(0xFF1E7A46);
  static const sucessoFundo   = Color(0xFFE6F4EC);
  static const atencao        = Color(0xFF8A5A06);
  static const atencaoFundo   = Color(0xFFFCF3E0);
  static const erro           = Color(0xFFB42318);
  static const erroFundo      = Color(0xFFFEF3F2);
  static const info           = Color(0xFF1B5FA8);
  static const infoFundo      = Color(0xFFEAF2FB);

  // tema escuro — estrutura
  static const fundoEscuro       = Color(0xFF12161F);
  static const superficieEscura  = Color(0xFF1B2130);
  static const superficieElevada = Color(0xFF262D3A);
  static const divisorEscuro     = Color(0xFF333B4B);
  static const textoEscuroPrim   = Color(0xFFE7EAF0);
  static const textoEscuroSec    = Color(0xFFA7B0C0);
  static const desabilitadoEscuro = Color(0xFF5D6678);
  static const selecaoEscura     = Color(0xFF33241A);

  // semânticos — escuro
  static const sucessoEscuro = Color(0xFF5FD08C);
  static const atencaoEscuro = Color(0xFFE5B65C);
  static const erroEscuro    = Color(0xFFF87A6E);
  static const infoEscuro    = Color(0xFF7FB4F0);
  // Fundo tonal de erro no escuro — o mesmo par do badge CANCELADO escuro,
  // contraste já verificado no §2.3 (acrescentado em 04/09/2026).
  static const erroFundoEscuro = Color(0xFF3D212B);
  // Fundo tonal de ATENÇÃO no escuro — o mesmo par do badge STANDBY escuro,
  // contraste já verificado no §2.3 (acrescentado em 05/09/2026, card 8.1,5).
  static const atencaoFundoEscuro = Color(0xFF332E27);

  // FORMADO (violeta própria — card 1.9 §6)
  static const formado       = Color(0xFF4C3FA8);
  static const formadoEscuro = Color(0xFFB3A6F2);
}

/// Par texto/fundo de um badge de status, por tema. Contrastes AA verificados
/// (docs/design-system.md §2.3).
class ParBadge {
  final Color texto, fundo;
  const ParBadge(this.texto, this.fundo);
}

abstract final class BadgesStatus {
  static const claro = {
    'ATIVO':     ParBadge(Color(0xFF1E7A46), Color(0xFFE6F4EC)),
    'ACELERAR':  ParBadge(Color(0xFF973E09), Color(0xFFFFF0E4)),
    'STANDBY':   ParBadge(Color(0xFF8A5A06), Color(0xFFFCF3E0)),
    'TRANCADO':  ParBadge(Color(0xFF3A4252), Color(0xFFECEEF2)),
    'CANCELADO': ParBadge(Color(0xFFB42318), Color(0xFFFEF3F2)),
    'FORMADO':   ParBadge(Color(0xFF4C3FA8), Color(0xFFEEEBFA)),
  };
  static const escuro = {
    'ATIVO':     ParBadge(Color(0xFF5FD08C), Color(0xFF1C3535)),
    'ACELERAR':  ParBadge(Color(0xFFF5A468), Color(0xFF3A2826)),
    'STANDBY':   ParBadge(Color(0xFFE5B65C), Color(0xFF332E27)),
    'TRANCADO':  ParBadge(Color(0xFFA7B0C0), Color(0xFF262D3A)),
    'CANCELADO': ParBadge(Color(0xFFF87A6E), Color(0xFF3D212B)),
    'FORMADO':   ParBadge(Color(0xFFB3A6F2), Color(0xFF27284E)),
  };
}

abstract final class BadgesTipo {
  static const claro = {
    'NOVO': Color(0xFF1E7A46),
    'REM':  Color(0xFF656F82),
    'PRE':  Color(0xFF1B5FA8),
    'REP':  Color(0xFF8A5A06),
  };
  static const escuro = {
    'NOVO': Color(0xFF5FD08C),
    'REM':  Color(0xFFA7B0C0),
    'PRE':  Color(0xFF7FB4F0),
    'REP':  Color(0xFFE5B65C),
  };
}
```

### 10.2 `lib/theme/tipografia.dart`

```dart
import 'package:flutter/material.dart';

/// Escala tipográfica — Inter empacotada como asset (card 3.7).
abstract final class Tipografia {
  static const _familia = 'Inter';

  static const titulo = TextStyle(
      fontFamily: _familia, fontSize: 24, height: 32 / 24, fontWeight: FontWeight.w700);
  static const subtitulo = TextStyle(
      fontFamily: _familia, fontSize: 20, height: 28 / 20, fontWeight: FontWeight.w600);
  static const corpo = TextStyle(
      fontFamily: _familia, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w400);
  static const corpoTabela = TextStyle(
      fontFamily: _familia, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w400);
  static const rotulo = TextStyle(
      fontFamily: _familia, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500);
  static const cabecalhoTabela = TextStyle(
      fontFamily: _familia, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600);
  static const apoio = TextStyle(
      fontFamily: _familia, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w400);
  static const badge = TextStyle(
      fontFamily: _familia, fontSize: 12, height: 16 / 12,
      fontWeight: FontWeight.w500, letterSpacing: 0.4);

  /// Numerais tabulares — obrigatório em tabela, grade e valor de estoque.
  static TextStyle numero(TextStyle base) =>
      base.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
```

### 10.3 `lib/theme/dimensoes.dart`

```dart
/// Espaçamento, raios e breakpoints — docs/design-system.md §2.6 e §3.
abstract final class Dim {
  // espaçamento (múltiplos de 4)
  static const e4 = 4.0, e8 = 8.0, e12 = 12.0, e16 = 16.0, e24 = 24.0, e32 = 32.0;

  // raios
  static const raioBadge = 6.0, raio = 8.0, raioDialogo = 12.0;

  // breakpoints (card 2.6 §2.1)
  static const bpTablet = 600.0, bpDesktop = 1024.0;
  static const larguraMenu = 240.0, larguraTrilho = 72.0, larguraConteudoMax = 1440.0;
  static const larguraFormularioMax = 560.0;

  // alvos e alturas
  static const alvoMobile = 44.0, alturaBotao = 40.0, alturaBotaoMobile = 48.0;
  static const alturaLinha = 44.0, alturaLinhaMobile = 48.0;
}

enum Faixa { mobile, tablet, desktop }

Faixa faixaDe(double largura) => largura >= Dim.bpDesktop
    ? Faixa.desktop
    : largura >= Dim.bpTablet ? Faixa.tablet : Faixa.mobile;
```

### 10.4 `lib/theme/tema.dart`

```dart
import 'package:flutter/material.dart';
import 'cores.dart';
import 'dimensoes.dart';
import 'tipografia.dart';

/// ColorScheme montado à mão (não fromSeed): os hex são os verificados
/// em docs/identidade-visual.md — a semente geraria tons não auditados.
const _esquemaClaro = ColorScheme.light(
  primary: Cores.acao,            onPrimary: Colors.white,
  secondary: Cores.grafite700,    onSecondary: Colors.white,
  surface: Colors.white,          onSurface: Cores.grafite900,
  surfaceContainerHighest: Cores.grafite100,
  onSurfaceVariant: Cores.grafite500,
  outline: Cores.grafite200,
  error: Cores.erro,              onError: Colors.white,
  errorContainer: Cores.erroFundo, onErrorContainer: Cores.erro,
  // ⚠️ Sem estes o Flutter devolve `tertiary = secondary` (grafite) e
  // `tertiaryContainer = tertiary`: toda superfície tonal de ATENÇÃO sai
  // grafite escuro (card 8.1,5, item A1).
  tertiary: Cores.atencao,        onTertiary: Colors.white,
  tertiaryContainer: Cores.atencaoFundo, onTertiaryContainer: Cores.atencao,
);

const _esquemaEscuro = ColorScheme.dark(
  primary: Cores.acaoEscuro,      onPrimary: Cores.grafite900,
  secondary: Cores.textoEscuroSec, onSecondary: Cores.grafite900,
  surface: Cores.superficieEscura, onSurface: Cores.textoEscuroPrim,
  surfaceContainerHighest: Cores.superficieElevada,
  onSurfaceVariant: Cores.textoEscuroSec,
  outline: Cores.divisorEscuro,
  error: Cores.erroEscuro,        onError: Cores.grafite900,
  // ⚠️ Sem estes dois o Flutter devolve `error` no lugar de `errorContainer` e
  // toda superfície tonal de erro do tema escuro fica com fundo, borda e texto
  // na mesma cor (achado de 04/09/2026, revisão da fase 05).
  errorContainer: Cores.erroFundoEscuro, onErrorContainer: Cores.erroEscuro,
  // O par de ATENÇÃO do escuro, pela mesma razão (card 8.1,5, item A1).
  tertiary: Cores.atencaoEscuro,  onTertiary: Cores.grafite900,
  tertiaryContainer: Cores.atencaoFundoEscuro,
  onTertiaryContainer: Cores.atencaoEscuro,
);

ThemeData _tema(ColorScheme esquema, {required bool escuro, required bool compacto}) {
  final foco = escuro ? Cores.acaoEscuro : Cores.grafite700; // anel de foco — card 1.9 §7
  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: escuro ? Cores.fundoEscuro : Cores.grafite50,
    fontFamily: 'Inter',
    visualDensity: compacto ? VisualDensity.compact : VisualDensity.standard,
    focusColor: foco,
    dividerTheme: DividerThemeData(color: esquema.outline, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: Size(64, compacto ? Dim.alturaBotao : Dim.alturaBotaoMobile),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Dim.raio)),
        textStyle: Tipografia.rotulo,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: escuro ? Cores.superficieElevada : Cores.grafite100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Dim.raio),
        borderSide: BorderSide(color: esquema.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Dim.raio),
        borderSide: BorderSide(color: esquema.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Dim.raio),
        borderSide: BorderSide(color: esquema.error, width: 2),
      ),
      labelStyle: Tipografia.rotulo,
      helperStyle: Tipografia.apoio,
      errorStyle: Tipografia.apoio,
    ),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: Tipografia.cabecalhoTabela,
      headingRowColor: WidgetStatePropertyAll(esquema.surfaceContainerHighest),
      dataTextStyle: Tipografia.corpoTabela,
      dataRowMinHeight: compacto ? Dim.alturaLinha : Dim.alturaLinhaMobile,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Dim.raioDialogo)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Dim.raio)),
    ),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
  );
}

ThemeData temaClaro({bool compacto = true}) =>
    _tema(_esquemaClaro, escuro: false, compacto: compacto);
ThemeData temaEscuro({bool compacto = true}) =>
    _tema(_esquemaEscuro, escuro: true, compacto: compacto);
```

---

## 11. Decisões e apontamentos deste card

Decisões (resumo para as Decisões vigentes):

1. **Badges no tema escuro definidos e verificados** (§2.3–§2.4) — a lacuna do card 1.9; todos os
   pares ≥ 5,5:1.
2. **`ColorScheme` à mão, nunca `fromSeed`** — a semente geraria tons não auditados; `primary` é a
   cor de ação, jamais a de marca.
3. **Sistema plano com bordas** — sombra só no que flutua (menu, diálogo, folha).
4. **Densidade pela faixa**: compacta no desktop/tablet, padrão no mobile; a mesma origem
   (`faixaDe`) decide shell, densidade e forma da tabela (linhas × cartões).
5. **Estilos tipográficos nomeados** + `Tipografia.numero()` para o tnum obrigatório — componente
   não escolhe tamanho avulso.
6. **Resultado que muda a próxima ação é diálogo/folha, nunca snackbar** (§5.8) — os três status
   da entrega e o veredito REP são os casos canônicos.
7. **Motivo obrigatório em botão desabilitado** é contrato do componente (§5.7), fechando a decisão
   1 do card 2.6 em código.
8. **Textos finais de erro e de estado vazio fechados** (§7) — os cards de tela consomem, não
   redigem. Tradução por `codigo`, com fallback que sempre exibe o código.
9. **Tema claro/escuro segue o sistema, com fixação local** (`shared_preferences`) — preferência de
   exibição não é dado de negócio.

Apontamentos para outros cards (nenhum bloqueante; nenhuma correção a documento anterior):

| # | Apontamento | Card |
|---|---|---|
| 1 | Empacotar Inter (pesos 400–700, variável) como asset e registrar no `pubspec.yaml`; copiar `lib/theme/` deste documento | 3.7 |
| 2 | `catalogo_erros.dart` (§7.1) nasce no 3.7 — o login já trata erro de credencial e rede | 3.7 |
| 3 | Os erros `REP_JA_CONTINUO`/`REP_NAO_CONTINUO` (card 2.5 §8) já estão no catálogo de mensagens; conferir que o card 5.3 os cria com esses códigos | 5.3 |
| 4 | `Semantics` da grade de vagas ("segunda 8h, 8 de 10 vagas…") exige que `v_bloco_vagas_semana`/`fn_grade_semana` continuem devolvendo dia e hora separados | 5.6 |
| 5 | O texto de `PARAMETRO_AUSENTE` cita a tela de Parâmetros — vale para a direção; para os demais perfis o caso não deve ocorrer (depende de `fn_param_int` como `security definer`, ajuste bloqueante já registrado para o card 3.4) | 3.4 |

### Correções vindas da revisão da fase 05 (04/09/2026, card 5.11)

As quatro telas da fase 05 foram construídas sem que **nenhuma** das sessões abrisse este documento
— a causa foi medida e corrigida na origem (`automacao/prompt-card.md` passou a declarar as
especificações vinculantes por `Tipo` de card). O que a revisão encontrou e este documento passou a
dizer com mais precisão:

| # | Correção | Onde |
|---|---|---|
| 6 | **Política de `retry` do Riverpod 3**, decidida uma vez para o projeto — sem ela `.when(error:)` pisca e a tela termina em esqueleto | §5.6 |
| 7 | **`errorContainer`/`onErrorContainer` faltavam no esquema escuro**: o Flutter devolvia `error` no lugar, e fundo, borda e texto de toda superfície tonal de erro ficavam na mesma cor. Nenhum teste e nenhum `analyze` veem isso | §10.1, §10.4 |
| 8 | **Lotado é peso 600, sem cor e sem ícone** — o §6 já dizia, e as duas grades e o cartão do método pintavam de âmbar com `Icons.block`. O alerta gasto ali falta na turma **estourada** | §6 |
| 9 | **Alvos de toque**: células de grade a 32 px, linhas de escolha a 26–28 px, nome do aluno a ~20 px, contra os 40/44 px do §8.4. O componente `LinhaEscolha` passou a ser o "rádio" das três listas de escolha, com semântica de rádio | §8.4, §8.5 |
| 10 | **`Semantics` da célula sem dia e hora**: numa matriz, "Interativo, 8 de 10" não diz *quando*, e quem lê por leitor de tela não tem a coluna à vista | §8.5 |
| 11 | **Jargão interno em texto de usuário** — referência a card do board e código de permissão entre crases. Virou portão automático em `app/test/texto_de_tela_test.dart`, junto com o de glifo fora de Inter/Roboto | §7 |
| 12 | **Vocabulário**: o mesmo objeto era "turma" no cartão e "bloco" no rodapé da mesma tela. O nome é **bloco de horário** | §7 |

### Divergência do card 6.6 (04/09/2026)

| # | Divergência | Como ficou |
|---|---|---|
| 13 | **O 🎓 do §7.3** ("Trilha concluída 🎓 — o checklist de certificado foi aberto") | **Sai o emoji, fica a frase.** O app carrega Inter/Roboto, que não têm o glifo, e a CSP do card 3.8 impede o download de uma fonte de emoji: o que apareceria é uma **caixa vazia** no meio da única frase comemorativa do sistema. Quem reprovou foi o portão do próprio projeto — `app/test/texto_de_tela_test.dart`, criado pela correção 11 acima —, e ele reprovou **antes** de a frase chegar a alguém. O texto em vigor é "…foi entregue. Trilha concluída — o checklist de certificado foi aberto.". Quem quiser o ícone de volta usa um `Icon` do Material ao lado do texto, que é o que a correção 11 já mandava; o caractere não volta |

### Divergências do card 6.7 (04/09/2026) — a linha em alerta e o botão sem guarda

| # | Divergência | Como ficou |
|---|---|---|
| 14 | **"Linha em alerta: fundo tonal … mais ícone na PRIMEIRA célula"** (§5.2) | O fundo tonal é o do §5.2 (`tertiaryContainer` para atenção, `errorContainer` para erro, e agora existe como `TomLinha` no `TabelaIm360`). O **ícone fica na célula do Saldo**, e não na primeira: é onde o wireframe §9 o desenha (`0 ⚠`, `-2 ✖`) e onde ele significa alguma coisa — ao lado do código, o mesmo ícone não diria *de que* o alerta é, numa tela que terá outros alertas. O contrato do §8.2 continua inteiro: forma própria por situação (⚠ atenção, ✖ erro) e a **palavra** no `Semantics` da célula ("Saldo -2, saldo negativo") e no `apoio` do cartão do mobile |
| 15 | **"Sem permissão → o botão não é renderizado"** (§5.7) aplicado ao "Editar material" do painel de estoque | **Exceção estreita e escrita:** o botão não escreve nada — abre o cadastro, que quem tem `materiais.ler` sempre pôde ver (card 4.4, tocando a linha). Desde o card 6.7 a linha abre o painel, então guardá-lo por `materiais.editar` **tiraria uma leitura que já existia**. O rótulo muda com a permissão ("Editar material" / "Ver cadastro"), e o "Salvar" continua guardado pelo próprio formulário. A regra vale para botão de **ação**; navegação para uma tela que já tem guarda própria não é ação |

### Correção vinda do card 6.8 (04/09/2026) — os quatro estados dentro de um painel

| # | Achado | Como ficou |
|---|---|---|
| 16 | **O §5.6 descreve os quatro estados como se eles sempre ocupassem a tela**, e `_Centro` os desenhava com um `Column(mainAxisSize.min)` dentro de um `Center` — sem rolagem | **`EstadoVazio`, `EstadoErro` e `EstadoSemAcesso` passaram a rolar quando não cabem.** Desde o card 6.7 os estados moram também em **painéis**, que ocupam 2/5 da altura ao lado da lista: ali o conjunto ícone (40 px) + frase + "Código: …" + botão não cabe, e o Flutter desenha as listras de overflow **por cima do "Tentar de novo"** — o estado de erro perde a saída exatamente onde a pessoa precisa dela. Medido no `tela_compras_test`, com o painel de itens falhando: `A RenderFlex overflowed by 40 pixels`. A correção é um `SingleChildScrollView` dentro do `Center`: continua centrado, e o scroll só entra quando falta altura. Vale para toda tela e todo painel, presentes e futuros — o defeito não era da tela 7, era do componente |

### Correções e divergências do card 8.1,5 (05/09/2026) — revisão das telas 06 e 07

| # | Achado | Como ficou |
|---|---|---|
| 17 | **`tertiary` e `tertiaryContainer` nunca foram declarados** nos dois esquemas do §10.4 | O `ColorScheme` do Flutter então devolve `tertiary = secondary` (grafite 700) e `tertiaryContainer = tertiary`: **toda superfície tonal de ATENÇÃO do sistema saía grafite escuro**, com o texto da linha em `onSurface` — também grafite. Medido no tema claro: a linha "abaixo do mínimo" de Materiais e a "sugerido > 0" de Compras **ilegíveis**, e o `AvisoTonal` de atenção como caixa grafite com texto branco. É a mesma família do `errorContainer` da correção do card 5.11, e igualmente invisível para `analyze` e para todo teste que não desenhe cor. Os quatro papéis passam a ser declarados nos dois esquemas, com o token novo `Cores.atencaoFundoEscuro` (o fundo do badge STANDBY escuro, contraste já verificado no §2.3), e **`test/tema_test.dart`** assere que nenhum par tonal é herdado por acidente |
| 18 | **A linha em alerta pintava o fundo e deixava o texto na cor da tabela** | O par de contraste verificado é *(container, onContainer)*, e metade dele não estava sendo usada. O `TabelaIm360` passou a envolver a linha num `DefaultTextStyle` com `onTertiaryContainer`/`onErrorContainer` conforme o tom |
| 19 | **Botão desabilitado com motivo estourava a barra de ações no mobile** | No celular o `BotaoAcao` desabilitado acrescenta a legenda embaixo (§5.7) e vira uma `Column` **sem largura** — dentro de uma `Row`, isso é infinito. Medido em 390 px: Compras, `RenderFlex overflowed by 295 px` (537 com mais permissões); Materiais, 135 px. Três correções, e as três valem para todo botão e toda tela: a barra de ações da tabela desceu para uma **segunda linha em `Wrap`**, o rótulo com ícone virou `Flexible` (para quebrar em vez de estourar) e a legenda do motivo só é desenhada quando o pai **dá largura** — onde não dá, o motivo continua no tooltip e na semântica |
| 20 | **A barra de filtros morava dentro do `TabelaIm360`** | As telas 4 (grade) e 5 (acordeão) não usam a tabela e por isso empilhavam os próprios controles à esquerda, com larguras diferentes e **sem a folha "Filtrar (n)"** que todas as outras têm no celular. Ela saiu para `lib/widgets/barra_filtros.dart` (`BarraFiltrosIm360`), com `FiltroSuspenso` e `CampoBusca` ao lado: largura fixa fora do mobile, **largura total** dentro da folha |
| 21 | **`TituloSecao` sem teto de linhas dentro de um painel** | O cabeçalho do painel tem *altura de painel* (2/5 da tela, correção 16): com um rótulo de botão mais largo ao lado, o apoio ganhou uma linha e o painel estourou 12 px, engolindo a lista. Ganhou `maxLinhasApoio` (nulo = sem limite, para quem mora em coluna rolável) e o `apoio` passou a ser **opcional** — enquanto a seção carrega não há contagem a afirmar |
| 22 | **Cabeçalho de painel com título e ações lado a lado em 390 px** | Uma `Row` dá largura **infinita** ao filho não flexível: o `Wrap` das ações não tinha onde quebrar e estourava 80 px. Nasceu `CabecalhoDePainel`, que empilha no celular e mantém lado a lado onde há largura |
| 23 | **Estado de região com altura FIXA** (`_alturaRegiao = 200`) | Virou altura **mínima**: desde a correção 16 os estados rolam, e grampear 200 px só reservava espaço em branco abaixo de um estado curto |
| 24 | **O portão `texto_de_tela_test` varria `card \d` e deixava passar a interpolação** | `'$nome — aba do card $card.'` rendia "Certificado — aba do card 8.6." **na tela** e nada no portão. O padrão passou a `card (\d|\$)`, e os dois textos que ele então reprovou — a aba futura da ficha e o `TelaEmConstrucao` — passaram a dizer "chega numa próxima versão", a mesma frase do rodapé do dashboard. Qual card entrega cada tela continua registrado **no código** (`_cardDaRota`, no roteador), que é onde a informação serve |
| 25 | **Nenhuma tela das fases 06 e 07 tinha teste em 390 px** | É por onde as correções 19 e o `Scaffold.of()` do shell passaram por todo o CI. Cada uma ganhou o teste mobile mínimo — monta em 390×800, `takeException()` nulo, ação primária alcançável —, e a obrigação entrou em `docs/estrategia-testes.md` §13 para todo card de Tela |


---

*Card 2.7 — Fase 2. Fecha a cadeia de design da Fase 2: identidade (1.9) → estrutura (2.6) →
aplicação (2.7). O próximo consumidor é o card 3.7 (esqueleto Flutter).*
