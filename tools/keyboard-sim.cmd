@echo off
rem Run keyboard scenarios in the Windows simulator window without a device.
rem A scenario JSON file can be dropped onto this launcher.
rem The window opens without a console: conhost --headless hides PowerShell's console
rem (and does not hand it to Windows Terminal). -NoConsole shows startup errors in a message box.
setlocal
if not exist "%~dp0scripts\keyboard-sim-gui.ps1" (
    echo Not found: "%~dp0scripts\keyboard-sim-gui.ps1"
    pause
    exit /b 1
)
start "" conhost.exe --headless powershell.exe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "%~dp0scripts\keyboard-sim-gui.ps1" -NoConsole %*
exit /b 0
