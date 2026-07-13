@echo off
setlocal EnableExtensions

set "PORT=8765"
if not "%~1"=="" set "PORT=%~1"

rem Support both a standalone repository and the competition workspace layout.
set "SITE_DIR="
if exist "%~dp0deliverables\app\index.html" (
  for %%I in ("%~dp0.") do set "SITE_DIR=%%~fI"
)
for /d %%D in ("%~dp0*") do (
  if not defined SITE_DIR if exist "%%~fD\deliverables\app\index.html" set "SITE_DIR=%%~fD"
)

if not defined SITE_DIR (
  echo ERROR: The Flutter Web build could not be found.
  pause
  exit /b 1
)

set "SERVER_SCRIPT=%SITE_DIR%\scripts\local-web-server.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SERVER_SCRIPT%" -Action Stop -Port "%PORT%"
set "EXIT_CODE=%ERRORLEVEL%"

if not defined NO_PAUSE pause
exit /b %EXIT_CODE%
