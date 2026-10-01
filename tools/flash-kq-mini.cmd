@echo off
rem Double-click to download the latest Keyboard Quantizer Mini firmware and flash it,
rem or drag and drop a .uf2 file onto this file to flash that file instead.
rem See the "Keyboard Quantizer Mini" flashing section in README.md for details.
setlocal
if "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0flash-kq-mini.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0flash-kq-mini.ps1" "%~1" %2
)
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
