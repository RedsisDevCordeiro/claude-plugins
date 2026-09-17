<#
.SYNOPSIS
    Confere que todo ponteiro das skills ainda aponta para algo que existe, e que cada nota
    tem um dono so.

.DESCRIPTION
    As skills nao copiam o procedimento: elas apontam para a nota do agente dono. A forma do
    ponteiro e sempre

        <id-do-indice> § "Titulo exato da secao"

    por exemplo:  git.integracao-lote § "Integracao em lote da main nas branches de chamados"

    As aspas em volta do titulo sao OBRIGATORIAS: sao elas que delimitam onde o titulo acaba.
    Ponteiro escrito sem aspas nao e reconhecido - e um ponteiro que este script nao ve e
    pior do que nenhum, porque passa por conferido.

    Numero de linha nao serve como ancora: a base e editada todo dia e a referencia apodrece
    em silencio. O ID vem do INDICE.md do agente dono, que a base e obrigada a atualizar na
    mesma alteracao; o titulo da secao sobrevive a movimentacao de linha e, se for renomeado,
    o grep nao acha nada - falha com ruido em vez de ler a secao errada calada.

    Este script transforma essa suposicao em medicao. Ele:
      1. le <Repo>\*\contexto\INDICE.md e monta o mapa ID -> arquivo do agente dono;
      2. recusa ID declarado por dois agentes (uma nota tem um dono so);
      3. para cada ponteiro nos SKILL.md, valida que o ID existe, que o arquivo existe e que
         o titulo da secao existe nesse arquivo.

    Nao depende de clone nenhum: o contexto vive dentro deste repositorio.

.OUTPUTS
    Relatorio na tela. Codigo de saida 0 quando tudo confere, 1 quando algo quebrou.

.EXAMPLE
    powershell -File "C:\Agentes\scripts\Test-Ancoras.ps1"

.NOTES
    PowerShell 5.1. Somente leitura: nao escreve nada, nao conecta a banco.
#>
[CmdletBinding()]
param(
    [string]$Repo
)

$ErrorActionPreference = 'Stop'

if (-not $Repo) {
    $Repo = Split-Path -Parent $PSScriptRoot
    if (-not $Repo) { $Repo = 'C:\Agentes' }
}

function Falha($t) { Write-Host "  [erro]  $t" -ForegroundColor Red }
function Passa($t) { Write-Host "  [ok]    $t" -ForegroundColor Green }
function Nota($t)  { Write-Host "  [info]  $t" -ForegroundColor DarkGray }

Write-Host ''
Write-Host 'Ancoras das skills -> contexto dos agentes' -ForegroundColor Cyan
Write-Host ''
Nota "repo:  $Repo"

# ------------------------------------------------------------------ 1. mapa ID -> arquivo
$indices = @(Get-ChildItem -Path (Join-Path $Repo '*\contexto\INDICE.md') -File -ErrorAction SilentlyContinue)
if ($indices.Count -eq 0) { Falha "nenhum <Agente>\contexto\INDICE.md encontrado em $Repo"; Write-Host ''; exit 1 }

$mapa = @{}
$donos = @{}
$catalogo = @{}
$conflitos = 0

