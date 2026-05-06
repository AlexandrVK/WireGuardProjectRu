@echo off
chcp 65001 > nul
net session >nul 2>&1 || (
    echo RUN AS ADMIN
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

set "_tmp=%TEMP%\compare_%RANDOM%.ps1"
set "_dir=%~dp0"
if "%_dir:~-1%"=="\" set "_dir=%_dir:~0,-1%"

setlocal enabledelayedexpansion
set "_copy=0"
for /f "usebackq delims=" %%L in ("%~f0") do (
    if "%%L"==":PS_END:" set "_copy=0"
    if !_copy!==1 echo(%%L>> "%_tmp%"
    if "%%L"==":PS_START:" set "_copy=1"
)
endlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%_tmp%" -ScriptDir "%_dir%"
set "_exit=%ERRORLEVEL%"
del /f /q "%_tmp%" 2>nul
exit /b %_exit%

:PS_START:
# ==============================================================================
# test-compare-routes (embedded in cmd)
# Сравнивает AllowedIPs из warp-ru.conf с реально активными маршрутами WireGuard.
# Показывает: что есть в конфиге но не применено, и что применено но не в конфиге.
# ==============================================================================

param([string]$ScriptDir = "")

$WGDir      = "C:\Program Files\WireGuard"
$WgExe      = "$WGDir\wg.exe"
$ConfDir    = if ($ScriptDir) { $ScriptDir } else { "C:\WireGuardProject" }
$FinalConf  = "$ConfDir\warp-ru.conf"
$TunnelName = "warp-ru"

# ── Цвета ──────────────────────────────────────────────────────────────────────
function Write-Header { param([string]$t) Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Write-OK     { param([string]$t) Write-Host "  $t" -ForegroundColor Green }
function Write-Warn   { param([string]$t) Write-Host "  $t" -ForegroundColor Yellow }
function Write-Err    { param([string]$t) Write-Host "  $t" -ForegroundColor Red }
function Write-Dim    { param([string]$t) Write-Host "  $t" -ForegroundColor DarkGray }

Write-Host ""
Write-Host "  WARP-RU Route Comparison" -ForegroundColor White
Write-Host "  ─────────────────────────────" -ForegroundColor DarkGray

# ── Проверка зависимостей ──────────────────────────────────────────────────────
Write-Header "Предварительные проверки"

if (-not (Test-Path $WgExe)) {
    Write-Err "wg.exe не найден: $WgExe"
    Write-Err "Установите WireGuard: https://www.wireguard.com/install/"
    pause; exit 1
}
Write-OK "wg.exe найден"

if (-not (Test-Path $FinalConf)) {
    Write-Err "warp-ru.conf не найден: $FinalConf"
    Write-Err "Запустите run-update.cmd для генерации конфига"
    pause; exit 1
}
Write-OK "warp-ru.conf найден"

# ── Статус туннеля ─────────────────────────────────────────────────────────────
Write-Header "Статус туннеля"

$wgOut = & $WgExe show $TunnelName 2>&1
$tunnelUp = ($LASTEXITCODE -eq 0 -and ($wgOut -match "interface"))

if (-not $tunnelUp) {
    Write-Warn "Туннель $TunnelName не запущен"
    Write-Warn "Для сравнения активных маршрутов туннель должен быть запущен"
    Write-Dim  "Запустите run-update.cmd и повторите"

    # Всё равно можем показать что в конфиге
    Write-Header "Содержимое warp-ru.conf (туннель не активен)"
    $confIPs = @()
    $inPeer  = $false
    foreach ($line in (Get-Content $FinalConf)) {
        if ($line.Trim() -eq "[Peer]") { $inPeer = $true }
        if ($inPeer -and $line.Trim() -match "^AllowedIPs\s*=\s*(.+)") {
            $confIPs = $Matches[1] -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d" }
        }
    }
    Write-OK   "Блоков в конфиге: $($confIPs.Count)"
    $dnsEntries = $confIPs | Where-Object { $_ -match "/32$" }
    Write-Dim  "DNS /32 записей: $($dnsEntries.Count) — $($dnsEntries -join ', ')"
    pause; exit 0
}

Write-OK "Туннель $TunnelName активен"

# ── Читаем AllowedIPs из конфига ───────────────────────────────────────────────
Write-Header "Разбор warp-ru.conf"

$confIPs = @()
$inPeer  = $false
foreach ($line in (Get-Content $FinalConf)) {
    if ($line.Trim() -eq "[Peer]") { $inPeer = $true }
    if ($inPeer -and $line.Trim() -match "^AllowedIPs\s*=\s*(.+)") {
        $confIPs = $Matches[1] -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        break
    }
}

$confIPv4 = $confIPs | Where-Object { $_ -match "^\d+\.\d+\.\d+\.\d+/\d+$" }
$confIPv6 = $confIPs | Where-Object { $_ -match ":" }

Write-OK  "Всего записей в конфиге: $($confIPs.Count)"
Write-Dim "  IPv4: $($confIPv4.Count)"
Write-Dim "  IPv6: $($confIPv6.Count)"

$dnsInConf = $confIPv4 | Where-Object { $_ -match "/32$" }
if ($dnsInConf.Count -gt 0) {
    Write-OK "DNS /32 записи: $($dnsInConf -join ', ')"
} else {
    Write-Warn "DNS /32 записи отсутствуют — DNS может идти мимо туннеля"
}

# ── Читаем реально активные маршруты из wg show ────────────────────────────────
Write-Header "Активные маршруты (wg show)"

# wg show warp-ru dump — машиночитаемый формат: interface, public-key, preshared-key, endpoint, allowed-ips, ...
$dumpOut = & $WgExe show $TunnelName allowed-ips 2>&1

$activeIPs = @()
foreach ($line in $dumpOut) {
    $line.Trim() -split "\s+" | ForEach-Object {
        $entry = $_.Trim()
        if ($entry -match "^\d+\.\d+\.\d+\.\d+/\d+$" -or $entry -match "^[\da-f:]+/\d+$") {
            $activeIPs += $entry
        }
    }
}

$activeIPv4 = $activeIPs | Where-Object { $_ -match "^\d+\.\d+\.\d+\.\d+/\d+$" }

Write-OK  "Всего активных маршрутов: $($activeIPs.Count)"
Write-Dim "  IPv4: $($activeIPv4.Count)"

# ── Сравнение ──────────────────────────────────────────────────────────────────
Write-Header "Сравнение конфига с активными маршрутами"

$confSet   = [System.Collections.Generic.HashSet[string]]($confIPv4)
$activeSet = [System.Collections.Generic.HashSet[string]]($activeIPv4)

# В конфиге но не активны
$onlyInConf = $confIPv4 | Where-Object { -not $activeSet.Contains($_) }
# Активны но не в конфиге
$onlyActive = $activeIPv4 | Where-Object { -not $confSet.Contains($_) }
# Совпадают
$matched = $confIPv4 | Where-Object { $activeSet.Contains($_) }

Write-OK "Совпадают: $($matched.Count) из $($confIPv4.Count)"

if ($onlyInConf.Count -eq 0 -and $onlyActive.Count -eq 0) {
    Write-OK "Конфиг полностью соответствует активным маршрутам — всё в порядке"
} else {
    if ($onlyInConf.Count -gt 0) {
        Write-Warn "В конфиге но НЕ применены ($($onlyInConf.Count) блоков):"
        $onlyInConf | Select-Object -First 20 | ForEach-Object { Write-Dim "  - $_" }
        if ($onlyInConf.Count -gt 20) { Write-Dim "  ... и ещё $($onlyInConf.Count - 20)" }
        Write-Warn "Возможная причина: туннель не перезапускался после обновления конфига"
        Write-Dim  "Запустите run-update.cmd для применения через wg syncconf"
    }

    if ($onlyActive.Count -gt 0) {
        Write-Warn "Активны но НЕ в конфиге ($($onlyActive.Count) блоков):"
        $onlyActive | Select-Object -First 20 | ForEach-Object { Write-Dim "  - $_" }
        if ($onlyActive.Count -gt 20) { Write-Dim "  ... и ещё $($onlyActive.Count - 20)" }
        Write-Warn "Возможная причина: конфиг обновился но syncconf ещё не применён"
    }
}

# ── Итог ───────────────────────────────────────────────────────────────────────
Write-Header "Итог"

$confDate = if (Test-Path $FinalConf) { (Get-Item $FinalConf).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "?" }
Write-Dim "warp-ru.conf последний раз изменён: $confDate"

$lastRunFile = "$ConfDir\ru-last-run.txt"
if (Test-Path $lastRunFile) {
    Write-Dim "Последний успешный запуск скрипта: $(Get-Content $lastRunFile)"
}

$syncStatus = if ($onlyInConf.Count -eq 0 -and $onlyActive.Count -eq 0) {
    "SYNC OK — конфиг соответствует активным маршрутам"
} elseif ($onlyInConf.Count -gt 0 -or $onlyActive.Count -gt 0) {
    "SYNC MISMATCH — расхождение $($onlyInConf.Count + $onlyActive.Count) блоков"
} else { "?" }

Write-Host ""
Write-Host "  $syncStatus" -ForegroundColor $(if ($syncStatus -match "OK") { "Green" } else { "Yellow" })
Write-Host ""

pause

:PS_END:
