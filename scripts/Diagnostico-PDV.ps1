<#
.SYNOPSIS
    Diagnostico completo de terminal PDV Windows - gera relatorio HTML.
.DESCRIPTION
    Executa uma bateria de verificacoes somente-leitura em um terminal de ponto
    de venda Windows e gera um relatorio HTML com semaforo (OK / ATENCAO / FALHA).
    Nao altera nada no sistema. Seguro para rodar em producao, em horario de loja.
.PARAMETER ServidorLoja
    Nome ou IP do servidor da loja (retaguarda / banco de dados).
.PARAMETER PortaSQL
    Porta do SQL Server no servidor da loja. Padrao 1433.
.PARAMETER ServicosCriticos
    Lista de servicos que precisam estar rodando neste terminal.
.PARAMETER Saida
    Pasta onde o relatorio sera gravado. Padrao: Desktop do usuario atual.
.EXAMPLE
    .\Diagnostico-PDV.ps1 -ServidorLoja 192.168.0.10
.EXAMPLE
    .\Diagnostico-PDV.ps1 -ServidorLoja SRVLOJA01 -ServicosCriticos "MSSQLSERVER","Spooler","MeuServicoPDV"
.NOTES
    Kit PDV Blindado | Somente leitura | Sem dependencias externas
#>

[CmdletBinding()]
param(
    [string]   $ServidorLoja      = "",
    [int]      $PortaSQL          = 1433,
    [string[]] $ServicosCriticos  = @("Spooler","W32Time","LanmanWorkstation"),
    [string]   $Saida             = "$env:USERPROFILE\Desktop",
    [int]      $DiasLog           = 2,
    [int]      $LimiteDiscoLivreGB = 10
)

$ErrorActionPreference = "Continue"
Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
$resultados = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param($Grupo, $Item, $Status, $Valor, $Detalhe = "")
    $resultados.Add([pscustomobject]@{
        Grupo   = $Grupo
        Item    = $Item
        Status  = $Status      # OK | ATENCAO | FALHA | INFO
        Valor   = $Valor
        Detalhe = $Detalhe
    })
}

Write-Host "== Kit PDV Blindado - diagnostico iniciado ==" -ForegroundColor Cyan
Write-Host "Terminal: $env:COMPUTERNAME" -ForegroundColor Cyan

# ---------------------------------------------------------------- IDENTIFICACAO
try {
    $os  = Get-CimInstance Win32_OperatingSystem
    $cs  = Get-CimInstance Win32_ComputerSystem
    $bios= Get-CimInstance Win32_BIOS
    $uptime = (Get-Date) - $os.LastBootUpTime

    Add-Check "Identificacao" "Terminal"        "INFO" $env:COMPUTERNAME
    Add-Check "Identificacao" "Sistema"         "INFO" "$($os.Caption) ($($os.Version))"
    Add-Check "Identificacao" "Fabricante"      "INFO" "$($cs.Manufacturer) $($cs.Model)"
    Add-Check "Identificacao" "Serial"          "INFO" $bios.SerialNumber
    Add-Check "Identificacao" "Usuario logado"  "INFO" "$env:USERDOMAIN\$env:USERNAME"

    $st = if ($uptime.TotalDays -gt 15) { "ATENCAO" } else { "OK" }
    Add-Check "Identificacao" "Uptime" $st ("{0:N1} dias" -f $uptime.TotalDays) `
        $(if($st -eq "ATENCAO"){"Terminal sem reiniciar ha mais de 15 dias. Agende reinicio fora do horario de loja."})
} catch { Add-Check "Identificacao" "Coleta" "FALHA" "erro" $_.Exception.Message }

# ------------------------------------------------------------------- HARDWARE
try {
    $memTotalGB = [math]::Round($os.TotalVisibleMemorySize/1MB,1)
    $memLivreGB = [math]::Round($os.FreePhysicalMemory/1MB,1)
    $pctLivre   = [math]::Round(($memLivreGB/$memTotalGB)*100,0)
    $st = if ($pctLivre -lt 10) { "FALHA" } elseif ($pctLivre -lt 20) { "ATENCAO" } else { "OK" }
    Add-Check "Hardware" "Memoria RAM" $st "$memLivreGB GB livres de $memTotalGB GB ($pctLivre%)"

    foreach ($d in Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3") {
        $livreGB = [math]::Round($d.FreeSpace/1GB,1)
        $totalGB = [math]::Round($d.Size/1GB,1)
        $st = if ($livreGB -lt 3) { "FALHA" } elseif ($livreGB -lt $LimiteDiscoLivreGB) { "ATENCAO" } else { "OK" }
        Add-Check "Hardware" "Disco $($d.DeviceID)" $st "$livreGB GB livres de $totalGB GB" `
            $(if($st -ne "OK"){"Disco cheio derruba o PDV e corrompe base local. Limpar temporarios e logs antigos."})
    }
} catch { Add-Check "Hardware" "Coleta" "FALHA" "erro" $_.Exception.Message }

