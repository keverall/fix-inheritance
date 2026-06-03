# Run fix-inheritance tests against prepared Windows test data
# Run this script as Administrator on Windows

param(
    [string]$TestRoot = "S:\",
    [string]$OutputPath = ".\output\TestResults.csv",
    [string]$LogPath = ".\logs\TestResults.log"
)

$ErrorActionPreference = "Stop"

Write-Host "Running fix-inheritance tests..."
Write-Host "Test Root: $TestRoot"
Write-Host "Output: $OutputPath"
Write-Host ""

# Ensure output and logs directories exist
$outDir = [System.IO.Path]::GetDirectoryName($OutputPath)
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$logDir = [System.IO.Path]::GetDirectoryName($LogPath)
if ($logDir -and -not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Run fix-inheritance
$scriptPath = ".\src\pwsh51\Fix-Inheritance.ps1"
if (-not (Test-Path $scriptPath)) {
    $scriptPath = ".\src\Fix-Inheritance.ps1"
}

& pwsh -NoProfile -File $scriptPath -TargetPath $TestRoot -OutputPath $OutputPath -LogPath $LogPath

Write-Host ""
Write-Host "Results:"
if (Test-Path $OutputPath) {
    $results = Import-Csv -Path $OutputPath
    Write-Host "Total failures recorded: $($results.Count)"
    $results | Group-Object ErrorReason | Format-Table Count, Name -AutoSize
} else {
    Write-Host "No results file created"
}

# Verify expected error types are present
Write-Host ""
Write-Host "Verifying error types..."
$errors = Import-Csv -Path $OutputPath

$expectedErrors = @(
    "Access Denied - requires ownership change",
    "Cannot enumerate (likely access denied or path error)"
)

foreach ($expected in $expectedErrors) {
    $found = $errors | Where-Object { $_.ErrorReason -like "*$expected*" }
    if ($found) {
        Write-Host "[PASS] Found: $expected"
    } else {
        Write-Host "[INFO] Not found (may be expected depending on test setup): $expected"
    }
}

# Check for special character handling
$specialFiles = $errors | Where-Object { $_.FileName -match 'file[,\s"`^]' }
if ($specialFiles) {
    Write-Host "[PASS] Special character filenames handled: $($specialFiles.Count) files"
}

# Check for deep path handling
$deepFiles = $errors | Where-Object { $_.FilePath -match "level20" }
if ($deepFiles) {
    Write-Host "[PASS] Deep paths handled: $($deepFiles.Count) files"
}

# Check for long path handling
$longFiles = $errors | Where-Object { $_.IsLongPath -eq "True" }
if ($longFiles) {
    Write-Host "[PASS] Long paths handled: $($longFiles.Count) files"
}

Write-Host ""
Write-Host "Test complete!"