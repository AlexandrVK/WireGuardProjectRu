# ==============================
# uninstall.ps1
# Удаление WireGuard WARP-RU AutoStart
# ==============================

Add-Type -AssemblyName System.Windows.Forms

# Подтверждение
# Защита от запуска второй копии
$mutex = New-Object System.Threading.Mutex($false, "Global\WireGuardWarpRU_Uninstall")
if (-not $mutex.WaitOne(0)) {
    [System.Windows.Forms.MessageBox]::Show("Другая копия скрипта уже выполняется.", "Ошибка", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    exit
}

$confirm = [System.Windows.Forms.MessageBox]::Show(
    "Удалить WireGuard WARP-RU AutoStart?`n`nБудут удалены:`n- Туннель warp-ru (если активен)`n- Задача планировщика WireGuard-WARP-RU`n- WireGuard (программа)`n- Папка C:\WireGuardProject со всеми файлами",
    "Подтверждение удаления",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Warning,
    [System.Windows.Forms.MessageBoxDefaultButton]::Button2
)
if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
    Write-Host "Удаление отменено."
    pause
    exit 0
}

$TaskName     = "WireGuard-WARP-RU"
$TunnelName   = "warp-ru"
$ProjectDir   = "C:\WireGuardProject"
$WireGuardExe = "C:\Program Files\WireGuard\wireguard.exe"
$WgExe        = "C:\Program Files\WireGuard\wg.exe"

# ШАГ 1: Остановка туннеля через WireGuard если активен
Write-Host "Проверяем туннель $TunnelName..."
if (Test-Path $WgExe) {
    $wgOut = & $WgExe show $TunnelName 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Туннель активен — останавливаем..."
        Start-Process $WireGuardExe -ArgumentList "/uninstalltunnelservice $TunnelName" -WindowStyle Hidden -Wait
        # Ждём подтверждения от wg show
        for ($i = 1; $i -le 15; $i++) {
            Start-Sleep -Seconds 1
            $check = & $WgExe show $TunnelName 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Туннель остановлен (через $i сек)"
                break
            }
        }
    } else {
        Write-Host "Туннель не активен"
    }
} else {
    Write-Host "WireGuard не установлен — пропускаем остановку туннеля"
}

# ШАГ 2: Удаление задачи планировщика
Write-Host "Удаляем задачу планировщика $TaskName..."
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Задача удалена"
} else {
    Write-Host "Задача не найдена"
}

# ШАГ 3: Удаление WireGuard через MSI
Write-Host "Удаляем WireGuard..."
$wgReg = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" `
    | Where-Object { $_.DisplayName -like "*WireGuard*" } `
    | Select-Object -First 1
if ($wgReg -and $wgReg.UninstallString) {
    # UninstallString = "MsiExec.exe /X{GUID}" — запускаем тихо
    $msiArgs = $wgReg.UninstallString -replace "MsiExec.exe ", ""
    $msiArgs = "$msiArgs /quiet /norestart"
    Write-Host "Запускаем: MsiExec.exe $msiArgs"
    Start-Process "MsiExec.exe" -ArgumentList $msiArgs -Wait
    Write-Host "WireGuard удалён"
} else {
    Write-Host "WireGuard не найден в реестре — пропускаем"
}

# ШАГ 4: Удаление папки проекта
# Скрипт может запускаться из этой папки — копируем себя во TEMP и удаляем папку оттуда
Write-Host "Удаляем папку $ProjectDir..."
if (Test-Path $ProjectDir) {
    $tempScript = "$env:TEMP\warp-cleanup.ps1"
    $cleanupScript = @"
Start-Sleep -Seconds 2
Remove-Item -Path "$ProjectDir" -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path "$ProjectDir") {
    Write-Host "ПРЕДУПРЕЖДЕНИЕ: папка не удалилась полностью"
} else {
    Write-Host "Папка $ProjectDir удалена"
}
Remove-Item -Path "`$PSCommandPath" -Force -ErrorAction SilentlyContinue
"@
    $cleanupScript | Set-Content $tempScript -Encoding UTF8
    Start-Process "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList "-NonInteractive -ExecutionPolicy Bypass -File `"$tempScript`"" `
        -WindowStyle Hidden
    Write-Host "Папка будет удалена через 2 сек (отдельный процесс)"
} else {
    Write-Host "Папка не найдена"
}

Write-Host ""
Write-Host "Удаление завершено." -ForegroundColor Green
Write-Host "WireGuard и все файлы WARP-RU удалены."
pause
