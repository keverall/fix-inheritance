<#
.SYNOPSIS
    Fixes inheritance on all files and subfolders, logging failures to CSV.

.DESCRIPTION
    Runs icacls inheritance:e /T /C /Q on a target path, parses the output
    for failures, and writes them to a CSV that can be fed to Take-Ownership.ps1
    for recovery.

      * Uses a single bulk icacls operation for performance (minutes instead of weeks).
      * The /Q (quiet) flag suppresses success messages so only failures are parsed.
      * All failures from icacls output are captured and recorded in the failure CSV.
      * Paths longer than Windows MAX_PATH (260) are passed with the \\?\ long-path
        prefix that icacls requires.
      * Export-Csv handles CSV escaping of commas, quotes, and newlines in filenames.
      * Exit code (HRESULT) is the primary signal for error classification,
        so behaviour is identical on non-English Windows installations.

.PARAMETER TargetPath
    The root folder path to fix inheritance on (e.g., R:\r_vs13_d2\ftcregfin\)

.PARAMETER OutputPath
    Path for results CSV. Default: in output/ folder under root directory

.PARAMETER LogPath
    Path for the log file. Default: in logs/ folder under root directory
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

# Version detection - robust fallback for environments where $PSScriptRoot is unavailable
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) { $ScriptRoot = $MyInvocation.PSScriptRoot }
if (-not $ScriptRoot) { $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptRoot) { $ScriptRoot = $PWD.Path }
if ($ScriptRoot -and (Split-Path $ScriptRoot -Leaf) -eq 'pwsh51') {
    $ScriptRoot = Split-Path $ScriptRoot -Parent
}

# PS7+ detection (PSEdition is the most reliable signal)
if ($PSVersionTable.PSEdition -ne 'Core' -and $PSVersionTable.PSVersion.Major -lt 6) {
    $pwsh51Script = [System.IO.Path]::Combine($ScriptRoot, "pwsh51", "Fix-Inheritance.ps1")
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

# Display clear PowerShell version banner
$psVer = if ($PSVersionTable.PSVersion) { $PSVersionTable.PSVersion.ToString() } else { "Unknown" }
$psEd = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { "Desktop" }
Write-Host "****************************************************" -ForegroundColor Cyan
Write-Host "* PowerShell Version: $psVer ($psEd)" -ForegroundColor Cyan
Write-Host "****************************************************" -ForegroundColor Cyan
Write-Host ""

. (Join-Path $ScriptRoot '_Common.ps1')

function Invoke-FixInheritance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [string]$OutputPath = $null,
        [string]$LogPath = $null
    )
    $paths = Resolve-OutputPaths -OutputCsv $OutputPath -LogPath $LogPath -DefaultCsvName 'FailedInheritance.csv' -DefaultLogName 'FailedInheritance.log'
    $OutputCsv = $paths.OutputCsv
    $LogPath = $paths.LogPath

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

    Write-Status 'Running bulk icacls operation on target path...'
    try {
        $longPathArg = Get-LongPath $TargetPath
        
        # /Q suppresses success messages so we only get failures and the summary line
        $r = Invoke-NativeCommand -FileName 'icacls.exe' -Arguments @($longPathArg, '/inheritance:e', '/T', '/C', '/Q') -ThrowOnError
        
        $combined = "$($r.Output)`n$($r.Error)"
        $lines = $combined -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        
         $summaryLine = $null
         foreach ($line in $lines) {
             # Parse the icacls error format: "Path: Error message"
              if ($line -match '^((?:[a-zA-Z]:|\\\\).*?):\s+(.*)$') {
                  $FilePath = $Matches[1].Trim()
                  $rawReason = $Matches[2].Trim()
                  # Normalize the raw icacls message into a categorized error reason
                  $failReason = Get-ErrorReason -ExitCode 0 -ErrorOutput $rawReason
                  Add-Failure -FilePath $FilePath -ErrorReason $failReason -FailedItems $failedItems
                  $failedCount++
              } else {
                  # Check if this line is the summary line (processed files, or contains numbers)
                  if ($line -match 'processed.*files' -or $line -match '\d+.*?\d+') {
                      $summaryLine = $line
                  } else {
                      # Unrecognized error format
                      Add-Failure -FilePath $TargetPath -ErrorReason "icacls output: $line" -FailedItems $failedItems
                      $failedCount++
                  }
              }
          }
         
        if ($r.ExitCode -ne 0 -and $failedCount -eq 0) {
            Add-Failure -FilePath $TargetPath `
                -ErrorReason "icacls failed with exit code $($r.ExitCode) but no specific file errors were parsed." `
                -FailedItems $failedItems
            $failedCount++
        }
    } catch {
        Write-Status "Bulk operation failed: $_" -Level 'WARNING'
        Add-Failure -FilePath $TargetPath `
            -ErrorReason "Bulk operation exception: $($_.Exception.Message)" `
            -FailedItems $failedItems
        $failedCount++
    }

    try {
        Write-FailureCsv -FailedItems $failedItems -OutputCsv $OutputCsv
    } catch {
        Write-Status "FATAL: failed to write CSV at $OutputCsv : $_" -Level 'ERROR'
        Write-Error $_
    }

    Write-Section 'Summary'
    Write-Status "Total failed items:     $failedCount"
    if ($summaryLine) {
        Write-Status "icacls summary:         $summaryLine"
    }
    Write-Status "CSV:                    $OutputCsv"
    
    if ($failedCount -gt 0) {
        Write-Status 'Error breakdown:'
        $failedItems | Group-Object ErrorReason | Sort-Object Count -Descending | ForEach-Object {
            Write-Status "  - $($_.Count) x $($_.Name)"
        }
        Write-Status 'Use Take-Ownership.ps1 to fix failed items.'
    } else {
        Write-Status 'No failures detected - inheritance successfully applied to all items.'
    }

    Write-Status 'Done.'
    return ($failedCount -gt 0)
}

if ($MyInvocation.InvocationName -ne '.') {
    $scriptErrors = $null
    $hasFailures = Invoke-FixInheritance @PSBoundParameters -ErrorVariable scriptErrors
    if ($scriptErrors) { exit 1 }
    if ($hasFailures) { exit 2 }
}
