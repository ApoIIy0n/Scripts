@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem  Mouse_Settings_Toggler.cmd by Apollyon
rem  - Auto-captures originals to MouseOrig.env on first run
rem  - Apply PROVIDED preset (1:1 curves, 6/11, no accel)
rem  - Restore ORIGINAL values (from MouseOrig.env)
rem  - Show current values
rem ============================================================

set "ENVFILE=%~dp0MouseOrig.env"

rem ----- Admin check (needed for HKEY_USERS\.DEFAULT) -----
net session >nul 2>&1
if %errorlevel% NEQ 0 (
  echo Requesting administrative privileges...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

rem ----- Provided (target) values -----
set "FIX_MSENS=10"
set "FIX_X=0000000000000000C0CC0C00000000008099190000000000406626000000000000333300000000"
set "FIX_Y=0000000000000000000038000000000000007000000000000000A800000000000000E00000000000"
set "FIX_DFLT_MSPEED=0"
set "FIX_DFLT_T1=0"
set "FIX_DFLT_T2=0"

rem ----- First-run: auto-capture originals if missing -----
if not exist "%ENVFILE%" (
  echo No backup found. Capturing your CURRENT mouse settings as ORIGINAL into:
  echo   "%ENVFILE%"
  call :DO_CAPTURE
  if exist "%ENVFILE%" (
    echo Backup created.
  ) else (
    echo Failed to create backup file. Check permissions and try again.
    pause
    goto END
  )
  echo.
)

:MENU
cls
echo Mouse settings tool
echo.
echo   1) Apply ORIGINAL values (from MouseOrig.env)
echo   2) Apply PROVIDED preset (1:1 scaling curves, 6/11 speed, no acceleration)
echo   3) Update ORIGINAL backup from CURRENT values (overwrite MouseOrig.env)
echo   4) Show CURRENT values
echo   0) Exit
set /p CH=> Choose an option (0-4): 
if "%CH%"=="1" goto APPLY_ORIG
if "%CH%"=="2" goto APPLY_PROV
if "%CH%"=="3" goto CAPTURE
if "%CH%"=="4" goto SHOW
if "%CH%"=="0" goto END
goto MENU

:CAPTURE
echo Capturing CURRENT values as ORIGINAL (overwriting MouseOrig.env)...
call :DO_CAPTURE
if exist "%ENVFILE%" (
  echo Wrote "%ENVFILE%".
) else (
  echo Failed to write "%ENVFILE%".
)
pause
goto MENU

:DO_CAPTURE
for /f "tokens=1,2,*" %%A in ('reg query "HKCU\Control Panel\Mouse" /v MouseSensitivity 2^>nul ^| findstr /r /c:"MouseSensitivity"') do set "CUR_MSENS=%%C"
for /f "tokens=1,2,*" %%A in ('reg query "HKCU\Control Panel\Mouse" /v SmoothMouseXCurve 2^>nul ^| findstr /r /c:"SmoothMouseXCurve"') do set "CUR_X=%%C"
for /f "tokens=1,2,*" %%A in ('reg query "HKCU\Control Panel\Mouse" /v SmoothMouseYCurve 2^>nul ^| findstr /r /c:"SmoothMouseYCurve"') do set "CUR_Y=%%C"

for /f "tokens=1,2,*" %%A in ('reg query "HKEY_USERS\.DEFAULT\Control Panel\Mouse" /v MouseSpeed 2^>nul ^| findstr /r /c:"MouseSpeed"') do set "CUR_DFLT_MSPEED=%%C"
for /f "tokens=1,2,*" %%A in ('reg query "HKEY_USERS\.DEFAULT\Control Panel\Mouse" /v MouseThreshold1 2^>nul ^| findstr /r /c:"MouseThreshold1"') do set "CUR_DFLT_T1=%%C"
for /f "tokens=1,2,*" %%A in ('reg query "HKEY_USERS\.DEFAULT\Control Panel\Mouse" /v MouseThreshold2 2^>nul ^| findstr /r /c:"MouseThreshold2"') do set "CUR_DFLT_T2=%%C"

