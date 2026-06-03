<#
.SYNOPSIS
    Fixes inheritance on all files and subfolders, logging failures to CSV.

.DESCRIPTION
    Runs icacls inheritance:e /T on a target path, captures per-item failures
    and writes them to a CSV that can be fed to Take-Ownership.ps1 for recovery.

      * NEVER stops on a single file failure - the per-item loop continues
        on every error and records it.
      * Files that fail to enumerate (access denied, lock, bad path) are
        captured via -ErrorVariable and recorded in the failure CSV.
      * All special characters in filenames are passed to icacls verbatim.
        On PowerShell 7+ this uses ProcessStartInfo.ArgumentList; on
        Windows PowerShell 5.1 it falls back to a manually-quoted
        Arguments string (see Invoke-NativeCommand for the rationale).
      * Paths longer than Windows MAX_PATH (260) are passed with the
        \\?\ long-path prefix that icacls requires.
      * Export-Csv handles CSV escaping of commas, quotes, and newlines
        in filenames.
      * Exit code (HRESULT) is the primary signal for error classification,
        so behaviour is identical on non-English Windows installations.

.PARAMETER TargetPath
    The root folder path to fix inheritance on (e.g., R:\r_vs13_d2\ftcregfin\)

.PARAMETER OutputPath
    Path for the output CSV file. Default: ./output/FailedInheritance.csv

.PARAMETER LogPath
    Path for the log file. Default: ./logs/FailedInheritance.log (independent of OutputPath)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TargetPath,

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$OutputPath = $null,

    [Parameter(Mandatory = $false, Position = 2)]
    [string]$LogPath = $null
)

# Final robust version detection using pwsh --version as fallback (reliable on problematic servers)
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) { $ScriptRoot = $MyInvocation.PSScriptRoot }
if (-not $ScriptRoot) { $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptRoot) { $ScriptRoot = $PWD.Path }

# Determine if we are running PowerShell 7+
$isPS7 = $false
if ($PSVersionTable.PSEdition -eq 'Core') { $isPS7 = $true }
if ($PSVersionTable.PSVersion.Major -ge 6) { $isPS7 = $true }

# Fallback: explicitly call pwsh --version (very reliable)
if (-not $isPS7) {
    try {
        $pwshOutput = & pwsh --version 2>$null
        if ($pwshOutput -like '*7.*') { $isPS7 = $true }
    } catch {}
}

if (-not $isPS7) {
    $pwsh51Script = Join-Path $ScriptRoot "pwsh51" "Fix-Inheritance.ps1"
    if (Test-Path -LiteralPath $pwsh51Script) {
        if ($MyInvocation.InvocationName -eq '.') {
            . $pwsh51Script @PSBoundParameters
        } else {
            & $pwsh51Script @PSBoundParameters
            exit $LASTEXITCODE
        }
        return
    }
}

. (Join-Path $ScriptRoot '_Common.ps1')

