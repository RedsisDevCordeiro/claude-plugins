<#
.SYNOPSIS
    Atualiza o ACBr DESTA maquina pelo SVN e o reinstala pelo ACBrInstall_Trunk2.exe, sem clique.

.DESCRIPTION
    E o procedimento de sempre - "SVN Update" na pasta do ACBr e o assistente do
    ACBrInstall_Trunk2.exe ate "Iniciar a Instalacao" -, feito por script:

      1. acha a pasta do ACBr pelo Library Path Win32 do Delphi (ou -Pasta);
      2. confere: Delphi fechado, svn.exe presente, copia de trabalho sem alteracao local e
         o ACBrInstall_Trunk2.ini com IDEs e pacotes marcados - e o .ini que o assistente
         rele, entao as opcoes da ultima instalacao feita a mao valem de novo;
      3. svn update como o usuario, sem elevacao, ate HEAD ou -Revisao;
      4. abre o ACBrInstall_Trunk2.exe elevado (um UAC) e conduz o assistente por mensagens
         de janela: Proximo ate "Instalacao", "Iniciar a Instalacao" e a caixa final;
      5. le o log do instalador (log_<Delphi>_Win32.txt) e so declara OK se ele confirmar
         pacotes compilados e instalados, sem erro.

    O instalador nao tem linha de comando, e tudo o que ele faz continua sendo ele quem faz:
    pacotes, Library Path, Known Packages, DLLs. Este script so clica e confere.

    Sem -Executar e dry-run: revisao atual, revisao remota, commits pendentes e o que
    impediria a execucao. Nada e alterado.

.PARAMETER Pasta
    Raiz do ACBr, onde fica o ACBrInstall_Trunk2.exe. Omitida, sai do Library Path Win32 do
    Delphi (...\Lib\Delphi\LibDxx\Win32).

.PARAMETER Revisao
    HEAD (padrao) ou um numero: atualiza, ou volta, para aquela revisao.

.PARAMETER Executar
    Faz de verdade. Sem ele, dry-run.

.PARAMETER SemUpdate
    Pula o svn update e so reinstala: update ja feito pelo TortoiseSVN, ou execucao anterior
    que parou antes da instalacao.

.PARAMETER Instalar
    Uso interno: o processo elevado que conduz o instalador e grava -Resumo.

.PARAMETER Resumo
    Uso interno, junto com -Instalar.

.PARAMETER TimeoutMinutos
    Tempo maximo da instalacao. Padrao 60.

.NOTES
    PowerShell 5.1. Gravado UTF-8 com BOM.
    Saida: linhas de andamento e, no fim, o resumo em JSON entre "=== RESUMO ===" e
    "=== FIM ===". O mesmo JSON fica em %LOCALAPPDATA%\redsis-acbr\ultima-execucao.json.
