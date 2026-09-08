@echo off
REM ==========================================================================
REM  KIT PDV BLINDADO - TESTE RAPIDO DE LOJA
REM  Para o pessoal da loja rodar ANTES de abrir chamado.
REM  Nao altera nada. Gera um arquivo TXT na area de trabalho.
REM
REM  Uso:  Teste-Rapido-Loja.bat  [ip-do-servidor]
REM        Sem parametro, testa o gateway detectado automaticamente.
REM ==========================================================================
setlocal enabledelayedexpansion

set "PS=powershell -NoProfile -ExecutionPolicy Bypass -Command"
set "PROBLEMAS=0"
set "SAIDA=%USERPROFILE%\Desktop\Teste_Loja_%COMPUTERNAME%.txt"

REM ---- Descobre o gateway real desta maquina -------------------------------
set "GW="
for /f "delims=" %%a in ('%PS% "$c = Get-NetIPConfiguration -ErrorAction SilentlyContinue; $g = $c.Where({$_.IPv4DefaultGateway}); if ($g) { $g[0].IPv4DefaultGateway.NextHop } "') do set "GW=%%a"

REM ---- Alvo: parametro tem prioridade sobre o gateway detectado ------------
if not "%~1"=="" (
    set "ALVO=%~1"
    set "ORIGEM=informado por voce"
) else (
    if defined GW (
        set "ALVO=!GW!"
        set "ORIGEM=gateway detectado automaticamente"
    ) else (
        set "ALVO="
        set "ORIGEM=nao foi possivel detectar"
    )
)

cls
echo.
echo   TESTE RAPIDO DE LOJA - %COMPUTERNAME%
echo   -------------------------------------
echo.

> "%SAIDA%" echo ==============================================
>>"%SAIDA%" echo  TESTE RAPIDO DE LOJA
>>"%SAIDA%" echo  Terminal : %COMPUTERNAME%
>>"%SAIDA%" echo  Usuario  : %USERNAME%
>>"%SAIDA%" echo  Data     : %date% %time%
>>"%SAIDA%" echo ==============================================
>>"%SAIDA%" echo.

REM ========================= 1. REDE ========================================
echo [1/5] Verificando a placa de rede...
>>"%SAIDA%" echo --- 1. REDE ---
%PS% "$c = Get-NetIPConfiguration -ErrorAction SilentlyContinue; $g = $c.Where({$_.IPv4DefaultGateway}); if (-not $g) { 'Nenhuma interface com gateway' } else { foreach ($i in $g) { 'Interface : {0}' -f $i.InterfaceAlias; 'IP        : {0}' -f ($i.IPv4Address.IPAddress -join ', '); 'Gateway   : {0}' -f $i.IPv4DefaultGateway.NextHop; 'DNS       : {0}' -f ($i.DNSServer.Where({$_.AddressFamily -eq 2}).ServerAddresses -join ', '); '' } }" >>"%SAIDA%" 2>&1

if not defined GW (
    echo       [X] SEM GATEWAY - cabo solto, Wi-Fi caiu ou roteador desligado
    >>"%SAIDA%" echo RESULTADO: FALHA - sem gateway
    set /a PROBLEMAS+=1
) else (
    echo       [OK] Conectado - gateway !GW!
    >>"%SAIDA%" echo RESULTADO: OK
)
>>"%SAIDA%" echo.

REM ================== 2. ROTEADOR / SERVIDOR ================================
echo [2/5] Testando %ALVO% ^(%ORIGEM%^)...
>>"%SAIDA%" echo --- 2. ROTEADOR/SERVIDOR ---
>>"%SAIDA%" echo Alvo: %ALVO%  (%ORIGEM%)
if not defined ALVO (
    echo       [X] Sem alvo para testar
    >>"%SAIDA%" echo RESULTADO: NAO TESTADO
    set /a PROBLEMAS+=1
) else (
    call :ping "%ALVO%"
    if !errorlevel! equ 0 (
        echo       [OK] Responde
        >>"%SAIDA%" echo RESULTADO: OK
    ) else (
        echo       [X] NAO RESPONDE - problema DENTRO da loja
        >>"%SAIDA%" echo RESULTADO: FALHA
        set /a PROBLEMAS+=1
    )
)
>>"%SAIDA%" echo.

