@echo off
rem Double-click to open the firmware flashing tool (tools\flash.cmd) with Keyboard Quantizer Mini selected,
rem or drag and drop a .uf2 file onto this file to flash that file instead.
rem See the "Keyboard Quantizer Mini" flashing section in README.md for details.
setlocal
if "%~1"=="" (
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0flash.ps1" -Keyboard KQ-mini
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0flash-kq-mini.ps1" "%~1" %2
)
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
