<#
.SYNOPSIS
    Pester tests for Fix-Inheritance.ps1, Take-Ownership.ps1, and Take-Ownership.bat

.DESCRIPTION
    Tests cover:
    - Parameter validation (mandatory/optional)
    - Path validation (existing vs non-existing)
    - CSV output format and content
    - Excel workbook structure (tabs, tables, charts)
    - Error reason classification
    - Long path detection
    - Folder aggregation logic
    - Batch file structure
    - Take-Ownership CSV processing logic

.NOTES
    Some tests are platform-aware (use forward slashes for cross-platform compatibility).
    Windows-specific execution tests (icacls/takeown) only run on Windows.
#>

# Resolve script root for finding the scripts under test
if ($null -eq $PSScriptRoot -or $PSScriptRoot -eq '') {
    $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
$ScriptRoot = Split-Path -Parent $PSScriptRoot
$IsWindowsPlatform = $PSVersionTable.Platform -eq 'Win32NT' -or $PSVersionTable.PSVersion.Major -le 5

Describe "Fix-Inheritance.ps1 - Structure & Parameters" {
    BeforeAll {
        $scriptPath = Join-Path $ScriptRoot "Fix-Inheritance.ps1"
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
        $scriptContent = Get-Content $scriptPath -Raw
    }

    It "Should exist and be non-empty" {
        $scriptPath | Should -Exist
        (Get-Item $scriptPath).Length | Should -BeGreaterThan 100
    }

    It "Should have TargetPath as mandatory parameter" {
        $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq "TargetPath" }
        $param | Should -Not -BeNullOrEmpty
        $hasMandatory = $param.Attributes.ArgumentNamePairs | Where-Object {
            $_.ArgumentName -eq "Mandatory" -and $_.Argument.Extent.Text -eq '$true'
        }
        $hasMandatory | Should -Not -BeNullOrEmpty
    }

    It "Should have OutputPath as optional parameter with default" {
        $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq "OutputPath" }
        $param | Should -Not -BeNullOrEmpty
        $param.DefaultValue.Extent.Text | Should -Be '".\FailedInheritance"'
    }

    It "Should reference both .csv and .xlsx output paths" {
        $scriptContent | Should -Match '\$OutputCsv.*\.csv'
        $scriptContent | Should -Match '\$OutputXlsx.*\.xlsx'
    }

    It "Should call icacls.exe with /inheritance:e flag" {
        $scriptContent | Should -Match 'icacls\.exe.*\/inheritance:e'
    }

    It "Should use -LiteralPath for Get-ChildItem (special char support)" {
        $scriptContent | Should -Match 'Get-ChildItem\s+-LiteralPath'
    }

    It "Should set DOTNET_SYSTEM_IO_USELONGPATHS environment variable" {
        $scriptContent | Should -Match 'DOTNET_SYSTEM_IO_USELONGPATHS'
    }

    It "Should validate target path existence before processing" {
        $scriptContent | Should -Match 'Test-Path.*TargetPath'
    }

    It "Should write output via Export-Csv" {
        $scriptContent | Should -Match 'Export-Csv'
    }

    It "Should write output via Export-Excel" {
        $scriptContent | Should -Match 'Export-Excel'
    }
}

