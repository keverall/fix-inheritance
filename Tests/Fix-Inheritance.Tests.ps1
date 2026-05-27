Describe "Fix-Inheritance.ps1" {
    BeforeAll {
        $scriptPath = "$PSScriptRoot/../src/Fix-Inheritance.ps1"
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

    It "Should have TargetPath as mandatory parameter" {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
        $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq "TargetPath" }
        $param | Should -Not -BeNullOrEmpty
    }

    It "Should exit with error when TargetPath does not exist" {
        & pwsh -NoProfile -Command "& '$scriptPath' -TargetPath 'Z:\NonExistent\Path' 2>&1"
        $LASTEXITCODE | Should -Not -Be 0
    }
}
