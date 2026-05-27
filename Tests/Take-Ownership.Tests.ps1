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

Describe "Take-Ownership.bat" {
    BeforeAll {
        $script:batPath = "$PSScriptRoot/../src/Take-Ownership.bat"
    }

    It "Should exist and be non-empty" {
        $script:batPath | Should -Exist
        (Get-Item $script:batPath).Length | Should -BeGreaterThan 0
    }

    It "Should contain takeown command" {
        Get-Content $script:batPath | Should -Match 'takeown'
    }

    It "Should contain icacls command" {
        Get-Content $script:batPath | Should -Match 'icacls'
    }

    It "Should contain enabledelayedexpansion" {
        Get-Content $script:batPath | Should -Match 'setlocal enabledelayedexpansion'
    }
}
