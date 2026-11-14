@echo off
setlocal
title opencode installer
cd /d "%~dp0"
if not exist "files\install-opencode.ps1" (
  echo.
  echo   Extract the whole zip first. This file needs the files\ folder next to it.
  goto :end
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0files\install-opencode.ps1"
:end
echo.
<nul set /p "=  Press any key to close"
pause >nul