foreach ($ix in $indices) {
    $pastaContexto = Split-Path -Parent $ix.FullName
    $agente = Split-Path -Leaf (Split-Path -Parent $pastaContexto)

    # O Contexto_comum e camada, nao agente: o INDICE.md dele e o CATALOGO de todos os IDs,
    # nao a declaracao de posse. Dono e sempre o agente onde a nota mora - exceto as poucas
    # notas da propria camada comum (comum.* e regra.global).
    $ehCatalogo = ($agente -eq 'Contexto_comum')

    foreach ($l in [System.IO.File]::ReadAllLines($ix.FullName)) {
        if ($l -notmatch '^\|') { continue }
        $cel = @($l -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        if ($cel.Count -lt 2) { continue }
        if ($cel[0] -notmatch '^`([a-z0-9]+(?:\.[a-z0-9-]+)+)`$') { continue }
        $id = $Matches[1]
        if ($cel[1] -notmatch '^`(.+\.md)`$') { continue }
        $nomeArquivo = $Matches[1]
        $arquivo = Join-Path $pastaContexto $nomeArquivo

        if ($ehCatalogo) {
            $catalogo[$id] = $nomeArquivo
            if ($id -notlike 'comum.*' -and $id -ne 'regra.global') { continue }
        }

        if ($mapa.ContainsKey($id) -and $mapa[$id] -ne $arquivo) {
            Falha "ID '$id' tem dois donos: $($donos[$id]) e $agente"
            $conflitos++
            continue
        }
        $mapa[$id] = $arquivo
        $donos[$id] = $agente
    }
}
Nota "$($mapa.Count) IDs com dono, em $($indices.Count) indice(s); $($catalogo.Count) no catalogo geral"

# O catalogo geral nao pode prometer ID que nenhum agente tem.
$orfaos = @($catalogo.Keys | Where-Object { -not $mapa.ContainsKey($_) })
foreach ($o in $orfaos) {
    Falha "catalogo geral promete '$o' ($($catalogo[$o])), que nenhum agente declara"
    $conflitos++
}

# ------------------------------------------------------------------ 2. ponteiros das skills
$skills = @(Get-ChildItem -Path (Join-Path $Repo '*\skill\*') -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') })

if ($skills.Count -eq 0) { Nota 'nenhuma skill no repositorio ainda; nada a conferir.'; Write-Host ''; exit 0 }

$rxPonteiro = '`(?<id>[a-z0-9]+(?:\.[a-z0-9-]+)+)`\s*§\s*["\u201C\u00AB](?<sec>[^"\u201D\u00BB\r\n]+)["\u201D\u00BB]'
$total = 0; $quebrados = 0

foreach ($s in $skills) {
    $arquivos = @(Get-ChildItem -Path $s.FullName -Filter '*.md' -Recurse -File)
    foreach ($a in $arquivos) {
        # ponteiro pode quebrar de linha entre o ID e o titulo: casamos no texto inteiro e
        # derivamos a linha pela posicao do casamento.
        $texto = [System.IO.File]::ReadAllText($a.FullName)
        foreach ($m in [regex]::Matches($texto, $rxPonteiro)) {
            $total++
            $id  = $m.Groups['id'].Value
            $sec = ($m.Groups['sec'].Value -replace '\s+', ' ').Trim()
            $linha = ($texto.Substring(0, $m.Index) -split "`n").Count
            $ondeSkill = "$($s.Name)/$($a.Name):$linha"

            if (-not $mapa.ContainsKey($id)) {
                Falha "$ondeSkill -> ID '$id' nao esta em nenhum INDICE.md de agente"; $quebrados++; continue
            }
            $alvo = $mapa[$id]
            if (-not (Test-Path $alvo)) {
                Falha "$ondeSkill -> ID '$id' aponta '$alvo', que nao existe"; $quebrados++; continue
            }
            $conteudo = [System.IO.File]::ReadAllText($alvo)
            $achou = $false
            foreach ($ln in ($conteudo -split "`r?`n")) {
                if ($ln -match '^#{1,6}\s+(.+?)\s*$') {
                    $titulo = ($Matches[1] -replace '\s+', ' ').Trim()
                    if ($titulo -eq $sec) { $achou = $true; break }
                }
            }
            if (-not $achou) {
                Falha "$ondeSkill -> secao `"$sec`" nao existe em $($donos[$id])/$(Split-Path -Leaf $alvo)"; $quebrados++; continue
            }
        }
    }
}

Write-Host ''
if ($conflitos -gt 0) {
    Falha "$conflitos ID(s) com mais de um dono. Uma nota tem um dono so."
    Write-Host ''
    exit 1
}
if ($total -eq 0) {
    Nota 'nenhum ponteiro encontrado nas skills. Se uma skill referencia o contexto, use'
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
Nota 'Corrija a SKILL.md, nao o contexto: a nota do agente dono e a fonte.'
Write-Host ''
exit 1
