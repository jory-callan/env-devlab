@echo off
chcp 65001 >nul
REM Run install-scoop.ps1 (Scoop needs no Administrator privileges).
REM Usage: install-scoop.bat [root_dir]

setlocal
set "ROOT=%~1"
if "%ROOT%"=="" set "ROOT=D:\env"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-scoop.ps1" -Root "%ROOT%"
pause
endlocal