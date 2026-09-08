<#
.SYNOPSIS
    Descobre o servidor da loja e o servico do PDV, e monta o comando pronto.
.DESCRIPTION
    Roda ANTES do diagnostico. Somente leitura. Nao altera nada.
    Ao final imprime a linha de comando ja preenchida para voce copiar e colar.
.EXAMPLE
    .\Descobrir-Ambiente.ps1
.NOTES
    Kit PDV Blindado | Somente leitura
#>

[CmdletBinding()]
param([switch] $Anonimizar)

$ErrorActionPreference = "Continue"
function Titulo($t) { Write-Host ""; Write-Host "  $t" -ForegroundColor Cyan; Write-Host ("  " + ("-" * $t.Length)) -ForegroundColor DarkGray }

Clear-Host
Write-Host ""
Write-Host "  DESCOBERTA DE AMBIENTE - $env:COMPUTERNAME" -ForegroundColor White
Write-Host "  Somente leitura. Nada sera alterado." -ForegroundColor DarkGray

# ------------------------------------------------------------ 1. GATEWAY
Titulo "1. Rede deste terminal"
$gw = $null
try {
    $cfg = Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.IPv4DefaultGateway }
    foreach ($c in $cfg) {
        $gw = $c.IPv4DefaultGateway.NextHop
        Write-Host ("    Interface : {0}" -f $c.InterfaceAlias)
        Write-Host ("    IP        : {0}" -f ($c.IPv4Address.IPAddress -join ", "))
        Write-Host ("    Gateway   : {0}" -f $gw)
    }
} catch {
    Write-Host "    Nao foi possivel ler a configuracao de rede (Windows antigo?)." -ForegroundColor Yellow
}

# --------------------------------------------- 2. QUEM ESTE PDV PROCURA
Titulo "2. Servidores que este terminal esta acessando agora"
Write-Host "    (o PDV precisa estar aberto para aparecer aqui)" -ForegroundColor DarkGray
$candidatos = New-Object System.Collections.Generic.List[string]
try {
    $conns = Get-NetTCPConnection -State Established -ErrorAction Stop |
             Where-Object { $_.RemotePort -in 1433,1434,3050,5432,3306 -and $_.RemoteAddress -notmatch "^(127\.|::1)" }
    if ($conns) {
        foreach ($c in ($conns | Sort-Object RemoteAddress, RemotePort -Unique)) {
            $proc = (Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue).ProcessName
            $banco = switch ($c.RemotePort) { 1433 {"SQL Server"} 1434 {"SQL Browser"} 3050 {"Firebird"} 5432 {"PostgreSQL"} 3306 {"MySQL"} }
            Write-Host ("    {0,-16} porta {1,-6} {2,-14} usado por: {3}" -f $c.RemoteAddress, $c.RemotePort, $banco, $proc) -ForegroundColor Green
            if (-not $candidatos.Contains([string]$c.RemoteAddress)) { $candidatos.Add([string]$c.RemoteAddress) }
        }
    } else {
        Write-Host "    Nenhuma conexao de banco de dados ativa neste momento." -ForegroundColor Yellow
        Write-Host "    Abra o sistema de vendas e rode de novo." -ForegroundColor Yellow
    }
} catch {
    Write-Host "    Get-NetTCPConnection indisponivel. Tentando netstat..." -ForegroundColor Yellow
    $net = netstat -ano | Select-String ":1433\s" | Select-Object -First 5
    if ($net) { $net | ForEach-Object { Write-Host ("    " + $_.ToString().Trim()) } }
    else { Write-Host "    Nada encontrado." -ForegroundColor Yellow }
}

# -------------------------------------- 3. SQL SERVER INSTALADO LOCALMENTE
Titulo "3. SQL Server instalado neste terminal"
$sqlLocal = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "MSSQL*" -and $_.Name -notlike "*Agent*" }
if ($sqlLocal) {
    foreach ($s in $sqlLocal) { Write-Host ("    {0,-28} {1}" -f $s.Name, $s.Status) -ForegroundColor Green }
    Write-Host "    O banco esta na propria maquina - use 'localhost' como servidor." -ForegroundColor DarkGray
    if (-not $candidatos.Contains("localhost")) { $candidatos.Add("localhost") }
} else {
    Write-Host "    Nenhum. O banco fica em outra maquina." -ForegroundColor DarkGray
}

# ------------------------------------------ 4. SERVICOS QUE NAO SAO DA MICROSOFT
Titulo "4. Servicos de terceiros, por funcao"

