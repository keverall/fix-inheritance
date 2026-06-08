import re

def replace_in_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
        
    old_resolution = r"""    if \(-not \$OutputPath\) \{ \$OutputPath = \[System\.IO\.Path\]::Combine\(\$repoRoot, 'output', 'FailedInheritance\.csv'\) \}
    if \(-not \$OutputPath\.ToLower\(\)\.EndsWith\('\.csv'\)\) \{ \$OutputPath = \$OutputPath \+ '\.csv' \}
    if \(-not \$LogPath\) \{ \$LogPath = \[System\.IO\.Path\]::Combine\(\$repoRoot, 'logs', 'FailedInheritance\.log'\) \}

    \$OutputCsv = \[System\.IO\.Path\]::GetFullPath\(\$OutputPath\)
    \$LogPath = \[System\.IO\.Path\]::GetFullPath\(\$LogPath\)

    New-DirectoryIfMissing \(\[System\.IO\.Path\]::GetDirectoryName\(\$OutputCsv\)\)
    New-DirectoryIfMissing \(\[System\.IO\.Path\]::GetDirectoryName\(\$LogPath\)\)"""

    new_resolution = """    $paths = Resolve-OutputPaths -OutputCsv $OutputPath -LogPath $LogPath -DefaultCsvName 'FailedInheritance.csv' -DefaultLogName 'FailedInheritance.log'
    $OutputCsv = $paths.OutputCsv
    $LogPath = $paths.LogPath"""
    
    new_content = re.sub(old_resolution, new_resolution, content, flags=re.MULTILINE)
    
    with open(filepath, 'w') as f:
        f.write(new_content)
    
    if content != new_content:
        print(f"Updated {filepath}")
    else:
        print(f"Failed to update {filepath}")

replace_in_file('src/Fix-Inheritance.ps1')
replace_in_file('src/pwsh51/Fix-Inheritance.ps1')

