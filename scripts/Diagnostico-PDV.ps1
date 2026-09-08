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
.PARAMETER Simular
    Mostra quais correcoes seriam feitas, sem executar nenhuma.
.PARAMETER Corrigir
    Executa as correcoes da lista branca (servico critico parado e fila de
    impressao travada). Exige privilegio de administrador. Grava o estado
    anterior em log para permitir desfazer.
.PARAMETER Anonimizar
    Mascara nome da maquina, usuario, dominio, serial, nome do servidor e
    enderecos IP privados no relatorio. Use para anexar em chamado de
    terceiro sem expor a infraestrutura.
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
    [int]      $LimiteDiscoLivreGB = 10,
    [switch]   $Simular,
    [switch]   $Corrigir,
    [switch]   $Anonimizar
)

$ErrorActionPreference = "Continue"
Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
$resultados = New-Object System.Collections.Generic.List[object]
$correcoes  = New-Object System.Collections.Generic.List[object]
$script:SerialReal = $null

# Depois de uma correcao bem-sucedida a coleta feita no inicio fica obsoleta.
# Sem isto a tabela mostra o estado de antes e contradiz o painel de correcoes.
function Atualiza-Linha {
    param($Grupo, $Item, $Status, $Valor, $Detalhe)
    $linha = $resultados | Where-Object { $_.Grupo -eq $Grupo -and $_.Item -eq $Item } | Select-Object -First 1
    if ($linha) {
        $linha.Status  = $Status
        $linha.Valor   = $Valor
        $linha.Detalhe = $Detalhe
    }
}

function Add-Correcao {
    param($Acao, $Status, $Detalhe = "")
    $correcoes.Add([pscustomobject]@{ Acao = $Acao; Status = $Status; Detalhe = $Detalhe })
}

