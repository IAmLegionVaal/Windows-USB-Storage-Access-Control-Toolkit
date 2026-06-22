@echo off
setlocal
cd /d "%~dp0"

:menu
set "ACTION="
set "CHOICE="
cls
echo ============================================================
echo   USB STORAGE ACCESS CONTROL TOOLKIT
echo ============================================================
echo   1. Diagnose current USB storage policy
echo   2. Repair USB storage access
echo   3. Disable USB mass storage
echo   4. Enable USB mass storage
echo   5. Set USB storage read-only
echo   6. Clear USB storage read-only policy
echo   7. Rescan Plug and Play devices
echo   0. Exit
echo ============================================================
set /p CHOICE=Select an option: 

if "%CHOICE%"=="1" set "ACTION=Diagnose"
if "%CHOICE%"=="2" set "ACTION=RepairAllSafe"
if "%CHOICE%"=="3" set "ACTION=DisableUsbStorage"
if "%CHOICE%"=="4" set "ACTION=EnableUsbStorage"
if "%CHOICE%"=="5" set "ACTION=SetReadOnly"
if "%CHOICE%"=="6" set "ACTION=ClearReadOnly"
if "%CHOICE%"=="7" set "ACTION=RescanDevices"
if "%CHOICE%"=="0" goto end
if not defined ACTION goto menu

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_USB_Storage_Access_Control_Toolkit.ps1" -Action "%ACTION%"
echo.
pause
goto menu

:end
endlocal
