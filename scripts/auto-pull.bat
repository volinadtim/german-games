@echo off
rem Double-click to start auto-pull. Optional args: auto-pull.bat [folder] [seconds]
set "DIR=%~1"
if "%DIR%"=="" set "DIR=%USERPROFILE%\german-games"
set "SEC=%~2"
if "%SEC%"=="" set "SEC=10"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0auto-pull.ps1" -Dir "%DIR%" -Interval %SEC%
pause
