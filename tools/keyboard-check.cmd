@echo off
rem Double-click to check whether the connected keyboard's settings (keymap, trackball) are as intended.
rem Reads the settings over Vial / VIA / ZMK Studio and runs an interactive test window.
rem See the keyboard check section in README.md for details.
setlocal
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0keyboard-check.ps1" %*
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
