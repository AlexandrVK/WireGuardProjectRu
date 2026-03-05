# ==============================
# install.ps1
# ==============================

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms


# ==============================
# Определение папки скрипта
# ==============================

if ($PSScriptRoot -and (Test-Path $PSScriptRoot)) {
    $ScriptDir = $PSScriptRoot
} else {
    $ScriptDir = Split-Path -Parent ([System.IO.Path]::GetFullPath($MyInvocation.MyCommand.Path))
}

# ==============================
# Конфигурация
# ==============================

$TaskName           = "WireGuard-WARP-RU"
$BaseDir            = "C:\WireGuardProject"
$LogFile            = "$BaseDir\install.log"
$WireGuardExe       = "C:\Program Files\WireGuard\wireguard.exe"
$WireGuardInstaller = "$BaseDir\wireguard-installer.msi"
$WgcfExe            = "$BaseDir\wgcf.exe"
$BaseConf           = "$BaseDir\warp-base.conf"
$ScriptDest         = "$BaseDir\Update-Warp-RU.ps1"
# Определяем архитектуру для выбора правильного MSI
$arch = (Get-WmiObject Win32_OperatingSystem).OSArchitecture
if ($arch -like "*ARM*") {
    $WGUrl = "https://download.wireguard.com/windows-client/wireguard-arm64-0.5.3.msi"
} elseif ([Environment]::Is64BitOperatingSystem) {
    $WGUrl = "https://download.wireguard.com/windows-client/wireguard-amd64-0.5.3.msi"
} else {
    $WGUrl = "https://download.wireguard.com/windows-client/wireguard-x86-0.5.3.msi"
}
$WgcfApiUrl         = "https://api.github.com/repos/ViRb3/wgcf/releases/latest"

# ==============================
# Логирование
# ==============================

function Write-Log {
    param([string]$Text, [string]$Level = "INFO")
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Text"
    Write-Host $line
    Add-Content $LogFile $line -ErrorAction SilentlyContinue
}

Write-Log "=== Начало установки ==="
Write-Log "Папка скриптов: $ScriptDir"

# ==============================
# Создание рабочей папки
# ==============================

New-Item -ItemType Directory -Force -Path $BaseDir | Out-Null
Write-Log "Рабочая папка: $BaseDir"

# ==============================
# Установка WireGuard
# ==============================

if (-not (Test-Path $WireGuardExe)) {
    Write-Log "WireGuard не найден. Загружаем установщик..."

    if (-not (Test-Path $WireGuardInstaller)) {
        Write-Log "Скачивание: $WGUrl"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $dlOk = $false
        try {
            (New-Object Net.WebClient).DownloadFile($WGUrl, $WireGuardInstaller)
            $dlOk = $true
        } catch {}
        if (-not $dlOk -or -not (Test-Path $WireGuardInstaller)) {
            Write-Log "Ошибка загрузки WireGuard" "ERROR"
            [System.Windows.Forms.MessageBox]::Show(
                "Не удалось скачать WireGuard.`nСкачайте вручную: https://www.wireguard.com/install/`nи положите в $WireGuardInstaller",
                "Ошибка загрузки",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            pause
            exit 1
        }
        Write-Log "Установщик загружен"
    } else {
        Write-Log "Установщик уже есть в папке"
    }

    # Тихая установка через msiexec — без диалогов, без перезагрузки
    Write-Log "Тихая установка WireGuard (msiexec /quiet)..."
    $msi = Start-Process "msiexec.exe" -ArgumentList "/i `"$WireGuardInstaller`" /quiet /norestart DO_NOT_LAUNCH=1" -Wait -PassThru -Verb RunAs
    Write-Log "msiexec завершён (код: $($msi.ExitCode))"

    if (-not (Test-Path $WireGuardExe)) {
        Write-Log "WireGuard не установлен после msiexec (код: $($msi.ExitCode))" "ERROR"
        [System.Windows.Forms.MessageBox]::Show(
            "WireGuard не установился (код: $($msi.ExitCode)).`nПопробуйте установить вручную: https://www.wireguard.com/install/",
            "Ошибка установки",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        pause
        exit 1
    }
    Write-Log "WireGuard успешно установлен"
    Remove-Item $WireGuardInstaller -Force -ErrorAction SilentlyContinue
    Write-Log "wireguard-installer.msi удалён"
} else {
    Write-Log "WireGuard уже установлен"
}

