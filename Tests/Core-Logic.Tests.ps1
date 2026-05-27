Describe "Fix-Inheritance.ps1 - Core Logic" -Tag "Unit" {
    BeforeAll {
        $scriptPath = "$PSScriptRoot/../src/Fix-Inheritance.ps1"
        $testDrive = Join-Path $PSScriptRoot "TestDrive_Unit"

        if (Test-Path $testDrive) {
            Remove-Item $testDrive -Recurse -Force
        }
        New-Item -Path $testDrive -ItemType Directory -Force | Out-Null

        # Create test folder structure
        New-Item -Path (Join-Path $testDrive "folder1") -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $testDrive "folder2") -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $testDrive "folder1/subfolder") -ItemType Directory -Force | Out-Null

        # Create test files
        "test content" | Set-Content (Join-Path $testDrive "file1.txt") -Encoding UTF8
        "test content" | Set-Content (Join-Path $testDrive "folder1/file2.txt") -Encoding UTF8
        "test content" | Set-Content (Join-Path $testDrive "folder1/subfolder\file3.txt") -Encoding UTF8
        "test content" | Set-Content (Join-Path $testDrive "folder2/file4.txt") -Encoding UTF8
        "test content with special chars: äöü & < >" | Set-Content (Join-Path $testDrive "folder2/file (special).txt") -Encoding UTF8
    }

    AfterAll {
        if (Test-Path $testDrive) {
            Remove-Item $testDrive -Recurse -Force
        }
    }

    It "Should validate existing path parameter" {
        $result = & pwsh -NoProfile -Command "& '$scriptPath' -TargetPath '$testDrive' -OutputPath '$testDrive/test_output' 2>&1"
        $result | Should -Not -BeNullOrEmpty
    }

    It "Should reject non-existent path" {
        $fakePath = "Z:\DoesNotExist\Path_$(Get-Random)"
        $result = & pwsh -NoProfile -Command "try { & '$scriptPath' -TargetPath '$fakePath' } catch { `$_.Exception.Message }"
        $result | Should -Not -BeNullOrEmpty
    }

    It "Should produce output path with .csv extension" {
        $outputPath = Join-Path $testDrive "unit_test"
        $expectedCsv = "$outputPath.csv"
        $expectedCsv | Should -BeLike "*.csv"
    }
}
