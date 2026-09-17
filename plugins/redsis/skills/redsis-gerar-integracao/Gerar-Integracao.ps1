<#
.SYNOPSIS
    Monta a branch de integracao a partir da main e puxa o pull request de cada
    chamado aprovado por cherry-pick, um commit por chamado.

.DESCRIPTION
    Este script e BURRO de proposito, igual ao Gerar-Exe.ps1: nenhuma decisao de
    fluxo vive aqui. Ele executa a sequencia, para na primeira coisa que exige
    julgamento e devolve o estado em resumo.json. Quem decide e o agente, pelo
    SKILL.md.

    Por que cherry-pick -m 2, e nao merge nem cherry-pick commit a commit: o topo
    de cada branch de chamado ja e um merge cujo 2o pai e o mesmo commit da main
    (a rodada de redsis-conflitos deixa assim). Com -m 2 o git aplica
    diff(main -> topo), que e exatamente o conteudo liquido do pull request, num
    commit so. Commit a commit traria dezenas de merges da main e de "Commit para
    salvar" que se anulam, cada um com chance propria de conflitar.

    Sequencia:
      1. fetch --prune;
      2. descobre o proximo Integracoes/Integracao_NN sequencial;
      3. cria a branch de origin/main e uma worktree para ela;
      4. inventaria os chamados: a branch de cada um e o 2o pai do topo, exigindo
         que todos os topos compartilhem a MESMA base;
      5. cherry-pick -m 2 de cada topo, na ordem recebida, parando no primeiro
         conflito;
      6. varre duplicidade NOVA de identificador (.pas) e de nome de componente
         (.dfm) que a soma dos chamados possa ter criado sem o git acusar;
      7. so com -Publicar: push da branch.

    NAO compila e NAO envia nada para lugar nenhum: exe e envio sao dos outros
    dois drivers.

.PARAMETER Chamados
    Numeros dos chamados, na ordem em que devem entrar. Aceita virgula ou espaco.

.PARAMETER ArquivoChamados
    Alternativa a -Chamados: arquivo texto com um numero por linha.

.PARAMETER Assuntos
    Arquivo texto com "numero|descricao funcional" por linha, usado como assunto
    do commit daquele chamado. O que faltar cai no assunto do ultimo commit
    funcional da branch e entra em resumo.json na lista assuntos_derivados, para
    o agente revisar.

.PARAMETER Continuar
    Retoma depois de um conflito resolvido a mao: fecha o cherry-pick pendente e
    segue a fila. Chamado ja aplicado e reconhecido pelo marcador PR-chamado no
    corpo do commit, entao repetir a fila inteira e seguro.

.PARAMETER Publicar
    Autoriza o push da branch de integracao para origin.

.PARAMETER Numero
    Forca o numero da integracao em vez de descobrir o proximo. Dois digitos.

.EXAMPLE
    powershell -File Gerar-Integracao.ps1 -Chamados 19380945,19394104 -Assuntos assuntos.txt

.EXAMPLE
    powershell -File Gerar-Integracao.ps1 -Continuar

.OUTPUTS
    Relatorio na tela e resumo.json em %LOCALAPPDATA%\redsis-integracao\<id>.
    Saida 0 quando a etapa concluiu, 1 quando parou.

.NOTES
    PowerShell 5.1. Gravado UTF-8 com BOM.
