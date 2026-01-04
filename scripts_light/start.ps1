# Set output encoding to UTF-8 to properly display Cyrillic characters in the console.
$OutputEncoding = [System.Text.Encoding]::UTF8

# Add assemblies for Windows Forms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

<#
.SYNOPSIS
    Light version: Main script to manage Android applications on a connected device.
.DESCRIPTION
    This script provides a graphical menu to install, uninstall, and run existing applications.
    It checks for ADB and provides GUI management without APK processing.
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# --- Configuration ---
$BaseDir = Split-Path $PSScriptRoot -Parent
$ScriptsDir = $PSScriptRoot
$AppsDir = Join-Path $BaseDir '_APPS_'
$AdbPath = Join-Path (Join-Path $BaseDir 'adb') 'adb.exe'

# --- Initial Checks ---

function Check-AdbEnvironment {
    Write-Host "--- Checking ADB environment ---"
    $adbOk = Test-Path $AdbPath

    if ($adbOk) {
        Write-Host "ADB is OK."
        return
    }

    Write-Host "ADB not found. Running ADB setup script..."
    try {
        & (Join-Path $ScriptsDir 'setup_adb.ps1')
    }
    catch {
        Write-Error "ADB setup failed. Please run 'scripts_light\setup_adb.ps1' manually and resolve any errors."
        exit 1
    }
}

# --- Menu Functions ---

