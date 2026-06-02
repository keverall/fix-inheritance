# Inheritance Fix Scripts

PowerShell scripts to fix Windows file inheritance issues with comprehensive error handling, special character support, long path support, and detailed logging.

## Overview

These scripts solve common Windows file permission inheritance problems by:

1. **Scanning** a target path recursively
2. **Attempting** to enable inheritance on all files/folders
3. **Logging** all failures to CSV with detailed error classification
4. **Providing** recovery scripts to take ownership and re-apply inheritance

## Scripts

| Script | Purpose |
|--------|---------|
| `src/Fix-Inheritance.ps1` | Scans target path, attempts to enable inheritance, logs all failures to CSV |
| `src/Take-Ownership.ps1` | Takes ownership of failed files from CSV, re-applies inheritance, logs results |
| `src/_Common.ps1` | Shared helper module (dot-sourced by both main scripts) |

## Key Improvements

- ✅ **Special character handling**: Commas, quotes, `&`, `^`, `$`, spaces, Unicode, etc.
- ✅ **Long path support**: Automatic `\\?\` prefix for paths > 260 characters
- ✅ **Continue-on-error**: Processes all files even when individual operations fail
- ✅ **Structured logging**: Timestamped log file alongside CSV output
- ✅ **Comprehensive error classification**: Uses HRESULT codes first (locale-independent)
- ✅ **Test coverage**: 55 automated Pester tests covering edge cases
- ✅ **Shared logic**: Common functions in `_Common.ps1` eliminate duplication
- ✅ **Safe execution**: Uses `ProcessStartInfo.ArgumentList` to avoid shell parsing issues

## Quick Start

### Step 1: Fix inheritance and generate report

```powershell
.\src\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin"
```

Produces:
- `FailedInheritance.csv` — list of all files where inheritance could not be enabled
- `FailedInheritance.log` — detailed execution log (same base name as CSV)

Custom output path:
```powershell
.\src\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin" -OutputPath "C:\reports\failures"
```

Produces `failures.csv` and `failures.log`.

### Step 2: Take ownership of failed files (run as Administrator)

```powershell
.\src\Take-Ownership.ps1 -CsvPath "FailedInheritance.csv"
```

Produces a results CSV (`Results_TIMESTAMP.csv` by default) and matching log file.

### Step 3: Re-run if needed

```powershell
.\src\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin" -OutputPath "C:\reports\verify"
```

## How It Works

### Fix-Inheritance Process
1. **Bulk attempt**: Runs `icacls /inheritance:e /T /C` on the root to fix most files quickly
2. **Individual processing**: Enumerates all files recursively (with `-ErrorVariable` to catch access denied folders), runs `icacls` on each via safe `Invoke-NativeCommand`, catches and classifies failures
3. **CSV output**: Detailed failure report with full path analysis
4. **Logging**: Every major step and error written to timestamped log file

### Take-Ownership Process
1. **Reads** input CSV of failed files
2. **Takes ownership** using `takeown.exe /f /A` via safe `Invoke-NativeCommand`
3. **Re-applies inheritance** using `icacls.exe /inheritance:e` via safe `Invoke-NativeCommand`
4. **Results CSV**: Tracks each file's final status (Fixed/Failed) with detailed reason
5. **Logging**: Complete audit trail in timestamped log file

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

## Error Reasons (Fix-Inheritance)

| Error | Meaning | Typical Fix |
|-------|---------|-------------|
| Access Denied - requires ownership change | File/folder owned by another user or protected system file | Run Take-Ownership as Administrator |
| File not found | File deleted or moved during scan | Remove from CSV, re-run Fix-Inheritance |
| File in use | File locked by another process | Close application, re-run |
| Path too long | Path exceeds Windows MAX_PATH (260 chars) | Automatic `\\?\` prefix applied |
| Invalid path or filename | Contains illegal characters | May need manual renaming |
| Cannot enumerate (likely access denied or path error) | Folder access denied during enumeration | Run as Administrator, check permissions |
| Unknown error (exit code: X) | Unclassified error | Check StatusDetail for raw exit code |

## Features in Detail

### Special Character Handling
All scripts correctly process filenames containing:
- Spaces: `my file.txt`
- Commas: `file,version2.txt`
- Quotes: `file"final".txt`
- Ampersand: `file&data.txt`
- Caret: `file^temp.txt`
- Dollar: `file$value.txt`
- Percent: `file%complete.txt`
- At symbol: `file@server.txt`
- Hash: `file#section.txt`
- Exclamation: `file!important.txt`
- Plus: `file+update.txt`
- Equals: `file=setting.txt`
- Brackets: `file[1].txt`, `file{config}.txt`
- Semicolon: `file;part.txt`
- Colon: `file:stream.txt` (alternate data stream)
- Parentheses: `file(v2).txt`
- Backtick: `` `file`.txt ``
- Tilde: `file~backup.txt`
- Pipe: `file|split.txt`
- Periods: `file..txt`, `.hidden`, `file.version.txt`

