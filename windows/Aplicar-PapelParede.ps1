param(
    [switch]$Diagnostico
)

# PRIME YOU - papel de parede e tela de bloqueio para o usuario conectado.
# Este arquivo e versionado em ProgramData\PrimeYouManaged\papelparede e chamado
# pela pasta Inicializar comum, na sessao de qualquer usuario (inclusive Entra ID).

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$VersaoScript = "1.0.0"
$UrlImagem = "https://raw.githubusercontent.com/PrimeYou012/primeyou-assets/main/Papel-de-parede-PrimeYou.png"
$PastaUsuario = Join-Path $env:LOCALAPPDATA "PrimeYou\Branding"
$ArquivoLog = Join-Path $PastaUsuario "Aplicar-PapelParede.log"
$PastaInicializarComum = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\Startup"
$ChamadorInicializacao = Join-Path $PastaInicializarComum "PrimeYou-PapelParede.lnk"
$ScriptInstalado = $PSCommandPath

function Registrar-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Mensagem,
        [ValidateSet("INFO", "AVISO", "ERRO")][string]$Nivel = "INFO"
    )

    try {
        New-Item -Path $PastaUsuario -ItemType Directory -Force | Out-Null
        $Linha = "{0} [{1}] v{2} {3}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Nivel, $VersaoScript, $Mensagem
        Add-Content -LiteralPath $ArquivoLog -Value $Linha -Encoding UTF8
    }
    catch {
        # Falha de log nao deve impedir a personalizacao.
    }
}

function Obter-ExtensaoImagem {
    param([Parameter(Mandatory = $true)][string]$Caminho)

    if (-not (Test-Path -LiteralPath $Caminho -PathType Leaf)) {
        throw "Arquivo de imagem nao encontrado: $Caminho"
    }

    if ((Get-Item -LiteralPath $Caminho).Length -lt 1024) {
        throw "O arquivo baixado possui menos de 1 KB e nao parece ser uma imagem valida."
    }

    $Cabecalho = New-Object byte[] 8
    $Fluxo = [System.IO.File]::OpenRead($Caminho)
    try {
        [void]$Fluxo.Read($Cabecalho, 0, $Cabecalho.Length)
    }
    finally {
        $Fluxo.Dispose()
    }

    if ($Cabecalho[0] -eq 0x89 -and $Cabecalho[1] -eq 0x50 -and $Cabecalho[2] -eq 0x4E -and $Cabecalho[3] -eq 0x47) {
        return ".png"
    }

    if ($Cabecalho[0] -eq 0xFF -and $Cabecalho[1] -eq 0xD8 -and $Cabecalho[2] -eq 0xFF) {
        return ".jpg"
    }

    throw "O endereco nao retornou uma imagem PNG ou JPG valida."
}

function Obter-Imagem {
    New-Item -Path $PastaUsuario -ItemType Directory -Force | Out-Null
    $Temporario = Join-Path $PastaUsuario "papel-parede.download"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        # O parametro muda a cada logon para evitar uma copia antiga do cache HTTP.
        $CacheBuster = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $UrlAtualizada = "{0}?v={1}" -f $UrlImagem, $CacheBuster
        $Cabecalhos = @{ "Cache-Control" = "no-cache"; "Pragma" = "no-cache" }
        Invoke-WebRequest -Uri $UrlAtualizada -Headers $Cabecalhos -OutFile $Temporario -UseBasicParsing -TimeoutSec 45

        $Extensao = Obter-ExtensaoImagem -Caminho $Temporario
        $HashCompleto = (Get-FileHash -LiteralPath $Temporario -Algorithm SHA256).Hash.ToLowerInvariant()
        $HashCurto = $HashCompleto.Substring(0, 16)
        $ImagemFinal = Join-Path $PastaUsuario ("papel-parede-{0}{1}" -f $HashCurto, $Extensao)

        if (Test-Path -LiteralPath $ImagemFinal) {
            Remove-Item -LiteralPath $Temporario -Force -ErrorAction SilentlyContinue
        }
        else {
            Move-Item -LiteralPath $Temporario -Destination $ImagemFinal -Force
        }

        Registrar-Log -Mensagem "Imagem baixada e validada. Hash: $HashCurto."
        return $ImagemFinal
    }
    catch {
        Remove-Item -LiteralPath $Temporario -Force -ErrorAction SilentlyContinue
        Registrar-Log -Mensagem ("Falha no download: " + $_.Exception.Message) -Nivel "AVISO"

        $ImagemAnterior = Get-ChildItem -LiteralPath $PastaUsuario -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^papel-parede-[0-9a-f]{16}\.(png|jpg)$' } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if ($ImagemAnterior) {
            [void](Obter-ExtensaoImagem -Caminho $ImagemAnterior.FullName)
            Registrar-Log -Mensagem "Sem acesso a URL; usando a ultima imagem valida." -Nivel "AVISO"
            return $ImagemAnterior.FullName
        }

        throw "Nao foi possivel baixar a imagem e nao existe copia local valida. $($_.Exception.Message)"
    }
}

