<#
.SINOPSE
    Cadeia de execução do board do Gestão IM360 — uma sessão headless por card,
    em sequência, sem acompanhamento humano. Card 5.5,5.

.DESCRICAO
    O driver é FINO de propósito. Ele não sabe o que é um card, não fala com o
    Notion e não decide o que fazer: quem sabe disso é a skill `proxima-tarefa`,
    e duplicar essa lógica aqui criaria duas fontes da verdade que divergiriam
    no primeiro card fora do comum.

    O que o driver faz, e só:
      1. confere que a máquina e o repositório estão em condição de rodar;
      2. abre uma sessão `claude -p` por card, com contexto NOVO a cada uma;
      3. lê a linha de veredito que a sessão imprime no fim;
      4. CONFERE por conta própria que `develop` andou antes de acreditar num
         `CARD_OK` — o relato da sessão não é evidência;
      5. para no primeiro sinal de que precisa de Irineu.

    Contexto novo por card não é detalhe: um card GG já consome sessão inteira,
    e emendar quatro num contexto só degrada a partir do terceiro.

.EXEMPLO
    .\automacao\cadeia.ps1 -Verificar
    Só o diagnóstico do ambiente. Não executa card nenhum.

.EXEMPLO
    .\automacao\cadeia.ps1 -MaxCards 1
    Roda um card e para. É o modo do piloto.

.EXEMPLO
    .\automacao\cadeia.ps1 -MaxCards 30
    Corre a fila até acabar, até dar 30 cards, ou até precisar de Irineu.
#>

[CmdletBinding()]
param(
    # Quantos cards no máximo. O teto existe para uma cadeia com defeito não
    # varrer o board inteiro antes de alguém reparar.
    [int]$MaxCards = 1,

    # Só diagnostica o ambiente e sai.
    [switch]$Verificar,

    # Mostra o que faria, sem abrir sessão nenhuma.
    [switch]$Simular,

    # Arquivo com o texto que cada sessão recebe. Existe para rodar um card
    # específico e para exercitar a mecânica do driver (invocação, captura,
    # leitura do veredito, conferência do SHA) sem gastar um card de verdade.
    [string]$Prompt
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RaizRepo   = Split-Path -Parent $PSScriptRoot
$DirLogs    = Join-Path $PSScriptRoot 'logs'
$ArqHistoria= Join-Path $DirLogs 'cadeia.jsonl'
$ArqPrompt  = if ($Prompt) { $Prompt } else { Join-Path $PSScriptRoot 'prompt-card.md' }

function Escrever($texto, $cor = 'Gray') { Write-Host $texto -ForegroundColor $cor }
function Titulo($texto) { Write-Host ''; Write-Host "── $texto" -ForegroundColor Cyan }

function Registrar($registro) {
    if (-not (Test-Path $DirLogs)) { New-Item -ItemType Directory -Path $DirLogs -Force | Out-Null }
    $registro['quando'] = (Get-Date).ToString('o')
    ($registro | ConvertTo-Json -Compress -Depth 6) | Add-Content -Path $ArqHistoria -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Pré-voo
#
# Cada uma destas checagens existe porque a falha correspondente é SILENCIOSA
# ou ilegível quando acontece no meio da cadeia, às três da manhã.
# ---------------------------------------------------------------------------
function PreVoo {
    $problemas = @()

    foreach ($f in 'claude', 'gh', 'git', 'node') {
        if (-not (Get-Command $f -ErrorAction SilentlyContinue)) {
            $problemas += "'$f' não está no PATH."
        }
    }

    # Docker precisa estar RODANDO, não só instalado: `supabase start` falha com
    # mensagem sobre daemon, e a sessão gastaria uma rodada inteira nisso.
    & docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $problemas += "Docker não está respondendo — o stack local não sobe." }

    & gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $problemas += "'gh' sem autenticação — a sessão não abre PR nem lê o CI." }

    Push-Location $RaizRepo
    try {
        $sujo = & git status --porcelain
        if ($sujo) { $problemas += "Working tree sujo. A cadeia cria branch por card e exige base limpa." }

        $atual = (& git rev-parse --abbrev-ref HEAD).Trim()
        if ($atual -eq 'main') { $problemas += "HEAD está em 'main'. A cadeia nunca trabalha a partir de main." }
    } finally { Pop-Location }

    if (-not (Test-Path $ArqPrompt)) { $problemas += "Falta $ArqPrompt (o texto que cada sessão recebe)." }

    return $problemas
}

