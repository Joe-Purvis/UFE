@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem -----------------------------------------------------------------------------
rem build_ll5k_menu.cmd
rem -----------------------------------------------------------------------------
rem Interactive UPduino iCE40UP5K build with menu + pause between steps.
rem Prompts for:
rem   - Verilog source .v/.sv file
rem   - Constraint .pcf file
rem   - Top module name
rem
rem Steps:
rem   1) Yosys    -> JSON netlist
rem   2) nextpnr  -> ASC + JSON report (utilisation inside)
rem   3) icepack  -> BIN
rem   4) iceprog  -> Program device
rem
rem Runs in cmd.exe to avoid PowerShell quoting issues.
rem -----------------------------------------------------------------------------

rem === Toolchain environment ===================================================
set "OSS_ENV=C:\Tools\oss-cad-suite\environment.bat"
if not exist "%OSS_ENV%" (
     echo ERROR: OSS CAD Suite environment not found:
     echo        "%OSS_ENV%"
     exit /b 2
)

call "%OSS_ENV%"
if errorlevel 1 (
     echo ERROR: Failed to load OSS CAD Suite environment.
     exit /b 3
)

rem === Prompt for inputs =======================================================
call :PromptInputs
if errorlevel 1 exit /b 10

rem === Derived outputs =========================================================
for %%F in ("%SRC%") do set "BASE=%%~nF"
set "JSON=%BASE%.json"
set "ASC=%BASE%.asc"
set "BIN=%BASE%.bin"
set "PNRJSON=%BASE%_pnr.json"

set "YOSYSLOG=%BASE%_yosys.log"
set "PNRLOG=%BASE%_nextpnr.log"
set "PACKLOG=%BASE%_icepack.log"
set "PROGLOG=%BASE%_iceprog.log"

:MENU
cls
echo.
echo ==========================================================
echo  LL5k Interactive Build Menu
echo ==========================================================
echo   Folder : %CD%
echo   SRC    : %SRC%
echo   TOP    : %TOP%
echo   PCF    : %PCF%
echo   DEVICE : %DEVICE%
echo   PACKAGE: %PACKAGE%
echo   BASE   : %BASE%
echo.
echo   [1] Run Yosys     (produce %JSON%)
echo   [2] Run nextpnr   (produce %ASC% and %PNRJSON%)
echo   [3] Run icepack   (produce %BIN%)
echo   [4] Run iceprog   (program %BIN%)
echo.
echo   [U] Show utilisation summary (from %PNRJSON%)
echo   [R] Re-enter inputs (SRC/PCF/TOP/etc.)
echo   [L] Open folder (Explorer)
echo   [Q] Quit
echo.
set "CHOICE="
set /p CHOICE="Select an option: "

if /I "%CHOICE%"=="1" goto STEP1
if /I "%CHOICE%"=="2" goto STEP2
if /I "%CHOICE%"=="3" goto STEP3
if /I "%CHOICE%"=="4" goto STEP4
if /I "%CHOICE%"=="U" goto UTIL
if /I "%CHOICE%"=="R" goto REINPUT
if /I "%CHOICE%"=="L" goto OPENFOLDER
if /I "%CHOICE%"=="Q" goto DONE

goto MENU

:REINPUT
call :PromptInputs
if errorlevel 1 (
     echo.
     echo ERROR: Input cancelled or invalid.
     pause
)
rem Recompute outputs after new SRC
for %%F in ("%SRC%") do set "BASE=%%~nF"
set "JSON=%BASE%.json"
set "ASC=%BASE%.asc"
set "BIN=%BASE%.bin"
set "PNRJSON=%BASE%_pnr.json"
set "YOSYSLOG=%BASE%_yosys.log"
set "PNRLOG=%BASE%_nextpnr.log"
set "PACKLOG=%BASE%_icepack.log"
set "PROGLOG=%BASE%_iceprog.log"
goto MENU

:STEP1
echo.
echo [1] Yosys: synth to %JSON%
echo Command:
echo   yosys -p "read_verilog -sv %SRC%; synth_ice40 -top %TOP% -json %JSON%"
echo.
yosys -p "read_verilog -sv %SRC%; synth_ice40 -top %TOP% -json %JSON%" > "%YOSYSLOG%" 2>&1
if errorlevel 1 (
     echo.
     echo ERROR: Yosys failed. See: %YOSYSLOG%
     pause
     goto MENU
)
echo.
echo OK: %JSON%
echo Log: %YOSYSLOG%
pause
goto MENU

