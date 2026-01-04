# setup_adb.ps1
# ADB setup script for light version - downloads and installs ADB if not present

$BaseDir = Split-Path $PSScriptRoot -Parent
$AdbDir = Join-Path $BaseDir 'adb'
$AdbExe = Join-Path $AdbDir 'adb.exe'

if (Test-Path $AdbExe) {
    Write-Host "ADB is already installed at $AdbExe"
    exit 0
}

Write-Host "ADB not found. Downloading and installing ADB..."

try {
    # Create ADB directory
    if (-not (Test-Path $AdbDir)) {
        New-Item -ItemType Directory -Path $AdbDir | Out-Null
    }

    # Download platform-tools
    $url = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
    $zipPath = Join-Path $BaseDir 'platform-tools.zip'

    Write-Host "Downloading ADB from $url..."
    Invoke-WebRequest -Uri $url -OutFile $zipPath

    # Extract
    Write-Host "Extracting ADB..."
    Expand-Archive -Path $zipPath -DestinationPath $BaseDir -Force

    # Move platform-tools to adb
    $platformToolsDir = Join-Path $BaseDir 'platform-tools'
    if (Test-Path $platformToolsDir) {
        Move-Item -Path "$platformToolsDir\*" -Destination $AdbDir -Force
        Remove-Item -Path $platformToolsDir -Recurse -Force
    }

    # Clean up
    Remove-Item -Path $zipPath -Force

    # Verify
    if (Test-Path $AdbExe) {
        Write-Host "ADB installed successfully at $AdbExe"
        exit 0
    } else {
        throw "ADB installation failed"
    }
}
catch {
    Write-Error "Failed to install ADB: $_"
    Write-Host "Please install ADB manually from https://developer.android.com/studio/releases/platform-tools"
    Read-Host "Press Enter after manual installation"
}