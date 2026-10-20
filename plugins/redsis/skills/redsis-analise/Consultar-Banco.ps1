<#
.SYNOPSIS
    Consulta SOMENTE LEITURA a um banco Firebird de cliente, para a skill redsis-analise.

.DESCRIPTION
    Tres travas, nesta ordem:

      1. trabalha sobre uma COPIA do banco (o original do cliente nunca e aberto,
         a menos que -Original seja passado de proposito);
      2. recusa a execucao se a SQL tiver qualquer comando que nao seja de leitura;
      3. abre a transacao com SET TRANSACTION READ ONLY, que faz o proprio Firebird
         recusar escrita ("attempted update during read-only transaction").

    Tambem resolve a armadilha do isql: ele recusa caminho de script com mais de
    ~260 caracteres. Por isso o script .sql e a copia do banco moram em %TEMP%\rsan.

.PARAMETER Banco
    Caminho do .RED / .FDB informado pela pessoa.

.PARAMETER Sql
    A consulta, como texto. Varias instrucoes separadas por ';'.

.PARAMETER Arquivo
    Alternativa a -Sql: caminho de um .sql ja escrito.

.PARAMETER Versao
    Versao do Firebird cujo isql sera usado: 2.5 (padrao), 3.0 ou 5.0.

.PARAMETER Dialeto
    Dialeto SQL da conexao: 1 (padrao) ou 3.

.PARAMETER Original
    Consulta o arquivo original, sem copiar. Use so quando a copia for inviavel
    (banco muito grande) e com a pessoa ciente.

.EXAMPLE
    .\Consultar-Banco.ps1 -Banco 'C:\Bancos\Gerencial\QUINTOGRAN.RED' -Sql "SELECT FIRST 5 * FROM PROD;"

.EXAMPLE
    .\Consultar-Banco.ps1 -Banco 'C:\Bancos\X.RED' -Arquivo .\consulta.sql -Lista
#>
[CmdletBinding(DefaultParameterSetName = 'Texto')]
param(
    [Parameter(Mandatory = $true)]
    [string]$Banco,

    [Parameter(ParameterSetName = 'Texto', Mandatory = $true)]
    [string]$Sql,

    [Parameter(ParameterSetName = 'Arquivo', Mandatory = $true)]
    [string]$Arquivo,

    [ValidateSet('2.5', '3.0', '5.0')]
    [string]$Versao = '2.5',

    [ValidateSet('1', '3')]
    [string]$Dialeto = '1',

    [string]$Charset = 'WIN1252',
    [string]$Usuario = 'SYSDBA',
    [string]$Senha   = 'masterkey',

    [switch]$Lista,
    [switch]$Original,
    [switch]$Recopiar,

    [int]$MaxLinhas = 400
)

$ErrorActionPreference = 'Stop'

function Falhar([string]$Mensagem) {
    Write-Host "ERRO: $Mensagem" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------- 1. o isql

$pasta = 'Firebird_' + ($Versao -replace '\.', '_')
$candidatos = @(
    (Join-Path "${env:ProgramFiles}\Firebird\$pasta\bin"      'isql.exe'),
    (Join-Path "${env:ProgramFiles(x86)}\Firebird\$pasta\bin" 'isql.exe')
)
$isql = $candidatos | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $isql) {
    Falhar "isql do Firebird $Versao nao encontrado. Procurei em:`n  $($candidatos -join "`n  ")"
}

# ------------------------------------------------- 2. a SQL, e a trava de leitura

if ($PSCmdlet.ParameterSetName -eq 'Arquivo') {
    if (-not (Test-Path -LiteralPath $Arquivo)) { Falhar "arquivo de SQL nao encontrado: $Arquivo" }
    $consulta = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Arquivo))
} else {
    $consulta = $Sql
}

# Fora comentarios, para que nenhum comando se esconda atras deles.
$limpa = [regex]::Replace($consulta, '/\*.*?\*/', ' ', 'Singleline')
$limpa = [regex]::Replace($limpa, '(?m)--.*$', ' ')

# COMMIT e ROLLBACK ficam de fora: depois deles o isql abre a transacao padrao, que e de
# escrita. Pelo mesmo motivo SET TRANSACTION (trocaria o READ ONLY) e SET TERM (mudaria o
# separador, e esta varredura so enxerga ';').
$permitidos = @('SELECT', 'WITH', 'SHOW', 'SET')
$proibidoAposSet = @('GENERATOR', 'STATISTICS', 'TRANSACTION', 'TERM')

foreach ($bruto in ($limpa -split ';')) {
    $inst = $bruto.Trim()
    if ([string]::IsNullOrWhiteSpace($inst)) { continue }

    $palavras = [regex]::Split($inst, '\s+')
    $primeira = $palavras[0].ToUpperInvariant()

    if ($permitidos -notcontains $primeira) {
        Falhar "esta skill so executa leitura. Instrucao recusada:`n  $inst"
    }
    if ($primeira -eq 'SET' -and $palavras.Count -gt 1 -and
        $proibidoAposSet -contains $palavras[1].ToUpperInvariant()) {
        Falhar "SET que escreve no banco ou troca a transacao e recusado:`n  $inst"
    }
}

