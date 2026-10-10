@echo off
setlocal
rem Copy beside the exported EXE. All progress stays in an isolated profile.
set "APPDATA=%~dp0_testenv\player\appdata"
if not exist "%APPDATA%" mkdir "%APPDATA%"
if not exist "%~dp0HoshigaokaEchoes.exe" (
  echo Copy this launcher beside HoshigaokaEchoes.exe first.
  pause
  exit /b 1
)
"%~dp0HoshigaokaEchoes.exe" --resolution 1280x720 -- --scene=battle --stage=1-5
endlocal