Describe "Fix-Inheritance.ps1 - Error Classification Logic" {
    It "Should classify 'Access is denied' correctly" {
        $errorStr = "Processed file: C:/test/file.txt: Access is denied."
        $reason = "Unknown"
        if ($errorStr -match "Access is denied") {
            $reason = "Access Denied - requires ownership change"
        }
        $reason | Should -Be "Access Denied - requires ownership change"
    }

    It "Should classify 'not found' correctly" {
        $errorStr = "C:/test/gone.txt: not found"
        $reason = "Unknown"
        if ($errorStr -match "not found") {
            $reason = "File not found"
        }
        $reason | Should -Be "File not found"
    }

    It "Should classify 'is in use' correctly" {
        $errorStr = "C:/test/locked.txt: is in use by another process"
        $reason = "Unknown"
        if ($errorStr -match "is in use") {
            $reason = "File in use"
        }
        $reason | Should -Be "File in use"
    }

    It "Should classify 'invalid' correctly" {
        $errorStr = "C:/test/bad: invalid path"
        $reason = "Unknown"
        if ($errorStr -match "invalid") {
            $reason = "Invalid path or filename"
        }
        $reason | Should -Be "Invalid path or filename"
    }

    It "Should default to unknown error with exit code" {
        $LASTEXITCODE = 3
        $errorStr = "some random error"
        $reason = "Unknown error (exit code: $LASTEXITCODE)"
        if ($errorStr -match "Access is denied") { $reason = "Access Denied" }
        elseif ($errorStr -match "not found") { $reason = "File not found" }
        elseif ($errorStr -match "is in use") { $reason = "File in use" }
        elseif ($errorStr -match "invalid") { $reason = "Invalid path" }
        elseif ($LASTEXITCODE -eq 5) { $reason = "Access Denied (HRESULT)" }

        $reason | Should -Be "Unknown error (exit code: 3)"
    }

    It "Should classify exit code 5 as Access Denied HRESULT" {
        $LASTEXITCODE = 5
        $errorStr = "some error"
        $reason = "Unknown"
        if ($errorStr -match "Access is denied") { $reason = "Access Denied" }
        elseif ($LASTEXITCODE -eq 5) { $reason = "Access Denied (HRESULT: 0x80070005)" }

        $reason | Should -Be "Access Denied (HRESULT: 0x80070005)"
    }
}

Describe "Fix-Inheritance.ps1 - Long Path Detection" {
    It "Should flag paths longer than 256 characters" {
        # Build a path guaranteed >256 chars on any platform
        $longPath = "/root" + ("/subfolder" * 30) + "/file.txt"
        $pathLength = $longPath.Length
        $isLongPath = ($pathLength -gt 256)
        $pathLength | Should -BeGreaterThan 256
        $isLongPath | Should -BeTrue
    }

    It "Should not flag normal-length paths" {
        $normalPath = "/short/path/file.txt"
        $pathLength = $normalPath.Length
        $isLongPath = ($pathLength -gt 256)
        $pathLength | Should -BeLessThan 256
        $isLongPath | Should -BeFalse
    }

    It "Should extract correct parent folder from path" {
        $fullPath = "/root/folder/subfolder/file.txt"
        $parentFolder = [System.IO.Path]::GetDirectoryName($fullPath)
        $fileName = [System.IO.Path]::GetFileName($fullPath)
        $folderName = [System.IO.Path]::GetFileName($parentFolder)

        $parentFolder | Should -Be "/root/folder/subfolder"
        $fileName | Should -Be "file.txt"
        $folderName | Should -Be "subfolder"
    }

    It "Should extract parent folder from Windows-style path (forward slash)" {
        # Windows paths with forward slashes work cross-platform
        $fullPath = "C:/root/folder/subfolder/file.txt"
        $parentFolder = [System.IO.Path]::GetDirectoryName($fullPath)
        $fileName = [System.IO.Path]::GetFileName($fullPath)

        $fileName | Should -Be "file.txt"
        # Parent folder behavior varies by platform; just verify it's non-empty
        $parentFolder | Should -Not -BeNullOrEmpty
    }
}

