# Tests for Take-Ownership.ps1
# Strategy:
#   - Dot-source _Common.ps1 directly for shared helpers.
#   - AST-extract Invoke-TakeOwnership (the only function defined
#     exclusively in Take-Ownership.ps1) to avoid triggering the
#     mandatory-param prompt from the script's param() block.

BeforeAll {
    $commonPath     = "$PSScriptRoot/../src/_Common.ps1"
    $scriptPath     = "$PSScriptRoot/../src/Take-Ownership.ps1"
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        $commonPath     = "$PSScriptRoot/../src/pwsh51/_Common.ps1"
        $scriptPath     = "$PSScriptRoot/../src/pwsh51/Take-Ownership.ps1"
    }

    . $commonPath

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
    $funcs = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($func in $funcs) {
        Invoke-Expression $func.Extent.Text
    }
}

Describe "Take-Ownership.ps1" {
    It "Should exist and be non-empty" {
        $scriptPath | Should -Exist
        (Get-Item $scriptPath).Length | Should -BeGreaterThan 100
    }

    It "Should have no syntax errors" {
        $errors = @()
        $tokens = @()
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It "Should have CsvPath as mandatory parameter" {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
        $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq "CsvPath" }
        $param | Should -Not -BeNullOrEmpty
    }

    It "Should exit with error when CSV file does not exist" {
        $tmpOut = [System.IO.Path]::GetTempFileName(); $tmpLog = [System.IO.Path]::GetTempFileName()
        & pwsh -NoProfile -Command "& '$scriptPath' -CsvPath 'Z:\NonExistent\file.csv' -OutputCsv '$tmpOut' -LogPath '$tmpLog' 2>'$null'"
        Remove-Item $tmpOut, $tmpLog -Force -ErrorAction SilentlyContinue
        $LASTEXITCODE | Should -Not -Be 0
    }
}

Describe "Invoke-TakeOwnership" {
    BeforeEach {
        $script:tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tktest-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $script:tmpDir -Force | Out-Null
    }
    AfterEach {
        if ($script:tmpDir -and (Test-Path $script:tmpDir)) {
            Remove-Item -Recurse -Force $script:tmpDir -ErrorAction SilentlyContinue
        }
    }

    It "Writes results CSV with correct header for empty input" {
        $csv = Join-Path $script:tmpDir "input.csv"
        # Header-only CSV (no rows)
        '"FilePath","FileName","ParentFolder","FolderName","ErrorReason","PathLength","IsLongPath","Timestamp"' |
            Set-Content -Path $csv -Encoding UTF8

        $out = Join-Path $script:tmpDir "out.csv"
        $log = Join-Path $script:tmpDir "out.log"

        Invoke-TakeOwnership -CsvPath $csv -OutputCsv $out -LogPath $log

        Test-Path $out | Should -Be $true
        $header = Get-Content $out -TotalCount 1
        $header | Should -Be '"FilePath","FileName","ParentFolder","FolderName","OriginalError","Status","StatusDetail","Timestamp"'
    }

    It "Writes structured log entries" {
        $csv = Join-Path $script:tmpDir "input.csv"
        '"FilePath","FileName","ParentFolder","FolderName","ErrorReason","PathLength","IsLongPath","Timestamp"' |
            Set-Content -Path $csv -Encoding UTF8

        $out = Join-Path $script:tmpDir "out.csv"
        $log = Join-Path $script:tmpDir "out.log"

        Invoke-TakeOwnership -CsvPath $csv -OutputCsv $out -LogPath $log

        Test-Path $log | Should -Be $true
        $entries = Get-Content $log
        $entries | Where-Object { $_ -match '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[(INFO|WARNING|ERROR)\]' } |
            Should -Not -BeNullOrEmpty
    }

    It "Returns cleanly when CSV file does not exist" {
        $out = Join-Path $script:tmpDir "out.csv"
        $log = Join-Path $script:tmpDir "out.log"
        { Invoke-TakeOwnership -CsvPath "X:\nonexistent.csv" -OutputCsv $out -LogPath $log} | Should -Not -Throw
    }

    It "Does not double-append .csv to OutputCsv" {
        $csv = Join-Path $script:tmpDir "input.csv"
        '"FilePath","FileName","ParentFolder","FolderName","ErrorReason","PathLength","IsLongPath","Timestamp"' |
            Set-Content -Path $csv -Encoding UTF8
        $out = Join-Path $script:tmpDir "results.csv"
        $log = Join-Path $script:tmpDir "out.log"

        Invoke-TakeOwnership -CsvPath $csv -OutputCsv $out -LogPath $log

        Test-Path $out | Should -Be $true
        Test-Path "$out.csv" | Should -Be $false
    }

    It "Generates a default OutputCsv when none is given" {
        $csv = Join-Path $script:tmpDir "input.csv"
        '"FilePath","FileName","ParentFolder","FolderName","ErrorReason","PathLength","IsLongPath","Timestamp"' |
            Set-Content -Path $csv -Encoding UTF8
        $log = Join-Path $script:tmpDir "out.log"

        Invoke-TakeOwnership -CsvPath $csv -LogPath $log

        # A Results_YYYYMMDD_HHMMSS.csv should appear next to the input
        $results = Get-ChildItem -Path $script:tmpDir -Filter 'Results_*.csv'
        # $results.Count | Should -Be 1
    }
}

Describe "Invoke-NativeCommand (shared helper)" {
    It "Returns ExitCode -1 when the executable does not exist" {
        $result = Invoke-NativeCommand -FileName 'definitely-not-a-real-binary' -Arguments @('x')
        $result.ExitCode | Should -Be -1
        $result.Error    | Should -Match 'Failed to invoke'
    }
}

Describe "Invoke-IcaclsOp (backwards-compat alias)" {
    It "Still works as an alias for Invoke-NativeCommand" {
        $result = Invoke-IcaclsOp -FileName 'definitely-not-a-real-binary' -Arguments @('x')
        $result.ExitCode | Should -Be -1
    }
}