### Long Path Support
Automatically detects and handles paths > 260 characters:
- Drive paths: `\\?\C:\very\long\path\...`
- UNC paths: `\\?\UNC\server\share\very\long\path\...`
- No double-prefixing of already-prefixed paths
- Path length tracking in CSV (`PathLength` and `IsLongPath` columns)

### Logging
Each run creates a timestamped log file:
- Format: `[YYYY-MM-DD HH:MM:SS] [LEVEL] Message`
- Levels: INFO, WARNING, ERROR
- Records: start/end times, file counts, errors, configuration
- Located next to CSV file with same base name

### Safety Features
- Uses `ProcessStartInfo.ArgumentList` for native command execution (avoids PowerShell parsing issues)
- `[CmdletBinding(SupportsShouldProcess)]` on state-changing functions
- `-WhatIf` and `-Confirm` support where appropriate
- Continue-on-error design: never stops processing due to individual file failures
- Admin privilege detection with helpful warnings (non-fatal on non-Windows platforms)

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Administrator privileges (required for Take-Ownership to work on protected files)
- Read access to target fileshare
- `icacls.exe` and `takeown.exe` (built into Windows operating system)
- For cross-platform testing: Scripts run on Linux/PowerShell 7 but will skip Windows-specific operations gracefully

## Test Suite

Comprehensive Pester test suite validates all three scripts end-to-end:
- **55 tests total** across `_Common.Tests.ps1`, `Fix-Inheritance.Tests.ps1`, and `Take-Ownership.Tests.ps1`
- Pure functions (helpers), integration paths, and script structure
- Special characters, deep paths, long paths, continue-on-error scenarios
- PSScriptAnalyzer clean (0 warnings excluding PSAvoidUsingWriteHost)

Run tests with:
```powershell
Invoke-Pester -Path Tests/
```

## Output Examples

### Successful Fix-Inheritance Run
```
Starting inheritance fix on: \\server\share\data
Output CSV:   C:\reports\FailedInheritance.csv
Log file:     C:\reports\FailedInheritance.log
Found 1,247 enumerable items (plus 3 items that failed enumeration)
Attempting bulk icacls operation on root...
Bulk operation finished (exit code: 0). Per-item verification will identify exact failures.
Processing items individually to identify failures (continues on all errors)...

==========================================
Summary
==========================================
Total items processed:  1,250
Failed items:           15
  - Enumeration errors: 3
  - Per-item errors:    12
CSV:                    C:\reports\FailedInheritance.csv
Done.
```

### Successful Take-Ownership Run
```
Starting take-ownership recovery
CSV:    C:\reports\FailedInheritance.csv
Output: C:\reports\Results_20260602_103000.csv
Log:    C:\reports\TakeOwnership_20260602_103000.log
Input CSV has 15 rows - processing...
==========================================
Summary
==========================================
Total processed:    15
Fixed:              12
Still failed:       3
Results:            C:\reports\Results_20260602_103000.csv
Done.
```
