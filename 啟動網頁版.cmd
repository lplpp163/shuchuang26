@echo off
setlocal EnableExtensions
chcp 65001 >nul

set "ACTION=Start"
set "PORT=8765"

if /i "%~1"=="stop" (
  set "ACTION=Stop"
  if not "%~2"=="" set "PORT=%~2"
) else if /i "%~1"=="status" (
  set "ACTION=Status"
  if not "%~2"=="" set "PORT=%~2"
) else (
  if not "%~1"=="" set "PORT=%~1"
)

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
  echo Expected: a folder containing deliverables\app\index.html
  pause
  exit /b 1
)

set "SERVER_SCRIPT=%SITE_DIR%\scripts\local-web-server.ps1"
if not exist "%SERVER_SCRIPT%" (
  echo ERROR: The local web server script could not be found.
  echo Expected: %SERVER_SCRIPT%
  pause
  exit /b 1
)

set "BROWSER_ARG="
if defined NO_BROWSER set "BROWSER_ARG=-NoBrowser"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SERVER_SCRIPT%" -Action %ACTION% -Port "%PORT%" %BROWSER_ARG%
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  if not defined NO_PAUSE pause
)

exit /b %EXIT_CODE%
