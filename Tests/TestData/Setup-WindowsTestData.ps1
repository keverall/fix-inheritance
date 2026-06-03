# Setup script for fix-inheritance tests on Windows
# Run this script as Administrator to create test scenarios

param(
    [string]$TestRoot = "C:\temp\fix-inheritance-tests"
)

Write-Host "Setting up fix-inheritance test data at $TestRoot"

# Clean up existing test directory
if (Test-Path $TestRoot) {
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
$fileQuote = [char]34
$fileQuotePath = "file$fileQuote.txt"
$filePath = Join-Path "$TestRoot\special" $fileQuotePath
Set-Content -Path $filePath -Value "file$fileQuote.txt"
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
# Remove inherited permissions - this will cause access denied
try {
    $acl = Get-Acl "$TestRoot\protected"
    $acl.SetAccessRuleProtection($true, $false)
    Set-Acl "$TestRoot\protected" $acl
} catch {
    Write-Host "Warning: Could not modify protected folder permissions: $_"
}

# 6. Folder that cannot be enumerated
New-Item -ItemType Directory -Path "$TestRoot\forbidden" -Force | Out-Null
"secret" | Set-Content -Path "$TestRoot\forbidden\hidden.txt"
# Remove all permissions from the folder
try {
    $acl = Get-Acl "$TestRoot\forbidden"
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner([System.Security.Principal.NTAccount]"Administrator")
    Set-Acl "$TestRoot\forbidden" $acl
} catch {
    Write-Host "Warning: Could not modify forbidden folder permissions: $_"
}
# Note: To fully deny access, you would need to remove all access rules
# For testing purposes, we'll just remove inheritance

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
