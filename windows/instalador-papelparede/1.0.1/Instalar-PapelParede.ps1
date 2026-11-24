#Requires -Version 5.1
param([Parameter(Mandatory)][ValidateSet('papelparede')][string]$Product)
$ErrorActionPreference = 'Stop'
try {
    $identity = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments = '-NoProfile -File "{0}" -Product papelparede' -f $PSCommandPath
        try {
            $elevated = Start-Process -FilePath $powershell -Verb RunAs -ArgumentList $arguments -Wait -PassThru
        } catch { throw 'Permissao de administrador cancelada ou indisponivel.' }
        exit $elevated.ExitCode
    }
    $root = Join-Path $env:ProgramData 'PrimeYouManaged'
    if (Test-Path -LiteralPath $root) {
        $item = Get-Item -LiteralPath $root -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Pasta de instalacao invalida.' }
    } else { New-Item -ItemType Directory -Path $root | Out-Null }
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
    foreach ($entry in @(@('S-1-5-18','FullControl'),@('S-1-5-32-544','FullControl'),@('S-1-5-11','ReadAndExecute'))) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($entry[0]), $entry[1], 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    }
    Set-Acl -LiteralPath $root -AclObject $acl
    # Recusa links preexistentes antes de instalar codigo que rodara como SYSTEM.
    foreach ($entry in @(Get-ChildItem -LiteralPath $root -Recurse -Force)) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Link inesperado: $($entry.FullName)" }
        $childAcl = Get-Acl -LiteralPath $entry.FullName
        $childAcl.SetAccessRuleProtection($false, $false)
        foreach ($rule in @($childAcl.Access)) { if (-not $rule.IsInherited) { $childAcl.RemoveAccessRuleSpecific($rule) } }
        Set-Acl -LiteralPath $entry.FullName -AclObject $childAcl
    }
    # Cada produto tem sua propria copia, evitando que instaladores antigos
    # de outro produto sobrescrevam o atualizador do papel de parede.
    $productRoot = Join-Path $root $Product
    New-Item -ItemType Directory -Path $productRoot -Force | Out-Null
    $updater = Join-Path $productRoot 'Update-PrimeYou.ps1'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Update-PrimeYou.ps1') -Destination $updater -Force
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $ps -NoProfile -NonInteractive -File $updater -Product $Product
    if ($LASTEXITCODE -ne 0) { throw 'Primeira aplicacao falhou. Consulte o log antes de tentar novamente.' }
    $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    $argsBase = '-NoProfile -NonInteractive -WindowStyle Hidden -File "{0}" -Product {1}' -f $updater, $Product
    $bootAction = New-ScheduledTaskAction -Execute $ps -Argument $argsBase
    Register-ScheduledTask -TaskName "PrimeYou-$Product-Atualizar" -Action $bootAction -Trigger (New-ScheduledTaskTrigger -AtStartup) -Principal $principal -Settings $settings -Force | Out-Null
    if ($Product -eq 'papelparede') {
        $launcherPath = Join-Path $root 'Run-PapelParede.ps1'
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Run-PapelParede.ps1') -Destination $launcherPath -Force
        $startup = [Environment]::GetFolderPath('CommonStartup')
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut((Join-Path $startup 'PrimeYou-PapelParede.lnk'))
        $link.TargetPath = $ps
        $link.Arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -File "{0}"' -f $launcherPath
        $link.WindowStyle = 7
        $link.Description = 'Aplica papel de parede e tela de bloqueio PRIME YOU no usuario conectado.'
        $link.Save()
        Write-Host 'Papel de parede: saia da conta e entre novamente para aplicar ao usuario.'
    } else {
        $logonAction = New-ScheduledTaskAction -Execute $ps -Argument ($argsBase + ' -ApplyOnly')
        $existingTask = if ($Product -eq 'connection') { 'PrimeYouConnection-VerificarHomepage' } else { 'ConfiguracaoEnergiaCorporativa' }
        Register-ScheduledTask -TaskName $existingTask -Action $logonAction -Trigger (New-ScheduledTaskTrigger -AtLogOn) -Principal $principal -Settings $settings -Force | Out-Null
    }
    Write-Host "Instalacao concluida: $Product. Atualizacao no boot; aplicacao local no logon." -ForegroundColor Green
    Write-Host "Log: $root\$Product\Ultima-Execucao.log"
    if ($Product -eq 'energia') { Write-Host 'Saia da conta e entre novamente para conferir a barra de tarefas.' }
    exit 0
} catch { Write-Host "Falha: $_" -ForegroundColor Red; exit 1 }
