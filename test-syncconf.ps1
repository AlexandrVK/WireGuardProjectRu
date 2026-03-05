# test-syncconf.ps1
# Тест: принудительное обновление конфига через wg syncconf
# Извлекает AllowedIPs из warp-base.conf и применяет их к работающему туннелю
# Используется для проверки что syncconf реально срабатывает

$ProjectDir = "C:\WireGuardProject"
$BaseConf   = "$ProjectDir\warp-base.conf"
$FinalConf  = "$ProjectDir\warp-ru.conf"
$PeerConf   = "$ProjectDir\warp-peer.conf"
$LogFile    = "$ProjectDir\warp.log"
$TunnelName = "warp-ru"
$WgExe      = "C:\Program Files\WireGuard\wg.exe"

function Write-Log {
    param([string]$Text)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Text"
    Write-Host $line
    Add-Content $LogFile $line -ErrorAction SilentlyContinue
}

Write-Log "=== ТЕСТ syncconf: применяем AllowedIPs из warp-base.conf ==="

# Проверяем что туннель запущен
$wgShowOut = & $WgExe show $TunnelName 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Log "ОШИБКА: туннель $TunnelName не запущен — тест невозможен"
    Write-Log "wg show: $wgShowOut"
    pause
    exit
}
Write-Log "Туннель запущен — OK"
Write-Log "Текущий статус:"
$wgShowOut | ForEach-Object { Write-Log "  $_" }

# Читаем AllowedIPs из warp-base.conf
Write-Log "Читаем AllowedIPs из $BaseConf..."
$inPeer = $false
$BaseAllowedIPs = $null
foreach ($line in (Get-Content $BaseConf)) {
    $t = $line.Trim()
    if ($t -eq "[Peer]") { $inPeer = $true; continue }
    if ($t -match "^\[") { $inPeer = $false }
    if ($inPeer -and $t -match "^AllowedIPs\s*=\s*(.+)$") {
        $BaseAllowedIPs = $Matches[1].Trim()
        break
    }
}

if (-not $BaseAllowedIPs) {
    Write-Log "ОШИБКА: AllowedIPs не найден в $BaseConf"
    pause
    exit
}
Write-Log "AllowedIPs из base: $BaseAllowedIPs"

# Читаем AllowedIPs из текущего warp-ru.conf (должен быть большой список)
Write-Log "Читаем текущий AllowedIPs из $FinalConf..."
$inPeer = $false
$CurrentAllowedIPs = $null
foreach ($line in (Get-Content $FinalConf)) {
    $t = $line.Trim()
    if ($t -eq "[Peer]") { $inPeer = $true; continue }
    if ($t -match "^\[") { $inPeer = $false }
    if ($inPeer -and $t -match "^AllowedIPs\s*=\s*(.+)$") {
        $CurrentAllowedIPs = $Matches[1].Trim()
        break
    }
}
$currentCount = ($CurrentAllowedIPs -split ",").Count
Write-Log "Текущий AllowedIPs: $currentCount блоков"

# Формируем тестовый peer-конфиг с AllowedIPs из base (маленький список)
Write-Log "Формируем тестовый peer-конфиг..."
$inPeer = $false
$peerLines = @()
foreach ($line in (Get-Content $FinalConf)) {
    if ($line.Trim() -eq "[Peer]") { $inPeer = $true }
    if ($inPeer) {
        if ($line.Trim() -match "^AllowedIPs") {
            $peerLines += "AllowedIPs = $BaseAllowedIPs"
        } else {
            $peerLines += $line
        }
    }
}
$peerLines | Set-Content $PeerConf -Encoding ASCII
Write-Log "Peer-конфиг записан ($($peerLines.Count) строк):"
$peerLines | ForEach-Object { Write-Log "  $_" }

# Применяем через syncconf
Write-Log "Применяем wg syncconf $TunnelName $PeerConf ..."
$result = & $WgExe syncconf $TunnelName "$PeerConf" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Log "ОШИБКА syncconf: $result"
    pause
    exit
}
Write-Log "syncconf выполнен — OK"

# Проверяем результат через wg show
Start-Sleep -Seconds 1
Write-Log "Проверяем wg show после syncconf:"
$wgShowAfter = & $WgExe show $TunnelName 2>&1
$wgShowAfter | ForEach-Object { Write-Log "  $_" }

Write-Log "=== ТЕСТ ЗАВЕРШЁН — AllowedIPs заменён на базовый список из warp-base.conf ==="
Write-Log "ВНИМАНИЕ: запустите Update-Warp-RU.ps1 чтобы восстановить полный RU список"
Write-Host ""
Write-Host "Нажмите любую клавишу для выхода..."
pause
