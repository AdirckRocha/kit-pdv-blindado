@echo off
REM ==========================================================================
REM  KIT PDV BLINDADO - BAIXAR E RODAR
REM
REM  Um arquivo so. De duplo clique nele em qualquer terminal Windows com
REM  internet. Ele baixa a versao atual, descobre o ambiente e gera o
REM  relatorio. Somente leitura - nao altera nada na maquina.
REM
REM  https://github.com/AdirckRocha/kit-pdv-blindado
REM ==========================================================================
setlocal

set "BASE=https://raw.githubusercontent.com/AdirckRocha/kit-pdv-blindado/main/scripts/"
set "DEST=%TEMP%\KitPDV"

cls
echo.
echo   KIT PDV BLINDADO
echo   ----------------
echo   Diagnostico de terminal de ponto de venda.
echo   Somente leitura: nada sera alterado nesta maquina.
echo.

REM ---------------------------------------------------- PowerShell existe?
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo   [X] PowerShell nao encontrado nesta maquina.
    echo       O diagnostico precisa dele. Fale com o suporte de TI.
    echo.
    pause
    exit /b 1
)

if not exist "%DEST%" mkdir "%DEST%" >nul 2>&1

REM --------------------------------------------------------- 1. BAIXAR
echo   [1/2] Baixando a versao atual...

powershell -NoProfile -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }; $ok = $true; foreach ($f in @('Descobrir-Ambiente','Diagnostico-PDV')) { try { Invoke-WebRequest ('%BASE%' + $f + '.ps1') -OutFile ('%DEST%\' + $f + '.ps1') -UseBasicParsing -TimeoutSec 60 } catch { Write-Host ('       falhou: ' + $f + ' - ' + $_.Exception.Message) -ForegroundColor Red; $ok = $false } }; if (-not $ok) { exit 1 }"

if errorlevel 1 (
    echo.
    echo   [X] Nao foi possivel baixar.
    echo.
    echo       Causas comuns: a loja esta sem internet, ou a rede usa
    echo       proxy e bloqueia o github.
    echo.
    echo       Alternativa: baixe o ZIP em outra maquina, em
    echo       github.com/AdirckRocha/kit-pdv-blindado, botao Code,
    echo       Download ZIP, e traga a pasta scripts por pendrive ou rede.
    echo.
    pause
    exit /b 1
)

if not exist "%DEST%\Descobrir-Ambiente.ps1" (
    echo   [X] O download terminou mas o arquivo nao esta la. Tente de novo.
    echo.
    pause
    exit /b 1
)

echo         ok
echo.

REM ------------------------------------------------------- 2. EXECUTAR
echo   [2/2] Descobrindo o ambiente e gerando o relatorio...
echo.
echo   Dica: se o sistema de vendas estiver aberto, a deteccao do
echo   servidor fica muito mais precisa.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%DEST%\Descobrir-Ambiente.ps1" -Executar

echo.
echo   ----------------------------------------------------------
echo   O relatorio em HTML foi aberto no navegador e esta salvo na
echo   area de trabalho.
echo.
echo   Para remover os arquivos temporarios desta execucao, apague:
echo   %DEST%
echo   ----------------------------------------------------------
echo.
pause
endlocal