# Mascara dados que identificam a maquina e a rede. Somente com -Anonimizar.
function Mascarar([string]$t) {
    if (-not $Anonimizar -or [string]::IsNullOrEmpty($t)) { return $t }
    # ORDEM IMPORTA: enderecos IP primeiro. Se o nome do servidor for um IP
    # (ex.: 10.0.0.1), substitui-lo antes cortaria o meio de outro endereco
    # que o contenha (10.0.0.141 viraria SERVIDOR-XX41, vazando o final).
    # Apenas faixas privadas - resolvedores publicos continuam legiveis.
    $t = $t -replace "\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b", "10.x.x.x"
    $t = $t -replace "\b192\.168\.\d{1,3}\.\d{1,3}\b", "192.168.x.x"
    $t = $t -replace "\b172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}\b", "172.x.x.x"
    # \b impede que um nome curto seja encontrado dentro de um nome maior
    if ($env:COMPUTERNAME) { $t = $t -replace ("\b" + [regex]::Escape($env:COMPUTERNAME) + "\b"), "TERMINAL-XX" }
    if ($env:USERNAME)     { $t = $t -replace ("\b" + [regex]::Escape($env:USERNAME) + "\b"), "usuario" }
    if ($env:USERDOMAIN)   { $t = $t -replace ("\b" + [regex]::Escape($env:USERDOMAIN) + "\b"), "DOMINIO" }
    if ($ServidorLoja)     { $t = $t -replace ("\b" + [regex]::Escape($ServidorLoja) + "\b"), "SERVIDOR-XX" }
    if ($script:SerialReal){ $t = $t -replace ("\b" + [regex]::Escape($script:SerialReal) + "\b"), "********" }
    return $t
}

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
    $lixo = @("Default string","To be filled by O.E.M.","System manufacturer",
              "System Product Name","None","Not Specified","O.E.M.","")
    function Limpar($t) {
        if ($null -eq $t) { return "nao informado pelo fabricante" }
        $t = $t.Trim()
        foreach ($x in $lixo) { if ($t -eq $x) { return "nao informado pelo fabricante" } }
        return $t
    }
    $fab = (Limpar $cs.Manufacturer), (Limpar $cs.Model) | Where-Object { $_ -ne "nao informado pelo fabricante" }
    Add-Check "Identificacao" "Fabricante" "INFO" $(if ($fab) { $fab -join " " } else { "nao informado pelo fabricante" })
    $script:SerialReal = $bios.SerialNumber
    Add-Check "Identificacao" "Serial"     "INFO" (Limpar $bios.SerialNumber)
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
    $fila = @(Get-CimInstance Win32_PrintJob -ErrorAction SilentlyContinue).Count
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
    $virtuais = "vEthernet","Hyper-V","VirtualBox","VMware","Loopback","WSL","TAP-","Bluetooth"
    $adapters = Get-NetAdapter -ErrorAction Stop | Where-Object Status -eq "Up" | Where-Object {
        $nome = "$($_.Name) $($_.InterfaceDescription)"
        -not ($virtuais | Where-Object { $nome -like "*$_*" })
    }
    if (-not $adapters) {
        Add-Check "Rede" "Interfaces fisicas" "ATENCAO" "nenhuma ativa" "So ha adaptadores virtuais no ar. Checar cabo e placa de rede."
    }
    foreach ($a in $adapters) {
        # PhysicalMediaType nao muda com o idioma do Windows, ao contrario
        # do nome da interface. "Native 802.11" e o marcador de Wi-Fi.
        $ehWifi = "$($a.PhysicalMediaType) $($a.InterfaceDescription)" -match "802\.11|Wireless|Wi-Fi"
        if ($ehWifi) {
            Add-Check "Rede" "Interface $($a.Name)" "ATENCAO" "$($a.LinkSpeed) - Wi-Fi" `
                "Terminal de PDV em Wi-Fi e causa classica de falha intermitente: a venda trava sem motivo aparente e o problema some quando o tecnico chega. Sempre que possivel, cabo."
        } else {
            Add-Check "Rede" "Interface $($a.Name)" "OK" "$($a.LinkSpeed)"
        }
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
    # w32tm devolve a fonte com um sufixo de flag, ex.: "time.windows.com,0x9".
    # O sufixo faz parte da resposta normal - nao e sinal de erro.
    $bruto = (w32tm /query /source 2>&1 | Out-String).Trim()
    $fonte = ($bruto -split ",")[0].Trim()
    $semFonte = @("Local CMOS Clock","Free-running System Clock","Relogio CMOS local","")
    $servico  = (Get-Service W32Time -ErrorAction SilentlyContinue).Status
    if ($servico -ne "Running") {
        Add-Check "Data e hora" "Sincronizacao" "ATENCAO" "servico W32Time parado" "Sem o servico a hora nao sincroniza. Rodar: net start w32time"
    } elseif ($semFonte -notcontains $fonte -and $bruto -notmatch "erro|error|0x8") {
        Add-Check "Data e hora" "Sincronizacao" "OK" $fonte "Hora errada quebra emissao fiscal e conciliacao de caixa."
    } else {
        Add-Check "Data e hora" "Sincronizacao" "ATENCAO" $(if ($fonte) { $fonte } else { "sem fonte de tempo" }) "Relogio livre, sem servidor de tempo. Rodar: w32tm /resync"
    }
    Add-Check "Data e hora" "Hora local" "INFO" (Get-Date -Format "dd/MM/yyyy HH:mm:ss")
} catch { Add-Check "Data e hora" "Sincronizacao" "ATENCAO" "nao verificavel" }

# ------------------------------------------------------------- EVENTOS CRITICOS
try {
    $desde = (Get-Date).AddDays(-$DiasLog)
    $erros = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=$desde} -ErrorAction SilentlyContinue
    $qtd = @($erros).Count
    $st = if ($qtd -gt 50) { "FALHA" } elseif ($qtd -gt 10) { "ATENCAO" } else { "OK" }
    Add-Check "Eventos" "Erros criticos (ultimos $DiasLog dias)" $st "$qtd evento(s)"

    $erros | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object {
        Add-Check "Eventos" "  origem: $($_.Name)" "INFO" "$($_.Count) ocorrencia(s)" `
            (($_.Group | Select-Object -First 1).Message -replace "`r?`n"," " | ForEach-Object { if($_.Length -gt 180){$_.Substring(0,180)+"..."}else{$_} })
    }
} catch { Add-Check "Eventos" "Coleta" "ATENCAO" "erro" $_.Exception.Message }

