@echo off
REM Take-Ownership.bat
REM Takes ownership of files listed in CSV, then re-runs icacls inheritance:e
REM Requires: Administrator privileges
REM Usage: Take-Ownership.bat FailedInheritance.csv [OutputResults.csv]

setlocal enabledelayedexpansion

if "%~1"=="" (
    echo Usage: Take-Ownership.bat ^<CSV_FILE^> [OutputCSV]
    echo   CSV_FILE  - Path to FailedInheritance.csv from Fix-Inheritance.ps1
    echo   OutputCSV - Optional output results CSV (default: Results_TIMESTAMP.csv)
    exit /b 1
)

set "CSV_FILE=%~1"

if not exist "%CSV_FILE%" (
    echo Error: CSV file not found: %CSV_FILE%
    exit /b 1
)

REM Generate default output filename if not provided
if "%~2"=="" (
    for /f "tokens=1-4 delims=/-: " %%a in ("%date% %time%") do set "TS=%%a%%b%%c_%%d%%e%%f"
    set "OUTPUT_CSV=%~dp0Results_%TS%.csv"
) else (
    set "OUTPUT_CSV=%~2"
)

echo ==========================================
echo Take Ownership Script
echo ==========================================
echo Input:  %CSV_FILE%
echo Output: %OUTPUT_CSV%
echo.
echo Running as Administrator is required.
echo.

REM Write CSV header
echo FilePath,FileName,ParentFolder,OriginalError,Status,StatusDetail,Timestamp > "%OUTPUT_CSV%"

set /a processed=0
set /a succeeded=0
set /a failed=0

REM Skip header line, parse CSV
REM CSV format: FilePath,FileName,ParentFolder,FolderName,ErrorReason,PathLength,IsLongPath,Timestamp
REM Use PowerShell for reliable CSV parsing (handles quoted fields with commas)
powershell -NoProfile -Command ^
    "$csvPath = '%CSV_FILE%'; ^
     $outCsv = '%OUTPUT_CSV%'; ^
     $items = Import-Csv -Path $csvPath -Encoding UTF8; ^
     foreach ($item in $items) { ^
         if ([string]::IsNullOrWhiteSpace($item.FilePath)) { continue }; ^
         $filePath = $item.FilePath; ^
         $fileName = $item.FileName; ^
         $parentFolder = $item.ParentFolder; ^
         $errorReason = $item.ErrorReason; ^
         Write-Host \"$filePath\"; ^
         $takeownOut = & takeown.exe /f $filePath /A 2>&1; ^
         if ($LASTEXITCODE -eq 0) { ^
             $icaclsOut = & icacls.exe $filePath /inheritance:e /C 2>&1; ^
             if ($LASTEXITCODE -eq 0) { ^
                 Write-Host '  -> FIXED' -ForegroundColor Green; ^
                 $status = 'Fixed'; $detail = ''; ^
                 $succeeded = $true; ^
             } else { ^
                 Write-Host '  -> FAILED (icacls exit $LASTEXITCODE)' -ForegroundColor Red; ^
                 $status = 'Failed'; $detail = 'Inheritance restore failed'; ^
                 $succeeded = $false; ^
             } ^
         } else { ^
             Write-Host '  -> FAILED (takeown exit $LASTEXITCODE)' -ForegroundColor Red; ^
             $status = 'Failed'; $detail = 'Takeown failed'; ^
             $succeeded = $false; ^
         }; ^
         $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; ^
         Add-Content -Path $outCsv -Value ('\"{0}\",\"{1}\",\"{2}\",\"{3}\",{4},\"{5}\",\"{6}\"' -f $filePath, $fileName, $parentFolder, $errorReason, $status, $detail, $ts); ^
         if ($succeeded) { $script:succeeded++ } else { $script:failed++ } ^
     }; ^
     Write-Host ''; ^
     Write-Host '==========================================' -ForegroundColor Yellow; ^
     Write-Host ('Total processed: {0}' -f ($items.Count)) -ForegroundColor Yellow; ^
     Write-Host ('Succeeded:       {0}' -f $script:succeeded) -ForegroundColor Green; ^
     Write-Host ('Failed:          {0}' -f $script:failed) -ForegroundColor Red; ^
     Write-Host '==========================================' -ForegroundColor Yellow"

echo.
echo Results saved to: %OUTPUT_CSV%
echo.
echo Done.

endlocal
