<#
.SYNOPSIS
    Descobre onde mora a base de contextos do Redsis (AGENTS_CONTEXTS_REDSIS).

.DESCRIPTION
    A base de contextos e um repositorio git PROPRIO, com remote e dono separados. Ela nao
    vem pelo Sincronizar.bat, nao tem endereco garantido entre maquinas, e por isso nenhuma
    skill deve ter esse caminho escrito dentro dela.

    Toda skill que precise da base chama este script e usa o caminho que ele imprime.

    Ordem de resolucao:
      1. variavel de ambiente REDSIS_CONTEXTOS, quando definida;
      2. <raiz deste repositorio>\AGENTS_CONTEXTS_REDSIS\contextos;
      3. C:\AGENTS_CONTEXTS_REDSIS\contextos e C:\Developer\AGENTS_CONTEXTS_REDSIS\contextos.

    Um candidato so e aceito se tiver o arquivo-marco contextos\AGENTS.md. Com -Estrito, o
    script ainda confirma pelo remote do git que o repositorio e mesmo o AGENTS_CONTEXTS_REDSIS.

.PARAMETER Estrito
    Alem do arquivo-marco, exige que o remote do git contenha AGENTS_CONTEXTS_REDSIS.

.PARAMETER Silencioso
    Nao imprime nada e devolve apenas o codigo de saida. Util para checagem condicional.

.OUTPUTS
    O caminho absoluto da pasta contextos, uma linha, na saida padrao.
    Codigo de saida 0 quando encontrou, 1 quando nao.

.EXAMPLE
    $base = & "C:\Agentes\scripts\Resolve-BaseRedsis.ps1"

.EXAMPLE
    if (& "C:\Agentes\scripts\Resolve-BaseRedsis.ps1" -Silencioso) { "base disponivel" }

.NOTES
    PowerShell 5.1. Nao escreve nada em disco. Nao conecta a banco nenhum.
    Gravado UTF-8 com BOM.
#>
[CmdletBinding()]
param(
    [switch]$Estrito,
    [switch]$Silencioso
)

$ErrorActionPreference = 'Stop'

$MARCO = 'AGENTS.md'
$URL   = 'https://github.com/AdhemarAlves/AGENTS_CONTEXTS_REDSIS.git'

# A raiz do repositorio Agentes: este script vive em <raiz>\scripts.
$raizAgentes = Split-Path -Parent $PSScriptRoot
if (-not $raizAgentes) { $raizAgentes = 'C:\Agentes' }

$candidatos = @()
if ($env:REDSIS_CONTEXTOS) { $candidatos += $env:REDSIS_CONTEXTOS }
$candidatos += (Join-Path $raizAgentes 'AGENTS_CONTEXTS_REDSIS\contextos')
$candidatos += 'C:\AGENTS_CONTEXTS_REDSIS\contextos'
$candidatos += 'C:\Developer\AGENTS_CONTEXTS_REDSIS\contextos'

foreach ($c in $candidatos) {
    if (-not $c) { continue }
    if (-not (Test-Path (Join-Path $c $MARCO))) { continue }

    if ($Estrito) {
        # O repositorio e o pai da pasta contextos.
        $repo = Split-Path -Parent $c
        $remotes = ''
        try { $remotes = (& git -C $repo remote -v 2>$null | Out-String) } catch { }
        if ($remotes -notmatch 'AGENTS_CONTEXTS_REDSIS') { continue }
    }

    if (-not $Silencioso) { (Resolve-Path -LiteralPath $c).Path }
    exit 0
}

if (-not $Silencioso) {
    Write-Host ''
    Write-Host '  X  nao achei a base de contextos do Redsis.' -ForegroundColor Red
    Write-Host ''
    Write-Host '     Ela e um repositorio separado e nao vem pelo Sincronizar.bat.' -ForegroundColor Gray
    Write-Host '     Traga com:' -ForegroundColor Gray
    Write-Host ''
    Write-Host ("       git clone {0} `"{1}`"" -f $URL, (Join-Path $raizAgentes 'AGENTS_CONTEXTS_REDSIS')) -ForegroundColor Gray
    Write-Host ''
    Write-Host '     Se ela mora em outro lugar nesta maquina, aponte o caminho:' -ForegroundColor Gray
    Write-Host ''
    Write-Host '       $env:REDSIS_CONTEXTOS = "D:\algum\lugar\AGENTS_CONTEXTS_REDSIS\contextos"' -ForegroundColor Gray
    Write-Host ''
    Write-Host '     Procurei em:' -ForegroundColor DarkGray
    $candidatos | Where-Object { $_ } | ForEach-Object { Write-Host ("       {0}" -f $_) -ForegroundColor DarkGray }
    Write-Host ''
}
exit 1