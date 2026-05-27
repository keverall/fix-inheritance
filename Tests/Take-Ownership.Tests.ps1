Describe "Take-Ownership.ps1" {
    BeforeAll {
        $scriptPath = "$PSScriptRoot/../src/Take-Ownership.ps1"
    }

    It "Should exist and be non-empty" {
        $scriptPath | Should -Exist
        (Get-Item $scriptPath).Length | Should -BeGreaterThan 100
    }

    It "Should have no syntax errors" {
        $errors = @()
        $tokens = @()
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It "Should have CsvPath as mandatory parameter" {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
        $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq "CsvPath" }
        $param | Should -Not -BeNullOrEmpty
    }

    It "Should exit with error when CSV file does not exist" {
        & pwsh -NoProfile -Command "& '$scriptPath' -CsvPath 'Z:\NonExistent\file.csv' 2>&1"
        $LASTEXITCODE | Should -Not -Be 0
    }
}

Describe "Take-Ownership.bat" {
    BeforeAll {
        $batPath = "$PSScriptRoot/../src/Take-Ownership.bat"
    }

    It "Should exist and be non-empty" {
        $batPath | Should -Exist
        (Get-Item $batPath).Length | Should -BeGreaterThan 0
    }
}