# ------------------------------------------------------------------- SERVICOS
foreach ($nome in $ServicosCriticos) {
    $svc = Get-Service -Name $nome -ErrorAction SilentlyContinue
    if (-not $svc) {
        Add-Check "Servicos" $nome "ATENCAO" "nao encontrado" "Servico nao existe neste terminal. Confira o nome ou o perfil da maquina."
        continue
    }
    $st = if ($svc.Status -eq "Running") { "OK" } else { "FALHA" }
    Add-Check "Servicos" $svc.DisplayName $st $svc.Status `
        $(if($st -eq "FALHA"){"Servico parado. Ver script Recuperar-Servicos.ps1."})
}

# ------------------------------------------------------------------- IMPRESSAO
try {
    $printers = Get-CimInstance Win32_Printer -ErrorAction Stop
    if (-not $printers) {
        Add-Check "Impressao" "Impressoras" "ATENCAO" "nenhuma instalada"
    } else {
        foreach ($p in $printers) {
            $st = if ($p.WorkOffline -or $p.PrinterStatus -eq 7) { "FALHA" } else { "OK" }
            $flag = if ($p.Default) { " (padrao)" } else { "" }
            Add-Check "Impressao" "$($p.Name)$flag" $st `
                $(if($p.WorkOffline){"OFFLINE"}else{"pronta"}) `
                $(if($st -eq "FALHA"){"Impressora offline - cupom nao sai. Checar cabo/USB, energia e fila."})
        }
    }
    $fila = (Get-CimInstance Win32_PrintJob -ErrorAction SilentlyContinue | Measure-Object).Count
    $st = if ($fila -gt 5) { "ATENCAO" } else { "OK" }
    Add-Check "Impressao" "Fila de impressao" $st "$fila trabalho(s)" `
        $(if($st -eq "ATENCAO"){"Fila travada. Parar Spooler, limpar C:\Windows\System32\spool\PRINTERS e subir de novo."})
} catch { Add-Check "Impressao" "Coleta" "ATENCAO" "erro" $_.Exception.Message }

# ------------------------------------------------------------- PERIFERICOS SERIAIS
try {
    $portas = [System.IO.Ports.SerialPort]::GetPortNames()
    if ($portas) { Add-Check "Perifericos" "Portas COM" "INFO" ($portas -join ", ") "Impressora fiscal / balanca / gaveta costumam usar estas portas." }
    else         { Add-Check "Perifericos" "Portas COM" "INFO" "nenhuma detectada" }
} catch { Add-Check "Perifericos" "Portas COM" "INFO" "nao verificavel" }

