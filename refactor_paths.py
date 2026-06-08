import os
import re

common_files = ['src/_Common.ps1', 'src/pwsh51/_Common.ps1']
for f in common_files:
    with open(f, 'r') as file:
        content = file.read()
    
    # Add RepoRoot and Resolve-OutputPaths right after the Constants section
    if 'Resolve-OutputPaths' not in content:
        injection = """#endregion

#region Path Resolution
$script:RepoRoot = Split-Path $ScriptRoot -Parent

function Resolve-OutputPaths {
    param(
        [string]$OutputCsv,
        [string]$LogPath,
        [string]$DefaultCsvName,
        [string]$DefaultLogName
    )
    
    if (-not $OutputCsv) { $OutputCsv = [System.IO.Path]::Combine($script:RepoRoot, 'output', $DefaultCsvName) }
    if (-not $OutputCsv.ToLower().EndsWith('.csv')) { $OutputCsv += '.csv' }
    if (-not $LogPath) { $LogPath = [System.IO.Path]::Combine($script:RepoRoot, 'logs', $DefaultLogName) }

    $resolvedCsv = [System.IO.Path]::GetFullPath($OutputCsv)
    $resolvedLog = [System.IO.Path]::GetFullPath($LogPath)

    New-DirectoryIfMissing ([System.IO.Path]::GetDirectoryName($resolvedCsv))
    New-DirectoryIfMissing ([System.IO.Path]::GetDirectoryName($resolvedLog))

    return @{
        OutputCsv = $resolvedCsv
        LogPath = $resolvedLog
    }
}
#endregion

#region Pure Functions"""
        content = content.replace('#endregion\n\n#region Pure Functions', injection)
        with open(f, 'w') as file:
            file.write(content)

def fix_fix_inheritance(f):
    with open(f, 'r') as file:
        content = file.read()
    
    # Remove repoRoot calc and the old resolution logic
    content = re.sub(r'\s*\$repoRoot = Split-Path \$ScriptRoot -Parent\n', '\n', content)
    
    old_resolution = r"""    \$repoRoot = Split-Path \$ScriptRoot -Parent
    if \(-not \$OutputPath\) \{ \$OutputPath = \[System\.IO\.Path\]::Combine\(\$repoRoot, 'output', 'FailedInheritance\.csv'\) \}
    if \(-not \$OutputPath\.ToLower\(\)\.EndsWith\('\.csv'\)\) \{ \$OutputPath = \$OutputPath \+ '\.csv' \}
    if \(-not \$LogPath\) \{ \$LogPath = \[System\.IO\.Path\]::Combine\(\$repoRoot, 'logs', 'FailedInheritance\.log'\) \}

    \$OutputCsv = \[System\.IO\.Path\]::GetFullPath\(\$OutputPath\)
    \$LogPath = \[System\.IO\.Path\]::GetFullPath\(\$LogPath\)

    New-DirectoryIfMissing \(\[System\.IO\.Path\]::GetDirectoryName\(\$OutputCsv\)\)
    New-DirectoryIfMissing \(\[System\.IO\.Path\]::GetDirectoryName\(\$LogPath\)\)"""
    
    new_resolution = """    $paths = Resolve-OutputPaths -OutputCsv $OutputPath -LogPath $LogPath -DefaultCsvName 'FailedInheritance.csv' -DefaultLogName 'FailedInheritance.log'
    $OutputCsv = $paths.OutputCsv
    $LogPath = $paths.LogPath"""
    
    content = re.sub(old_resolution, new_resolution, content, flags=re.MULTILINE)
    
    # If the first sub didn't catch repoRoot because it didn't exist in the function, check for it.
    
    with open(f, 'w') as file:
        file.write(content)

fix_fix_inheritance('src/Fix-Inheritance.ps1')
fix_fix_inheritance('src/pwsh51/Fix-Inheritance.ps1')


def fix_take_ownership(f):
    with open(f, 'r') as file:
        content = file.read()
        
    content = re.sub(r'\s*\$repoRoot = Split-Path \$ScriptRoot -Parent\n', '\n', content)
    
    old_resolution = r"""    if \(-not \$OutputCsv\) \{
        \$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        \$outputDir = \[System\.IO\.Path\]::GetDirectoryName\(\[System\.IO\.Path\]::GetFullPath\(\$CsvPath\)\)
        \$OutputCsv = Join-Path \$outputDir "Results_\$timestamp\.csv"
    \}
    if \(-not \$LogPath\) \{
        \$LogPath = \[System\.IO\.Path\]::Combine\(\$repoRoot, 'logs', 'TakeOwnership\.log'\)
    \}

    \$OutputCsv = \[System\.IO\.Path\]::GetFullPath\(\$OutputCsv\)
    \$LogPath = \[System\.IO\.Path\]::GetFullPath\(\$LogPath\)

    New-DirectoryIfMissing \(\[System\.IO\.Path\]::GetDirectoryName\(\$OutputCsv\)\)
    New-DirectoryIfMissing \(\[System\.IO\.Path\]::GetDirectoryName\(\$LogPath\)\)"""
    
    new_resolution = """    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $paths = Resolve-OutputPaths -OutputCsv $OutputCsv -LogPath $LogPath -DefaultCsvName "Results_$timestamp.csv" -DefaultLogName 'TakeOwnership.log'
    $OutputCsv = $paths.OutputCsv
    $LogPath = $paths.LogPath"""
    
    # Let's use a simpler regex that just replaces the whole block
    old_resolution2 = r"""    if \(-not \$OutputCsv\) \{
        \$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        \$outputDir = \[System\.IO\.Path\]::GetDirectoryName\(\[System\.IO\.Path\]::GetFullPath\(\$CsvPath\)\)
        \$OutputCsv = Join-Path \$outputDir "Results_\$timestamp\.csv"
    \}
    if \(-not \$LogPath\) \{ \$LogPath = \[System\.IO\.Path\]::Combine\(\$repoRoot, 'logs', 'TakeOwnership\.log'\) \}

    \$OutputCsv = \[System\.IO\.Path\]::GetFullPath\(\$OutputCsv\)
    \$LogPath = \[System\.IO\.Path\]::GetFullPath\(\$LogPath\)

    New-DirectoryIfMissing \(\[System\.IO\.Path\]::GetDirectoryName\(\$OutputCsv\)\)
    New-DirectoryIfMissing \(\[System\.IO\.Path\]::GetDirectoryName\(\$LogPath\)\)"""
    
    # Also handle the one with the one-liner logpath
    content = re.sub(old_resolution2, new_resolution, content, flags=re.MULTILINE)
    
    # Let's use string find and replace if regex is too brittle
    
    with open(f, 'w') as file:
        file.write(content)

fix_take_ownership('src/Take-Ownership.ps1')
fix_take_ownership('src/pwsh51/Take-Ownership.ps1')

