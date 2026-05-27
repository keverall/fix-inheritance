<#
.SYNOPSIS
    Fixes inheritance on all files and subfolders, logging failures to CSV and Excel.

.DESCRIPTION
    Runs icacls inheritance:e /T on a target path, catches failures, and outputs
    both a CSV and an Excel workbook with full paths of files that failed inheritance takeover.
    Handles long paths (>256 chars) and special characters.

.PARAMETER TargetPath
    The root folder path to fix inheritance on (e.g., R:\r_vs13_d2\ftcregfin\)

.PARAMETER OutputPath
    Base path for output files. Creates both .csv and .xlsx from this name.
    Default: .\FailedInheritance

.EXAMPLE
    .\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin"

.EXAMPLE
    .\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin" -OutputPath "C:\reports\MyReport"

.NOTES
    Always produces both .csv and .xlsx files.
    Excel output requires the ImportExcel module:
    Install-Module -Name ImportExcel -Scope CurrentUser -Force
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TargetPath,

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$OutputPath = ".\FailedInheritance"
)

# Enable long path support in PowerShell
$null = [System.Environment]::SetEnvironmentVariable("DOTNET_SYSTEM_IO_USELONGPATHS", "true", "Process")

# Validate target path exists
if (-not (Test-Path -Path $TargetPath)) {
    Write-Error "Target path does not exist: $TargetPath"
    exit 1
}

# Resolve output paths - always produce both CSV and Excel
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$OutputCsv  = "$OutputPath.csv"
$OutputXlsx = "$OutputPath.xlsx"

Write-Host "Starting inheritance fix on: $TargetPath"
Write-Host "Output CSV:   $OutputCsv"
Write-Host "Output Excel: $OutputXlsx"
Write-Host ""

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

# First, try icacls on the entire tree (fast path)
Write-Host "Attempting bulk icacls operation on root..."
try {
    $bulkResult = & icacls.exe "`"$TargetPath`"" /inheritance:e /T /C 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Bulk operation completed successfully."
        Write-Host "No failures detected."
        Write-Host "CSV:   $OutputCsv (header only)"
        Write-Host "Excel: $OutputXlsx (summary only)"

        # Write CSV header only
        "FilePath,FileName,ParentFolder,FolderName,ErrorReason,PathLength,IsLongPath,Timestamp" | Set-Content -Path $OutputCsv -Encoding UTF8

        # Write summary-only Excel
        $summaryData = @(
            [PSCustomObject]@{ Metric = "Target Path";       Value = $TargetPath }
            [PSCustomObject]@{ Metric = "Total Items";       Value = $totalItems }
            [PSCustomObject]@{ Metric = "Failed Items";      Value = 0 }
            [PSCustomObject]@{ Metric = "Success Rate";      Value = "100%" }
            [PSCustomObject]@{ Metric = "Timestamp";         Value = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") }
        )
        $pkg = $summaryData | Export-Excel -Path $OutputXlsx -WorksheetName "Summary" -AutoSize -TableName "Summary" -PassThru
        # Add empty tabs so structure is consistent
        $null = [PSCustomObject]@{ Note = "No failures" } | Export-Excel -ExcelPackage $pkg -WorksheetName "Errors by Folder" -PassThru
        $null = [PSCustomObject]@{ Note = "No failures" } | Export-Excel -ExcelPackage $pkg -WorksheetName "All Failures" -PassThru
        $null = [PSCustomObject]@{ Note = "No long paths" } | Export-Excel -ExcelPackage $pkg -WorksheetName "Long Paths" -PassThru
        Close-Excel -ExcelPackage $pkg -Save
        exit 0
    } else {
        Write-Host "Bulk operation completed with errors (exit code: $LASTEXITCODE)"
        Write-Host "Individual processing will identify specific failures..."
    }
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

    # icacls handles long paths natively on Windows 10+ when LongPathsEnabled is set
    # Pass path directly; icacls will handle it
    $icaclsPath = $fullPath

    try {
        $errorOutput = & icacls.exe "`"$icaclsPath`"" /inheritance:e /C 2>&1

        if ($LASTEXITCODE -ne 0) {
            $errorReason = "Unknown error (exit code: $LASTEXITCODE)"
            $errorStr = $errorOutput -join " "

            if ($errorStr -match "Access is denied") {
                $errorReason = "Access Denied - requires ownership change"
            } elseif ($errorStr -match "not found") {
                $errorReason = "File not found"
            } elseif ($errorStr -match "is in use") {
                $errorReason = "File in use"
            } elseif ($errorStr -match "invalid") {
                $errorReason = "Invalid path or filename"
            } elseif ($LASTEXITCODE -eq 5) {
                $errorReason = "Access Denied (HRESULT: 0x80070005)"
            }

            $parentFolder = [System.IO.Path]::GetDirectoryName($fullPath)
            $folderName   = [System.IO.Path]::GetFileName($parentFolder)
            $pathLength   = $fullPath.Length
            $fileName     = [System.IO.Path]::GetFileName($fullPath)

            $failedItems.Add([PSCustomObject]@{
                FilePath     = $fullPath
                FileName     = $fileName
                ParentFolder = $parentFolder
                FolderName   = $folderName
                ErrorReason  = $errorReason
                PathLength   = $pathLength
                IsLongPath   = ($pathLength -gt 256)
                Timestamp    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            })

            $failedCount++
        }
    } catch {
        $parentFolder = [System.IO.Path]::GetDirectoryName($fullPath)
        $folderName   = [System.IO.Path]::GetFileName($parentFolder)
        $pathLength   = $fullPath.Length
        $fileName     = [System.IO.Path]::GetFileName($fullPath)

        $failedItems.Add([PSCustomObject]@{
            FilePath     = $fullPath
            FileName     = $fileName
            ParentFolder = $parentFolder
            FolderName   = $folderName
            ErrorReason  = "Exception: $($_.Exception.Message)"
            PathLength   = $pathLength
            IsLongPath   = ($pathLength -gt 256)
            Timestamp    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        })
        $failedCount++
    }
}

