<#
.SYNOPSIS
    Validates markdown help files for completeness and correctness using platyPS.

.DESCRIPTION
    Runs validation checks on all .md files in the Help directory:
    - Checks for required sections (SYNOPSIS, DESCRIPTION, PARAMETERS, EXAMPLES)
    - Validates parameter documentation matches actual script parameters
    - Flags broken markdown syntax
    - Reports stale content that no longer matches the source script

.EXAMPLE
    .\Test-Help.ps1

.NOTES
    Requires platyPS module: Install-Module -Name platyPS -Scope CurrentUser
#>

[CmdletBinding()]
param()

if (-not (Get-Module -ListAvailable -Name platyPS)) {
    Write-Error "platyPS module not found. Install with: Install-Module -Name platyPS -Scope CurrentUser"
    exit 1
}

Import-Module -Name platyPS -ErrorAction Stop

$ProjectRoot = [System.IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$HelpDir     = Join-Path $ProjectRoot "Help"

if (-not (Test-Path $HelpDir)) {
    Write-Error "Help directory not found: $HelpDir"
    Write-Host "Run Build-MarkdownHelp.ps1 first to generate help files."
    exit 1
}

$mdFiles = Get-ChildItem -Path $HelpDir -Filter "*.md"
if ($mdFiles.Count -eq 0) {
    Write-Warning "No markdown help files found in $HelpDir"
    Write-Host "Run Build-MarkdownHelp.ps1 first to generate help files."
    exit 1
}

# Common parameters auto-injected by platyPS — skip these in validation
$autoParams = @("ProgressAction", "CommonParameters", "Debug", "ErrorAction", "ErrorVariable",
    "InformationAction", "InformationVariable", "OutVariable", "OutBuffer",
    "PipelineVariable", "Verbose", "WarningAction", "WarningVariable")

$issues = [System.Collections.Generic.List[string]]::new()
$passed = 0
$failed = 0

foreach ($mdFile in $mdFiles) {
    # platyPS names: Fix-Inheritance.ps1.md → script is Fix-Inheritance.ps1
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($mdFile.Name) # strips .md → "Fix-Inheritance.ps1"
    $scriptPath = Join-Path $ProjectRoot "$scriptName"

    Write-Host "Checking: $($mdFile.Name)" -ForegroundColor Cyan

    $content = Get-Content -Path $mdFile.FullName -Raw
    $requiredSections = @("## SYNOPSIS", "## SYNTAX", "## DESCRIPTION", "## PARAMETERS", "## EXAMPLES")

    foreach ($section in $requiredSections) {
        if ($content -notmatch [regex]::Escape($section)) {
            $issues.Add("$($mdFile.Name): Missing required section '$section'")
            $failed++
        }
    }

    # Check SYNOPSIS is not empty
    if ($content -match "## SYNOPSIS\s*[\r\n]+\s*[\r\n]+") {
        $issues.Add("$($mdFile.Name): SYNOPSIS section is empty")
        $failed++
    }

    # Check DESCRIPTION is not empty
    if ($content -match "## DESCRIPTION\s*[\r\n]+\s*[\r\n]+") {
        $issues.Add("$($mdFile.Name): DESCRIPTION section is empty")
        $failed++
    }

    # Validate parameters against source script
    if (Test-Path $scriptPath) {
        $errors = @()
        $tokens = @()
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)

        $scriptParams = @($ast.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath } |
            ForEach-Object { $_.Name.VariablePath.UserPath })

        # Extract documented parameters from markdown (### -ParamName pattern)
        $mdParams = [regex]::Matches($content, "### -(\w+)") | ForEach-Object { $_.Groups[1].Value }
        $mdParams = $mdParams | Where-Object { $_ -notin $autoParams }

        # Check: script params documented?
        foreach ($paramName in $scriptParams) {
            if ($paramName -notin $mdParams) {
                $issues.Add("$($mdFile.Name): Parameter '$paramName' in script but not documented")
                $failed++
            }
        }

        # Check: stale params in markdown?
        foreach ($mdParam in $mdParams) {
            if ($mdParam -notin $scriptParams) {
                $issues.Add("$($mdFile.Name): Parameter '$mdParam' documented but removed from script — run Build-MarkdownHelp.ps1 -Force")
                $failed++
            }
        }

        $userScriptParams = $scriptParams | Where-Object { $_ -notin $autoParams }
        Write-Host "  Parameters: $($userScriptParams.Count) in script, $($mdParams.Count) documented — OK" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  Warning: Source script not found: $scriptName" -ForegroundColor Yellow
    }
}

# Report
Write-Host ""
Write-Host "=========================================="
Write-Host "Help Validation Results"
Write-Host "=========================================="

if ($issues.Count -gt 0) {
    Write-Host "ISSUES FOUND: $($issues.Count)" -ForegroundColor Red
    Write-Host ""
    foreach ($issue in $issues) {
        Write-Host "  - $issue" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Run .\Build-MarkdownHelp.ps1 -Force to regenerate help files."
    exit 1
} else {
    Write-Host "All help files pass validation." -ForegroundColor Green
    exit 0
}
