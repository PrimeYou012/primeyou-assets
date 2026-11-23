#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'primeyou-maquina.ps1') -Aplicar
exit $LASTEXITCODE
