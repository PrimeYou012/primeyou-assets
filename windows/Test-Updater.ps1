#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$testDir = Join-Path $env:TEMP ('PrimeYouTests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null
$updater = Join-Path $PSScriptRoot 'runtime\Update-PrimeYou.ps1'
$scenario = @'
param($Case, $TestDir, $Updater)
$ErrorActionPreference = 'Stop'
$root = Join-Path $TestDir $Case
$productDir = Join-Path $root 'connection'
$oldName = 'v1.0.0-' + ('a' * 32)
$old = Join-Path $productDir $oldName
$fixtures = Join-Path $root 'fixtures'
New-Item -ItemType Directory -Path $old, $fixtures -Force | Out-Null
$env:PRIMEYOU_TEST_MARKER = Join-Path $root 'applications.txt'
$oldCode = "Add-Content -LiteralPath `$env:PRIMEYOU_TEST_MARKER -Value 'old'; exit 0"
[IO.File]::WriteAllText((Join-Path $old 'Apply.ps1'), $oldCode)
if ($Case -notin @('first-install','first-offline')) {
    @{version='1.0.0';directory=$oldName} | ConvertTo-Json | Set-Content (Join-Path $productDir 'installed.json')
}
$code = if ($Case -eq 'apply-failure') { 'exit 1' } else { "Add-Content -LiteralPath `$env:PRIMEYOU_TEST_MARKER -Value 'new'; exit 0" }
[IO.File]::WriteAllText((Join-Path $fixtures 'Apply.ps1'), $code)
[IO.File]::WriteAllText((Join-Path $fixtures 'primeyou-maquina.ps1'), '# fixture; no policies')
$files = @(Get-ChildItem $fixtures -File | ForEach-Object { @{name=$_.Name;sha256=(Get-FileHash $_.FullName).Hash} })
if ($Case -eq 'bad-hash') { $files[0].sha256 = '0' * 64 }
$global:PrimeYouTestManifest = @{product='connection';version=$(if ($Case -eq 'same' -or $Case -eq 'apply-only') {'1.0.0'} elseif ($Case -eq 'older') {'0.9.0'} else {'1.0.1'});files=$files}
function Invoke-RestMethod {
    param($Uri,$TimeoutSec,$Headers)
    Add-Content -LiteralPath (Join-Path $root 'requests.txt') -Value 'manifest'
    if ($Case -in @('offline','first-offline')) { throw 'simulated offline' }
    return $global:PrimeYouTestManifest
}
function Invoke-WebRequest {
    param([switch]$UseBasicParsing,$Uri,$OutFile,$TimeoutSec)
    Add-Content -LiteralPath (Join-Path $root 'requests.txt') -Value 'file'
    Copy-Item -LiteralPath (Join-Path $fixtures ([IO.Path]::GetFileName($OutFile))) -Destination $OutFile
}
if ($Case -eq 'apply-only') { & $Updater -Product connection -Root $root -ApplyOnly }
else { & $Updater -Product connection -Root $root }
exit $LASTEXITCODE
'@
$scenarioPath = Join-Path $testDir 'Scenario.ps1'
[IO.File]::WriteAllText($scenarioPath, $scenario)
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
foreach ($case in @('same','older','newer','bad-hash','offline','apply-failure','apply-only','first-install','first-offline')) {
    & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scenarioPath -Case $case -TestDir $testDir -Updater $updater | Out-Null
    if ($case -eq 'first-offline') {
        if ($LASTEXITCODE -ne 1 -or (Test-Path (Join-Path $testDir "$case\connection\installed.json"))) { throw 'Primeira instalacao offline deveria falhar sem promover estado.' }
        Write-Output "PASS $case"
        continue
    }
    if ($LASTEXITCODE -ne 0) { throw "Cenario falhou: $case" }
    $root = Join-Path $testDir $case
    $state = Get-Content (Join-Path $root 'connection\installed.json') -Raw | ConvertFrom-Json
    $requests = @(Get-Content (Join-Path $root 'requests.txt') -ErrorAction SilentlyContinue)
    $applications = @(Get-Content (Join-Path $root 'applications.txt'))
    $expectedVersion = if ($case -in @('newer','first-install')) {'1.0.1'} else {'1.0.0'}
    $expectedApplication = if ($case -in @('newer','first-install')) {'new'} else {'old'}
    if ($state.version -ne $expectedVersion -or $applications.Count -ne 1 -or $applications[0] -ne $expectedApplication) { throw "Estado/aplicacao incorretos: $case" }
    if ($case -in @('same','older','offline','apply-only') -and 'file' -in $requests) { throw "Download indevido: $case" }
    if ($case -eq 'apply-only' -and $requests.Count -ne 0) { throw 'Logon consultou rede.' }
    Write-Output "PASS $case"
}
Write-Output "Fixtures e logs de teste: $testDir"
