# Gestão IM360 — identidade visual

Card 1.9 do board. Fecha nome, marca, paleta e tipografia do sistema. É a entrada de referência para o card **2.7 (Design de UI e design system Flutter)** e para o card de bundle/ícones da Fase 3.

## 1. Nome e identificadores (já fechados em 31/08/2026)

| Item | Valor |
|---|---|
| Nome do produto | **Gestão IM360** (uso corrente); *GESTÃO IM360* em caixa alta só dentro da marca |
| Domínio | `gestaoim360.com` |
| App id / bundle id | `com.gestaoim360.app` |
| Org Flutter | `com.gestaoim360` |

## 2. Relação com a marca Instituto Mix

O sistema é de um **franqueado**, construído de forma independente; **não é um produto do Instituto Mix**. A identidade foi construída como *inspiração*, não como derivação:

| Herdado da referência | Deliberadamente afastado |
|---|---|
| Família cromática quente (laranja) como cor de marca — é o que a equipe da escola reconhece | O **vermelho institucional** (`#E30B2C` no site) não entra na marca: aqui vermelho é **só** semântica de erro/destrutivo |
| Sem-serifa geométrica de peso alto no logotipo | Superfícies vermelhas full-bleed do site — impraticáveis em telas densas de tabela e grade de turmas |
| Tom direto, sem ornamento | Montserrat (tipografia do site) — trocada por Inter, ver seção 4 |
| — | Símbolo próprio (arco 360°), sem relação com o *pin* do logotipo da franqueadora |

**Regra de uso:** nenhum material do sistema pode exibir o logotipo, o wordmark ou o vermelho institucional do Instituto Mix, nem sugerir endosso da franqueadora. Se o franqueado quiser co-assinatura, isso passa por autorização da franqueadora — está fora do escopo deste card.

## 3. Paleta

Todos os pares de texto abaixo foram calculados em WCAG 2.1 e o valor está anotado. Onde há duas opções, o motivo da escolha está registrado.

### 3.1 Laranja — cor de marca e de ação

| Token | Hex | Uso |
|---|---|---|
| `laranja-50` | `#FFF4EC` | fundo de badge, realce de linha |
| `laranja-100` | `#FFE3D0` | fundo de estado selecionado |
| `laranja-300` | `#FBA36F` | texto/ícone de marca **sobre fundo escuro** (9,11:1) |
| `laranja-400` | `#F2803F` | ação principal **no tema escuro** (6,84:1 sobre fundo escuro) |
| `laranja-500` | `#E2620F` | **cor de marca** — logotipo, elementos gráficos. **Não usar como texto nem como fundo de botão** |
| `laranja-600` | `#BE4E08` | **ação principal no tema claro** — botão preenchido com texto branco (4,90:1) e link (4,90:1) |
| `laranja-700` | `#973E09` | hover/pressed da ação; texto do badge ACELERAR (6,26:1) |
| `laranja-900` | `#4A210A` | reserva |

> **Decisão registrada:** `laranja-500` (`#E2620F`), a cor da marca, tem apenas **3,51:1** contra branco — reprova AA como texto e como fundo de botão. Por isso marca e ação são **tons distintos**: a marca é o 500, a ação é o 600. Não unificar os dois.

### 3.2 Grafite-azulado — estrutura e neutros

| Token | Hex | Uso | Contraste |
|---|---|---|---|
| `grafite-50` | `#F6F7F9` | fundo da aplicação (claro) | — |
| `grafite-100` | `#ECEEF2` | superfície secundária, cabeçalho de tabela | — |
| `grafite-200` | `#D9DDE5` | bordas e divisores | decorativo |
| `grafite-400` | `#8B94A6` | texto desabilitado, placeholder | 3,05:1 — só ≥18pt |
| `grafite-500` | `#656F82` | texto secundário | 5,06:1 AA |
| `grafite-700` | `#3A4252` | texto de corpo | 10,09:1 AAA |
| `grafite-800` | `#262D3A` | barra lateral / cabeçalho de app | branco a 13,83:1 |
| `grafite-900` | `#171C26` | títulos; fundo do símbolo | 17,07:1 AAA |

