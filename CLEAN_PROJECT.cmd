@echo off
cd /d "%~dp0"
echo Close the game and packaging/test processes before cleaning.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Clean-Project.ps1"
pause
