# Tests for Windows Container using WinBoat network share
# 
# PREREQUISITES:
# 1. Run a Windows container that supports docker exec with PowerShell:
#    docker run -d --name win-test -p 5985:5985 mcr.microsoft.com/windows/servercore:ltsc2022
#
# 2. Mount the repo: C:\Users\keverall\repos\fix-inheritance
#
# 3. Run tests:
#    pwsh ./Tests/WinBoat.Tests.ps1

$winBoatAvailable = $false
try {
    $result = docker exec WinBoat powershell -Command "Write-Host 'test'" 2>$null
    if ($result -and $result -notmatch "OCI runtime") {
        $winBoatAvailable = $true
    }
} catch {}

Describe "WinBoat Windows Container Tests" {
    It "WinBoat container supports docker exec PowerShell" -Skip:(-not $winBoatAvailable) {
        $winBoatAvailable | Should -Be $true
    }
}

Describe "Windows Fix-Inheritance Tests" -Skip:(-not $winBoatAvailable) {
    BeforeAll {
        $script:repoPath = "C:\Users\keverall\repos\fix-inheritance"
        
        function script:Invoke-WinCmd {
            param([string]$Command)
            docker exec WinBoat powershell -Command $Command 2>&1
        }
    }
    
    It "Fix-Inheritance handles special character filenames on PS 5.1" {
        $testDir = "C:\temp\fitest-special-$(Get-Random)"
        Invoke-WinCmd "New-Item -ItemType Directory -Path '$testDir' -Force" > $null
        
        $files = @("file with spaces.txt", "file,comma.txt", "file""quote.txt")
        foreach ($f in $files) {
            Invoke-WinCmd "New-Item -ItemType File -Path '$testDir\$f' -Force" > $null
        }
        
        $csv = "$testDir\out.csv"
        $log = "$testDir\out.log"
        $result = Invoke-WinCmd "& '$script:repoPath\src\Fix-Inheritance.ps1' -TargetPath '$testDir' -OutputPath '$csv' -LogPath '$log'"
        
        Invoke-WinCmd "Remove-Item -Path '$testDir' -Recurse -Force" > $null
        
        $result | Should -Match "Done"
    }
    
    It "Fix-Inheritance handles non-existent path on PS 5.1" {
        $result = Invoke-WinCmd "& '$script:repoPath\src\Fix-Inheritance.ps1' -TargetPath 'X:\nonexistent' -OutputPath 'C:\temp\out.csv' -LogPath 'C:\temp\out.log'"
        $result | Should -Match "Target path does not exist"
    }
    
    AfterEach {
        Invoke-WinCmd "Remove-Item -Path 'C:\temp\fitest-*' -Recurse -Force -ErrorAction SilentlyContinue" > $null
    }
}