# --------------------------------------------------------------------- REDE
try {
    $adapters = Get-NetAdapter -ErrorAction Stop | Where-Object Status -eq "Up"
    foreach ($a in $adapters) {
        Add-Check "Rede" "Interface $($a.Name)" "OK" "$($a.LinkSpeed)"
    }
    $ipcfg = Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.IPv4DefaultGateway }
    foreach ($c in $ipcfg) {
        $ip = ($c.IPv4Address.IPAddress -join ", ")
        $gw = $c.IPv4DefaultGateway.NextHop
        $dns= ($c.DNSServer | Where-Object AddressFamily -eq 2 | Select-Object -Expand ServerAddresses) -join ", "
        Add-Check "Rede" "Endereco IP" "INFO" $ip
        Add-Check "Rede" "Gateway"     "INFO" $gw
        Add-Check "Rede" "DNS"         "INFO" $dns

        $okGw = Test-Connection -ComputerName $gw -Count 2 -Quiet -ErrorAction SilentlyContinue
        Add-Check "Rede" "Ping no gateway" $(if($okGw){"OK"}else{"FALHA"}) $(if($okGw){"responde"}else{"sem resposta"}) `
            $(if(-not $okGw){"Sem gateway a loja fica isolada. Checar switch, cabo e roteador."})
    }
} catch { Add-Check "Rede" "Coleta" "FALHA" "erro" $_.Exception.Message }

# ------------------------------------------------------------------ INTERNET
foreach ($alvo in @("8.8.8.8","1.1.1.1")) {
    $ok = Test-Connection -ComputerName $alvo -Count 2 -Quiet -ErrorAction SilentlyContinue
    Add-Check "Internet" "Ping $alvo" $(if($ok){"OK"}else{"FALHA"}) $(if($ok){"responde"}else{"sem resposta"})
}
try {
    $dnsOk = [bool](Resolve-DnsName "www.google.com" -ErrorAction Stop)
    Add-Check "Internet" "Resolucao DNS" "OK" "funcionando"
} catch {
    Add-Check "Internet" "Resolucao DNS" "FALHA" "nao resolve" "Ping por IP funciona mas nome nao resolve = problema de DNS, nao de link."
}

# ------------------------------------------------------------- SERVIDOR DA LOJA
if ($ServidorLoja) {
    $okSrv = Test-Connection -ComputerName $ServidorLoja -Count 2 -Quiet -ErrorAction SilentlyContinue
    Add-Check "Servidor da loja" "Ping $ServidorLoja" $(if($okSrv){"OK"}else{"FALHA"}) `
        $(if($okSrv){"responde"}else{"sem resposta"}) `
        $(if(-not $okSrv){"Terminal nao enxerga a retaguarda. Venda offline pode acumular."})

    foreach ($porta in @($PortaSQL, 445, 135)) {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $conn = $tcp.BeginConnect($ServidorLoja, $porta, $null, $null)
            $aberto = $conn.AsyncWaitHandle.WaitOne(3000, $false) -and $tcp.Connected
            $tcp.Close()
        } catch { $aberto = $false }
        $rotulo = switch ($porta) { $PortaSQL {"SQL Server"} 445 {"Compartilhamento SMB"} 135 {"RPC"} default {"porta"} }
        $st = if ($aberto) { "OK" } elseif ($porta -eq $PortaSQL) { "FALHA" } else { "ATENCAO" }
        Add-Check "Servidor da loja" "$rotulo (tcp/$porta)" $st $(if($aberto){"aberta"}else{"fechada/filtrada"}) `
            $(if(-not $aberto -and $porta -eq $PortaSQL){"Sem SQL o PDV nao sincroniza. Checar servico SQL, firewall e SQL Browser."})
    }
} else {
    Add-Check "Servidor da loja" "Verificacao" "INFO" "nao executada" "Rode com -ServidorLoja <ip ou nome> para testar a retaguarda."
}

# --------------------------------------------------------------------- HORA
try {
    $w32 = (w32tm /query /status 2>&1 | Out-String)
    if ($w32 -match "Origem:|Source:") {
        $src = ($w32 -split "`n" | Where-Object { $_ -match "Origem:|Source:" } | Select-Object -First 1).Trim()
        Add-Check "Data e hora" "Sincronizacao" "OK" $src "Hora errada quebra emissao fiscal e conciliacao de caixa."
    } else {
        Add-Check "Data e hora" "Sincronizacao" "ATENCAO" "nao sincronizado" "Rodar: w32tm /resync"
    }
    Add-Check "Data e hora" "Hora local" "INFO" (Get-Date -Format "dd/MM/yyyy HH:mm:ss")
} catch { Add-Check "Data e hora" "Sincronizacao" "ATENCAO" "nao verificavel" }

