<#
.SYNOPSIS
    Coleta evidencias de um terminal PDV em um unico .zip para escalar chamado.
.DESCRIPTION
    Junta configuracao de rede, servicos, eventos, impressoras e espaco em disco
    num pacote unico. Somente leitura. Nao coleta senhas nem dados de venda.
.EXAMPLE
    .\Coletar-Evidencias.ps1 -Chamado INC0012345
.NOTES
    Kit PDV Blindado | Somente leitura
#>

[CmdletBinding()]
param(
    [string] $Chamado = "SEM-CHAMADO",
    [string] $Saida   = "$env:USERPROFILE\Desktop",
    [int]    $Dias    = 3
)

$carimbo = Get-Date -Format "yyyyMMdd_HHmmss"
$tmp = Join-Path $env:TEMP "KitPDV_$carimbo"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$desde = (Get-Date).AddDays(-$Dias)

Write-Host "Coletando evidencias de $env:COMPUTERNAME ..." -ForegroundColor Cyan

"Terminal : $env:COMPUTERNAME
Chamado  : $Chamado
Coletado : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
Operador : $env:USERDOMAIN\$env:USERNAME
Sistema  : $((Get-CimInstance Win32_OperatingSystem).Caption)
Modelo   : $((Get-CimInstance Win32_ComputerSystem).Manufacturer) $((Get-CimInstance Win32_ComputerSystem).Model)
Serial   : $((Get-CimInstance Win32_BIOS).SerialNumber)" | Out-File "$tmp\00_resumo.txt" -Encoding UTF8

ipconfig /all                              | Out-File "$tmp\01_rede_ipconfig.txt" -Encoding UTF8
route print                                | Out-File "$tmp\02_rede_rotas.txt"    -Encoding UTF8
netstat -ano                               | Out-File "$tmp\03_rede_conexoes.txt" -Encoding UTF8
Get-Service | Sort-Object Status,DisplayName |
    Select-Object Status,Name,DisplayName,StartType |
    Format-Table -AutoSize | Out-String -Width 200 | Out-File "$tmp\04_servicos.txt" -Encoding UTF8
Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue |
    Select-Object Name,Default,WorkOffline,PrinterStatus,PortName,DriverName |
    Format-List | Out-File "$tmp\05_impressoras.txt" -Encoding UTF8
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
    Select-Object DeviceID,@{n='LivreGB';e={[math]::Round($_.FreeSpace/1GB,1)}},@{n='TotalGB';e={[math]::Round($_.Size/1GB,1)}} |
    Format-Table -AutoSize | Out-String | Out-File "$tmp\06_discos.txt" -Encoding UTF8

foreach ($lg in @("System","Application")) {
    Get-WinEvent -FilterHashtable @{LogName=$lg; Level=1,2,3; StartTime=$desde} -ErrorAction SilentlyContinue |
        Select-Object TimeCreated,LevelDisplayName,ProviderName,Id,Message |
        Format-List | Out-File "$tmp\07_eventos_$lg.txt" -Encoding UTF8
}

Get-CimInstance Win32_Product -ErrorAction SilentlyContinue |
    Select-Object Name,Version,Vendor | Sort-Object Name |
    Format-Table -AutoSize | Out-String -Width 200 | Out-File "$tmp\08_programas.txt" -Encoding UTF8

$zip = Join-Path $Saida ("Evidencias_{0}_{1}_{2}.zip" -f $Chamado, $env:COMPUTERNAME, $carimbo)
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path "$tmp\*" -DestinationPath $zip -Force
Remove-Item $tmp -Recurse -Force

Write-Host "Pacote pronto: $zip" -ForegroundColor Green
Write-Host "Anexe este arquivo no chamado." -ForegroundColor Green
