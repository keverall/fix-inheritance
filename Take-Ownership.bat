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
for /f "usebackq skip=1 tokens=1,2,3,4,5 delims=," %%A in ("%CSV_FILE%") do (
    set "FILE_PATH=%%~A"
    set "FILE_NAME=%%~B"
    set "PARENT_FOLDER=%%~C"
    set "FOLDER_NAME=%%~D"
    set "ERROR_REASON=%%~E"

    REM Remove surrounding quotes if present
    set "FILE_PATH=!FILE_PATH:"=!"
    set "FILE_NAME=!FILE_NAME:"=!"
    set "PARENT_FOLDER=!PARENT_FOLDER:"=!"
    set "ERROR_REASON=!ERROR_REASON:"=!"

    if not "!FILE_PATH!"=="" (
        set /a processed+=1
        echo [!processed!] !FILE_PATH!

        REM Take ownership
        takeown /f "!FILE_PATH!" /A /R /D Y >nul 2>&1
        if !errorlevel! equ 0 (
            echo   -^> Ownership acquired.

            REM Re-apply inheritance
            icacls "!FILE_PATH!" /inheritance:e /C /T >nul 2>&1
            if !errorlevel! equ 0 (
                echo   -^> FIXED
                set /a succeeded+=1
                echo "!FILE_PATH!","!FILE_NAME!","!PARENT_FOLDER!","!ERROR_REASON!","Fixed","","!date! !time!" >> "%OUTPUT_CSV%"
            ) else (
                echo   -^> FAILED (icacls error)
                set /a failed+=1
                echo "!FILE_PATH!","!FILE_NAME!","!PARENT_FOLDER!","!ERROR_REASON!","Failed","Inheritance restore failed","!date! !time!" >> "%OUTPUT_CSV%"
            )
        ) else (
            echo   -^> FAILED (takeown error)
            set /a failed+=1
            echo "!FILE_PATH!","!FILE_NAME!","!PARENT_FOLDER!","!ERROR_REASON!","Failed","Takeown failed","!date! !time!" >> "%OUTPUT_CSV%"
        )
    )
)

echo.
echo ==========================================
echo Summary
echo ==========================================
echo Total processed: %processed%
echo Succeeded:       %succeeded%
echo Failed:          %failed%
echo ==========================================
echo.
echo Results saved to: %OUTPUT_CSV%
echo.
echo Done.

endlocal
