@echo off
setlocal
set "ROOT=%~dp0"
start "" powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%ROOT%remote-window.ps1"
endlocal
