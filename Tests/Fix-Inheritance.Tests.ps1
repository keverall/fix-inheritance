BeforeAll {
    function Get-ScriptInfo {
        param([string]$ScriptPath)
        $errors = @()
        $tokens = @()
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $ScriptPath, [ref]$tokens, [ref]$errors
        )
        return @{ Ast = $ast; Errors = $errors; Content = Get-Content -Path $ScriptPath -Raw }
    }
}

Describe "Fix-Inheritance.ps1" {
    BeforeAll {
        $info = Get-ScriptInfo "$PSScriptRoot/../src/Fix-Inheritance.ps1"
        $script:ast     = $info.Ast
        $script:errors  = $info.Errors
        $script:content = $info.Content
    }

    It "Should have no syntax errors" {
        $script:errors.Count | Should -Be 0
    }

    It "Should have <Name> parameter with Mandatory=<Mandatory>" -TestCases @(
        @{ Name = "TargetPath"; Mandatory = $true  }
        @{ Name = "OutputPath"; Mandatory = $false }
    ) {
        $param = $script:ast.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq $Name }
        $param | Should -Not -BeNullOrEmpty

        $mandatoryAttr = $param.Attributes.ArgumentNamePairs |
            Where-Object { $_.ArgumentName -eq "Mandatory" }

        if ($Mandatory) {
            $mandatoryAttr | Should -Not -BeNullOrEmpty
            $mandatoryAttr.Argument.Extent.Text | Should -Be '$true'
        } else {
            # Optional param: either no Mandatory attribute, or set to $false
            if ($mandatoryAttr) {
                $mandatoryAttr.Argument.Extent.Text | Should -Be '$false'
            }
        }
    }

    It "OutputPath should default to '.\FailedInheritance'" {
        $param = $script:ast.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq "OutputPath" }
        $param.DefaultValue.Extent.Text | Should -Be '".\FailedInheritance"'
    }

    It "Should define Get-ErrorReason helper function" {
        $script:ast.FindAll(
            { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ErrorReason' },
            $true
        ) | Should -Not -BeNullOrEmpty
    }

    It "Should define Add-Failure helper function" {
        $script:ast.FindAll(
            { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Add-Failure' },
            $true
        ) | Should -Not -BeNullOrEmpty
    }

    It "Should exit with error when TargetPath does not exist" {
        & pwsh -NoProfile -Command "
            & '$PSScriptRoot/../src/Fix-Inheritance.ps1' -TargetPath 'Z:\NonExistent\Path' 2>&1
            exit `$LASTEXITCODE
        "
        $LASTEXITCODE | Should -Not -Be 0
    }
}

Describe "Take-Ownership.ps1" {
    BeforeAll {
        $info = Get-ScriptInfo "$PSScriptRoot/../src/Take-Ownership.ps1"
        $script:ast     = $info.Ast
        $script:errors  = $info.Errors
        $script:content = $info.Content
    }

    It "Should have no syntax errors" {
        $script:errors.Count | Should -Be 0
    }

    It "Should have <Name> parameter with Mandatory=<Mandatory>" -TestCases @(
        @{ Name = "CsvPath";   Mandatory = $true  }
        @{ Name = "OutputCsv"; Mandatory = $false }
    ) {
        $param = $script:ast.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq $Name }
        $param | Should -Not -BeNullOrEmpty

        $mandatoryAttr = $param.Attributes.ArgumentNamePairs |
            Where-Object { $_.ArgumentName -eq "Mandatory" }

        if ($Mandatory) {
            $mandatoryAttr | Should -Not -BeNullOrEmpty
            $mandatoryAttr.Argument.Extent.Text | Should -Be '$true'
        } else {
            if ($mandatoryAttr) {
                $mandatoryAttr.Argument.Extent.Text | Should -Be '$false'
            }
        }
    }

    It "Should exit with error when CSV file does not exist" {
        & pwsh -NoProfile -Command "
            & '$PSScriptRoot/../src/Take-Ownership.ps1' -CsvPath 'Z:\NonExistent\file.csv' 2>&1
            exit `$LASTEXITCODE
        "
        $LASTEXITCODE | Should -Not -Be 0
    }
}
