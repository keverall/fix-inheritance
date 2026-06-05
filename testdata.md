# setup

1. Best & Easiest: Take Ownership + Strip Administrators Rights (recommended)
Run these two commands on the target file/folder:

# Replace the path with your test file/folder
$target = "S:\fix-inheritance-tests\protected\secret.txt"

icacls $target /setowner "SYSTEM" /c
icacls $target /inheritance:r /grant "SYSTEM:(OI)(CI)F" /remove:g "Administrators" /remove:d "Administrators" /c
Do the same for a folder if you want.

After this, running the tool as a normal Administrator should produce an “Access Denied - requires ownership change” row in the CSV.

2. Quick one-liner version (single file)
icacls "S:\fix-inheritance-tests\myfile.txt" /setowner SYSTEM /inheritance:r /grant SYSTEM:F /remove:g Administrators /remove:d Administrators /c
3. For “File in use” (sharing violation – exit 32)
Keep the file open in another process, e.g.:

# In one PowerShell window (keep it running)
$file = [System.IO.File]::Open("S:\fix-inheritance-tests\inuse\locked.txt", 'Open', 'ReadWrite', 'None')

# In another window run the tool — it should now report “File in use”
Close the handle ($file.Close()) when done.

Added `Set-AdministratorDeniedInheritance` helper function to `Tests/TestData/Setup-WindowsTestData.ps1`.

The function:
- Sets owner to `SYSTEM`
- Grants rights only to `SYSTEM`
- Removes **all** Administrators permissions

It is now used for both the `protected` and `forbidden` test cases.

You can also call it manually from any elevated session:

```powershell
. .\Tests\TestData\Setup-WindowsTestData.ps1   # dot-source to load the function
Set-AdministratorDeniedInheritance -Path "S:\fix-inheritance-tests\mybadfolder"
```

Re-run the setup script to regenerate the test tree with the new reliable denial pattern.





 .\src\Fix-Inheritance.ps1 -TargetPath "R:\R_VS13_D2\ftcREGFIN\CECIL\2011 Checking  Sheet\1. Feb 2011"
Join-Path : A positional parameter cannot be found that accepts argument 'Fix-Inheritance.ps1'.
At T:\KevinE\KevsProducts\fix-inheritance\src\Fix-Inheritance.ps1:57 char:21
+ ...  $pwsh51Script = Join-Path $ScriptRoot "pwsh51" "Fix-Inheritance.ps1"
+                      ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidArgument: (:) [Join-Path], ParameterBindingException
    + FullyQualifiedErrorId : PositionalParameterNotFound,Microsoft.PowerShell.Commands.JoinPathCommand

Test-Path : Cannot bind argument to parameter 'LiteralPath' because it is null.
At T:\KevinE\KevsProducts\fix-inheritance\src\Fix-Inheritance.ps1:58 char:32
+     if (Test-Path -LiteralPath $pwsh51Script) {
+                                ~~~~~~~~~~~~~
    + CategoryInfo          : InvalidData: (:) [Test-Path], ParameterBindingValidationException
    + FullyQualifiedErrorId : ParameterArgumentValidationErrorNullNotAllowed,Microsoft.PowerShell.Commands.TestPathCom
   mand

****************************************************
* PowerShell Version: 5.1.17763.8641 (Desktop)
****************************************************

Join-Path : A positional parameter cannot be found that accepts argument '_Common.ps1'.
At T:\KevinE\KevsProducts\fix-inheritance\src\_Common.ps1:31 char:21
+     $pwsh51Common = Join-Path $ScriptRoot "pwsh51" "_Common.ps1"
+                     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidArgument: (:) [Join-Path], ParameterBindingException
    + FullyQualifiedErrorId : PositionalParameterNotFound,Microsoft.PowerShell.Commands.JoinPathCommand

Test-Path : Cannot bind argument to parameter 'LiteralPath' because it is null.
At T:\KevinE\KevsProducts\fix-inheritance\src\_Common.ps1:32 char:32
+     if (Test-Path -LiteralPath $pwsh51Common) {
+                                ~~~~~~~~~~~~~
    + CategoryInfo          : InvalidData: (:) [Test-Path], ParameterBindingValidationException
    + FullyQualifiedErrorId : ParameterArgumentValidationErrorNullNotAllowed,Microsoft.PowerShell.Commands.TestPathCom
   mand

Output file already exists and will be overwritten: T:\KevinE\KevsProducts\fix-inheritance\output\FailedInheritance.csv
Starting inheritance fix on: R:\R_VS13_D2\ftcREGFIN\CECIL\2011 Checking  Sheet\1. Feb 2011
Output CSV:   T:\KevinE\KevsProducts\fix-inheritance\output\FailedInheritance.csv
Log file:     T:\KevinE\KevsProducts\fix-inheritance\output\FailedInheritance.log
Running bulk icacls operation on target path...
==========================================
Summary
==========================================
Total failed items:     32
icacls summary:         Successfully processed 0 files; Failed processing 32 files
CSV:                    T:\KevinE\KevsProducts\fix-inheritance\output\FailedInheritance.csv
Error breakdown:
  - 32 x Access Denied - requires ownership change
Use Take-Ownership.ps1 to fix failed items.
Done.