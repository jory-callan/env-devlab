@echo off
chcp 65001 >nul
REM Run install-choco.ps1 with Administrator privileges.
REM Usage: install-choco.bat [root_dir]

setlocal
set "ROOT=%~1"
if "%ROOT%"=="" set "ROOT=D:\env"

net session >nul 2>&1
if not %errorlevel%==0 (
    echo Requesting Administrator privileges...
    if "%~1"=="" (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs"
    )
    exit /b 0
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-choco.ps1" -Root "%ROOT%"
pause
endlocal