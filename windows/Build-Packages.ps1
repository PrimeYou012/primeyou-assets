#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
foreach ($product in @('connection','energia')) {
    $version = if ($product -eq 'connection') { '1.0.0' } else { '1.2.0' }
    $versionDir = Join-Path $PSScriptRoot "$product\versions\$version"
    $files = @(Get-ChildItem -LiteralPath $versionDir -File | Sort-Object Name | ForEach-Object {
        @{ name = $_.Name; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    @{ product = $product; version = $version; files = $files } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot "$product\manifest.json") -Encoding UTF8
}
$installerData = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'runtime\Install-PrimeYou.ps1')))
$updaterData = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'runtime\Update-PrimeYou.ps1')))
$header = @'
@echo off
setlocal
set "PRIMEYOU_INSTALLER=%~f0"
set "PRIMEYOU_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PRIMEYOU_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%PRIMEYOU_PS%" -NoProfile -ExecutionPolicy Bypass -Command "$raw=[IO.File]::ReadAllText($env:PRIMEYOU_INSTALLER); $marker='#==PRIMEYOU-INSTALLER=='; & ([scriptblock]::Create($raw.Substring($raw.LastIndexOf($marker)+$marker.Length)))"
set "PRIMEYOU_RESULT=%ERRORLEVEL%"
if /I "%~1"=="/quiet" exit /b %PRIMEYOU_RESULT%
pause
exit /b %PRIMEYOU_RESULT%
#==PRIMEYOU-INSTALLER==
'@
$body = @'
$ErrorActionPreference = 'Stop'
try {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Solicitando permissao de administrador...'
        $path = $env:PRIMEYOU_INSTALLER.Replace("'", "''")
        $loader = "`$raw=[IO.File]::ReadAllText('$path'); `$marker='#==PRIMEYOU-'+'INSTALLER=='; & ([scriptblock]::Create(`$raw.Substring(`$raw.LastIndexOf(`$marker)+`$marker.Length)))"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($loader))
        try { $process = Start-Process -FilePath $ps -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) -Wait -PassThru }
        catch { throw 'Permissao de administrador cancelada ou indisponivel.' }
        exit $process.ExitCode
    }
    $tempDir = Join-Path $env:TEMP ('PrimeYouInstaller-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    $install = Join-Path $tempDir 'Install-PrimeYou.ps1'
    [IO.File]::WriteAllBytes($install, [Convert]::FromBase64String('__INSTALLER__'))
    [IO.File]::WriteAllBytes((Join-Path $tempDir 'Update-PrimeYou.ps1'), [Convert]::FromBase64String('__UPDATER__'))
    & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $install -Product '__PRODUCT__'
    $result = $LASTEXITCODE
    # Apenas os dois arquivos criados por esta execucao; sem exclusao recursiva.
    Remove-Item -LiteralPath $install, (Join-Path $tempDir 'Update-PrimeYou.ps1') -Force
    Remove-Item -LiteralPath $tempDir -Force
    exit $result
} catch { Write-Host "Falha: $_" -ForegroundColor Red; exit 1 }
'@
foreach ($product in @('connection','energia')) {
    $name = if ($product -eq 'connection') { 'Instalar-PrimeYouConnection.bat' } else { 'Instalar-Configuracao-Energia.bat' }
    $code = $body.Replace('__INSTALLER__', $installerData).Replace('__UPDATER__', $updaterData).Replace('__PRODUCT__', $product)
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot $name), (($header + "`r`n" + $code) -replace '\r?\n', "`r`n"), [Text.Encoding]::ASCII)
}
