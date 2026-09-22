<#
.SYNOPSIS
    Compila o exe da branch de um chamado, compacta em .rar e anexa no chamado do SAC.

.DESCRIPTION
    Mesmo caminho que o stage 'Copia para o Chamado' do Jenkins ja faz por PR
    (ci/scripts/build_exe.py), mas acionado pelo NUMERO DO CHAMADO e com a
    configuracao escolhida na hora - Debug ou Release.

    Este script e BURRO de proposito, pelo mesmo motivo do Jenkinsfile: nenhuma
    decisao de fluxo vive aqui. Ele executa a sequencia e devolve o resultado em
    resumo.json; quem decide o que fazer com falha e o agente, pelo SKILL.md.

    A autenticacao do SAC NAO e reimplementada. O script materializa
    ci/scripts/sac_anexar.ps1, ci/scripts/sac_fetch.ps1 e ci/scripts/sac_anexos.ps1
    a partir de -CiRef e os chama - eles reusam o SacApi.ps1 do time, cuja
    credencial e DPAPI e so pode ser lida pela conta Windows que a gravou.

    Sequencia:
      1. resolve a branch do chamado entre Tags/, Corretivos/ e Evolutivos/;
      2. escolhe o nome do pacote: lista os anexos do chamado e sai
         Redsis_<codigo>, ou _2, _3... quando ja ha copia la (o SAC substitui
         anexo de mesmo nome, e a copia anterior nao pode sumir);
      3. exige checkout limpo (puxar e compilar por cima de alteracao em aberto
         mistura ou perde trabalho do programador);
      4. troca para a branch e puxa origin/<branch> com --ff-only;
      5. em Release com -Versao, ajusta VerInfo_* no .dproj, compila e RESTAURA
         o .dproj byte a byte, conferindo por SHA-256;
      6. compila Config/Win32 por rsvars + msbuild;
      7. copia o exe para a pasta de trabalho e compacta em <nome>.rar;
      8. le o assunto do chamado e mostra o que seria anexado;
      9. SO com -Confirmar: envia o anexo e apaga exe e rar locais.

    ESCREVE em sistema de producao que o cliente le. Sem -Confirmar nada sobe:
    o padrao imprime o que seria enviado e sai, igual ao sac_anexar.ps1.

.PARAMETER Chamado
    Numero do chamado, 7 a 9 digitos. Define a branch e o nome do anexo.
    Pode ser omitido SO com -Branch e -SemAnexar juntos: e o caso da branch de
    integracao, que nao tem chamado. Ai o identificador vem do ultimo trecho da
    branch (Integracoes/Integracao_06 -> Integracao_06) e nomeia pasta e pacote.

.PARAMETER Config
    Debug (padrao) ou Release. Debug leva informacao de depuracao no exe, que e
    o que o pessoal de testes precisa para receber stack trace com linha.

.PARAMETER Versao
    So com -Config Release. Major.Minor.Release.Build, ex. 4.1.15.17. Ajusta o
    version info temporariamente e confere FileVersion/ProductVersion no exe.
    Omitida, a Release sai com a versao que estiver no projeto.

.PARAMETER Confirmar
    Autoriza o envio do anexo ao chamado. Sem ele, dry-run.

.PARAMETER PularBuild
    Reusa o .rar ja existente na pasta de trabalho, sem recompilar. E o que
    permite confirmar o anexo depois do dry-run sem pagar de novo os minutos de
    compilacao. O nome vem do resumo.json da execucao anterior: o "pode" vale
    para o pacote que o programador viu, com o numero que ele viu.

.PARAMETER SemAnexar
    Compila e compacta, e para antes de falar com o SAC.

.PARAMETER ManterArquivos
    Nao apaga exe e rar depois de anexar.

.PARAMETER Remoto
    Modo do servidor, acionado pelo job Jenkins "Redsis Exe" (mcp\Rodar-Exe-Jenkins.ps1).
    Exige que -Repo seja um worktree dedicado, compila origin/<branch> sem merge nem
    pull local, e so anexa com -PularBuild e -Sha256Esperado.

.EXAMPLE
    powershell -File Gerar-Exe.ps1 -Chamado 19436169
    powershell -File Gerar-Exe.ps1 -Chamado 19436169 -PularBuild -Confirmar

.EXAMPLE
    powershell -File Gerar-Exe.ps1 -Chamado 19436169 -Config Release -Versao 4.1.15.17

.OUTPUTS
    Relatorio na tela e resumo.json na pasta de trabalho. Saida 0 quando a
    etapa pedida concluiu, 1 quando parou.

.NOTES
    PowerShell 5.1. Gravado UTF-8 com BOM.
