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
    [string[]]$FerramentasPermitidas = @('mcp__claude_ai_Notion'),

    # Modelo das sessões. Vazio = o padrão da CLI (hoje Opus 5, que foi o que
    # rodou a primeira corrida). Aceita alias ('opus', 'fable', 'sonnet').
    [string]$Modelo,

    # Em vez de executar cards, abre UMA sessão de revisão da fase inteira.
    # Ver `automacao/prompt-revisao-fase.md` e o §7.2 de docs/cadeia-execucao.md.
    [switch]$RevisarFase,

    # Teto de utilização da janela de 5 h. Acima disto o driver não começa card
    # novo — espera. 0.92 deixa folga para a estimativa errar para menos sem
    # matar a sessão no meio, que é o desfecho caro.
    [double]$TetoJanela = 0.92
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Esta linha governa a LEITURA da saída de um processo nativo, e é a única de
# encoding que o script ainda precisa.
#
# Havia uma segunda, `$OutputEncoding`, que governa o que o PowerShell ESCREVE
# ao canalizar de um nativo para outro. Ela saiu junto com a pipeline: quem abre
# o `claude` agora é o `executar-sessao.mjs`, e o PowerShell não escreve mais na
# entrada de nativo nenhum. As duas armadilhas que ela trouxe — o padrão **ASCII**
# do `$OutputEncoding` no 5.1, que fazia "fumaça" chegar como "fuma?a", e o
# **BOM** do `[System.Text.Encoding]::UTF8`, que quebrava o `JSON.parse` só da
# primeira linha — estão em `docs/cadeia-execucao.md` §7.1. Somem do código, não
# da memória de quem mexer nisto depois.

$RaizRepo   = Split-Path -Parent $PSScriptRoot
$DirLogs    = Join-Path $PSScriptRoot 'logs'
$ArqHistoria= Join-Path $DirLogs 'cadeia.jsonl'
$ArqLimite  = Join-Path $DirLogs 'limite.json'   # último rate_limit_info visto
$ArqPrompt  = if ($Prompt) { $Prompt }
              elseif ($RevisarFase) { Join-Path $PSScriptRoot 'prompt-revisao-fase.md' }
              else { Join-Path $PSScriptRoot 'prompt-card.md' }

