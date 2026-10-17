#requires -Version 7.0
<#
.SYNOPSIS
    Pester 6 测试套件 - mcsrc.ps1
    单元测试 dot-source 后测内部函数；集成测试用 & 调用命令。
#>

Describe 'ConvertTo-Lines' {

    BeforeAll {
        $scriptDir = Split-Path -Parent $PSCommandPath
        $rootDir = Split-Path -Parent $scriptDir
        $mcsrcScript = Join-Path $rootDir '.agents\skills\skill-neoforge-minecraft-sources\scripts\mcsrc.ps1'
        if (-not (Test-Path -LiteralPath $mcsrcScript)) { throw "mcsrc.ps1 not found" }
        . $mcsrcScript
    }

    It 'returns empty array for empty string' {
        $result = ConvertTo-Lines ''
        @($result).Count | Should -Be 0
    }

    It 'returns empty array for null' {
        $result = ConvertTo-Lines $null
        @($result).Count | Should -Be 0
    }

    It 'splits single line' {
        $result = ConvertTo-Lines 'hello'
        $result.Count | Should -Be 1
        $result[0] | Should -Be 'hello'
    }

    It 'splits multiple lines (LF)' {
        $result = ConvertTo-Lines "a`nb`nc"
        $result.Count | Should -Be 3
        $result[0] | Should -Be 'a'
        $result[1] | Should -Be 'b'
        $result[2] | Should -Be 'c'
    }

    It 'splits multiple lines (CRLF)' {
        $result = ConvertTo-Lines "a`r`nb`r`nc"
        $result.Count | Should -Be 3
        $result[0] | Should -Be 'a'
        $result[1] | Should -Be 'b'
        $result[2] | Should -Be 'c'
    }

    It 'strips trailing empty line' {
        $result = ConvertTo-Lines "a`nb`n"
        $result.Count | Should -Be 2
        $result[0] | Should -Be 'a'
        $result[1] | Should -Be 'b'
    }

    It 'handles text with only a newline' {
        $result = ConvertTo-Lines "`n"
        @($result) | Should -Be @('')
    }
}

Describe 'Get-Pattern' {

    BeforeAll {
        $scriptDir = Split-Path -Parent $PSCommandPath
        $rootDir = Split-Path -Parent $scriptDir
        $mcsrcScript = Join-Path $rootDir '.agents\skills\skill-neoforge-minecraft-sources\scripts\mcsrc.ps1'
        . $mcsrcScript
    }

    It 'builds case-insensitive pattern by default' {
        $result = Get-Pattern 'hello'
        $result | Should -Be '(?i)hello'
    }

    It 'builds case-sensitive pattern when -CaseSensitive' {
        $prev = $CaseSensitive
        $CaseSensitive = $true
        try {
            $result = Get-Pattern 'hello'
            $result | Should -BeExactly 'hello'
        }
        finally {
            $CaseSensitive = $prev
        }
    }

    It 'throws on empty value' {
        { Get-Pattern '' } | Should -Throw
    }

    It 'throws on whitespace-only value' {
        { Get-Pattern '   ' } | Should -Throw
    }

    It 'handles regex special characters literally' {
        $result = Get-Pattern 'java.lang.String'
        $result | Should -Be '(?i)java.lang.String'
    }
}

Describe 'ConvertTo-Prefix' {

    BeforeAll {
        $scriptDir = Split-Path -Parent $PSCommandPath
        $rootDir = Split-Path -Parent $scriptDir
        $mcsrcScript = Join-Path $rootDir '.agents\skills\skill-neoforge-minecraft-sources\scripts\mcsrc.ps1'
        . $mcsrcScript
    }

    It 'returns null for empty' {
        $result = ConvertTo-Prefix ''
        $result | Should -Be $null
    }

    It 'returns null for whitespace' {
        $result = ConvertTo-Prefix '   '
        $result | Should -Be $null
    }

    It 'converts backslashes to forward slashes' {
        $result = ConvertTo-Prefix 'net\minecraft'
        $result | Should -Be 'net/minecraft/'
    }

    It 'converts dotted class name to path' {
        $result = ConvertTo-Prefix 'net.minecraft.world'
        $result | Should -Be 'net/minecraft/world/'
    }

    It 'preserves forward-slash path' {
        $result = ConvertTo-Prefix 'net/minecraft/world'
        $result | Should -Be 'net/minecraft/world/'
    }

    It 'does not append trailing slash for .java files' {
        $result = ConvertTo-Prefix 'net/minecraft/world/Level.java'
        $result | Should -Be 'net/minecraft/world/Level.java'
    }

    It 'does not append trailing slash when already present' {
        $result = ConvertTo-Prefix 'net/minecraft/world/'
        $result | Should -Be 'net/minecraft/world/'
    }

    It 'strips leading and trailing slashes' {
        $result = ConvertTo-Prefix '/net/minecraft/'
        $result | Should -Be 'net/minecraft/'
    }
}

