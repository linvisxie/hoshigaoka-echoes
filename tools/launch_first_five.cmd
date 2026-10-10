@echo off
setlocal
cd /d "%~dp0"
set "APPDATA=%~dp0_testenv\player\appdata"
if not exist "%APPDATA%" mkdir "%APPDATA%"
start "" "%~dp0HoshigaokaEchoes.exe" --resolution 1280x720
endlocal
