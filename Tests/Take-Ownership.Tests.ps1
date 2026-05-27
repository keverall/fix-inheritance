Describe "Take-Ownership.ps1 - Parameter Validation" {
    It "Should have CsvPath as mandatory parameter" {
        $scriptPath = "$PSScriptRoot/../Take-Ownership.ps1"
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
        $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq "CsvPath" }
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes.ArgumentNamePairs | Where-Object { $_.ArgumentName -eq "Mandatory" } | Should -Not -BeNullOrEmpty
    }

    It "Should have OutputCsv as optional parameter" {
        $scriptPath = "$PSScriptRoot/../Take-Ownership.ps1"
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
        $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq "OutputCsv" }
        $param | Should -Not -BeNullOrEmpty
    }

    It "Should have no syntax errors" {
        $scriptPath = "$PSScriptRoot/../Take-Ownership.ps1"
        $errors = @()
        $tokens = @()
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It "Should exit with error when CSV file does not exist" {
        $scriptPath = "$PSScriptRoot/../Take-Ownership.ps1"
        & pwsh -NoProfile -Command "& '$scriptPath' -CsvPath 'Z:\NonExistent\file.csv' 2>&1"
        $LASTEXITCODE | Should -Not -Be 0
    }
}

Describe "Take-Ownership.bat - Basic Validation" {
    It "Should exist and be non-empty" {
        $batPath = "$PSScriptRoot/../Take-Ownership.bat"
        $batPath | Should -Exist
        (Get-Item $batPath).Length | Should -BeGreaterThan 0
    }

    It "Should contain takeown command" {
        $batPath = "$PSScriptRoot/../Take-Ownership.bat"
        Get-Content $batPath | Should -Match 'takeown'
    }

    It "Should contain icacls command" {
        $batPath = "$PSScriptRoot/../Take-Ownership.bat"
        Get-Content $batPath | Should -Match 'icacls'
    }

    It "Should contain enabledelayedexpansion" {
        $batPath = "$PSScriptRoot/../Take-Ownership.bat"
        Get-Content $batPath | Should -Match 'setlocal enabledelayedexpansion'
    }
}