### 3.3 Semânticos (tema claro)

| Papel | Texto/ícone | Fundo tonal | Contraste |
|---|---|---|---|
| Sucesso | `#1E7A46` | `#E6F4EC` | 4,71:1 AA |
| Atenção | `#8A5A06` | `#FCF3E0` | 5,37:1 AA |
| Erro / destrutivo | `#B42318` | `#FEF3F2` | 6,05:1 AA |
| Informação | `#1B5FA8` | `#EAF2FB` | 5,72:1 AA |

### 3.4 Tema escuro

| Papel | Hex | Contraste sobre `#12161F` |
|---|---|---|
| Fundo da aplicação | `#12161F` | — |
| Superfície | `#1B2130` | — |
| Superfície elevada | `#262D3A` | — |
| Divisor | `#333B4B` | decorativo |
| Texto primário | `#E7EAF0` | 15,02:1 AAA |
| Texto secundário | `#A7B0C0` | 8,29:1 AAA |
| Ação principal | `#F2803F` (texto `#171C26` sobre ela, 6,45:1) | 6,84:1 AA |
| Sucesso / Atenção / Erro / Info | `#5FD08C` / `#E5B65C` / `#F87A6E` / `#7FB4F0` | 9,38 / 9,63 / 6,90 / 8,35 |

O tema escuro é entregue desde o início porque o monitor usa o sistema no celular, no laboratório, com iluminação variável.

## 4. Tipografia

**Inter** (variável), família única, empacotada como asset — sem CDN, para o app funcionar offline e para não depender de terceiro no Cloudflare Pages.

Montserrat, do site de referência, foi descartada por motivo funcional além do afastamento de marca: é uma geométrica de display, com dígitos de largura estreita e pouca diferenciação entre `1`/`l` e `0`/`O` em corpo pequeno — ruim para as telas deste sistema, que são majoritariamente tabelas de códigos de aluno, códigos de material e quantidades.

- **Numerais tabulares obrigatórios** (`font-feature-settings: 'tnum'`) em toda tabela, grade de turma e valor de estoque: as colunas têm de alinhar na vertical.
- Escala: 12 / 14 / 16 / 20 / 24 / 32 px. Corpo de tabela 14; corpo de formulário 16 (evita zoom automático em iOS).
- Pesos: 400 corpo, 500 rótulo, 600 cabeçalho de tabela, 700 título e marca.

## 5. Logotipo

Arquivos em `assets/marca/`:

| Arquivo | Uso |
|---|---|
| `gestao-im360-horizontal.svg` | assinatura principal — login, cabeçalho, documentos |
| `gestao-im360-simbolo.svg` | ícone do app, favicon, avatar, espaços pequenos |
| `gestao-im360-mono.svg` | uma cor via `currentColor` — impressão, marca d'água, fundo colorido |

**Construção:** quadrado de cantos arredondados em `grafite-900`, arco de 360° **aberto no quadrante superior direito** em `laranja-500` — o giro em curso, não o ciclo fechado — e o monograma `IM` em branco. Na assinatura horizontal, `GESTÃO` em `grafite-500` com entreletra aberta sobre `IM` (`grafite-900`) + `360` (`laranja-600`).

**Regras de uso:** área de proteção = metade da altura do símbolo em todos os lados; tamanho mínimo do símbolo 24 px e da assinatura horizontal 120 px de largura; não recolorir, não inclinar, não aplicar sombra, não recompor o wordmark em outra fonte.

⚠️ **Ponto em aberto:** os SVGs usam `<text>` com Inter. Antes de qualquer uso externo (loja, favicon gerado, material impresso), o wordmark deve ser **convertido em contornos** (`text-to-path`) — senão a marca muda de forma em máquina sem a fonte instalada. Para o app, o risco não existe porque a fonte vai empacotada.

## 6. Cores de estado — vocabulário do domínio

