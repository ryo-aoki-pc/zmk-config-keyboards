@echo off
rem Double-click to choose a ZMK keyboard (LisM / AroundFortyRB / KUKEY42 / Pyuron /
rem roBa / torabo-tsuki-lp),
rem download its latest firmware and flash the right and left halves,
rem or drag and drop a .uf2 file onto this file to flash that file instead.
rem See the "ZMK" flashing section in README.md for details.
setlocal
if "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0flash-zmk.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0flash-zmk.ps1" "%~1"
)
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