REM ========================= 3. INTERNET ====================================
echo [3/5] Testando a internet...
>>"%SAIDA%" echo --- 3. INTERNET ---
call :ping "8.8.8.8"
if !errorlevel! equ 0 (
    echo       [OK] Internet respondendo
    >>"%SAIDA%" echo RESULTADO PING: OK
) else (
    echo       [X] SEM INTERNET - problema no link ou na operadora
    >>"%SAIDA%" echo RESULTADO PING: FALHA
    set /a PROBLEMAS+=1
)
%PS% "try { $null = [System.Net.Dns]::GetHostEntry('www.google.com'); 'Resolucao DNS: OK'; exit 0 } catch { 'Resolucao DNS: FALHA - ping funciona mas nome nao resolve'; exit 1 }" >>"%SAIDA%" 2>&1
if errorlevel 1 (
    echo       [X] DNS NAO RESOLVE - o problema e de DNS, nao do link
    set /a PROBLEMAS+=1
)
>>"%SAIDA%" echo.

REM ======================== 4. IMPRESSORAS ==================================
echo [4/5] Verificando impressoras...
>>"%SAIDA%" echo --- 4. IMPRESSORAS ---
%PS% "$p = @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue); if ($p.Count -eq 0) { 'Nenhuma impressora instalada'; exit 0 }; foreach ($i in $p) { '{0,-45} {1}{2}' -f $i.Name, $(if ($i.WorkOffline) {'OFFLINE'} else {'pronta '}), $(if ($i.Default) {' [PADRAO]'} else {''}) }; exit $p.Where({$_.WorkOffline}).Count" >>"%SAIDA%" 2>&1
set "OFFP=!errorlevel!"
if !OFFP! gtr 0 (
    echo       [X] !OFFP! impressora^(s^) OFFLINE - cupom nao sai
    >>"%SAIDA%" echo RESULTADO: FALHA - !OFFP! offline
    set /a PROBLEMAS+=1
) else (
    echo       [OK] Nenhuma impressora offline
    >>"%SAIDA%" echo RESULTADO: OK
)
>>"%SAIDA%" echo.

REM =========================== 5. DISCO =====================================
echo [5/5] Verificando espaco em disco...
>>"%SAIDA%" echo --- 5. DISCO ---
%PS% "$d = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue); foreach ($i in $d) { '{0}  {1,7:N1} GB livres de {2,7:N1} GB  ({3:N0} por cento livre)' -f $i.DeviceID, ($i.FreeSpace/1GB), ($i.Size/1GB), (($i.FreeSpace/$i.Size)*100) }; exit $d.Where({$_.FreeSpace -lt 10GB}).Count" >>"%SAIDA%" 2>&1
set "DBAIXO=!errorlevel!"
if !DBAIXO! gtr 0 (
    echo       [X] !DBAIXO! disco^(s^) com menos de 10 GB livres
    >>"%SAIDA%" echo RESULTADO: ATENCAO - !DBAIXO! disco com pouco espaco
    set /a PROBLEMAS+=1
) else (
    echo       [OK] Espaco em disco suficiente
    >>"%SAIDA%" echo RESULTADO: OK
)
>>"%SAIDA%" echo.

REM ========================== VEREDITO ======================================
>>"%SAIDA%" echo ==============================================
if "%PROBLEMAS%"=="0" (
    >>"%SAIDA%" echo VEREDITO: NENHUM PROBLEMA DETECTADO
) else (
    >>"%SAIDA%" echo VEREDITO: %PROBLEMAS% PROBLEMA^(S^) DETECTADO^(S^)
)
>>"%SAIDA%" echo ==============================================

echo.
echo   -------------------------------------
if "%PROBLEMAS%"=="0" (
    echo   VEREDITO: nenhum problema detectado
) else (
    echo   VEREDITO: %PROBLEMAS% problema^(s^) detectado^(s^)
)
echo.
echo   Arquivo gerado na area de trabalho:
echo   Teste_Loja_%COMPUTERNAME%.txt
echo.
echo   Anexe esse arquivo ao abrir o chamado.
echo   -------------------------------------
echo.
pause
endlocal
goto :eof

REM ==========================================================================
REM  :ping  <alvo>   - 4 tentativas via .NET, saida limpa, sem problema de
REM                    codepage. Retorna 0 se respondeu, 1 se nao.
REM ==========================================================================
:ping
%PS% "$png = New-Object System.Net.NetworkInformation.Ping; $ok = 0; $soma = 0; foreach ($i in 1..4) { try { $r = $png.Send('%~1', 2000); if ($r.Status -eq 'Success') { $ok++; $soma += $r.RoundtripTime } } catch {} }; $perda = (4 - $ok) * 25; if ($ok -gt 0) { 'Enviados 4, recebidos {0}, perda {1} por cento, tempo medio {2} ms' -f $ok, $perda, [math]::Round($soma / $ok, 0) } else { 'Enviados 4, recebidos 0, perda 100 por cento - SEM RESPOSTA' }; exit $(if ($ok -gt 0) { 0 } else { 1 })" >>"%SAIDA%" 2>&1
exit /b %errorlevel%
