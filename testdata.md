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