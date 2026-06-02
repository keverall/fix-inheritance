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

.Parameter LogPath
    Optional path for the log file. Default: same as OutputPath with .log extension
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TargetPath,

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$OutputPath = ".\FailedInheritance",

    [Parameter(Mandatory = $false, Position = 2)]
    [string]$LogPath = ""
)

# Resolve paths
$OutputCsv = [System.IO.Path]::GetFullPath("$OutputPath.csv")
if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = [System.IO.Path]::GetFullPath("$OutputPath.log")
} else {
    $LogPath = [System.IO.Path]::GetFullPath($LogPath)
}

# Ensure output directory exists
$outputDir = [System.IO.Path]::GetDirectoryName($OutputCsv)
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
$logDir = [System.IO.Path]::GetDirectoryName($LogPath)
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try {
        Add-Content -Path $script:LogPath -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

# Validate target path exists
if (-not (Test-Path -LiteralPath $TargetPath)) {
    Write-Log "Target path does not exist: $TargetPath" -Level "ERROR"
    Write-Error "Target path does not exist: $TargetPath"
    exit 1
}

if (Test-Path -LiteralPath $OutputCsv -PathType Leaf) {
    Write-Log "Output file already exists and will be overwritten: $OutputCsv" -Level "WARNING"
}

Write-Log "Starting inheritance fix on: $TargetPath"
Write-Log "Output CSV:   $OutputCsv"
Write-Log "Log file:     $LogPath"
Write-Host ""
try { Add-Content -Path $LogPath -Value "" -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
function Get-ErrorReason {
    param(
        [int]$ExitCode,
        [string]$ErrorOutput
    )
    if ($ErrorOutput -match "Access is denied") {
        return "Access Denied - requires ownership change"
    }
    if ($ErrorOutput -match "path not found") {
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
    Write-Log "Error enumerating path: $_" -Level "WARNING"
    $allItems = @()
}

$totalItems = ($allItems | Measure-Object).Count
Write-Log "Found $totalItems items to process"
""

# Try bulk icacls first (fast path for accessible files)
Write-Host "Attempting bulk icacls operation on root..."
Write-Log "Attempting bulk icacls operation on root..."
try {
    & icacls.exe $TargetPath /inheritance:e /T /C 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Bulk operation completed successfully."
        Write-Log "Bulk operation completed successfully."
        Write-Host "No failures detected."
        Write-Log "No failures detected."
        "FilePath,FileName,ParentFolder,FolderName,ErrorReason,PathLength,IsLongPath,Timestamp" | Set-Content -Path $OutputCsv -Encoding UTF8
        Write-Host "CSV: $OutputCsv"
        Write-Log "CSV: $OutputCsv"
        Write-Log "Script completed successfully (bulk path)."
        exit 0
    }
    Write-Host "Bulk operation completed with errors (exit code: $LASTEXITCODE)"
    Write-Log "Bulk operation completed with errors (exit code: $LASTEXITCODE)"
    Write-Host "Individual processing will identify specific failures..."
    Write-Log "Individual processing will identify specific failures..."
} catch {
    Write-Log "Bulk operation failed: $_. Continuing with individual processing..."
}

Write-Host ""
Write-Host "Processing items individually..."
Write-Host ""

foreach ($item in $allItems) {
    $processedCount++
    $fullPath = $item.FullName

    if ($processedCount % 100 -eq 0) {
        Write-Host "Processed: $processedCount / $totalItems (Failures: $failedCount)"
        Write-Log "Progress: Processed $processedCount / $totalItems (Failures: $failedCount)"
    }

    try {
        $errorOutput = & icacls.exe $fullPath /inheritance:e /C 2>&1

        if ($LASTEXITCODE -ne 0) {
            Add-Failure -FullPath $fullPath -ErrorReason (Get-ErrorReason -ExitCode $LASTEXITCODE -ErrorOutput $errorOutput) -FailedItems $failedItems
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
Write-Log "=========================================="
Write-Host "Summary"
Write-Log "Summary"
Write-Host "=========================================="
Write-Log "=========================================="

Write-Host "Total items processed: $processedCount"
Write-Log "Total items processed: $processedCount"
Write-Host "Failed items:          $failedCount"
Write-Log "Failed items:          $failedCount"
Write-Host "CSV:                   $OutputCsv"
Write-Log "CSV:                   $OutputCsv"

if ($failedCount -gt 0) {
    Write-Host ""
    Write-Host "Error breakdown:"
    $failedItems | Group-Object ErrorReason | Sort-Object Count -Descending | Format-Table Count, Name -AutoSize
    Write-Host "Use Take-Ownership.ps1 or Take-Ownership.bat to fix failed items."
}

Write-Host ""
Write-Host "Done."
Write-Log "Done."
