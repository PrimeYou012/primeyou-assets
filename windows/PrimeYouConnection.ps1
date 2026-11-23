#Requires -Version 5.1
#Requires -RunAsAdministrator

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

try { Apply-Policies; exit 0 } catch { Write-Output ($_ | Out-String); exit 1 }
