<#
.SYNOPSIS
    Copia para a pasta do chamado os helpers que os scripts gerados exigem, para o RedTestes
    importar a pasta inteira sem "Helper ausente".

.DESCRIPTION
    O RedTestes so aceita require literal de arquivo da mesma pasta (require("UTEIS") ->
    UTEIS.js). Este script le cada .js da pasta do chamado, acha os require literais, copia o
    arquivo correspondente da pasta Script do projeto TestComplete e repete com o que foi
    copiado, ate fechar a cadeia. Nada e copiado por cima de arquivo que ja exista na pasta do
    chamado, a menos que -Atualizar seja informado.

    Ao final, lista os scripts de rotina (os que chamam funcoesIniciais) com a base e o modulo
    lidos do texto, do mesmo jeito que o RedTestes le na importacao.

.PARAMETER Destino
    Pasta do chamado, por exemplo C:\Testes\RedTestes\19436169.

.PARAMETER Origem
    Pasta Script do projeto TestComplete. Padrao:
    C:\Developer\Testes\TestCompleteProjects\REDSIS\RELEASE\Script

.PARAMETER Atualizar
    Recopia os helpers mesmo quando ja existem no destino.

.OUTPUTS
    Relatorio na tela. Saida 0 quando a cadeia fechou; 1 quando algum require nao foi achado.

.EXAMPLE
    powershell -File Preparar-Pasta.ps1 -Destino C:\Testes\RedTestes\19436169

.NOTES
    PowerShell 5.1. Le e copia arquivos; nao executa JavaScript nem conecta a banco.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Destino,
    [string]$Origem = 'C:\Developer\Testes\TestCompleteProjects\REDSIS\RELEASE\Script',
    [switch]$Atualizar
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Origem -PathType Container)) {
    Write-Host "Pasta Script nao encontrada: $Origem" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $Destino -PathType Container)) {
    Write-Host "Pasta do chamado nao encontrada: $Destino" -ForegroundColor Red
    exit 1
}
$item = Get-Item -LiteralPath $Destino
if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    # O RedTestes recusa pasta vinculada ("Pastas vinculadas nao sao aceitas").
    Write-Host "O RedTestes nao importa pasta vinculada (junction/link): $Destino" -ForegroundColor Red
    exit 1
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$padraoRequire = 'require\s*\(\s*["'']([A-Za-z0-9_$-]+)(?:\.js)?["'']\s*\)'
$copiados = New-Object System.Collections.Generic.List[string]
$faltando = New-Object System.Collections.Generic.List[string]
$vistos = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$fila = New-Object System.Collections.Generic.Queue[string]

Get-ChildItem -LiteralPath $Destino -Filter *.js -File | ForEach-Object { $fila.Enqueue($_.FullName) }

while ($fila.Count -gt 0) {
    $arquivo = $fila.Dequeue()
    if (-not $vistos.Add($arquivo)) { continue }
    $texto = [IO.File]::ReadAllText($arquivo, $utf8)
    foreach ($m in [regex]::Matches($texto, $padraoRequire)) {
        $nome = $m.Groups[1].Value + '.js'
        $alvo = Join-Path $Destino $nome
        $fonte = Get-ChildItem -LiteralPath $Origem -Filter $nome -File | Select-Object -First 1
        if (-not $fonte) {
            if (-not (Test-Path -LiteralPath $alvo) -and -not $faltando.Contains($nome)) { $faltando.Add($nome) }
            continue
        }
        if (-not (Test-Path -LiteralPath $alvo) -or ($Atualizar -and -not $copiados.Contains($nome))) {
            Copy-Item -LiteralPath $fonte.FullName -Destination $alvo -Force
            $copiados.Add($nome)
        }
        $fila.Enqueue((Resolve-Path -LiteralPath $alvo).Path)
    }
}

Write-Host "Origem dos helpers: $Origem"
if ($copiados.Count -gt 0) { Write-Host ("Copiados: " + ($copiados -join ', ')) }
else { Write-Host "Nenhum helper novo copiado." }

Write-Host ""
Write-Host "Rotinas na pasta (lidas como o RedTestes le na importacao):"
$padraoInicio = 'funcoesIniciais\s*\(\s*["'']([^"''\r\n]*)["'']\s*,\s*["'']([^"''\r\n]*)["'']\s*,\s*["'']([^"''\r\n]*)["'']'
Get-ChildItem -LiteralPath $Destino -Filter *.js -File | Sort-Object Name | ForEach-Object {
    $texto = [IO.File]::ReadAllText($_.FullName, $utf8)
    $m = [regex]::Match($texto, $padraoInicio)
    if ($m.Success) {
        $checks = ([regex]::Matches($texto, 'aqObject\.CheckProperty\s*\(')).Count
        $todos = ([regex]::Matches($texto, '//\s*TODO')).Count
        Write-Host ("  {0}  base {1}  modulo {2}  CheckProperty {3}  TODO {4}" -f $_.Name, $m.Groups[2].Value, $m.Groups[3].Value, $checks, $todos)
    }
}

if ($faltando.Count -gt 0) {
    Write-Host ""
    Write-Host ("require sem arquivo na pasta Script: " + ($faltando -join ', ')) -ForegroundColor Red
    Write-Host "O RedTestes recusaria a importacao com 'Helper ausente'." -ForegroundColor Red
    exit 1
}
exit 0
