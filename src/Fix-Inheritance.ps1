<#
.SYNOPSIS
    Fixes inheritance on all files and subfolders, logging failures to CSV.

.DESCRIPTION
    Runs icacls inheritance:e /T on a target path, captures per-item failures
    and writes them to a CSV that can be fed to Take-Ownership.ps1 for recovery.

    Robustness guarantees:
      * NEVER stops on a single file failure - the per-item loop continues
        on every error and records it.
      * Files that fail to enumerate (access denied, lock, bad path) are
        captured via -ErrorVariable and recorded in the failure CSV.
      * All special characters in filenames are passed to icacls verbatim
        via ProcessStartInfo.ArgumentList (no command-line string
        re-parsing that could mishandle & ^ | " etc.).
      * Paths longer than Windows MAX_PATH (260) are passed with the
        \\?\ long-path prefix that icacls requires.
      * Export-Csv handles CSV escaping of commas, quotes, and newlines
        in filenames.
      * Exit code (HRESULT) is the primary signal for error classification,
        so behaviour is identical on non-English Windows installations.

.PARAMETER TargetPath
    The root folder path to fix inheritance on (e.g., R:\r_vs13_d2\ftcregfin\)

.PARAMETER OutputPath
    Path for the output CSV file. Default: .\FailedInheritance.csv
    If the value already ends in .csv it is used verbatim.

.PARAMETER LogPath
    Optional path for the log file. Default: same as OutputPath with .log extension
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TargetPath,

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$OutputPath = '.\FailedInheritance',

    [Parameter(Mandatory = $false, Position = 2)]
    [string]$LogPath = ''
)

# Load shared helpers (pure + I/O functions, constants).
# This file has no top-level code so it is safe to dot-source.
. (Join-Path $PSScriptRoot '_Common.ps1')

#region Main

