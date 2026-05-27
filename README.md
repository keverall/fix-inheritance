# Inheritance Fix Scripts

Fixes inheritance on all files and subfolders within a target path, logging failures to CSV and Excel.

## Scripts

| Script | Purpose |
|--------|---------|
| `Fix-Inheritance.ps1` | Scans target path, runs `icacls /inheritance:e`, logs failures to **CSV + Excel** |
| `Take-Ownership.ps1` | Takes ownership of failed files from CSV, re-applies inheritance |
| `Take-Ownership.bat` | Batch alternative for take ownership from CSV |

## Prerequisites

### Excel output (recommended)
```powershell
Install-Module -Name ImportExcel -Scope CurrentUser -Force
```

## Quick Start

### Step 1: Fix inheritance and generate report

```powershell
.\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin"
```

Produces:
- `FailedInheritance.csv` — flat file of all failures
- `FailedInheritance.xlsx` — multi-tab workbook with summaries, charts, and folder aggregation

Custom output path:
```powershell
.\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin" -OutputPath "C:\reports\MyReport"
```

Produces `MyReport.csv` and `MyReport.xlsx`.

### Step 2: Take ownership of failed files (run as Administrator)

**PowerShell:**
```powershell
.\Take-Ownership.ps1 -CsvPath "FailedInheritance.csv"
```

**Batch:**
```cmd
Take-Ownership.bat "FailedInheritance.csv"
```

Both produce a results CSV (`Results_TIMESTAMP.csv`).

### Step 3: Re-run if needed

```powershell
.\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin" -OutputPath "C:\reports\Verify"
```

## Excel Report Structure

### Fix-Inheritance.ps1 produces:

| Tab | Contents |
|-----|----------|
| **Summary** | Total items, failed count, success rate, error breakdown pie chart, timestamp |
| **Errors by Folder** | Aggregated file counts per folder with conditional formatting (red >50, yellow 10-50), total row |
| **All Failures** | Every failed file: full path, filename, parent folder, error reason, path length, long-path flag, timestamp |
| **Long Paths** | Filtered view of files with paths >256 characters |

### Take-Ownership produces:

| Output | Contents |
|--------|----------|
| **Results CSV** | Every file processed: original error, status (Fixed/Failed), detail, timestamp |

## How It Works

1. **Bulk attempt**: Runs `icacls /inheritance:e /T /C` on the root to fix most files quickly
2. **Individual processing**: Enumerates all files, runs icacls on each, catches failures
3. **CSV output**: Flat file with all failure details — used by Take-Ownership scripts
4. **Excel output**: Multi-tab workbook with summary, folder aggregation, conditional formatting, charts
5. **Long path support**: Uses `\\?\` prefix for paths >256 characters
6. **Special characters**: Uses `-LiteralPath` and proper quoting throughout
7. **Ownership recovery**: Take-Ownership uses `takeown /f /A` then re-runs icacls

## CSV Format

```csv
FilePath,FileName,ParentFolder,FolderName,ErrorReason,PathLength,IsLongPath,Timestamp
"R:\r_vs13_d2\ftcregfin\file.txt","file.txt","R:\r_vs13_d2\ftcregfin","ftcregfin","Access Denied - requires ownership change","45","False","2026-05-27 10:30:00"
```

## Error Reasons

| Error | Meaning | Fix |
|-------|---------|-----|
| Access Denied | File owned by another user | Run Take-Ownership as Administrator |
| File not found | File deleted or moved | Remove from CSV, re-run |
| File in use | File locked by process | Close application, re-run |
| Invalid path | Path/filename invalid | May need manual intervention |

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Administrator privileges (for Take-Ownership scripts)
- Read access to target fileshare
- `icacls.exe` and `takeown.exe` (built into Windows)
- `ImportExcel` module for Excel output (`Install-Module ImportExcel`)