#>
[CmdletBinding()]
param(
    # Opcional SO quando -Branch e -SemAnexar vem juntos: a branch de integracao
    # nao tem numero de chamado. Validado adiante, junto do identificador.
    [string]$Chamado,
    [ValidateSet('Debug', 'Release')][string]$Config = 'Debug',
    [string]$Versao,
    [switch]$Confirmar,
    [switch]$PularBuild,
    [switch]$SemAnexar,
    [switch]$ManterArquivos,
    # Escape para Integracoes/ e para o caso de duas categorias no mesmo numero.
    [string]$Branch,
    [string]$Repo = 'C:\Developer\Redsis',
    [string]$Rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
    [string]$RarExe = 'C:\Program Files\WinRAR\Rar.exe',
    [string]$CiRef = 'origin/Evolutivos/ci-pipeline',
    [int]$TimeoutBuild = 2400,
    # Modo servidor (job Jenkins "Redsis Exe"): quem pede nao tem Delphi. Compila
    # origin/<branch> tal como esta, num worktree dedicado - nunca no checkout principal.
    [switch]$Remoto,
    [string]$PastaTrabalho = (Join-Path $env:LOCALAPPDATA 'redsis-exe'),
    # Bancada: compila a arvore como ela esta, sem tocar em branch. E o que permite
    # compilar um merge resolvido que ainda nao foi commitado nem publicado.
    [switch]$SemCheckout,
    # Para depois de compilar: sem pacote, sem SAC. Valida a resolucao do conflito.
    [switch]$SoCompilar,
    # Nomeia a pasta de trabalho quando nao ha chamado nem branch para derivar.
    [string]$Identificador,
    # Identifica a execucao no resumo.json, para o servidor.py nao confundir pedidos.
    [string]$Pedido,
    # Com -Confirmar: o pacote precisa ser exatamente o que o programador conferiu.
    [string]$Sha256Esperado
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$script:trabalho = $null
$resumo = [ordered]@{
    chamado = $Chamado
    config  = $Config
    versao  = $Versao
    status  = 'INCOMPLETO'
    etapa   = 'inicio'
    pedido  = $Pedido
    remoto  = [bool]$Remoto
}

function Escreve {
    param([string]$Texto, [string]$Cor = 'Gray')
    Write-Host $Texto -ForegroundColor $Cor
}

function Salva-Resumo {
    if ($script:trabalho -and (Test-Path $script:trabalho)) {
        ($resumo | ConvertTo-Json -Depth 4) |
            Set-Content -LiteralPath (Join-Path $script:trabalho 'resumo.json') -Encoding UTF8
    }
}

function Etapa {
    # Grava a cada etapa, e nao so no fim: no servidor, o resumo.json e o que mostra
    # o andamento para quem pediu o exe de outra maquina.
    param([string]$Nome)
    $resumo.etapa = $Nome
    Salva-Resumo
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

function Git-Redsis {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Argumentos)
    # ErrorActionPreference volta a Continue durante a chamada: com 'Stop', o
    # PS 5.1 promove cada linha de stderr de um executavel nativo a
    # NativeCommandError terminante - e o git escreve progresso normal em
    # stderr ("From https://..." no fetch). Sem isto, um fetch bem-sucedido
    # matava o script antes de qualquer verificacao.
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $saida = & git -C $Repo @Argumentos 2>&1 | ForEach-Object { "$_" }
        $script:GitOk = ($LASTEXITCODE -eq 0)
    }
    finally {
        $ErrorActionPreference = $anterior
    }
    return $saida
}

function Hash-De {
    param([string]$Caminho)
    (Get-FileHash -LiteralPath $Caminho -Algorithm SHA256).Hash
}

function Mb-De {
    param([string]$Caminho)
    [math]::Round((Get-Item -LiteralPath $Caminho).Length / 1MB, 1)
}

function Materializa-Ci {
    # A pasta ci/ nao esta na main: vem do ref do pipeline. Materializar em pasta de
    # trabalho, e nao com 'git checkout -- ci', para nao sujar o checkout do programador.
    # Uma vez por execucao: o nome do anexo, o assunto e o envio usam os mesmos scripts.
    if ($script:ciDir) { return $script:ciDir }
    $dir = Join-Path $script:trabalho 'ci'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Git-Redsis fetch origin ($CiRef -replace '^origin/', '') | Out-Null
    foreach ($s in 'sac_anexar.ps1', 'sac_fetch.ps1', 'sac_anexos.ps1') {
        $conteudo = Git-Redsis show "${CiRef}:ci/scripts/$s"
        if (-not $script:GitOk) {
            Falha "Nao consegui ler ci/scripts/$s de $CiRef. Sem ele nao ha como falar com o SAC."
        }
        [System.IO.File]::WriteAllLines((Join-Path $dir $s), $conteudo,
            (New-Object System.Text.UTF8Encoding($false)))
    }
    $script:ciDir = $dir
    return $dir
}