# Categorias montadas a partir do que roda de verdade num terminal de loja.
# Hardware entra aqui porque impressora e pinpad sao a causa mais comum de
# chamado - software de PDV parado e menos frequente que cupom que nao sai.
$categorias = [ordered]@{
    "BANCO DE DADOS"      = 'mssql|sqlserver|sqlagent|firebird|postgres|mysql|oracle|sqlanywhere|sybase'
    "SISTEMA DE VENDAS"   = 'linx|microvix|totvs|senior|consinco|sysmo|\bpdv\b|\bcaixa\b|venda|frente|retail|varejo|\bloja\b'
    "IMPRESSORA"          = 'epson|bematech|elgin|daruma|sweda|diebold|impressora|printer|spool'
    "PINPAD / TEF"        = 'gertec|ingenico|verifone|\bpax\b|sitef|\btef\b|pinpad|stone|cielo|getnet|paygo'
    "FISCAL"              = '\bsat\b|nfce|nfe\b|fiscal|acbr|emissor|sefaz'
    "PERIFERICO"          = 'balanca|toledo|filizola|scanner|leitor|gaveta|checkout'
    "ACESSO REMOTO"       = 'teamviewer|anydesk|\bvnc\b|logmein|rustdesk|helpdesk|\brmm\b|supremo'
}

$serv = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object {
    $_.State -eq "Running" -and $_.PathName -notmatch "\\Windows\\" -and $_.PathName
})

$classificados = @{}
$paraMonitorar = New-Object System.Collections.Generic.List[string]
$jaVisto       = New-Object System.Collections.Generic.List[string]

foreach ($cat in $categorias.Keys) {
    $regex = $categorias[$cat]
    $achados = @($serv | Where-Object {
        $texto = "$($_.Name) $($_.DisplayName) $($_.PathName)"
        $texto -match $regex -and -not $jaVisto.Contains($_.Name)
    })
    foreach ($a in $achados) { $jaVisto.Add($a.Name) }
    if ($achados) { $classificados[$cat] = $achados }
}

foreach ($cat in $categorias.Keys) {
    if (-not $classificados.ContainsKey($cat)) { continue }
    $cor = if ($cat -eq "ACESSO REMOTO") { "DarkGray" } else { "Green" }
    Write-Host ""
    Write-Host ("    [$cat]") -ForegroundColor $cor
    foreach ($a in $classificados[$cat]) {
        Write-Host ('      "{0}"' -f $a.Name) -ForegroundColor $cor -NoNewline
        Write-Host ("   {0}" -f $a.DisplayName) -ForegroundColor DarkGray
        # acesso remoto nao entra no monitoramento: cair nao para a loja
        if ($cat -ne "ACESSO REMOTO") { $paraMonitorar.Add($a.Name) }
    }
}

$naoClassificados = @($serv | Where-Object { -not $jaVisto.Contains($_.Name) })
if ($naoClassificados) {
    Write-Host ""
    Write-Host "    [NAO CLASSIFICADO - confira se algum e do PDV]" -ForegroundColor Yellow
    foreach ($n in ($naoClassificados | Sort-Object DisplayName | Select-Object -First 15)) {
        Write-Host ("      {0,-32} {1}" -f $n.Name, $n.DisplayName) -ForegroundColor DarkGray
    }
    if ($naoClassificados.Count -gt 15) {
        Write-Host ("      ... e mais {0}." -f ($naoClassificados.Count - 15)) -ForegroundColor DarkGray
    }
}

# ------------------------------------------------------ 5. COMANDO PRONTO
$alvo = if ($candidatos.Count -gt 0) { $candidatos[0] } elseif ($gw) { $gw } else { "<ip-do-servidor>" }
$paraMonitorar.Add("Spooler")
$listaServ = (($paraMonitorar | Select-Object -Unique) | ForEach-Object { '"' + $_ + '"' }) -join ","

Titulo "5. Copie e cole a linha abaixo"
Write-Host ""
Write-Host "    .\Diagnostico-PDV.ps1 -ServidorLoja $alvo -ServicosCriticos $listaServ -Anonimizar" -ForegroundColor Yellow
Write-Host ""
if ($candidatos.Count -gt 1) {
    Write-Host ("    Outros servidores possiveis: {0}" -f (($candidatos | Select-Object -Skip 1) -join ", ")) -ForegroundColor DarkGray
}
Write-Host "    Confira o servidor antes de rodar. Se o PDV estava fechado," -ForegroundColor DarkGray
Write-Host "    a deteccao pode ter pego o gateway em vez do banco." -ForegroundColor DarkGray
Write-Host ""
