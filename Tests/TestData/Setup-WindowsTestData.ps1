# Setup script for fix-inheritance tests on Windows
# Run this script as Administrator to create test scenarios

param(
    [string]$TestRoot = "S:\fix-inheritance-tests"
)

function Set-AdministratorDeniedInheritance {
    <#
    .SYNOPSIS
        Creates a folder that will cause icacls /inheritance:e to fail even when
        run as Administrator. Used to generate real CSV failure rows for testing.
    .PARAMETER Path
        Folder to configure.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    # Set owner to SYSTEM and remove all Administrators permissions.
    # This forces Access Denied on subsequent icacls /inheritance:e calls.
    & icacls.exe $Path /inheritance:r /setowner SYSTEM /grant "SYSTEM:(OI)(CI)F" `
        /remove:g Administrators /remove:d Administrators /c 2>$null | Out-Null
}

Write-Host "Setting up fix-inheritance test data at $TestRoot"

# Clean up existing test directory
if (Test-Path $TestRoot) {
    # Reset ACLs first to allow deletion of folders with removed inheritance
    & icacls.exe $TestRoot /reset /T /C 2>$null | Out-Null
    Remove-Item -Path $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

# 1. Normal files (should succeed with inheritance fix)
New-Item -ItemType Directory -Path "$TestRoot\normal" -Force | Out-Null
"normal file" | Set-Content -Path "$TestRoot\normal\file1.txt"
"another normal file" | Set-Content -Path "$TestRoot\normal\file2.txt"

# 2. Files with special characters in names
New-Item -ItemType Directory -Path "$TestRoot\special" -Force | Out-Null
"file with spaces.txt" | Set-Content -Path "$TestRoot\special\file with spaces.txt"
"file,comma.txt" | Set-Content -Path "$TestRoot\special\file,comma.txt"
"file``backtick.txt" | Set-Content -Path "$TestRoot\special\file``backtick.txt"
"file&ampersand.txt" | Set-Content -Path "$TestRoot\special\file&ampersand.txt"
"file^caret.txt" | Set-Content -Path "$TestRoot\special\file^caret.txt"

# 3. Deep directory structure
$deepPath = $TestRoot
1..20 | ForEach-Object { $deepPath = Join-Path $deepPath "level$_"; New-Item -ItemType Directory -Path $deepPath -Force | Out-Null }
"deep file" | Set-Content -Path "$deepPath\bottom.txt"

# 4. Long path (near MAX_PATH limit)
$longDir = Join-Path $TestRoot "long_path_here"
New-Item -ItemType Directory -Path $longDir -Force | Out-Null
$longFileName = 'a' * (255 - $longDir.Length)
"long path file" | Set-Content -Path "$longDir\$longFileName.txt"

# 5. Files that will trigger "access denied" (requires changing permissions)
New-Item -ItemType Directory -Path "$TestRoot\protected" -Force | Out-Null
"protected file" | Set-Content -Path "$TestRoot\protected\secret.txt"
Set-AdministratorDeniedInheritance -Path "$TestRoot\protected"

# 6. Folder that cannot be enumerated
New-Item -ItemType Directory -Path "$TestRoot\forbidden" -Force | Out-Null
"secret" | Set-Content -Path "$TestRoot\forbidden\hidden.txt"
Set-AdministratorDeniedInheritance -Path "$TestRoot\forbidden"

# 7. File in use simulation
New-Item -ItemType Directory -Path "$TestRoot\inuse" -Force | Out-Null
"locked file" | Set-Content -Path "$TestRoot\inuse\locked.txt"

Write-Host "Test data setup complete!"
Write-Host ""
Write-Host "Run fix-inheritance with:"
Write-Host "  pwsh -File src/Fix-Inheritance.ps1 -TargetPath $TestRoot -OutputPath output/TestResults.csv -LogPath output/TestResults.log"
Write-Host ""
Write-Host "After testing, clean up with:"
Write-Host "  Remove-Item -Path $TestRoot -Recurse -Force"
