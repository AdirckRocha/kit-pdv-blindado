@echo off
REM ==========================================================================
REM  KIT PDV BLINDADO - TESTE RAPIDO DE LOJA
REM  Para o pessoal da loja rodar ANTES de abrir chamado.
REM  Nao altera nada. Gera um arquivo TXT na area de trabalho.
REM ==========================================================================
setlocal enabledelayedexpansion

set "SERVIDOR=%~1"
if "%SERVIDOR%"=="" set "SERVIDOR=192.168.0.1"

set "SAIDA=%USERPROFILE%\Desktop\Teste_Loja_%COMPUTERNAME%.txt"

echo ============================================== >  "%SAIDA%"
echo  TESTE RAPIDO DE LOJA                          >> "%SAIDA%"
echo  Terminal : %COMPUTERNAME%                     >> "%SAIDA%"
echo  Data     : %date% %time%                      >> "%SAIDA%"
echo ============================================== >> "%SAIDA%"
echo. >> "%SAIDA%"

cls
echo.
echo   TESTE RAPIDO DE LOJA - %COMPUTERNAME%
echo   ------------------------------------
echo.

echo [1/5] Verificando cabo de rede...
echo --- 1. PLACA DE REDE --- >> "%SAIDA%"
ipconfig | findstr /C:"IPv4" /C:"Gateway" >> "%SAIDA%"
ipconfig | findstr /C:"Midia desconectada" /C:"Media disconnected" >nul
if !errorlevel! equ 0 (
  echo       [X] CABO DESCONECTADO ou Wi-Fi caiu
  echo RESULTADO: CABO DESCONECTADO >> "%SAIDA%"
) else (
  echo       [OK] Placa de rede conectada
  echo RESULTADO: OK >> "%SAIDA%"
)
echo. >> "%SAIDA%"

echo [2/5] Testando o roteador da loja...
echo --- 2. ROTEADOR/SERVIDOR (%SERVIDOR%) --- >> "%SAIDA%"
ping -n 3 %SERVIDOR% >> "%SAIDA%" 2>&1
ping -n 2 %SERVIDOR% >nul 2>&1
if !errorlevel! equ 0 ( echo       [OK] Roteador responde
) else ( echo       [X] ROTEADOR NAO RESPONDE - problema DENTRO da loja )

echo [3/5] Testando a internet...
echo. >> "%SAIDA%"
echo --- 3. INTERNET --- >> "%SAIDA%"
ping -n 3 8.8.8.8 >> "%SAIDA%" 2>&1
ping -n 2 8.8.8.8 >nul 2>&1
if !errorlevel! equ 0 ( echo       [OK] Internet respondendo
) else ( echo       [X] SEM INTERNET - problema no link/operadora )

echo [4/5] Verificando impressora...
echo. >> "%SAIDA%"
echo --- 4. IMPRESSORAS --- >> "%SAIDA%"
wmic printer get Name,WorkOffline,Default /format:list 2>nul >> "%SAIDA%"
echo       [i] Detalhes no arquivo

echo [5/5] Verificando espaco em disco...
echo. >> "%SAIDA%"
echo --- 5. DISCO --- >> "%SAIDA%"
wmic logicaldisk where "DriveType=3" get DeviceID,FreeSpace,Size /format:list 2>nul >> "%SAIDA%"
echo       [i] Detalhes no arquivo

echo.
echo   ------------------------------------
echo   Arquivo gerado na area de trabalho:
echo   Teste_Loja_%COMPUTERNAME%.txt
echo.
echo   Anexe esse arquivo ao abrir o chamado.
echo   ------------------------------------
echo.
pause
endlocal
