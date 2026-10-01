@echo off
rem Drag and drop a .uf2 file onto this file to flash a XIAO nRF52840, BLE Micro Pro Boost
rem or Keyboard Quantizer Mini (UF2 bootloader).
rem See the "Windows" flashing section in README.md for details.
setlocal
if "%~1"=="" (
    echo Usage: drag and drop a .uf2 file onto flash-uf2.cmd
    echo    or: flash-uf2.cmd path\to\firmware.uf2 [E:]
    pause
    exit /b 2
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0flash-uf2.ps1" "%~1" %2
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
