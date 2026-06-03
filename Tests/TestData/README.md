# Windows Test Data for Fix-Inheritance

This directory contains scripts to create test data for validating fix-inheritance functionality on Windows.

## Quick Start

### 1. Setup Test Data (Run as Administrator)

```powershell
.\Tests\TestData\Setup-WindowsTestData.ps1
```

This creates test files at `C:\temp\fix-inheritance-tests` with:
- Normal files (should succeed)
- Special character filenames
- Deep directory structures
- Long paths (> 260 characters)
- Protected files (access denied)
- Enumeration-error folders
- Locked files (simulated with inheritance removal)

### 2. Run Fix-Inheritance Tests

```powershell
.\Tests\TestData\Run-FixInheritanceTests.ps1
```

This runs fix-inheritance against the test data and displays results.

### 3. Cleanup

```powershell
Remove-Item -Path 'C:\temp\fix-inheritance-tests' -Recurse -Force
```

## PowerShell Version Routing

The fix-inheritance scripts automatically detect the PowerShell version and route accordingly:

- **PowerShell 5.1**: Routes to `src/pwsh51/` implementations
- **PowerShell 7.x**: Uses `src/` implementations

**No manual intervention needed** - the routing is automatic via `$PSVersionTable.PSVersion.Major` checks in:
- `src/_Common.ps1`
- `src/Fix-Inheritance.ps1`
- `src/Take-Ownership.ps1`

## Expected Error Types

| Error | Trigger |
|-------|---------|
| Access Denied | Protected files/folders |
| Cannot enumerate | Folders without read permissions |
| Path too long | Files with paths > 260 characters |
| Locked files | Files with inheritance removed |
| Invalid path/filename | Special characters in names |

## Running on Different PowerShell Versions

### PowerShell 5.1 (Windows PowerShell)
```powershell
# The scripts automatically route to pwsh51/
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -File .\src\Fix-Inheritance.ps1 -TargetPath "C:\temp\fix-inheritance-tests"
```

### PowerShell 7.x
```powershell
# The scripts run directly from src/
pwsh -File .\src\Fix-Inheritance.ps1 -TargetPath "C:\temp\fix-inheritance-tests"
```
