# Tests for _Common.ps1 shared helpers
BeforeAll {
    $commonPath = "$PSScriptRoot/../src/_Common.ps1"
    . $commonPath
}

Describe "_Common.ps1 (shared helpers)" {
    Context "Constants" {
        It "MaxPathLength is 260" {
            $script:MaxPathLength | Should -Be 260
        }
        It "LongPathPrefix is \\?\\" {
            $script:LongPathPrefix | Should -Be '\\?\'
        }
    }

    Describe "Get-LongPath" {
        It "Returns empty or null unchanged" {
            Get-LongPath '' | Should -Be ''
            $r = Get-LongPath $null
            [string]::IsNullOrEmpty($r) | Should -Be $true
        }
        It "Returns short paths unchanged" {
            Get-LongPath 'C:\short\path.txt' | Should -Be 'C:\short\path.txt'
        }
        It "Returns path at exactly MAX_PATH unchanged" {
            $filler = 'a' * ($script:MaxPathLength - 'C:\'.Length - 4)
            $p = "C:\$filler.txt"
            $p.Length | Should -Be $script:MaxPathLength
            Get-LongPath $p | Should -Be $p
        }
        It "Adds \\?\ prefix to long drive-rooted paths" {
            $filler = 'a' * 270
            $expected = '\\?\C:\' + $filler + '.txt'
            Get-LongPath "C:\$filler.txt" | Should -Be $expected
        }
        It "Adds \\?\UNC\ prefix to long UNC paths" {
            $filler = 'a' * 270
            $expected = '\\?\UNC\server\share\' + $filler + '.txt'
            Get-LongPath "\\server\share\$filler.txt" | Should -Be $expected
        }
        It "Does not double-prefix already prefixed paths" {
            $p = '\\?\C:\already\prefixed\long\path.txt'
            Get-LongPath $p | Should -Be $p
        }
        It "Handles regular long paths (no drive root, no UNC)" {
            $filler = 'a' * 270
            $expected = '\\?\C:\' + $filler
            Get-LongPath "C:\$filler" | Should -Be $expected
        }
    }

    Describe "ConvertFrom-HResult" {
        It "Maps known HRESULTs to symbolic names" {
            ConvertFrom-HResult 0   | Should -Be 'SUCCESS'
            ConvertFrom-HResult 2   | Should -Be 'ERROR_FILE_NOT_FOUND'
            ConvertFrom-HResult 3   | Should -Be 'ERROR_PATH_NOT_FOUND'
            ConvertFrom-HResult 5   | Should -Be 'ERROR_ACCESS_DENIED'
            ConvertFrom-HResult 32  | Should -Be 'ERROR_SHARING_VIOLATION'
            ConvertFrom-HResult 87  | Should -Be 'ERROR_INVALID_PARAMETER'
            ConvertFrom-HResult 206 | Should -Be 'ERROR_FILENAME_EXCED_RANGE'
        }
        It "Generates ERROR_CODE_N for unknown codes" {
            ConvertFrom-HResult 9999 | Should -Be 'ERROR_CODE_9999'
            ConvertFrom-HResult -1   | Should -Be 'ERROR_CODE_-1'
        }
    }

    Describe "Get-ErrorReason" {
        Context "Exit-code-first classification (locale-independent)" {
            It "5 = Access Denied" {
                Get-ErrorReason -ExitCode 5 | Should -Be 'Access Denied - requires ownership change'
            }
            It "32 = File in use" {
                Get-ErrorReason -ExitCode 32 | Should -Be 'File in use'
            }
            It "2 = File not found" {
                Get-ErrorReason -ExitCode 2 | Should -Be 'File not found'
            }
            It "3 = Path not found" {
                Get-ErrorReason -ExitCode 3 | Should -Be 'File not found'
            }
            It "206 = Path too long" {
                Get-ErrorReason -ExitCode 206 | Should -Be 'Path too long'
            }
            It "87 = Invalid path or filename" {
                Get-ErrorReason -ExitCode 87 | Should -Be 'Invalid path or filename'
            }
        }

        Context "Message fallback for unknown codes" {
            It "Detects 'Access is denied'" {
                Get-ErrorReason -ExitCode 1 -ErrorOutput "Access is denied." |
                    Should -Be 'Access Denied - requires ownership change'
            }
            It "Detects 'is in use'" {
                Get-ErrorReason -ExitCode 1 -ErrorOutput "The process cannot access the file because it is being used by another process." |
                    Should -Be 'File in use'
            }
            It "Detects 'cannot find the path'" {
                Get-ErrorReason -ExitCode 1 -ErrorOutput "The system cannot find the path specified." |
                    Should -Be 'File not found'
            }
            It "Detects 'too long'" {
                Get-ErrorReason -ExitCode 1 -ErrorOutput "The filename or extension is too long." |
                    Should -Be 'Path too long'
            }
            It "Detects 'invalid'" {
                Get-ErrorReason -ExitCode 1 -ErrorOutput "The filename, directory name, or volume label syntax is incorrect." |
                    Should -Be 'Invalid path or filename'
            }
        }

        It "Prefers exit code over message" {
            Get-ErrorReason -ExitCode 5 -ErrorOutput 'file is in use' |
                Should -Be 'Access Denied - requires ownership change'
        }
        It "Returns Unknown for unmatched errors" {
            Get-ErrorReason -ExitCode 1 -ErrorOutput 'weird' |
                Should -Be 'Unknown error (exit code: 1)'
        }
        It "Handles empty ErrorOutput" {
            Get-ErrorReason -ExitCode 1 | Should -Be 'Unknown error (exit code: 1)'
        }
    }

    Describe "Add-Failure" {
        It "Records all fields correctly" {
            $list = [System.Collections.Generic.List[object]]::new()
            Add-Failure -FullPath 'C:/dir/file.txt' -ErrorReason 'Test reason' -FailedItems $list
            $list.Count | Should -Be 1
            $item = $list[0]
            $item.FilePath     | Should -Be 'C:/dir/file.txt'
            $item.FileName     | Should -Be 'file.txt'
            $item.ParentFolder | Should -Be 'C:/dir'
            $item.FolderName   | Should -Be 'dir'
            $item.ErrorReason  | Should -Be 'Test reason'
            $item.PathLength   | Should -Be 15
            $item.IsLongPath   | Should -Be $false
            $item.Timestamp    | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        }

        It "Marks IsLongPath true for paths > MAX_PATH" {
            $list = [System.Collections.Generic.List[object]]::new()
            $filler = 'a' * 270
            Add-Failure -FullPath "C:\$filler.txt" -ErrorReason 'x' -FailedItems $list
            $list[0].IsLongPath | Should -Be $true
            $list[0].PathLength | Should -BeGreaterThan $script:MaxPathLength
        }

        It "Handles special characters in filenames" {
            $list = [System.Collections.Generic.List[object]]::new()
            Add-Failure -FullPath 'C:/dir/with,comma & quote"here.txt' -ErrorReason 'x' -FailedItems $list
            $list[0].FileName | Should -Be 'with,comma & quote"here.txt'
            $list[0].FilePath | Should -Be 'C:/dir/with,comma & quote"here.txt'
        }

        It "Handles dots, spaces, dollar, caret" {
            $list = [System.Collections.Generic.List[object]]::new()
            Add-Failure -FullPath 'C:/dir/my.file $ver^.v2 & more.txt' -ErrorReason 'x' -FailedItems $list
            $list[0].FileName | Should -Be 'my.file $ver^.v2 & more.txt'
        }

        It "Appends to list without replacing" {
            $list = [System.Collections.Generic.List[object]]::new()
            Add-Failure -FullPath 'C:/a.txt' -ErrorReason 'r1' -FailedItems $list
            Add-Failure -FullPath 'C:/b.txt' -ErrorReason 'r2' -FailedItems $list
            $list.Count | Should -Be 2
            $list[1].FileName | Should -Be 'b.txt'
            $list[1].ErrorReason | Should -Be 'r2'
        }
    }

    Describe "Resolve-OutputCsvPath" {
        It "Appends .csv when no extension" {
            $r = Resolve-OutputCsvPath '.\report'
            $r | Should -BeLike '*.csv'
            $r.EndsWith('report.csv') | Should -Be $true
        }
        It "Does not double-append when .csv already present" {
            $r = Resolve-OutputCsvPath '.\report.csv'
            $r.EndsWith('report.csv.csv') | Should -Be $false
            $r.EndsWith('report.csv')   | Should -Be $true
        }
        It "Resolves relative paths to absolute" {
            $r = Resolve-OutputCsvPath '.\test'
            # Cross-platform: ends in test.csv and is not a relative path entry
            $r.EndsWith('test.csv') | Should -Be $true
            [System.IO.Path]::IsPathRooted($r) | Should -Be $true
        }
        It "Handles paths with spaces and special chars" {
            $r = Resolve-OutputCsvPath '.\my report & data'
            $r | Should -BeLike '*.csv'
        }
    }

    Describe "Get-ErrorRecordPath" {
        It "Extracts path from targetObject when present" {
            # Use the targetObject constructor parameter; it's the canonical
            # way to attach a target to an ErrorRecord without relying on
            # CategoryInfo.Target (which is read-only on newer PowerShell).
            $ex  = New-Object Exception('access denied')
            $err = [System.Management.Automation.ErrorRecord]::new(
                $ex, 'id1', 'PermissionDenied', 'C:/dir/file.txt'
            )
            Get-ErrorRecordPath -Record $err | Should -Be 'C:/dir/file.txt'
        }
        It "Falls back to parsing the message" {
            # Build a real ErrorRecord whose Exception.Message already contains
            # a quoted path. This mirrors what Get-ChildItem actually produces.
            $pathMsg = "Get-ChildItem: Cannot find path ''C:\missing\file.txt''."
            $ex  = New-Object System.IO.DirectoryNotFoundException($pathMsg)
            $err = [System.Management.Automation.ErrorRecord]::new(
                $ex, 'id2', 'ObjectNotFound', $null
            )
            # CategoryInfo.Target is empty so we exercise the regex fallback
            $err.CategoryInfo.Target | Should -BeNullOrEmpty
            Get-ErrorRecordPath -Record $err | Should -Be 'C:\missing\file.txt'
        }
        It "Returns null when no path can be extracted" {
            $err = [System.Management.Automation.ErrorRecord]::new(
                [Exception]'no path here', 'id3', 'NotSpecified', $null
            )
            $result = Get-ErrorRecordPath -Record $err
            [string]::IsNullOrEmpty($result) | Should -Be $true
        }
    }

    Describe "Write-ScriptLog" {
        BeforeEach {
            $script:_testLog = Join-Path ([System.IO.Path]::GetTempPath()) ("cslog-" + [Guid]::NewGuid().ToString("N") + '.log')
            $script:_oldLog = $LogPath
            $LogPath = $script:_testLog
        }
        AfterEach {
            $LogPath = $script:_oldLog
            if (Test-Path $script:_testLog) { Remove-Item $script:_testLog -Force }
        }

        It "Creates the log file and writes a line" {
            Write-ScriptLog 'hello world' -Level 'INFO'
            Test-Path $script:_testLog | Should -Be $true
            $content = Get-Content $script:_testLog
            $content | Should -Match 'INFO'
            $content | Should -Match 'hello world'
        }

        It "Writes with WARNING level" {
            Write-ScriptLog 'be careful' -Level 'WARNING'
            Get-Content $script:_testLog | Should -Match 'WARNING'
        }

        It "Does not throw when log path is missing dir" {
            $badLog = Join-Path ([System.IO.Path]::GetTempPath()) ("no-dir-" + [Guid]::NewGuid().ToString("N") + '\log.txt')
            $LogPath = $badLog
            { Write-ScriptLog 'test' } | Should -Not -Throw
        }

        It "Handles special characters in messages" {
            $LogPath = $script:_testLog
            Write-ScriptLog 'path=C:\my,special"file&^%$.txt' -Level 'INFO'
            $content = Get-Content $script:_testLog -Raw
            $content | Should -Match 'my,special'
        }
    }

    Describe "New-DirectoryIfMissing" {
        It "Creates a missing directory" {
            $d = Join-Path ([System.IO.Path]::GetTempPath()) ("ndir-" + [Guid]::NewGuid().ToString("N"))
            New-DirectoryIfMissing -Path $d -WhatIf:$false
            Test-Path $d | Should -Be $true
            Remove-Item $d -Force
        }
        It "Does not throw if directory already exists" {
            $d = Join-Path ([System.IO.Path]::GetTempPath()) ("ndir-" + [Guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $d | Out-Null
            { New-DirectoryIfMissing -Path $d -WhatIf:$false } | Should -Not -Throw
            Remove-Item $d -Force
        }
        It "Creates nested missing parents" {
            $d = Join-Path ([System.IO.Path]::GetTempPath()) ("ndir-" + [Guid]::NewGuid().ToString("N"), "a", "b", "c")
            New-DirectoryIfMissing -Path $d -WhatIf:$false
            Test-Path $d | Should -Be $true
            Remove-Item (Split-Path $d) -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
