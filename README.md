# Inheritance Fix Scripts

PowerShell scripts to fix Windows file permission inheritance issues with comprehensive error handling, special character support, long path support, and detailed logging.

## Project Structure

```text
fix-inheritance/
├── README.md                          # This documentation
├── .gitignore                         # Git ignore rules (ignores .vscode/, .kilo/, *.csv, *.log)
├── src/
│   ├── _Common.ps1                    # Shared helper module (dot-sourced by main scripts)
│   ├── Fix-Inheritance.ps1            # Main script: bulk icacls + failure parsing → CSV
│   ├── Take-Ownership.ps1             # Recovery script: takes ownership + re-applies icacls
│   └── pwsh51/                        # PowerShell 5.1 compatibility layer (auto-selected on PS 5.1)
│       ├── _Common.ps1
│       ├── Fix-Inheritance.ps1
│       └── Take-Ownership.ps1
├── Tests/
│   ├── Fix-Inheritance.Tests.ps1      # Pester tests for Fix-Inheritance
│   ├── Take-Ownership.Tests.ps1       # Pester tests for Take-Ownership
│   └── TestData/
│       ├── README.md                  # Test data documentation
│       ├── Setup-WindowsTestData.ps1  # Creates Windows test scenarios
│       └── Run-FixInheritanceTests.ps1 # Manual test runner for Windows data
├── logs/
│   └── *.log                          # Execution log output (default location)
└── output/
    └── *.csv                          # Timestamped failure/result CSVs (default location)
```

## Overview

These scripts solve common Windows file permission inheritance problems by:

1. **Scanning** a target path recursively.
2. **Attempting** to enable inheritance on all files/folders using a single bulk `icacls` operation for maximum performance.
3. **Logging** all failures to a CSV with detailed error classification.
4. **Providing** a recovery script to take ownership of failed files and re-apply inheritance.

## PowerShell Version Routing

The scripts automatically detect the PowerShell version. If run on Windows PowerShell 5.1, they seamlessly re-invoke the compatible versions located in the `src/pwsh51/` directory. No manual intervention is required.

## Quick Start

### Step 1: Fix inheritance and generate report

```powershell
.\src\Fix-Inheritance.ps1 -TargetPath "drive/folderpath"
```

**Produces:**

- `output/FailedInheritance.csv` — list of all files where inheritance could not be enabled.
- `logs/FailedInheritance.log` — detailed execution log.

**Custom output paths:**
*(Note: The `.csv` extension is appended automatically to `-OutputPath` if omitted. If `-LogPath` is omitted, the log defaults to the `logs/` folder in the repo root, regardless of the `-OutputPath` value.)*

```powershell
.\src\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin" -OutputPath "C:\reports\failures" -LogPath "C:\reports\failures.log"
```

### Step 2: Take ownership of failed files (run as Administrator)

```powershell
.\src\Take-Ownership.ps1 -CsvPath ".\output\FailedInheritance.csv"
```

**Produces:**

- `output/Results_TIMESTAMP.csv` — tracks each file's final status (Fixed/Failed).
- `logs/TakeOwnership.log` — detailed execution log.

### Step 3: Re-run if needed

```powershell
.\src\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin" -OutputPath "C:\reports\verify"
```

## How It Works

### Fix-Inheritance Process

1. **Bulk attempt**: Runs `icacls /inheritance:e /T /C /Q` on the root to fix most files quickly.
2. **Individual processing**: Enumerates all files recursively, runs `icacls` on each via safe `Invoke-NativeCommand`, and catches/classifies failures.
3. **CSV output**: Detailed failure report with full path analysis.
4. **Logging**: Every major step and error written to the log file.

### Take-Ownership Process

1. **Reads** the input CSV of failed files.
2. **Takes ownership** using `takeown.exe /f /A` via safe `Invoke-NativeCommand`.
3. **Re-applies inheritance** using `icacls.exe /inheritance:e` via safe `Invoke-NativeCommand`.
4. **Results CSV**: Tracks each file's final status (Fixed/Failed) with detailed reasons.
5. **Logging**: Complete audit trail in the log file.

## CSV Format

### Fix-Inheritance Output (`FailedInheritance.csv`)

```csv
FilePath,FileName,ParentFolder,FolderName,ErrorReason,PathLength,IsLongPath,Timestamp
"R:\r_vs13_d2\ftcregfin\file.txt","file.txt","R:\r_vs13_d2\ftcregfin","ftcregfin","Access Denied - requires ownership change","45","False","2026-05-27 10:30:00"
```

### Take-Ownership Output (`Results_TIMESTAMP.csv`)

```csv
FilePath,FileName,ParentFolder,FolderName,OriginalError,Status,StatusDetail,Timestamp
"R:\r_vs13_d2\ftcregfin\file.txt","file.txt","R:\r_vs13_d2\ftcregfin","ftcregfin","Access Denied - requires ownership change","Fixed","Success","2026-05-27 10:35:00"
```

