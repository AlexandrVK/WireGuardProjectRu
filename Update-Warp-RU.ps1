# ==============================
# Update-Warp-RU.ps1
# Автозапуск WireGuard WARP-RU при старте Windows
# ==============================

# ==============================
# Настройки
# ==============================

$BaseConf     = "C:\WireGuardProject\warp-base.conf"
$FinalConf    = "C:\WireGuardProject\warp-ru.conf"
$PeerConf     = "C:\WireGuardProject\warp-peer.conf"
$TempRU       = "C:\WireGuardProject\ru-new.txt"
$LastRU       = "C:\WireGuardProject\ru-last.txt"
$LogFile      = "C:\WireGuardProject\warp.log"
$MaxLogLines  = 200
$LastRunFile  = "C:\WireGuardProject\ru-last-run.txt"
$TestHost     = "1.1.1.1"
$TunnelName   = "warp-ru"
$ServiceName  = 'WireGuardTunnel$warp-ru'
$WGDir        = "C:\Program Files\WireGuard"
$ConfigsDir   = "$WGDir\Data\Configurations"
$DpapiFile    = "$ConfigsDir\warp-ru.conf.dpapi"
$WireGuardExe = "$WGDir\wireguard.exe"
$WgExe        = "$WGDir\wg.exe"

$SourcesFile      = "C:\WireGuardProject\sources.txt"
# URL будет задан после публикации проекта на GitHub
$SourcesGitHubURL = "https://raw.githubusercontent.com/AlexandrVK/WireGuardProjectRu/main/sources.txt"

# ==============================
# Инициализация
# ==============================

Add-Type -AssemblyName System.Windows.Forms

# ==============================
# Логирование
# ==============================

function Write-Log {
    param([string]$Text)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Text"
    Add-Content $LogFile $line -ErrorAction SilentlyContinue
    Write-Host $line
    $lines = Get-Content $LogFile -ErrorAction SilentlyContinue
    if ($lines -and $lines.Count -gt $MaxLogLines) {
        $lines[-$MaxLogLines..-1] | Set-Content $LogFile
    }
}

function Exit-Success {
    param([string]$Reason)
    Write-Log $Reason
    $today | Set-Content $LastRunFile -Encoding ASCII
    Write-Log "Дата запуска сохранена: $today"
    $mutex.ReleaseMutex()
    exit
}