#>
[CmdletBinding()]
param(
    [string[]]$Chamados,
    [string]$ArquivoChamados,
    [string]$Assuntos,
    [switch]$Continuar,
    [switch]$Publicar,
    [ValidatePattern('^\d{2}$')][string]$Numero,
    [string]$Repo = 'C:\Developer\Redsis',
    [string]$Worktree,
    [string]$Origem = 'origin/main'
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$script:trabalho = $null
$script:wt = $null
$resumo = [ordered]@{
    integracao         = $null
    branch             = $null
    base               = $null
    status             = 'INCOMPLETO'
    etapa              = 'inicio'
    aplicados          = @()
    assuntos_derivados = @()
    pendente           = $null
}

function Escreve {
    param([string]$Texto, [string]$Cor = 'Gray')
    Write-Host $Texto -ForegroundColor $Cor
}

function Salva-Resumo {
    if ($script:trabalho -and (Test-Path $script:trabalho)) {
        ($resumo | ConvertTo-Json -Depth 5) |
            Set-Content -LiteralPath (Join-Path $script:trabalho 'resumo.json') -Encoding UTF8
    }
}

function Falha {
    param([string]$Texto)
    $resumo.status = 'FALHOU'
    $resumo.erro = $Texto
    Salva-Resumo
    Escreve ''
    Escreve "ERRO: $Texto" Red
    exit 1
}

# ErrorActionPreference volta a Continue durante a chamada: com 'Stop' o PS 5.1
# promove cada linha de stderr de executavel nativo a erro terminante, e o git
# escreve progresso normal em stderr. Mesmo motivo do Gerar-Exe.ps1.
function Git-Em {
    param([string]$Dir, [Parameter(ValueFromRemainingArguments)][string[]]$Argumentos)
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $saida = & git -C $Dir @Argumentos 2>&1 | ForEach-Object { "$_" }
        $script:GitOk = ($LASTEXITCODE -eq 0)
    }
    finally { $ErrorActionPreference = $anterior }
    return $saida
}

function Git-Repo { Git-Em -Dir $Repo @args }
function Git-Wt { Git-Em -Dir $script:wt @args }

function Duplicados {
    param([string[]]$Linhas, [string]$Regex)
    $vistos = @{}
    $dup = @{}
    foreach ($l in $Linhas) {
        if ($l -match $Regex) {
            $k = $Matches[1]
            if ($vistos.ContainsKey($k)) { $dup[$k] = $true } else { $vistos[$k] = $true }
        }
    }
    return @($dup.Keys | Sort-Object)
}