# ------------------------------------------------------ 3. area de trabalho curta

$trabalho = Join-Path $env:TEMP 'rsan'
if (-not (Test-Path $trabalho)) { New-Item -ItemType Directory -Path $trabalho | Out-Null }

if (-not (Test-Path -LiteralPath $Banco)) { Falhar "banco nao encontrado: $Banco" }
$origem = Get-Item -LiteralPath $Banco

if ($Original) {
    $alvo = $origem.FullName
    Write-Host "AVISO: consultando o arquivo ORIGINAL do cliente, sem copia." -ForegroundColor Yellow
} else {
    # Uma copia por banco de origem, reaproveitada enquanto a origem nao mudar.
    $md5 = [Security.Cryptography.MD5]::Create()
    $hash = [BitConverter]::ToString(
        $md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($origem.FullName.ToLowerInvariant()))
    ).Replace('-', '').Substring(0, 8)

    $pastaCopia = Join-Path $trabalho $hash
    if (-not (Test-Path $pastaCopia)) { New-Item -ItemType Directory -Path $pastaCopia | Out-Null }
    $alvo = Join-Path $pastaCopia $origem.Name

    # A assinatura da ORIGEM fica num arquivo ao lado: o proprio Firebird reescreve o
    # cabecalho da copia a cada conexao, entao a data da copia nao serve de comparacao.
    $assinatura = Join-Path $pastaCopia 'origem.txt'
    $atual = "$($origem.Length)|$($origem.LastWriteTimeUtc.Ticks)"

    $precisa = $Recopiar -or -not (Test-Path -LiteralPath $alvo) -or
               -not (Test-Path -LiteralPath $assinatura) -or
               ([IO.File]::ReadAllText($assinatura).Trim() -ne $atual)

    if ($precisa) {
        Write-Host "Copiando o banco para a area de trabalho ($([math]::Round($origem.Length/1MB,1)) MB)..."
        Copy-Item -LiteralPath $origem.FullName -Destination $alvo -Force
        [IO.File]::WriteAllText($assinatura, $atual)
    }
}

if ($alvo.Length -gt 250) {
    Falhar "o caminho do banco tem $($alvo.Length) caracteres; o isql recusa acima de ~260."
}

# ------------------------------------------------------------- 4. monta o script

$linhas = New-Object System.Collections.Generic.List[string]
$linhas.Add("CONNECT '$alvo' USER '$Usuario' PASSWORD '$Senha';")
if ($Lista) { $linhas.Add('SET LIST ON;') }
$linhas.Add('SET TRANSACTION READ ONLY WAIT;')
$linhas.Add($consulta.TrimEnd())
if (-not $consulta.TrimEnd().EndsWith(';')) { $linhas.Add(';') }
# Fecha a transacao de leitura; sem isso o isql imprime "Rolling back work." no fim.
$linhas.Add('COMMIT;')

$script = Join-Path $trabalho 'q.sql'
$saida  = Join-Path $trabalho 'q.txt'
$w1252  = [Text.Encoding]::GetEncoding(1252)
[IO.File]::WriteAllText($script, ($linhas -join "`r`n") + "`r`n", $w1252)

# --------------------------------------------------------------- 5. executa

# O isql ANEXA no arquivo de -o. Sem apagar antes, a saida de agora vem colada
# na da consulta anterior, e a leitura sai errada.
if (Test-Path -LiteralPath $saida) { Remove-Item -LiteralPath $saida -Force }

& $isql -q -s $Dialeto -ch $Charset -i $script -o $saida -m | Out-Null

if (-not (Test-Path -LiteralPath $saida)) { Falhar 'o isql nao produziu saida.' }
$texto = [IO.File]::ReadAllText($saida, $w1252)
# Ruido do isql ao sair com a transacao de leitura aberta; nao e resultado nem erro.
$texto = [regex]::Replace($texto, '(?m)^Rolling back work\.\r?\n', '').Trim()
$todas = $texto -split "`r?`n"

if ($todas.Count -gt $MaxLinhas) {
    ($todas | Select-Object -First $MaxLinhas) -join [Environment]::NewLine
    Write-Host ""
    Write-Host "[... $($todas.Count - $MaxLinhas) linhas omitidas. Refine a consulta, ou use -MaxLinhas. Saida inteira em $saida]" -ForegroundColor Yellow
} else {
    $texto.TrimEnd()
}

if ($texto -match 'Statement failed|SQLSTATE') {
    Write-Host ""
    Write-Host "A consulta falhou. Em dialeto 1, aspas duplas sao literal de texto (nao identificador) e DATE guarda data+hora." -ForegroundColor Yellow
    exit 2
}
