<#
.SYNOPSIS
    Shared helper functions and constants for Fix-Inheritance.ps1 and
    Take-Ownership.ps1. This file is intended to be DOT-SOURCED by
    those scripts (or by their Pester tests), not executed directly.
    It defines no top-level execution code - only functions and
    constants - so it can be loaded without triggering any pipeline.

.DESCRIPTION
    Public surface:
      Pure (no external dependencies, easily unit-tested):
        Get-LongPath, ConvertFrom-HResult, Get-ErrorReason, Get-ErrorRecordPath, Add-Failure

      I/O (depend on script state or invoke processes):
        Write-ScriptLog, Write-Status, Write-Section,
        Invoke-IcaclsOp, New-DirectoryIfMissing

    Constants (set in $script: scope so they are visible to functions
    loaded alongside this file):
        $script:MaxPathLength, $script:LongPathPrefix
#>

# Version detection - robust fallback for environments where $PSScriptRoot is unavailable
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) { $ScriptRoot = $MyInvocation.PSScriptRoot }
if (-not $ScriptRoot) { $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptRoot) { $ScriptRoot = $PWD.Path }

# PS7+ detection (PSEdition is the most reliable signal)
if ($PSVersionTable.PSEdition -ne 'Core' -and $PSVersionTable.PSVersion.Major -lt 6) {
    $pwsh51Common = Join-Path $ScriptRoot "pwsh51" "_Common.ps1"
    if (Test-Path -LiteralPath $pwsh51Common) {
        . $pwsh51Common
        return
    }
}

# Display clear PowerShell version banner (only if not already shown by main script)
if (-not (Get-Variable -Name "FixInheritanceBannerShown" -ErrorAction SilentlyContinue)) {
    $psVer = if ($PSVersionTable.PSVersion) { $PSVersionTable.PSVersion.ToString() } else { "Unknown" }
    $psEd = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { "Desktop" }
    Write-Host "****************************************************" -ForegroundColor Cyan
    Write-Host "* PowerShell Version: $psVer ($psEd)" -ForegroundColor Cyan
    Write-Host "****************************************************" -ForegroundColor Cyan
    Write-Host ""
    Set-Variable -Name "FixInheritanceBannerShown" -Value $true -Scope Script
}

#region Constants
# Windows MAX_PATH is 260; the \\?\ prefix lets APIs handle longer paths.
$script:MaxPathLength = 260
$script:LongPathPrefix = '\\?\'
#endregion

#region Pure Functions

# Returns the path with the \\?\ long-path prefix when it exceeds MAX_PATH.
# Handles drive roots (C:\), regular paths, and UNC paths (\\server\share).
function Get-LongPath {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return $Path }
    if ($Path.Length -le $script:MaxPathLength) { return $Path }
    if ($Path.StartsWith($script:LongPathPrefix)) { return $Path }
    if ($Path.Length -ge 2 -and $Path[1] -eq ':') {
        return "$script:LongPathPrefix$Path"
    }
    if ($Path.StartsWith('\\')) {
        return $script:LongPathPrefix + 'UNC\' + $Path.Substring(2)
    }
    return "$script:LongPathPrefix$Path"
}

# Maps a Windows error code (HRESULT) to its symbolic name. Windows
# error codes are numeric and therefore locale-independent.
function ConvertFrom-HResult {
    param([int]$Code)
    $map = @{
        0   = 'SUCCESS'
        2   = 'ERROR_FILE_NOT_FOUND'
        3   = 'ERROR_PATH_NOT_FOUND'
        5   = 'ERROR_ACCESS_DENIED'
        32  = 'ERROR_SHARING_VIOLATION'
        87  = 'ERROR_INVALID_PARAMETER'
        206 = 'ERROR_FILENAME_EXCED_RANGE'
    }
    if ($map.ContainsKey($Code)) { return $map[$Code] }
    return "ERROR_CODE_$Code"
}

# Classifies an icacls/takeown failure into a category. Uses the exit
# code (HRESULT) first (locale-independent), then falls back to
# message-pattern matching for codes not in the HRESULT map.
function Get-ErrorReason {
    param(
        [int]$ExitCode,
        [string]$ErrorOutput = ''
    )
    switch ($ExitCode) {
        5   { return 'Access Denied - requires ownership change' }
        32  { return 'File in use' }
        2   { return 'File not found' }
        3   { return 'File not found' }
        206 { return 'Path too long' }
        87  { return 'Invalid path or filename' }
        default {
            if ($ErrorOutput -match 'Access is denied') { return 'Access Denied - requires ownership change' }
            if ($ErrorOutput -match 'is in use|being used by another process') { return 'File in use' }
            if ($ErrorOutput -match 'path not found|The system cannot find the path') { return 'File not found' }
            if ($ErrorOutput -match 'filename or extension is too long|too long') { return 'Path too long' }
            if ($ErrorOutput -match 'invalid|syntax is incorrect') { return 'Invalid path or filename' }
            return "Unknown error (exit code: $ExitCode)"
        }
    }
}

