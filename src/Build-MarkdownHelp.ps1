<#
.SYNOPSIS
    Generates or updates markdown help from script comment-based help using platyPS.

.DESCRIPTION
    Scans the project root for .ps1 files with comment-based help,
    generates platyPS-compatible markdown in the Help directory,
    and validates the generated markdown.

.PARAMETER Force
    Regenerate all markdown help files even if they already exist.

.EXAMPLE
    .\Build-MarkdownHelp.ps1

.EXAMPLE
    .\Build-MarkdownHelp.ps1 -Force

.NOTES
    Requires platyPS module: Install-Module -Name platyPS -Scope CurrentUser
#>

[CmdletBinding()]
param(
    [switch]$Force
)

if (-not (Get-Module -ListAvailable -Name platyPS)) {
    Write-Error "platyPS module not found. Install with: Install-Module -Name platyPS -Scope CurrentUser"
    exit 1
}

Import-Module -Name platyPS -ErrorAction Stop

$ProjectRoot = [System.IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$HelpDir     = Join-Path $ProjectRoot "Help"
$Scripts     = @(
    (Join-Path $PSScriptRoot "Fix-Inheritance.ps1"),
    (Join-Path $PSScriptRoot "Take-Ownership.ps1")
)

if (-not (Test-Path $HelpDir)) {
    New-Item -Path $HelpDir -ItemType Directory | Out-Null
}

$generated = 0
$updated   = 0
$errors    = 0

foreach ($script in $Scripts) {
    if (-not (Test-Path $script)) {
        Write-Warning "Script not found, skipping: $script"
        continue
    }

    $name = [System.IO.Path]::GetFileNameWithoutExtension($script)

    try {
        $existing = Get-ChildItem -Path $HelpDir -Filter "$name.md" -ErrorAction SilentlyContinue

        if ($existing -and -not $Force) {
            Update-MarkdownHelp -Path $HelpDir -LogPath (Join-Path $HelpDir "update.log") | Out-Null
            Write-Host "Updated: $name.md" -ForegroundColor Yellow
            $updated++
        } else {
            New-MarkdownHelp -Command $script -OutputFolder $HelpDir -Force | Out-Null
            Write-Host "Generated: $name.md" -ForegroundColor Green
            $generated++
        }
    } catch {
        Write-Warning "Failed to process $name`: $_"
        $errors++
    }
}

Write-Host ""
Write-Host "Generated: $generated  Updated: $updated  Errors: $errors"
Write-Host "Help directory: $HelpDir"

if ($errors -gt 0) { exit 1 }