function Proximo-Nome {
    # Redsis_<codigo>, ou _2, _3... quando o chamado ja tem copia anexada: o SAC
    # SUBSTITUI anexo de mesmo nome, e quem esta testando a copia anterior nao pode
    # ve-la sumir. Mesma regra do CI (ci/lib/sac.py, proximo_nome), para as duas
    # origens numerarem o mesmo chamado da mesma forma: compara sem extensao - o .exe
    # e o .rar sao a mesma copia - e continua do MAIOR sufixo, nao do primeiro buraco,
    # para a nova ser sempre a ultima da lista mesmo que apaguem uma do meio.
    param([string]$Base, [string[]]$Existentes)
    $rx = [regex]::new('^' + [regex]::Escape($Base) + '(?:_(\d+))?$',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $maior = 0
    foreach ($n in $Existentes) {
        $m = $rx.Match([System.IO.Path]::GetFileNameWithoutExtension("$n"))
        if ($m.Success) {
            $numero = if ($m.Groups[1].Success) { [int]$m.Groups[1].Value } else { 1 }
            if ($numero -gt $maior) { $maior = $numero }
        }
    }
    if ($maior -eq 0) { return $Base }
    return "${Base}_$($maior + 1)"
}

# ------------------------------------------------------------------ pre-requisitos
$resumo.etapa = 'pre-requisitos'
if (-not (Test-Path (Join-Path $Repo '.git'))) {
    Falha "$Repo nao e um clone git do Redsis."
}
$projeto = Join-Path $Repo 'Projects\Redsis\Redsis.dproj'
if (-not (Test-Path $projeto)) {
    Falha "Projeto nao encontrado em $projeto."
}
if (-not (Test-Path $Rsvars)) {
    Falha ("rsvars.bat nao encontrado em $Rsvars - sem ele o msbuild nao acha os " +
           'caminhos de biblioteca do RAD Studio.')
}
if (-not (Test-Path $RarExe)) {
    Falha "Rar.exe nao encontrado em $RarExe. So o WinRAR gera .rar; instale ou aponte -RarExe."
}
if ($Versao) {
    if ($Config -ne 'Release') {
        Falha '-Versao so vale com -Config Release. Em Debug o version info nao e ajustado.'
    }
    if ($Versao -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        Falha "Versao '$Versao' invalida - use Major.Minor.Release.Build, ex. 4.1.15.17."
    }
}

if ($SemCheckout -and -not $Remoto) {
    Falha '-SemCheckout so existe no modo -Remoto: e a bancada do servidor.'
}
if ($SoCompilar -and -not $SemCheckout) {
    Falha '-SoCompilar acompanha -SemCheckout: validar a arvore da bancada e o unico uso dele.'
}
if ($Remoto) {
    # O worktree dedicado e o que torna seguro descartar estado local mais adiante. No
    # checkout principal isso apagaria trabalho do programador: recusar, nao adivinhar.
    $gitDir = "$(Git-Redsis rev-parse --path-format=absolute --git-dir | Select-Object -First 1)".Trim()
    $gitComum = "$(Git-Redsis rev-parse --path-format=absolute --git-common-dir | Select-Object -First 1)".Trim()
    if (-not $script:GitOk -or $gitDir -eq $gitComum) {
        Falha "-Remoto so compila em worktree dedicado, e $Repo e um checkout principal."
    }
    if ($SemCheckout -and $PularBuild) {
        Falha '-SemCheckout e -PularBuild se excluem: um compila a arvore, o outro nao compila.'
    }
    if ($Confirmar -and -not $PularBuild) {
        Falha '-Remoto so anexa o pacote ja conferido no dry-run: use -PularBuild com -Confirmar.'
    }
    if ($Confirmar -and $Sha256Esperado -notmatch '^[0-9A-Fa-f]{64}$') {
        Falha '-Remoto com -Confirmar exige -Sha256Esperado com o SHA-256 completo do dry-run.'
    }
}

# Sem -Chamado o identificador vem da branch. E o caso da branch de integracao,
# que nao tem numero: exige -Branch e -SemAnexar, porque sem numero nao existe
# chamado para receber o anexo, e adivinhar destino no SAC e o pior erro daqui.
if ($Chamado -and $Chamado -notmatch '^\d{7,9}$') {
    Falha "Chamado '$Chamado' invalido - use 7 a 9 digitos."
}
if ($Identificador) {
    # A bancada nomeia a propria pasta: a arvore pode nem estar numa branch de chamado.
    if ($Identificador -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,59}$') {
        Falha "Identificador '$Identificador' invalido."
    }
    $identificador = $Identificador
}
elseif ($Chamado) {
    $identificador = $Chamado
}
else {
    if ($SemCheckout)    { Falha 'Com -SemCheckout, informe -Chamado ou -Identificador para nomear a pasta.' }
    if (-not $Branch)    { Falha 'Sem -Chamado, -Branch e obrigatorio: nao ha numero para resolver a branch.' }
    if (-not $SemAnexar) { Falha 'Sem -Chamado nao existe chamado para anexar: rode com -SemAnexar.' }
    $identificador = ($Branch -split '/')[-1]
    if (-not $identificador) { Falha "Nao consegui derivar um identificador de '$Branch'." }
}
$resumo.chamado = $Chamado
$resumo.identificador = $identificador

