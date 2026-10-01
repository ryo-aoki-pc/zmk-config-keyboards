@echo off
rem Double-click to download the latest Keyball39 firmware and flash both halves,
rem or drag and drop a .hex file onto this file to flash that file instead.
rem See the "Keyball39" flashing section in README.md for details.
setlocal
if "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0flash-keyball.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0flash-keyball.ps1" "%~1"
)
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
