@echo off
rem Double-click to open the firmware flashing tool (flash.cmd) with Keyball39 selected,
rem or drag and drop a .hex file onto this file to flash that file instead.
rem See the "Keyball39" flashing section in README.md for details.
setlocal
if "%~1"=="" (
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0flash.ps1" -Keyboard Keyball39
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0flash-keyball.ps1" "%~1"
)
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