#>
[CmdletBinding()]
param(
    [string]$Pasta,
    [string]$Revisao = 'HEAD',
    [switch]$Executar,
    [switch]$SemUpdate,
    [switch]$Instalar,
    [string]$Resumo,
    [ValidateRange(5, 240)][int]$TimeoutMinutos = 60
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$PastaDados = Join-Path $env:LOCALAPPDATA 'redsis-acbr'
$Ansi = [Text.Encoding]::GetEncoding(1252)
# O instalador regrava este arquivo a cada execucao (DesligarDefines, a partir do .ini).
# Alteracao local nele e dele, nao de gente: reverter antes do update e seguro.
$IncDoInstalador = 'Fontes\ACBrComum\ACBr.inc'

function Escreve([string]$texto) { Write-Host $texto }
function Falha([string]$mensagem) { throw $mensagem }
function Normaliza([string]$caminho) { [IO.Path]::GetFullPath($caminho.Trim()).TrimEnd('\') }

function Elevado {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Grava-Json($objeto, [string]$caminho) {
    $pai = Split-Path $caminho -Parent
    if (-not (Test-Path $pai)) { $null = New-Item -ItemType Directory -Path $pai -Force }
    $temporario = "$caminho.tmp"
    [IO.File]::WriteAllText($temporario, ($objeto | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporario -Destination $caminho -Force
}

function Le-Json([string]$caminho) {
    if (-not (Test-Path -LiteralPath $caminho)) { return $null }
    try { return ([IO.File]::ReadAllText($caminho) | ConvertFrom-Json) } catch { return $null }
}

# --------------------------------------------------------------------------------- svn

function Acha-Svn {
    $comando = Get-Command svn.exe -ErrorAction SilentlyContinue
    if ($comando) { return $comando.Path }
    foreach ($base in @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($base -and (Test-Path (Join-Path $base 'TortoiseSVN\bin\svn.exe'))) { return (Join-Path $base 'TortoiseSVN\bin\svn.exe') }
    }
    return $null
}

function Aspas([string]$texto) {
    if ($texto -notmatch '[\s"]') { return $texto }
    return '"' + ($texto -replace '"', '\"') + '"'
}

# Process direto, e nao "& svn": a saida --xml e UTF-8 e o "&" a decodificaria na codepage
# do console, estragando acento de mensagem de commit.
function Invoke-Svn([string[]]$Argumentos, [switch]$Xml) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:Svn
    $info.Arguments = (@($Argumentos) + '--non-interactive' | ForEach-Object { Aspas $_ }) -join ' '
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    if ($Xml) { $info.StandardOutputEncoding = [Text.Encoding]::UTF8 } else { $info.StandardOutputEncoding = $Ansi }
    $info.StandardErrorEncoding = $Ansi
    $processo = [Diagnostics.Process]::Start($info)
    $saida = $processo.StandardOutput.ReadToEndAsync()
    $erro = $processo.StandardError.ReadToEnd()
    $processo.WaitForExit()
    [pscustomobject]@{ Codigo = $processo.ExitCode; Saida = $saida.Result; Erro = $erro }
}

function Resume-Erro([string]$texto) {
    ((($texto -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 3) -join ' / ')
}

function Info-Svn([string]$alvo, [string]$revisao) {
    $argumentos = @('info', '--xml')
    if ($revisao) { $argumentos += @('-r', $revisao) }
    $r = Invoke-Svn ($argumentos + $alvo) -Xml
    if ($r.Codigo -ne 0) { Falha ("svn info $alvo falhou: " + (Resume-Erro $r.Erro)) }
    $entrada = ([xml]$r.Saida).info.entry
    [pscustomobject]@{
        Revisao         = [int]$entrada.revision
        Url             = [string]$entrada.url
        UltimaAlteracao = [int]$entrada.commit.revision
        Data            = [string]$entrada.commit.date
    }
}

function Alteracoes-Locais([string]$raiz) {
    $r = Invoke-Svn @('status', '--xml', '-q', $raiz) -Xml
    if ($r.Codigo -ne 0) { Falha ("svn status falhou: " + (Resume-Erro $r.Erro)) }
    $lista = @()
    foreach ($entrada in @(([xml]$r.Saida).status.target.entry)) {
        if (-not $entrada) { continue }
        $estado = $entrada.'wc-status'
        $marcas = @()
        if ([string]$estado.item -notin @('normal', 'unversioned', 'ignored', 'external', 'none', '')) { $marcas += [string]$estado.item }
        if ([string]$estado.props -in @('modified', 'conflicted')) { $marcas += "props-$($estado.props)" }
        if ([string]$estado.'tree-conflicted' -eq 'true') { $marcas += 'tree-conflict' }
        if ([string]$estado.'wc-locked' -eq 'true') { $marcas += 'travado' }
        if ($marcas.Count -eq 0) { continue }
        $caminho = [string]$entrada.path
        if ($caminho.StartsWith($raiz, [StringComparison]::OrdinalIgnoreCase)) { $caminho = $caminho.Substring($raiz.Length).TrimStart('\', '/') }
        $lista += [pscustomobject]@{ caminho = $caminho; estado = ($marcas -join ',') }
    }
    return $lista
}

# Commits entre duas revisoes do trunk (exclusivo em $menor), mais novos primeiro.
function Commits-Entre([string]$url, [int]$menor, [int]$maior) {
    if ($maior -le $menor) { return [pscustomobject]@{ total = 0; recentes = @() } }
    $r = Invoke-Svn @('log', '--xml', '-r', ('{0}:{1}' -f $maior, ($menor + 1)), $url) -Xml
    if ($r.Codigo -ne 0) { return [pscustomobject]@{ total = $null; recentes = @(); erro = (Resume-Erro $r.Erro) } }
    $entradas = @(([xml]$r.Saida).log.logentry | Where-Object { $_ })
    $recentes = @(foreach ($entrada in ($entradas | Select-Object -First 15)) {
            $texto = "$($entrada.SelectSingleNode('msg').InnerText)"
            $data = "$($entrada.SelectSingleNode('date').InnerText)"
            [pscustomobject]@{
                revisao  = [int]$entrada.revision
                autor    = "$($entrada.SelectSingleNode('author').InnerText)"
                data     = $data.Substring(0, [Math]::Min(10, $data.Length))
                mensagem = "$(@($texto -split "`r?`n" | Where-Object { $_.Trim() })[0])".Trim()
            }
        })
    [pscustomobject]@{ total = $entradas.Count; recentes = $recentes }
}

# ------------------------------------------------------------ pasta, instalador e IDE

function Acha-Pastas {
    $achadas = New-Object Collections.Generic.List[string]
    foreach ($chave in @(Get-ChildItem 'HKCU:\Software\Embarcadero\BDS' -ErrorAction SilentlyContinue)) {
        $biblioteca = Get-ItemProperty -Path (Join-Path $chave.PSPath 'Library\Win32') -ErrorAction SilentlyContinue
        if (-not $biblioteca) { continue }
        foreach ($entrada in ([string]$biblioteca.'Search Path') -split ';') {
            if ($entrada -match '^(.+?)\\Lib\\Delphi\\Lib[^\\]+\\Win32\\?$') {
                $raiz = $Matches[1]
                if ((Test-Path (Join-Path $raiz 'ACBrInstall_Trunk2.exe')) -and -not ($achadas -contains $raiz)) { $achadas.Add($raiz) }
            }
        }
    }
    if ($achadas.Count -eq 0) {
        foreach ($candidata in @('C:\ACBr', 'C:\Developer\Componentes\ACBr', 'C:\Componentes\ACBr', 'D:\ACBr')) {
            if (Test-Path (Join-Path $candidata 'ACBrInstall_Trunk2.exe')) { $achadas.Add($candidata) }
        }
    }
    return $achadas.ToArray()
}

function Le-Ini([string]$arquivo) {
    $secoes = @{}
    $atual = ''
    foreach ($linha in [IO.File]::ReadAllLines($arquivo, $Ansi)) {
        $texto = $linha.Trim()
        if (-not $texto -or $texto.StartsWith(';')) { continue }
        if ($texto -match '^\[(.+)\]$') {
            $atual = $Matches[1].ToUpperInvariant()
            if (-not $secoes.ContainsKey($atual)) { $secoes[$atual] = @{} }
            continue
        }
        $igual = $texto.IndexOf('=')
        if ($igual -gt 0 -and $atual) { $secoes[$atual][$texto.Substring(0, $igual).Trim()] = $texto.Substring($igual + 1).Trim() }
    }
    return $secoes
}

# O assistente rele o .ini ao abrir. Tudo o que o faria parar numa caixa de dialogo ou
# instalar outra coisa e conferido aqui, antes de abri-lo.
function Estado-Instalador([string]$raiz) {
    $ini = Join-Path $raiz 'ACBrInstall_Trunk2.ini'
    $estado = [ordered]@{
        exe = (Test-Path (Join-Path $raiz 'ACBrInstall_Trunk2.exe')); ini = (Test-Path $ini)
        versao_ini = $null; versao_esperada = $null; diretorio = $null; plataformas = @(); pacotes = 0; problemas = @()
    }
    if (-not $estado.exe) { $estado.problemas += 'ACBrInstall_Trunk2.exe nao existe na pasta' }
    if (-not $estado.ini) {
        $estado.problemas += 'sem ACBrInstall_Trunk2.ini: rode o instalador a mao uma vez, marcando IDEs e pacotes - e esse .ini que a automacao reaproveita'
        return $estado
    }
    $secoes = Le-Ini $ini
    if ($secoes['CONFIG']) {
        $estado.versao_ini = $secoes['CONFIG']['VersaoArquivoIniConfig']
        $estado.diretorio = $secoes['CONFIG']['DiretorioInstalacao']
    }
    if ($secoes['PLATAFORMAS']) { $estado.plataformas = @(([string]$secoes['PLATAFORMAS']['Marcadas']) -split ';' | Where-Object { $_.Trim() }) }
    if ($secoes['PACOTES']) { $estado.pacotes = @($secoes['PACOTES'].Values | Where-Object { $_ -eq '1' }).Count }
    $fonte = Join-Path $raiz 'Projetos\ACBrInstall Trunk2\ACBr.InstallDelphiComponentes.pas'
    if ((Test-Path $fonte) -and ([IO.File]::ReadAllText($fonte, $Ansi) -match "cVersaoConfig\s*=\s*'([^']*)'")) { $estado.versao_esperada = $Matches[1] }

    if ($estado.plataformas.Count -eq 0) { $estado.problemas += 'nenhuma IDE marcada no .ini' }
    if ($estado.pacotes -eq 0) { $estado.problemas += 'nenhum pacote marcado no .ini' }
    if ($estado.diretorio -and (Normaliza $estado.diretorio) -ne (Normaliza $raiz)) {
        $estado.problemas += "o .ini instala a partir de '$($estado.diretorio)', nao desta pasta"
    }
    if ($estado.versao_esperada -and $estado.versao_ini -ne $estado.versao_esperada) {
        $estado.problemas += "o .ini e da versao '$($estado.versao_ini)' e o instalador espera '$($estado.versao_esperada)': ele vai pedir para apagar o .ini - rode-o a mao uma vez"
    }
    return $estado
}

function Delphi-Aberto { @(Get-Process -Name bds -ErrorAction SilentlyContinue).Count -gt 0 }
function Instalador-Aberto { @(Get-Process -Name ACBrInstall_Trunk2 -ErrorAction SilentlyContinue).Count -gt 0 }

# Os logs sao ANSI e o instalador recria cada um a cada execucao: vale o que mudou desde $desde.
function Le-Logs([string]$raiz, [datetime]$desde) {
    $resultado = [ordered]@{ arquivos = @(); compilados = 0; instalados = 0; concluiu = $true; erros = @(); avisos = 0 }
    $win32 = 0
    foreach ($log in @(Get-ChildItem -LiteralPath $raiz -Filter 'log_*.txt' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $desde })) {
        $resultado.arquivos += $log.FullName
        $texto = [IO.File]::ReadAllText($log.FullName, $Ansi)
        $resultado.compilados += ([regex]::Matches($texto, 'compilado com sucesso')).Count
        $resultado.instalados += ([regex]::Matches($texto, 'instalado com sucesso')).Count
        $resultado.avisos += ([regex]::Matches($texto, '(?m)^AVISO:')).Count
        foreach ($linha in $texto -split "`r?`n") {
            if ($linha -match 'Erro ao compilar|Ocorreu um erro|Ocorreu erro|Abortando|does not support command line| Error: E\d{4}| Fatal: F\d{4}') {
                if ($resultado.erros.Count -lt 25) { $resultado.erros += "$($log.Name): $($linha.Trim())" }
            }
        }
        if ($log.Name -like '*_Win32.txt') {
            $win32++
            if ($texto -notmatch 'INSTALANDO OUTROS REQUISITOS') { $resultado.concluiu = $false }
        }
    }
    if ($win32 -eq 0) { $resultado.concluiu = $false }
    return $resultado
}

# --------------------------------------------------------- conducao do assistente (elevado)

$CodigoJanela = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class AcbrJanela
{
    delegate bool EnumProc(IntPtr janela, IntPtr parametro);

    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, IntPtr parametro);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr pai, EnumProc callback, IntPtr parametro);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr janela, out uint processo);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr janela, StringBuilder texto, int maximo);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageTimeoutW")]
    static extern IntPtr SendMessageTimeoutTexto(IntPtr janela, uint mensagem, IntPtr w, StringBuilder l, uint flags, uint timeout, out IntPtr resultado);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr janela, uint mensagem, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr janela);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr janela);
    [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr janela);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr janela);
    [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr janela);
    [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr janela, int id);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr janela, out RECT retangulo);
    [DllImport("user32.dll")] static extern int MapWindowPoints(IntPtr de, IntPtr para, ref RECT retangulo, int pontos);
    [DllImport("user32.dll")] static extern IntPtr GetWindowDpiAwarenessContext(IntPtr janela);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr contexto);

    [StructLayout(LayoutKind.Sequential)]
    struct RECT { public int Left, Top, Right, Bottom; }

    const uint WM_GETTEXT = 0x000D, WM_CLOSE = 0x0010, WM_COMMAND = 0x0111;
    const uint WM_LBUTTONDOWN = 0x0201, WM_LBUTTONUP = 0x0202, MK_LBUTTON = 0x0001;
    const uint SMTO_ABORTIFHUNG = 0x0002, TDM_CLICK_BUTTON = 0x0466, BM_CLICK = 0x00F5;

    public static IntPtr[] Janelas(int processo)
    {
        List<IntPtr> lista = new List<IntPtr>();
        EnumWindows(delegate(IntPtr janela, IntPtr p) {
            uint dono;
            GetWindowThreadProcessId(janela, out dono);
            if (dono == (uint)processo) lista.Add(janela);
            return true;
        }, IntPtr.Zero);
        return lista.ToArray();
    }

    public static IntPtr[] Filhas(IntPtr pai)
    {
        List<IntPtr> lista = new List<IntPtr>();
        EnumChildWindows(pai, delegate(IntPtr janela, IntPtr p) { lista.Add(janela); return true; }, IntPtr.Zero);
        return lista.ToArray();
    }

    public static string Classe(IntPtr janela)
    {
        StringBuilder texto = new StringBuilder(256);
        GetClassName(janela, texto, texto.Capacity);
        return texto.ToString();
    }

    public static string Texto(IntPtr janela)
    {
        StringBuilder texto = new StringBuilder(4096);
        IntPtr resultado;
        if (SendMessageTimeoutTexto(janela, WM_GETTEXT, (IntPtr)texto.Capacity, texto, SMTO_ABORTIFHUNG, 2000, out resultado) == IntPtr.Zero) return "";
        return texto.ToString();
    }

    // Botao com janela (TButton, TBitBtn, botao de MessageBox): BN_CLICKED ao pai, que a VCL
    // devolve ao botao como CN_COMMAND -> Click. Post, e nao Send: o clique pode abrir modal.
    public static bool Clicar(IntPtr botao)
    {
        return PostMessage(GetParent(botao), WM_COMMAND, (IntPtr)(GetDlgCtrlID(botao) & 0xFFFF), botao);
    }

    // Segunda tentativa, se o BN_CLICKED nao andou: o proprio botao simula o clique.
    public static bool ClicarBm(IntPtr botao)
    {
        return PostMessage(botao, BM_CLICK, IntPtr.Zero, IntPtr.Zero);
    }

    public static bool ClicarId(IntPtr dialogo, int id)
    {
        return PostMessage(dialogo, WM_COMMAND, (IntPtr)(id & 0xFFFF), GetDlgItem(dialogo, id));
    }

    public static bool ClicarTaskDialog(IntPtr dialogo, int id)
    {
        return PostMessage(dialogo, TDM_CLICK_BUTTON, (IntPtr)id, IntPtr.Zero);
    }

    // TSpeedButton nao tem janela: o clique vai ao controle pai no ponto do botao, e a VCL o
    // entrega ao controle grafico que estiver ali.
    public static void ClicarEm(IntPtr janela, int x, int y)
    {
        IntPtr ponto = (IntPtr)(((y & 0xFFFF) << 16) | (x & 0xFFFF));
        PostMessage(janela, WM_LBUTTONDOWN, (IntPtr)MK_LBUTTON, ponto);
        PostMessage(janela, WM_LBUTTONUP, IntPtr.Zero, ponto);
    }

    public static void Fechar(IntPtr janela)
    {
        PostMessage(janela, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
    }

    // Retangulo de 'filha' em coordenadas de cliente de 'pai', no contexto de DPI da janela
    // alvo: o ponto do clique sai na escala que a VCL do instalador enxerga.
    public static int[] Retangulo(IntPtr filha, IntPtr pai)
    {
        try { SetThreadDpiAwarenessContext(GetWindowDpiAwarenessContext(pai)); } catch (EntryPointNotFoundException) { }
        RECT r;
        GetWindowRect(filha, out r);
        MapWindowPoints(IntPtr.Zero, pai, ref r, 2);
        return new int[] { r.Left, r.Top, r.Right, r.Bottom };
    }
}
'@

