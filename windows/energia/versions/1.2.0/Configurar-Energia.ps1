#Requires -RunAsAdministrator
<#
Configura os modos de energia do Windows 11 e os tempos de inatividade.
Execute em um PowerShell aberto como administrador.
#>
$ErrorActionPreference = 'Stop'

function Invoke-PowerCfg {
    param([string[]]$Argumentos)
    & "$env:SystemRoot\System32\powercfg.exe" @Argumentos
    if ($LASTEXITCODE -ne 0) {
        throw "Falha no powercfg ($LASTEXITCODE): $($Argumentos -join ' ')"
    }
}

if (-not ('ConfiguracaoEnergia.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace ConfiguracaoEnergia {
    public static class Native {
        [DllImport("powrprof.dll")]
        public static extern uint PowerGetUserConfiguredACPowerMode(out Guid mode);
        [DllImport("powrprof.dll")]
        public static extern uint PowerGetUserConfiguredDCPowerMode(out Guid mode);
        [DllImport("powrprof.dll")]
        public static extern uint PowerSetUserConfiguredACPowerMode(ref Guid mode);
        [DllImport("powrprof.dll")]
        public static extern uint PowerSetUserConfiguredDCPowerMode(ref Guid mode);
    }
}
'@
}

function Assert-Sucesso {
    param([uint32]$Codigo, [string]$Operacao)
    if ($Codigo -ne 0) {
        $descricao = ([System.ComponentModel.Win32Exception]::new([int]$Codigo)).Message
        throw "${Operacao}: $descricao (codigo $Codigo)."
    }
}

# Confere a disponibilidade da API antes de alterar as configuracoes.
[Guid]$modoAC = [Guid]::Empty
[Guid]$modoDC = [Guid]::Empty
try {
    Assert-Sucesso ([ConfiguracaoEnergia.Native]::PowerGetUserConfiguredACPowerMode([ref]$modoAC)) 'Consultar modo conectado'
    Assert-Sucesso ([ConfiguracaoEnergia.Native]::PowerGetUserConfiguredDCPowerMode([ref]$modoDC)) 'Consultar modo bateria'
} catch {
    throw "Nao foi possivel acessar os modos de energia. Este script requer Windows 11 com suporte a essa API. Detalhes: $_"
}

# O plano Equilibrado permite usar os modos de energia independentes AC/DC.
Invoke-PowerCfg -Argumentos @('/setactive', '381b4222-f694-41f0-9685-ff5bb260df2e')

# Tempos em minutos. Zero significa nunca.
Invoke-PowerCfg -Argumentos @('/change', 'monitor-timeout-ac', '15')
Invoke-PowerCfg -Argumentos @('/change', 'monitor-timeout-dc', '15')
Invoke-PowerCfg -Argumentos @('/change', 'standby-timeout-ac', '0')
Invoke-PowerCfg -Argumentos @('/change', 'standby-timeout-dc', '60')

# Hibernacao completa (necessaria para hibernar, alem da inicializacao rapida).
Invoke-PowerCfg -Argumentos @('/hibernate', 'on')
Invoke-PowerCfg -Argumentos @('/hibernate', '/type', 'full')
# Grava diretamente em segundos para evitar o ajuste de 60 para 61 minutos
# observado com /change quando suspensao e hibernacao usam o mesmo tempo.
Invoke-PowerCfg -Argumentos @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_SLEEP', 'HIBERNATEIDLE', '0')
Invoke-PowerCfg -Argumentos @('/setdcvalueindex', 'SCHEME_CURRENT', 'SUB_SLEEP', 'HIBERNATEIDLE', '3600')

# Economia de energia automatica quando a bateria atingir 20%.
# GUIDs oficiais usados porque os aliases podem nao estar disponiveis.
Invoke-PowerCfg -Argumentos @('/setdcvalueindex', 'SCHEME_CURRENT', 'de830923-a562-41af-a086-e3a2c6bad2da', 'e69653ca-cf7f-4f05-aa73-cb833fa90ad4', '20')
Invoke-PowerCfg -Argumentos @('/setactive', 'SCHEME_CURRENT')

[Guid]$desempenho = 'ded574b5-45a0-4f42-8737-46345c09c238'
[Guid]$eficiencia = '961cc777-2547-4f9d-8174-7d86181b8a7a'
Assert-Sucesso ([ConfiguracaoEnergia.Native]::PowerSetUserConfiguredACPowerMode([ref]$desempenho)) 'Definir desempenho conectado'
Assert-Sucesso ([ConfiguracaoEnergia.Native]::PowerSetUserConfiguredDCPowerMode([ref]$eficiencia)) 'Definir eficiencia na bateria'

Assert-Sucesso ([ConfiguracaoEnergia.Native]::PowerGetUserConfiguredACPowerMode([ref]$modoAC)) 'Verificar modo conectado'
Assert-Sucesso ([ConfiguracaoEnergia.Native]::PowerGetUserConfiguredDCPowerMode([ref]$modoDC)) 'Verificar modo bateria'
if ($modoAC -ne $desempenho -or $modoDC -ne $eficiencia) {
    throw 'Os modos lidos nao correspondem aos solicitados. Verifique as politicas de energia do dispositivo.'
}

Write-Host 'Configuracoes aplicadas com sucesso:' -ForegroundColor Green
@(
    [PSCustomObject]@{ Alimentacao = 'Conectado'; Modo = 'Melhor desempenho'; DesligarTela = '15 minutos'; Suspender = 'Nunca'; Hibernar = 'Nunca' }
    [PSCustomObject]@{ Alimentacao = 'Bateria'; Modo = 'Melhor eficiencia de energia'; DesligarTela = '15 minutos'; Suspender = '1 hora'; Hibernar = '1 hora' }
) | Format-Table -AutoSize
Write-Host 'Economia de energia automatica: bateria em 20%.'
