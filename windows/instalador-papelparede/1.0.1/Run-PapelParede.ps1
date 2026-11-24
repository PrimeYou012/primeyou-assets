$ErrorActionPreference = 'Stop'
try {
    $dir = Join-Path $PSScriptRoot 'papelparede'
    $state = Get-Content -LiteralPath (Join-Path $dir 'installed.json') -Raw | ConvertFrom-Json
    if ($state.directory -notmatch '^v\d+\.\d+\.\d+-[a-f0-9]{32}$') { throw 'Estado do papel de parede invalido.' }
    $script = Join-Path (Join-Path $dir $state.directory) 'Apply.ps1'
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $ps -NoProfile -NonInteractive -File $script
    exit $LASTEXITCODE
} catch {
    $userLog = Join-Path $env:LOCALAPPDATA 'PrimeYou\Branding'
    New-Item -ItemType Directory -Path $userLog -Force | Out-Null
    ($_ | Out-String) | Add-Content -LiteralPath (Join-Path $userLog 'Inicializacao.log')
    exit 1
}