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



 .\src\Fix-Inheritance.ps1 -TargetPath "C:\tests"                              0  12:38:21 
Join-Path : A positional parameter cannot be found that accepts argument 'Fix-Inheritance.ps1'.
At C:\Users\98253\repos\fix-inheritance\src\Fix-Inheritance.ps1:51 char:21
+ ...  $pwsh51Script = Join-Path $scriptRoot "pwsh51" "Fix-Inheritance.ps1"
+                      ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidArgument: (:) [Join-Path], ParameterBindingException
    + FullyQualifiedErrorId : PositionalParameterNotFound,Microsoft.PowerShell.Commands.JoinPathCommand

Test-Path : Cannot bind argument to parameter 'Path' because it is null.
At C:\Users\98253\repos\fix-inheritance\src\Fix-Inheritance.ps1:52 char:19
+     if (Test-Path $pwsh51Script) {
+                   ~~~~~~~~~~~~~
    + CategoryInfo          : InvalidData: (:) [Test-Path], ParameterBindingValidationException
    + FullyQualifiedErrorId : ParameterArgumentValidationErrorNullNotAllowed,Microsoft.PowerShell.Commands.TestPathCom
   mand

Join-Path : A positional parameter cannot be found that accepts argument '_Common.ps1'.
At C:\Users\98253\repos\fix-inheritance\src\_Common.ps1:28 char:21
+     $pwsh51Common = Join-Path $scriptRoot "pwsh51" "_Common.ps1"
+                     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidArgument: (:) [Join-Path], ParameterBindingException
    + FullyQualifiedErrorId : PositionalParameterNotFound,Microsoft.PowerShell.Commands.JoinPathCommand

Test-Path : Cannot bind argument to parameter 'Path' because it is null.
At C:\Users\98253\repos\fix-inheritance\src\_Common.ps1:29 char:19
+     if (Test-Path $pwsh51Common) {
+                   ~~~~~~~~~~~~~
    + CategoryInfo          : InvalidData: (:) [Test-Path], ParameterBindingValidationException
    + FullyQualifiedErrorId : ParameterArgumentValidationErrorNullNotAllowed,Microsoft.PowerShell.Commands.TestPathCom
   mand

Output file already exists and will be overwritten: C:\Users\98253\repos\fix-inheritance\output\FailedInheritance.csv
Starting inheritance fix on: C:\tests
Output CSV:   C:\Users\98253\repos\fix-inheritance\output\FailedInheritance.csv
Log file:     C:\Users\98253\repos\fix-inheritance\logs\FailedInheritance.log
Found 7 enumerable items (Files: 6, Folders: 1) plus 0 items that failed enumeration
Attempting bulk icacls operation on root...
Bulk operation finished (exit code 0). Per-item verification will identify exact failures.
Processing items individually to identify failures (continues on all errors)...
==========================================
Summary
==========================================
Items discovered:       7
  - Files:              6
  - Folders:            1
Items processed:        7
  - Files processed:    6
  - Folders processed:  1
Failed items:           0
  - Enumeration errors: 0
  - Per-item errors:    0
CSV:                    C:\Users\98253\repos\fix-inheritance\output\FailedInheritance.csv
Done.

If it still fails, please run this diagnostic command and paste the output:

pwsh -Command '$PSVersionTable | Format-List *; "IsCoreCLR = $IsCoreCLR"'

pwsh -Command '$PSVersionTable | Format-List *; "IsCoreCLR = $IsCoreCLR"' 167ms  12:49:44 

Name  : PSVersion
Key   : PSVersion
Value : 7.6.2

Name  : PSEdition
Key   : PSEdition
Value : Core

Name  : GitCommitId
Key   : GitCommitId
Value : 7.6.2

Name  : OS
Key   : OS
Value : Microsoft Windows 10.0.22631

Name  : Platform
Key   : Platform
Value : Win32NT

Name  : PSCompatibleVersions
Key   : PSCompatibleVersions
Value : {1.0, 2.0, 3.0, 4.0…}

Name  : PSRemotingProtocolVersion
Key   : PSRemotingProtocolVersion
Value : 2.4

Name  : SerializationVersion
Key   : SerializationVersion
Value : 1.1.0.1

Name  : WSManStackVersion
Key   : WSManStackVersion
Value : 3.0

IsCoreCLR: The term 'IsCoreCLR' is not recognized as a name of a cmdlet, function, script file, or executable program.
Check the spelling of the name, or if a path was included, verify that the path is correct and try again.