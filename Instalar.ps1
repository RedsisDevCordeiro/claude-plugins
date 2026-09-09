<#
.SINOPSE
    Instala as skills da Redsis nesta máquina. Roda UMA vez, e nunca mais.

.DESCRICAO
    Depois disto, skill nova, correção de skill e conteúdo novo das bases chegam sozinhos:
    o conteúdo é servido ao vivo pelo MCP da Redsis, e o texto das skills vem pelo
    auto-update do marketplace.

    O que faz:
      1. confere que o CLI `claude` existe;
      2. grava a variável REDSIS_MCP_TOKEN (é o que autentica no servidor das bases);
      3. registra o marketplace e instala o plugin `redsis` no escopo do usuário;
      4. liga o auto-update do marketplace e pré-aprova as ferramentas do MCP, para você
         não levar prompt de permissão a cada pergunta;
      5. clona a base de contextos e repõe os dois scripts que as skills de procedimento
         chamam por caminho absoluto.

    NENHUM vault é copiado: os 40 MB de notas do DBA ficam no servidor.

.EXEMPLO
    powershell -ExecutionPolicy Bypass -File .\Instalar.ps1 -Token "<o token que te passaram>"

.EXEMPLO
    # Para conferir o que faria, sem mexer em nada:
    powershell -ExecutionPolicy Bypass -File .\Instalar.ps1 -Token "..." -Simular
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Token,

    [string]$Marketplace = 'RedsisDevCordeiro/claude-plugins',
    [string]$NomeMarketplace = 'redsis-tools',
    [string]$Plugin = 'redsis',
    [string]$Contextos = 'C:\Developer\AGENTS_CONTEXTS_REDSIS',
    [switch]$Simular
)

$ErrorActionPreference = 'Stop'

function Escreve([string]$texto, [string]$cor = 'Gray') { Write-Host $texto -ForegroundColor $cor }
function Falha([string]$texto) { Write-Host $texto -ForegroundColor Red; exit 1 }
function Passo([string]$texto) { Write-Host ""; Write-Host "-> $texto" -ForegroundColor Cyan }

Escreve "=== Skills da Redsis ===" Cyan
if ($Simular) { Escreve "MODO SIMULACAO: nada será alterado." Yellow }

# --------------------------------------------------------------------------- 1. pré-requisitos
Passo "Conferindo pré-requisitos"
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Falha @"
O CLI 'claude' não está no PATH. Instale o Claude Code antes:
  npm install -g @anthropic-ai/claude-code
Depois abra um terminal novo e rode este script de novo.
"@
}
Escreve "  claude: $((Get-Command claude).Source)" Gray
$temGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
Escreve "  git: $(if ($temGit) { (Get-Command git).Source } else { 'AUSENTE (a base de contextos não será clonada)' })" Gray

# --------------------------------------------------------------------------------- 2. token
Passo "Gravando o token do servidor de bases"
if ($Simular) { Escreve "  [simulacao] gravaria REDSIS_MCP_TOKEN ($($Token.Length) chars)" Gray }
else {
    [Environment]::SetEnvironmentVariable('REDSIS_MCP_TOKEN', $Token.Trim(), 'User')
    $env:REDSIS_MCP_TOKEN = $Token.Trim()
    Escreve "  REDSIS_MCP_TOKEN gravado no seu ambiente." Green
    Escreve "  Terminal que já estava aberto não enxerga a variável: abra um novo depois." Yellow
}

# -------------------------------------------------------------------- 3. marketplace e plugin
Passo "Instalando o plugin"
if ($Simular) {
    Escreve "  [simulacao] claude plugin marketplace add $Marketplace" Gray
    Escreve "  [simulacao] claude plugin install $Plugin@$NomeMarketplace --scope user" Gray
}
else {
    & claude plugin marketplace add $Marketplace 2>&1 | ForEach-Object { Escreve "  $_" Gray }
    & claude plugin install "$Plugin@$NomeMarketplace" --scope user 2>&1 | ForEach-Object { Escreve "  $_" Gray }
}

# ------------------------------------------------------- 4. auto-update e permissão do MCP
Passo "Ligando o auto-update e pré-aprovando as ferramentas"

$arquivoSettings = Join-Path $env:USERPROFILE '.claude\settings.json'
$pastaSettings = Split-Path $arquivoSettings -Parent
if (-not (Test-Path $pastaSettings)) { New-Item -ItemType Directory -Path $pastaSettings -Force | Out-Null }

$cfg = if (Test-Path $arquivoSettings) {
    try { Get-Content $arquivoSettings -Raw | ConvertFrom-Json }
    catch { Falha "O seu $arquivoSettings não é JSON válido. Conserte-o e rode de novo — não vou sobrescrevê-lo." }
}
else { [pscustomobject]@{} }

# Em objeto vazio, PSObject.Properties.Name devolve $null - por isso o @() em volta.
function Tem-Propriedade($objeto, [string]$nome) {
    @($objeto.PSObject.Properties.Name) -contains $nome
}

function Garante-Propriedade($objeto, [string]$nome, $valorPadrao) {
    if (-not (Tem-Propriedade $objeto $nome)) {
        $objeto | Add-Member -NotePropertyName $nome -NotePropertyValue $valorPadrao
    }
    $objeto.$nome
}

# Marketplace de terceiro vem com auto-update DESLIGADO. Sem esta linha, skill nova nunca chega.
$mkts = Garante-Propriedade $cfg 'extraKnownMarketplaces' ([pscustomobject]@{})
$entrada = [pscustomobject]@{
    source     = [pscustomobject]@{ source = 'github'; repo = $Marketplace }
    autoUpdate = $true
}
if (Tem-Propriedade $mkts $NomeMarketplace) { $mkts.$NomeMarketplace = $entrada }
else { $mkts | Add-Member -NotePropertyName $NomeMarketplace -NotePropertyValue $entrada }

# Sem isto, cada pergunta que toca a base levanta prompt de permissão — o oposto de
# "o usuário não se preocupa com nada".
#
# O nome NAO e 'mcp__redsis'. Servidor MCP que vem de plugin e prefixado com
# plugin_<plugin>_<servidor>, entao as ferramentas se chamam
# mcp__plugin_redsis_redsis__redsis_ler e afins. Medido nesta maquina, nao deduzido.
$perm = Garante-Propriedade $cfg 'permissions' ([pscustomobject]@{})
$lista = @(Garante-Propriedade $perm 'allow' @())
if ($lista -notcontains 'mcp__plugin_redsis_redsis') {
    $lista = @($lista + 'mcp__plugin_redsis_redsis')
}
$perm.allow = $lista

if ($Simular) {
    Escreve "  [simulacao] escreveria em $arquivoSettings :" Gray
    ($cfg | ConvertTo-Json -Depth 10) -split "`n" | ForEach-Object { Escreve "    $_" Gray }
}
else {
    $copia = "$arquivoSettings.bak"
    if (Test-Path $arquivoSettings) { Copy-Item $arquivoSettings $copia -Force }
    [IO.File]::WriteAllText($arquivoSettings, ($cfg | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding $false))
    Escreve "  $arquivoSettings atualizado (auto-update ligado, ferramentas do MCP liberadas)." Green
}

# ------------------------------------------------------- 5. base de contextos e scripts
Passo "Base de contextos e scripts de apoio"

$urlContextos = 'https://github.com/AdhemarAlves/AGENTS_CONTEXTS_REDSIS.git'
if (Test-Path (Join-Path $Contextos 'contextos\AGENTS.md')) {
    Escreve "  Base de contextos já está em $Contextos." Gray
}
elseif (-not $temGit) {
    Escreve "  git ausente: clone você mesmo depois, com" Yellow
    Escreve "    git clone $urlContextos `"$Contextos`"" Cyan
}
elseif ($Simular) { Escreve "  [simulacao] git clone $urlContextos `"$Contextos`"" Gray }
else {
    $pai = Split-Path $Contextos -Parent
    if (-not (Test-Path $pai)) { New-Item -ItemType Directory -Path $pai -Force | Out-Null }
    & git clone --quiet $urlContextos $Contextos
    if ($LASTEXITCODE -eq 0) { Escreve "  Base de contextos clonada em $Contextos." Green }
    else { Escreve "  O clone falhou. Rode à mão: git clone $urlContextos `"$Contextos`"" Yellow }
}

# Seis das oito skills chamam estes dois por caminho absoluto. Repô-los aqui custa ~9 KB e
# evita reescrever as seis. O resolvedor cai sozinho para C:\Developer\AGENTS_CONTEXTS_REDSIS.
$origemScripts = Join-Path $PSScriptRoot "plugins\$Plugin\scripts"
$destinoScripts = 'C:\Agentes\scripts'
if (-not (Test-Path $origemScripts)) {
    Escreve "  AVISO: não achei $origemScripts. As skills de procedimento vão reclamar." Yellow
}
elseif ($Simular) { Escreve "  [simulacao] copiaria os scripts de apoio para $destinoScripts" Gray }
else {
    if (-not (Test-Path $destinoScripts)) { New-Item -ItemType Directory -Path $destinoScripts -Force | Out-Null }
    Copy-Item (Join-Path $origemScripts '*.ps1') $destinoScripts -Force
    Escreve "  Scripts de apoio em $destinoScripts." Green
}

# ------------------------------------------------------------------------------- fechamento
Write-Host ""
Escreve "=== Pronto ===" Green
Escreve "Abra um terminal NOVO (por causa da variável de ambiente) e confira com:" Gray
Escreve "  claude mcp list" Cyan
Escreve "Deve aparecer:  redsis: https://mcp.redsis.com.br/mcp (HTTP) - Connected" Gray
Write-Host ""
Escreve "As skills chegam com o prefixo do plugin: /redsis:cerebro-dba, /redsis:cerebro-regras," Gray
Escreve "/redsis:redsis-chamado, e assim por diante. Você também pode só perguntar: o Claude" Gray
Escreve "escolhe a skill sozinho pela descrição." Gray
Write-Host ""
Escreve "Daqui em diante você não atualiza mais nada." Green
