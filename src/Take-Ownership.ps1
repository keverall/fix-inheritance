<#
.SYNOPSIS
    Takes ownership of files listed in CSV and re-applies inheritance.

.DESCRIPTION
    Reads the FailedInheritance.csv output from Fix-Inheritance.ps1,
    takes ownership of each file using takeown, then re-runs icacls
    to enable inheritance. Requires Administrator privileges.

    Robustness guarantees (mirrors Fix-Inheritance.ps1):
      * NEVER stops on a single file failure - the per-item loop
        continues on every error and records it.
      * All special characters in filenames are passed to takeown /
        icacls verbatim via ProcessStartInfo.ArgumentList (no
        command-line string re-parsing that could mishandle
        & ^ | " etc.).
      * Paths longer than Windows MAX_PATH (260) are passed with the
        \\?\ long-path prefix.
      * Exit code (HRESULT) is the primary signal for classification.
      * All activity is written to a log file (same format as
        Fix-Inheritance.ps1) so post-mortem is possible.

.PARAMETER CsvPath
    Path to the FailedInheritance.csv file

.PARAMETER OutputCsv
    Path for results CSV. Defaults to Results_YYYYMMDD_HHMMSS.csv next to input.
    If the value already ends in .csv it is used verbatim.

.PARAMETER LogPath
    Optional path for the log file. Default: same dir as CsvPath with
    TakeOwnership_YYYYMMDD_HHmmss.log.

.EXAMPLE
    .\Take-Ownership.ps1 -CsvPath "C:\temp\FailedInheritance.csv"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputCsv = "",

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ''
)

# Load shared helpers (pure + I/O functions, constants).
. (Join-Path $PSScriptRoot '_Common.ps1')

#region Main