function Show-Menu($title, $options) {
    $selection = 0
    $key = $null

    try {
        [Console]::CursorVisible = $false
    } catch {
        # ignore
    }

    try {
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

            if ($oldSelection -ne $selection) {
                try {
                    [Console]::SetCursorPosition(0, 2 + $oldSelection)
                } catch {
                    # ignore
                }
                Write-Host "   $($options[$oldSelection])" -ForegroundColor White

                try {
                    [Console]::SetCursorPosition(0, 2 + $selection)
                } catch {
                    # ignore
                }
                Write-Host " > $($options[$selection])" -ForegroundColor Black -BackgroundColor White

                try {
                    [Console]::SetCursorPosition(0, 2 + $options.Count + 2)
                } catch {
                    # ignore
                }
            }

        } while ($key.VirtualKeyCode -ne 13 -and $key.VirtualKeyCode -ne 27)

        if ($key.VirtualKeyCode -eq 27) { return -1 } else { return $selection }
    }
    finally {
        try {
            [Console]::CursorVisible = $true
        } catch {
            # ignore
        }
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
    if (-not (Test-Path $scriptPath)) { Write-Error "Run script not found!"; pause; return }
    Start-Process -FilePath cmd.exe -ArgumentList "/c `"$scriptPath`"" -WorkingDirectory $appDir -Wait
}

function DeleteFrom-Menu($app) {
    $confirmation = Read-Host "Are you sure you want to delete $($app.AppName) from the menu? (y/n)"
    if ($confirmation -ne 'y') { Write-Host "Deletion cancelled."; return }

    $appDir = Join-Path $AppsDir $app.PackageName
    try {
        Remove-Item -Path $appDir -Recurse -Force

        $appLabelFile = Join-Path $AppsDir 'apps_label.txt'
        if (-not (Test-Path $appLabelFile)) {
            Write-Error "apps_label.txt not found after deletion."
            exit 1
        }

        $apps = @(Get-Content $appLabelFile -Encoding UTF8 | Where-Object {
                $parts = $_.Split(';')
                $parts[2] -ne $app.PackageName
            })
        Set-Content -Path (Join-Path $AppsDir 'apps_label.txt') -Value $apps -Encoding UTF8

        Write-Host "$($app.AppName) has been deleted from the menu."
        return $true
    }
    catch {
        Write-Error "Failed to delete $($app.AppName): $_"
    }
    return $false
}

function Apps-Prepare() {
    $appLabelFile = Join-Path $AppsDir 'apps_label.txt'
    if (-not (Test-Path $appLabelFile)) {
        Write-Error "apps_label.txt not found. No apps to manage."
        exit 1
    }
    $temp = @()
    @(Get-Content $appLabelFile -Encoding UTF8 | ForEach-Object {
            $parts = $_.Split(';')
            if ($parts.Length -ge 3) {
                $temp += [PSCustomObject]@{
                    AppName      = $parts[0]
                    AppVersion   = $parts[1]
                    PackageName  = $parts[2]
                }
            }
    })

    $apps = @($temp | Where-Object {
        $appDir = Join-Path $AppsDir $_.PackageName
        $hasScripts = (Test-Path (Join-Path $appDir "install.bat")) -and
                      (Test-Path (Join-Path $appDir "run.bat")) -and
                      (Test-Path (Join-Path $appDir "uninstall.bat"))
        $hasApk = (Test-Path (Join-Path $appDir "app.apk")) -or
                  (Test-Path (Join-Path $appDir "app.xapk")) -or
                  (Test-Path (Join-Path $appDir "app.apks"))
        $result = $hasScripts -and $hasApk
        $result
    })

    if ($apps.Count -eq 0) {
        Write-Host "No applications found to manage."
        exit 0
    }

    return $apps
}

function Create-GUI($apps) {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Android App Manager (Light)"
    $form.Size = New-Object System.Drawing.Size(600, 500)
    $form.StartPosition = "CenterScreen"

    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.Location = New-Object System.Drawing.Point(10, 10)
    $listBox.Size = New-Object System.Drawing.Size(400, 350)
    $listBox.Font = New-Object System.Drawing.Font("Arial", 10)
    foreach ($app in $apps) {
        $listBox.Items.Add("$($app.AppName) (v$($app.AppVersion))") | Out-Null
    }
    $form.Controls.Add($listBox)

    $installButton = New-Object System.Windows.Forms.Button
    $installButton.Location = New-Object System.Drawing.Point(420, 10)
    $installButton.Size = New-Object System.Drawing.Size(150, 40)
    $installButton.Text = "Install"
    $installButton.Add_Click({
        if ($listBox.SelectedIndex -ge 0) {
            $selectedApp = $apps[$listBox.SelectedIndex]
            Invoke-InstallGUI -app $selectedApp
        } else {
            [System.Windows.Forms.MessageBox]::Show("Please select an application.", "Warning")
        }
    })
    $form.Controls.Add($installButton)

    $uninstallButton = New-Object System.Windows.Forms.Button
    $uninstallButton.Location = New-Object System.Drawing.Point(420, 60)
    $uninstallButton.Size = New-Object System.Drawing.Size(150, 40)
    $uninstallButton.Text = "Uninstall"
    $uninstallButton.Add_Click({
        if ($listBox.SelectedIndex -ge 0) {
            $selectedApp = $apps[$listBox.SelectedIndex]
            Invoke-UninstallGUI -app $selectedApp
        } else {
            [System.Windows.Forms.MessageBox]::Show("Please select an application.", "Warning")
        }
    })
    $form.Controls.Add($uninstallButton)

    $runButton = New-Object System.Windows.Forms.Button
    $runButton.Location = New-Object System.Drawing.Point(420, 110)
    $runButton.Size = New-Object System.Drawing.Size(150, 40)
    $runButton.Text = "Run"
    $runButton.Add_Click({
        if ($listBox.SelectedIndex -ge 0) {
            $selectedApp = $apps[$listBox.SelectedIndex]
            Invoke-RunGUI -app $selectedApp
        } else {
            [System.Windows.Forms.MessageBox]::Show("Please select an application.", "Warning")
        }
    })
    $form.Controls.Add($runButton)

    # Initially disable action buttons since no app is selected
    $installButton.Enabled = $false
    $uninstallButton.Enabled = $false
    $runButton.Enabled = $false

    # Add event handler for listBox selection change
    $listBox.Add_SelectedIndexChanged({
        $enabled = $this.SelectedIndex -ge 0
        $installButton.Enabled = $enabled
        $uninstallButton.Enabled = $enabled
        $runButton.Enabled = $enabled
    })


    $rebootButton = New-Object System.Windows.Forms.Button
    $rebootButton.Location = New-Object System.Drawing.Point(420, 210)
    $rebootButton.Size = New-Object System.Drawing.Size(150, 40)
    $rebootButton.Text = "Reboot Device"
    $rebootButton.Add_Click({
        if (Test-AdbConnection) {
            [System.Windows.Forms.MessageBox]::Show("Rebooting device...", "Info")
            & $AdbPath reboot
        } else {
            [System.Windows.Forms.MessageBox]::Show("No ADB device found. Please connect a device and ensure USB debugging is enabled.", "Error")
        }
    })
    $form.Controls.Add($rebootButton)


    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Location = New-Object System.Drawing.Point(10, 370)
    $statusLabel.Size = New-Object System.Drawing.Size(560, 40)
    $statusLabel.Text = "Select an application and choose an action."
    $form.Controls.Add($statusLabel)

    [System.Windows.Forms.Application]::Run($form)
}

# --- GUI Action Functions ---

function Invoke-InstallGUI($app) {
    if (-not (Test-AdbConnection)) { return }
    $appDir = Join-Path $AppsDir $app.PackageName
    $scriptPath = Join-Path $appDir 'install.bat'
    if (-not (Test-Path $scriptPath)) {
        [System.Windows.Forms.MessageBox]::Show("Install script not found!", "Error")
        return
    }
    Start-Process -FilePath cmd.exe -ArgumentList "/c `"$scriptPath`"" -WorkingDirectory $appDir -Wait
    [System.Windows.Forms.MessageBox]::Show("Installation completed.", "Info")
}

