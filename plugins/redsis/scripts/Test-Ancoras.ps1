<#
.SYNOPSIS
    Confere que todo ponteiro das skills ainda aponta para algo que existe na base.

.DESCRIPTION
    As skills operacionais nao copiam o procedimento da base de contextos: elas apontam
    para ele. A forma do ponteiro e sempre

        <id-do-indice> § "Titulo exato da secao"

    por exemplo:  projeto.chamados § "Integracao em lote da main nas branches de chamados"

    As aspas em volta do titulo sao OBRIGATORIAS: sao elas que delimitam onde o titulo
    acaba. Ponteiro escrito sem aspas nao e reconhecido - e um ponteiro que este script
    nao ve e pior do que nenhum, porque passa por conferido.

    Numero de linha nao serve como ancora: a base e editada todo dia, por obrigacao de
    colheita, e a referencia apodrece em silencio. O ID vem do INDEX.md, que a base e
    obrigada a atualizar na mesma alteracao; o titulo da secao sobrevive a movimentacao de
    linha e, se for renomeado, o grep nao acha nada - falha com ruido em vez de ler a
    secao errada calada.

    Este script transforma essa suposicao em medicao. Para cada ponteiro encontrado nos
    SKILL.md do repositorio, valida que:
      1. o ID existe no INDEX.md e aponta um arquivo;
      2. o arquivo existe dentro da base;
      3. o titulo da secao existe nesse arquivo.

    Rodar depois do Sincronizar.bat e a cada onda de skill nova.

.OUTPUTS
    Relatorio na tela. Codigo de saida 0 quando tudo confere, 1 quando algo quebrou.

.EXAMPLE
    powershell -File "C:\Agentes\scripts\Test-Ancoras.ps1"

.NOTES
    PowerShell 5.1. Somente leitura: nao escreve nada, nao conecta a banco.
    Gravado UTF-8 com BOM.
#>
[CmdletBinding()]
param(
    [string]$Repo,
    [string]$Base
)

$ErrorActionPreference = 'Stop'

if (-not $Repo) {
    $Repo = Split-Path -Parent $PSScriptRoot
    if (-not $Repo) { $Repo = 'C:\Agentes' }
}

if (-not $Base) {
    $resolver = Join-Path $PSScriptRoot 'Resolve-BaseRedsis.ps1'
    if (Test-Path $resolver) { $Base = (& $resolver) }
}

function Falha($t) { Write-Host "  [erro]  $t" -ForegroundColor Red }
function Passa($t) { Write-Host "  [ok]    $t" -ForegroundColor Green }
function Nota($t)  { Write-Host "  [info]  $t" -ForegroundColor DarkGray }

Write-Host ''
Write-Host 'Ancoras das skills -> base de contextos' -ForegroundColor Cyan
Write-Host ''

if (-not $Base -or -not (Test-Path $Base)) {
    Falha 'base de contextos nao encontrada; rode scripts\Resolve-BaseRedsis.ps1 para ver o motivo.'
    Write-Host ''
    exit 1
}
Nota "base:  $Base"
Nota "repo:  $Repo"

$indice = Join-Path $Base 'INDEX.md'
if (-not (Test-Path $indice)) { Falha "INDEX.md nao existe em $Base"; Write-Host ''; exit 1 }

# O INDEX.md cataloga em tabela markdown; a ultima celula da linha e o caminho do arquivo,
# e a primeira e o ID entre backticks. Pegamos os dois sem depender da ordem das colunas
# do meio, que muda entre as tabelas do proprio indice.
$mapa = @{}
foreach ($l in [System.IO.File]::ReadAllLines($indice)) {
    if ($l -notmatch '^\|') { continue }
    $cel = @($l -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    if ($cel.Count -lt 2) { continue }
    if ($cel[0] -notmatch '^`([a-z0-9]+(?:\.[a-z0-9-]+)+)`$') { continue }
    $id = $Matches[1]
    $ultima = $cel[$cel.Count - 1]
    if ($ultima -match '^`(.+\.md)`$') { $mapa[$id] = $Matches[1] }
}
Nota "$($mapa.Count) IDs lidos do INDEX.md"

$skills = @(Get-ChildItem -Path (Join-Path $Repo '*\skill\*') -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') })

if ($skills.Count -eq 0) { Nota 'nenhuma skill no repositorio ainda; nada a conferir.'; Write-Host ''; exit 0 }

$rxPonteiro = '`(?<id>[a-z0-9]+(?:\.[a-z0-9-]+)+)`\s*§\s*["\u201C\u00AB](?<sec>[^"\u201D\u00BB\r\n]+)["\u201D\u00BB]'
$total = 0; $quebrados = 0

foreach ($s in $skills) {
    $arquivos = @(Get-ChildItem -Path $s.FullName -Filter '*.md' -Recurse -File)
    foreach ($a in $arquivos) {
        $linhas = [System.IO.File]::ReadAllLines($a.FullName)
        for ($i = 0; $i -lt $linhas.Count; $i++) {
            foreach ($m in [regex]::Matches($linhas[$i], $rxPonteiro)) {
                $total++
                $id  = $m.Groups['id'].Value
                $sec = $m.Groups['sec'].Value.Trim()
                $ondeSkill = "$($s.Name)/$($a.Name):$($i+1)"

                if (-not $mapa.ContainsKey($id)) {
                    Falha "$ondeSkill -> ID '$id' nao esta no INDEX.md"; $quebrados++; continue
                }
                $alvo = Join-Path $Base ($mapa[$id] -replace '/', '\')
                if (-not (Test-Path $alvo)) {
                    Falha "$ondeSkill -> ID '$id' aponta '$($mapa[$id])', que nao existe na base"; $quebrados++; continue
                }
                $texto = [System.IO.File]::ReadAllText($alvo)
                $achou = $false
                foreach ($ln in ($texto -split "`r?`n")) {
                    if ($ln -match '^#{1,6}\s+(.+?)\s*$' -and $Matches[1].Trim() -eq $sec) { $achou = $true; break }
                }
                if (-not $achou) {
                    Falha "$ondeSkill -> secao `"$sec`" nao existe em $($mapa[$id])"; $quebrados++; continue
                }
            }
        }
    }
}

Write-Host ''
if ($total -eq 0) {
    Nota 'nenhum ponteiro encontrado nas skills. Se uma skill referencia a base, use a forma'
    Nota '  `id.do.indice` § "Titulo exato da secao"'
    Write-Host ''
    exit 0
}
if ($quebrados -eq 0) {
    Passa "$total ponteiro(s) conferido(s), todos apontam para secao existente"
    Write-Host ''
    exit 0
}
Falha "$quebrados de $total ponteiro(s) quebrado(s)"
Nota 'Corrija a SKILL.md, nao a base: a secao canonica e a fonte.'
Write-Host ''
exit 1