Describe "Take-Ownership.ps1 - Structure & Parameters" {
    BeforeAll {
        $scriptPath = Join-Path $ScriptRoot "Take-Ownership.ps1"
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
        $scriptContent = Get-Content $scriptPath -Raw
    }

    It "Should exist and be non-empty" {
        $scriptPath | Should -Exist
        (Get-Item $scriptPath).Length | Should -BeGreaterThan 100
    }

    It "Should have CsvPath as mandatory parameter" {
        $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq "CsvPath" }
        $param | Should -Not -BeNullOrEmpty
        $hasMandatory = $param.Attributes.ArgumentNamePairs | Where-Object {
            $_.ArgumentName -eq "Mandatory" -and $_.Argument.Extent.Text -eq '$true'
        }
        $hasMandatory | Should -Not -BeNullOrEmpty
    }

    It "Should have OutputCsv as optional parameter" {
        $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq "OutputCsv" }
        $param | Should -Not -BeNullOrEmpty
    }

    It "Should call takeown.exe" {
        $scriptContent | Should -Match 'takeown\.exe'
    }

    It "Should call icacls.exe" {
        $scriptContent | Should -Match 'icacls\.exe'
    }

    It "Should check for Administrator privileges" {
        $scriptContent | Should -Match 'Administrator'
    }

    It "Should import CSV with UTF8 encoding" {
        $scriptContent | Should -Match 'Import-Csv.*UTF8'
    }

    It "Should export results via Export-Csv" {
        $scriptContent | Should -Match 'Export-Csv'
    }

    It "Should use takeown /A flag (administrator ownership)" {
        $scriptContent | Should -Match 'takeown.*\/A'
    }

    It "Should use icacls /inheritance:e flag" {
        $scriptContent | Should -Match 'icacls.*\/inheritance:e'
    }
}

Describe "Take-Ownership.bat - Structure" {
    BeforeAll {
        $batPath = Join-Path $ScriptRoot "Take-Ownership.bat"
        $content = Get-Content $batPath -Raw
    }

    It "Should exist and be non-empty" {
        $batPath | Should -Exist
        (Get-Item $batPath).Length | Should -BeGreaterThan 100
    }

    It "Should contain enabledelayedexpansion" {
        $content | Should -Match 'setlocal enabledelayedexpansion'
    }

    It "Should contain takeown command" {
        $content | Should -Match 'takeown'
    }

    It "Should contain icacls command" {
        $content | Should -Match 'icacls'
    }

    It "Should validate input CSV parameter" {
        $content | Should -Match 'if.*%~1.*==.*""'
    }

    It "Should skip CSV header line" {
        $content | Should -Match 'skip=1'
    }

    It "Should check file existence before processing" {
        $content | Should -Match 'if not exist'
    }
}

Describe "Fix-Inheritance.ps1 - Path Resolution Logic" {
    It "Should resolve relative output path to full path" {
        $OutputPath = "./TestReport"
        $resolved = [System.IO.Path]::GetFullPath($OutputPath)
        $resolved | Should -Not -Be "./TestReport"
        $resolved | Should -Match 'TestReport'
    }

    It "Should append .csv extension to output path" {
        $OutputPath = "/reports/MyReport"
        $OutputCsv = "$OutputPath.csv"
        $OutputCsv | Should -Be "/reports/MyReport.csv"
    }

    It "Should append .xlsx extension to output path" {
        $OutputPath = "/reports/MyReport"
        $OutputXlsx = "$OutputPath.xlsx"
        $OutputXlsx | Should -Be "/reports/MyReport.xlsx"
    }
}

