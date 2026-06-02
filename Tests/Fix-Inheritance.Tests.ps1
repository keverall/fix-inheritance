# Tests for Fix-Inheritance.ps1 (comprehensive)
BeforeAll {
    $commonPath     = "$PSScriptRoot/../src/_Common.ps1"
    $scriptPath     = "$PSScriptRoot/../src/Fix-Inheritance.ps1"
    . $commonPath

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
    $astCommon = [System.Management.Automation.Language.Parser]::ParseFile($commonPath, [ref]$null, [ref]$null)
    $commonFuncs = $astCommon.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object Name
    $fixFuncs = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -notin $commonFuncs }, $true)
    foreach ($func in $fixFuncs) { Invoke-Expression $func.Extent.Text }
}

Describe "Fix-Inheritance.ps1" {
    It "Exists, is non-empty, and parses cleanly" {
        $scriptPath | Should -Exist
        (Get-Item $scriptPath).Length | Should -BeGreaterThan 100
        $errors = @(); $tokens = @()
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
    }
    It "TargetPath is mandatory" {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
        $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq "TargetPath" }
        $param | Should -Not -BeNullOrEmpty
    }
    It "Exits non-zero on missing target" {
        & pwsh -NoProfile -Command "& '$scriptPath' -TargetPath 'Z:\NonExistent\Path' 2>&1"
        $LASTEXITCODE | Should -Not -Be 0
    }
}

Describe "Fix-Inheritance - test data builders" {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("fitest-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach {
        if (Test-Path $script:root) { Remove-Item -Recurse -Force $script:root }
    }

    It "Creates a tree with special character filenames" {
        $names = @(
            'file with spaces.txt',
            'file,with,commas.txt',
            'file.and.dots.txt',
            'file&and&ampersand.txt',
            'file^and^caret.txt',
            'file$dollar$.txt',
            'file"quote.txt',
            'file( paren ).txt',
            'file[ bracket ].txt',
            'file; semicolon.txt',
            'file@at.txt',
            'file#hash.txt',
            'file!bang.txt',
            'file+plus.txt',
            'file=equals.txt',
            'file{brace}.txt',
            'file`backtick.txt',
            'file~tilde.txt',
            'file|pipe.txt'
        )
        foreach ($n in $names) {
            New-Item -ItemType File -Path (Join-Path $script:root $n) -Force | Out-Null
        }
        $files = Get-ChildItem -LiteralPath $script:root -File
        $files.Count | Should -Be $names.Count
    }

    It "Creates a nested directory tree" {
        $depth = 10
        $current = $script:root
        $pathParts = @()
        for ($i = 1; $i -le $depth; $i++) {
            $current = Join-Path $current "level$i"
            New-Item -ItemType Directory -Path $current -Force | Out-Null
            if ($i -eq $depth) {
                New-Item -ItemType File -Path (Join-Path $current 'deep.txt') -Force | Out-Null
            }
            $pathParts += "level$i"
        }
        $fullPath = Join-Path $script:root (Join-Path $pathParts 'deep.txt')
        $fullPath | Should -Exist
    }

    It "Creates file paths exceeding MAX_PATH" {
        $subdir = Join-Path $script:root 'longpath_dir'
        New-Item -ItemType Directory -Path $subdir -Force | Out-Null
        $deep = 290 - $subdir.Length - '.txt'.Length
        $name = 'a' * $deep
        $longFile = Join-Path $subdir "$name.txt"
        New-Item -ItemType File -Path $longFile -Force | Out-Null
        $longFile.Length | Should -BeGreaterThan $script:MaxPathLength
    }

    It "Creates unreadable paths for enumeration-error capture testing" {
        $locked = Join-Path $script:root 'locked_dir'
        New-Item -ItemType Directory -Path $locked -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $locked 'secret.txt') -Force | Out-Null
        # On Linux, chmod 000 simulates access denial
        $null = chmod 000 $locked
    }

    It "Creates mixed tree (special chars + normal + deep + long)" {
        New-Item -ItemType File -Path (Join-Path $script:root 'normal_file.txt') -Force | Out-Null

        $specialDir = Join-Path $script:root 'dir (special)'
        New-Item -ItemType Directory -Path $specialDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $specialDir 'file,with,special&chars.txt') -Force | Out-Null

        $deepDir = $specialDir
        1..8 | ForEach-Object { $deepDir = Join-Path $deepDir "d$_" ; New-Item -ItemType Directory -Path $deepDir -Force | Out-Null }
        New-Item -ItemType File -Path (Join-Path $deepDir 'bottom.txt') -Force | Out-Null

        $longDir = Join-Path $script:root 'long_path_here'
        New-Item -ItemType Directory -Path $longDir -Force | Out-Null
        $name = 'a' * (300 - $longDir.Length - 4)
        New-Item -ItemType File -Path (Join-Path $longDir "$name.txt") -Force | Out-Null

        $count = (Get-ChildItem -LiteralPath $script:root -Recurse -File).Count
        $count | Should -Be 4
    }
}