# ------------------------------------------------------------- EVENTOS CRITICOS
try {
    $desde = (Get-Date).AddDays(-$DiasLog)
    $erros = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=$desde} -ErrorAction SilentlyContinue
    $qtd = ($erros | Measure-Object).Count
    $st = if ($qtd -gt 50) { "FALHA" } elseif ($qtd -gt 10) { "ATENCAO" } else { "OK" }
    Add-Check "Eventos" "Erros criticos (ultimos $DiasLog dias)" $st "$qtd evento(s)"

    $erros | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object {
        Add-Check "Eventos" "  origem: $($_.Name)" "INFO" "$($_.Count) ocorrencia(s)" `
            (($_.Group | Select-Object -First 1).Message -replace "`r?`n"," " | ForEach-Object { if($_.Length -gt 180){$_.Substring(0,180)+"..."}else{$_} })
    }
} catch { Add-Check "Eventos" "Coleta" "ATENCAO" "erro" $_.Exception.Message }

# ------------------------------------------------------------------ RELATORIO
$falhas   = ($resultados | Where-Object Status -eq "FALHA").Count
$atencoes = ($resultados | Where-Object Status -eq "ATENCAO").Count
$veredito = if ($falhas -gt 0) { "CRITICO" } elseif ($atencoes -gt 0) { "ATENCAO" } else { "SAUDAVEL" }
$corVer   = switch ($veredito) { "CRITICO" {"#c0392b"} "ATENCAO" {"#b9770e"} default {"#1e8449"} }

$linhas = ""
foreach ($g in ($resultados | Group-Object Grupo)) {
    $linhas += "<tr class='grupo'><td colspan='3'>$($g.Name)</td></tr>"
    foreach ($r in $g.Group) {
        $cls = switch ($r.Status) { "OK"{"ok"} "ATENCAO"{"warn"} "FALHA"{"fail"} default{"info"} }
        $det = if ($r.Detalhe) { "<div class='det'>$([System.Web.HttpUtility]::HtmlEncode($r.Detalhe))</div>" } else { "" }
        $linhas += "<tr><td class='item'>$([System.Web.HttpUtility]::HtmlEncode($r.Item))$det</td><td class='val'>$([System.Web.HttpUtility]::HtmlEncode([string]$r.Valor))</td><td><span class='badge $cls'>$($r.Status)</span></td></tr>"
    }
}

$html = @"
<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<title>Diagnostico PDV - $env:COMPUTERNAME</title>
<style>
 body{font-family:Segoe UI,Arial,sans-serif;background:#f4f6f8;margin:0;padding:24px;color:#222}
 .card{max-width:960px;margin:0 auto;background:#fff;border-radius:10px;box-shadow:0 1px 4px rgba(0,0,0,.12);overflow:hidden}
 header{padding:20px 24px;border-bottom:1px solid #e3e7ea}
 h1{margin:0 0 4px;font-size:20px}
 .sub{color:#667;font-size:13px}
 .veredito{display:inline-block;margin-top:12px;padding:8px 16px;border-radius:6px;color:#fff;font-weight:700;background:$corVer}
 .resumo{font-size:13px;color:#556;margin-top:8px}
 table{width:100%;border-collapse:collapse;font-size:13px}
 td{padding:8px 24px;border-bottom:1px solid #eef1f3;vertical-align:top}
 tr.grupo td{background:#f0f3f6;font-weight:700;font-size:12px;letter-spacing:.5px;text-transform:uppercase;color:#456}
 .item{width:45%} .val{width:38%;color:#334}
 .det{font-size:11.5px;color:#7a6000;background:#fffbe6;border-left:3px solid #e2b203;padding:5px 8px;margin-top:5px;border-radius:0 4px 4px 0}
 .badge{display:inline-block;padding:2px 9px;border-radius:20px;font-size:11px;font-weight:700}
 .ok{background:#d5f0dd;color:#1e8449}.warn{background:#fdf0d5;color:#b9770e}.fail{background:#fadbd8;color:#c0392b}.info{background:#e8eaed;color:#556}
 footer{padding:14px 24px;font-size:11.5px;color:#889;border-top:1px solid #e3e7ea}
</style></head><body><div class="card">
<header>
 <h1>Diagnostico de PDV - $env:COMPUTERNAME</h1>
 <div class="sub">Gerado em $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss') &middot; usuario $env:USERNAME</div>
 <div class="veredito">$veredito</div>
 <div class="resumo">$falhas falha(s) &middot; $atencoes ponto(s) de atencao &middot; $($resultados.Count) verificacoes</div>
</header>
<table>$linhas</table>
<footer>Kit PDV Blindado &middot; verificacoes somente-leitura &middot; nenhuma alteracao foi feita neste terminal</footer>
</div></body></html>
"@

if (-not (Test-Path $Saida)) { New-Item -ItemType Directory -Path $Saida -Force | Out-Null }
$arquivo = Join-Path $Saida ("Diagnostico_{0}_{1}.html" -f $env:COMPUTERNAME, (Get-Date -Format "yyyyMMdd_HHmmss"))
$html | Out-File -FilePath $arquivo -Encoding UTF8

Write-Host ""
Write-Host "Veredito: $veredito  ($falhas falha(s), $atencoes atencao)" -ForegroundColor $(if($falhas){"Red"}elseif($atencoes){"Yellow"}else{"Green"})
Write-Host "Relatorio: $arquivo" -ForegroundColor Cyan
try { Start-Process $arquivo } catch {}
