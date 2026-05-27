---
external help file: -help.xml
Module Name:
online version:
schema: 2.0.0
---

# Fix-Inheritance.ps1

## SYNOPSIS
Fixes inheritance on all files and subfolders, logging failures to CSV.

## SYNTAX

```
Fix-Inheritance.ps1 [-TargetPath] <String> [[-OutputPath] <String>] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Runs icacls inheritance:e /T on a target path, catches failures, and outputs
a CSV with full paths of files that failed inheritance takeover.
The CSV can be fed to Take-Ownership scripts for recovery.
Handles long paths (\>256 chars) and special characters.

## EXAMPLES

### EXAMPLE 1
```
.\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin"
```

### EXAMPLE 2
```
.\Fix-Inheritance.ps1 -TargetPath "R:\r_vs13_d2\ftcregfin" -OutputPath "C:\reports\failures"
```

## PARAMETERS

### -TargetPath
The root folder path to fix inheritance on (e.g., R:\r_vs13_d2\ftcregfin\\)

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -OutputPath
Path for the output CSV file.
Default: .\FailedInheritance.csv

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: .\FailedInheritance
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProgressAction
{{ Fill ProgressAction Description }}

```yaml
Type: ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES

## RELATED LINKS