:STEP2
if not exist "%JSON%" (
     echo.
     echo ERROR: Missing %JSON%
     echo Run step [1] first.
     pause
     goto MENU
)
echo.
echo [2] nextpnr: PNR to %ASC% and report to %PNRJSON%
echo Command:
echo   nextpnr-ice40 --%DEVICE% --package %PACKAGE% --json "%JSON%" --pcf "%PCF%" --asc "%ASC%" --report "%PNRJSON%"
echo.
nextpnr-ice40 --%DEVICE% --package %PACKAGE% --json "%JSON%" --pcf "%PCF%" --asc "%ASC%" --report "%PNRJSON%" > "%PNRLOG%" 2>&1
if errorlevel 1 (
     echo.
     echo ERROR: nextpnr failed. See: %PNRLOG%
     pause
     goto MENU
)
echo.
echo OK: %ASC%
echo OK: %PNRJSON%
echo Log: %PNRLOG%
pause
goto MENU

:STEP3
if not exist "%ASC%" (
     echo.
     echo ERROR: Missing %ASC%
     echo Run step [2] first.
     pause
     goto MENU
)
echo.
echo [3] icepack: pack to %BIN%
echo Command:
echo   icepack "%ASC%" "%BIN%"
echo.
icepack "%ASC%" "%BIN%" > "%PACKLOG%" 2>&1
if errorlevel 1 (
     echo.
     echo ERROR: icepack failed. See: %PACKLOG%
     pause
     goto MENU
)
echo.
echo OK: %BIN%
echo Log: %PACKLOG%
pause
goto MENU

:STEP4
if not exist "%BIN%" (
     echo.
     echo ERROR: Missing %BIN%
     echo Run step [3] first.
     pause
     goto MENU
)
echo.
echo [4] iceprog: program %BIN%
echo Command:
echo   iceprog "%BIN%"
echo.
iceprog "%BIN%" > "%PROGLOG%" 2>&1
if errorlevel 1 (
     echo.
     echo ERROR: iceprog failed. See: %PROGLOG%
     pause
     goto MENU
)
echo.
echo OK: Programmed %BIN%
echo Log: %PROGLOG%
pause
goto MENU

:UTIL
if not exist "%PNRJSON%" (
     echo.
     echo ERROR: Missing %PNRJSON%
     echo Run step [2] first (nextpnr --report).
     pause
     goto MENU
)
echo.
echo === Utilisation summary (from %PNRJSON%) ===
findstr /C:"\"utilization\"" "%PNRJSON%"
echo.
echo --- Key blocks ---
findstr /C:"\"ICESTORM_LC\"" /C:"\"ICESTORM_RAM\"" /C:"\"ICESTORM_SPRAM\"" /C:"\"ICESTORM_DSP\"" /C:"\"ICESTORM_PLL\"" /C:"\"SB_IO\"" /C:"\"SB_GB\"" "%PNRJSON%"
echo.
pause
goto MENU

:OPENFOLDER
explorer "%CD%"
goto MENU

:DONE
endlocal
exit /b 0

rem -----------------------------------------------------------------------------
rem Subroutine: PromptInputs
rem Returns errorlevel 0 on success, 1 on failure/cancel.
rem -----------------------------------------------------------------------------
:PromptInputs
cls
echo.
echo ==========================================================
echo  Configure build inputs
echo ==========================================================
echo   Folder: %CD%
echo.

rem --- Verilog source ----------------------------------------------------------
:ASKSRC
echo Available Verilog/SystemVerilog files in this folder:
dir /b *.v *.sv 2>nul
echo.
set "SRC="
set /p SRC="Enter RTL file name (.v or .sv): "
if "%SRC%"=="" (
     echo ERROR: Please enter a file name.
     echo.
     goto ASKSRC
)
if not exist "%SRC%" (
     echo ERROR: File not found: "%SRC%"
     echo.
     goto ASKSRC
)

rem --- PCF ---------------------------------------------------------------------
:ASKPCF
echo.
echo Available PCF files in this folder:
dir /b *.pcf 2>nul
echo.
set "PCF="
set /p PCF="Enter constraints file (.pcf): "
if "%PCF%"=="" (
     echo ERROR: Please enter a file name.
     echo.
     goto ASKPCF
)
if not exist "%PCF%" (
     echo ERROR: File not found: "%PCF%"
     echo.
     goto ASKPCF
)

rem --- Top module --------------------------------------------------------------
echo.
set "TOP="
set /p TOP="Enter top module name (e.g. LL5k_WIP): "
if "%TOP%"=="" (
     echo ERROR: Please enter a top module name.
     echo.
     goto PromptInputs
)

rem --- Device/package (defaults offered) ---------------------------------------
echo.
set "DEVICE=up5k"
set /p DEVICE="Enter device (default up5k; options typically up5k/hx8k/etc.): "
if "%DEVICE%"=="" set "DEVICE=up5k"

set "PACKAGE=sg48"
set /p PACKAGE="Enter package (default sg48): "
if "%PACKAGE%"=="" set "PACKAGE=sg48"

echo.
echo Summary:
echo   SRC    = %SRC%
echo   PCF    = %PCF%
echo   TOP    = %TOP%
echo   DEVICE = %DEVICE%
echo   PACKAGE= %PACKAGE%
echo.
pause
exit /b 0