O sistema tem dois vocabulários de estado que aparecem lado a lado na mesma tela e **não podem se confundir**. A separação é de forma, não só de cor: **status do aluno = badge preenchido tonal; tipo na turma = badge de contorno.** Assim continuam distinguíveis em impressão P&B e para daltônicos.

### Status do aluno (preenchido tonal)

| Status | Texto | Fundo | Contraste |
|---|---|---|---|
| ATIVO | `#1E7A46` | `#E6F4EC` | 4,71:1 |
| ACELERAR | `#973E09` | `#FFF0E4` | 6,26:1 |
| STANDBY | `#8A5A06` | `#FCF3E0` | 5,37:1 |
| TRANCADO | `#3A4252` | `#ECEEF2` | 8,69:1 |
| CANCELADO | `#B42318` | `#FEF3F2` | 6,05:1 |
| FORMADO | `#4C3FA8` | `#EEEBFA` | 6,93:1 |

FORMADO recebe cor própria (violeta) em vez de reaproveitar o verde de ATIVO: são os dois estados "bons" do aluno e precisam ser distinguíveis num filtro de lista.

### Tipo na turma (contorno, fundo transparente)

| Tipo | Cor da borda e do texto |
|---|---|
| NOVO | `#1E7A46` |
| REM | `#656F82` |
| PRE | `#1B5FA8` |
| REP | `#8A5A06` |

## 7. Foco e acessibilidade

- Anel de foco visível em **todo** controle: 2 px `grafite-700` no tema claro, 2 px `laranja-400` no escuro, com 2 px de deslocamento. Nunca `outline: none` sem substituto.
- Cor nunca é o único portador de informação: badge sempre com rótulo em texto; linha em alerta na tabela recebe ícone além do fundo tonal.
- Alvo de toque mínimo 44 × 44 px nas telas do monitor (registrar entrega, marcar financeiro OK).

## 8. Apêndice — tokens para o Flutter

Pronto para o card 2.7; ainda não há projeto Flutter no repositório.

```dart
// lib/theme/cores.dart
abstract final class Cores {
  static const marca        = Color(0xFFE2620F); // só marca — reprova AA como texto
  static const acao         = Color(0xFFBE4E08);
  static const acaoHover    = Color(0xFF973E09);
  static const acaoEscuro   = Color(0xFFF2803F);

  static const grafite50    = Color(0xFFF6F7F9);
  static const grafite100   = Color(0xFFECEEF2);
  static const grafite200   = Color(0xFFD9DDE5);
  static const grafite400   = Color(0xFF8B94A6);
  static const grafite500   = Color(0xFF656F82);
  static const grafite700   = Color(0xFF3A4252);
  static const grafite800   = Color(0xFF262D3A);
  static const grafite900   = Color(0xFF171C26);

  static const sucesso      = Color(0xFF1E7A46);
  static const atencao      = Color(0xFF8A5A06);
  static const erro         = Color(0xFFB42318);
  static const info         = Color(0xFF1B5FA8);
  static const formado      = Color(0xFF4C3FA8);
}

final temaClaro = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme.light(
    primary: Cores.acao,
    onPrimary: Colors.white,
    secondary: Cores.grafite700,
    surface: Colors.white,
    onSurface: Cores.grafite900,
    error: Cores.erro,
  ),
  scaffoldBackgroundColor: Cores.grafite50,
  fontFamily: 'Inter',
);
```

## 9. O que este card não fecha

- **Aplicação nas telas** (componentes, tabelas, formulários, estados vazios, breakpoints): card **2.7**.
- **Ícone do app nas lojas e splash screen** nos tamanhos exigidos: fase de build (Fase 3) — o `simbolo.svg` é a fonte.
- **Fotografia e ilustração:** o sistema é interno e não usa; se um dia usar, definir então.

---

*Card 1.9 — Fase 1. Referência cromática colhida em `institutomix.com.br` em 31/08/2026 para efeito de inspiração e afastamento deliberado.*