# ==============================
# Загрузка wgcf и генерация конфига WARP
# ==============================

if (Test-Path $BaseConf) {
    Write-Log "Конфиг уже существует: $BaseConf — пропускаем"
} else {
    # Скачиваем wgcf если нет
    if (-not (Test-Path $WgcfExe)) {
        Write-Log "Получение ссылки на wgcf через GitHub API..."
        $WgcfUrl = $null
        try {
            $release = Invoke-RestMethod -Uri $WgcfApiUrl -Headers @{"User-Agent"="WireGuardProject"} -ErrorAction Stop
            $asset = $release.assets | Where-Object { $_.name -like "*windows_amd64*" } | Select-Object -First 1
            if ($asset) { $WgcfUrl = $asset.browser_download_url }
        } catch {}

        if (-not $WgcfUrl) {
            Write-Log "API недоступен, резервная ссылка v2.2.30" "WARN"
            $WgcfUrl = "https://github.com/ViRb3/wgcf/releases/download/v2.2.30/wgcf_2.2.30_windows_amd64.exe"
        }
        Write-Log "Скачивание wgcf: $WgcfUrl"

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $dlOk2 = $false
        try {
            (New-Object Net.WebClient).DownloadFile($WgcfUrl, $WgcfExe)
            $dlOk2 = $true
        } catch {}
        if (-not $dlOk2 -or -not (Test-Path $WgcfExe)) {
            Write-Log "Ошибка загрузки wgcf" "ERROR"
            [System.Windows.Forms.MessageBox]::Show(
                "Не удалось скачать wgcf.`nСкачайте вручную: https://github.com/ViRb3/wgcf/releases`nФайл переименуйте в wgcf.exe и положите в $BaseDir",
                "Ошибка загрузки wgcf",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            pause
            exit 1
        }
        Write-Log "wgcf загружен"
    } else {
        Write-Log "wgcf уже существует"
    }

    # Регистрация и генерация конфига
    Write-Log "Регистрация в Cloudflare WARP (wgcf register)..."
    Push-Location $BaseDir

    $savedPref = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"

    cmd /c "`"$WgcfExe`" register --accept-tos > `"$BaseDir\wgcf-register.log`" 2>&1"
    Write-Log "wgcf register завершён (код: $LASTEXITCODE)"

    Write-Log "Генерация конфига (wgcf generate)..."
    cmd /c "`"$WgcfExe`" generate > `"$BaseDir\wgcf-generate.log`" 2>&1"
    Write-Log "wgcf generate завершён (код: $LASTEXITCODE)"

    $ErrorActionPreference = $savedPref
    Pop-Location

    $ProfileConf = "$BaseDir\wgcf-profile.conf"
    if (Test-Path $ProfileConf) {
        Move-Item $ProfileConf $BaseConf -Force
        Write-Log "Конфиг создан: $BaseConf"
    } else {
        $regLog = if (Test-Path "$BaseDir\wgcf-register.log") { Get-Content "$BaseDir\wgcf-register.log" -Raw } else { "(пусто)" }
        Write-Log "wgcf-profile.conf не найден. Лог регистрации: $regLog" "ERROR"
        [System.Windows.Forms.MessageBox]::Show(
            "Ошибка генерации конфига WARP.`nПроверьте интернет и повторите запуск.`n`nЛог: $BaseDir\wgcf-register.log",
            "Ошибка генерации конфига",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        pause
        exit 1
    }
}

# ==============================
# Копирование файлов в рабочую папку
# ==============================

# Все файлы проекта — копируем из папки запуска в C:\WireGuardProject\
# Если запуск уже из C:\WireGuardProject\ — пропускаем (нельзя копировать файл сам в себя)
$FilesToCopy = @(
    "install.ps1",
    "install.cmd",
    "uninstall.ps1",
    "uninstall.cmd",
    "Update-Warp-RU.ps1",
    "run-update.cmd",
    "test-tunnel-status.ps1",
    "test-syncconf.ps1",
    "sources.txt"
)

$SameDirMsg = $false
foreach ($file in $FilesToCopy) {
    $src = Join-Path $ScriptDir $file
    $dst = Join-Path $BaseDir $file
    if (-not (Test-Path $src)) {
        Write-Log "$file — не найден рядом, пропускаем" "WARN"
        continue
    }
    $srcRes = (Resolve-Path $src).Path
    $dstRes = (Resolve-Path $dst -ErrorAction SilentlyContinue).Path
    if ($srcRes -eq $dstRes) {
        if (-not $SameDirMsg) {
            Write-Log "Запуск из рабочей папки — копирование файлов не требуется"
            $SameDirMsg = $true
        }
        continue
    }
    Copy-Item $src $dst -Force
    Write-Log "Скопирован: $file"
}

# Скрываем папку проекта — файлы конфиденциальные (ключи WARP)
(Get-Item $BaseDir).Attributes = "Hidden"
Write-Log "Папка $BaseDir скрыта"

# ==============================
# Регистрация задачи планировщика
# ==============================

# Планировщик задач всегда 64-битный, поэтому используем System32 напрямую.
# Sysnative здесь нельзя — он виртуальный алиас только для 32-битных процессов,
# планировщик его не видит и выдаёт ошибку 0x80070002.
$PS64 = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

# Регистрируем через XML и schtasks.exe — единственный способ добавить EventTrigger надёжно.
# Единственный триггер: EventID 10000 (NetworkProfile) — сеть стала доступна, задержка 5 сек.
# Логика "раз в сутки" реализована внутри скрипта через файл ru-last-run.txt.
$TaskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Запуск WireGuard WARP-RU при подключении к сети (раз в сутки)</Description>
  </RegistrationInfo>
  <Triggers>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational"&gt;&lt;Select Path="Microsoft-Windows-NetworkProfile/Operational"&gt;*[System[EventID=10000]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
      <Delay>PT5S</Delay>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <ExecutionTimeLimit>PT1H</ExecutionTimeLimit>
    <RestartOnFailure>
      <Interval>PT5M</Interval>
      <Count>3</Count>
    </RestartOnFailure>
    <StartWhenAvailable>true</StartWhenAvailable>
  </Settings>
  <Actions>
    <Exec>
      <Command>$PS64</Command>
      <Arguments>-NonInteractive -ExecutionPolicy Bypass -File "$ScriptDest"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

$TmpXml = "$env:TEMP\warp-task.xml"
$TaskXml | Set-Content $TmpXml -Encoding Unicode
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
$schtResult = & schtasks.exe /Create /TN $TaskName /XML $TmpXml /F 2>&1
Remove-Item $TmpXml -Force -ErrorAction SilentlyContinue
if ($LASTEXITCODE -ne 0) {
    Write-Log "ОШИБКА регистрации задачи: $schtResult" "ERROR"
    [System.Windows.Forms.MessageBox]::Show(
        "Не удалось зарегистрировать задачу планировщика.`n$schtResult",
        "Ошибка", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    pause; exit 1
}
Write-Log "Задача '$TaskName' зарегистрирована (триггер: сеть EventID=10000, логика раз в сутки — внутри скрипта)"
# Удаляем wgcf.exe если вдруг остался (например при повторном запуске когда конфиг уже был)
if (Test-Path $WgcfExe) {
    Remove-Item $WgcfExe -Force -ErrorAction SilentlyContinue
    Write-Log "wgcf.exe удалён"
}

Write-Log "=== Установка завершена ==="

# Запускаем основной скрипт сразу после установки:
# обновит sources.txt, скачает RU список, установит и запустит туннель
Write-Log "Запускаем Update-Warp-RU.ps1 для первоначальной настройки..."
$updateScript = "C:\WireGuardProject\Update-Warp-RU.ps1"
Remove-Item "C:\WireGuardProject\ru-last-run.txt" -Force -ErrorAction SilentlyContinue
Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$updateScript`"" `
    -Wait -WindowStyle Normal

[System.Windows.Forms.MessageBox]::Show(
    "Установка завершена успешно!`n`nТуннель warp-ru установлен и запущен.`nПри каждом старте Windows скрипт автоматически обновляет список RU IP и поддерживает туннель активным.`n`nДля принудительного обновления запустите:`nC:\WireGuardProject\run-update.cmd",
    "Установка завершена",
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
) | Out-Null