function Invoke-TakeOwnership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CsvPath,
        [string]$OutputCsv = '',
        [string]$LogPath = ''
    )

    # --- Resolve paths ---
    if (-not (Test-Path -LiteralPath $CsvPath)) {
        # Use Write-Error since the log file may not be initialised yet
        Write-Error "CSV file not found: $CsvPath"
        return
    }

    $csvDir = [System.IO.Path]::GetDirectoryName($CsvPath)

    if ([string]::IsNullOrEmpty($OutputCsv)) {
        $OutputCsv = [System.IO.Path]::Combine($csvDir, "Results_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv")
    }
    $OutputCsv = Resolve-OutputCsvPath $OutputCsv

    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $LogPath = [System.IO.Path]::Combine($csvDir, "TakeOwnership_$(Get-Date -Format 'yyyyMMdd_HHmmss').log")
    } else {
        $LogPath = [System.IO.Path]::GetFullPath($LogPath)
    }
    New-DirectoryIfMissing ([System.IO.Path]::GetDirectoryName($OutputCsv))
    New-DirectoryIfMissing ([System.IO.Path]::GetDirectoryName($LogPath))

    # --- Admin check (Windows-only; silently skipped on other platforms) ---
    $isAdmin = $true
    if ($IsWindows -or $PSVersionTable.Platform -eq 'Win32NT' -or -not $PSVersionTable.ContainsKey('Platform')) {
        try {
            $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator
            )
        } catch {
            $isAdmin = $true   # Cannot determine - assume admin to avoid spurious warnings
        }
    }
    if (-not $isAdmin) {
        Write-Status 'Not running as Administrator. Takeown may fail for protected files.' -Level 'WARNING'
        Write-Status 'Right-click PowerShell and select "Run as administrator".' -Level 'WARNING'
    }

    Write-Status "Starting take-ownership recovery"
    Write-Status "CSV:    $CsvPath"
    Write-Status "Output: $OutputCsv"
    Write-Status "Log:    $LogPath"

    # --- Read failures ---
    $failedFiles     = Import-Csv -Path $CsvPath -Encoding UTF8
    $totalCount      = @($failedFiles).Count
    $processedCount  = 0
    $succeededCount  = 0
    $stillFailedCount = 0
    $results         = [System.Collections.Generic.List[object]]::new()

    if ($totalCount -eq 0) {
        Write-Status "Input CSV has no rows - nothing to do." -Level 'WARNING'
    }

    # --- Per-file: takeown + icacls ---
    # try/catch ensures a single file's exception does NOT stop the loop.
    foreach ($file in $failedFiles) {
        $processedCount++
        $filePath = $file.FilePath

        if ($processedCount % 100 -eq 0 -or $processedCount -eq 1) {
            Write-Status "Progress: [$processedCount/$totalCount] Processing..."
        }

        $status = 'Unknown'
        $statusDetail = ''

        # Step 1: take ownership
        $takeownErrorReason = $null
        try {
            $takeownPath = Get-LongPath $filePath
            $r = Invoke-NativeCommand -FileName 'takeown.exe' -Arguments @('/f', $takeownPath, '/A')
            if ($r.ExitCode -ne 0) {
                $takeownErrorReason = (Get-ErrorReason -ExitCode $r.ExitCode -ErrorOutput ($r.Output + "`n" + $r.Error))
                Write-Status "  [$processedCount/$totalCount] $filePath -> FAILED (takeown: $takeownErrorReason)" -Level 'ERROR'
                $stillFailedCount++
                $status = 'Failed'
                $statusDetail = "Takeown failed: $takeownErrorReason"
            } else {
                # Step 2: re-apply inheritance
                $icaclsPath = Get-LongPath $filePath
                $r2 = Invoke-NativeCommand -FileName 'icacls.exe' -Arguments @($icaclsPath, '/inheritance:e', '/C')
                if ($r2.ExitCode -eq 0) {
                    Write-Status "  [$processedCount/$totalCount] $filePath -> FIXED"
                    $succeededCount++
                    $status = 'Fixed'
                } else {
                    $icaclsErrorReason = (Get-ErrorReason -ExitCode $r2.ExitCode -ErrorOutput ($r2.Output + "`n" + $r2.Error))
                    Write-Status "  [$processedCount/$totalCount] $filePath -> FAILED (icacls: $icaclsErrorReason after takeown)" -Level 'ERROR'
                    $stillFailedCount++
                    $status = 'Failed'
                    $statusDetail = "Inheritance restore failed after takeown: $icaclsErrorReason"
                }
            }
        } catch {
            Write-Status "  [$processedCount/$totalCount] $filePath -> EXCEPTION: $($_.Exception.Message)" -Level 'ERROR'
            $stillFailedCount++
            $status = 'Failed'
            $statusDetail = "Exception: $($_.Exception.Message)"
        }

        $results.Add([PSCustomObject]@{
            FilePath      = $filePath
            FileName      = $file.FileName
            ParentFolder  = $file.ParentFolder
            OriginalError = $file.ErrorReason
            Status        = $status
            StatusDetail  = $statusDetail
            Timestamp     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        })
    }

    # --- Write results CSV (with header even when empty) ---
    if ($results.Count -gt 0) {
        $results | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8 -Force
    } else {
        '"FilePath","FileName","ParentFolder","OriginalError","Status","StatusDetail","Timestamp"' |
            Set-Content -Path $OutputCsv -Encoding UTF8 -Force
    }

    # --- Summary ---
    Write-Section 'Summary'
    Write-Status "Total processed:    $processedCount"
    Write-Status "Fixed:              $succeededCount"
    Write-Status "Still failed:       $stillFailedCount"
    Write-Status "Results:            $OutputCsv"
    Write-Status 'Done.'
}
#endregion

# --- Invocation guard ---
# Run main only when the script is invoked directly, not when dot-sourced
# for testing (in which case the test invokes Invoke-TakeOwnership).
if ($MyInvocation.InvocationName -ne '.') {
    $scriptErrors = $null
    Invoke-TakeOwnership @PSBoundParameters -ErrorVariable scriptErrors
    if ($scriptErrors) { exit 1 }
}
