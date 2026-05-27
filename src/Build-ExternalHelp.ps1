<#
.SYNOPSIS
    Generates MAML external help from platyPS markdown help files.

.DESCRIPTION
    Converts markdown help in the Help directory into a MAML .help.txt file
    that PowerShell can use for Get-Help. Produces output in the Help\en-US
    subdirectory following PowerShell module help conventions.

.PARAMETER OutputDir
    Directory for the compiled help file. Default: Help\en-US

.EXAMPLE
    .\Build-ExternalHelp.ps1

.EXAMPLE
    .\Build-ExternalHelp.ps1 -OutputDir "C:\modules\en-US"

.NOTES
    Requires platyPS module: Install-Module -Name platyPS -Scope CurrentUser
    Markdown help must exist (run Build-MarkdownHelp.ps1 first).
#>

[CmdletBinding()]
param(
    [string]$OutputDir = ""
)

if (-not (Get-Module -ListAvailable -Name platyPS)) {
    Write-Error "platyPS module not found. Install with: Install-Module -Name platyPS -Scope CurrentUser"
    exit 1
}

Import-Module -Name platyPS -ErrorAction Stop

$ProjectRoot = [System.IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$HelpDir     = Join-Path $ProjectRoot "Help"

if (-not (Test-Path $HelpDir)) {
    Write-Error "Help directory not found: $HelpDir"
    Write-Host "Run Build-MarkdownHelp.ps1 first."
    exit 1
}

$mdFiles = Get-ChildItem -Path $HelpDir -Filter "*.md"
if ($mdFiles.Count -eq 0) {
    Write-Error "No markdown help files found in $HelpDir"
    Write-Host "Run Build-MarkdownHelp.ps1 first."
    exit 1
}

if ([string]::IsNullOrEmpty($OutputDir)) {
    $OutputDir = Join-Path $HelpDir "en-US"
}

if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory | Out-Null
}

$compiled = 0
$errors   = 0

foreach ($mdFile in $mdFiles) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($mdFile.Name)
    $outFile = Join-Path $OutputDir "$name-help.xml"

    try {
        New-ExternalHelp -MarkdownPath $mdFile.FullName -OutputPath $outFile -Force | Out-Null
        Write-Host "Compiled: $name-help.xml" -ForegroundColor Green
        $compiled++
    } catch {
        Write-Warning "Failed to compile $name`: $_"
        $errors++
    }
}

Write-Host ""
Write-Host "Compiled: $compiled  Errors: $errors"
Write-Host "Output: $OutputDir"

if ($errors -gt 0) { exit 1 }
