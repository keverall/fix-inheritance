---
external help file: -help.xml
Module Name:
online version:
schema: 2.0.0
---

# Take-Ownership.ps1

## SYNOPSIS
Takes ownership of files listed in CSV and re-applies inheritance.

## SYNTAX

```
Take-Ownership.ps1 [-CsvPath] <String> [-OutputCsv <String>] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Reads the FailedInheritance.csv output from Fix-Inheritance.ps1,
takes ownership of each file using takeown, then re-runs icacls
to enable inheritance.
Requires Administrator privileges.

## EXAMPLES

### EXAMPLE 1
```
.\Take-Ownership.ps1 -CsvPath "C:\temp\FailedInheritance.csv"
```

## PARAMETERS

### -CsvPath
Path to the FailedInheritance.csv file

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

### -OutputCsv
Path for results CSV.
Defaults to Results_YYYYMMDD_HHMMSS.csv next to input.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
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
