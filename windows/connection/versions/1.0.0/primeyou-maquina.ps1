#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$Aplicar)
$ErrorActionPreference = 'Stop'
$url = 'https://primeyou.sharepoint.com/sites/Prime_You-Connection'
$installDir = Join-Path $env:ProgramFiles 'PrimeYouConnection'
$installedScript = Join-Path $installDir 'primeyou-maquina.ps1'
$taskName = 'PrimeYouConnection-VerificarHomepage'

function Set-PolicyValue($Key, $Name, $Value, $Kind) {
    if (($Key.GetValue($Name, $null) -cne $Value) -or
        ($Key.GetValueNames() -contains $Name -and $Key.GetValueKind($Name) -ne $Kind)) {
        $Key.SetValue($Name, $Value, $Kind)
    }
    if ($Key.GetValue($Name) -cne $Value -or $Key.GetValueKind($Name) -ne $Kind) {
        throw "Falha ao verificar a politica $Name."
    }
}

function Apply-Policies {
    $hive = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
    try {
        foreach ($path in @('SOFTWARE\Policies\Microsoft\Edge', 'SOFTWARE\Policies\Google\Chrome')) {
            $key = $hive.CreateSubKey($path)
            try {
                Set-PolicyValue $key 'RestoreOnStartup' 4 ([Microsoft.Win32.RegistryValueKind]::DWord)
                Set-PolicyValue $key 'HomepageLocation' $url ([Microsoft.Win32.RegistryValueKind]::String)
                Set-PolicyValue $key 'HomepageIsNewTabPage' 0 ([Microsoft.Win32.RegistryValueKind]::DWord)
                Set-PolicyValue $key 'ShowHomeButton' 1 ([Microsoft.Win32.RegistryValueKind]::DWord)
                $list = $key.CreateSubKey('RestoreOnStartupURLs')
                try {
                    Set-PolicyValue $list '1' $url ([Microsoft.Win32.RegistryValueKind]::String)
                    # A lista de inicializacao deve conter somente o portal solicitado.
                    foreach ($name in $list.GetValueNames()) {
                        if ($name -ne '1') { $list.DeleteValue($name) }
                    }
                } finally { $list.Dispose() }
            } finally { $key.Dispose() }
        }
    } finally { $hive.Dispose() }
}

try {
    if (-not $Aplicar) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        if ((Get-Item -LiteralPath $installDir).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'A pasta de instalacao nao pode ser um link.'
        }
        # O codigo executado como SYSTEM so pode ser alterado por administradores/SYSTEM.
        $acl = New-Object System.Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        $acl.SetOwner([System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
        foreach ($entry in @(@('S-1-5-18','FullControl'), @('S-1-5-32-544','FullControl'), @('S-1-5-32-545','ReadAndExecute'))) {
            $sid = [System.Security.Principal.SecurityIdentifier]::new($entry[0])
            $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
                $sid, $entry[1], 'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $acl.AddAccessRule($rule)
        }
        Set-Acl -LiteralPath $installDir -AclObject $acl
        if (Test-Path -LiteralPath $installedScript) {
            if ((Get-Item -LiteralPath $installedScript).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'O arquivo instalado nao pode ser um link.'
            }
        }
        if ($PSCommandPath -ne $installedScript) {
            Copy-Item -LiteralPath $PSCommandPath -Destination $installedScript -Force
        }
        $fileAcl = Get-Acl -LiteralPath $installedScript
        $fileAcl.SetAccessRuleProtection($false, $false)
        foreach ($rule in @($fileAcl.Access)) {
            if (-not $rule.IsInherited) { [void]$fileAcl.RemoveAccessRuleSpecific($rule) }
        }
        Set-Acl -LiteralPath $installedScript -AclObject $fileAcl
    }

    Apply-Policies

    if (-not $Aplicar) {
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $action = New-ScheduledTaskAction -Execute $ps -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Aplicar' -f $installedScript)
        $triggers = @((New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -AtLogOn))
        $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description 'Verifica e corrige as politicas de pagina inicial do Edge e Chrome para todos os usuarios.' -Force | Out-Null
        Write-Host 'Instalado: politicas da maquina aplicadas e tarefa SYSTEM registrada.'
        Write-Host 'Feche e abra os navegadores e confira edge://policy e chrome://policy.'
        Write-Host 'A aceitacao das politicas depende dos requisitos de gerenciamento dos navegadores.'
    }
    exit 0
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