function Invoke-FixInheritance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [string]$OutputPath = '.\FailedInheritance',
        [string]$LogPath = ''
    )

    # --- Path resolution ---
    $OutputCsv = Resolve-OutputCsvPath $OutputPath
    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $LogPath = [System.IO.Path]::GetFullPath("$OutputPath.log")
    } else {
        $LogPath = [System.IO.Path]::GetFullPath($LogPath)
    }
    New-DirectoryIfMissing ([System.IO.Path]::GetDirectoryName($OutputCsv))
    New-DirectoryIfMissing ([System.IO.Path]::GetDirectoryName($LogPath))

    # --- Validate target ---
    if (-not (Test-Path -LiteralPath $TargetPath)) {
        Write-Status "Target path does not exist: $TargetPath" -Level 'ERROR'
        Write-Error "Target path does not exist: $TargetPath"
        return
    }
    if (Test-Path -LiteralPath $OutputCsv -PathType Leaf) {
        Write-Status "Output file already exists and will be overwritten: $OutputCsv" -Level 'WARNING'
    }

    Write-Status "Starting inheritance fix on: $TargetPath"
    Write-Status "Output CSV:   $OutputCsv"
    Write-Status "Log file:     $LogPath"

    # --- Enumerate ---
    $failedItems  = [System.Collections.Generic.List[object]]::new()
    $failedCount  = 0
    $enumErrors   = $null
    try {
        $allItems = Get-ChildItem -LiteralPath $TargetPath -Recurse -Force `
            -ErrorAction SilentlyContinue -ErrorVariable enumErrors
    } catch {
        Write-Status "Error enumerating path: $_" -Level 'WARNING'
        $allItems = @()
    }

    # Capture items that failed to enumerate (access denied, lock, etc.)
    if ($enumErrors) {
        foreach ($err in $enumErrors) {
            $p = Get-ErrorRecordPath -Record $err
            if ($p) {
                Add-Failure -FullPath $p -ErrorReason "Cannot enumerate (likely access denied or path error)" -FailedItems $failedItems
                $failedCount++
            }
        }
        Write-Status "Captured $(@($enumErrors).Count) enumeration error(s) into the failure list." -Level 'WARNING'
    }

    $totalItems   = ($allItems | Measure-Object).Count
    $processedCount = 0
    Write-Status "Found $totalItems enumerable items (plus $failedCount items that failed enumeration)"

    # --- Bulk icacls ---
    # icacls with /C returns exit code 0 even if some items failed.
    # We never trust $LASTEXITCODE -eq 0 as proof of "no failures" -
    # we always do the per-item pass below to enumerate exact failures
    # for the CSV. The bulk pass is a speed optimisation that
    # pre-modifies the easy items in one process.
    Write-Status 'Attempting bulk icacls operation on root...'
    try {
        $r = Invoke-NativeCommand -FileName 'icacls.exe' -Arguments @((Get-LongPath $TargetPath), '/inheritance:e', '/T', '/C')
        Write-Status "Bulk operation finished (exit code: $($r.ExitCode)). Per-item verification will identify exact failures."
    } catch {
        Write-Status "Bulk operation failed: $_" -Level 'WARNING'
    }

    # --- Per-item pass ---
    # try/catch ensures a single file's exception does NOT stop the loop.
    Write-Status 'Processing items individually to identify failures (continues on all errors)...'

    foreach ($item in $allItems) {
        $processedCount++
        $fullPath = $item.FullName

        if ($processedCount % 100 -eq 0) {
            Write-Status "Progress: Processed $processedCount / $totalItems (Failures: $failedCount)"
        }

        try {
            $r = Invoke-NativeCommand -FileName 'icacls.exe' -Arguments @((Get-LongPath $fullPath), '/inheritance:e', '/C')
            if ($r.ExitCode -ne 0) {
                $combined = "$($r.Output)`n$($r.Error)"
                Add-Failure -FullPath $fullPath -ErrorReason (Get-ErrorReason -ExitCode $r.ExitCode -ErrorOutput $combined) -FailedItems $failedItems
                $failedCount++
            }
        } catch {
            Add-Failure -FullPath $fullPath -ErrorReason "Exception: $($_.Exception.Message)" -FailedItems $failedItems
            $failedCount++
        }
    }

    # --- Export CSV ---
    # Export-Csv on an empty collection produces an empty file, so we
    # write the header explicitly when the list is empty.
    if ($failedItems.Count -gt 0) {
        $failedItems | Select-Object FilePath, FileName, ParentFolder, FolderName, ErrorReason, PathLength, IsLongPath, Timestamp |
            Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8 -Force
    } else {
        '"FilePath","FileName","ParentFolder","FolderName","ErrorReason","PathLength","IsLongPath","Timestamp"' |
            Set-Content -Path $OutputCsv -Encoding UTF8 -Force
    }

    # --- Summary ---
    $enumErrorCount = @($enumErrors).Count
    Write-Section 'Summary'
    Write-Status "Total items processed:  $processedCount"
    Write-Status "Failed items:           $failedCount"
    Write-Status "  - Enumeration errors: $enumErrorCount"
    Write-Status "  - Per-item errors:    $($failedCount - $enumErrorCount)"
    Write-Status "CSV:                    $OutputCsv"

    if ($failedCount -gt 0) {
        Write-Status 'Error breakdown:'
        $failedItems | Group-Object ErrorReason | Sort-Object Count -Descending | Format-Table Count, Name -AutoSize
        Write-Status 'Use Take-Ownership.ps1 or Take-Ownership.bat to fix failed items.'
    }

    Write-Status 'Done.'
}
#endregion

# --- Invocation guard ---
# Run main only when the script is invoked directly, not when dot-sourced
# for testing (in which case the test invokes Invoke-FixInheritance with
# its own parameters).
if ($MyInvocation.InvocationName -ne '.') {
    $scriptErrors = $null
    Invoke-FixInheritance @PSBoundParameters -ErrorVariable scriptErrors
    if ($scriptErrors) { exit 1 }
}