$trabalho = Join-Path $PastaTrabalho $identificador
$script:trabalho = $trabalho
New-Item -ItemType Directory -Force -Path $trabalho | Out-Null
$base = "Redsis_$identificador"
$nome = $base
$resumo.pasta = $trabalho

# Com -PularBuild o pacote e o da execucao anterior: config, branch, commit e o NOME
# escolhido la vem de resumo.json. Lido ANTES do primeiro Salva-Resumo, que sobrescreve
# o arquivo.
$resumoAnterior = Join-Path $trabalho 'resumo.json'
if ($PularBuild -and (Test-Path $resumoAnterior)) {
    try {
        $anterior = Get-Content -LiteralPath $resumoAnterior -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($anterior.config) { $resumo.config = "$($anterior.config)" }
        if ($anterior.commit) { $resumo.commit = "$($anterior.commit)" }
        # A branch tambem e a do dry-run, e nao uma resolvida de novo: o pacote da bancada
        # nasce em trabalho/<x>, que so existe no servidor e nunca foi publicada.
        if ($anterior.branch) { $resumo.branch = "$($anterior.branch)" }
        if ($anterior.pull) { $resumo.pull = "$($anterior.pull)" }
        if ($anterior.arquivo) {
            # O "pode" vale para o pacote do dry-run, com o nome que o programador viu.
            # Recalcular aqui trocaria o numero do anexo entre conferir e enviar.
            $nome = [System.IO.Path]::GetFileNameWithoutExtension("$($anterior.arquivo)")
        }
    }
    catch { }
}

# --------------------------------------------------------------------- nome do anexo
# Escolhido ANTES de compilar: e ele que nomeia exe e rar, e o nome do arquivo e o nome
# com que o anexo chega ao chamado. So quando ha chamado para receber: sem anexo
# (integracao, download) nao ha lista com que comparar, e o nome base basta.
if ($Chamado -and -not $SemAnexar -and -not $PularBuild) {
    Etapa 'nome'
    $listados = $null
    $brutoAnexos = Join-Path $trabalho 'anexos-raw.json'
    if (Test-Path -LiteralPath $brutoAnexos) { Remove-Item -LiteralPath $brutoAnexos -Force }
    & powershell -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path (Materializa-Ci) 'sac_anexos.ps1') -Codigo $Chamado -Saida $brutoAnexos 2>&1 |
        Out-Null
    if (Test-Path -LiteralPath $brutoAnexos) {
        try {
            $bruto = Get-Content -LiteralPath $brutoAnexos -Raw -Encoding UTF8 | ConvertFrom-Json
            # Sem a propriedade 'result' a resposta nao e a lista de anexos: tratar isso
            # como "chamado sem anexo" faria a copia sair com o nome base e SUBSTITUIR a
            # anterior sem ninguem saber.
            if ($null -ne $bruto -and $bruto.PSObject.Properties.Name -contains 'result') {
                $listados = @($bruto.result | ForEach-Object { "$($_.nome)" } | Where-Object { $_ })
            }
        }
        catch { $listados = $null }
    }
    if ($null -eq $listados) {
        # Sem a lista nao da para saber o proximo numero. Sai com o nome base, que
        # SUBSTITUI a copia anterior - ruim, mas melhor que deixar quem testa sem exe.
        $resumo.anexos_lidos = $false
        Escreve ("Nao consegui listar os anexos do chamado $Chamado - o pacote sai como " +
                 "$base.rar e SUBSTITUI a copia anterior no chamado.") Yellow
    }
    else {
        $resumo.anexos_lidos = $true
        $resumo.anexos_no_chamado = $listados.Count
        $nome = Proximo-Nome $base $listados
        if ($nome -ne $base) {
            Escreve ("O chamado $Chamado ja tem copia anexada: esta sai como $nome.rar, " +
                     'sem substituir a anterior.') Cyan
        }
    }
}

$exe = Join-Path $trabalho "$nome.exe"
$rar = Join-Path $trabalho "$nome.rar"
Salva-Resumo

$rotulo = if ($Chamado) { "Chamado $Chamado" } else { $identificador }
Escreve "$rotulo  |  $Config/Win32  |  pasta de trabalho: $trabalho" Cyan

