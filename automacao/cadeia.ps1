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
    [string]$Prompt,

    # Ferramentas pré-autorizadas nas sessões da cadeia.
    #
    # ⚠️ `--permission-mode acceptEdits` cobre EDIÇÃO DE ARQUIVO e **não**
    # ferramenta de MCP — medido em 03/09/2026, quando a primeira corrida real
    # parou por três chamadas negadas ao Notion. Sem board não há card a
    # escolher nem status a gravar, então toda sessão da fila bateria na mesma
    # parede.
    #
    # A concessão fica AQUI, e não no `permissions.allow` do
    # `.claude/settings.json`, de propósito: assim ela vale só para a cadeia, e
    # a sessão interativa continua perguntando como sempre. Menos privilégio, e
    # no arquivo de quem usa.
    [string[]]$FerramentasPermitidas = @('mcp__claude_ai_Notion')
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ⚠️ As duas linhas são necessárias e fazem coisas DIFERENTES no PowerShell 5.1:
# `[Console]::OutputEncoding` governa a LEITURA da saída de um processo nativo;
# `$OutputEncoding` governa o que se ESCREVE ao canalizar de um nativo para
# outro — e o padrão dele no 5.1 é **ASCII**. Sem esta segunda linha, a saída do
# `claude` era reescrita em ASCII a caminho do filtro e "fumaça" chegava como
# "fuma?a" (medido em 03/09/2026, na estreia da narração ao vivo). Um relatório
# de card em português inteiro passa por aqui.
#
# `$OutputEncoding` (o que o PowerShell ESCREVE ao canalizar para um processo
# nativo) não aparece mais aqui: com o `executar-sessao.mjs` abrindo o `claude`
# por conta própria, o PowerShell deixou de escrever na entrada de qualquer
# nativo. As duas armadilhas que ele trouxe — o padrão ASCII e o BOM do
# `[System.Text.Encoding]::UTF8` — estão registradas em `docs/cadeia-execucao.md`
# §7.1, porque somem do código mas não da memória de quem mexer nisto depois.

$RaizRepo   = Split-Path -Parent $PSScriptRoot
$DirLogs    = Join-Path $PSScriptRoot 'logs'
$ArqHistoria= Join-Path $DirLogs 'cadeia.jsonl'
$ArqPrompt  = if ($Prompt) { $Prompt } else { Join-Path $PSScriptRoot 'prompt-card.md' }
$ExecutorSessao = Join-Path $PSScriptRoot 'executar-sessao.mjs'

# O `claude` do PATH é um atalho `.ps1`/`.cmd` do npm. O executor prefere o
# `.exe` de verdade: assim o `spawn` corre sem shell, e um prompt de milhares de
# caracteres não precisa ser citado — que é onde esse tipo de invocação quebra.
function ResolverExecutavelClaude {
    $atalho = (Get-Command claude -ErrorAction SilentlyContinue)
    if (-not $atalho) { return $null }
    $exe = Join-Path (Split-Path $atalho.Source) 'node_modules/@anthropic-ai/claude-code/bin/claude.exe'
    if (Test-Path $exe) { return $exe }
    return $atalho.Source
}

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
    if (-not (Test-Path $ExecutorSessao)) { $problemas += "Falta $ExecutorSessao (quem abre e narra a sessão)." }
    if (-not (ResolverExecutavelClaude)) { $problemas += "Nao consegui resolver o executavel do claude a partir do PATH." }

    # ⚠️ Enquanto o diretório não for CONFIADO, o CLI IGNORA as entradas de
    # `permissions.allow` do `.claude/settings.json` inteiras — e sessão headless
    # não tem a quem pedir aprovação. O card falharia por permissão parecendo
    # defeito de código. Medido em 03/09/2026, na primeira corrida com a CLI
    # recém-instalada: "Ignoring 22 permissions.allow entries".
    $arqCli = Join-Path $HOME '.claude.json'
    if (Test-Path $arqCli) {
        try {
            $cfg = Get-Content $arqCli -Raw -Encoding UTF8 | ConvertFrom-Json
            $chave = ($RaizRepo -replace '\\', '/')
            $proj = $cfg.projects.PSObject.Properties[$chave]
            if (-not $proj -or -not $proj.Value.hasTrustDialogAccepted) {
                $problemas += "Diretorio nao confiado pela CLI: o allow do .claude/settings.json seria IGNORADO e a sessao headless travaria pedindo permissao. Rode 'claude' interativamente aqui uma vez e aceite o dialogo de confianca."
            }
        } catch {
            $problemas += "Nao foi possivel ler $arqCli para conferir a confianca do diretorio: $($_.Exception.Message)"
        }
    }

    # ⚠️ SONDA DE VERDADE, e ela existe por um motivo medido: `claude -p` sem
    # login imprime "Not logged in · Please run /login" e **sai com código 0**
    # (03/09/2026). Sem esta sonda a cadeia abriria a sessão do card, receberia
    # isso, não acharia veredito e reportaria SEM_VEREDITO — diagnóstico
    # indireto para um problema de um minuto. Custa uma chamada mínima por
    # corrida, contra até 30 cards; e de quebra prova que a CLI responde, não só
    # que existe no PATH.
    # A sonda NÃO se contenta em ver a CLI responder: ela manda a sessão CHAMAR
    # o Notion, porque é isso que todo card faz na primeira coisa que executa.
    # Medido em 03/09/2026: com a CLI logada, confiada e respondendo, a primeira
    # corrida real ainda morreu — o MCP era negado, e a descoberta custou uma
    # sessão inteira. Sonda que mede a CLI e não o board mediria o degrau errado.
    # ⚠️ A instrucao e ASSIM DE INSISTENTE por medida: a primeira versao pedia
    # "responda apenas PRONTO" e a sessao devolveu uma TABELA com os resultados
    # da busca. A chamada tinha funcionado — a sonda e que reprovou por causa do
    # formato. Sonda que reprova quando o sistema esta bom ensina a ignorar
    # vermelho, que e o pior defeito que uma checagem pode ter.
    $perg = 'RESPONDA COM UMA UNICA PALAVRA E NADA MAIS. ' +
            'Chame a ferramenta de busca do Notion procurando por "Roadmap de Construcao". ' +
            'Se a chamada responder, sua resposta inteira e exatamente: PRONTO. ' +
            'Se for negada ou falhar, sua resposta inteira e exatamente: NEGADO. ' +
            'Nao escreva tabelas, listas, explicacoes, nem os resultados da busca.'

    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $sonda = (& claude -p $perg --permission-mode acceptEdits --allowedTools @FerramentasPermitidas 2>&1 | Out-String)
    } catch {
        $sonda = "falhou: $($_.Exception.Message)"
    } finally { $ErrorActionPreference = $eap }

    # ⚠️ A asserção procura MARCADOR DE FALHA, não token de sucesso. Duas
    # tentativas de exigir a palavra exata reprovaram com o sistema BOM: a
    # sessão devolveu uma tabela numa, e "OK" na outra. O que a sonda precisa
    # distinguir é bem definido — CLI sem login e MCP negado têm texto próprio —
    # enquanto "sucesso" pode ser escrito de mil maneiras. Exigir a forma do
    # sucesso é o caminho curto para uma checagem que ninguém mais lê.
    $marcaFalha = "Not logged in|haven't granted|hasn't granted|requested permissions|" +
                  'permission denied|NEGADO|no such tool|not authorized'

    if ($sonda -match $marcaFalha -or -not $sonda.Trim()) {
        # O aviso de confiança e o rastro do PowerShell vêm ANTES do motivo real
        # e o empurrariam para fora do resumo — a confiança já tem linha própria
        # acima, e o que falta descobrir aqui é a outra causa.
        $ruido = 'Ignoring \d+ permissions|Run Claude Code interactively|hasTrustDialogAccepted|^\s*\+|CategoryInfo|FullyQualifiedErrorId|^\S+\.ps1:\d+|^No .*:\d+ caractere'
        $resumo = (($sonda -split "`r?`n" |
                    Where-Object { $_.Trim() -and $_ -notmatch $ruido } |
                    Select-Object -First 2) -join ' | ')
        if (-not $resumo) { $resumo = '(sem saida legivel)' }
        $problemas += "Sonda reprovada — a sessao nao chegou ao Notion (login? MCP negado?). Devolveu: $resumo"
    }

    return $problemas
}