function Aplicar-PapelParede {
    param([Parameter(Mandatory = $true)][string]$Imagem)

    $ChaveDesktop = "HKCU:\Control Panel\Desktop"
    if (-not (Test-Path $ChaveDesktop)) {
        throw "O perfil do usuario atual nao esta carregado."
    }

    Set-ItemProperty -Path $ChaveDesktop -Name "Wallpaper" -Value $Imagem -Force
    Set-ItemProperty -Path $ChaveDesktop -Name "WallpaperStyle" -Value "10" -Force
    Set-ItemProperty -Path $ChaveDesktop -Name "TileWallpaper" -Value "0" -Force

    if (-not ("PrimeYouDesktop" -as [type])) {
        Add-Type @"
using System.Runtime.InteropServices;
public static class PrimeYouDesktop
{
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool SystemParametersInfo(int action, int parameter, string value, int options);
}
"@
    }

    # SPI_SETDESKWALLPAPER = 20; SPIF_UPDATEINIFILE | SPIF_SENDCHANGE = 3.
    $Resultado = [PrimeYouDesktop]::SystemParametersInfo(20, 0, $Imagem, 3)
    if (-not $Resultado) {
        $Codigo = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Falha ao aplicar o papel de parede. Codigo Win32: $Codigo"
    }

    Registrar-Log -Mensagem "Papel de parede aplicado ao usuario $env:USERDOMAIN\$env:USERNAME."
}

function Aguardar-OperacaoWinRt {
    param(
        [Parameter(Mandatory = $true)]$Operacao,
        [Parameter(Mandatory = $true)][Type]$TipoResultado
    )

    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $MetodoGenerico = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq "AsTask" -and
            $_.IsGenericMethodDefinition -and
            $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq "IAsyncOperation``1"
        } |
        Select-Object -First 1

    if (-not $MetodoGenerico) {
        throw "Conversor IAsyncOperation do Windows Runtime nao encontrado."
    }

    $Tarefa = $MetodoGenerico.MakeGenericMethod($TipoResultado).Invoke($null, @($Operacao))
    return $Tarefa.GetAwaiter().GetResult()
}

function Aguardar-AcaoWinRt {
    param([Parameter(Mandatory = $true)]$Acao)

    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $Metodo = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq "AsTask" -and
            -not $_.IsGenericMethod -and
            $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq "IAsyncAction"
        } |
        Select-Object -First 1

    if (-not $Metodo) {
        throw "Conversor IAsyncAction do Windows Runtime nao encontrado."
    }

    $Tarefa = $Metodo.Invoke($null, @($Acao))
    $Tarefa.GetAwaiter().GetResult() | Out-Null
}

function Aplicar-TelaBloqueio {
    param([Parameter(Mandatory = $true)][string]$Imagem)

    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        throw "Execute o script pelo Windows PowerShell de 64 bits."
    }

    [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
    [Windows.System.UserProfile.LockScreen, Windows.System.UserProfile, ContentType = WindowsRuntime] | Out-Null

    $OperacaoArquivo = [Windows.Storage.StorageFile]::GetFileFromPathAsync($Imagem)
    $ArquivoStorage = Aguardar-OperacaoWinRt -Operacao $OperacaoArquivo -TipoResultado ([Windows.Storage.StorageFile])
    $AcaoAplicacao = [Windows.System.UserProfile.LockScreen]::SetImageFileAsync($ArquivoStorage)
    Aguardar-AcaoWinRt -Acao $AcaoAplicacao

    $ImagemConfirmada = [Windows.System.UserProfile.LockScreen]::OriginalImageFile
    if ($null -eq $ImagemConfirmada) {
        throw "A API do Windows terminou sem confirmar uma imagem de tela de bloqueio."
    }

    Registrar-Log -Mensagem "Tela de bloqueio aplicada ao usuario $env:USERDOMAIN\$env:USERNAME."
}

function Mostrar-Diagnostico {
    Write-Host "PRIME YOU - diagnostico v$VersaoScript"
    Write-Host "Usuario: $env:USERDOMAIN\$env:USERNAME"
    Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Host "Processo 64 bits: $([Environment]::Is64BitProcess)"
    Write-Host "URL: $UrlImagem"
    Write-Host "Script instalado: $(Test-Path -LiteralPath $ScriptInstalado) | $ScriptInstalado"
    Write-Host "Inicializacao para todos: $(Test-Path -LiteralPath $ChamadorInicializacao) | $ChamadorInicializacao"
    Write-Host "Pasta do usuario: $PastaUsuario"
    Write-Host "Log: $ArquivoLog"
    Write-Host ""
    Write-Host "Ultimas linhas do log:"
    if (Test-Path -LiteralPath $ArquivoLog) {
        Get-Content -LiteralPath $ArquivoLog -Tail 30
    }
    else {
        Write-Host "Log ainda nao encontrado para este usuario."
    }
}

try {
    if ($Diagnostico) {
        Mostrar-Diagnostico
        exit 0
    }

    Registrar-Log -Mensagem "Inicio da aplicacao no logon."
    $Imagem = Obter-Imagem
    Aplicar-PapelParede -Imagem $Imagem
    Aplicar-TelaBloqueio -Imagem $Imagem
    Registrar-Log -Mensagem "Papel de parede e tela de bloqueio concluidos com sucesso."
    exit 0
}
catch {
    Registrar-Log -Mensagem $_.Exception.ToString() -Nivel "ERRO"
    Write-Error $_
    exit 1
}
