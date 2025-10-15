# Set output encoding to UTF-8 to properly display Cyrillic characters in the console.
$OutputEncoding = [System.Text.Encoding]::UTF8

<#
.SYNOPSIS
    Main script to manage Android applications on a connected device.
.DESCRIPTION
    This script provides an interactive menu to install, uninstall, and run applications.
    It first checks for all required dependencies and runs setup scripts if needed.
    It then processes local APK/XAPK files to prepare them for installation.
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# --- Configuration ---
# The script is now in the 'scripts' dir, so the base dir is one level up.
$BaseDir = Split-Path $PSScriptRoot -Parent
$ScriptsDir = $PSScriptRoot	# This script is now inside the scripts dir
$AppsDir = Join-Path $BaseDir '_APPS_'

$AdbPath = Join-Path (Join-Path $BaseDir 'adb') 'adb.exe'

# --- Initial Checks ---

function Check-Environment {
    Write-Host "--- Checking environment ---"
    $adbOk = Test-Path $AdbPath
    if ($adbOk) {
        Write-Host "Environment is OK."
        return
    }

    Write-Host "One or more dependencies are missing. Running setup script..."
    try {
        $setupScript = (Join-Path $ScriptsDir 'setup_light.ps1')
        Start-Process -WorkingDirectory $BaseDir -FilePath powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$setupScript`"" -NoNewWindow -Wait
    }
    catch {

        Write-Error "Environment setup failed. Please run '$ScriptsDirs\setup_light.ps1' manually and resolve any errors."
        exit 1
    }
}

# --- Menu Functions ---

function Show-Menu($title, $options) {
    $selection = 0
    $key = $null
    
    # Скрываем курсор для лучшего визуального эффекта
    $originalCursorSize = [Console]::CursorSize
    [Console]::CursorVisible = $false
    
    try {
        # Первоначальная отрисовка
        Clear-Host
        Write-Host "$title`n" -ForegroundColor Cyan
        
        for ($i = 0; $i -lt $options.Count; $i++) {
            if ($i -eq $selection) {
                Write-Host " > $($options[$i])" -ForegroundColor Black -BackgroundColor White
            }
            else {
                Write-Host "   $($options[$i])" -ForegroundColor White
            }
        }
        Write-Host "`nUse arrow keys to navigate, Enter to select, Esc to go back/exit." -ForegroundColor DarkGray

        do {
            $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            $oldSelection = $selection

            switch ($key.VirtualKeyCode) {
                38 { if ($selection -gt 0) { $selection-- } } # Up
                40 { if ($selection -lt ($options.Count - 1)) { $selection++ } } # Down
            }

            # Перерисовываем только если выбор изменился
            if ($oldSelection -ne $selection) {
                # Обновляем старый пункт
                [Console]::SetCursorPosition(0, 2 + $oldSelection)
                Write-Host "   $($options[$oldSelection])" -ForegroundColor White
                
                # Обновляем новый пункт
                [Console]::SetCursorPosition(0, 2 + $selection)
                Write-Host " > $($options[$selection])" -ForegroundColor Black -BackgroundColor White
                
                # Возвращаем курсор в исходное положение
                [Console]::SetCursorPosition(0, 2 + $options.Count + 2)
            }

        } while ($key.VirtualKeyCode -ne 13 -and $key.VirtualKeyCode -ne 27)

        if ($key.VirtualKeyCode -eq 27) { return -1 } else { return $selection } 
    }
    finally {
        # Восстанавливаем видимость курсора
        [Console]::CursorVisible = $true
        [Console]::CursorSize = $originalCursorSize
    }
}
# --- Action Functions ---

function Test-AdbConnection {
    Write-Host "Checking for connected ADB devices..."
    $deviceOutput = & $AdbPath devices
    $connected = $deviceOutput | Select-Object -Skip 1 | Where-Object { $_ -match '.+\s+device' }
    if ($connected) {
        Write-Host "Device found."
        return $true
    }
    else {
        Write-Host "No ADB device found. Please connect a device and ensure USB debugging is enabled." -ForegroundColor Red
        pause
        return $false
    }
}