# ------------------------------------------------------------------------- branch
Etapa 'branch'
if ($PularBuild) {
    # Anexo: nada e compilado nem posicionado, e a branch ja veio do resumo do dry-run.
    # Resolver de novo aqui so podia falhar - o pacote da bancada nasce em trabalho/<x>,
    # que nao existe em origin, e a branch do chamado pode ter sido apagada entre o
    # dry-run e o "pode".
    $alvo = "$($resumo.branch)"
}
elseif ($SemCheckout) {
    # A bancada ja esta posicionada: compilar o que esta ali, inclusive merge resolvido
    # e ainda nao commitado. Tocar em branch aqui descartaria exatamente esse trabalho.
    $alvo = "$(Git-Redsis rev-parse --abbrev-ref HEAD | Select-Object -First 1)".Trim()
    if (-not $script:GitOk) { Falha "Nao consegui ler o estado de $Repo." }
    $resumo.branch = $alvo
    $resumo.commit = "$(Git-Redsis rev-parse HEAD | Select-Object -First 1)".Trim().Substring(0, 12)
    $resumo.pull = 'BANCADA'
    Escreve "Bancada: $alvo em $($resumo.commit), compilada como esta." Cyan
}
elseif ($Remoto) {
    # No servidor so vale o que esta publicado, entao o fetch vem antes de resolver.
    Git-Redsis fetch --prune origin | Out-Null
    if (-not $script:GitOk) { Falha 'Nao consegui atualizar as referencias de origin.' }
}
if ($PularBuild -or $SemCheckout) {
    # $alvo ja veio do resumo do dry-run ou do HEAD da bancada, acima: nada a resolver.
}
elseif ($Branch) {
    $alvo = $Branch
    $script:GitOk = $false
    if (-not $Remoto) { Git-Redsis rev-parse --verify --quiet "refs/heads/$alvo" | Out-Null }
    if (-not $script:GitOk) {
        Git-Redsis rev-parse --verify --quiet "refs/remotes/origin/$alvo" | Out-Null
        if (-not $script:GitOk) { Falha "Branch '$alvo' nao existe local nem em origin." }
    }
}
else {
    # Branch so local nao existe para o servidor: la, compilar e compilar o remoto.
    # @() por fora: um if que devolve um elemento so vira string, e splat de string nao
    # passa o ref - medido, o -Remoto dizia que nenhuma branch existia.
    $escopo = @(if ($Remoto) { 'refs/remotes/origin' } else { 'refs/heads'; 'refs/remotes/origin' })
    $refs = Git-Redsis for-each-ref --format='%(refname:short)' @escopo
    if (-not $script:GitOk) { Falha "Nao consegui listar as branches de $Repo." }
    $rx = "^(?:origin/)?(Tags|Corretivos|Evolutivos)/$Chamado$"
    $achadas = @($refs |
        Where-Object { $_ -match $rx } |
        ForEach-Object { $_ -replace '^origin/', '' } |
        Select-Object -Unique)
    if ($achadas.Count -eq 0) {
        Falha ("Nenhuma branch Tags/$Chamado, Corretivos/$Chamado ou Evolutivos/$Chamado " +
               'existe local ou em origin. O chamado precisa de branch antes de gerar exe; ' +
               'para Integracoes/ ou outro nome, passe -Branch.')
    }
    if ($achadas.Count -gt 1) {
        Falha ("O numero $Chamado tem branch em mais de uma categoria: " + ($achadas -join ', ') +
               '. Escolher por conta propria compilaria a arvore errada - informe ' +
               '-Branch <nome completo>.')
    }
    $alvo = $achadas[0]
}
$resumo.branch = $alvo
Escreve "Branch: $alvo" Cyan

