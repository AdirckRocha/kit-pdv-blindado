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
Titulo "4. Servicos de terceiros rodando (o do seu PDV esta aqui)"
$palavras = "linx","pdv","pos","caixa","venda","retail","loja","fisc","sat","tef","sitef","microvix","frente"
$serv = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object {
    $_.State -eq "Running" -and $_.PathName -notmatch "\\Windows\\" -and $_.PathName
})
if ($serv) {
    $provaveis = @($serv | Where-Object { $t = "$($_.Name) $($_.DisplayName) $($_.PathName)"; $palavras | Where-Object { $t -match $_ } })
    if ($provaveis) {
        Write-Host "    PROVAVEIS - nome do servico entre aspas:" -ForegroundColor Green
        foreach ($s in $provaveis) { Write-Host ("      `"{0}`"  ->  {1}" -f $s.Name, $s.DisplayName) -ForegroundColor Green }
        Write-Host ""
    }
    $outros = @($serv | Where-Object { $provaveis -notcontains $_ })
    if ($outros) {
        Write-Host "    Outros servicos de terceiros:" -ForegroundColor DarkGray
        foreach ($s in ($outros | Sort-Object DisplayName | Select-Object -First 15)) {
            Write-Host ("      {0,-30} {1}" -f $s.Name, $s.DisplayName) -ForegroundColor DarkGray
        }
        if ($outros.Count -gt 15) { Write-Host ("      ... e mais {0}." -f ($outros.Count - 15)) -ForegroundColor DarkGray }
    }
} else {
    Write-Host "    Nenhum servico de terceiro em execucao." -ForegroundColor Yellow
}

# ------------------------------------------------------ 5. COMANDO PRONTO
$alvo = if ($candidatos.Count -gt 0) { $candidatos[0] } elseif ($gw) { $gw } else { "<ip-do-servidor>" }
$listaServ = if ($provaveis) { ($provaveis | ForEach-Object { '"' + $_.Name + '"' }) -join "," } else { '"Spooler","W32Time"' }

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
