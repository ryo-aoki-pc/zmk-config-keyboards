@echo off
rem Double-click to open the firmware flashing tool (tools\flash.cmd) for the ZMK keyboards (LisM /
rem AroundFortyRB / KUKEY42 / Pyuron / roBa / torabo-tsuki-lp),
rem or drag and drop a .uf2 file onto this file to flash that file instead.
rem See the "ZMK" flashing section in README.md for details.
setlocal
if "%~1"=="" (
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0flash-zmk.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0flash-zmk.ps1" "%~1"
)
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
