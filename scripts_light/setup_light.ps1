$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseDir = (Get-Item (Join-Path $ScriptDir '..')).FullName
$AdbDir = Join-Path $BaseDir 'adb'
$AdbExe = Join-Path $AdbDir 'adb.exe'

if (Test-Path $AdbExe) {
    Write-Host "adb find: $AdbExe"
    return
}

$tempZip = Join-Path $env:TEMP ("platform-tools_{0}.zip" -f ([Guid]::NewGuid()))
$downloadUrl = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'

Write-Host "Download platform-tools (ADB) from: $downloadUrl"
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -UseBasicParsing -ErrorAction Stop
}
catch {
    Write-Error "Error downloading platform-tools: $_"
    return
}

try {
    
    $extractDir = Join-Path $env:TEMP ("pt_extract_{0}" -f ([Guid]::NewGuid()))
    $extractDir
    if (-not (Test-Path $extractDir)) {
       New-Item -Type Directory -Path $extractDir | Out-Null
    }

    Write-Host "Unpack in: $extractDir"
    Expand-Archive -Path $tempZip -DestinationPath $extractDir -Force
    $extracted = Join-Path $extractDir 'platform-tools'
    if (-not (Test-Path $extracted)) {
        # иногда архив содержит сразу файлы
        $extracted = $extractDir
    }

    if (Test-Path $AdbDir) {
        Write-Host "Delete folder adb: $AdbDir"
        try { Remove-Item -LiteralPath $AdbDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }

    if (-not (Test-Path $AdbDir)) {
       New-Item -Type Directory -Path $AdbDir | Out-Null
    }

    Copy-Item -Path (Join-Path $extracted '*') -Destination $AdbDir -Recurse -Force
    Write-Host "ADB find: $AdbDir"
}
catch {
    Write-Error "Unpack/Copy Error: $_"
}
finally {
    if (Test-Path $tempZip) { Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue }
    if ($extractDir -and (Test-Path $extractDir)) { Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "Ready. Check adb: & `"$AdbExe`" devices"