# ------------------------------------------------------------------ RELATORIO
# ------------------------------------------------------- CORRECAO AUTOMATICA
# Lista branca: apenas acoes onde o dano possivel e menor que o dano existente.
# Servico ja parado nao piora ao subir. Fila travada nao piora ao ser limpa.
# Tudo o mais e apenas sugerido, nunca executado.
if ($Simular -or $Corrigir) {
    $ehAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    $logDir = "$env:ProgramData\KitPDV\logs"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $logCor = Join-Path $logDir ("correcao_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    function Log($m) { Add-Content -Path $logCor -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m) }
    Log "Inicio - terminal $env:COMPUTERNAME - modo $(if($Simular){'SIMULAR'}else{'CORRIGIR'}) - admin=$ehAdmin"

    if (-not $ehAdmin -and $Corrigir) {
        Add-Correcao "Correcao automatica" "BLOQUEADO" "Execute como Administrador. Nenhuma alteracao foi tentada."
        Log "Abortado: sem privilegio de administrador."
    }
    else {
        # --- acao 1: servico critico parado ---
        foreach ($nome in $ServicosCriticos) {
            $svc = Get-Service -Name $nome -ErrorAction SilentlyContinue
            if (-not $svc -or $svc.Status -eq "Running") { continue }

            $modoAnterior = (Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'" -ErrorAction SilentlyContinue).StartMode
            Log "ROLLBACK-INFO: $($svc.Name) estava '$($svc.Status)' com StartMode '$modoAnterior'."

            if ($Simular) {
                Add-Correcao "Iniciar servico $($svc.DisplayName)" "SIMULADO" "Estava '$($svc.Status)'. Rode com -Corrigir para executar."
                continue
            }
            try {
                Start-Service -Name $svc.Name -ErrorAction Stop
                Start-Sleep -Seconds 3
                $svc.Refresh()
                if ($svc.Status -eq "Running") {
                    Add-Correcao "Iniciar servico $($svc.DisplayName)" "CORRIGIDO" "Estado anterior gravado em $logCor"
                    Atualiza-Linha "Servicos" $svc.DisplayName "OK" "Running" "Estava parado. Foi iniciado automaticamente nesta execucao."
                    Log "SUCESSO: $($svc.DisplayName) iniciado."
                } else {
                    Add-Correcao "Iniciar servico $($svc.DisplayName)" "FALHOU" "Servico subiu e caiu. Causa esta em dependencia, licenca ou disco - ver Visualizador de Eventos."
                    Log "FALHA: $($svc.DisplayName) continua '$($svc.Status)'."
                }
            } catch {
                Add-Correcao "Iniciar servico $($svc.DisplayName)" "FALHOU" $_.Exception.Message
                Log "ERRO ao iniciar $($svc.DisplayName): $($_.Exception.Message)"
            }
        }

        # --- acao 2: fila de impressao travada ---
        if ($fila -gt 5) {
            if ($Simular) {
                Add-Correcao "Destravar fila de impressao" "SIMULADO" "$fila trabalho(s) na fila. Rode com -Corrigir para executar."
            } else {
                try {
                    Log "ROLLBACK-INFO: fila com $fila trabalho(s) antes da limpeza. Trabalhos pendentes serao descartados."
                    Stop-Service Spooler -Force -ErrorAction Stop
                    Start-Sleep -Seconds 2
                    Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue
                    Start-Service Spooler -ErrorAction Stop
                    Start-Sleep -Seconds 2
                    $filaDepois = @(Get-CimInstance Win32_PrintJob -ErrorAction SilentlyContinue).Count
                    Add-Correcao "Destravar fila de impressao" "CORRIGIDO" "$fila trabalho(s) descartado(s). Fila agora com $filaDepois."
                    Atualiza-Linha "Impressao" "Fila de impressao" "OK" "$filaDepois trabalho(s)" "Fila tinha $fila trabalho(s) travado(s) e foi limpa nesta execucao."
                    Log "SUCESSO: fila limpa, agora com $filaDepois trabalho(s)."
                } catch {
                    Add-Correcao "Destravar fila de impressao" "FALHOU" $_.Exception.Message
                    Log "ERRO ao limpar fila: $($_.Exception.Message)"
                }
            }
        }

        if ($correcoes.Count -eq 0) {
            Add-Correcao "Nenhuma acao necessaria" "OK" "Nada na lista branca precisava de correcao neste terminal."
        }
    }
    Log "Fim."
}

$falhas   = @($resultados | Where-Object Status -eq "FALHA").Count
$atencoes = @($resultados | Where-Object Status -eq "ATENCAO").Count
$veredito = if ($falhas -gt 0) { "CRITICO" } elseif ($atencoes -gt 0) { "ATENCAO" } else { "SAUDAVEL" }
$corVer   = switch ($veredito) { "CRITICO" {"#c0392b"} "ATENCAO" {"#b9770e"} default {"#1e8449"} }

$linhas = ""
foreach ($g in ($resultados | Group-Object Grupo)) {
    $linhas += "<tr class='grupo'><td colspan='3'>$($g.Name)</td></tr>"
    foreach ($r in $g.Group) {
        $cls = switch ($r.Status) { "OK"{"ok"} "ATENCAO"{"warn"} "FALHA"{"fail"} default{"info"} }
        $det = if ($r.Detalhe) { "<div class='det'>$([System.Web.HttpUtility]::HtmlEncode((Mascarar $r.Detalhe)))</div>" } else { "" }
        $linhas += "<tr><td class='item'>$([System.Web.HttpUtility]::HtmlEncode((Mascarar $r.Item)))$det</td><td class='val'>$([System.Web.HttpUtility]::HtmlEncode((Mascarar ([string]$r.Valor))))</td><td><span class='badge $cls'>$($r.Status)</span></td></tr>"
    }
}

$blocoCorrecao = ""
if ($correcoes.Count -gt 0) {
    $itens = ""
    foreach ($c in $correcoes) {
        $cc = switch ($c.Status) { "CORRIGIDO" {"ok"} "SIMULADO" {"info"} "OK" {"ok"} "BLOQUEADO" {"warn"} default {"fail"} }
        $dd = if ($c.Detalhe) { "<div class='det'>$([System.Web.HttpUtility]::HtmlEncode((Mascarar $c.Detalhe)))</div>" } else { "" }
        $itens += "<tr><td class='item'>$([System.Web.HttpUtility]::HtmlEncode((Mascarar $c.Acao)))$dd</td><td class='val'></td><td><span class='badge $cc'>$($c.Status)</span></td></tr>"
    }
    $titulo = if ($Simular) { "O que seria corrigido (simulacao - nada foi alterado)" } else { "Correcoes aplicadas automaticamente" }
    $blocoCorrecao = "<table><tr class='grupo corrigido'><td colspan='3'>$titulo</td></tr>$itens</table>"
}

$nomeMaquina = Mascarar $env:COMPUTERNAME
$nomeUsuario = Mascarar $env:USERNAME

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
 tr.grupo.corrigido td{background:#e2eff0;color:#0e5c63}
 tr.grupo td{background:#f0f3f6;font-weight:700;font-size:12px;letter-spacing:.5px;text-transform:uppercase;color:#456}
 .item{width:45%} .val{width:38%;color:#334}
 .det{font-size:11.5px;color:#7a6000;background:#fffbe6;border-left:3px solid #e2b203;padding:5px 8px;margin-top:5px;border-radius:0 4px 4px 0}
 .badge{display:inline-block;padding:2px 9px;border-radius:20px;font-size:11px;font-weight:700}
 .ok{background:#d5f0dd;color:#1e8449}.warn{background:#fdf0d5;color:#b9770e}.fail{background:#fadbd8;color:#c0392b}.info{background:#e8eaed;color:#556}
 footer{padding:14px 24px;font-size:11.5px;color:#889;border-top:1px solid #e3e7ea}
</style></head><body><div class="card">
<header>
 <h1>Diagnostico de PDV - $nomeMaquina</h1>
 <div class="sub">Gerado em $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss') &middot; usuario $nomeUsuario$(if($Anonimizar){' &middot; relatorio anonimizado'})</div>
 <div class="veredito">$veredito</div>
 <div class="resumo">$falhas falha(s) &middot; $atencoes ponto(s) de atencao &middot; $($resultados.Count) verificacoes</div>
</header>
$blocoCorrecao
<table>$linhas</table>
<footer>Kit PDV Blindado &middot; verificacoes somente-leitura &middot; nenhuma alteracao foi feita neste terminal</footer>
</div></body></html>
"@

if (-not (Test-Path $Saida)) { New-Item -ItemType Directory -Path $Saida -Force | Out-Null }
$rotulo  = if ($Anonimizar) { "ANONIMO" } else { $env:COMPUTERNAME }
$arquivo = Join-Path $Saida ("Diagnostico_{0}_{1}.html" -f $rotulo, (Get-Date -Format "yyyyMMdd_HHmmss"))
$html | Out-File -FilePath $arquivo -Encoding UTF8

Write-Host ""
Write-Host "Veredito: $veredito  ($falhas falha(s), $atencoes atencao)" -ForegroundColor $(if($falhas){"Red"}elseif($atencoes){"Yellow"}else{"Green"})
if ($correcoes.Count -gt 0) {
    $rotuloC = if ($Simular) { "Simulacao" } else { "Correcoes" }
    Write-Host "$($rotuloC): $($correcoes.Count) acao(oes) - ver secao no relatorio" -ForegroundColor Cyan
}
if ($Anonimizar) { Write-Host "Relatorio anonimizado - seguro para anexar em chamado de terceiro." -ForegroundColor Cyan }
Write-Host "Relatorio: $arquivo" -ForegroundColor Cyan
try { Start-Process $arquivo } catch {}
