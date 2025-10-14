# Короткий скрипт для установки только ADB (platform-tools)
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseDir = (Get-Item (Join-Path $ScriptDir '..')).FullName
$AdbDir = Join-Path $BaseDir 'adb'
$AdbExe = Join-Path $AdbDir 'adb.exe'

if (Test-Path $AdbExe) {
    Write-Host "adb уже установлен в: $AdbExe"
    return
}

$tempZip = Join-Path $env:TEMP ("platform-tools_{0}.zip" -f ([Guid]::NewGuid()))
$downloadUrl = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'

Write-Host "Скачиваю platform-tools (ADB) из: $downloadUrl"
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -UseBasicParsing -ErrorAction Stop
}
catch {
    Write-Error "Не удалось скачать platform-tools: $_"
    return
}

try {
    $extractDir = Join-Path $env:TEMP ("pt_extract_{0}" -f ([Guid]::NewGuid()))
    Ensure-DirectoryExists = { param($p) if (-not (Test-Path $p)) { New-Item -Path $p -ItemType Directory | Out-Null } }
    & { Ensure-DirectoryExists.Invoke($extractDir) }

    Write-Host "Распаковка в: $extractDir"
    Expand-Archive -Path $tempZip -DestinationPath $extractDir -Force

    $extracted = Join-Path $extractDir 'platform-tools'
    if (-not (Test-Path $extracted)) {
        # иногда архив содержит сразу файлы
        $extracted = $extractDir
    }

    if (Test-Path $AdbDir) {
        Write-Host "Удаляю предыдущую папку adb: $AdbDir"
        try { Remove-Item -LiteralPath $AdbDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }

    Copy-Item -Path (Join-Path $extracted '*') -Destination $AdbDir -Recurse -Force
    Write-Host "ADB установлен в: $AdbDir"
}
catch {
    Write-Error "Ошибка при распаковке/копировании: $_"
}
finally {
    if (Test-Path $tempZip) { Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue }
    if ($extractDir -and (Test-Path $extractDir)) { Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "Готово. Проверьте adb: & `"$AdbExe`" devices"