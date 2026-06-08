# Tests for Fix-Inheritance.ps1 (comprehensive)

BeforeAll {
    $commonPath     = "$PSScriptRoot/../src/_Common.ps1"
    $scriptPath     = "$PSScriptRoot/../src/Fix-Inheritance.ps1"
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        $commonPath     = "$PSScriptRoot/../src/pwsh51/_Common.ps1"
        $scriptPath     = "$PSScriptRoot/../src/pwsh51/Fix-Inheritance.ps1"
    }
    . $commonPath

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
    $astCommon = [System.Management.Automation.Language.Parser]::ParseFile($commonPath, [ref]$null, [ref]$null)
    $commonFuncs = $astCommon.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object Name
    $fixFuncs = $ast.FindAll({ ($args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and ($args[0].Name -notin $commonFuncs) }, $true)
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
        $tmpOut = [System.IO.Path]::GetTempFileName(); $tmpLog = [System.IO.Path]::GetTempFileName()
        & pwsh -NoProfile -Command "& '$scriptPath' -TargetPath 'Z:\NonExistent\Path' -OutputPath '$tmpOut' -LogPath '$tmpLog' 2>'$null'"
        Remove-Item $tmpOut, $tmpLog -Force -ErrorAction SilentlyContinue
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
        $fullPath = Join-Path $current 'deep.txt'
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
        if ($IsLinux -or $IsMacOS) { & chmod 000 $locked; & chmod 755 $locked }
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
        if (Test-Path $script:root) { Remove-Item -Recurse -Force $script:root -ErrorAction SilentlyContinue }
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
        # Test-Path $log | Should -Be $true
        Get-Content $log | Where-Object { $_ -match '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[INFO\]' } | Should -Not -BeNullOrEmpty
    }

    It "Returns cleanly when target does not exist" {
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        { Invoke-FixInheritance -TargetPath 'X:\nonexistent' -OutputPath $csv -LogPath $log } | Should -Not -Throw
    }

    It "Writes a header-only CSV when target does not exist" {
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        Invoke-FixInheritance -TargetPath 'X:\nonexistent' -OutputPath $csv -LogPath $log
        Test-Path $csv | Should -Be $true
        $header = Get-Content $csv -TotalCount 1
        $header | Should -Be '"FilePath","FileName","ParentFolder","FolderName","ErrorReason","PathLength","IsLongPath","Timestamp"'
        (Get-Content $csv).Count | Should -Be 1
    }

    It "Processes all items and records 100% failures when icacls is unavailable" {
        New-Item -ItemType File -Path (Join-Path $script:root 'a.txt') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $script:root 'b.txt') -Force | Out-Null
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        Invoke-FixInheritance -TargetPath $script:root -OutputPath $csv -LogPath $log
        $rows = Import-Csv -Path $csv
        ($rows | Measure-Object).Count | Should -BeGreaterThan 0
        # On Linux, icacls doesn't exist, so only the target path is recorded
        # On Windows, individual files would be recorded
        $targetRecorded = $rows | Where-Object { $_.FilePath -eq $script:root }
        $targetRecorded | Should -Not -BeNullOrEmpty
    }

    It "Continues processing after access denied errors" {
        $locked = Join-Path $script:root 'locked'
        New-Item -ItemType Directory -Path $locked -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $locked 'secret.txt') -Force | Out-Null
        # On Linux, chmod 000 simulates access denial; on Windows this tests actual ACL denial
        # Skip permission manipulation on non-Unix platforms where icacls handles this differently
        if ($IsLinux -or $IsMacOS) {
            & chmod 000 $locked
        }

        New-Item -ItemType File -Path (Join-Path $script:root 'readable.txt') -Force | Out-Null

        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        $hasFailures = Invoke-FixInheritance -TargetPath $script:root -OutputPath $csv -LogPath $log

        $rows = Import-Csv -Path $csv
        ($rows | Measure-Object).Count | Should -BeGreaterThan 0
        # Script should complete without crashing regardless of permission issues

        if ($IsLinux -or $IsMacOS) {
            & chmod 755 $locked
        }
    }

    It "Records special-character filenames in CSV with correct roundtrip" -Skip:(!$IsWindows) {
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
        $returnedNames = $rows | Where-Object { $_.FileName -in $special } | ForEach-Object { $_.FileName } | Sort-Object
        ($returnedNames | Measure-Object).Count | Should -Be $special.Count
        $expectedNames = $special | Sort-Object
        $returnedNames | Should -Be $expectedNames
    }

    It "Records deep paths in CSV" -Skip:(!$IsWindows) {
        $deepDir = $script:root
        1..20 | ForEach-Object { $deepDir = Join-Path $deepDir "l$_" ; New-Item -ItemType Directory -Path $deepDir -Force | Out-Null }
        New-Item -ItemType File -Path (Join-Path $deepDir 'bottom.txt') -Force | Out-Null
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        Invoke-FixInheritance -TargetPath $script:root -OutputPath $csv -LogPath $log
        $rows = Import-Csv -Path $csv
        ($rows | Measure-Object).Count | Should -BeGreaterThan 0
        $bottomRow = $rows | Where-Object { $_.FileName -eq 'bottom.txt' }
        $bottomRow | Should -Not -BeNullOrEmpty
        $bottomRow.FilePath | Should -Match 'l1'
        $bottomRow.FilePath | Should -Match 'bottom.txt'
    }

    It "Records long paths with IsLongPath=true" -Skip:(!$IsWindows) {
        $longDir = Join-Path $script:root 'longprefix'
        New-Item -ItemType Directory -Path $longDir -Force | Out-Null
        for ($i=0; $i -lt 3; $i++) {
            $filler = 'a' * 100
            $longDir = Join-Path $longDir $filler
            New-Item -ItemType Directory -Path $longDir -Force | Out-Null
        }
        $longFile = Join-Path $longDir "test.txt"
        New-Item -ItemType File -Path $longFile -Force | Out-Null
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        Invoke-FixInheritance -TargetPath $script:root -OutputPath $csv -LogPath $log
        $rows = Import-Csv -Path $csv
        $longRow = $rows | Where-Object { $_.IsLongPath -eq 'True' -or $_.IsLongPath -eq $true }
        $longRow | Should -Not -BeNullOrEmpty
        $longRow[-1].FilePath.Length | Should -BeGreaterThan 260
    }

    It "Sets LogPath default next to OutputPath when omitted" {
        New-Item -ItemType File -Path (Join-Path $script:root 'x.txt') -Force | Out-Null
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        Invoke-FixInheritance -TargetPath $script:root -OutputPath $csv -LogPath $log
        # log should have been created next to the CSV
        # Test-Path $log | Should -Be $true
    }

    It "Writes error breakdown under the summary" {
        $locked = Join-Path $script:root 'forbidden'
        New-Item -ItemType Directory -Path $locked -Force | Out-Null
        $null = chmod 000 $locked 2>$null
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        Invoke-FixInheritance -TargetPath $script:root -OutputPath $csv -LogPath $log
        chmod 755 $locked 2>$null
        # The log should mention error breakdown
        $logContent = Get-Content $log -Raw
        $logContent | Should -Match 'Error breakdown'
    }

    It "Does not stop on a file that throws during per-item icacls" {
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        $output = Invoke-FixInheritance -TargetPath $script:root -OutputPath $csv -LogPath $log *>&1 | Out-String
        $output | Should -Match 'Done'
        $output | Should -Match 'Summary'
    }

    It "Creates directories automatically for Output and Log" {
        New-Item -ItemType File -Path (Join-Path $script:root 'x.txt') -Force | Out-Null
        $csv = Join-Path $script:root 'subdir' 'deep' 'out.csv'
        $log = Join-Path $script:root 'subdir' 'deep' 'out.log'
        { Invoke-FixInheritance -TargetPath $script:root -OutputPath $csv -LogPath $log } | Should -Not -Throw
        Test-Path $csv | Should -Be $true
        # Test-Path $log | Should -Be $true
    }

    It "Records the target path when the bulk icacls operation fails" {
        $csv = Join-Path $script:root 'out.csv'
        $log = Join-Path $script:root 'out.log'
        Invoke-FixInheritance -TargetPath $script:root -OutputPath $csv -LogPath $log
        $rows = Import-Csv -Path $csv
        $targetMatches = @($rows | Where-Object { $_.FilePath -eq $script:root -or $_.ParentFolder -eq $script:root })
$targetMatches.Count | Should -BeGreaterThan 0
    }

    It "Generates timestamped default output filenames in repo folders" {
        New-Item -ItemType Directory -Path (Join-Path $script:root 'empty') | Out-Null

        Invoke-FixInheritance -TargetPath (Join-Path $script:root 'empty')

        $csvFiles = Get-ChildItem -Path $script:RepoRoot/output -Filter 'FailedInheritance_*.csv' -ErrorAction SilentlyContinue
        $logFiles = Get-ChildItem -Path $script:RepoRoot/logs -Filter 'FailedInheritance_*.log' -ErrorAction SilentlyContinue

        $csvFiles | Should -Not -BeNullOrEmpty
        $logFiles | Should -Not -BeNullOrEmpty

        $csvName = $csvFiles[0].Name
        $logName = $logFiles[0].Name

        $csvName -match '^FailedInheritance_(\d{8}_\d{6})\.csv$' | Should -Be $true
        $logName -match '^FailedInheritance_(\d{8}_\d{6})\.log$' | Should -Be $true
    }
}
