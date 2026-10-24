@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Check-And-Cleanup.ps1"
if errorlevel 1 echo Error: operation failed. Check the message above.
pause
