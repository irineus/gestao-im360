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
    [double]$TetoJanela = 0.92,

    # Teto da janela SEMANAL, mais alto que o de 5 h de propósito — e a razão é
    # medida, não intuição. A margem existe para absorver o erro da estimativa
    # de UM card, e o erro tem tamanhos muito diferentes nas duas janelas:
    #
    #   5 h     : média 18 pontos por card, MÁXIMO 54 -> erro de até +36
    #   semanal : média 1,5 ponto por card, máximo  2 -> erro de até +0,5
    #
    # A API reporta a utilização semanal em ponto percentual INTEIRO (os únicos
    # valores medidos foram 1 e 2), o que dá ±0,5 de incerteza NA LEITURA. ⚠️ Ela
    # NÃO acumula entre decisões: cada card relê a utilização corrente, então o
    # que importa é a imprecisão de uma leitura só. (Primeira versão desta conta
    # somava o arredondamento de várias leituras e chegava a 0,94 — conservador
    # demais por erro de aritmética, não por prudência.)
    #
    # Pior desfecho ao começar em U: U + 0,5 (leitura) + 2,5 (card) = U + 3.
    # Com 0,96 o card só começa se U <= 94,4, e o pior caso termina em 97,4% —
    # não estoura. Com o 0,88 do de 5 h sobrariam 12 pontos, quatro vezes o
    # necessário: ~7 cards de capacidade semanal jogados fora por semana.
    [double]$TetoSemanal = 0.96,

    # Quanto o driver aceita ESPERAR por um reset antes de desistir e parar.
    # Existe porque a janela SEMANAL reinicia às segundas: quem tranca por ela
    # teria três dias de espera, e script que dorme três dias não é espera, é
    # travamento com cara de funcionamento.
    [int]$MaxEsperaMin = 360
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
    # ⚠️ A ferramenta e NOMEADA, e nao descrita. Pedindo "a ferramenta de busca
    # do Notion", a sessao escolheu `notion-ai-search` — que exige plano
    # Business e devolve upsell —, e a sonda reprovou com o MCP funcionando
    # perfeitamente (medido em 04/09/2026). Sonda que reprova com o sistema bom
    # ensina a ignorar vermelho, e esta ja tinha caido nisso duas vezes.
    #
    # A consulta escolhida e a MESMA que a skill `proxima-tarefa` faz primeiro:
    # exercita o caminho de verdade e devolve um numero, nao uma pagina.
    $perg = 'RESPONDA COM UMA UNICA PALAVRA E NADA MAIS. ' +
            'Use a ferramenta mcp__claude_ai_Notion__notion-query-data-sources (modo sql) para rodar ' +
            'SELECT count(*) FROM "collection://e50abe7f-1688-402a-96b5-c6049b24ce82". ' +
            'NAO use notion-ai-search nem notion-search. ' +
            'Se a consulta responder, sua resposta inteira e exatamente: PRONTO. ' +
            'Se for negada ou falhar, sua resposta inteira e exatamente: NEGADO. ' +
            'Nao escreva tabelas, listas, explicacoes, nem o resultado da consulta.'

    # ⚠️ A sonda passa PELO EXECUTOR, e não pelo `claude` direto, por um motivo
    # que não é organização de código: o executor é quem grava o `limite.json`.
    # Chamando o `claude` direto, o pré-voo abria uma sessão, VIA o estado da
    # janela e o jogava fora — e o primeiro card decidia o orçamento com a
    # leitura do fim da corrida anterior, que podia ser de horas antes. Foi o que
    # Irineu viu em 04/09/2026: "janela em 91%" com o painel marcando 96%.
    #
    # Com a decisão passando a ser fina (autonomia contra tempo até o reset),
    # número velho deixa de ser incômodo e vira erro de conta.
    $exeClaude = ResolverExecutavelClaude
    if (-not (Test-Path $DirLogs)) { New-Item -ItemType Directory -Path $DirLogs -Force | Out-Null }
    $arqPergunta = Join-Path $DirLogs 'sonda-prompt.md'
    $arqSondaLog = Join-Path $DirLogs 'sonda.log'
    $arqSondaCru = Join-Path $DirLogs 'sonda.jsonl'
    Set-Content -Path $arqPergunta -Value $perg -Encoding UTF8
    Remove-Item $arqSondaLog, $arqSondaCru -Force -ErrorAction SilentlyContinue

    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($exeClaude -and (Test-Path $ExecutorSessao)) {
            $sonda = (& node $ExecutorSessao $exeClaude $arqPergunta $arqSondaLog $arqSondaCru $ArqLimite `
                             @FerramentasPermitidas 2>&1 | Out-String)
        } else {
            $sonda = 'falhou: sem executável do claude ou sem o executor de sessão'
        }
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
                $sem = if ($r.semanalGasta) { [double]$r.semanalGasta } else { 0.0 }
                $medidos += [pscustomobject]@{ janela = [double]$r.janelaGasta; minutos = [double]$r.minutos; semanal = $sem }
            }
        }
    }

    if ($medidos.Count -ge 2) {
        $semanal = ($medidos | Where-Object { $_.semanal -gt 0 })
        return @{
            janela  = ($medidos | Measure-Object janela  -Average).Average
            minutos = ($medidos | Measure-Object minutos -Average).Average
            semanal = if ($semanal) { ($semanal | Measure-Object semanal -Average).Average } else { 0.016 }
            base    = "$($medidos.Count) card(s) medido(s)"
        }
    }

    # Padrão até haver medida própria, das corridas de 04/09/2026: ~25 pontos da
    # janela de 5 h, ~1,6 ponto da semanal e ~33 min por card, em nove sessões.
    return @{ janela = 0.25; minutos = 33.0; semanal = 0.016; base = 'padrão das corridas de 04/09 (sem medida local ainda)' }
}

# Lê o último estado da janela. Devolve $null quando ainda não há leitura.
function EstadoJanela {
    if (-not (Test-Path $ArqLimite)) { return $null }
    try {
        $j = Get-Content $ArqLimite -Raw -Encoding UTF8 | ConvertFrom-Json
        $w = $j.unifiedWindows
        if ($null -eq $w) { return $null }
        $lidoEm = if ($j.lidoEm) { [datetime]$j.lidoEm } else { $null }

        # ⚠️ O `resetsAt` DO TOPO não serve: ele descreve a janela que estiver
        # apertando no momento, e em 04/09/2026 virou `seven_day` assim que o
        # semanal passou o de 5 h. O driver estava casando a UTILIZAÇÃO de 5 h
        # com o RESET do semanal e anunciando "reset em 4.405 min" — três dias.
        # Cada janela traz o seu par dentro de `unifiedWindows`; é de lá que se
        # lê, sempre.
        $janelas = @()
        foreach ($def in @(@{ k = 'five_hour'; n = '5 h' }, @{ k = 'seven_day'; n = 'semanal' })) {
            $chave = $def.k; $nome = $def.n
            $d = $w.$chave
            if ($null -eq $d) { continue }
            $uso = if ($null -ne $d.utilization) { [double]$d.utilization } else { 0.0 }
            $reset = if ($d.resetsAt) { [DateTimeOffset]::FromUnixTimeSeconds([long]$d.resetsAt).LocalDateTime } else { $null }
            $janelas += @{ chave = $chave; nome = $nome; uso = $uso; reset = $reset }
        }

        $cinco = $janelas | Where-Object { $_.chave -eq 'five_hour' } | Select-Object -First 1
        $uso = if ($cinco) { $cinco.uso } else { 0.0 }
        $reset = if ($cinco) { $cinco.reset } else { $null }

        # ⚠️ Leitura cujo reset JÁ PASSOU não é velha, é INVÁLIDA: aquela
        # utilização pertence a um ciclo que não existe mais, e o ciclo novo
        # começa perto de zero. Devolver $null faz o driver dizer "sem leitura
        # ainda" e seguir — em vez de anunciar um "não cabe" com o número do
        # ciclo anterior, que é o tipo de mensagem que ensina a ignorar o aviso.
        if ($reset -and $reset -lt (Get-Date)) { return $null }

        return @{ uso = [double]$uso; reset = $reset; status = $j.status; lidoEm = $lidoEm; janelas = $janelas }
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

    $idade = if ($e.lidoEm) { [int]((Get-Date) - $e.lidoEm).TotalMinutes } else { $null }
    $script:leituraEm = $e.lidoEm
    $nota = if ($null -ne $idade -and $idade -gt 5) { " · leitura de $idade min atrás" } else { '' }

    Escrever ("  orçamento: card estimado em {0:P0} da janela de 5 h e {1:P1} da semanal / {2:N0} min ({3}){4}" -f `
              $m.janela, $m.semanal, $m.minutos, $m.base, $nota) 'DarkGray'

    # ⚠️ AS DUAS JANELAS DECIDEM, e a que apertar primeiro manda. Modelar só a
    # de 5 h deixaria a cadeia planejar contra ela e ser barrada pela semanal
    # sem entender por quê — em 04/09/2026 a semanal já estava em 75% enquanto a
    # de 5 h marcava 28%. Medido: ~25 pontos de 5 h e ~1,6 ponto de semanal por
    # card, ou seja, a semanal aguenta ~15 cards e a de 5 h aguenta ~3.
    $script:janelaQueTranca = $null
    $cabe = $true

    foreach ($j in $e.janelas) {
        $est = if ($j.chave -eq 'five_hour') { $m.janela } else { $m.semanal }
        $teto = if ($j.chave -eq 'five_hour') { $TetoJanela } else { $TetoSemanal }
        $sobra = [Math]::Max([double]0, $teto - $j.uso)
        $ateReset = if ($j.reset) { ($j.reset - (Get-Date)).TotalMinutes } else { $null }
        $txtReset = if ($null -ne $ateReset) { "reset em {0:N0} min" -f $ateReset } else { 'reset desconhecido' }

        Escrever ("             {0,-8} em {1,5:P0} · sobra {2,5:P0} até o teto · {3}" -f `
                  $j.nome, $j.uso, $sobra, $txtReset) 'DarkGray'

        # Caso simples: o card inteiro cabe no que resta desta janela.
        if (($j.uso + $est) -le $teto) { continue }

        # ---------------------------------------------------------------
        # AUTONOMIA — substituiu "não cabe inteiro, então tranca".
        #
        # Aquela regra desperdiçava a sobra: com a janela em 72% e um card de
        # 29%, trancava e deixava 20 pontos morrerem no reset. Mas o card NÃO
        # PRECISA caber inteiro no ciclo atual — precisa AGUENTAR ATÉ O RESET,
        # e daí em diante corre no ciclo novo. O card 5.7 da primeira corrida
        # atravessou um reset (66% -> 5% no meio dele) e terminou normalmente.
        #
        # ⚠️ `[Math]::Max([double]0, …)` com o `[double]` NÃO é firula: sem
        # ele o PowerShell escolhe a sobrecarga de inteiros e ARREDONDA —
        # `[Math]::Max(0, 0.60)` devolve `1`. A sobra virava 100% na tela, e
        # como a autonomia só é consultada quando a sobra é menor que a
        # estimativa (sempre < 0,5 na prática), ela arredondava para ZERO e a
        # otimização inteira nunca disparava. Medido em 04/09/2026.
        # ---------------------------------------------------------------
        if ($null -eq $ateReset -or $m.minutos -le 0 -or $est -le 0) {
            Escrever ("  ⏸ {0}: não cabe, e sem reset conhecido para calcular autonomia." -f $j.nome) 'Yellow'
            $cabe = $false; $script:janelaQueTranca = $j; continue
        }

        $taxa = $est / $m.minutos                     # pontos por minuto nesta janela
        $autonomia = if ($taxa -gt 0) { $sobra / $taxa } else { [double]::PositiveInfinity }

        if ($autonomia -ge $ateReset) {
            Escrever ("             {0,-8} autonomia de {1:N0} min cobre os {2:N0} min até o reset" -f `
                      $j.nome, $autonomia, $ateReset) 'DarkGray'
            continue
        }

        Escrever ("  ⏸ {0}: autonomia de {1:N0} min acaba antes do reset ({2:N0} min) — a sessão morreria no meio." -f `
                  $j.nome, $autonomia, $ateReset) 'Yellow'
        $cabe = $false
        if ($null -eq $script:janelaQueTranca) { $script:janelaQueTranca = $j }
    }

    if ($cabe) { Escrever '  ✓ cabe nas duas janelas' 'DarkGray' }
    return $cabe
}

# Espera o reset da janela, em passos, mostrando quanto falta.
#
# ⚠️ NÃO REAVALIA A UTILIZAÇÃO, e a versão anterior fingia que sim. O
# `limite.json` só é escrito pelo EXECUTOR, no fim de uma sessão; durante a
# espera não há sessão nenhuma, então reler o arquivo devolve o mesmo número
# para sempre. Medido em 04/09/2026: o driver imprimiu "janela em 91%" sete
# vezes seguidas enquanto o painel de Irineu já marcava 96%.
#
# E mesmo com leitura fresca a reavaliação não teria o que decidir: a janela é
# FIXA — o `resetsAt` é idêntico em todas as leituras —, então antes do reset a
# utilização só pode SUBIR. Um laço que só pode piorar não é reavaliação, é
# contagem regressiva com outro nome. Aqui ela tem o nome certo.
#
# O passo de 10 min existe para a espera dar sinal de vida e poder ser
# interrompida, não porque algo mude a cada 10 min.
function EsperarJanela($indice) {
    $j = $script:janelaQueTranca
    if ($null -eq $j -or -not $j.reset) { return $true }   # sem reset, não há o que esperar

    $faltam = ($j.reset - (Get-Date)).TotalMinutes

    # ⚠️ NUNCA dormir por dias. Quando quem tranca é a janela SEMANAL, o reset
    # pode estar a três dias — e um script que dorme três dias não é espera, é
    # travamento com aparência de funcionamento. Aí a cadeia PARA e diz por quê:
    # a decisão de esperar até segunda-feira é de Irineu, não do driver.
    if ($faltam -gt $MaxEsperaMin) {
        Escrever ("  ✗ quem tranca é a janela {0}, e o reset dela é só às {1:dd/MM HH:mm} ({2:N0} h)." -f `
                  $j.nome, $j.reset, ($faltam / 60)) 'Red'
        Escrever '    A cadeia não espera tanto — retome quando a janela abrir.' 'Red'
        return $false
    }

    while ($true) {
        $faltam = ($j.reset - (Get-Date)).TotalMinutes
        if ($faltam -le 0) { break }

        $passo = [Math]::Min(10, [Math]::Ceiling($faltam))

        # ⚠️ O número NÃO é de agora, e a tela precisa dizer isso. `limite.json`
        # só é escrito pelo executor, no fim de cada card; durante a espera nada
        # roda e nada o atualiza — e não há como reler de graça: a utilização
        # chega apenas nos eventos de uma sessão, e sondar gastaria justamente o
        # que foi medir. Em 04/09/2026 a tela repetiu 71% por horas enquanto o
        # real já era 75% — a diferença era a SESSÃO INTERATIVA, porque a janela
        # é da conta, não do script. Defasagem inofensiva para a decisão (dentro
        # de uma janela fixa o uso só sobe, então a medida velha é um piso), mas
        # anunciá-la como se fosse leitura viva ensina a desconfiar do painel.
        $idadeLeitura = if ($script:leituraEm) { [int]((Get-Date) - $script:leituraEm).TotalMinutes } else { $null }
        $selo = if ($null -ne $idadeLeitura) { "{0:P0} há {1:N0} min, só sobe" -f $j.uso, $idadeLeitura }
                else { "{0:P0} na última medida" -f $j.uso }

        Escrever ("  ⏳ janela {0} sem espaço para um card ({1}); reset às {2:HH:mm} — faltam {3:N0} min" -f `
                  $j.nome, $selo, $j.reset, $faltam) 'Yellow'
        Start-Sleep -Seconds ([int]($passo * 60))
    }

    # A janela virou. A utilização REAL do novo ciclo vem no primeiro evento da
    # sessão seguinte — pode não ser zero, porque a janela é da conta inteira e
    # outra sessão pode já estar consumindo. Apagar a leitura velha é o que
    # impede o driver de decidir o próximo card com o número do ciclo anterior.
    Escrever ("  ▶ janela {0} reiniciada — retomando." -f $j.nome) 'Green'
    try { Remove-Item $ArqLimite -Force -ErrorAction SilentlyContinue } catch { }
    return $true
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
    if (-not (CabeNaJanela $i)) {
        if (-not (EsperarJanela $i)) {
            $parou = 'janela de uso esgotada e o reset está longe demais para esperar'
            break
        }
    }

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

        $semAntes  = ($eAntes.janelas  | Where-Object { $_.chave -eq 'seven_day' } | Select-Object -First 1)
        $semDepois = ($eDepois.janelas | Where-Object { $_.chave -eq 'seven_day' } | Select-Object -First 1)
        if ($semAntes -and $semDepois) {
            $gastoSem = $semDepois.uso - $semAntes.uso
            if ($gastoSem -gt 0) { $registro['semanalGasta'] = [Math]::Round($gastoSem, 5) }
        }
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
