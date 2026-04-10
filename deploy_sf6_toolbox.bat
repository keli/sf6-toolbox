@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%scripts\deploy_reframework.ps1"

if not exist "%PS1%" (
  echo [deploy] missing script: "%PS1%"
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "CODE=%ERRORLEVEL%"

if not "%CODE%"=="0" (
  echo.
  echo [deploy] failed with exit code %CODE%
)

pause
exit /b %CODE%