# --------------------------------------------------------------- lista de chamados
$lista = @()
if ($ArquivoChamados) {
    if (-not (Test-Path $ArquivoChamados)) { Falha "Arquivo '$ArquivoChamados' nao existe." }
    $lista = @(Get-Content -LiteralPath $ArquivoChamados |
        ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
elseif ($Chamados) {
    $lista = @($Chamados -split '[,\s]+' | Where-Object { $_ })
}
foreach ($c in $lista) {
    if ($c -notmatch '^\d{7,9}$') { Falha "Chamado '$c' invalido - use 7 a 9 digitos." }
}
if ($lista.Count -ne (@($lista | Select-Object -Unique)).Count) {
    Falha 'A lista tem chamado repetido. Repetido vira commit duplicado: corrija a lista.'
}
if (-not $Continuar -and $lista.Count -eq 0) {
    Falha 'Sem chamados. Passe -Chamados ou -ArquivoChamados, ou retome com -Continuar.'
}

# ---------------------------------------------------------------- mapa de assuntos
$mapaAssunto = @{}
if ($Assuntos) {
    if (-not (Test-Path $Assuntos)) { Falha "Arquivo de assuntos '$Assuntos' nao existe." }
    foreach ($l in (Get-Content -LiteralPath $Assuntos -Encoding UTF8)) {
        if ($l -match '^\s*(\d{7,9})\s*\|\s*(.+?)\s*$') { $mapaAssunto[$Matches[1]] = $Matches[2] }
    }
}

if (-not (Test-Path (Join-Path $Repo '.git'))) { Falha "Repositorio '$Repo' nao tem .git." }

# ------------------------------------------------------------------------- fetch
$resumo.etapa = 'fetch'
Escreve 'Buscando referencias em origin...' Cyan
Git-Repo fetch --prune origin | Out-Null
if (-not $script:GitOk) { Falha "Nao consegui fazer fetch em $Repo." }

# ------------------------------------------------------------- numero e identidade
$resumo.etapa = 'numero'
$refs = Git-Repo for-each-ref --format='%(refname:short)' refs/heads refs/remotes/origin
if (-not $script:GitOk) { Falha 'Nao consegui listar as branches.' }

if ($Numero) {
    $n = $Numero
}
else {
    $usados = @($refs | ForEach-Object {
            if ($_ -match '^(?:origin/)?Integracoes/Integracao_(\d+)$') { [int]$Matches[1] }
        })
    $prox = 1
    if ($usados.Count -gt 0) { $prox = ([int](($usados | Measure-Object -Maximum).Maximum)) + 1 }
    $n = '{0:00}' -f $prox
}
$id = "Integracao_$n"
$branch = "Integracoes/$id"
$resumo.integracao = $id
$resumo.branch = $branch

$script:trabalho = Join-Path $env:LOCALAPPDATA "redsis-integracao\$id"
New-Item -ItemType Directory -Force -Path $script:trabalho | Out-Null
$resumo.pasta = $script:trabalho

if (-not $Worktree) { $Worktree = "C:\Developer\Redsis-$id" }
$script:wt = $Worktree

Escreve "$id  |  branch: $branch  |  worktree: $Worktree" Cyan

# ------------------------------------------------------------- branch e worktree
$resumo.etapa = 'branch'
Git-Repo rev-parse --verify --quiet "refs/heads/$branch" | Out-Null
$existeLocal = $script:GitOk

if (-not $existeLocal) {
    if ($Continuar) { Falha "-Continuar pediu $branch, que nao existe. Rode sem -Continuar." }
    Git-Repo rev-parse --verify --quiet "refs/remotes/$Origem" | Out-Null
    if (-not $script:GitOk) { Falha "Origem '$Origem' nao existe em $Repo." }
    Git-Repo branch $branch $Origem | Out-Null
    if (-not $script:GitOk) { Falha "Nao consegui criar $branch a partir de $Origem." }
    Escreve "Branch criada de $Origem." Green
}
elseif (-not $Continuar) {
    Falha ("$branch ja existe - e o resultado de uma rodada anterior. Retome com " +
        '-Continuar, ou informe -Numero para montar outra integracao.')
}

if (-not (Test-Path (Join-Path $Worktree '.git'))) {
    Escreve 'Criando a worktree (o primeiro checkout leva alguns minutos)...' Cyan
    Git-Repo worktree add $Worktree $branch | Out-Null
    if (-not $script:GitOk) { Falha "Nao consegui criar a worktree em $Worktree." }
}
$resumo.worktree = $Worktree

$emConflito = @(Git-Wt diff --name-only --diff-filter=U | Where-Object { $_ })
$estadoPath = Join-Path $script:trabalho 'estado.json'
$msgPath = Join-Path $script:trabalho 'mensagem.txt'

# --------------------------------------------------- fecha o cherry-pick pendente
if ($Continuar) {
    if ($emConflito.Count -gt 0) {
        Falha ('Ainda ha conflito em aberto: ' + ($emConflito -join ', ') +
            '. Resolva os arquivos antes de -Continuar.')
    }
    if (Test-Path $estadoPath) {
        $est = Get-Content -LiteralPath $estadoPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($est.pendente) {
            if (-not (Test-Path $msgPath)) { Falha "Falta $msgPath para fechar o commit pendente." }
            Escreve "Fechando o cherry-pick do chamado $($est.pendente)..." Cyan
            Git-Wt add -A | Out-Null
            Git-Wt commit --no-verify -F $msgPath | Out-Null
            if (-not $script:GitOk) { Falha "Nao consegui commitar o chamado $($est.pendente)." }
            Escreve "  fechado: $(Git-Wt log -1 --format='%h %s')" Green
            Remove-Item -LiteralPath $estadoPath -Force
        }
    }
}
else {
    $sujo = @(Git-Wt status --porcelain | Where-Object { $_ })
    if ($sujo.Count -gt 0) {
        Falha ('A worktree tem alteracao em aberto: ' + (($sujo | Select-Object -First 10) -join ', ') +
            '. Cherry-pick por cima disso mistura trabalho.')
    }
}

# ---------------------------------------------------------------------- inventario
$resumo.etapa = 'inventario'
$jaAplicados = @()
foreach ($l in (Git-Wt log --format='%b' "$Origem..$branch")) {
    if ($l -match '^PR-chamado:\s*(\d{7,9})\s*$') { $jaAplicados += $Matches[1] }
}

$inventario = @()
$bases = @{}
foreach ($c in $lista) {
    $achadas = @($refs |
        Where-Object { $_ -match "^(?:origin/)?(Tags|Corretivos|Evolutivos|Integracoes)/$c$" } |
        ForEach-Object { $_ -replace '^origin/', '' } |
        Select-Object -Unique)
    if ($achadas.Count -eq 0) { Falha "Nenhuma branch para o chamado $c em $Repo nem em origin." }
    if ($achadas.Count -gt 1) {
        Falha ("O chamado $c tem branch em mais de uma categoria: " + ($achadas -join ', ') +
            '. Escolher por conta propria puxaria a arvore errada.')
    }
    $b = $achadas[0]
    $topo = (Git-Repo rev-parse "origin/$b").Trim()
    if (-not $script:GitOk) { Falha "Nao consegui resolver origin/$b." }
    $pais = @((Git-Repo log -1 --format='%P' $topo).Trim() -split '\s+')
    if ($pais.Count -ne 2) {
        Falha ("O topo de $b nao e um merge de dois pais ($($pais.Count)). Este fluxo depende " +
            'do merge da main que redsis-conflitos deixa no topo: rode a integracao da main ' +
            'nessa branch antes.')
    }
    $base = (Git-Repo rev-parse $pais[1]).Trim()
    $bases[$base] = $true
    $inventario += [pscustomobject]@{ chamado = $c; branch = $b; topo = $topo; base = $base }
}

if ($bases.Keys.Count -gt 1) {
    Falha ('Os chamados nao compartilham a mesma base da main: ' + ($bases.Keys -join ', ') +
        '. Integrar bases diferentes num lote so mistura snapshots - atualize as branches ' +
        'com a mesma main antes.')
}
$resumo.base = @($bases.Keys)[0]
$resumo.inventario = $inventario
Escreve "$($inventario.Count) chamado(s) inventariado(s), base comum $($resumo.base.Substring(0,9))." Cyan

# -------------------------------------------------------------------- cherry-pick
$resumo.etapa = 'cherry-pick'
$aplicados = @()
$derivados = @()
foreach ($it in $inventario) {
    $c = $it.chamado
    if ($jaAplicados -contains $c) {
        Escreve "== $c ja aplicado, pulando" DarkGray
        $aplicados += $c
        continue
    }

    $assunto = $mapaAssunto[$c]
    if (-not $assunto) {
        $assunto = (Git-Repo log --no-merges --format='%s' -1 "$($it.base)..origin/$($it.branch)")
        $assunto = ("$assunto" -replace '^\s*\[\d{7,9}\]\s*', '').Trim()
        if ($assunto.Length -gt 68) { $assunto = $assunto.Substring(0, 65) + '...' }
        if (-not $assunto) { $assunto = 'alteracoes do chamado' }
        $derivados += $c
    }

    $autores = ((Git-Repo log --no-merges --format='%an' "$($it.base)..origin/$($it.branch)") |
        Sort-Object -Unique) -join ', '
    $hashes = ((Git-Repo log --no-merges --format='%h' --reverse "$($it.base)..origin/$($it.branch)")) -join ' '

    $mensagem = @(
        "[$c] $assunto",
        '',
        "Cherry-pick do conteudo integral do pull request do chamado $c.",
        '',
        "Origem: $($it.branch) @ $($it.topo.Substring(0,9)) (merge que ja incorporava a main",
        "$($resumo.base.Substring(0,9)); aplicado com cherry-pick -m 2, trazendo o PR inteiro",
        'em um commit).',
        "Autores originais: $autores",
        "Commits funcionais de origem: $hashes",
        '',
        "PR-chamado: $c",
        '',
        'Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>'
    )
    Set-Content -LiteralPath $msgPath -Value $mensagem -Encoding UTF8

    Escreve "== $c  cherry-pick -m 2 $($it.topo.Substring(0,9))  ($($it.branch))" Cyan
    Git-Wt cherry-pick -m 2 --no-commit $it.topo | Out-Null
    $conflitos = @(Git-Wt diff --name-only --diff-filter=U | Where-Object { $_ })

    if ($conflitos.Count -gt 0) {
        $resumo.pendente = $c
        $resumo.conflitos = $conflitos
        $resumo.aplicados = $aplicados
        $resumo.assuntos_derivados = $derivados
        $resumo.status = 'CONFLITO'
        Salva-Resumo
        [pscustomobject]@{ pendente = $c; branch = $it.branch; topo = $it.topo } |
            ConvertTo-Json | Set-Content -LiteralPath $estadoPath -Encoding UTF8
        Escreve ''
        Escreve "CONFLITO no chamado ${c}:" Yellow
        foreach ($f in $conflitos) { Escreve "  $f" Yellow }
        Escreve ''
        Escreve 'Resolva por significado, e depois:' Yellow
        Escreve "  powershell -File `"$PSCommandPath`" -Continuar" Yellow
        exit 1
    }

    Git-Wt commit --no-verify -F $msgPath | Out-Null
    if (-not $script:GitOk) { Falha "cherry-pick do $c aplicou, mas o commit falhou." }
    Escreve "   ok -> $(Git-Wt log -1 --format='%h %s')" Green
    $aplicados += $c
}
$resumo.aplicados = $aplicados
$resumo.assuntos_derivados = $derivados
if (Test-Path $estadoPath) { Remove-Item -LiteralPath $estadoPath -Force }

# ------------------------------------------------- duplicidade que o git nao acusa
# Dois chamados podem criar, cada um, um campo ou um componente com o MESMO nome no
# mesmo arquivo, em trechos distantes. O merge passa liso; o compilador para no
# identificador repetido e o streaming do formulario estoura em execucao com
# EComponentError. So interessa o que a integracao criou: por isso a comparacao e
# contra a propria main, que ja tem duplicidade legitima (sobrecarga, variavel local).
$resumo.etapa = 'duplicidade'
$rxCampo = '^    ([A-Za-z_][A-Za-z0-9_]*): T[A-Za-z0-9_]+;'
$rxObjeto = '^\s*(?:object|inline) ([A-Za-z_][A-Za-z0-9_]*):'
$novas = @()
foreach ($f in (Git-Wt diff --name-only $Origem $branch)) {
    if ($f -notmatch '\.(pas|dfm)$') { continue }
    $rx = if ($f -match '\.pas$') { $rxCampo } else { $rxObjeto }
    $antes = @(Duplicados -Linhas (Git-Wt show "${Origem}:$f") -Regex $rx)
    $depois = @(Duplicados -Linhas (Git-Wt show "${branch}:$f") -Regex $rx)
    $delta = @($depois | Where-Object { $antes -notcontains $_ })
    if ($delta.Count -gt 0) { $novas += [pscustomobject]@{ arquivo = $f; nomes = $delta } }
}
$resumo.duplicidades = $novas

# ------------------------------------------------------------------------ publicar
if ($Publicar) {
    $resumo.etapa = 'publicar'
    if ($novas.Count -gt 0) {
        Falha ('Ha duplicidade nova; nao publico assim. Conserte e rode de novo com -Publicar.')
    }
    Escreve 'Publicando a branch em origin...' Cyan
    Git-Wt push -u origin "${branch}:${branch}" | Out-Null
    if (-not $script:GitOk) { Falha "Nao consegui publicar $branch em origin." }
    $resumo.publicada = $true
    Escreve "Publicada: origin/$branch" Green
}

# ------------------------------------------------------------------------ relatorio
$resumo.etapa = 'fim'
$resumo.commits = [int]((Git-Wt rev-list --count "$Origem..$branch") | Select-Object -First 1)
$resumo.status = if ($novas.Count -gt 0) { 'DUPLICIDADE' } else { 'PRONTO' }
Salva-Resumo

Escreve ''
Escreve "$id : $($aplicados.Count) chamado(s) aplicado(s), $($resumo.commits) commit(s) sobre $Origem." Cyan
if ($derivados.Count -gt 0) {
    Escreve "Assunto derivado do commit de origem (revise): $($derivados -join ', ')" Yellow
}
if ($novas.Count -gt 0) {
    Escreve ''
    Escreve 'DUPLICIDADE NOVA - a integracao criou nome repetido que a main nao tinha:' Red
    foreach ($d in $novas) { Escreve "  $($d.arquivo): $($d.nomes -join ', ')" Red }
    Escreve 'Isso quebra a compilacao ou o streaming do formulario. Conserte antes do exe.' Red
    exit 1
}
Escreve "Resumo: $(Join-Path $script:trabalho 'resumo.json')" DarkGray
exit 0