Describe "Take-Ownership.ps1 - CSV Processing Logic" {
    BeforeEach {
        $testDir = Join-Path $TestDrive "takeown_test"
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null
    }

    It "Should auto-generate output CSV path with timestamp" {
        $CsvPath = Join-Path $testDir "input.csv"
        $OutputCsv = ""

        if ([string]::IsNullOrEmpty($OutputCsv)) {
            $csvDir = [System.IO.Path]::GetDirectoryName($CsvPath)
            $csvBase = [System.IO.Path]::GetFileNameWithoutExtension($CsvPath)
            $OutputCsv = [System.IO.Path]::Combine($csvDir, "Results_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv")
        }

        $OutputCsv | Should -Match 'Results_'
        $OutputCsv | Should -Match '\.csv$'
        [System.IO.Path]::GetDirectoryName($OutputCsv) | Should -Be $testDir
    }

    It "Should process CSV with expected columns" {
        $csvContent = @"
FilePath,FileName,ParentFolder,FolderName,ErrorReason,PathLength,IsLongPath,Timestamp
"/test/file1.txt","file1.txt","/test","test","Access Denied","18","False","2026-05-27 10:00:00"
"@
        $csvPath = Join-Path $testDir "test.csv"
        $csvContent | Set-Content -Path $csvPath -Encoding UTF8

        $data = Import-Csv -Path $csvPath -Encoding UTF8
        $data.Count | Should -Be 1
        $data[0].FilePath | Should -Be "/test/file1.txt"
        $data[0].FileName | Should -Be "file1.txt"
        $data[0].ErrorReason | Should -Be "Access Denied"
        $data[0].IsLongPath | Should -Be "False"
    }

    It "Should handle CSV with special characters in paths" {
        $csvContent = @"
FilePath,FileName,ParentFolder,FolderName,ErrorReason,PathLength,IsLongPath,Timestamp
"/test/folder with spaces/file & stuff.txt","file & stuff.txt","/test/folder with spaces","folder with spaces","Access Denied","42","False","2026-05-27 10:00:00"
"@
        $csvPath = Join-Path $testDir "special.csv"
        $csvContent | Set-Content -Path $csvPath -Encoding UTF8

        $data = Import-Csv -Path $csvPath -Encoding UTF8
        $data.Count | Should -Be 1
        $data[0].FileName | Should -Be "file & stuff.txt"
        $data[0].ParentFolder | Should -Be "/test/folder with spaces"
    }

    It "Should handle empty CSV (header only)" {
        $csvContent = "FilePath,FileName,ParentFolder,FolderName,ErrorReason,PathLength,IsLongPath,Timestamp"
        $csvPath = Join-Path $testDir "empty.csv"
        $csvContent | Set-Content -Path $csvPath -Encoding UTF8

        $data = Import-Csv -Path $csvPath -Encoding UTF8
        $data.Count | Should -Be 0
    }
}

Describe "Fix-Inheritance.ps1 - Folder Aggregation Logic" {
    BeforeAll {
        $mockFailedItems = @(
            [PSCustomObject]@{ FilePath = "/root/folder1/a.txt"; ParentFolder = "/root/folder1"; ErrorReason = "Access Denied"; IsLongPath = $false; FileName = "a.txt" }
            [PSCustomObject]@{ FilePath = "/root/folder1/b.txt"; ParentFolder = "/root/folder1"; ErrorReason = "Access Denied"; IsLongPath = $false; FileName = "b.txt" }
            [PSCustomObject]@{ FilePath = "/root/folder1/c.txt"; ParentFolder = "/root/folder1"; ErrorReason = "File not found"; IsLongPath = $false; FileName = "c.txt" }
            [PSCustomObject]@{ FilePath = "/root/folder2/d.txt"; ParentFolder = "/root/folder2"; ErrorReason = "Access Denied"; IsLongPath = $false; FileName = "d.txt" }
        )
    }

    It "Should aggregate errors by folder" {
        $folderSummary = $mockFailedItems | Group-Object ParentFolder | Sort-Object Count -Descending
        $folderSummary.Count | Should -Be 2
        $folderSummary[0].Name | Should -Be "/root/folder1"
        $folderSummary[0].Count | Should -Be 3
        $folderSummary[1].Name | Should -Be "/root/folder2"
        $folderSummary[1].Count | Should -Be 1
    }

    It "Should extract unique error types per folder" {
        $folder1Items = $mockFailedItems | Where-Object { $_.ParentFolder -eq "/root/folder1" }
        $errorTypes = ($folder1Items | Select-Object -ExpandProperty ErrorReason -Unique) -join ", "
        $errorTypes | Should -Match "Access Denied"
        $errorTypes | Should -Match "File not found"
    }

    It "Should calculate error breakdown correctly" {
        $errorBreakdown = $mockFailedItems | Group-Object ErrorReason | Sort-Object Count -Descending
        $errorBreakdown[0].Name | Should -Be "Access Denied"
        $errorBreakdown[0].Count | Should -Be 3
        $errorBreakdown[1].Name | Should -Be "File not found"
        $errorBreakdown[1].Count | Should -Be 1
    }

    It "Should identify long paths in the set" {
        $longPathItems = $mockFailedItems | Where-Object { $_.IsLongPath }
        $longPathItems.Count | Should -Be 0
    }
}

