import re

def replace_in_file(filepath, pattern, replacement):
    with open(filepath, 'r') as f:
        content = f.read()
    
    new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)
    
    with open(filepath, 'w') as f:
        f.write(new_content)
    
    if content != new_content:
        print(f"Updated {filepath}")
    else:
        print(f"Failed to update {filepath}")

fix_pattern = r"\s*\$repoRoot = Split-Path \$ScriptRoot -Parent\n\s*if \(-not \$OutputPath\) \{ \$OutputPath = \[System\.IO\.Path\]::Combine\(\$repoRoot, 'output', 'FailedInheritance\.csv'\) \}\n\s*if \(-not \$OutputPath\.ToLower\(\)\.EndsWith\('\.csv'\)\) \{ \$OutputPath = \$OutputPath \+ '\.csv' \}\n\s*if \(-not \$LogPath\) \{ \$LogPath = \[System\.IO\.Path\]::Combine\(\$repoRoot, 'logs', 'FailedInheritance\.log'\) \}\n\n\s*\$OutputCsv = \[System\.IO\.Path\]::GetFullPath\(\$OutputPath\)\n\s*\$LogPath = \[System\.IO\.Path\]::GetFullPath\(\$LogPath\)\n\n\s*New-DirectoryIfMissing \(\[System\.IO\.Path\]::GetDirectoryName\(\$OutputCsv\)\)\n\s*New-DirectoryIfMissing \(\[System\.IO\.Path\]::GetDirectoryName\(\$LogPath\)\)"

fix_replacement = """
    $paths = Resolve-OutputPaths -OutputCsv $OutputPath -LogPath $LogPath -DefaultCsvName 'FailedInheritance.csv' -DefaultLogName 'FailedInheritance.log'
    $OutputCsv = $paths.OutputCsv
    $LogPath = $paths.LogPath
"""

replace_in_file('src/Fix-Inheritance.ps1', fix_pattern, fix_replacement)
replace_in_file('src/pwsh51/Fix-Inheritance.ps1', fix_pattern, fix_replacement)

take_pattern = r"\s*if \(-not \$OutputCsv\) \{\n\s*\$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'\n\s*\$outputDir = \[System\.IO\.Path\]::GetDirectoryName\(\[System\.IO\.Path\]::GetFullPath\(\$CsvPath\)\)\n\s*\$OutputCsv = Join-Path \$outputDir \"Results_\$timestamp\.csv\"\n\s*\}\n\s*if \(-not \$LogPath\) \{\n\s*\$LogPath = \[System\.IO\.Path\]::Combine\(\$repoRoot, 'logs', 'TakeOwnership\.log'\)\n\s*\}\n\n\s*\$OutputCsv = \[System\.IO\.Path\]::GetFullPath\(\$OutputCsv\)\n\s*\$LogPath = \[System\.IO\.Path\]::GetFullPath\(\$LogPath\)\n\n\s*New-DirectoryIfMissing \(\[System\.IO\.Path\]::GetDirectoryName\(\$OutputCsv\)\)\n\s*New-DirectoryIfMissing \(\[System\.IO\.Path\]::GetDirectoryName\(\$LogPath\)\)"

take_replacement = """
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $paths = Resolve-OutputPaths -OutputCsv $OutputCsv -LogPath $LogPath -DefaultCsvName "Results_$timestamp.csv" -DefaultLogName 'TakeOwnership.log'
    $OutputCsv = $paths.OutputCsv
    $LogPath = $paths.LogPath
"""

replace_in_file('src/Take-Ownership.ps1', take_pattern, take_replacement)
replace_in_file('src/pwsh51/Take-Ownership.ps1', take_pattern, take_replacement)