function Carrega-Janela { if (-not ('AcbrJanela' -as [type])) { Add-Type -TypeDefinition $CodigoJanela -Language CSharp } }

# So caixas de dialogo: MessageDlg da VCL (TMessageForm), MessageBox e TaskDialog (#32770).
# Janela de dica (THintWindow) aparece com o mouse em cima e nao pode passar por dialogo.
function Dialogo-Aberto([int]$processo) {
    foreach ($janela in [AcbrJanela]::Janelas($processo)) {
        if ([AcbrJanela]::IsWindowVisible($janela) -and ([AcbrJanela]::Classe($janela) -in @('TMessageForm', '#32770'))) { return $janela }
    }
    return $null
}

function Texto-Uia([IntPtr]$janela) {
    try {
        Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes -ErrorAction Stop
        $elemento = [Windows.Automation.AutomationElement]::FromHandle($janela)
        $todos = $elemento.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
        return ((@($todos | ForEach-Object { $_.Current.Name } | Where-Object { $_ }) | Select-Object -Unique) -join ' | ')
    }
    catch { return '' }
}

function Descreve-Dialogo([IntPtr]$janela) {
    $classe = [AcbrJanela]::Classe($janela)
    $filhas = [AcbrJanela]::Filhas($janela)
    $tipo = 'vcl'
    if ($classe -eq '#32770') {
        $tipo = 'messagebox'
        if (@($filhas | Where-Object { [AcbrJanela]::Classe($_) -eq 'DirectUIHWND' }).Count) { $tipo = 'taskdialog' }
    }
    $botoes = @(foreach ($filha in $filhas) {
            if ([AcbrJanela]::Classe($filha) -match 'Button' -and [AcbrJanela]::IsWindowVisible($filha)) {
                [pscustomobject]@{ Handle = $filha; Texto = ([AcbrJanela]::Texto($filha) -replace '&', '').Trim() }
            }
        })
    $texto = ''
    if ($tipo -eq 'messagebox') {
        $estatico = [AcbrJanela]::GetDlgItem($janela, 0xFFFF)
        if ($estatico -ne [IntPtr]::Zero) { $texto = [AcbrJanela]::Texto($estatico) }
    }
    if (-not $texto) { $texto = Texto-Uia $janela }
    [pscustomobject]@{ Handle = $janela; Tipo = $tipo; Titulo = [AcbrJanela]::Texto($janela); Texto = $texto; Botoes = $botoes }
}

