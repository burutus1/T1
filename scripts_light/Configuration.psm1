# Configuration.psm1 (Light Version)
# Module for configuration management (ADB only)

class ApkProcessorConfig {
    [string]$BaseDir
    [string]$AdbCommand
    [string]$AppsDir
    [string]$AppLabelFile
    [string]$ProgressPreference
    [string]$ErrorActionPreference

    ApkProcessorConfig() {
        $this.BaseDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent  # Go up one level from scripts_light to project root
        $this.AdbCommand = Join-Path (Join-Path $this.BaseDir 'adb') 'adb.exe'
        $this.AppsDir = Join-Path $this.BaseDir '_APPS_'
        $this.AppLabelFile = Join-Path $this.AppsDir 'apps_label.txt'
        $this.ProgressPreference = 'SilentlyContinue'
        $this.ErrorActionPreference = 'Stop'
    }

    [void] EnsureDirectoriesExist() {
        $directories = @($this.AppsDir)
        foreach ($dir in $directories) {
            if (-not (Test-Path -Path $dir -PathType Container)) {
                Write-Host "Creating directory: $dir"
                New-Item -Path $dir -ItemType Directory | Out-Null
            }
        }
    }

    [bool] ValidateAdb() {
        $adbPath = Split-Path $this.AdbCommand -Parent
        if (-not (Test-Path $adbPath)) {
            Write-Warning "ADB path not found: $adbPath"
            return $false
        }
        return $true
    }
}

# Global configuration instance
$global:Config = [ApkProcessorConfig]::new()

function Get-Configuration {
    return $global:Config
}

function Initialize-Configuration {
    $global:Config.EnsureDirectoriesExist()
    if (-not $global:Config.ValidateAdb()) {
        throw "ADB validation failed. Please check ADB path."
    }
}

Export-ModuleMember -Function Get-Configuration, Initialize-Configuration
Export-ModuleMember -Variable Config