#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
try {
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Configurar-Energia.ps1')
    if ($LASTEXITCODE -ne 0) { throw "Configuracao de energia falhou: $LASTEXITCODE" }
    # Caminho permanente: o candidato e movido depois de validado pelo atualizador.
    $layoutPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Barra-Tarefas.xml'
    $source = Join-Path $PSScriptRoot 'Barra-Tarefas.xml'
    if (-not (Test-Path -LiteralPath $layoutPath) -or (Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $layoutPath).Hash) {
        Copy-Item -LiteralPath $source -Destination $layoutPath -Force
    }
    $policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
    if (-not (Test-Path -LiteralPath $policy)) { New-Item -Path $policy -Force | Out-Null }
    New-ItemProperty -Path $policy -Name StartLayoutFile -Value $layoutPath -PropertyType ExpandString -Force | Out-Null
    New-ItemProperty -Path $policy -Name LockedStartLayout -Value 1 -PropertyType DWord -Force | Out-Null
    exit 0
} catch { Write-Output ($_ | Out-String); exit 1 }
