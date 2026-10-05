@echo off
rem Run keyboard scenarios in the Windows simulator window without a device.
rem A scenario JSON file can be dropped onto this launcher.
setlocal
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\keyboard-sim-gui.ps1" %*
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
