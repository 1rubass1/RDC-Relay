@echo off
title Remote Desktop Commander
call "C:\Program Files\nodejs\npx.cmd" --yes @wonderwhy-er/desktop-commander@latest remote
if errorlevel 1 pause