# ---------------------------------------------------------------------------
# Uma sessão = um card
# ---------------------------------------------------------------------------
function ExecutarCard($indice) {
    $prompt = Get-Content -Path $ArqPrompt -Raw -Encoding UTF8
    $carimbo = Get-Date -Format 'yyyyMMdd-HHmmss'
    if (-not (Test-Path $DirLogs)) { New-Item -ItemType Directory -Path $DirLogs -Force | Out-Null }
    $arqSaida = Join-Path $DirLogs "card-$carimbo.log"

    Escrever "  sessão $indice — saída em $arqSaida"
    if ($Simular) { return @{ veredito = 'SIMULADO'; linha = '(simulação)'; saida = $arqSaida } }

    Push-Location $RaizRepo
    try {
        # `--permission-mode acceptEdits` aceita edição de arquivo; o que a
        # sessão pode RODAR continua vindo do allow/deny do .claude/settings.json
        # e do hook guarda-destrutivos.mjs. Nada aqui afrouxa isso.
        #
        # ⚠️ NÃO usar `Tee-Object -Encoding`: o parâmetro só existe no PowerShell
        # 6+, e no 5.1 (o que vem no Windows) o bind falha com
        # NamedParameterNotFound ANTES de a sessão abrir. Medido em 03/09/2026,
        # na primeira tentativa de rodar a cadeia. O ForEach abaixo faz as duas
        # coisas que o Tee faria — mostrar e gravar — e grava em UTF-8 de
        # verdade, que é o que o Get-Content da leitura do veredito espera.
        & claude -p $prompt --permission-mode acceptEdits 2>&1 | ForEach-Object {
            $linha = [string]$_
            Write-Host $linha
            Add-Content -Path $arqSaida -Value $linha -Encoding UTF8
        }
        $codigo = $LASTEXITCODE
    } finally { Pop-Location }

    if ($codigo -ne 0) {
        return @{ veredito = 'ERRO_PROCESSO'; linha = "claude saiu com código $codigo"; saida = $arqSaida }
    }

    # A última linha `>>> ` manda. Procurar da última para a primeira evita que
    # um `>>>` citado no meio do relatório seja lido como veredito.
    $linha = Get-Content $arqSaida -Encoding UTF8 |
             Where-Object { $_ -match '^\s*>>>\s+(CARD_OK|CARD_PARADO|CADEIA_FIM)\b' } |
             Select-Object -Last 1

    if (-not $linha) {
        return @{ veredito = 'SEM_VEREDITO'; linha = 'a sessão terminou sem a linha >>> exigida'; saida = $arqSaida }
    }

    $veredito = ([regex]::Match($linha, '>>>\s+(\w+)')).Groups[1].Value
    return @{ veredito = $veredito; linha = $linha.Trim(); saida = $arqSaida }
}

# ---------------------------------------------------------------------------
# Conferir que `develop` andou
#
# Um CARD_OK é RELATO. Esta função é a EVIDÊNCIA — e as duas discordarem é
# exatamente o modo de falha que uma cadeia sem ninguém olhando produz: a
# sessão acredita que mergeou, o board diz concluído, e develop está parado.
# ---------------------------------------------------------------------------
function DevelopAndou($shaAntes) {
    Push-Location $RaizRepo
    try {
        & git fetch origin develop --quiet
        $agora = (& git rev-parse origin/develop).Trim()
        return @{ andou = ($agora -ne $shaAntes); sha = $agora }
    } finally { Pop-Location }
}

function ShaDevelop {
    Push-Location $RaizRepo
    try {
        & git fetch origin develop --quiet
        return (& git rev-parse origin/develop).Trim()
    } finally { Pop-Location }
}

# ---------------------------------------------------------------------------
Titulo 'Pré-voo'
$problemas = @(PreVoo)
if ($problemas.Count -gt 0) {
    foreach ($p in $problemas) { Escrever "  ✗ $p" 'Red' }
    Escrever ''
    Escrever 'Cadeia não iniciada.' 'Red'
    exit 1
}
Escrever '  ✓ ferramentas, Docker, gh, repositório limpo' 'Green'

if ($Verificar) { Escrever ''; Escrever 'Só verificação — nada executado.' 'Yellow'; exit 0 }

Titulo "Cadeia — até $MaxCards card(s)"
$feitos = 0
$parou = $null

for ($i = 1; $i -le $MaxCards; $i++) {
    $shaAntes = ShaDevelop
    Titulo "Card $i de no máximo $MaxCards"

    $r = ExecutarCard $i
    $registro = @{ indice = $i; veredito = $r.veredito; linha = $r.linha; saida = $r.saida }

    switch ($r.veredito) {
        'CARD_OK' {
            $conf = DevelopAndou $shaAntes
            if (-not $conf.andou) {
                # Relato e evidência discordam. Não seguir: o próximo card
                # nasceria de uma base que não tem o card anterior.
                $registro['conferencia'] = 'develop NAO andou apesar do CARD_OK'
                Registrar $registro
                Escrever "  ✗ a sessão relatou merge, mas origin/develop não mudou ($($conf.sha))." 'Red'
                $parou = 'CARD_OK sem merge de verdade em develop'
                break
            }
            $registro['conferencia'] = "develop andou para $($conf.sha)"
            Registrar $registro
            $feitos++
            Escrever "  ✓ $($r.linha)" 'Green'
        }
        'SIMULADO'      { Registrar $registro; Escrever "  · simulação"; }
        'CADEIA_FIM'    { Registrar $registro; $parou = "fim da fila — $($r.linha)" }
        'CARD_PARADO'   { Registrar $registro; $parou = $r.linha }
        'SEM_VEREDITO'  { Registrar $registro; $parou = "$($r.linha) — ver $($r.saida)" }
        'ERRO_PROCESSO' { Registrar $registro; $parou = "$($r.linha) — ver $($r.saida)" }
        default         { Registrar $registro; $parou = "veredito desconhecido: $($r.veredito)" }
    }

    if ($parou) { break }
}

Titulo 'Fim'
Escrever "  cards mergeados em develop nesta corrida: $feitos"
if ($parou) {
    Escrever "  parou porque: $parou" 'Yellow'
} else {
    Escrever "  teto de $MaxCards card(s) atingido — a fila pode ter mais." 'Yellow'
}
Escrever ''
Escrever '  A promoção develop → main continua sua, sempre.' 'Cyan'
Escrever "  Histórico: $ArqHistoria"
