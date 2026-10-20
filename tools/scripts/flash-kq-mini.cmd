@echo off
rem Double-click to open the firmware flashing tool (tools\flash.cmd) with Keyboard Quantizer Mini selected,
rem or drag and drop a .uf2 file onto this file to flash that file instead.
rem See the "Keyboard Quantizer Mini" flashing section in README.md for details.
rem With no file, the window opens without a console: conhost --headless hides PowerShell's
rem console and does not hand it to Windows Terminal. -NoConsole shows startup errors in a message box.
setlocal
if "%~1"=="" (
    if not exist "%~dp0flash.ps1" (
        echo Not found: "%~dp0flash.ps1"
        pause
        exit /b 1
    )
    start "" conhost.exe --headless powershell.exe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "%~dp0flash.ps1" -NoConsole -Keyboard KQ-mini
    exit /b 0
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0flash-kq-mini.ps1" "%~1" %2
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
