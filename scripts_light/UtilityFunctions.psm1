# UtilityFunctions.psm1
# Module for utility functions

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [ConsoleColor]$Color = "White"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    Write-Host $logMessage -ForegroundColor $Color

    # TODO: Add file logging if needed
}

function Test-DirectoryExists {
    param([string]$Path)

    if (-not (Test-Path -Path $Path -PathType Container)) {
        Write-Log "Creating directory: $Path" -Level "INFO" -Color Green
        New-Item -Path $Path -ItemType Directory | Out-Null
    }
}

function Remove-PathSafe {
    param([string]$Path)

    if (-not (Test-Path -Path $Path)) { return }

    # normalize path
    $literal = (Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue).FullName 2>$null
    if (-not $literal) { $literal = $Path }

    # helper to try Remove-Item with optional longPath prefix
    function Try-Remove($p) {
        try {
            Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
            return $true
        }
        catch {
            return $false
        }
    }

    # try straightforward removal first
    if (Try-Remove $literal) { return }

    Write-Log "Remove-Item failed for '$literal': will attempt advanced removal methods..." -Level "WARNING" -Color Yellow

    # Try Remove-Item using Windows long path prefix
    try {
        $longPath = "\\?\$literal"
        if (Try-Remove $longPath) { return }
    }
    catch {
        # ignore
    }

    # Attempt to take ownership and reset ACLs, then try remove again
    try {
        Write-Log "Attempting to take ownership and reset permissions for: $literal" -Level "INFO" -Color Yellow
        Start-Process -FilePath cmd.exe -ArgumentList "/c takeown /f `"$literal`" /r /d y" -NoNewWindow -Wait
        Start-Process -FilePath cmd.exe -ArgumentList "/c icacls `"$literal`" /grant Administrators:F /t /c" -NoNewWindow -Wait
        Start-Sleep -Milliseconds 500
        if (Try-Remove $literal -eq $true) { return }
        if (Try-Remove ("\\?\$literal")) { return }
    }
    catch {
        Write-Log "takeown/icacls attempt failed: $_" -Level "WARNING" -Color Yellow
    }

    # Try cmd rd /s /q
    try {
        $cmd = "/c rd /s /q `"$literal`""
        Start-Process -FilePath cmd.exe -ArgumentList $cmd -NoNewWindow -Wait
        if (-not (Test-Path $literal)) { return }
    }
    catch {
        Write-Log "cmd rd failed: $_" -Level "WARNING" -Color Yellow
    }

    # Try robocopy mirror from an empty folder
    try {
        $empty = Join-Path $env:TEMP ("empty_{0}" -f ([Guid]::NewGuid().ToString()))
        New-Item -Path $empty -ItemType Directory | Out-Null
        $robocopyArgs = @($empty, $literal, '/MIR')
        Start-Process -FilePath robocopy -ArgumentList $robocopyArgs -NoNewWindow -Wait
        Remove-Item -Path $empty -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $literal) {
            Try-Remove $literal | Out-Null
            Try-Remove ("\\?\$literal") | Out-Null
        }
        if (-not (Test-Path $literal)) { return }
    }
    catch {
        Write-Log "robocopy removal attempt failed: $_" -Level "WARNING" -Color Yellow
    }

    # Fallback: try mounting parent folder to a temporary drive letter (subst) to shorten long paths
    try {
        $parent = Split-Path -Path $literal -Parent
        if (Test-Path $parent) {
            # find free drive letter from Z downwards
            $used = (Get-PSDrive -PSProvider FileSystem).Name
            $driveLetter = $null
            for ($c = [byte][char]'Z'; $c -ge [byte][char]'T'; $c--) {
                $d = [char]$c
                if (-not ($used -contains "$d`:")) { $driveLetter = "$d`:"; break }
            }
            if ($driveLetter) {
                $substCmd = "/c subst $driveLetter `"$parent`""
                Start-Process -FilePath cmd.exe -ArgumentList $substCmd -NoNewWindow -Wait
                try {
                    $leaf = Split-Path -Path $literal -Leaf
                    $shortPath = Join-Path $driveLetter $leaf
                    Try-Remove $shortPath | Out-Null
                    Try-Remove ("\\?\$shortPath") | Out-Null
                    $removedBySubst = -not (Test-Path $literal)
                }
                catch {
                    Write-Log "Removal via subst failed: $_" -Level "WARNING" -Color Yellow
                }
                finally {
                    # remove subst
                    $delSubst = "/c subst $driveLetter /d"
                    Start-Process -FilePath cmd.exe -ArgumentList $delSubst -NoNewWindow -Wait
                }
                if ($removedBySubst) { return }
            }
        }
    }
    catch {
        Write-Log "subst fallback failed: $_" -Level "WARNING" -Color Yellow
    }

    Write-Log "Could not remove path '$literal' by any method. Manual cleanup may be required." -Level "ERROR" -Color Red
}

function Get-FileHashSafe {
    param([string]$Path)

    try {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
    catch {
        Write-Log "Failed to calculate hash for $Path`: $_" -Level "ERROR" -Color Red
        return $null
    }
}

function Test-FileExists {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "File not found: $Path"
    }
}

function Test-CommandExists {
    param([string]$Command)

    try {
        $null = Get-Command $Command -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Invoke-ExternalCommand {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory = $null,
        [int]$ExpectedExitCode = 0
    )

    $startInfo = @{
        FilePath = $FilePath
        ArgumentList = $ArgumentList
        NoNewWindow = $true
        Wait = $true
        PassThru = $true
    }

    if ($WorkingDirectory) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }

    $process = Start-Process @startInfo

    if ($process.ExitCode -ne $ExpectedExitCode) {
        throw "Command '$FilePath $($ArgumentList -join ' ')' failed with exit code $($process.ExitCode)"
    }

    return $process
}

Export-ModuleMember -Function Write-Log, Test-DirectoryExists, Remove-PathSafe, Get-FileHashSafe, Test-FileExists, Test-CommandExists, Invoke-ExternalCommand