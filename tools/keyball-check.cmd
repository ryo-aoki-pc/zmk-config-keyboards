@echo off
rem Double-click to check whether a Keyball (QMK / VIA) recognizes its trackball (read-only).
rem Connect the Keyball directly to the PC, not through a Keyboard Quantizer.
rem See the Keyball39 trackball troubleshooting section in README.md for details.
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0keyball-check.ps1" %*
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
