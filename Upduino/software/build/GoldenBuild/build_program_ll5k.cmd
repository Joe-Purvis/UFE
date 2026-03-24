@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ------------------------------------------------------------
REM UPduino Golden Build: build + program ll5k
REM Outputs are placed under .\build\
REM On SUCCESS, keeps only:
REM   - build\ll5k.bin
REM   - build\ll5k_iceprog.log
REM ------------------------------------------------------------

set "OSS_ENV=C:\Tools\oss-cad-suite\environment.bat"
set "TOP=ll5k"
set "SRC=ll5k.v"
set "PCF=upduino.pcf"

set "OUTDIR=build"

set "JSON=%OUTDIR%\%TOP%.json"
set "ASC=%OUTDIR%\%TOP%.asc"
set "BIN=%OUTDIR%\%TOP%.bin"

set "LOG_YOSYS=%OUTDIR%\%TOP%_yosys.log"
set "LOG_PNR=%OUTDIR%\%TOP%_pnr.log"
set "LOG_PACK=%OUTDIR%\%TOP%_icepack.log"
set "LOG_PROG=%OUTDIR%\%TOP%_iceprog.log"

echo ============================================================
echo  GOLDEN BUILD: %TOP%
echo  Folder: %CD%
echo  Output: %OUTDIR%\
echo ============================================================

if not exist "%OSS_ENV%" (
     echo ERROR: OSS CAD Suite env not found:
     echo   %OSS_ENV%
     exit /b 1
)

if not exist "%SRC%" (
     echo ERROR: Missing RTL:
     echo   %SRC%
     exit /b 1
)

if not exist "%PCF%" (
     echo ERROR: Missing PCF:
     echo   %PCF%
     exit /b 1
)

if not exist "%OUTDIR%" (
     mkdir "%OUTDIR%"
     if errorlevel 1 (
          echo ERROR: Could not create output directory: %OUTDIR%
          exit /b 1
     )
)

REM ---------------------------
REM 1) Yosys -> JSON
REM ---------------------------
echo.
echo [1/4] Yosys: synth to %JSON%
call "%OSS_ENV%" >nul 2>&1
yosys -p "read_verilog -sv %SRC%; synth_ice40 -top %TOP% -json %JSON%" > "%LOG_YOSYS%" 2>&1
if errorlevel 1 (
     echo ERROR: Yosys failed. See %LOG_YOSYS%
     exit /b 1
)
if not exist "%JSON%" (
     echo ERROR: Yosys did not create %JSON%. See %LOG_YOSYS%
     exit /b 1
)
echo OK: %JSON%

REM ---------------------------
REM 2) nextpnr -> ASC
REM ---------------------------
echo.
echo [2/4] nextpnr: PNR to %ASC%
nextpnr-ice40 --up5k --package sg48 --pcf "%PCF%" --json "%JSON%" --asc "%ASC%" > "%LOG_PNR%" 2>&1
if errorlevel 1 (
     echo ERROR: nextpnr failed. See %LOG_PNR%
     exit /b 1
)
if not exist "%ASC%" (
     echo ERROR: nextpnr did not create %ASC%. See %LOG_PNR%
     exit /b 1
)
echo OK: %ASC%

REM ---------------------------
REM 3) icepack -> BIN
REM ---------------------------
echo.
echo [3/4] icepack: pack to %BIN%
icepack "%ASC%" "%BIN%" > "%LOG_PACK%" 2>&1
if errorlevel 1 (
     echo ERROR: icepack failed. See %LOG_PACK%
     exit /b 1
)
if not exist "%BIN%" (
     echo ERROR: icepack did not create %BIN%. See %LOG_PACK%
     exit /b 1
)
echo OK: %BIN%

REM ---------------------------
REM 4) iceprog -> program
REM ---------------------------
echo.
echo [4/4] iceprog: programming %BIN%
iceprog "%BIN%" > "%LOG_PROG%" 2>&1
if errorlevel 1 (
     echo ERROR: iceprog failed. See %LOG_PROG%
     exit /b 1
)
echo OK: Programmed %BIN%

REM ------------------------------------------------------------
REM CLEANUP ON SUCCESS:
REM Keep only BIN + iceprog log
REM ------------------------------------------------------------
echo.
echo Cleanup: keeping only %BIN% and %LOG_PROG%

if exist "%JSON%" del /f /q "%JSON%" >nul 2>&1
if exist "%ASC%"  del /f /q "%ASC%"  >nul 2>&1

if exist "%LOG_YOSYS%" del /f /q "%LOG_YOSYS%" >nul 2>&1
if exist "%LOG_PNR%"   del /f /q "%LOG_PNR%"   >nul 2>&1
if exist "%LOG_PACK%"  del /f /q "%LOG_PACK%"  >nul 2>&1

echo.
echo ============================================================
echo  DONE
echo  NOTE: FPGA internal POR is ~87 ms; wait >=200 ms before
echo        first UART transaction after power-up/programming.
echo ============================================================

REM Remove stray numeric exit-code artefact (Explorer/OneDrive quirk)
if exist "200" del /f /q "200" >nul 2>&1

exit /b 0