rem trim spaces in REG_BINARY data
set "CUR_X=%CUR_X: =%"
set "CUR_Y=%CUR_Y: =%"

> "%ENVFILE%" (
  echo rem Saved original mouse settings
  echo set ORIG_MSENS=%CUR_MSENS%
  echo set ORIG_X=%CUR_X%
  echo set ORIG_Y=%CUR_Y%
  echo set ORIG_DFLT_MSPEED=%CUR_DFLT_MSPEED%
  echo set ORIG_DFLT_T1=%CUR_DFLT_T1%
  echo set ORIG_DFLT_T2=%CUR_DFLT_T2%
)
exit /b

:APPLY_ORIG
if not exist "%ENVFILE%" (
  echo "%ENVFILE%" not found. Choose option 3 to capture your originals.
  pause
  goto MENU
)
call "%ENVFILE%"
echo Applying ORIGINAL values...
reg add "HKCU\Control Panel\Mouse" /v MouseSensitivity /t REG_SZ /d "%ORIG_MSENS%" /f >nul
reg add "HKCU\Control Panel\Mouse" /v SmoothMouseXCurve /t REG_BINARY /d %ORIG_X% /f >nul
reg add "HKCU\Control Panel\Mouse" /v SmoothMouseYCurve /t REG_BINARY /d %ORIG_Y% /f >nul

reg add "HKEY_USERS\.DEFAULT\Control Panel\Mouse" /v MouseSpeed /t REG_SZ /d "%ORIG_DFLT_MSPEED%" /f >nul
reg add "HKEY_USERS\.DEFAULT\Control Panel\Mouse" /v MouseThreshold1 /t REG_SZ /d "%ORIG_DFLT_T1%" /f >nul
reg add "HKEY_USERS\.DEFAULT\Control Panel\Mouse" /v MouseThreshold2 /t REG_SZ /d "%ORIG_DFLT_T2%" /f >nul
echo Done. You may need to sign out/in for curve changes to fully apply.
pause
goto MENU

:APPLY_PROV
echo Applying PROVIDED preset...
reg add "HKCU\Control Panel\Mouse" /v MouseSensitivity /t REG_SZ /d "%FIX_MSENS%" /f >nul
reg add "HKCU\Control Panel\Mouse" /v SmoothMouseXCurve /t REG_BINARY /d %FIX_X% /f >nul
reg add "HKCU\Control Panel\Mouse" /v SmoothMouseYCurve /t REG_BINARY /d %FIX_Y% /f >nul

reg add "HKEY_USERS\.DEFAULT\Control Panel\Mouse" /v MouseSpeed /t REG_SZ /d "%FIX_DFLT_MSPEED%" /f >nul
reg add "HKEY_USERS\.DEFAULT\Control Panel\Mouse" /v MouseThreshold1 /t REG_SZ /d "%FIX_DFLT_T1%" /f >nul
reg add "HKEY_USERS\.DEFAULT\Control Panel\Mouse" /v MouseThreshold2 /t REG_SZ /d "%FIX_DFLT_T2%" /f >nul
echo Done. You may need to sign out/in for curve changes to fully apply.
pause
goto MENU

:SHOW
echo.
reg query "HKCU\Control Panel\Mouse" /v MouseSensitivity
reg query "HKCU\Control Panel\Mouse" /v SmoothMouseXCurve
reg query "HKCU\Control Panel\Mouse" /v SmoothMouseYCurve
reg query "HKEY_USERS\.DEFAULT\Control Panel\Mouse" /v MouseSpeed
reg query "HKEY_USERS\.DEFAULT\Control Panel\Mouse" /v MouseThreshold1
reg query "HKEY_USERS\.DEFAULT\Control Panel\Mouse" /v MouseThreshold2
echo.
pause
goto MENU

:END
endlocal
exit /b 0
