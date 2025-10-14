<#
.SYNOPSIS
    Finds a device by name and updates its driver. Automatically requests Admin privileges.

.DESCRIPTION
    This script searches for a PnP device with a name matching "SA8155 V2- *".
    If the device is found, it checks for the existence of a "./USB" directory.
    - If the directory exists, it uses the .inf file within it to update the driver.
    - If the directory does not exist, it downloads the official Google Android USB driver,
      extracts it to the "./USB" directory, and then proceeds with the installation.

    If not run as Administrator, the script will re-launch itself and request elevation.
#>

# --- Script Body ---

# 1. Self-elevation to Administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Administrator privileges are required. Attempting to re-launch with elevation..."
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Write-Host "Script is running with Administrator privileges."

# Set the working directory to the script's own folder to ensure relative paths work correctly.
Set-Location -Path $PSScriptRoot
Write-Host "Working directory set to: $PSScriptRoot"

# --- Configuration ---
# The path to the file containing a list of device names (one per line).
$deviceListFile = "devices.txt"
$targetDeviceNames = @() # Initialize an empty array

if (Test-Path -Path $deviceListFile) {
    # Read all non-empty lines from the file.
    $targetDeviceNames = Get-Content -Path $deviceListFile | Where-Object { $_.Trim() -ne "" }
}

# Check if any device names were loaded.
if ($targetDeviceNames.Count -eq 0) {
    Write-Error "The device list file '$deviceListFile' was not found or is empty. Please create it and add at least one device name."
    Start-Sleep -Seconds 10
    exit 1
}
# The local directory where the driver files are expected to be.
$driverPath = ".\USB"
# The URL to download the driver from if the local directory doesn't exist.
$driverDownloadUrl = "https://dl.google.com/android/repository/usb_driver_r13-windows.zip"
# The name for the temporary downloaded zip file.
$zipFileName = "android_usb_driver.zip"


# 2. Check if the driver directory exists. If not, download and extract it.
if (-not (Test-Path -Path $driverPath -PathType Container)) {
    Write-Host "Driver directory '$driverPath' not found."
    Write-Host "Downloading Android USB Driver from '$driverDownloadUrl'..."

    try {
        Invoke-WebRequest -Uri $driverDownloadUrl -OutFile $zipFileName -ErrorAction Stop
        Write-Host "Download complete. Extracting archive..."
        Expand-Archive -Path $zipFileName -DestinationPath $PSScriptRoot -Force -ErrorAction Stop
        # The zip extracts to a 'usb_driver' folder, let's rename it to 'USB'
        Rename-Item -Path ".\usb_driver" -NewName "USB" -ErrorAction Stop
        Write-Host "Driver extracted and prepared in '$driverPath' directory."
    }
    catch {
        Write-Error "Failed to download or extract the driver. Error: $_"
        # Pause for user to see the error
        Start-Sleep -Seconds 10
        exit 1
    }
    finally {
        # Clean up the downloaded zip file
        if (Test-Path -Path $zipFileName) {
            Remove-Item -Path $zipFileName -Force
        }
    }
}
else {
    Write-Host "Driver directory '$driverPath' already exists. Skipping download."
}

# 3. Find the target device(s)
Write-Host "Searching for devices matching: $($targetDeviceNames -join ', ')"
# Using Get-PnpDevice as it's the modern standard for this task.
$device = Get-PnpDevice | Where-Object {
    $currentDeviceName = $_.Name
    foreach ($pattern in $targetDeviceNames) {
        if ($currentDeviceName -like $pattern) {
            return $true # A match was found, so include this device.
        }
    }
    return $false # No matches were found for this device.
}

if ($device) {
    # We only expect one such device, so we take the first one found.
    $targetDevice = $device | Select-Object -First 1
    Write-Host "SUCCESS: Found device '$($targetDevice.Name)' (InstanceId: $($targetDevice.InstanceId))"

    # 4. Find the driver's .inf file and install it
    $infFile = Get-ChildItem -Path $driverPath -Filter "*.inf" -Recurse | Select-Object -First 1

    if ($infFile) {
        Write-Host "Found driver INF file: $($infFile.FullName)"
        Write-Host "Attempting to install driver... This may take a moment."

        # Use pnputil to add the driver to the driver store and install it.
        # This is the recommended modern method for driver installation via command line.
        pnputil /add-driver $infFile.FullName /install
        
        Write-Host "Driver installation command executed. Check the output above for status."
        Write-Host "You may need to unplug and replug the device for changes to take full effect."
    }
    else {
        Write-Error "CRITICAL: No .inf file found within the '$driverPath' directory. Cannot proceed with installation."
    }
}
else {
    Write-Warning "Device with name like '$deviceNamePattern' not found. Please ensure it is connected and visible in Device Manager."
}

Write-Host "Script finished."
# Pause at the end to allow the user to read the full output.
Start-Sleep -Seconds 5