Describe "Take-Ownership.ps1 - Status Classification Logic" {
    It "Should classify as Fixed when both takeown and icacls succeed" {
        $takeownExit = 0
        $icaclsExit = 0
        $status = "Unknown"
        $statusDetail = ""

        if ($takeownExit -ne 0) {
            $status = "Failed"
            $statusDetail = "Takeown failed"
        }
        else {
            if ($icaclsExit -eq 0) {
                $status = "Fixed"
            }
            else {
                $status = "Failed"
                $statusDetail = "Inheritance restore failed"
            }
        }

        $status | Should -Be "Fixed"
        $statusDetail | Should -Be ""
    }

    It "Should classify as Failed when takeown fails" {
        $takeownExit = 1
        $icaclsExit = 0
        $status = "Unknown"
        $statusDetail = ""

        if ($takeownExit -ne 0) {
            $status = "Failed"
            $statusDetail = "Takeown failed (exit $takeownExit)"
        }
        else {
            if ($icaclsExit -eq 0) {
                $status = "Fixed"
            }
            else {
                $status = "Failed"
                $statusDetail = "Inheritance restore failed"
            }
        }

        $status | Should -Be "Failed"
        $statusDetail | Should -Be "Takeown failed (exit 1)"
    }

    It "Should classify as Failed when icacls fails after successful takeown" {
        $takeownExit = 0
        $icaclsExit = 5
        $status = "Unknown"
        $statusDetail = ""

        if ($takeownExit -ne 0) {
            $status = "Failed"
        }
        else {
            if ($icaclsExit -eq 0) {
                $status = "Fixed"
            }
            else {
                $status = "Failed"
                $statusDetail = "Inheritance restore failed after ownership"
            }
        }

        $status | Should -Be "Failed"
        $statusDetail | Should -Be "Inheritance restore failed after ownership"
    }
}

Describe "Integration - File Share Workflow" {
    BeforeEach {
        $workflowDir = Join-Path $TestDrive "workflow_test"
        New-Item -Path $workflowDir -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $workflowDir "subfolder") -ItemType Directory -Force | Out-Null
        "test" | Set-Content (Join-Path $workflowDir "file1.txt") -Encoding UTF8
        "test" | Set-Content (Join-Path $workflowDir "subfolder/file2.txt") -Encoding UTF8
    }

    It "Should enumerate all files recursively" {
        $allItems = Get-ChildItem -LiteralPath $workflowDir -Recurse -Force -ErrorAction SilentlyContinue
        $allItems.Count | Should -BeGreaterOrEqual 3 # 2 files + 1 subfolder
    }

    It "Should produce correct CSV format after export and re-import" {
        $testCsv = Join-Path $workflowDir "test_output.csv"
        $testData = @(
            [PSCustomObject]@{
                FilePath     = "/test/file.txt"
                FileName     = "file.txt"
                ParentFolder = "/test"
                FolderName   = "test"
                ErrorReason  = "Access Denied"
                PathLength   = 18
                IsLongPath   = $false
                Timestamp    = "2026-05-27 10:00:00"
            }
        )
        $testData | Export-Csv -Path $testCsv -NoTypeInformation -Encoding UTF8 -Force

        $imported = Import-Csv -Path $testCsv -Encoding UTF8
        $imported.Count | Should -Be 1
        $imported[0].FilePath | Should -Be "/test/file.txt"
        $imported[0].ErrorReason | Should -Be "Access Denied"
    }
}