# Write CSV
$failedItems | Select-Object FilePath, FileName, ParentFolder, FolderName, ErrorReason, PathLength, IsLongPath, Timestamp | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8 -Force

# Build Excel workbook
$pkg = $failedItems | Export-Excel -Path $OutputXlsx -WorksheetName "All Failures" -AutoSize -FreezeTopRow -TableName "AllFailures" -PassThru

# Summary tab
$summaryData = @(
    [PSCustomObject]@{ Metric = "Target Path";              Value = $TargetPath }
    [PSCustomObject]@{ Metric = "Total Items Scanned";       Value = $totalItems }
    [PSCustomObject]@{ Metric = "Failed Items";              Value = $failedCount }
    [PSCustomObject]@{ Metric = "Successful Items";          Value = ($totalItems - $failedCount) }
    [PSCustomObject]@{ Metric = "Success Rate";              Value = if ($totalItems -gt 0) { "{0:P2}" -f (($totalItems - $failedCount) / $totalItems) } else { "N/A" } }
    [PSCustomObject]@{ Metric = "Long Path Files (>256)";    Value = ($failedItems | Where-Object { $_.IsLongPath }).Count }
    [PSCustomObject]@{ Metric = "Report Generated";          Value = Get-Date -Format "yyyy-MM-dd HH:mm:ss" }
)
$pkg = $summaryData | Export-Excel -ExcelPackage $pkg -WorksheetName "Summary" -AutoSize -TableName "Summary" -PassThru -ClearSheet

# Error breakdown
$errorBreakdown = $failedItems | Group-Object ErrorReason | Sort-Object Count -Descending | Select-Object @{Name="Error Type"; Expression={$_.Name}}, Count
if ($errorBreakdown.Count -gt 0) {
    $pkg = $errorBreakdown | Export-Excel -ExcelPackage $pkg -WorksheetName "Summary" -StartRow 12 -AutoSize -TableName "ErrorBreakdown" -PassThru
}

if ($failedItems.Count -gt 0) {
    # Errors by Folder
    $folderSummary = $failedItems | Group-Object ParentFolder | Sort-Object Count -Descending | Select-Object @{Name="Folder"; Expression={$_.Name}}, @{Name="File Count"; Expression={$_.Count}}, @{Name="Error Types"; Expression={($_.Group | Select-Object -ExpandProperty ErrorReason -Unique) -join ", "}}

    $pkg = $folderSummary | Export-Excel -ExcelPackage $pkg -WorksheetName "Errors by Folder" -AutoSize -TableName "FolderSummary" -FreezeTopRow -PassThru -ClearSheet

    $totalRow = $folderSummary | Measure-Object -Property "File Count" -Sum
    $pkg = [PSCustomObject]@{ Folder = "TOTAL"; "File Count" = $totalRow.Sum; "Error Types" = "-" } | Export-Excel -ExcelPackage $pkg -WorksheetName "Errors by Folder" -StartRow ($folderSummary.Count + 3) -AutoSize -PassThru

    # Conditional formatting
    Add-ConditionalFormatting -Address "B2:B100" -Worksheet $pkg.Workbook.Worksheets["Errors by Folder"] -RuleType "GreaterThan" -ConditionValue 50 -ForegroundColor White -BackgroundColor Red
    Add-ConditionalFormatting -Address "B2:B100" -Worksheet $pkg.Workbook.Worksheets["Errors by Folder"] -RuleType "Between" -ConditionValue 10 -ConditionValue2 50 -ForegroundColor Black -BackgroundColor Yellow

    # Long Paths tab
    $longPaths = $failedItems | Where-Object { $_.IsLongPath } | Select-Object FilePath, PathLength, FileName, ErrorReason, ParentFolder
    if ($longPaths.Count -gt 0) {
        $pkg = $longPaths | Export-Excel -ExcelPackage $pkg -WorksheetName "Long Paths" -AutoSize -FreezeTopRow -TableName "LongPaths" -PassThru -ClearSheet
    }

    # Pie chart on Summary
    $chart = New-ExcelChartDefinition -XRange "A2:A10" -YRange "B2:B10" -ChartType Pie -NoLegend -Title "Error Distribution" -Width 500 -Height 400
    Add-ExcelChart -Worksheet $pkg.Workbook.Worksheets["Summary"] -ChartDefinition $chart | Out-Null
}

Close-Excel -ExcelPackage $pkg -Save

# Console output
if ($failedItems.Count -gt 0) {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "Summary"
    Write-Host "=========================================="
    Write-Host "Total items processed: $processedCount"
    Write-Host "Failed items:          $failedCount"
    Write-Host ""
    Write-Host "CSV:   $OutputCsv"
    Write-Host "Excel: $OutputXlsx"
    Write-Host ""
    Write-Host "Error breakdown:"
    $failedItems | Group-Object ErrorReason | Sort-Object Count -Descending | Format-Table Count, Name -AutoSize
} else {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "All $processedCount items processed successfully."
    Write-Host "No inheritance failures detected."
    Write-Host "=========================================="
    Write-Host "CSV:   $OutputCsv"
    Write-Host "Excel: $OutputXlsx"
}

Write-Host ""
Write-Host "Done."
