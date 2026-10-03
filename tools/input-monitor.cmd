@echo off
rem Double-click to record the input events (keys, trackball motion, clicks, wheel) that every connected
rem keyboard / mouse sends to the PC, with timestamps, and to analyze the timing (tap-hold, AML, BLE stutter).
rem See the input monitor section in README.md for details.
setlocal
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\input-monitor.ps1" %*
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