function Invoke-Install($app) {
    if (-not (Test-AdbConnection)) { return }
    $appDir = Join-Path $AppsDir $app.PackageName
    $scriptPath = Join-Path $appDir 'install.bat'
    if (-not (Test-Path $scriptPath)) { Write-Error "Install script not found!"; pause; return }
    Start-Process -FilePath cmd.exe -ArgumentList "/c `"$scriptPath`"" -WorkingDirectory $appDir -Wait
}

function Invoke-Uninstall($app) {
    if (-not (Test-AdbConnection)) { return }
    $confirmation = Read-Host "Are you sure you want to uninstall $($app.AppName)? (y/n)"
    if ($confirmation -ne 'y') { Write-Host "Uninstall cancelled."; return }

    $appDir = Join-Path $AppsDir $app.PackageName
    $scriptPath = Join-Path $appDir 'uninstall.bat'
    if (-not (Test-Path $scriptPath)) { Write-Error "Uninstall script not found!"; pause; return }
    Start-Process -FilePath cmd.exe -ArgumentList "/c `"$scriptPath`"" -WorkingDirectory $appDir -Wait
}

function Invoke-Run($app) {    
    if (-not (Test-AdbConnection)) { return }
    $appDir = Join-Path $AppsDir $app.PackageName
    $scriptPath = Join-Path $appDir 'run.bat'
    if (-not (Test-Path $scriptPath)) { Write-Error "Uninstall script not found!"; pause; return }
    Start-Process -FilePath cmd.exe -ArgumentList "/c `"$scriptPath`"" -WorkingDirectory $appDir -Wait
}

# --- Main Execution ---

Check-Environment

$appLabelFile = Join-Path $AppsDir 'apps_label.txt'
if (-not (Test-Path $appLabelFile)) {
    Write-Error "apps_label.txt not found after sync. No apps to manage."
    exit 1
}

$apps = @(Get-Content $appLabelFile -Encoding UTF8 | ForEach-Object {
        $parts = $_.Split(';')
        if ($parts.Length -ge 3) {
            [PSCustomObject]@{
                AppName      = $parts[0]
                AppVersion   = $parts[1]
                PackageName  = $parts[2]
                DisplayLabel = "$($parts[0]) (v$($parts[1]))"
            }
        }
    })

if ($apps.Count -eq 0) {
    Write-Host "No applications found to manage."
    exit 0
}

# Main Menu Loop
while ($true) {
    $appNames = @($apps.DisplayLabel) + "Exit"
    $selection = Show-Menu -title "Select an Application" -options $appNames
    $selection
    if ($selection -eq -1 -or $selection -eq ($appNames.Count - 1)) {
        # Esc or Exit
        break
    }

    $selectedApp = $apps[$selection]
    
    # Action Menu Loop
    while ($true) {
        $launchActivityFile = Join-Path (Join-Path $AppsDir $selectedApp.PackageName) 'run.bat'
        $hasLaunchActivity = Test-Path $launchActivityFile

        $actionOptions = @("Install", "Uninstall")
        if ($hasLaunchActivity) {
            $actionOptions += "Open/Run"
        }
        $actionOptions += "Back to Main Menu"

        $actionSelection = Show-Menu -title "$($selectedApp.AppName) - Select Action" -options $actionOptions

        if ($actionSelection -eq -1 -or $actionOptions[$actionSelection] -eq "Back to Main Menu") {
            # Esc or Back
            break
        }

        $selectedAction = $actionOptions[$actionSelection]

        switch ($selectedAction) {
            "Install" { Invoke-Install -app $selectedApp }
            "Uninstall" { Invoke-Uninstall -app $selectedApp }
            "Open/Run" { Invoke-Run -app $selectedApp }
        }
    }
}

Write-Host "Exiting."