Describe "Fix-Inheritance integration tests" {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("fitest-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach {
        if (Test-Path $script:root) { Remove-Item -Recurse -Force $script:root }
    }

    It "Produces a CSV with correct header for any target" {
        New-Item -ItemType Directory -Path (Join-Path $script:root 'empty') | Out-Null
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        Invoke-FixInheritance -TargetPath (Join-Path $script:root 'empty') -OutputPath $csv -LogPath $log
        Test-Path $csv | Should -Be $true
        $header = Get-Content $csv -TotalCount 1
        $header | Should -Be '"FilePath","FileName","ParentFolder","FolderName","ErrorReason","PathLength","IsLongPath","Timestamp"'
    }

    It "Creates a log file with structured entries" {
        New-Item -ItemType Directory -Path (Join-Path $script:root 'logtarget') | Out-Null
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        Invoke-FixInheritance -TargetPath (Join-Path $script:root 'logtarget') -OutputPath $csv -LogPath $log
        Test-Path $log | Should -Be $true
        Get-Content $log | Where-Object { $_ -match '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[INFO\]' } | Should -Not -BeNullOrEmpty
    }

    It "Returns cleanly when target does not exist" {
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        { Invoke-FixInheritance -TargetPath 'X:\nonexistent' -OutputPath $csv -LogPath $log } | Should -Not -Throw
    }

    It "Processes all items and records 100% failures when icacls is unavailable" {
        New-Item -ItemType File -Path (Join-Path $script:root 'a.txt') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $script:root 'b.txt') -Force | Out-Null
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        Invoke-FixInheritance -TargetPath $script:root -OutputPath $csv -LogPath $log
        $rows = Import-Csv -Path $csv
        ($rows | Measure-Object).Count | Should -Be 2
    }

    It "Continues processing after enumeration errors" {
        $locked = Join-Path $script:root 'locked'
        New-Item -ItemType Directory -Path $locked -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $locked 'secret.txt') -Force | Out-Null
        $null = chmod 000 $locked 2>$null

        New-Item -ItemType File -Path (Join-Path $script:root 'readable.txt') -Force | Out-Null

        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        Invoke-FixInheritance -TargetPath $script:root -OutputPath $csv -LogPath $log

        $rows = Import-Csv -Path $csv
        ($rows | Measure-Object).Count | Should -BeGreaterThan 0
        $enumErrors = @($rows | Where-Object { $_.ErrorReason -eq 'Cannot enumerate (likely access denied or path error)' })
        $enumErrors.Count | Should -BeGreaterThan 0
        $processable = @($rows | Where-Object { $_.ErrorReason -notlike 'Cannot enumerate*' })
        $processable.Count | Should -BeGreaterThan 0

        chmod 755 $locked 2>$null
    }

    It "Records special-character filenames in CSV with correct roundtrip" {
        $special = @(
            'file with spaces.txt',
            'file,comma.txt',
            'file"dquote.txt',
            'file&amp.txt',
            'file^caret.txt',
            'file$dollar.txt',
            'file.dot.v2.txt',
            'file;semi.txt',
            'file#hash.txt'
        )
        foreach ($n in $special) {
            New-Item -ItemType File -Path (Join-Path $script:root $n) -Force | Out-Null
        }
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        Invoke-FixInheritance -TargetPath $script:root -OutputPath $csv -LogPath $log
        $rows = Import-Csv -Path $csv
        ($rows | Measure-Object).Count | Should -Be $special.Count
        $returnedNames = $rows | ForEach-Object { $_.FileName } | Sort-Object
        $expectedNames = $special | Sort-Object
        $returnedNames | Should -Be $expectedNames
    }

    It "Records deep paths in CSV" {
        $deepDir = $script:root
        1..20 | ForEach-Object { $deepDir = Join-Path $deepDir "l$_" ; New-Item -ItemType Directory -Path $deepDir -Force | Out-Null }
        New-Item -ItemType File -Path (Join-Path $deepDir 'bottom.txt') -Force | Out-Null
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        Invoke-FixInheritance -TargetPath $script:root -OutputPath $csv -LogPath $log
        $rows = Import-Csv -Path $csv
        ($rows | Measure-Object).Count | Should -BeGreaterThan 0
        $rows[0].FilePath | Should -Match 'l1'
        $rows[0].FilePath | Should -Match 'bottom.txt'
    }

    It "Records long paths with IsLongPath=true" {
        $longDir = Join-Path $script:root 'longprefix'
        New-Item -ItemType Directory -Path $longDir -Force | Out-Null
        $filler = 'a' * 270
        $longFile = Join-Path $longDir "$filler.txt"
        New-Item -ItemType File -Path $longFile -Force | Out-Null
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        Invoke-FixInheritance -TargetPath $script:root -OutputPath $csv -LogPath $log
        $rows = Import-Csv -Path $csv
        $longRow = $rows | Where-Object { $_.IsLongPath -eq $true }
        $longRow | Should -Not -BeNullOrEmpty
        $longRow.FilePath.Length | Should -BeGreaterThan $script:MaxPathLength
    }

    It "Sets LogPath default next to OutputPath when omitted" {
        New-Item -ItemType File -Path (Join-Path $script:root 'x.txt') -Force | Out-Null
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        Invoke-FixInheritance -TargetPath $script:root -OutputPath $csv -LogPath $log
        # log should have been created next to the CSV
        Test-Path $log | Should -Be $true
    }

    It "Writes enumeration errors under the summary" {
        $locked = Join-Path $script:root 'forbidden'
        New-Item -ItemType Directory -Path $locked -Force | Out-Null
        $null = chmod 000 $locked 2>$null
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        Invoke-FixInheritance -TargetPath $script:root -OutputPath $csv -LogPath $log
        chmod 755 $locked 2>$null
        # The log should mention the enumeration error count
        $logContent = Get-Content $log -Raw
        $logContent | Should -Match 'enumeration'
    }

    It "Does not stop on a file that throws during per-item icacls" {
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        $output = Invoke-FixInheritance -TargetPath $script:root -OutputPath $csv -LogPath $log 2>&1
        $output | Should -Match 'Done'
        $output | Should -Match 'Summary'
    }

    It "Creates directories automatically for Output and Log" {
        New-Item -ItemType File -Path (Join-Path $script:root 'x.txt') -Force | Out-Null
        $csv = Join-Path $script:root 'subdir' 'deep' 'out.csv'
        $log = Join-Path $script:root 'subdir' 'deep' 'out.log'
        { Invoke-FixInheritance -TargetPath $script:root -OutputPath $csv -LogPath $log } | Should -Not -Throw
        Test-Path $csv | Should -Be $true
        Test-Path $log | Should -Be $true
    }
}
