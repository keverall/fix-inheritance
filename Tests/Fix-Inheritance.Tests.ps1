Describe "Fix-Inheritance.ps1 - Parameter Validation" {
    It "Should have TargetPath as mandatory parameter" {
        $scriptPath = "$PSScriptRoot/../Fix-Inheritance.ps1"
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
        $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq "TargetPath" }
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes.ArgumentNamePairs | Where-Object { $_.ArgumentName -eq "Mandatory" } | Should -Not -BeNullOrEmpty
    }

    It "Should have OutputPath as optional parameter with default" {
        $scriptPath = "$PSScriptRoot/../Fix-Inheritance.ps1"
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
        $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq "OutputPath" }
        $param | Should -Not -BeNullOrEmpty
        $param.DefaultValue.Extent.Text | Should -Be '".\FailedInheritance"'
    }

    It "Should have no syntax errors" {
        $scriptPath = "$PSScriptRoot/../Fix-Inheritance.ps1"
        $errors = @()
        $tokens = @()
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It "Should exit with error when TargetPath does not exist" {
        $scriptPath = "$PSScriptRoot/../Fix-Inheritance.ps1"
        $result = & pwsh -NoProfile -Command "& '$scriptPath' -TargetPath 'Z:\NonExistent\Path' 2>&1"
        $LASTEXITCODE | Should -Not -Be 0
    }
}