function Resumo-Dialogo($dialogo) {
    [ordered]@{ tipo = $dialogo.Tipo; titulo = $dialogo.Titulo; texto = $dialogo.Texto; botoes = @($dialogo.Botoes | ForEach-Object { $_.Texto }) }
}

# Responde e confere que a caixa fechou. 'seguro' tenta Nao, Cancelar e OK, nessa ordem:
# nunca abre o log no bloco de notas nem confirma o que nao foi pedido.
function Responde($dialogo, [string]$quero) {
    $ids = @{ ok = 1; cancelar = 2; sim = 6; nao = 7 }
    $padroes = @{ ok = '^OK$'; cancelar = '^(Cancel|Cancelar)$'; sim = '^(Yes|Sim)$'; nao = '^(No|N.o)$' }
    $ordem = @($quero)
    if ($quero -eq 'seguro') { $ordem = @('nao', 'cancelar', 'ok') }
    foreach ($nome in $ordem) {
        $botao = @($dialogo.Botoes | Where-Object { $_.Texto -match $padroes[$nome] }) | Select-Object -First 1
        $clicou = $false
        switch ($dialogo.Tipo) {
            'taskdialog' { $clicou = [AcbrJanela]::ClicarTaskDialog($dialogo.Handle, $ids[$nome]) }
            'messagebox' {
                if ([AcbrJanela]::GetDlgItem($dialogo.Handle, $ids[$nome]) -ne [IntPtr]::Zero) { $clicou = [AcbrJanela]::ClicarId($dialogo.Handle, $ids[$nome]) }
            }
            default { if ($botao) { $clicou = [AcbrJanela]::Clicar($botao.Handle) } }
        }
        if (-not $clicou) { continue }
        for ($i = 0; $i -lt 10; $i++) {
            Start-Sleep -Milliseconds 300
            if (-not [AcbrJanela]::IsWindow($dialogo.Handle) -or -not [AcbrJanela]::IsWindowVisible($dialogo.Handle)) { return $nome }
        }
    }
    [AcbrJanela]::Fechar($dialogo.Handle)
    return 'fechar'
}