Describe 'Test-Prefix' {

    BeforeAll {
        $scriptDir = Split-Path -Parent $PSCommandPath
        $rootDir = Split-Path -Parent $scriptDir
        $mcsrcScript = Join-Path $rootDir '.agents\skills\skill-neoforge-minecraft-sources\scripts\mcsrc.ps1'
        . $mcsrcScript
    }

    It 'returns true for null prefix' {
        $result = Test-Prefix 'net/minecraft/Level.java' $null
        $result | Should -Be $true
    }

    It 'returns true when name starts with prefix' {
        $result = Test-Prefix 'net/minecraft/world/Level.java' 'net/minecraft/world'
        $result | Should -Be $true
    }

    It 'returns true when prefix appears in path (case insensitive)' {
        $result = Test-Prefix 'net/minecraft/world/Level.java' 'World'
        $result | Should -Be $true
    }

    It 'returns false when prefix does not match' {
        $result = Test-Prefix 'net/minecraft/world/Level.java' 'com/example'
        $result | Should -Be $false
    }

    It 'handles prefix without leading slash' {
        $result = Test-Prefix 'net/minecraft/world/Level.java' 'minecraft/world'
        $result | Should -Be $true
    }
}

Describe 'Find-Matches' {

    BeforeAll {
        $scriptDir = Split-Path -Parent $PSCommandPath
        $rootDir = Split-Path -Parent $scriptDir
        $mcsrcScript = Join-Path $rootDir '.agents\skills\skill-neoforge-minecraft-sources\scripts\mcsrc.ps1'
        . $mcsrcScript
    }

    It 'finds a simple literal match' {
        $text = "hello world`nhello again"
        $result = Find-Matches $text 'hello'
        $result.Hits.Count | Should -Be 2
    }

    It 'finds with regex' {
        $text = "line1`nline2`nLINE3"
        $result = Find-Matches $text 'line'
        $result.Hits.Count | Should -Be 3
    }

    It 'returns no hits for non-matching pattern' {
        $text = "line1`nline2"
        $result = Find-Matches $text 'NonExistent'
        $result.Hits.Count | Should -Be 0
    }

    It 'caps results by Limit' {
        $text = "a`na`na`na`na"
        $result = Find-Matches $text 'a' -Limit 2
        $result.Hits.Count | Should -BeLessOrEqual 2
    }

    It 'stores original text lines' {
        $text = "hello`nworld"
        $result = Find-Matches $text 'hello'
        $result.Lines | Should -Not -Be $null
        $result.Lines.Count | Should -Be 2
    }
}

Describe 'Format-MatchGroup' {

    BeforeAll {
        $scriptDir = Split-Path -Parent $PSCommandPath
        $rootDir = Split-Path -Parent $scriptDir
        $mcsrcScript = Join-Path $rootDir '.agents\skills\skill-neoforge-minecraft-sources\scripts\mcsrc.ps1'
        . $mcsrcScript
    }

    It 'formats single match with header' {
        $lines = @('line 1', 'line 2 is a match', 'line 3')
        $hits = [System.Collections.Generic.List[int]]::new()
        $hits.Add(1)
        $result = @(Format-MatchGroup 'TestFile.java' $lines $hits 0)
        $result.Count | Should -BeGreaterOrEqual 2
        $result[0] | Should -Be '== TestFile.java (1 match)'
    }

    It 'uses colon for hit line' {
        $lines = @('line 1', 'line 2 is a match', 'line 3')
        $hits = [System.Collections.Generic.List[int]]::new()
        $hits.Add(1)
        $result = @(Format-MatchGroup 'TestFile.java' $lines $hits 0)
        $result[1] | Should -Match '^\s*\d+:'
    }

    It 'uses dash for context line' {
        $lines = @('before', 'this is a hit line')
        $hits = [System.Collections.Generic.List[int]]::new()
        $hits.Add(1)
        $result = @(Format-MatchGroup 'Test.java' $lines $hits 2)
        ($result -join "`n") | Should -Match '-'
    }

    It 'returns empty for no hits' {
        $lines = @('line 1', 'line 2')
        $noHits = [System.Collections.Generic.List[int]]::new()
        $result = Format-MatchGroup 'TestFile.java' $lines $noHits 0
        @($result).Count | Should -Be 0
    }
}

Describe 'Get-HomeDir' {

    BeforeAll {
        $scriptDir = Split-Path -Parent $PSCommandPath
        $rootDir = Split-Path -Parent $scriptDir
        $mcsrcScript = Join-Path $rootDir '.agents\skills\skill-neoforge-minecraft-sources\scripts\mcsrc.ps1'
        . $mcsrcScript
    }

    It 'returns a non-empty string' {
        $result = Get-HomeDir
        $result | Should -Not -BeNullOrEmpty
    }

    It 'returns a valid directory path' {
        $result = Get-HomeDir
        Test-Path -LiteralPath $result | Should -Be $true
    }
}

