# test-tunnel-status.ps1
$ServiceName  = 'WireGuardTunnel$warp-ru'
$TunnelName   = "warp-ru"
$WireGuardExe = "$env:ProgramW6432\WireGuard\wireguard.exe"
$WgExe        = "$env:ProgramW6432\WireGuard\wg.exe"
$LogFile      = "C:\WireGuardProject\tunnel-test.log"

function Write-Log {
    param([string]$Text)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Text"
    Write-Host $line
    Add-Content $LogFile $line -ErrorAction SilentlyContinue
}

Write-Log "=== ТЕСТ ОПРЕДЕЛЕНИЯ СТАТУСА ТУННЕЛЯ ==="

# --- 1. Все службы WireGuard ---
$allWG = Get-Service | Where-Object { $_.Name -like "WireGuardTunnel*" }
if ($allWG) {
    foreach ($s in $allWG) {
        Write-Log "Найдена служба: Name='$($s.Name)' Status='$($s.Status)' DisplayName='$($s.DisplayName)'"
    }
} else {
    Write-Log "Служб WireGuardTunnel* не найдено"
}

# --- 2. Конкретная служба по ПРАВИЛЬНОМУ имени (одинарные кавычки!) ---
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
Write-Log "Get-Service '$ServiceName': $(if ($svc) { "найдена, Status=$($svc.Status)" } else { "НЕ НАЙДЕНА" })"

# --- 3. Через sc.exe с правильным именем ---
$scOut = sc.exe query "WireGuardTunnel`$warp-ru" 2>&1
Write-Log "sc.exe query: $($scOut -join ' | ')"

# --- 4. WMI с правильным именем ---
$wmi = Get-WmiObject Win32_Service -Filter "Name='WireGuardTunnel`$warp-ru'" -ErrorAction SilentlyContinue
Write-Log "WMI Win32_Service: $(if ($wmi) { "найдена, State=$($wmi.State) Status=$($wmi.Status)" } else { "НЕ НАЙДЕНА" })"

# --- 4b. dpapi файл ---
Write-Log "env:ProgramFiles = $env:ProgramFiles"
Write-Log "env:ProgramW6432 = $env:ProgramW6432"
Write-Log "hardcoded path exists: $(Test-Path 'C:\Program Files\WireGuard\Data\Configurations\warp-ru.conf.dpapi')"
$DpapiFile = "$env:ProgramW6432\WireGuard\Data\Configurations\warp-ru.conf.dpapi"
Write-Log "dpapi файл ($DpapiFile): $(Test-Path $DpapiFile)"
$DpapiDir = "$env:ProgramFiles\WireGuard\Data\Configurations"
if (Test-Path $DpapiDir) {
    $files = Get-ChildItem $DpapiDir -ErrorAction SilentlyContinue
    Write-Log "Файлы в Configurations: $(if ($files) { ($files | ForEach-Object { $_.Name }) -join ', ' } else { '(пусто)' })"
} else {
    Write-Log "Папка Configurations не существует"
}

# --- 5. wg show ---
$wgShow = & $WgExe show 2>&1
Write-Log "wg show (все): $($wgShow -join ' | ')"

$wgShowTunnel = & $WgExe show $TunnelName 2>&1
Write-Log "wg show $TunnelName : $($wgShowTunnel -join ' | ')"

# --- 6. wireguard /dumplog последние 5 строк ---
$dump = & $WireGuardExe /dumplog 2>&1 | Select-Object -Last 5
Write-Log "wireguard /dumplog (last 5): $($dump -join ' | ')"

Write-Log "=== ТЕСТ ЗАВЕРШЁН ==="
