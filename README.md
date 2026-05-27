# Inheritance Fix Scripts

Fixes inheritance on all files and subfolders within a target path, logging failures to CSV.

## Scripts

| Script | Purpose |
|--------|---------|
| `src/Fix-Inheritance.ps1` | Scans target path, runs `icacls /inheritance:e`, logs failures to CSV |
| `src/Take-Ownership.ps1` | Takes ownership of failed files from CSV, re-applies inheritance |
| `src/Take-Ownership.bat` | Batch alternative for take ownership from CSV |
| `src/Build-MarkdownHelp.ps1` | Generates/updates platyPS markdown help from scripts |
| `src/Test-Help.ps1` | Validates markdown help for completeness |
| `src/Build-ExternalHelp.ps1` | Compiles markdown help into MAML external help |

## Quick Start

### Step 1: Fix inheritance and generate report

```powershell
.\src\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin"
```

Produces:
- `FailedInheritance.csv` — list of all files where inheritance could not be enabled

Custom output path:
```powershell
.\src\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin" -OutputPath "C:\reports\failures"
```

Produces `failures.csv`.

### Step 2: Take ownership of failed files (run as Administrator)

**PowerShell:**
```powershell
.\src\Take-Ownership.ps1 -CsvPath "FailedInheritance.csv"
```

**Batch:**
```cmd
REM Open Command Prompt as Administrator, then run:
src\Take-Ownership.bat "FailedInheritance.csv"

REM With custom output path:
src\Take-Ownership.bat "FailedInheritance.csv" "C:\reports\Results.csv"
```

Both produce a results CSV (`Results_TIMESTAMP.csv` by default, or the path you specify).


### Step 3: Re-run if needed

```powershell
.\src\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin" -OutputPath "C:\reports\verify"
```

## Help Documentation

### Generate markdown help
```powershell
.\src\Build-MarkdownHelp.ps1
.\src\Build-MarkdownHelp.ps1 -Force    # Regenerate all
```

### Validate help
```powershell
.\src\Test-Help.ps1
```

### Build MAML external help
```powershell
.\src\Build-ExternalHelp.ps1
```

Output: `Help/en-US/*.help.xml`

## How It Works

1. **Bulk attempt**: Runs `icacls /inheritance:e /T /C` on the root to fix most files quickly
2. **Individual processing**: Enumerates all files, runs icacls on each, catches failures
3. **CSV output**: Flat file with all failure details — used by Take-Ownership scripts
4. **Ownership recovery**: Take-Ownership uses `takeown /f /A` then re-runs icacls

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
- `platyPS` module for help generation (`Install-Module -Name platyPS -Scope CurrentUser`)