Describe 'Project root discovery' {

    BeforeAll {
        $scriptDir = Split-Path -Parent $PSCommandPath
        $rootDir = Split-Path -Parent $scriptDir
        $mcsrcScript = Join-Path $rootDir '.agents\skills\skill-neoforge-minecraft-sources\scripts\mcsrc.ps1'
        . $mcsrcScript

        $outer = Join-Path $TestDrive 'proj'
        $skill = Join-Path $outer '.agents/skills/mc/scripts'
        $plain = Join-Path $TestDrive 'plain'
        New-Item -ItemType Directory -Force -Path (Join-Path $outer '.git'), $skill, (Join-Path $skill '.git'), (Join-Path $plain '.git') | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $outer 'settings.gradle'), (Join-Path $outer 'gradle.properties') | Out-Null
    }

    It 'accepts a directory with .git and a Gradle marker' {
        Test-ProjectRoot $outer | Should -Be $true
    }

    It 'rejects a directory with only .git (skill submodule)' {
        Test-ProjectRoot $skill | Should -Be $false
    }

    It 'walks past a nested .git to the Gradle project root' {
        $found = Find-ProjectRootUp $skill
        $found | Should -Be $outer
    }

    It 'returns null when no Gradle project root exists above' {
        Find-ProjectRootUp $plain | Should -Be $null
    }
}

Describe 'Integration: jar commands' {

    BeforeAll {
        $scriptDir = Split-Path -Parent $PSCommandPath
        $rootDir = Split-Path -Parent $scriptDir
        $mcsrcScript = Join-Path $rootDir '.agents\skills\skill-neoforge-minecraft-sources\scripts\mcsrc.ps1'
        Set-Variable -Name mcsrcScript -Value $mcsrcScript -Scope 1
        Set-Variable -Name rootDir -Value $rootDir -Scope 1
    }

    It 'info displays jar information' {
        $output = & $mcsrcScript info -ProjectRoot $rootDir 2>&1
        $outputString = $output -join "`n"
        $outputString | Should -Match 'jar'
        $outputString | Should -Match 'entries'
    }

    It 'info resolves the project root without -ProjectRoot' {
        $output = & $mcsrcScript info 2>&1
        $output -join "`n" | Should -Match 'jar\s+:'
    }

    It 'find locates a known class' {
        $output = & $mcsrcScript find 'TntBlock' -ProjectRoot $rootDir 2>&1
        $output -join "`n" | Should -Match 'TntBlock'
    }

    It 'find supports regex' {
        $output = & $mcsrcScript find '.*Block$' -Max 10 -ProjectRoot $rootDir 2>&1
        $output -join "`n" | Should -Match 'Block'
    }

    It 'show prints a class' {
        $output = & $mcsrcScript show 'net.minecraft.world.level.Level' -ProjectRoot $rootDir 2>&1
        $output -join "`n" | Should -Match 'public .*class Level'
    }

    It 'show supports line range' {
        $output = & $mcsrcScript show 'net.minecraft.world.level.Level' -Lines '10-20' -ProjectRoot $rootDir 2>&1
        $output -join "`n" | Should -Not -BeNullOrEmpty
    }

    It 'list shows top-level packages' {
        $output = & $mcsrcScript list -ProjectRoot $rootDir 2>&1
        $output -join "`n" | Should -Match 'net'
    }

    It 'list shows classes under a package' {
        $output = & $mcsrcScript list 'net.minecraft.world.level.block' -Max 10 -ProjectRoot $rootDir 2>&1
        $output -join "`n" | Should -Match 'Block'
    }

    It 'grep finds a pattern' {
        $output = & $mcsrcScript grep 'class TntBlock' -Path 'net/minecraft/world/level/block' -ProjectRoot $rootDir 2>&1
        $output -join "`n" | Should -Match 'TntBlock'
    }

    It 'grep reports no match for nonsense' {
        $output = & $mcsrcScript grep 'XYZZYNoSuchPattern12345' -Path 'net/minecraft/world/level/block' -Max 1 -ProjectRoot $rootDir 2>&1
        $output -join "`n" | Should -Match 'no match'
    }

    It 'grep supports context' {
        $output = & $mcsrcScript grep 'class TntBlock' -Path 'net/minecraft/world/level/block' -Context 2 -ProjectRoot $rootDir 2>&1
        $output -join "`n" | Should -Match 'TntBlock'
    }
}

Describe 'Command: help' {

    BeforeAll {
        $scriptDir = Split-Path -Parent $PSCommandPath
        $rootDir = Split-Path -Parent $scriptDir
        $mcsrcScript = Join-Path $rootDir '.agents\skills\skill-neoforge-minecraft-sources\scripts\mcsrc.ps1'
        Set-Variable -Name mcsrcScript -Value $mcsrcScript -Scope 1
    }

    It 'displays help text with all commands' {
        $output = & $mcsrcScript help 2>&1
        $outputString = $output -join "`n"
        $outputString | Should -Match 'mcsrc'
        $outputString | Should -Match 'info'
        $outputString | Should -Match 'find'
        $outputString | Should -Match 'grep'
        $outputString | Should -Match 'show'
        $outputString | Should -Match 'list'
    }
}