# ---------------------------------------------------------- checkout limpo e pull
if ($PularBuild) {
    if (-not (Test-Path $rar)) {
        Falha "-PularBuild pediu para reusar $rar, e ele nao existe. Rode sem -PularBuild."
    }
    Escreve "Reusando o pacote ja compilado: $(Split-Path -Leaf $rar) ($(Mb-De $rar) MB)" Yellow
    $resumo.build = 'REUSADO'
}
else {
    Etapa 'checkout'
    if ($SemCheckout) {
        Escreve 'Bancada: nenhum checkout - a arvore e compilada como esta.' Gray
    }
    elseif ($Remoto) {
        # Worktree dedicado: ninguem edita nele, entao descartar o que sobrou do build
        # anterior e seguro - e e o que garante compilar o remoto tal como esta, sem
        # merge nem commit local no caminho.
        Git-Redsis checkout --detach --force "origin/$alvo" | Out-Null
        if (-not $script:GitOk) { Falha "Nao consegui posicionar o worktree em origin/$alvo." }
        $resumo.pull = 'REMOTO'
        Escreve "Worktree posicionado em origin/$alvo, sem merge." Gray
    }
    else {
        $sujo = @(Git-Redsis status --porcelain)
        if ($sujo.Count -gt 0) {
            Escreve 'Alteracoes em aberto no checkout principal:' Yellow
            $sujo | Select-Object -First 20 | ForEach-Object { Escreve "  $_" Yellow }
            Falha ("O checkout $Repo tem alteracao nao commitada. Puxar a branch e compilar por " +
                   'cima disso mistura ou descarta trabalho do programador. Comite, guarde com ' +
                   'git stash ou resolva antes de gerar o exe.')
        }

        $origem = (Git-Redsis rev-parse --abbrev-ref HEAD | Select-Object -First 1).Trim()
        $resumo.branch_anterior = $origem
        if ($origem -ne $alvo) {
            Escreve "Trocando o checkout de $origem para $alvo..." Gray
            Git-Redsis checkout $alvo | Out-Null
            if (-not $script:GitOk) { Falha "Nao consegui fazer checkout de $alvo." }
        }

        Etapa 'pull'
        Git-Redsis fetch origin $alvo | Out-Null
        if ($script:GitOk) {
            $antes = (Git-Redsis rev-parse HEAD | Select-Object -First 1).Trim()
            $saidaMerge = Git-Redsis merge --ff-only "origin/$alvo"
            if (-not $script:GitOk) {
                Escreve ($saidaMerge -join [Environment]::NewLine) Yellow
                Falha ("origin/$alvo divergiu do local: o fast-forward nao aplica. Resolver isso e " +
                       'decisao do programador (merge, rebase ou reset) - nao do gerador de exe.')
            }
            $depois = (Git-Redsis rev-parse HEAD | Select-Object -First 1).Trim()
            if ($antes -eq $depois) {
                Escreve "Branch ja estava atualizada em $($depois.Substring(0,12))." Gray
            }
            else {
                Escreve "Puxado: $($antes.Substring(0,12)) -> $($depois.Substring(0,12))" Green
            }
        }
        else {
            Escreve "AVISO: origin/$alvo nao existe - branch so local, nada a puxar." Yellow
            $resumo.pull = 'SEM_REMOTO'
        }
    }
    $resumo.commit = (Git-Redsis rev-parse HEAD | Select-Object -First 1).Trim().Substring(0, 12)

    # ---------------------------------------------- arquivos que o build reescreve
    # O Delphi REGENERA Projects\Redsis\Redsis.res a cada compilacao, e ele e
    # versionado: com -Versao, a versao temporaria fica gravada dentro dele e
    # sobrevive a compilacao - medido, o git acusava ' M Redsis.res' depois de
    # uma Release 4.1.15.99. Backup por copia (nao por 'git checkout --', que
    # apagaria alteracao alheia se alguma escapasse da conferencia acima).
    $res = Join-Path $Repo 'Projects\Redsis\Redsis.res'
    $backupRes = $null
    if (Test-Path $res) {
        $backupRes = Join-Path $trabalho 'Redsis.res.original'
        Copy-Item -LiteralPath $res -Destination $backupRes -Force
    }

    # ------------------------------------------------------- version info (Release)
    $backupDproj = $null
    $hashOriginal = $null
    if ($Versao) {
        $resumo.etapa = 'version-info'
        $backupDproj = Join-Path $trabalho 'Redsis.dproj.original'
        Copy-Item -LiteralPath $projeto -Destination $backupDproj -Force
        $hashOriginal = Hash-De $projeto
        $p = $Versao.Split('.')

        # Regex no texto cru, e nao [xml]: o objetivo aqui e devolver o arquivo
        # exatamente como estava, e reserializar XML muda espacos e atributos.
        $texto = [System.IO.File]::ReadAllText($projeto)
        $texto = [regex]::Replace($texto, '(?<=<VerInfo_MajorVer>)[^<]*', $p[0])
        $texto = [regex]::Replace($texto, '(?<=<VerInfo_MinorVer>)[^<]*', $p[1])
        $texto = [regex]::Replace($texto, '(?<=<VerInfo_Release>)[^<]*', $p[2])
        $texto = [regex]::Replace($texto, '(?<=<VerInfo_Build>)[^<]*', $p[3])
        $texto = [regex]::Replace($texto, '(?<=FileVersion=)[^;<]*', $Versao)
        $texto = [regex]::Replace($texto, '(?<=ProductVersion=)[^;<]*', $Versao)
        [System.IO.File]::WriteAllText($projeto, $texto, (New-Object System.Text.UTF8Encoding($true)))
        Escreve "Version info ajustado temporariamente para $Versao (original em $backupDproj)." Gray
    }

    # ------------------------------------------------------------------ compilacao
    Etapa 'compilacao'
    Escreve "Compilando $Config/Win32 (1.661 units; costuma levar minutos)..." Cyan
    $cmd = "call `"$Rsvars`" && msbuild `"$projeto`" /t:Build /p:Config=$Config " +
           '/p:Platform=Win32 /nologo /v:minimal'
    $logBuild = Join-Path $trabalho 'msbuild.log'
    $t0 = Get-Date

    # ProcessStartInfo, e nao Start-Process: com -PassThru e a sobrecarga
    # WaitForExit(ms), o ExitCode volta VAZIO - e '$null -ne 0' e verdadeiro,
    # entao um build que terminou bem era reportado como quebrado. Aqui o
    # codigo de saida vem do proprio objeto, ja com o processo encerrado.
    # As duas saidas sao lidas em paralelo de proposito: ler uma so ate o fim
    # enche o buffer da outra e travaria o msbuild no meio da compilacao.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $env:ComSpec
    $psi.Arguments = "/c $cmd"
    $psi.WorkingDirectory = $Repo
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $lendoSaida = $proc.StandardOutput.ReadToEndAsync()
    $lendoErro = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit($TimeoutBuild * 1000)) {
        try { $proc.Kill() } catch { }
        if ($backupDproj) { Copy-Item -LiteralPath $backupDproj -Destination $projeto -Force }
        if ($backupRes) { Copy-Item -LiteralPath $backupRes -Destination $res -Force }
        Falha "Timeout de compilacao ($TimeoutBuild s). O .dproj e o .res foram restaurados."
    }
    $seg = [int]((Get-Date) - $t0).TotalSeconds
    $codigoSaida = $proc.ExitCode
    [System.IO.File]::WriteAllText($logBuild,
        ($lendoSaida.Result + [Environment]::NewLine + $lendoErro.Result))
    $resumo.segundos = $seg

    # Restaurar o .dproj ANTES de avaliar o resultado: a alteracao de versao e
    # temporaria e nao pode sobreviver a uma compilacao que quebrou.
    if ($backupDproj) {
        Copy-Item -LiteralPath $backupDproj -Destination $projeto -Force
        if ((Hash-De $projeto) -ne $hashOriginal) {
            Falha ("O .dproj NAO voltou ao estado original. Confira com git diff e restaure " +
                   "de $backupDproj.")
        }
        Escreve 'Version info restaurado e conferido por SHA-256.' Gray
    }
    if ($backupRes) {
        Copy-Item -LiteralPath $backupRes -Destination $res -Force
    }

    # O checkout estava limpo antes da compilacao (conferido acima), entao
    # qualquer arquivo versionado sujo agora e resto do build. Restaurar o que
    # se conhece e RELATAR o resto, sem tocar: apagar por conta propria uma
    # alteracao nao identificada e o erro caro deste passo.
    $sobrou = @(Git-Redsis status --porcelain)
    if ($sobrou.Count -gt 0) {
        $resumo.arquivos_sujos = $sobrou
        Escreve ''
        Escreve 'ATENCAO: a compilacao deixou arquivo versionado alterado:' Yellow
        $sobrou | ForEach-Object { Escreve "  $_" Yellow }
        Escreve 'Nao foi revertido por este script - confira com git diff.' Yellow
    }

    if ($codigoSaida -ne 0) {
        $erros = @(Get-Content -LiteralPath $logBuild -ErrorAction SilentlyContinue |
            Where-Object { $_ -match ': error ' -or $_ -match '^error' } |
            ForEach-Object { ($_ -replace '\s*\[[^\]]*\.dproj\]\s*$', '').Trim() } |
            Select-Object -First 15)
        if ($erros.Count -eq 0) {
            $erros = @(Get-Content -LiteralPath $logBuild -ErrorAction SilentlyContinue |
                Where-Object { $_.Trim() } | Select-Object -Last 5)
        }
        $resumo.erros = $erros
        Escreve ''
        Escreve "Compilacao falhou em ${seg}s (msbuild saiu $codigoSaida):" Red
        $erros | ForEach-Object { Escreve "  $_" Red }
        Falha "Nada foi compactado nem anexado. Log completo em $logBuild."
    }

    $gerado = Join-Path $Repo "Projects\Redsis\Win32\$Config\Redsis.exe"
    if (-not (Test-Path $gerado)) {
        Falha "msbuild terminou 0 mas o exe nao esta em $gerado."
    }
    Escreve "Compilado em ${seg}s: $gerado ($(Mb-De $gerado) MB)" Green

    # Validar a resolucao do conflito termina aqui: empacotar 42 MB e falar com o SAC
    # nao prova nada sobre o merge, e o exe da bancada sai depois, num pedido proprio.
    if ($SoCompilar) {
        $resumo.status = 'COMPILADO'
        Etapa 'fim'
        Escreve 'Compilacao validada; nada foi empacotado (-SoCompilar).' Cyan
        exit 0
    }

    # Copia, nao move: o exe em Win32\<Config> e o que o fluxo de teste do
    # chamado abre, e mover deixaria aquele caminho vazio sem avisar ninguem.
    Copy-Item -LiteralPath $gerado -Destination $exe -Force

    if ($Versao) {
        $resumo.etapa = 'conferencia-versao'
        $info = (Get-Item -LiteralPath $exe).VersionInfo
        # Comparacao EXATA, nao prefixo: com -like "$Versao*" um exe 4.1.15.10
        # passaria por 4.1.15.1. A virgula aparece quando o metadado vem no
        # formato '4, 1, 15, 17' de algumas ferramentas.
        $fv = (("$($info.FileVersion)" -replace ',\s*', '.')).Trim()
        $pv = (("$($info.ProductVersion)" -replace ',\s*', '.')).Trim()
        $resumo.file_version = $fv
        $resumo.product_version = $pv
        if ($fv -ne $Versao -or $pv -ne $Versao) {
            Falha ("O exe saiu com FileVersion='$fv' e ProductVersion='$pv', e nao com $Versao. " +
                   'Compilar sem erro nao prova a versao - o pacote nao sera enviado.')
        }
        Escreve "Versao conferida no exe: $fv" Green
    }

    # ------------------------------------------------------------------ compactar
    Etapa 'compactar'
    if (Test-Path $rar) { Remove-Item -LiteralPath $rar -Force }
    # a -ep : sem caminho dentro do arquivo   -y : nao pergunta nada
    & $RarExe a -ep -y $rar $exe | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $rar)) {
        Falha "Rar.exe saiu $LASTEXITCODE - nao consegui compactar $exe."
    }
    Escreve "Compactado: $(Split-Path -Leaf $rar) ($(Mb-De $rar) MB, de $(Mb-De $exe) MB)" Green
    if ($Remoto) {
        # No servidor ninguem abre esta copia, e o anexo so usa o .rar: sao 233 MB a
        # menos num disco que ja divide espaco com o worktree e a saida do build.
        Remove-Item -LiteralPath $exe -Force
    }
}

