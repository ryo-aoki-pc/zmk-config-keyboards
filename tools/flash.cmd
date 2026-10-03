@echo off
rem Double-click to open the firmware flashing tool (a window): choose a keyboard (ZMK keyboards,
rem Keyball39, KQ-mini) and a build (the latest, a pull request build or a past build), then follow
rem the steps. Drag and drop a .uf2 / .hex file onto this file to flash that file instead.
rem See the "flashing tool" section in README.md for details.
setlocal
if "%~1"=="" (
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\flash.ps1"
) else (
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\flash.ps1" "%~1"
)
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