function Show-Error {
    param([string]$Text)
    [System.Windows.Forms.MessageBox]::Show(
        $Text, "WARP ошибка",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

# ==============================
# ШАГ 1: Проверка предусловий
# ==============================

Write-Log "=== Запуск Update-Warp-RU ==="

# Защита от запуска второй копии через именованный мьютекс
$mutexName = "Global\WireGuardWarpRU"
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
$mutexAcquired = $mutex.WaitOne(0)
if (-not $mutexAcquired) {
    Write-Log "Другая копия скрипта уже выполняется — выходим"
    exit
}

# Проверка туннеля при каждом запуске — независимо от даты.
# Если туннель не запущен — запускаем немедленно без обновления баз.
# Обновление баз из интернета — только раз в сутки.
$today = (Get-Date).ToString("yyyy-MM-dd")

$_wgQuickCheck = & $WgExe show $TunnelName 2>&1
$_tunnelUp = ($LASTEXITCODE -eq 0 -and ($_wgQuickCheck -match "interface"))

if (Test-Path $LastRunFile) {
    $lastRun = (Get-Content $LastRunFile -ErrorAction SilentlyContinue).Trim()
    if ($lastRun -eq $today) {
        if ($_tunnelUp) {
            Write-Log "Скрипт уже выполнялся сегодня, туннель запущен — выходим"
            $mutex.ReleaseMutex()
            exit
        } else {
            Write-Log "Скрипт уже выполнялся сегодня, но туннель не запущен — восстанавливаем"
            # Пропускаем обновление баз, переходим сразу к запуску туннеля
            $SkipUpdate = $true
        }
    }
}

if (-not (Get-Variable SkipUpdate -ErrorAction SilentlyContinue)) { $SkipUpdate = $false }

if (-not (Test-Path $WireGuardExe)) {
    Write-Log "WireGuard не установлен: $WireGuardExe"
    Show-Error "WireGuard не установлен.`nЗапустите install.ps1 для первоначальной настройки."
    $mutex.ReleaseMutex()
    exit
}

if (-not (Test-Path $BaseConf)) {
    Write-Log "Базовый конфиг не найден: $BaseConf"
    Show-Error "Базовый конфиг не найден:`n$BaseConf`n`nЗапустите install.ps1 для первоначальной настройки."
    $mutex.ReleaseMutex()
    exit
}

# Проверяем WireGuardManager — без него не работает шифрование .conf в .dpapi
# и туннель не отображается в GUI
$mgr = Get-Service -Name "WireGuardManager" -ErrorAction SilentlyContinue
if (-not $mgr) {
    Write-Log "WireGuardManager не зарегистрирован — регистрируем..."
    Start-Process $WireGuardExe -ArgumentList "/installmanagerservice" -WindowStyle Hidden -Wait
    Start-Sleep -Seconds 2
    $mgr = Get-Service -Name "WireGuardManager" -ErrorAction SilentlyContinue
}
if ($mgr -and $mgr.Status -ne "Running") {
    Write-Log "WireGuardManager остановлен — запускаем..."
    Start-Service "WireGuardManager" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $mgr = Get-Service -Name "WireGuardManager" -ErrorAction SilentlyContinue
}
if (-not $mgr -or $mgr.Status -ne "Running") {
    Write-Log "ОШИБКА: WireGuardManager не запустился"
    Show-Error "Не удалось запустить службу WireGuard Manager.`nПопробуйте переустановить WireGuard."
    $mutex.ReleaseMutex()
    exit
}
Write-Log "WireGuardManager запущен — OK"

# Папка Data\Configurations нужна для хранения .dpapi
# Manager создаёт её сам при первом запуске, но на чистой установке может отсутствовать
if (-not (Test-Path $ConfigsDir)) {
    Write-Log "Папка $ConfigsDir не найдена — создаём..."
    New-Item -ItemType Directory -Path $ConfigsDir -Force | Out-Null
    Write-Log "Папка создана — OK"
}

Write-Log "Предусловия OK"

# Если туннель упал, а обновление баз уже было сегодня — сразу запускаем туннель
if ($SkipUpdate) {
    Write-Log "Режим восстановления: пропускаем обновление баз, запускаем туннель"
    $TunnelInstalled = (Test-Path $DpapiFile)
    $TunnelRunning   = $false
    if (-not $TunnelInstalled -and -not (Test-Path $FinalConf)) {
        Write-Log "ОШИБКА: нет ни dpapi ни warp-ru.conf — невозможно восстановить туннель без обновления"
        Show-Error "Туннель не установлен и конфиг отсутствует.`nЗапустите force.cmd для полного обновления."
        $mutex.ReleaseMutex()
        exit
    }
    # Используем функцию Install-Tunnel — она определена ниже, поэтому вызываем через ScriptBlock
    # Вместо этого дублируем минимальную логику запуска
    $ConfDest = "$ConfigsDir\warp-ru.conf"
    if (-not $TunnelInstalled) {
        Write-Log "Копируем конфиг и ждём dpapi..."
        Copy-Item $FinalConf $ConfDest -Force
        $encrypted = $false
        for ($i = 1; $i -le 30; $i++) {
            Start-Sleep -Seconds 1
            if ((Test-Path $DpapiFile) -and -not (Test-Path $ConfDest)) {
                Write-Log "Конфиг зашифрован (через $i сек) — OK"
                $encrypted = $true; break
            }
            Write-Log "Ожидание dpapi... $i/30"
        }
        if (-not $encrypted) {
            Show-Error "WireGuard Manager не обработал конфиг.`nПроверьте что служба WireGuardManager запущена."
            $mutex.ReleaseMutex(); exit
        }
    }
    Write-Log "Запускаем туннель..."
    Start-Process $WireGuardExe -ArgumentList "/installtunnelservice `"$FinalConf`"" -WindowStyle Hidden -Wait
    $restored = $false
    for ($i = 1; $i -le 30; $i++) {
        Start-Sleep -Seconds 1
        $chk = & $WgExe show $TunnelName 2>&1
        if ($LASTEXITCODE -eq 0 -and ($chk -match "interface")) {
            Write-Log "Туннель восстановлен (через $i сек) — OK"
            $restored = $true; break
        }
        Write-Log "Ожидание туннеля... $i/30"
    }
    if (-not $restored) {
        Show-Error "Туннель не запустился.`nПроверьте warp.log для деталей."
        $mutex.ReleaseMutex(); exit
    }
    # Дату не обновляем — полный цикл ещё не выполнялся
    $mutex.ReleaseMutex()
    exit
}

# ==============================
# ШАГ 2: Ожидание интернета
# ==============================

# Ждём интернет — без диалогов (запускается от SYSTEM, нет сессии пользователя)
# Таймаут 5 минут (300 сек), проверка каждые 5 сек
$internetWait = 0
while (-not (Test-Connection -ComputerName $TestHost -Count 1 -Quiet)) {
    if ($internetWait -ge 300) {
        Write-Log "Интернет не появился за 5 минут — выходим"
        $mutex.ReleaseMutex()
        exit
    }
    Write-Log "Нет интернета, ждём... ($internetWait сек)"
    Start-Sleep -Seconds 5
    $internetWait += 5
}

Write-Log "Интернет доступен"

# ==============================
# ШАГ 3: Синхронизация sources.txt с GitHub
# ==============================

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$wc = New-Object Net.WebClient
try {

Write-Log "Синхронизация sources.txt с GitHub..."
try {
    $TempSources = "$SourcesFile.tmp"
    $wc.DownloadFile($SourcesGitHubURL, $TempSources)
    if ((Test-Path $TempSources) -and (Get-Item $TempSources).Length -gt 10) {
        Move-Item $TempSources $SourcesFile -Force
        Write-Log "sources.txt обновлён с GitHub"
    } else {
        Remove-Item $TempSources -Force -ErrorAction SilentlyContinue
        Write-Log "sources.txt с GitHub пустой — используем локальный"
    }
} catch {
    Write-Log "Не удалось скачать sources.txt с GitHub: $_ — используем локальный"
}

if (-not (Test-Path $SourcesFile)) {
    Write-Log "ОШИБКА: sources.txt не найден"
    Show-Error "Файл sources.txt не найден:`n$SourcesFile`n`nСкачайте его с GitHub или создайте вручную."
    $mutex.ReleaseMutex()
    exit
}

$RU_List_URLs = Get-Content $SourcesFile |
    Where-Object { $_.Trim() -ne "" -and -not $_.TrimStart().StartsWith("#") }

if (-not $RU_List_URLs) {
    Write-Log "ОШИБКА: sources.txt не содержит ни одного URL"
    Show-Error "Файл sources.txt пуст или содержит только комментарии:`n$SourcesFile"
    $mutex.ReleaseMutex()
    exit
}

Write-Log "Источников в sources.txt: $($RU_List_URLs.Count)"

# ==============================
# ШАГ 4: Скачивание RU списка
# ==============================

$dlSuccess = $false

foreach ($url in $RU_List_URLs) {
    try {
        Write-Log "Скачивание RU списка: $url"
        $wc.DownloadFile($url, $TempRU)
        if ((Test-Path $TempRU) -and (Get-Item $TempRU).Length -gt 1000) {
            Write-Log "RU список скачан ($([Math]::Round((Get-Item $TempRU).Length/1KB)) КБ)"
            $dlSuccess = $true
            break
        }
    } catch {
        Write-Log "Недоступен: $url — $_"
    }
}

if (-not $dlSuccess) {
    Write-Log "Все источники RU списка недоступны"
    Remove-Item $TempRU -Force -ErrorAction SilentlyContinue
    Show-Error "Не удалось скачать RU список ни с одного источника.`nПроверьте sources.txt и интернет."
    $mutex.ReleaseMutex()
    exit
}
} finally {
    $wc.Dispose()
}

# ==============================
# ШАГ 5: Сравнение с предыдущим списком
# ==============================

$ListChanged = $true

if (Test-Path $LastRU) {
    if ((Get-FileHash $TempRU).Hash -eq (Get-FileHash $LastRU).Hash) {
        $ListChanged = $false
        Write-Log "RU список не изменился"
    } else {
        Write-Log "RU список изменился — требуется обновление конфига"
    }
} else {
    Write-Log "ru-last.txt не найден — первый запуск, формируем конфиг"
}

# ==============================
# ШАГ 6: Статус туннеля
# ==============================

# TunnelInstalled — наличие dpapi файла (туннель зарегистрирован в WireGuard)
$TunnelInstalled = (Test-Path $DpapiFile)

# TunnelRunning — прямой запрос к WireGuard: wg show вернёт exitcode=0 только если интерфейс активен
$wgShowOut = & $WgExe show $TunnelName 2>&1
$TunnelRunning = ($LASTEXITCODE -eq 0 -and ($wgShowOut -match "interface"))

Write-Log "Туннель установлен: $TunnelInstalled | Запущен: $TunnelRunning"
if ($TunnelRunning) { Write-Log "wg show: $($wgShowOut[0])" }

# ==============================
# Вспомогательные функции
# ==============================

function Build-Config {
    Write-Log "Генерация $FinalConf..."
    $RU_IPs = Get-Content $LastRU | Where-Object { $_ -match "^\d+\.\d+\.\d+\.\d+/\d+$" }
    $AllowedLine = "AllowedIPs = " + ($RU_IPs -join ", ")
    # Читаем warp-base.conf, вставляем AllowedIPs и PersistentKeepalive внутрь секции [Peer]
    $lines = Get-Content $BaseConf
    $out = @()
    $peerSeen = $false
    $peerDone = $false
    foreach ($line in $lines) {
        $t = $line.Trim()
        if ($t -eq "[Peer]") { $peerSeen = $true }
        # Пропускаем старые AllowedIPs и PersistentKeepalive
        if ($t -match "^AllowedIPs|^PersistentKeepalive") { continue }
        # Перед следующей секцией после [Peer] вставляем наши строки
        if ($peerSeen -and -not $peerDone -and $t -match "^\[" -and $t -ne "[Peer]") {
            $out += $AllowedLine
            $out += "PersistentKeepalive = 25"
            $peerDone = $true
        }
        $out += $line
    }
    # Если [Peer] последняя секция в файле
    if ($peerSeen -and -not $peerDone) {
        $out += $AllowedLine
        $out += "PersistentKeepalive = 25"
    }
    if (-not $RU_IPs -or $RU_IPs.Count -eq 0) {
        Write-Log "ОШИБКА: ru-last.txt не содержит корректных CIDR-блоков"
        Show-Error "Файл ru-last.txt пуст или повреждён.`nУдалите его и запустите скрипт повторно."
        $mutex.ReleaseMutex()
        exit
    }
    $out | Set-Content $FinalConf -Encoding ASCII
    Write-Log "Конфиг сгенерирован: $($RU_IPs.Count) блоков"
}

function Install-Tunnel {
    $ConfDest = "$ConfigsDir\warp-ru.conf"

    if ($TunnelInstalled) {
        # Туннель уже зарегистрирован — .dpapi существует.
        # Не трогаем папку Configurations, просто запускаем через /installtunnelservice
        Write-Log "  [1/2] Туннель уже установлен (dpapi есть) — пропускаем копирование конфига"
    } else {
        # Первая установка — копируем .conf, ждём шифрования Manager-ом
        Write-Log "  [1/2] Копируем конфиг в $ConfigsDir..."
        Copy-Item $FinalConf $ConfDest -Force
        Start-Sleep -Milliseconds 500

        Write-Log "  [1/2] Ждём шифрования конфига WireGuard Manager-ом..."
        $encrypted = $false
        for ($i = 1; $i -le 30; $i++) {
            Start-Sleep -Seconds 1
            $dpapiExists = Test-Path $DpapiFile
            $confExists  = Test-Path $ConfDest
            if ($dpapiExists -and -not $confExists) {
                Write-Log "  [1/2] Конфиг зашифрован (через $i сек) — OK"
                $encrypted = $true
                break
            }
            Write-Log "  [1/2] Ожидание... $i/30 (dpapi=$dpapiExists, conf=$confExists)"
        }
        if (-not $encrypted) {
            Write-Log "ОШИБКА: Manager не зашифровал конфиг за 30 сек"
            Show-Error "WireGuard Manager не обработал конфиг.`nПроверьте что служба WireGuardManager запущена."
            $mutex.ReleaseMutex()
            exit
        }
    }

    # Запускаем туннель и ждём подтверждения от wg show
    Write-Log "  [2/2] Команда /installtunnelservice..."
    Start-Process $WireGuardExe -ArgumentList "/installtunnelservice `"$FinalConf`"" -WindowStyle Hidden -Wait

    Write-Log "  [2/2] Ждём подтверждения от wg show..."
    $running = $false
    for ($i = 1; $i -le 30; $i++) {
        Start-Sleep -Seconds 1
        $wgCheck = & $WgExe show $TunnelName 2>&1
        if ($LASTEXITCODE -eq 0 -and ($wgCheck -match "interface")) {
            Write-Log "  [2/2] wg show: туннель активен (через $i сек) — OK"
            $running = $true
            break
        }
        Write-Log "  [2/2] Ожидание... $i/30"
    }
    if (-not $running) {
        Write-Log "ОШИБКА: туннель не появился в wg show за 30 сек"
        Show-Error "WireGuard туннель не запустился.`nПроверьте warp.log для деталей."
        $mutex.ReleaseMutex()
        exit
    }
}