## Error Reasons

| Error | Meaning | Typical Fix |
|-------|---------|-------------|
| Access Denied - requires ownership change | File/folder owned by another user or protected system file | Run Take-Ownership as Administrator |
| File not found | File deleted or moved during scan | Remove from CSV, re-run Fix-Inheritance |
| File in use | File locked by another process | Close application, re-run |
| Path too long | Path exceeds Windows MAX_PATH (260 chars) | Handled automatically with `\\?\` prefix |
| Invalid path or filename | Contains illegal characters | May need manual renaming |
| Cannot enumerate (likely access denied or path error) | Folder access denied during enumeration | Run as Administrator, check permissions |
| Failed to reset ACL | icacls failed to reset permissions | Check file attributes or running process |
| File attribute prevents operation | File is read-only or has restrictive attributes | Remove read-only attribute manually |
| Disk or I/O error | Underlying storage issue | Check disk health and connectivity |
| Unknown error (exit code: X) | Unclassified error | Check StatusDetail for raw exit code |

## Features in Detail

### Special Character Handling

All scripts correctly process filenames containing spaces, commas, quotes, ampersands, carets, dollar signs, percents, at symbols, hashes, exclamation marks, pluses, equals, brackets, semicolons, colons, parentheses, backticks, tildes, pipes, and periods.

### Long Path Support

Automatically detects and handles paths > 260 characters:
- Drive paths: `\\?\C:\very\long\path\...`
- UNC paths: `\\?\UNC\server\share\very\long\path\...`
- No double-prefixing of already-prefixed paths.
- Path length tracking in CSV (`PathLength` and `IsLongPath` columns).

### Logging

Each run creates a log file:
- Format: `[YYYY-MM-DD HH:MM:SS] [LEVEL] Message`
- Levels: INFO, WARNING, ERROR
- Records: start/end times, file counts, errors, configuration.
- **Default Behavior**: If `-LogPath` is not explicitly provided, logs are written to the `logs/` folder in the repository root (e.g., `logs/FailedInheritance.log` or `logs/TakeOwnership.log`), regardless of where `-OutputPath` or `-OutputCsv` points.

### Safety Features

- Uses `ProcessStartInfo.ArgumentList` on PowerShell 7+ (with a manually-quoted `Arguments` string fallback on Windows PowerShell 5.1) for native command execution, avoiding PowerShell parsing issues with special characters.
- Continue-on-error design: never stops processing due to individual file failures.
- Admin privilege detection with helpful warnings (non-fatal on non-Windows platforms).
- Enumeration errors captured via `-ErrorVariable` so inaccessible folders don't halt processing.

## Requirements

- **Windows PowerShell 5.1 or PowerShell 7+**
- Administrator privileges (required for Take-Ownership to work on protected files)
- Read access to target fileshare
- `icacls.exe` and `takeown.exe` (built into Windows)
- For cross-platform testing: Scripts run on Linux/PowerShell 7 but will skip Windows-specific operations gracefully.

### Running Scripts in Locked-Down Environments

If you get "script cannot be loaded" errors due to execution policy, use:

```powershell
# Recommended - bypass for this invocation only
powershell -ExecutionPolicy Bypass -File .\src\Fix-Inheritance.ps1 -TargetPath "R:\data"

# Or from an elevated PowerShell prompt
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
.\src\Fix-Inheritance.ps1 -TargetPath "R:\data"
```

This only affects the current process/session and doesn't require permanent policy changes.

## Test Suite

Comprehensive Pester test suite validates the scripts end-to-end:

- Integration tests, special characters, deep paths, long paths, enumeration-error handling, and default-path resolution.
- Continue-on-error design verified across all scenarios.

### Running Tests

```powershell
Invoke-Pester -Path Tests/
```

## Troubleshooting

- **"Access Denied - requires ownership change"**: The file or folder is owned by another user (e.g., SYSTEM) or has restrictive ACLs. Run `Take-Ownership.ps1` as an Administrator to resolve.
- **"File not found"**: The file was deleted or moved after the initial scan. It will be skipped on subsequent runs.
- **"File in use"**: Another process has an exclusive lock on the file. Close the application holding the file and re-run the script.
- **"Path too long"**: The script automatically handles this by prepending the `\\?\` long-path prefix. If it still fails, the path may exceed the absolute maximum limit or contain invalid characters.
- **"icacls not found"**: The scripts rely on Windows-native tools. They will fail gracefully on non-Windows platforms (like Linux/macOS) where `icacls.exe` is not available.
- **"Cannot enumerate"**: The script lacks read permissions for a specific directory. Ensure you are running as Administrator or have been granted explicit read access to the target path.
