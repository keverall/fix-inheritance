<#
.SYNOPSIS
    Takes ownership of files listed in CSV and re-applies inheritance.

.DESCRIPTION
    Reads the FailedInheritance.csv output from Fix-Inheritance.ps1,
    takes ownership of each file using takeown, then re-runs icacls
    to enable inheritance. Requires Administrator privileges.

.PARAMETER CsvPath
    Path to the FailedInheritance.csv file

.PARAMETER OutputCsv
    Path for results CSV. Defaults to Results_YYYYMMDD_HHMMSS.csv next to input.

.EXAMPLE
    .\Take-Ownership.ps1 -CsvPath "C:\temp\FailedInheritance.csv"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputCsv = ""
)

# Validate CSV exists
if (-not (Test-Path -Path $CsvPath)) {
    Write-Error "CSV file not found: $CsvPath"
    exit 1
}

# Default output path next to input CSV
if ([string]::IsNullOrEmpty($OutputCsv)) {
    $csvDir  = [System.IO.Path]::GetDirectoryName($CsvPath)
    $csvBase = [System.IO.Path]::GetFileNameWithoutExtension($CsvPath)
    $OutputCsv = [System.IO.Path]::Combine($csvDir, "Results_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv")
}
$OutputCsv = [System.IO.Path]::GetFullPath($OutputCsv)

# Admin check
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Warning "Not running as Administrator. Takeown may fail for protected files."
    Write-Warning "Right-click PowerShell and select 'Run as administrator'."
    Write-Host ""
}

Write-Host "=========================================="
Write-Host "Take Ownership Script"
Write-Host "=========================================="
Write-Host "CSV:    $CsvPath"
Write-Host "Output: $OutputCsv"
Write-Host ""

$failedFiles = Import-Csv -Path $CsvPath -Encoding UTF8
$totalCount  = ($failedFiles | Measure-Object).Count
$processedCount = 0
$succeededCount = 0
$stillFailedCount = 0
$results = [System.Collections.Generic.List[object]]::new()

foreach ($file in $failedFiles) {
    $processedCount++
    $filePath = $file.FilePath

    if ($processedCount % 100 -eq 0 -or $processedCount -eq 1) {
        Write-Host "[$processedCount/$totalCount] Processing..."
    }

    $status = "Unknown"
    $statusDetail = ""

    # Step 1: Take ownership
    $takeownOut = & takeown.exe /f $filePath /A 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  -> FAILED (takeown exit $LASTEXITCODE)" -ForegroundColor Red
        $stillFailedCount++
        $status = "Failed"
        $statusDetail = "Takeown failed (exit $LASTEXITCODE)"
    } else {
        # Step 2: Re-apply inheritance
        $icaclsOut = & icacls.exe $filePath /inheritance:e /C 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  -> FIXED" -ForegroundColor Green
            $succeededCount++
            $status = "Fixed"
        } else {
            Write-Host "  -> FAILED (icacls exit $LASTEXITCODE)" -ForegroundColor Red
            $stillFailedCount++
            $status = "Failed"
            $statusDetail = "Inheritance restore failed after ownership"
        }
    }

    $results.Add([PSCustomObject]@{
        FilePath      = $filePath
        FileName      = $file.FileName
        ParentFolder  = $file.ParentFolder
        OriginalError = $file.ErrorReason
        Status        = $status
        StatusDetail  = $statusDetail
        Timestamp     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

# Write results
$results | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8 -Force

# Summary
Write-Host ""
Write-Host "=========================================="
Write-Host "Total processed:   $processedCount"
Write-Host "Fixed:             $succeededCount"
Write-Host "Still failed:      $stillFailedCount"
Write-Host "=========================================="
Write-Host "Results: $OutputCsv"
Write-Host ""
Write-Host "Done."