# ==============================
# ШАГ 7: Основная логика
# ==============================

if (-not $ListChanged) {

    # --- Список не изменился ---
    Remove-Item $TempRU -Force -ErrorAction SilentlyContinue

    if ($TunnelRunning -and $TunnelInstalled) {
        Exit-Success "Туннель установлен, запущен, список актуален — выходим"
    }

    # Туннель не запущен или не установлен — запускаем/устанавливаем
    Write-Log "Туннель не запущен или не установлен — запускаем"
    if (-not (Test-Path $FinalConf)) { Build-Config }
    Install-Tunnel
    Exit-Success "Туннель запущен — OK"

} else {

    # --- Список изменился (или первый запуск) ---

    Copy-Item $TempRU $LastRU -Force
    Remove-Item $TempRU -Force -ErrorAction SilentlyContinue
    Write-Log "ru-last.txt обновлён"

    Build-Config

    if ($TunnelRunning -and $TunnelInstalled) {
        # Туннель установлен и работает — применяем новый конфиг без остановки через syncconf
        # syncconf принимает только секцию [Peer] — без [Interface]
        Write-Log "Туннель запущен — применяем через wg syncconf..."
        $peerLines = @()
        $inPeer = $false
        foreach ($line in (Get-Content $FinalConf)) {
            if ($line.Trim() -eq "[Peer]") { $inPeer = $true }
            if ($inPeer) { $peerLines += $line }
        }
        $peerLines | Set-Content $PeerConf -Encoding ASCII
        Write-Log "Peer-конфиг сформирован: $($peerLines.Count) строк"
        $result = & $WgExe syncconf $TunnelName "$PeerConf" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "ОШИБКА wg syncconf: $result"
            Show-Error "Не удалось применить новый конфиг через wg syncconf.`n$result"
            $mutex.ReleaseMutex()
            exit
        }
        Exit-Success "wg syncconf выполнен — OK"
    } else {
        # Туннель не запущен — устанавливаем с новым конфигом
        Write-Log "Туннель не запущен — устанавливаем с новым конфигом"
        Install-Tunnel
        Exit-Success "Туннель установлен и запущен с новым конфигом — OK"
    }
}