function Texto-Dialogo($dialogo) {
    $partes = @($dialogo.Titulo, $dialogo.Texto) | Where-Object { $_ }
    "[" + ($partes -join ': ') + "] botoes: " + (@($dialogo.Botoes | ForEach-Object { $_.Texto }) -join '/')
}

function Janela-Principal([int]$processo) {
    foreach ($janela in [AcbrJanela]::Janelas($processo)) {
        if ([AcbrJanela]::Classe($janela) -eq 'TfrmPrincipal' -and [AcbrJanela]::IsWindowVisible($janela)) { return $janela }
    }
    return [IntPtr]::Zero
}

function Pagina-Atual([IntPtr]$principal) {
    foreach ($janela in [AcbrJanela]::Filhas($principal)) {
        if ([AcbrJanela]::Classe($janela) -match '^TJvWizard\w*Page$' -and [AcbrJanela]::IsWindowVisible($janela)) {
            return [pscustomobject]@{ Handle = $janela; Nome = [AcbrJanela]::Texto($janela) }
        }
    }
    return $null
}

function Botao-Proximo([IntPtr]$principal) {
    foreach ($janela in [AcbrJanela]::Filhas($principal)) {
        if ([AcbrJanela]::IsWindowVisible($janela) -and (([AcbrJanela]::Texto($janela) -replace '&', '').Trim() -match '^Pr.ximo$')) { return $janela }
    }
    return [IntPtr]::Zero
}

function Conduz-Instalador([string]$raiz, $resumo, [string]$arquivo, [int]$minutos) {
    Carrega-Janela
    $inicio = Get-Date
    $resumo.etapa = 'abrindo o instalador'
    Grava-Json $resumo $arquivo
    $processo = Start-Process -FilePath (Join-Path $raiz 'ACBrInstall_Trunk2.exe') -WorkingDirectory $raiz -PassThru
    $principal = [IntPtr]::Zero
    try {
        $limite = (Get-Date).AddSeconds(90)
        while ($principal -eq [IntPtr]::Zero) {
            if ($processo.HasExited) { Falha "o instalador fechou sozinho ao abrir (codigo $($processo.ExitCode))" }
            $caixa = Dialogo-Aberto $processo.Id
            if ($caixa) {
                $d = Descreve-Dialogo $caixa
                $resumo.dialogo = Resumo-Dialogo $d
                Falha "caixa inesperada ao abrir o instalador $(Texto-Dialogo $d)"
            }
            if ((Get-Date) -gt $limite) { Falha 'a janela do instalador nao apareceu em 90 s' }
            Start-Sleep -Milliseconds 500
            $principal = Janela-Principal $processo.Id
        }

        # Proximo ate a pagina "Instalacao". Cada pagina valida e grava o .ini ao sair.
        $paginas = @()
        for ($passo = 0; $passo -lt 8; $passo++) {
            $pagina = Pagina-Atual $principal
            if (-not $pagina) { Falha 'nao achei a pagina visivel do assistente' }
            $paginas += $pagina.Nome
            $resumo.paginas = $paginas
            $resumo.etapa = "assistente: $($pagina.Nome)"
            Grava-Json $resumo $arquivo
            if ($pagina.Nome -match '^Instala') { break }
            $proximo = Botao-Proximo $principal
            if ($proximo -eq [IntPtr]::Zero) { Falha "sem botao Proximo na pagina '$($pagina.Nome)'" }
            if (-not [AcbrJanela]::IsWindowEnabled($proximo)) { Falha "Proximo desabilitado na pagina '$($pagina.Nome)'" }
            [void][AcbrJanela]::Clicar($proximo)
            $reforco = (Get-Date).AddSeconds(6)
            $limite = (Get-Date).AddSeconds(30)
            do {
                Start-Sleep -Milliseconds 400
                if ($processo.HasExited) { Falha 'o instalador fechou no meio do assistente' }
                if ($reforco -and (Get-Date) -gt $reforco -and [AcbrJanela]::IsWindowEnabled($proximo)) {
                    [void][AcbrJanela]::ClicarBm($proximo)
                    $reforco = $null
                }
                $caixa = Dialogo-Aberto $processo.Id
                if ($caixa) {
                    $d = Descreve-Dialogo $caixa
                    $resumo.dialogo = Resumo-Dialogo $d
                    Falha "caixa na pagina '$($pagina.Nome)' $(Texto-Dialogo $d)"
                }
                $agora = Pagina-Atual $principal
                if ((Get-Date) -gt $limite) { Falha "Proximo nao saiu da pagina '$($pagina.Nome)' em 30 s" }
            } while (-not $agora -or $agora.Handle -eq $pagina.Handle)
        }
        $pagina = Pagina-Atual $principal
        if (-not $pagina -or $pagina.Nome -notmatch '^Instala') { Falha ("o assistente nao chegou a pagina Instalacao; paginas: " + ($paginas -join ' > ')) }

        # "Iniciar a Instalacao" e um TSpeedButton, sem janela. No projeto ele fica logo abaixo
        # da barra de progresso (6 px), alinhado a direita com ela, 151 x 38: o ponto sai da
        # barra medida em tempo de execucao, o que ja inclui a escala de DPI.
        $barra = @([AcbrJanela]::Filhas($pagina.Handle) | Where-Object { [AcbrJanela]::Classe($_) -eq 'TProgressBar' }) | Select-Object -First 1
        if (-not $barra) { Falha 'nao achei a barra de progresso da pagina Instalacao: o layout do instalador mudou' }
        $r = [AcbrJanela]::Retangulo($barra, $pagina.Handle)
        $escala = ($r[3] - $r[1]) / 28.0
        if ($escala -lt 0.75 -or $escala -gt 4) { $escala = 1.0 }
        $proximo = Botao-Proximo $principal
        $comecou = $false
        foreach ($deslocamento in @(@(75, 25), @(40, 25), @(110, 25), @(75, 14), @(75, 36))) {
            $x = [int]($r[2] - $deslocamento[0] * $escala)
            $y = [int]($r[3] + $deslocamento[1] * $escala)
            $antes = (Get-Date).AddSeconds(-1)
            [AcbrJanela]::ClicarEm($pagina.Handle, $x, $y)
            $limite = (Get-Date).AddSeconds(8)
            do {
                Start-Sleep -Milliseconds 500
                if ($processo.HasExited -or (Dialogo-Aberto $processo.Id)) { $comecou = $true }
                elseif ($proximo -ne [IntPtr]::Zero -and -not [AcbrJanela]::IsWindowEnabled($proximo)) { $comecou = $true }
                elseif (@(Get-ChildItem -LiteralPath $raiz -Filter 'log_*.txt' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $antes }).Count) { $comecou = $true }
            } while (-not $comecou -and (Get-Date) -lt $limite)
            if ($comecou) { break }
        }
        if (-not $comecou) { Falha 'o clique em "Iniciar a Instalacao" nao iniciou a instalacao' }

        $resumo.etapa = 'instalando'
        Grava-Json $resumo $arquivo
        $limite = (Get-Date).AddMinutes($minutos)
        $ultima = Get-Date
        $caixa = $null
        while (-not $caixa) {
            Start-Sleep -Seconds 2
            if ($processo.HasExited) { Falha 'o instalador fechou durante a instalacao' }
            $caixa = Dialogo-Aberto $processo.Id
            if (-not $caixa -and (Get-Date) -gt $limite) { Falha "a instalacao passou de $minutos min sem terminar" }
            if (((Get-Date) - $ultima).TotalSeconds -ge 10) {
                $parcial = Le-Logs $raiz $inicio
                $resumo.pacotes_compilados = $parcial.compilados
                $resumo.pacotes_instalados = $parcial.instalados
                Grava-Json $resumo $arquivo
                $ultima = Get-Date
            }
        }
        Start-Sleep -Seconds 1
        $d = Descreve-Dialogo $caixa
        $resumo.dialogo = Resumo-Dialogo $d
        # Sucesso e MessageDlg so com OK ("compilados e instalados com sucesso"). Sim/Nao e a
        # de erro ("deseja visualizar o log?") e MessageBox classico e excecao: as duas, falha.
        $falhouNaCaixa = ($d.Tipo -eq 'messagebox') -or ($d.Texto -match 'erro') -or
            (@($d.Botoes | Where-Object { $_.Texto -match '^(No|N.o)$' }).Count -gt 0)
        if ($falhouNaCaixa) { [void](Responde $d 'seguro') } else { [void](Responde $d 'ok') }

        $logs = Le-Logs $raiz $inicio
        $resumo.logs = $logs.arquivos
        $resumo.pacotes_compilados = $logs.compilados
        $resumo.pacotes_instalados = $logs.instalados
        $resumo.avisos_log = $logs.avisos
        $resumo.erros = $logs.erros
        if ($falhouNaCaixa) { Falha "o instalador terminou com erro $(Texto-Dialogo $d)" }
        if ($logs.erros.Count) { Falha "a caixa final foi a de sucesso, mas o log tem erro: $($logs.erros[0])" }
        if (-not $logs.concluiu -or $logs.compilados -eq 0) {
            Falha 'a caixa final foi a de sucesso, mas o log Win32 nao confirma a instalacao (sem pacote compilado ou sem "INSTALANDO OUTROS REQUISITOS")'
        }
        $resumo.status = 'INSTALADO'
    }
    finally {
        if (-not $processo.HasExited) {
            $caixa = Dialogo-Aberto $processo.Id
            if ($caixa) { [void](Responde (Descreve-Dialogo $caixa) 'seguro') }
            if ($principal -ne [IntPtr]::Zero) { [AcbrJanela]::Fechar($principal) }
            if (-not $processo.WaitForExit(20000)) { Stop-Process -Id $processo.Id -Force -ErrorAction SilentlyContinue }
        }
    }
}

