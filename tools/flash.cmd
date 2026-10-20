@echo off
rem Double-click to open the firmware flashing tool (a window): choose a keyboard (ZMK keyboards,
rem Keyball39, KQ-mini) and a build (the latest, a pull request build or a past build), then follow
rem the steps. Drag and drop a .uf2 / .hex file onto this file to flash that file instead.
rem See the "flashing tool" section in README.md for details.
rem With no file, the window opens without a console: conhost --headless hides PowerShell's
rem console and does not hand it to Windows Terminal. -NoConsole shows startup errors in a message box.
setlocal
if "%~1"=="" (
    if not exist "%~dp0scripts\flash.ps1" (
        echo Not found: "%~dp0scripts\flash.ps1"
        pause
        exit /b 1
    )
    start "" conhost.exe --headless powershell.exe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "%~dp0scripts\flash.ps1" -NoConsole
    exit /b 0
)
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\flash.ps1" "%~1"
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
