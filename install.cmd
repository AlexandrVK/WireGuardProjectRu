@echo off
setlocal

:: Проверка прав администратора
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo RUN AS ADMIN ....
    powershell -Command "Start-Process '%0' -Verb RunAs"
    exit /b
)

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "PS1=%~dp0install.ps1"

if not exist "%PS1%" (
    echo [ERROR] PowerShell script not found:
    echo %PS1%
    exit /b 1
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