$resumo.arquivo = Split-Path -Leaf $rar
$resumo.mb = Mb-De $rar
$resumo.sha256 = Hash-De $rar

if ($SemAnexar) {
    $resumo.status = 'PACOTE_PRONTO'
    $resumo.etapa = 'fim'
    Salva-Resumo
    Escreve ''
    Escreve "Pacote pronto e NAO anexado (-SemAnexar): $rar" Cyan
    exit 0
}

# ----------------------------------------------------------- scripts do SAC (CI)
Etapa 'sac'
$ciDir = Materializa-Ci

# Quem e o chamado, na fonte. Um digito errado no numero anexa dezenas de MB no
# atendimento de outro cliente - e o assunto e o que deixa isso visivel antes.
$assunto = ''
$brutoTicket = Join-Path $trabalho 'ticket-raw.json'
& powershell -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $ciDir 'sac_fetch.ps1') -Codigo $Chamado -Saida $brutoTicket 2>&1 |
    Out-Null
if (Test-Path $brutoTicket) {
    try {
        $t = (Get-Content -LiteralPath $brutoTicket -Raw -Encoding UTF8 | ConvertFrom-Json).result[0]
        $assunto = "$($t.assunto)"
        $resumo.assunto = $assunto
        $resumo.status_chamado = "$($t.status)"
    }
    catch { }
}
if (-not $assunto) { $assunto = '(assunto nao lido - confira o numero antes de confirmar)' }
Escreve ''
Escreve "Chamado $Chamado - $assunto" Cyan
Escreve ("Anexo: $($resumo.arquivo)  |  $($resumo.mb) MB  |  " +
         "SHA-256 $($resumo.sha256.Substring(0,16))...") Cyan

