#Requires -Version 5.1
param([Parameter(Mandatory)][ValidateSet('connection','energia','papelparede')][string]$Product,
      [switch]$ApplyOnly,
      [string]$Root = (Join-Path $env:ProgramData 'PrimeYouManaged'))
$ErrorActionPreference = 'Stop'
$baseUrl = 'https://raw.githubusercontent.com/PrimeYou012/primeyou-assets/main/windows'
$productDir = Join-Path $Root $Product
$statePath = Join-Path $productDir 'installed.json'
$names = @('Apply.ps1')
$remoteFile = switch ($Product) { 'connection' {'PrimeYouConnection.ps1'} 'energia' {'Configuracao-Energia.ps1'} 'papelparede' {'Aplicar-PapelParede.ps1'} }

function Invoke-Application([string]$Directory) {
    if ($Product -eq 'papelparede') {
        Write-Output 'Script validado e disponivel; a imagem sera aplicada na sessao do usuario no logon.'
        return
    }
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $exe -NoProfile -ExecutionPolicy RemoteSigned -NonInteractive -File (Join-Path $Directory 'Apply.ps1')
    if ($LASTEXITCODE -ne 0) { throw "Aplicacao falhou: codigo $LASTEXITCODE" }
}

$lock = $null
$transcript = $false
$candidate = $null
try {
    New-Item -ItemType Directory -Path $productDir -Force | Out-Null
    # Bloqueio compartilhado pelos gatilhos de boot e logon.
    try { $lock = [IO.File]::Open((Join-Path $productDir 'execution.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { Write-Output 'Outra execucao esta em andamento.'; exit 0 }
    Start-Transcript -Path (Join-Path $productDir 'Ultima-Execucao.log') -Force | Out-Null
    $transcript = $true
    $installed = $null
    if (Test-Path -LiteralPath $statePath) {
        $installed = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ($installed.version -notmatch '^\d+\.\d+\.\d+$') { throw 'Versao local invalida.' }
    }
    $applied = $false
    if (-not $ApplyOnly) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $manifest = Invoke-RestMethod -Uri "$baseUrl/versions.json" -TimeoutSec 20 -Headers @{ 'Cache-Control' = 'no-cache' }
            $manifest = $manifest.$Product
            if ($manifest.product -ne $Product -or $manifest.version -notmatch '^\d+\.\d+\.\d+$') { throw 'Manifesto invalido.' }
            if ($installed -and [version]$manifest.version -le [version]$installed.version) {
                Write-Output "Versao local $($installed.version) atualizada; nenhum arquivo baixado ou substituido."
            } else {
                if (@($manifest.files).Count -ne $names.Count) { throw 'Quantidade de arquivos invalida.' }
                $seen = @{}
                $candidate = Join-Path $productDir ('candidate-' + [Guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $candidate | Out-Null
                foreach ($file in $manifest.files) {
                    if ($file.name -notin $names -or $seen.ContainsKey($file.name) -or $file.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Arquivo de manifesto invalido.' }
                    $seen[$file.name] = $true
                    $target = Join-Path $candidate $file.name
                    $uri = "$baseUrl/$remoteFile"
                    Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $target -TimeoutSec 30
                    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $file.sha256) { throw "SHA256 divergente: $($file.name)" }
                    if ($file.name.EndsWith('.ps1')) {
                        $tokens = $null; $syntaxErrors = $null
                        [Management.Automation.Language.Parser]::ParseFile($target, [ref]$tokens, [ref]$syntaxErrors) | Out-Null
                        if ($syntaxErrors.Count) { throw "PowerShell invalido: $($file.name)" }
                    } else { [xml]$xmlCheck = Get-Content -LiteralPath $target -Raw }
                }
                # A versao so e promovida depois de baixar, validar e aplicar tudo.
                Invoke-Application $candidate
                $versionName = 'v' + $manifest.version + '-' + [Guid]::NewGuid().ToString('N')
                $versionDir = Join-Path $productDir $versionName
                Move-Item -LiteralPath $candidate -Destination $versionDir
                $candidate = $null
                $newState = @{ version = $manifest.version; directory = $versionName }
                $tempState = Join-Path $productDir 'installed.next.json'
                $newState | ConvertTo-Json | Set-Content -LiteralPath $tempState -Encoding UTF8
                if (Test-Path -LiteralPath $statePath) { [IO.File]::Replace($tempState, $statePath, [NullString]::Value) }
                else { [IO.File]::Move($tempState, $statePath) }
                $installed = [PSCustomObject]$newState
                $applied = $true
                Write-Output "Atualizado para $($manifest.version)."
            }
        } catch {
            Write-Warning "Atualizacao indisponivel: $_"
            if (-not $installed) { throw 'Sem versao local valida. Instalacao inicial exige acesso ao GitHub.' }
        }
    }
    if (-not $installed) { throw 'Nenhuma versao instalada.' }
    if (-not $applied) {
        if ($installed.directory -notmatch '^v\d+\.\d+\.\d+-[a-f0-9]{32}$') { throw 'Diretorio local invalido.' }
        Invoke-Application (Join-Path $productDir $installed.directory)
    }
    exit 0
} catch {
    Write-Output ($_ | Out-String)
    exit 1
} finally {
    # Candidatos incompletos ficam isolados e nunca sao executados no proximo boot.
    if ($transcript) { Stop-Transcript | Out-Null }
    if ($lock) { $lock.Dispose() }
}