# ------------------------------------------------------------------- processo elevado

if ($Instalar) {
    # $registro, e nao $resumo: variavel do PowerShell ignora caixa, e $resumo sobrescreveria
    # o parametro -Resumo, que e o caminho do arquivo.
    $identidade = [Security.Principal.WindowsIdentity]::GetCurrent()
    $registro = [ordered]@{
        tipo = 'instalacao'; status = 'EM_ANDAMENTO'; etapa = 'preparando'; pasta = $Pasta
        usuario = $identidade.Name; sid = $identidade.User.Value; inicio = (Get-Date).ToString('s')
        pacotes_compilados = 0; pacotes_instalados = 0
    }
    try {
        if (-not $Resumo) { Falha '-Instalar exige -Resumo' }
        if (-not (Elevado)) { Falha '-Instalar precisa rodar elevado' }
        if (-not $Pasta -or -not (Test-Path (Join-Path $Pasta 'ACBrInstall_Trunk2.exe'))) { Falha "pasta do ACBr invalida: '$Pasta'" }
        if (Delphi-Aberto) { Falha 'o Delphi (bds.exe) esta aberto: feche-o antes de instalar' }
        if (Instalador-Aberto) { Falha 'ja ha um ACBrInstall_Trunk2 aberto: feche-o antes' }
        Conduz-Instalador (Normaliza $Pasta) $registro $Resumo $TimeoutMinutos
    }
    catch {
        $registro.status = 'FALHOU'
        $registro.erro = "$($_.Exception.Message)"
    }
    $registro.etapa = 'fim'
    $registro.fim = (Get-Date).ToString('s')
    if ($Resumo) { Grava-Json $registro $Resumo }
    if ($registro.status -eq 'INSTALADO') { exit 0 }
    exit 1
}

# ----------------------------------------------------------- dry-run e execucao (usuario)