function Invoke-UninstallGUI($app) {
    $result = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to uninstall $($app.AppName)?", "Confirm Uninstall", [System.Windows.Forms.MessageBoxButtons]::YesNo)
    if ($result -eq [System.Windows.Forms.DialogResult]::No) { return }

    if (-not (Test-AdbConnection)) { return }
    $appDir = Join-Path $AppsDir $app.PackageName
    $scriptPath = Join-Path $appDir 'uninstall.bat'
    if (-not (Test-Path $scriptPath)) {
        [System.Windows.Forms.MessageBox]::Show("Uninstall script not found!", "Error")
        return
    }
    Start-Process -FilePath cmd.exe -ArgumentList "/c `"$scriptPath`"" -WorkingDirectory $appDir -WindowStyle Hidden -Wait
    [System.Windows.Forms.MessageBox]::Show("Uninstallation completed.", "Info")
}

function Invoke-RunGUI($app) {
    if (-not (Test-AdbConnection)) { return }
    $appDir = Join-Path $AppsDir $app.PackageName
    $scriptPath = Join-Path $appDir 'run.bat'
    if (-not (Test-Path $scriptPath)) {
        [System.Windows.Forms.MessageBox]::Show("Run script not found!", "Error")
        return
    }
    Start-Process -FilePath cmd.exe -ArgumentList "/c `"$scriptPath`"" -WorkingDirectory $appDir -WindowStyle Hidden -Wait
    [System.Windows.Forms.MessageBox]::Show("Application launched.", "Info")
}

function DeleteFrom-MenuGUI($app) {
    $result = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to delete $($app.AppName) from the menu?", "Confirm Delete", [System.Windows.Forms.MessageBoxButtons]::YesNo)
    if ($result -eq [System.Windows.Forms.DialogResult]::No) { return $false }

    $appDir = Join-Path $AppsDir $app.PackageName
    try {
        Remove-Item -Path $appDir -Recurse -Force

        $appLabelFile = Join-Path $AppsDir 'apps_label.txt'
        $appsContent = Get-Content $appLabelFile -Encoding UTF8 | Where-Object {
            $parts = $_.Split(';')
            $parts[2] -ne $app.PackageName
        }
        Set-Content -Path $appLabelFile -Value $appsContent -Encoding UTF8

        [System.Windows.Forms.MessageBox]::Show("$($app.AppName) has been deleted from the menu.", "Info")
        return $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to delete $($app.AppName): $_", "Error")
        return $false
    }
}

# --- Main Execution ---

Check-AdbEnvironment
$apps = Apps-Prepare
Create-GUI $apps