# O dry-run mostrou um SHA-256 ao programador; o "pode" vale para AQUELE pacote. Se ele
# foi regerado no meio (outro pedido do mesmo chamado), o anexo nao sai.
if ($Confirmar -and $Sha256Esperado -and $resumo.sha256 -ne $Sha256Esperado.ToUpperInvariant()) {
    Falha ("O pacote atual (SHA-256 $($resumo.sha256)) nao e o conferido no dry-run " +
           "($Sha256Esperado). Nada foi enviado - gere e confira de novo.")
}

# ---------------------------------------------------------------------- anexar
$argsAnexo = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
               (Join-Path $ciDir 'sac_anexar.ps1'),
               '-Codigo', $Chamado, '-Arquivo', $rar)
if ($Confirmar) { $argsAnexo += '-Confirmar' }
& powershell @argsAnexo
$enviado = ($LASTEXITCODE -eq 0 -and $Confirmar)

if (-not $Confirmar) {
    $resumo.status = 'DRY_RUN'
    $resumo.etapa = 'fim'
    Salva-Resumo
    Escreve ''
    Escreve 'Nada foi enviado ao chamado. Para anexar de verdade, sem recompilar:' Yellow
    Escreve "  powershell -File `"$PSCommandPath`" -Chamado $Chamado -PularBuild -Confirmar" Yellow
    exit 0
}
if (-not $enviado) {
    $resumo.status = 'ANEXO_FALHOU'
    Salva-Resumo
    Falha "O anexo NAO foi enviado. O pacote foi preservado em $rar para nova tentativa."
}

$resumo.status = 'OK'
$resumo.anexado = $true
Escreve "Anexado ao chamado $Chamado." Green

# --------------------------------------------------------------------- limpeza
# Dezenas de MB por geracao enchem o disco. So limpa depois do envio confirmado:
# se falhou, o pacote fica para nova tentativa sem recompilar.
if ($ManterArquivos) {
    $resumo.limpo = $false
    Escreve "Arquivos mantidos em $trabalho (-ManterArquivos)." Gray
}
else {
    foreach ($f in $exe, $rar) {
        if (Test-Path $f) { Remove-Item -LiteralPath $f -Force }
    }
    $resumo.limpo = $true
    Escreve 'Exe e rar locais removidos; log e resumo.json ficam.' Gray
}
$resumo.etapa = 'fim'
Salva-Resumo
exit 0