function Confere-Ide([string]$raiz, [datetime]$desde) {
    $conferencia = [ordered]@{ known_packages = 0; library_path_win32 = $false; envoptions = @(); dcus_novos = 0 }
    foreach ($chave in @(Get-ChildItem 'HKCU:\Software\Embarcadero\BDS' -ErrorAction SilentlyContinue)) {
        $pacotes = Get-Item -Path (Join-Path $chave.PSPath 'Known Packages') -ErrorAction SilentlyContinue
        if ($pacotes) { $conferencia.known_packages += @($pacotes.Property | Where-Object { $_.StartsWith("$raiz\", [StringComparison]::OrdinalIgnoreCase) }).Count }
        $biblioteca = Get-ItemProperty -Path (Join-Path $chave.PSPath 'Library\Win32') -ErrorAction SilentlyContinue
        $doAcbr = @(([string]$biblioteca.'Search Path') -split ';' | Where-Object { $_.StartsWith("$raiz\", [StringComparison]::OrdinalIgnoreCase) })
        if (-not $doAcbr.Count) { continue }
        $conferencia.library_path_win32 = $true
        # O msbuild le o Library Path do EnvOptions.proj, que a IDE regrava; o instalador so
        # mexe no registro. Divergencia aqui quebra compilacao por linha de comando.
        $envOptions = Join-Path $env:APPDATA ("Embarcadero\BDS\{0}\EnvOptions.proj" -f $chave.PSChildName)
        if (Test-Path $envOptions) {
            $blocos = [regex]::Matches([IO.File]::ReadAllText($envOptions), "(?s)<PropertyGroup Condition=""'\`$\(Platform\)'=='Win32'"">(.*?)</PropertyGroup>")
            $textoWin32 = (@($blocos | ForEach-Object { $_.Groups[1].Value }) -join "`n")
            $faltam = @($doAcbr | Where-Object { $textoWin32.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -lt 0 })
            $conferencia.envoptions += [pscustomobject]@{ versao = $chave.PSChildName; confere = ($faltam.Count -eq 0) }
        }
    }
    foreach ($pastaLib in @(Get-ChildItem -LiteralPath (Join-Path $raiz 'Lib\Delphi') -Directory -ErrorAction SilentlyContinue)) {
        $win32 = Join-Path $pastaLib.FullName 'Win32'
        if (Test-Path $win32) { $conferencia.dcus_novos += @(Get-ChildItem -LiteralPath $win32 -Filter '*.dcu' | Where-Object { $_.LastWriteTime -ge $desde }).Count }
    }
    return $conferencia
}

function Espera-Elevado([string]$raiz, [string]$arquivo, [int]$minutos) {
    $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Aspas $PSCommandPath), '-Instalar',
        '-Pasta', (Aspas $raiz), '-Resumo', (Aspas $arquivo), '-TimeoutMinutos', $minutos) -join ' '
    try { $filho = Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -PassThru -ArgumentList $argumentos }
    catch { Falha "a elevacao (UAC) foi recusada ou nao esta disponivel: $($_.Exception.Message)" }
    $limite = (Get-Date).AddMinutes($minutos + 5)
    $ultimaLinha = ''
    while ($true) {
        try { $acabou = $filho.HasExited } catch { $acabou = -not (Get-Process -Id $filho.Id -ErrorAction SilentlyContinue) }
        if ($acabou) { break }
        $parcial = Le-Json $arquivo
        if ($parcial) {
            $linha = "  instalador: $($parcial.etapa) - $($parcial.pacotes_compilados) compilados, $($parcial.pacotes_instalados) instalados"
            if ($linha -ne $ultimaLinha) { Escreve $linha; $ultimaLinha = $linha }
        }
        if ((Get-Date) -gt $limite) { Falha 'o processo elevado passou do tempo limite; confira se o instalador ainda esta aberto' }
        Start-Sleep -Seconds 5
    }
    Start-Sleep -Seconds 1
    return (Le-Json $arquivo)
}

$inicio = Get-Date
$final = [ordered]@{ status = 'DRY_RUN'; pasta = $null; inicio = $inicio.ToString('s') }
$avisos = @()
$impedimentos = @()
if (-not (Test-Path $PastaDados)) { $null = New-Item -ItemType Directory -Path $PastaDados -Force }

try {
    if ($Revisao -notmatch '^(?i:HEAD|\d+)$') { Falha "-Revisao deve ser HEAD ou um numero; veio '$Revisao'" }
    $Revisao = $Revisao.ToUpperInvariant()

    $script:Svn = Acha-Svn
    if (-not $script:Svn) {
        Falha ("svn.exe nao encontrado. Instale as 'command line client tools' do TortoiseSVN: rode o " +
            "instalador do TortoiseSVN da mesma versao, escolha Modify e marque 'command line client tools'.")
    }
    $final.svn = $script:Svn

    if ($Pasta) { $raiz = Normaliza $Pasta }
    else {
        $achadas = @(Acha-Pastas)
        if ($achadas.Count -eq 0) { Falha 'nao achei a pasta do ACBr pelo Library Path do Delphi: informe -Pasta <raiz do ACBr>' }
        if ($achadas.Count -gt 1) { Falha ("mais de uma pasta do ACBr no Library Path (" + ($achadas -join '; ') + "): informe -Pasta") }
        $raiz = Normaliza $achadas[0]
    }
    $final.pasta = $raiz
    if (-not (Test-Path (Join-Path $raiz '.svn'))) { Falha "$raiz nao e raiz de copia de trabalho do SVN (sem .svn)" }

    Escreve "ACBr em $raiz"
    $local = Info-Svn $raiz ''
    $final.url = $local.Url
    $final.revisao_atual = $local.Revisao
    $final.ultima_alteracao_local = $local.UltimaAlteracao

    if ($Revisao -eq 'HEAD') {
        $remota = Info-Svn $local.Url 'HEAD'
        $alvo = $remota.UltimaAlteracao
        $final.revisao_remota = $alvo
        $final.data_remota = $remota.Data
        $referencia = $local.UltimaAlteracao
    }
    else {
        $alvo = [int]$Revisao
        $referencia = $local.Revisao
    }
    $final.alvo = $alvo
    $emDia = ($alvo -eq $referencia)
    if ($alvo -ge $referencia) { $commits = Commits-Entre $local.Url $referencia $alvo; $final.direcao = 'avanca' }
    else { $commits = Commits-Entre $local.Url $alvo $referencia; $final.direcao = 'volta' }
    $final.commits = $commits.total
    $final.commits_recentes = $commits.recentes
    if ($emDia) { $final.direcao = 'em dia' }

    $alteracoes = @(Alteracoes-Locais $raiz)
    $final.alteracoes_locais = $alteracoes
    $alheias = @($alteracoes | Where-Object { $_.caminho -ne $IncDoInstalador })
    # Com -SemUpdate nada e baixado: alteracao local entra na compilacao, e isso e escolha de quem a fez.
    if ($alheias.Count -and -not $SemUpdate) {
        $impedimentos += ("alteracao local na copia de trabalho (" + (@($alheias | ForEach-Object { "$($_.caminho) [$($_.estado)]" }) -join '; ') +
            "): o update nao mexe em trabalho de ninguem - reverta ou guarde pelo TortoiseSVN e rode de novo")
    }
    $final.delphi_aberto = Delphi-Aberto
    if ($final.delphi_aberto) { $impedimentos += 'o Delphi (bds.exe) esta aberto: feche-o - o instalador recusa e os .bpl ficam travados' }
    if (Instalador-Aberto) { $impedimentos += 'o ACBrInstall_Trunk2 ja esta aberto: feche-o' }
    $instalador = Estado-Instalador $raiz
    $final.instalador = $instalador
    $impedimentos += @($instalador.problemas)
    $final.elevado = Elevado
    if (-not $final.elevado) { $avisos += 'o instalador exige administrador: o Windows vai pedir um UAC ao chegar nele' }

    Escreve ("revisao atual r{0} (ultima alteracao r{1}); alvo r{2}; {3} commit(s) - {4}" -f $local.Revisao, $local.UltimaAlteracao, $alvo, $commits.total, $final.direcao)

    if (-not $Executar) {
        $final.status = 'DRY_RUN'
    }
    elseif ($emDia -and -not $SemUpdate) {
        $final.status = 'NADA_A_FAZER'
        $avisos += 'a copia de trabalho ja esta no alvo; para so reinstalar, use -SemUpdate'
    }
    else {
        if ($impedimentos.Count) { Falha ("nada foi feito: " + ($impedimentos -join ' | ')) }

        if (-not $SemUpdate) {
            if (@($alteracoes | Where-Object { $_.caminho -eq $IncDoInstalador }).Count) {
                $r = Invoke-Svn @('revert', (Join-Path $raiz $IncDoInstalador))
                if ($r.Codigo -ne 0) { Falha ("svn revert do ACBr.inc falhou: " + (Resume-Erro $r.Erro)) }
                $final.acbr_inc_revertido = $true
            }
            Escreve "svn update ate r$alvo ..."
            $argumentosUpdate = @('update', '--accept', 'postpone', '-r', "$alvo", $raiz)
            $r = Invoke-Svn $argumentosUpdate
            if ($r.Codigo -ne 0 -and "$($r.Erro)" -match 'E155004|E155037|cleanup') {
                Escreve 'copia de trabalho travada por operacao interrompida: svn cleanup e nova tentativa'
                $null = Invoke-Svn @('cleanup', $raiz)
                $r = Invoke-Svn $argumentosUpdate
            }
            $logUpdate = Join-Path $PastaDados 'svn-update.txt'
            [IO.File]::WriteAllText($logUpdate, "$($r.Saida)`r`n$($r.Erro)", (New-Object Text.UTF8Encoding($false)))
            $final.log_update = $logUpdate
            # Linha de item do update: 4 colunas de estado (arquivo, propriedade, trava, conflito de arvore) e o caminho.
            $final.arquivos_atualizados = @(($r.Saida -split "`r?`n") | Where-Object { $_ -match '^(?! {4})[ADUCGER ][ADUCGER ][ B][ C]\s+\S' }).Count
            if ($r.Codigo -ne 0) { Falha ("svn update falhou: " + (Resume-Erro $r.Erro)) }
            $depois = Info-Svn $raiz ''
            $final.revisao_depois = $depois.Revisao
            $pendentes = @(Alteracoes-Locais $raiz)
            $conflitos = @($pendentes | Where-Object { $_.estado -match 'conflict|travado|obstructed|missing|incomplete' })
            if ($conflitos.Count) {
                Falha ("o update deixou conflito ou item pendente (" + (@($conflitos | ForEach-Object { "$($_.caminho) [$($_.estado)]" }) -join '; ') +
                    "): resolva pelo TortoiseSVN antes de instalar - nada foi instalado")
            }
            Escreve "atualizado: r$($local.Revisao) -> r$($depois.Revisao)"
            $instalador = Estado-Instalador $raiz
            $final.instalador = $instalador
            if ($instalador.problemas.Count) { Falha ("update feito, instalacao nao: " + ($instalador.problemas -join ' | ') + ". Depois de acertar, rode com -SemUpdate") }
        }

        Escreve 'abrindo o ACBrInstall_Trunk2.exe e conduzindo o assistente (nao mexa na janela dele) ...'
        $arquivoInstalacao = Join-Path $PastaDados 'instalacao.json'
        if (Test-Path $arquivoInstalacao) { Remove-Item $arquivoInstalacao -Force }
        $instalacao = $null
        if ($final.elevado) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Instalar -Pasta $raiz -Resumo $arquivoInstalacao -TimeoutMinutos $TimeoutMinutos | Out-Null
            $instalacao = Le-Json $arquivoInstalacao
        }
        else {
            $instalacao = Espera-Elevado $raiz $arquivoInstalacao $TimeoutMinutos
        }
        if (-not $instalacao) { Falha 'o processo do instalador nao deixou resumo: confira se o UAC foi aceito e se a janela do instalador ficou aberta' }
        $final.instalacao = $instalacao
        if ($instalacao.sid -and $instalacao.sid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
            $avisos += "o instalador rodou como $($instalacao.usuario), outra conta: o Delphi desta conta nao recebe os pacotes - repita com uma conta administradora propria"
        }
        if ($instalacao.status -ne 'INSTALADO') {
            $motivo = "instalacao falhou: $($instalacao.erro)"
            if (-not $SemUpdate -and $final.revisao_depois) { $motivo += " | o update ja foi feito (r$($final.revisao_depois)); para so reinstalar, -SemUpdate; para voltar, -Revisao $($local.Revisao)" }
            Falha $motivo
        }
        $conferencia = Confere-Ide $raiz $inicio
        $final.conferencia = $conferencia
        if ($conferencia.known_packages -eq 0) { $avisos += 'nenhum pacote do ACBr em Known Packages desta conta' }
        if ($conferencia.dcus_novos -eq 0) { $avisos += 'nenhum .dcu novo em Lib\Delphi\Lib*\Win32' }
        foreach ($e in @($conferencia.envoptions | Where-Object { -not $_.confere })) {
            $avisos += "EnvOptions.proj do BDS $($e.versao) nao tem o Library Path do ACBr: abra e feche o Delphi uma vez antes de compilar por msbuild"
        }
        $final.status = 'OK'
    }
}
catch {
    $final.status = 'FALHOU'
    $final.erro = "$($_.Exception.Message)"
}

if ($impedimentos.Count) { $final.impedimentos = $impedimentos }
if ($avisos.Count) { $final.avisos = $avisos }
$final.fim = (Get-Date).ToString('s')
$final.segundos = [int]((Get-Date) - $inicio).TotalSeconds
Grava-Json $final (Join-Path $PastaDados 'ultima-execucao.json')

Escreve '=== RESUMO ==='
Write-Output ($final | ConvertTo-Json -Depth 6)
Escreve '=== FIM ==='
if ($final.status -eq 'FALHOU') { exit 1 }
exit 0