# ---------------------------------------------------------------------------
# Uma sessão = um card
# ---------------------------------------------------------------------------
function ExecutarCard($indice) {
    # O prompt não é lido aqui: quem o lê é o executor, que também abre o
    # processo. Passá-lo por argumento do PowerShell reintroduziria o problema
    # de citação que o `.exe` resolvido justamente evita.
    $exeClaude = ResolverExecutavelClaude
    $carimbo = Get-Date -Format 'yyyyMMdd-HHmmss'
    if (-not (Test-Path $DirLogs)) { New-Item -ItemType Directory -Path $DirLogs -Force | Out-Null }
    $arqSaida = Join-Path $DirLogs "card-$carimbo.log"
    $arqBruto = Join-Path $DirLogs "card-$carimbo.jsonl"

    Escrever "  sessão $indice — saída em $arqSaida"
    if ($Simular) { return @{ veredito = 'SIMULADO'; linha = '(simulação)'; saida = $arqSaida } }

    # ⚠️ `$ErrorActionPreference = 'Stop'` (o padrão deste script) transforma
    # QUALQUER linha que o `claude` escreva em stderr num erro TERMINANTE, e o
    # driver morre antes de gravar uma linha do log. Medido em 03/09/2026: o CLI
    # avisou sobre a confiança do diretório, o `2>&1` transformou o aviso em
    # NativeCommandError e a corrida acabou ali, com o log vazio. Um CLI escreve
    # aviso em stderr o tempo todo — parar por causa disso seria trocar toda a
    # cadeia por um diagnóstico que nem é do card.
    $eapAnterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

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
        # ⚠️ QUEM ABRE O `claude` É O NODE, e isso não é rodeio — é a correção do
        # defeito que a primeira corrida de verdade expôs.
        #
        # A versão anterior fazia `claude … | node filtro.mjs` numa pipeline do
        # PowerShell. Quando o PowerShell canaliza um nativo para outro nativo,
        # ele escreve na entrada do segundo em BLOCOS e só descarrega quando o
        # primeiro termina: numa sessão de 3 segundos tudo sai junto e a narração
        # parece funcionar; numa de 40 minutos não sai NADA até o fim. Ou seja, o
        # conserto do buffer do `claude` só tinha mudado o buffer de lugar.
        #
        # Com o node abrindo o processo, o pipe é do sistema operacional e o
        # PowerShell só CONSOME a saída — o lado que ele sempre transmitiu linha
        # a linha. O executor devolve o código do `claude`, ou 3 quando a sessão
        # termina sem evento `result`.
        & node $ExecutorSessao $exeClaude $ArqPrompt $arqSaida $arqBruto @FerramentasPermitidas |
            ForEach-Object { Write-Host ([string]$_) }
        $codigo = $LASTEXITCODE
    } finally {
        Pop-Location
        $ErrorActionPreference = $eapAnterior
    }

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
