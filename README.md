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
| `src/pwsh51/` | PowerShell 5.1-specific implementations (auto-selected when running on PS 5.1) |

## Quick Start

### Step 1: Fix inheritance and generate report

```powershell
.\src\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin"
```

Produces:

- `output/FailedInheritance.csv` — list of all files where inheritance could not be enabled
- `output/FailedInheritance.log` — detailed execution log (same base name as CSV)

Custom output path (`.csv` extension is appended automatically if omitted, and `.log` defaults next to it):

**PowerShell Version Banner:** The script prints a clearly highlighted PowerShell version banner on startup (for example, `PowerShell Version: 7.6.2 (Core)`) so you can immediately confirm which runtime is executing.

```powershell
.\src\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin" -OutputPath "C:\reports\failures"
```

Produces `C:\reports\failures.csv` and `C:\reports\failures.log`.

### Step 2: Take ownership of failed files (run as Administrator)

```powershell
.\src\Take-Ownership.ps1 -CsvPath "./output/FailedInheritance.csv"
```

Produces `Results_TIMESTAMP.csv` next to the input CSV and a log file.

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

Each run creates a log file:
- Format: `[YYYY-MM-DD HH:MM:SS] [LEVEL] Message`
- Levels: INFO, WARNING, ERROR
- Records: start/end times, file counts, errors, configuration
- Fix-Inheritance: log is placed next to the output CSV with `.log` extension (same base name)
- Take-Ownership: log defaults to `./logs/TakeOwnership.log` unless `-LogPath` is specified

### Safety Features

- Uses `ProcessStartInfo.ArgumentList` on PowerShell 7+ (with a manually-quoted `Arguments` string fallback on Windows PowerShell 5.1, where the property does not exist) for native command execution (avoids PowerShell parsing issues)
- Continue-on-error design: never stops processing due to individual file failures
- Admin privilege detection with helpful warnings (non-fatal on non-Windows platforms)
- Enumeration errors captured via `-ErrorVariable` so inaccessible folders don't halt processing

## Requirements

- **Windows PowerShell 5.1 or PowerShell 7+**
- Administrator privileges (required for Take-Ownership to work on protected files)
- Read access to target fileshare
- `icacls.exe` and `takeown.exe` (built into Windows operating system)
- For cross-platform testing: Scripts run on Linux/PowerShell 7 but will skip Windows-specific operations gracefully

### PowerShell 5.1 Support

The scripts support both Windows PowerShell 5.1 and PowerShell 7+. When run on PowerShell 5.1, the scripts automatically route to version-specific implementations in `src/pwsh51/` that avoid PS 7+ language features.

### Windows Container Testing (WinBoat)

Tests can be run against a Windows container running in WinBoat (Docker) on CachyOS/Linux:

1. Start a Windows container with WinBoat (noVNC):
   ```bash
   docker run -d --name winboat -p 47270:6080 mcr.microsoft.com/windows/servercore:ltsc2022
   ```

2. Ensure the repo is accessible at `\\host.lan\Data\repos\fix-inheritance` in the container

3. Run tests - they automatically skip if WinBoat isn't available:
   ```bash
   pwsh ./Tests/WinBoat.Tests.ps1
   ```

These tests validate PowerShell 5.1 and 7.x compatibility on Windows with network share access.

## Test Suite

Comprehensive Pester test suite validates the scripts end-to-end:

- **34 tests** across `Fix-Inheritance.Tests.ps1` and `Take-Ownership.Tests.ps1`
- Integration tests, special characters, deep paths, long paths, enumeration-error handling, and default-path resolution
- Continue-on-error design verified across all scenarios

### Running Tests

```powershell
Invoke-Pester -Path Tests/
```

### Windows Container Testing (WinBoat)

Tests can be run against a Windows container running in WinBoat (Docker) on CachyOS/Linux:

1. Start a Windows container with PowerShell:
   ```bash
   docker run -d --name win-test -p 5985:5985 mcr.microsoft.com/windows/servercore:ltsc2022
   ```

2. Mount the repo inside the container at `C:\Users\keverall\repos\fix-inheritance`

3. Run the WinBoat tests:
   ```bash
   pwsh ./Tests/WinBoat.Tests.ps1
   ```

**Note:** The dockur/windows image doesn't support `docker exec` with PowerShell. Use a full Windows container like `mcr.microsoft.com/windows/servercore:ltsc2022` for testing.

### Manual Windows Testing

For comprehensive testing on Windows:

1. Setup test data (run as Administrator):
   ```powershell
   .\Tests\TestData\Setup-WindowsTestData.ps1
   ```

2. Run fix-inheritance:
   ```powershell
   .\Tests\TestData\Run-FixInheritanceTests.ps1
   ```

This creates test files with:
- Special character filenames (spaces, commas, quotes, etc.)
- Deep directory structures
- Long paths (> 260 characters)
- Protected files (access denied)
- Files in protected folders (enumeration errors)
