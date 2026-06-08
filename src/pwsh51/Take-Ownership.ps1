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
        icacls verbatim. On PowerShell 7+ this uses
        ProcessStartInfo.ArgumentList; on Windows PowerShell 5.1 it
        falls back to a manually-quoted Arguments string (see
        Invoke-NativeCommand for the rationale).
      * Paths longer than Windows MAX_PATH (260) are passed with the
        \\?\ long-path prefix.
      * Exit code (HRESULT) is the primary signal for classification.
      * All activity is written to a log file (same format as
        Fix-Inheritance.ps1) so post-mortem is possible.

.PARAMETER CsvPath
    Path to the FailedInheritance.csv file in output/ folder under root directory

.PARAMETER OutputCsv
    Path for results CSV. Default: in output/ folder under root directory

.PARAMETER LogPath
    Path for the log file. Default: in logs/ folder under root directory
    
.EXAMPLE
    .\Take-Ownership.ps1 -CsvPath "./output/FailedInheritance.csv"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputCsv = $null,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = $null
)

# Version detection - robust fallback for environments where $PSScriptRoot is unavailable
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) { $ScriptRoot = $MyInvocation.PSScriptRoot }
if (-not $ScriptRoot) { $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptRoot) { $ScriptRoot = $PWD.Path }
if ($ScriptRoot -and (Split-Path $ScriptRoot -Leaf) -eq 'pwsh51') {
    $ScriptRoot = Split-Path $ScriptRoot -Parent
}

. (Join-Path $PSScriptRoot '_Common.ps1')

function Invoke-TakeOwnership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CsvPath,
        [string]$OutputCsv = $null,
        [string]$LogPath = $null
    )

    if (-not (Test-Path -LiteralPath $CsvPath)) {
        Write-Error "CSV file not found: $CsvPath"
        return
    }
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $paths = Resolve-OutputPaths -OutputCsv $OutputCsv -LogPath $LogPath -DefaultCsvName "Results_$timestamp.csv" -DefaultLogName 'TakeOwnership.log'
    $OutputCsv = $paths.OutputCsv
    $LogPath = $paths.LogPath


    $isAdmin = $true
    if ($IsWindows -or $PSVersionTable.Platform -eq 'Win32NT' -or -not $PSVersionTable.ContainsKey('Platform')) {
        try {
            $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator
            )
        } catch {
            $isAdmin = $true
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

    $failedFiles     = Import-Csv -Path $CsvPath -Encoding UTF8
    $totalCount      = @($failedFiles).Count
    $processedCount  = 0
    $succeededCount  = 0
    $stillFailedCount = 0
    $results         = [System.Collections.Generic.List[object]]::new()

    if ($totalCount -eq 0) {
        Write-Status "Input CSV has no rows - nothing to do." -Level 'WARNING'
    }

    foreach ($file in $failedFiles) {
        $processedCount++
        $filePath = $file.FilePath

        if ($processedCount % 100 -eq 0 -or $processedCount -eq 1) {
            Write-Status "Progress: [$processedCount/$totalCount] Processing..."
        }

        $status = 'Unknown'
        $statusDetail = ''

        $takeownErrorReason = $null
        try {
            $takeownPath = Get-LongPath $filePath
            $r = Invoke-NativeCommand -FileName 'takeown.exe' -Arguments @('/f', $takeownPath)
            if ($r.ExitCode -ne 0) {
                $takeownErrorReason = (Get-ErrorReason -ExitCode $r.ExitCode -ErrorOutput ($r.Output + "`n" + $r.Error))
                Write-Status "  [$processedCount/$totalCount] $filePath -> FAILED (takeown: $takeownErrorReason)" -Level 'ERROR'
                $stillFailedCount++
                $status = 'Failed'
                $statusDetail = "Takeown failed: $takeownErrorReason"
            } else {
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
            FolderName    = $file.FolderName
            OriginalError = $file.ErrorReason
            Status        = $status
            StatusDetail  = $statusDetail
            Timestamp     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        })
    }

    if ($results.Count -gt 0) {
        $results | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8 -Force
    } else {
        '"FilePath","FileName","ParentFolder","FolderName","OriginalError","Status","StatusDetail","Timestamp"' |
            Set-Content -Path $OutputCsv -Encoding UTF8 -Force
    }

    Write-Section 'Summary'
    Write-Status "Total processed:    $processedCount"
    Write-Status "Fixed:              $succeededCount"
    Write-Status "Still failed:       $stillFailedCount"
    Write-Status "Results:            $OutputCsv"
    Write-Status 'Done.'
}

if ($MyInvocation.InvocationName -ne '.') {
    $scriptErrors = $null
    Invoke-TakeOwnership @PSBoundParameters -ErrorVariable scriptErrors
    if ($scriptErrors) { exit 1 }
}