# A revisão é UMA sessão que olha a fase inteira, não uma por card. Ela não
# mergeia nada: encerra com `CADEIA_FIM` depois de criar o card de correções,
# e por isso reusa o caminho de parada que já existe, sem laço.
if ($RevisarFase) { $MaxCards = 1 }
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
$script:avisos = @()

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

    # ⚠️ AVISO, não problema: a cadeia roda sem isto, mas roda PIOR, e do jeito
    # silencioso — foi o que aconteceu na primeira corrida de 6 cards.
    #
    # As sessões não conseguiram subir o stack local uma única vez (`supabase
    # test db`: ZERO tentativas em 6 cards) e caíram para "o CI é o portão".
    # O CI de fato roda a suíte, então correção continuou medida; o que se perdeu
    # foi a CONTRAPROVA por sabotagem NO BANCO, que não existe sem stack na
    # máquina. ⚠️ A do Flutter continuou acontecendo — o log do card 5.9 mostra
    # "sabotagem das duas asserções centrais, antes de aceitá-las" —, e dizer que
    # a disciplina inteira caiu seria exagerar o estrago. Os cards relataram a
    # degradação; mas quem lê o relatório já gastou a sessão.
    #
    # A checagem é ESTÁTICA de propósito: lê o allow e responde se uma sessão
    # CONSEGUIRIA. Custa milissegundos e nenhuma chamada de API.
    $regras = @()
    try {
        $regras = (Get-Content (Join-Path $RaizRepo '.claude/settings.json') -Raw -Encoding UTF8 |
                   ConvertFrom-Json).permissions.allow
    } catch { }

    $temSupabaseGlobal = [bool](Get-Command supabase -ErrorAction SilentlyContinue)
    $cobreSupabase = if ($temSupabaseGlobal) { [bool]($regras -match '^Bash\(supabase') }
                     else { [bool]($regras -match '^Bash\(npx') }
    $cobreDocker = [bool]($regras | Where-Object { $_ -match '^Bash\(docker' -and $_ -notmatch '^Bash\(docker ps' })

    if (-not $cobreSupabase) {
        $comoInvoca = if ($temSupabaseGlobal) { 'supabase' } else { 'npx supabase (nao ha supabase global nesta maquina)' }
        $script:avisos += "As sessoes NAO vao rodar a suite pgTAP local: o allow nao cobre '$comoInvoca'. O portao do BANCO vira so o CI, e a contraprova por sabotagem no banco deixa de ser possivel — a dos testes Flutter continua valendo, e as sessoes a fizeram."
    }
    if (-not $cobreDocker) {
        $script:avisos += "O allow so permite 'docker ps'. Sem 'docker info'/'docker --version' a sessao conclui que Docker nao existe e nem tenta o stack local."
    }
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
        $extras = @()
        if ($Modelo) { $extras += @('--model', $Modelo) }
        & node $ExecutorSessao $exeClaude $ArqPrompt $arqSaida $arqBruto $ArqLimite `
               @extras @FerramentasPermitidas |
            ForEach-Object {
                # O executor emite `Cor<TAB>texto`. Ver o comentário do `COR` em
                # executar-sessao.mjs: ANSI sairia cru por esta pipeline.
                $partes = ([string]$_) -split "`t", 2
                if ($partes.Count -eq 2) { Write-Host $partes[1] -ForegroundColor $partes[0] }
                else { Write-Host ([string]$_) }
            }
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
# Orçamento da janela de 5 horas
#
# O limite não é de dinheiro, é de UTILIZAÇÃO da janela — e a CLI informa as
# duas pontas em todo evento: `utilization` (0 a 1) e `resetsAt`. Medido na
# corrida de 04/09/2026, subindo 0,40 → 0,51 → 0,72 conforme os cards passavam.
#
# A conta é feita ANTES de abrir o card, nunca depois: sessão que morre no meio
# deixa branch criada, arquivos escritos e talvez PR aberto, e retomar isso
# automaticamente é adivinhação. Parar antes de começar é determinístico.
#
# ⚠️ As três leituras observadas trouxeram o MESMO `resetsAt`, o que indica
# janela FIXA e não deslizante — esperar até o reset é exato. Ainda assim a
# reavaliação é de 10 em 10 minutos, como Irineu pediu: se a janela for
# deslizante em algum plano, o laço aproveita a folga que for surgindo; se for
# fixa, ele apenas dorme até o reset em passos. Custa nada nos dois casos.
# ---------------------------------------------------------------------------

# Consumo médio de janela e duração por card, a partir do histórico.
function MediaPorCard {
    $medidos = @()
    if (Test-Path $ArqHistoria) {
        foreach ($l in Get-Content $ArqHistoria -Encoding UTF8) {
            if (-not $l.Trim()) { continue }
            try { $r = $l.TrimStart([char]0xFEFF) | ConvertFrom-Json } catch { continue }
            if ($r.veredito -eq 'CARD_OK' -and $r.janelaGasta -gt 0) {
                $medidos += [pscustomobject]@{ janela = [double]$r.janelaGasta; minutos = [double]$r.minutos }
            }
        }
    }

    if ($medidos.Count -ge 2) {
        return @{
            janela  = ($medidos | Measure-Object janela  -Average).Average
            minutos = ($medidos | Measure-Object minutos -Average).Average
            base    = "$($medidos.Count) card(s) medido(s)"
        }
    }

    # Padrão até haver medida própria: o que a corrida de 04/09/2026 mostrou —
    # ~0,11 de janela e ~31 min por card, seis cards de 5.6 a 6.1.
    return @{ janela = 0.11; minutos = 31.0; base = 'padrão da corrida de 04/09 (sem medida local ainda)' }
}

# Lê o último estado da janela. Devolve $null quando ainda não há leitura.
function EstadoJanela {
    if (-not (Test-Path $ArqLimite)) { return $null }
    try {
        $j = Get-Content $ArqLimite -Raw -Encoding UTF8 | ConvertFrom-Json
        $uso = $j.unifiedWindows.five_hour.utilization
        if ($null -eq $uso) { $uso = 0 }
        $reset = if ($j.resetsAt) { [DateTimeOffset]::FromUnixTimeSeconds([long]$j.resetsAt).LocalDateTime } else { $null }
        return @{ uso = [double]$uso; reset = $reset; status = $j.status }
    } catch { return $null }
}

