<#
.SYNOPSIS
    Recuperacao controlada de servicos parados em terminal PDV.
.DESCRIPTION
    Verifica servicos criticos, mostra o que sera feito e SO EXECUTA apos
    confirmacao explicita. Grava log de tudo que foi alterado, para auditoria
    e para rollback manual. Use -WhatIf para simular sem tocar em nada.
.PARAMETER Servicos
    Servicos que devem estar rodando neste terminal.
.PARAMETER Automatico
    Pula a confirmacao interativa. Use apenas em janela de manutencao.
.EXAMPLE
    .\Recuperar-Servicos.ps1 -Servicos "Spooler","MeuServicoPDV" -WhatIf
.EXAMPLE
    .\Recuperar-Servicos.ps1 -Servicos "Spooler"
.NOTES
    Kit PDV Blindado | Requer execucao como Administrador
#>

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [string[]] $Servicos  = @("Spooler"),
    [switch]   $Automatico,
    [string]   $PastaLog  = "$env:ProgramData\KitPDV\logs"
)

$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Este script precisa ser executado como Administrador."
    return
}

if (-not (Test-Path $PastaLog)) { New-Item -ItemType Directory -Path $PastaLog -Force | Out-Null }
$log = Join-Path $PastaLog ("recuperacao_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
function Registrar($msg) {
    $linha = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -Path $log -Value $linha
    Write-Host $linha
}

Registrar "Inicio - terminal $env:COMPUTERNAME - operador $env:USERNAME"

$parados = @()
foreach ($nome in $Servicos) {
    $svc = Get-Service -Name $nome -ErrorAction SilentlyContinue
    if (-not $svc) { Registrar "AVISO: servico '$nome' nao existe neste terminal."; continue }
    if ($svc.Status -eq "Running") { Registrar "OK: $($svc.DisplayName) ja esta rodando." }
    else { Registrar "PARADO: $($svc.DisplayName) esta '$($svc.Status)'."; $parados += $svc }
}

if (-not $parados) { Registrar "Nada a fazer. Todos os servicos monitorados estao rodando."; return }

Write-Host ""
Write-Host "Servicos que serao iniciados:" -ForegroundColor Yellow
$parados | ForEach-Object { Write-Host "  - $($_.DisplayName) [$($_.Name)]" -ForegroundColor Yellow }
Write-Host ""

if (-not $Automatico) {
    $r = Read-Host "Confirmar o start desses servicos? (digite SIM)"
    if ($r -ne "SIM") { Registrar "Cancelado pelo operador."; return }
}

foreach ($svc in $parados) {
    if ($PSCmdlet.ShouldProcess($svc.DisplayName, "Iniciar servico")) {
        try {
            $modoAnterior = (Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'").StartMode
            Registrar "ROLLBACK-INFO: $($svc.Name) estava '$($svc.Status)' com StartMode '$modoAnterior'."

            Start-Service -Name $svc.Name
            Start-Sleep -Seconds 3
            $svc.Refresh()

            if ($svc.Status -eq "Running") { Registrar "SUCESSO: $($svc.DisplayName) iniciado." }
            else { Registrar "FALHA: $($svc.DisplayName) continua '$($svc.Status)'. Ver Visualizador de Eventos." }
        } catch {
            Registrar "ERRO ao iniciar $($svc.DisplayName): $($_.Exception.Message)"
        }
    }
}

Registrar "Fim. Log completo em: $log"
