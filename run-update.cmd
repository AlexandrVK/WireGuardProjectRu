@echo off
setlocal

:: Проверка прав администратора
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo RUN AS ADMIN ....
    powershell -Command "Start-Process '%0' -Verb RunAs"
    exit /b
)

:: Удаляет ru-last-run.txt чтобы обойти проверку "уже запускался сегодня"
if exist "%~dp0ru-last-run.txt" del /f /q "%~dp0ru-last-run.txt"
if exist "C:\WireGuardProject\ru-last-run.txt" del /f /q "C:\WireGuardProject\ru-last-run.txt"

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "PS1=C:\WireGuardProject\Update-Warp-RU.ps1"

if not exist "%PS1%" (
    echo [ERROR] PowerShell script not found:
    echo %PS1%
    exit /b 1
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
pause