# Anuncia a conta e devolve $true quando o card pode começar agora.
function CabeNaJanela($indice) {
    $m = MediaPorCard
    $e = EstadoJanela

    if ($null -eq $e) {
        Escrever ("  orçamento: sem leitura da janela ainda — estimativa {0:P0} e {1:N0} min por card ({2})" -f $m.janela, $m.minutos, $m.base) 'DarkGray'
        return $true
    }

    $sobra = 1.0 - $e.uso
    $ateReset = if ($e.reset) { [int]([Math]::Max(0, ($e.reset - (Get-Date)).TotalMinutes)) } else { $null }
    $projetado = $e.uso + $m.janela

    $txtReset = if ($null -ne $ateReset) { "reset em {0} min" -f $ateReset } else { 'reset desconhecido' }
    Escrever ("  orçamento: janela em {0:P0}, sobra {1:P0}, {2}; card estimado em {3:P0} / {4:N0} min ({5})" -f `
              $e.uso, $sobra, $txtReset, $m.janela, $m.minutos, $m.base) 'DarkGray'

    if ($projetado -le $TetoJanela) {
        Escrever ("  ✓ cabe: projeção {0:P0} contra teto de {1:P0}" -f $projetado, $TetoJanela) 'DarkGray'
        return $true
    }

    Escrever ("  ⏸ não cabe: projeção {0:P0} passaria do teto de {1:P0}." -f $projetado, $TetoJanela) 'Yellow'
    return $false
}

# Espera em passos de 10 min até o card caber (ou até o reset chegar).
function EsperarJanela($indice) {
    while ($true) {
        $e = EstadoJanela
        if ($null -eq $e) { return }   # sem leitura, não há o que esperar

        $ateReset = if ($e.reset) { ($e.reset - (Get-Date)).TotalMinutes } else { 0 }
        if ($ateReset -le 0) {
            # A janela virou. A utilização real vem no primeiro evento da
            # sessão seguinte; aqui só se registra que a espera acabou.
            Escrever '  ▶ janela reiniciada — retomando.' 'Green'
            try { Remove-Item $ArqLimite -Force } catch { }
            return
        }

        $passo = [Math]::Min(10, [Math]::Ceiling($ateReset))
        Escrever ("  ⏳ aguardando {0} min (faltam {1:N0} min para o reset) — reavaliação às {2:HH:mm}" -f `
                  $passo, $ateReset, (Get-Date).AddMinutes($passo)) 'Yellow'
        Start-Sleep -Seconds ([int]($passo * 60))

        if (CabeNaJanela $indice) { return }
    }
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

# Aviso não impede a corrida — mas sai ANTES dela, e não escondido no relatório
# de um card que já custou meia hora.
foreach ($a in $script:avisos) { Escrever "  ⚠ $a" 'Yellow' }

if ($Verificar) { Escrever ''; Escrever 'Só verificação — nada executado.' 'Yellow'; exit 0 }

Titulo "Cadeia — até $MaxCards card(s)"
$feitos = 0
$parou = $null

for ($i = 1; $i -le $MaxCards; $i++) {
    $shaAntes = ShaDevelop
    Titulo "Card $i de no máximo $MaxCards"

    # A conta sai ANTES de todo card, inclusive o primeiro — quem acompanha
    # precisa saber o que vai acontecer, não descobrir depois.
    if (-not (CabeNaJanela $i)) { EsperarJanela $i }

    $eAntes = EstadoJanela
    $t0 = Get-Date
    $r = ExecutarCard $i
    $minutos = [Math]::Round(((Get-Date) - $t0).TotalMinutes, 1)
    $eDepois = EstadoJanela

    $registro = @{ indice = $i; veredito = $r.veredito; linha = $r.linha; saida = $r.saida; minutos = $minutos }

    # Delta negativo = a janela virou no meio do card. Não é medida útil e
    # entraria na média puxando-a para baixo, então fica de fora.
    if ($eAntes -and $eDepois) {
        $gasto = $eDepois.uso - $eAntes.uso
        if ($gasto -gt 0) { $registro['janelaGasta'] = [Math]::Round($gasto, 4) }
    }

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