# Records a failure entry in the list. Kept pure (no I/O) for testability.
function Add-Failure {
    param(
        [string]$FullPath,
        [string]$ErrorReason,
        [System.Collections.Generic.List[object]]$FailedItems
    )
    $FailedItems.Add([PSCustomObject]@{
        FilePath     = $FullPath
        FileName     = [System.IO.Path]::GetFileName($FullPath)
        ParentFolder = [System.IO.Path]::GetDirectoryName($FullPath)
        FolderName   = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($FullPath))
        ErrorReason  = $ErrorReason
        PathLength   = $FullPath.Length
        IsLongPath   = ($FullPath.Length -gt $script:MaxPathLength)
        Timestamp    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    })
}

# Extracts the target path from a PowerShell ErrorRecord produced by
# Get-ChildItem. Returns $null if no path can be identified.
function Get-ErrorRecordPath {
    param([System.Management.Automation.ErrorRecord]$Record)
    if ($Record.CategoryInfo -and $Record.CategoryInfo.TargetName) {
        return $Record.CategoryInfo.TargetName
    }
    $msg = if ($Record.Exception) { $Record.Exception.Message } else { $Record.ToString() }
    if ($msg -match "'([^']+)'") {
        return $Matches[1]
    }
    return $null
}
#endregion

#region I/O Functions

# Writes a timestamped entry to the log file. Silently ignores log
# write failures so they never crash the main pipeline.
function Write-ScriptLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO','WARNING','ERROR')][string]$Level = 'INFO'
    )
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogPath -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue
}

# Writes a status message to BOTH console (with level-based colour) and
# the log file. Replaces the repeated Write-Host + Write-ScriptLog pair
# that would otherwise appear throughout the script.
function Write-Status {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO','WARNING','ERROR')][string]$Level = 'INFO'
    )
    $color = switch ($Level) {
        'ERROR'   { 'Red' }
        'WARNING' { 'Yellow' }
        default   { $null }
    }
    if ($color) { Write-Host $Message -ForegroundColor $color } else { Write-Host $Message }
    Write-ScriptLog -Message $Message -Level $Level
}

# Writes a titled section header (with ==== separators) to both
# console and log.
function Write-Section {
    param([Parameter(Mandatory = $true)][string]$Title)
    $line = '=' * 42
    Write-Status $line
    Write-Status $Title
    Write-Status $line
}

# Invokes a native command (icacls.exe or takeown.exe) so that
# every argument is passed verbatim to the OS, with no PowerShell
# or cmd pre-parsing that could mishandle metacharacters in paths.
function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$ThrowOnError
    )
    $result = [PSCustomObject]@{ ExitCode = 0; Output = ''; Error = '' }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $FileName
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::Default
        $psi.StandardErrorEncoding  = [System.Text.Encoding]::Default

        $hasArgList = $null -ne ([System.Diagnostics.ProcessStartInfo].GetProperty('ArgumentList'))
        if ($hasArgList) {
            foreach ($a in $Arguments) { [void]$psi.ArgumentList.Add($a) }
        } else {
            $psi.Arguments = ($Arguments | ForEach-Object {
                if ($_ -match '[\s"]') { '"' + ($_ -replace '"','\"') + '"' } else { $_ }
            }) -join ' '
        }

        $proc = [System.Diagnostics.Process]::Start($psi)
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        $proc.WaitForExit()
        $result.Output    = $outTask.Result
        $result.Error     = $errTask.Result
        $result.ExitCode  = $proc.ExitCode
    } catch {
        if ($ThrowOnError) { throw }
        $result.ExitCode = -1
        $result.Error    = "Failed to invoke $FileName : $($_.Exception.Message)"
    }
    return $result
}

# Backwards-compatible alias used by Fix-Inheritance.ps1
Set-Alias -Name Invoke-IcaclsOp -Value Invoke-NativeCommand -Scope Global -Force

# Creates a directory (and parents) if it does not already exist.
function New-DirectoryIfMissing {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# Writes the failure list to a CSV.
function Write-FailureCsv {
    param(
        [object[]]$FailedItems,
        [Parameter(Mandatory = $true)][string]$OutputCsv
    )
    if ($FailedItems -and $FailedItems.Count -gt 0) {
        $FailedItems | Select-Object FilePath, FileName, ParentFolder, FolderName, ErrorReason, PathLength, IsLongPath, Timestamp |
            Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8 -Force
    } else {
        '"FilePath","FileName","ParentFolder","FolderName","ErrorReason","PathLength","IsLongPath","Timestamp"' |
            Set-Content -Path $OutputCsv -Encoding UTF8 -Force
    }
}
#endregion
