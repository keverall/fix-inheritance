<#
.SYNOPSIS
    Fixes inheritance on all files and subfolders, logging failures to CSV.

.DESCRIPTION
    Runs icacls inheritance:e /T on a target path, catches failures, and outputs
    a CSV with full paths of files that failed inheritance takeover.
    The CSV can be fed to Take-Ownership scripts for recovery.
    Handles long paths (>256 chars) and special characters.

.PARAMETER TargetPath
    The root folder path to fix inheritance on (e.g., R:\r_vs13_d2\ftcregfin\)

.PARAMETER OutputPath
    Path for the output CSV file. Default: .\FailedInheritance.csv

.EXAMPLE
    .\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin"

.EXAMPLE
    .\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin" -OutputPath "C:\reports\failures"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TargetPath,

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$OutputPath = ".\FailedInheritance"
)

# Validate target path exists
if (-not (Test-Path -Path $TargetPath)) {
    Write-Error "Target path does not exist: $TargetPath"
    exit 1
}

# Resolve output path
$OutputCsv = [System.IO.Path]::GetFullPath("$OutputPath.csv")

Write-Host "Starting inheritance fix on: $TargetPath"
Write-Host "Output CSV:   $OutputCsv"
Write-Host ""

# Helper: classify icacls error output
function Get-ErrorReason {
    param(
        [int]$ExitCode,
        [string]$ErrorOutput
    )
    if ($ErrorOutput -match "Access is denied") {
        return "Access Denied - requires ownership change"
    }
    if ($ErrorOutput -match "not found") {
        return "File not found"
    }
    if ($ErrorOutput -match "is in use") {
        return "File in use"
    }
    if ($ErrorOutput -match "invalid") {
        return "Invalid path or filename"
    }
    if ($ExitCode -eq 5) {
        return "Access Denied (HRESULT: 0x80070005)"
    }
    return "Unknown error (exit code: $ExitCode)"
}

# Helper: record a failure
function Add-Failure {
    param(
        [string]$FullPath,
        [string]$ErrorReason,
        [System.Collections.Generic.List[object]]$FailedItems
    )
    $failedItems.Add([PSCustomObject]@{
        FilePath     = $fullPath
        FileName     = [System.IO.Path]::GetFileName($fullPath)
        ParentFolder = [System.IO.Path]::GetDirectoryName($fullPath)
        FolderName   = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($fullPath))
        ErrorReason  = $errorReason
        PathLength   = $fullPath.Length
        IsLongPath   = ($fullPath.Length -gt 256)
        Timestamp    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

# Collect all files and folders
$failedItems = [System.Collections.Generic.List[object]]::new()
$processedCount = 0
$failedCount = 0

try {
    $allItems = Get-ChildItem -LiteralPath $TargetPath -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-Warning "Error enumerating path: $_"
    $allItems = @()
}

$totalItems = ($allItems | Measure-Object).Count
Write-Host "Found $totalItems items to process"
Write-Host ""

# Try bulk icacls first (fast path for accessible files)
Write-Host "Attempting bulk icacls operation on root..."
try {
    $bulkResult = & icacls.exe $TargetPath /inheritance:e /T /C 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Bulk operation completed successfully."
        Write-Host "No failures detected."

        # Write empty CSV with header
        "FilePath,FileName,ParentFolder,FolderName,ErrorReason,PathLength,IsLongPath,Timestamp" | Set-Content -Path $OutputCsv -Encoding UTF8
        Write-Host "CSV: $OutputCsv"
        exit 0
    }
    Write-Host "Bulk operation completed with errors (exit code: $LASTEXITCODE)"
    Write-Host "Individual processing will identify specific failures..."
} catch {
    Write-Host "Bulk operation failed: $_"
    Write-Host "Falling back to individual file processing..."
}

Write-Host ""
Write-Host "Processing items individually..."
Write-Host ""

foreach ($item in $allItems) {
    $processedCount++
    $fullPath = $item.FullName

    if ($processedCount % 100 -eq 0) {
        Write-Host "Processed: $processedCount / $totalItems (Failures: $failedCount)"
    }

    try {
        $errorOutput = & icacls.exe $fullPath /inheritance:e /C 2>&1

        if ($LASTEXITCODE -ne 0) {
            Add-Failure -FullPath $fullPath -ErrorReason (Get-ErrorReason -ExitCode $LASTEXITCODE -ErrorOutput ($errorOutput -join " ")) -FailedItems $failedItems
            $failedCount++
        }
    } catch {
        Add-Failure -FullPath $fullPath -ErrorReason "Exception: $($_.Exception.Message)" -FailedItems $failedItems
        $failedCount++
    }
}

# Write CSV
$failedItems | Select-Object FilePath, FileName, ParentFolder, FolderName, ErrorReason, PathLength, IsLongPath, Timestamp | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8 -Force

# Console summary
Write-Host ""
Write-Host "=========================================="
Write-Host "Summary"
Write-Host "=========================================="
Write-Host "Total items processed: $processedCount"
Write-Host "Failed items:          $failedCount"
Write-Host "CSV:                   $OutputCsv"

if ($failedCount -gt 0) {
    Write-Host ""
    Write-Host "Error breakdown:"
    $failedItems | Group-Object ErrorReason | Sort-Object Count -Descending | Format-Table Count, Name -AutoSize
    Write-Host "Use Take-Ownership.ps1 or Take-Ownership.bat to fix failed items."
}

Write-Host ""
Write-Host "Done."
