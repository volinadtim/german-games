@echo off
rem Double-click: commit your local changes and send them to GitHub right now.
set "DIR=%~1"
if "%DIR%"=="" set "DIR=%USERPROFILE%\german-games"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0auto-pull.ps1" -Dir "%DIR%" -Once
pause
