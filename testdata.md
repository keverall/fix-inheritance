# Test Data Setup Notes

This document provides instructions for creating test scenarios to validate the `fix-inheritance` scripts on Windows.

## Quick Setup

### 1. Access Denied / Ownership Change Scenarios
To reliably generate "Access Denied - requires ownership change" errors for testing, run these commands as Administrator on a target file or folder:

```powershell
$target = "S:\fix-inheritance-tests\protected\secret.txt"

# Set owner to SYSTEM and grant rights only to SYSTEM, removing Administrators
icacls $target /setowner "SYSTEM" /c
icacls $target /inheritance:r /grant "SYSTEM:(OI)(CI)F" /remove:g "Administrators" /remove:d "Administrators" /c
```
*Note: A helper function `Set-AdministratorDeniedInheritance` is available in `Tests/TestData/Setup-WindowsTestData.ps1` to automate this for entire directories.*

### 2. File in Use Scenarios (Sharing Violation - Exit Code 32)
To simulate a locked file, keep it open in another process while running the tool:

```powershell
# In one PowerShell window (keep it running)
$file = [System.IO.File]::Open("S:\fix-inheritance-tests\inuse\locked.txt", 'Open', 'ReadWrite', 'None')

# In another window, run the tool — it should now report "File in use"
# Remember to close the handle ($file.Close()) when done testing.
```

## Automated Test Data Generation
For a comprehensive test suite, use the provided setup script (run as Administrator):





.\src\Fix-Inheritance.ps1 -TargetPath "R:\R_VS13_D2\ftcREGFIN\CECIL\2011 Checking  Sheet"
The script failed due to call depth overflow.
At C:\Products\Repos\fix-inheritance\src\pwsh51\Fix-Inheritance.ps1:46 char:5
+ if ($ScriptRoot -and (Split-Path $ScriptRoot -Leaf) -eq 'pwsh51') {
+     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidOperation: (0:Int32) [], RuntimeException
    + FullyQualifiedErrorId : CallDepthOverflow

The script failed due to call depth overflow.
At C:\Products\Repos\fix-inheritance\src\pwsh51\Fix-Inheritance.ps1:57 char:13
+             & $pwsh51Script @PSBoundParameters
+             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidOperation: (0:Int32) [], RuntimeException
    + FullyQualifiedErrorId : CallDepthOverflow

The script failed due to call depth overflow.
At C:\Products\Repos\fix-inheritance\src\pwsh51\Fix-Inheritance.ps1:57 char:13
+             & $pwsh51Script @PSBoundParameters
+             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidOperation: (0:Int32) [], RuntimeException
    + FullyQualifiedErrorId : CallDepthOverflow

The script failed due to call depth overflow.
At C:\Products\Repos\fix-inheritance\src\pwsh51\Fix-Inheritance.ps1:57 char:13
+             & $pwsh51Script @PSBoundParameters
+             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidOperation: (0:Int32) [], RuntimeException
    + FullyQualifiedErrorId : CallDepthOverflow

The script failed due to call depth overflow.
At C:\Products\Repos\fix-inheritance\src\pwsh51\Fix-Inheritance.ps1:57 char:13
+             & $pwsh51Script @PSBoundParameters
+             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidOperation: (0:Int32) [], RuntimeException
    + FullyQualifiedErrorId : CallDepthOverflow

The script failed due to call depth overflow.
At C:\Products\Repos\fix-inheritance\src\pwsh51\Fix-Inheritance.ps1:57 char:13
+             & $pwsh51Script @PSBoundParameters
+             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidOperation: (0:Int32) [], RuntimeException
    + FullyQualifiedErrorId : CallDepthOverflow

The script failed due to call depth overflow.
At C:\Products\Repos\fix-inheritance\src\pwsh51\Fix-Inheritance.ps1:57 char:13
+             & $pwsh51Script @PSBoundParameters
+             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidOperation: (0:Int32) [], RuntimeException
    + FullyQualifiedErrorId : CallDepthOverflow

The script failed due to call depth overflow.
At C:\Products\Repos\fix-inheritance\src\pwsh51\Fix-Inheritance.ps1:57 char:13
+             & $pwsh51Script @PSBoundParameters
+             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidOperation: (0:Int32) [], RuntimeException
    + FullyQualifiedErrorId : CallDepthOverflow

The script failed due to call depth overflow.
At C:\Products\Repos\fix-inheritance\src\pwsh51\Fix-Inheritance.ps1:57 char:13
+             & $pwsh51Script @PSBoundParameters
+             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidOperation: (0:Int32) [], RuntimeException
    + FullyQualifiedErrorId : CallDepthOverflow

The script failed due to call depth overflow.
At C:\Products\Repos\fix-inheritance\src\pwsh51\Fix-Inheritance.ps1:57 char:13
+             & $pwsh51Script @PSBoundParameters
+             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidOperation: (0:Int32) [], RuntimeException
    + FullyQualifiedErrorId : CallDepthOverflow

```powershell
.\Tests\TestData\Setup-WindowsTestData.ps1
```
This script creates a structured test tree at `S:\` (or a custom path) containing normal files, special character filenames, deep directory structures, long paths, protected files, and enumeration-error folders.