function Invoke-FixInheritance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [string]$OutputPath = $null,
        [string]$LogPath = $null
    )

    $repoRoot = Split-Path $PSScriptRoot -Parent
    if (-not $OutputPath) { $OutputPath = Join-Path $repoRoot 'output/FailedInheritance.csv' }
    if (-not $OutputPath.ToLower().EndsWith('.csv')) { $OutputPath = $OutputPath + '.csv' }
    if (-not $LogPath) { $LogPath = Join-Path $repoRoot 'logs/FailedInheritance.log' }

    $OutputCsv = [System.IO.Path]::GetFullPath($OutputPath)
    $LogPath = [System.IO.Path]::GetFullPath($LogPath)

    New-DirectoryIfMissing ([System.IO.Path]::GetDirectoryName($OutputCsv))
    New-DirectoryIfMissing ([System.IO.Path]::GetDirectoryName($LogPath))

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        Write-Status "Target path does not exist: $TargetPath" -Level 'ERROR'
        Write-Error "Target path does not exist: $TargetPath"
        Write-FailureCsv -FailedItems @() -OutputCsv $OutputCsv
        return
    }
    if (Test-Path -LiteralPath $OutputCsv -PathType Leaf) {
        Write-Status "Output file already exists and will be overwritten: $OutputCsv" -Level 'WARNING'
    }

    Write-Status "Starting inheritance fix on: $TargetPath"
    Write-Status "Output CSV:   $OutputCsv"
    Write-Status "Log file:     $LogPath"

    $failedItems  = [System.Collections.Generic.List[object]]::new()
    $failedCount  = 0
    $enumErrors   = $null
    try {
        $allItems = Get-ChildItem -LiteralPath $TargetPath -Recurse -Force `
            -ErrorAction Continue -ErrorVariable enumErrors
    } catch {
        Write-Status "Error enumerating path: $_" -Level 'WARNING'
        if (-not $allItems) { $allItems = @() }
        if (-not $enumErrors) {
            Add-Failure -FullPath $TargetPath `
                -ErrorReason "Cannot enumerate (likely access denied or path error): $($_.Exception.Message)" `
                -FailedItems $failedItems
            $failedCount++
            Write-Status "Recorded terminating enumeration error against target path." -Level 'WARNING'
        }
    }

    if ($enumErrors) {
        foreach ($err in $enumErrors) {
            $p = Get-ErrorRecordPath -Record $err
            if (-not $p) { $p = $TargetPath }
            Add-Failure -FullPath $p -ErrorReason "Cannot enumerate (likely access denied or path error)" -FailedItems $failedItems
            $failedCount++
        }
        Write-Status "Captured $(@($enumErrors).Count) enumeration error(s) into the failure list." -Level 'WARNING'
    }

    $totalItems   = ($allItems | Measure-Object).Count
    $actualFileCount = @($allItems | Where-Object { -not $_.PSIsContainer }).Count
    $folderCount     = @($allItems | Where-Object { $_.PSIsContainer }).Count
    $processedCount  = 0
    $filesProcessed  = 0
    $foldersProcessed = 0
    Write-Status "Found $totalItems enumerable items (Files: $actualFileCount, Folders: $folderCount) plus $failedCount items that failed enumeration"

    Write-Status 'Attempting bulk icacls operation on root...'
    try {
        $r = Invoke-NativeCommand -FileName 'icacls.exe' -Arguments @((Get-LongPath $TargetPath), '/inheritance:e', '/T', '/C') -ThrowOnError
        if ($r.ExitCode -ne 0) {
            $combined = "$($r.Output)`n$($r.Error)"
            Add-Failure -FullPath $TargetPath `
                -ErrorReason (Get-ErrorReason -ExitCode $r.ExitCode -ErrorOutput $combined) `
                -FailedItems $failedItems
            $failedCount++
            Write-Status "Bulk icacls failed (exit code $($r.ExitCode)); recorded against target path." -Level 'WARNING'
        } else {
            Write-Status "Bulk operation finished (exit code 0). Per-item verification will identify exact failures."
        }
    } catch {
        Write-Status "Bulk operation failed: $_" -Level 'WARNING'
        Add-Failure -FullPath $TargetPath `
            -ErrorReason "Bulk operation exception: $($_.Exception.Message)" `
            -FailedItems $failedItems
        $failedCount++
    }

    Write-Status 'Processing items individually to identify failures (continues on all errors)...'

    foreach ($item in $allItems) {
        $processedCount++
        try {
            if ($item.PSIsContainer) { $foldersProcessed++ } else { $filesProcessed++ }
            $fullPath = $item.FullName

            if ($processedCount % 100 -eq 0) {
                Write-Status "Progress: Processed $processedCount / $totalItems (Files: $filesProcessed/$actualFileCount, Folders: $foldersProcessed/$folderCount, Failures: $failedCount)"
            }

            $r = Invoke-NativeCommand -FileName 'icacls.exe' -Arguments @((Get-LongPath $fullPath), '/inheritance:e', '/C') -ThrowOnError
            if ($r.ExitCode -ne 0) {
                $combined = "$($r.Output)`n$($r.Error)"
                Add-Failure -FullPath $fullPath -ErrorReason (Get-ErrorReason -ExitCode $r.ExitCode -ErrorOutput $combined) -FailedItems $failedItems
                $failedCount++
            }
        } catch {
            $fp = if ($item -and $item.FullName) { $item.FullName } else { $TargetPath }
            Add-Failure -FullPath $fp -ErrorReason "Exception: $($_.Exception.Message)" -FailedItems $failedItems
            $failedCount++
        }
    }

    try {
        Write-FailureCsv -FailedItems $failedItems -OutputCsv $OutputCsv
    } catch {
        Write-Status "FATAL: failed to write CSV at $OutputCsv : $_" -Level 'ERROR'
        Write-Error $_
    }

    $enumErrorCount = @($enumErrors).Count
    Write-Section 'Summary'
    Write-Status "Items discovered:       $totalItems"
    Write-Status "  - Files:              $actualFileCount"
    Write-Status "  - Folders:            $folderCount"
    Write-Status "Items processed:        $processedCount"
    Write-Status "  - Files processed:    $filesProcessed"
    Write-Status "  - Folders processed:  $foldersProcessed"
    Write-Status "Failed items:           $failedCount"
    Write-Status "  - Enumeration errors: $enumErrorCount"
    Write-Status "  - Per-item errors:    $($failedCount - $enumErrorCount)"
    Write-Status "CSV:                    $OutputCsv"

    $countMismatch = $false
    if ($actualFileCount -ne $filesProcessed) {
        Write-Status "*** COUNT MISMATCH: Actual file count ($actualFileCount) does not match files processed ($filesProcessed) ***" -Level 'WARNING'
        $countMismatch = $true
    }
    if ($folderCount -ne $foldersProcessed) {
        Write-Status "*** COUNT MISMATCH: Actual folder count ($folderCount) does not match folders processed ($foldersProcessed) ***" -Level 'WARNING'
        $countMismatch = $true
    }
    if (($actualFileCount + $folderCount) -ne $processedCount) {
        Write-Status "*** COUNT MISMATCH: Total discovered ($($actualFileCount + $folderCount)) does not match total processed ($processedCount) ***" -Level 'WARNING'
        $countMismatch = $true
    }

    if ($failedCount -gt 0) {
        Write-Status 'Error breakdown:'
        $failedItems | Group-Object ErrorReason | Sort-Object Count -Descending | Format-Table Count, Name -AutoSize
        Write-Status 'Use Take-Ownership.ps1 to fix failed items.'
    }

    Write-Status 'Done.'
    return $countMismatch
}

if ($MyInvocation.InvocationName -ne '.') {
    $scriptErrors = $null
    $countMismatch = Invoke-FixInheritance @PSBoundParameters -ErrorVariable scriptErrors
    if ($scriptErrors) { exit 1 }
    if ($countMismatch) { exit 2 }
}
