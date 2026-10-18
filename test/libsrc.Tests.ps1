#requires -Version 7.0
<#
.SYNOPSIS
    Pester 6 tests for libsrc.ps1.
    Unit tests dot-source the script; integration tests invoke it.
#>

Describe 'libsrc.ps1' {

    BeforeAll {
        $script:scriptDir = Split-Path -Parent $PSCommandPath
        $script:rootDir = Split-Path -Parent $script:scriptDir
        $script:libsrcScript = Join-Path $script:rootDir '.agents\skills\skill-external-lib-sources\scripts\libsrc.ps1'
        if (-not (Test-Path -LiteralPath $script:libsrcScript)) { throw 'libsrc.ps1 not found' }

        $env:LIBSRC_SOURCE_ONLY = '1'
        . $script:libsrcScript
        Remove-Item Env:LIBSRC_SOURCE_ONLY -ErrorAction SilentlyContinue

        # A cache with three modules plus artifacts that must be ignored.
        $script:cache = Join-Path $TestDrive 'modules-2/files-2.1'

        function New-FakeLibrary {
            param(
                [string]$Root,
                [string]$Group,
                [string]$Module,
                [string]$Version,
                [switch]$NoSources,
                [switch]$NoBinary
            )
            $hashDir = Join-Path $Root (Join-Path $Group (Join-Path $Module (Join-Path $Version '0123456789abcdef')))
            New-Item -ItemType Directory -Force -Path $hashDir | Out-Null
            if (-not $NoBinary) {
                New-Item -ItemType File -Force -Path (Join-Path $hashDir "$Module-$Version.jar") | Out-Null
            }
            if (-not $NoSources) {
                New-Item -ItemType File -Force -Path (Join-Path $hashDir "$Module-$Version-sources.jar") | Out-Null
            }
            return $hashDir
        }

        $script:alphaDir = New-FakeLibrary -Root $script:cache -Group 'com.example' -Module 'alpha' -Version '1.0.0'
        $null = New-FakeLibrary -Root $script:cache -Group 'com.example' -Module 'beta' -Version '2.0.0' -NoSources
        $script:gammaDir = New-FakeLibrary -Root $script:cache -Group 'org.other' -Module 'gamma' -Version '3.1.4'

        function New-SourceJar {
            param([string]$Path, [hashtable]$Entries)
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
            $zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($key in $Entries.Keys) {
                    $entry = $zip.CreateEntry($key)
                    $writer = [System.IO.StreamWriter]::new($entry.Open(), [System.Text.UTF8Encoding]::new($false))
                    try { $writer.Write($Entries[$key]) } finally { $writer.Dispose() }
                }
            }
            finally { $zip.Dispose() }
        }

        # Real source jars so find/grep/show/list can read entries.
        $script:alphaSourceJar = Join-Path $script:alphaDir 'alpha-1.0.0-sources.jar'
        New-SourceJar -Path $script:alphaSourceJar -Entries @{
            'com/example/alpha/Alpha.java' = @'
package com.example.alpha;

public class Alpha {
    public static String greet() {
        return "alpha";
    }
}
'@
            'com/example/alpha/Helper.java' = @'
package com.example.alpha;

final class Helper {
    static int add(int a, int b) {
        return a + b;
    }
}
'@
        }

        $script:gammaSourceJar = Join-Path $script:gammaDir 'gamma-3.1.4-sources.jar'
        New-SourceJar -Path $script:gammaSourceJar -Entries @{
            'org/example/gamma/Gamma.java' = @'
package org.example.gamma;

public class Gamma {
    public static String name() {
        return "gamma";
    }
}
'@
            'org/example/gamma/Alpha.java' = @'
package org.example.gamma;

public class Alpha {
    public static String origin() {
        return "gamma";
    }
}
'@
        }

        # A classifier jar must not replace the main alpha jar.
        New-Item -ItemType File -Force -Path (Join-Path $script:alphaDir 'alpha-1.0.0-tests.jar') | Out-Null
        # Javadoc-only and natives-only modules are not libraries with a jar.
        $javadocDir = Join-Path $script:cache 'com.example/javadoc-only/1.0.0/0123456789abcdef'
        New-Item -ItemType Directory -Force -Path $javadocDir | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $javadocDir 'javadoc-only-1.0.0-javadoc.jar') | Out-Null
        $nativesDir = Join-Path $script:cache 'com.example/natives-only/1.0.0/0123456789abcdef'
        New-Item -ItemType Directory -Force -Path $nativesDir | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $nativesDir 'natives-only-1.0.0-natives-windows.jar') | Out-Null

        # A second Gradle home used to test -GradleHome resolution.
        $script:fakeHome = Join-Path $TestDrive 'gradle-home'
        $script:homeCache = Join-Path $script:fakeHome 'caches/modules-2/files-2.1'
        $null = New-FakeLibrary -Root $script:homeCache -Group 'com.home' -Module 'delta' -Version '4.0'

        # A synthetic IntelliJ Gradle model. The learner entry comes first so
        # the reader has to replace it with the main alpha jar.
        $script:ideModel = Join-Path $TestDrive 'libraries.xml'
        $ideXml = @'
<component name="libraryTable">
  <library name="Gradle: com.example:alpha:natives-windows:1.0.0" type="java-imported" __external-system-id="GRADLE">
    <properties groupId="com.example" artifactId="alpha" version="1.0.0" baseVersion="1.0.0" />
    <CLASSES>
      <root url="jar://$USER_HOME$/fake-cache/com.example/alpha/1.0.0/hash/alpha-1.0.0-natives-windows.jar!/" />
    </CLASSES>
    <JAVADOC />
    <SOURCES>
      <root url="jar://__ALPHA_SOURCES__!/" />
    </SOURCES>
  </library>
  <library name="Gradle: com.example:alpha:1.0.0" type="java-imported" __external-system-id="GRADLE">
    <properties groupId="com.example" artifactId="alpha" version="1.0.0" baseVersion="1.0.0" />
    <CLASSES>
      <root url="jar://$USER_HOME$/fake-cache/com.example/alpha/1.0.0/hash/alpha-1.0.0.jar!/" />
    </CLASSES>
    <JAVADOC />
    <SOURCES>
      <root url="jar://__ALPHA_SOURCES__!/" />
    </SOURCES>
  </library>
  <library name="Gradle: com.example:beta:2.0.0" type="java-imported" __external-system-id="GRADLE">
    <properties groupId="com.example" artifactId="beta" version="2.0.0" baseVersion="2.0.0" />
    <CLASSES>
      <root url="jar://$PROJECT_DIR$/libs/beta-2.0.0.jar!/" />
    </CLASSES>
    <JAVADOC />
    <SOURCES />
  </library>
</component>
'@
        $ideXml = $ideXml.Replace('__ALPHA_SOURCES__', ($script:alphaSourceJar -replace '\\', '/'))
        Set-Content -LiteralPath $script:ideModel -Value $ideXml -Encoding utf8

        # A fake IntelliJ system directory + fake project for discovery tests.
        $script:fakeProject = Join-Path $TestDrive 'fake-project'
        New-Item -ItemType Directory -Force -Path (Join-Path $script:fakeProject '.git') | Out-Null
        New-Item -ItemType File -Force -Path (Join-Path $script:fakeProject 'settings.gradle') | Out-Null

        $script:fakeLocalAppData = Join-Path $TestDrive 'localappdata'
        $ideProjectDir = Join-Path $script:fakeLocalAppData 'JetBrains/IntelliJIdea2099.1/projects/fake-project.deadbeef'
        $modelDir = Join-Path $ideProjectDir 'external_build_system/project'
        New-Item -ItemType Directory -Force -Path $modelDir | Out-Null
        Copy-Item -LiteralPath $script:ideModel -Destination (Join-Path $modelDir 'libraries.xml')

        $projectPath = ($script:fakeProject -replace '\\', '/')
        $stateXml = '<project version="4"><component name="ExternalSystemProjectTracker">{ "' + $projectPath + '": {} }</component></project>'
        Set-Content -LiteralPath (Join-Path $ideProjectDir 'cache-state.xml') -Value $stateXml -Encoding utf8

        $script:realGradleHome = $null
        if ($env:GRADLE_USER_HOME) { $script:realGradleHome = $env:GRADLE_USER_HOME }
        elseif ($env:USERPROFILE) { $script:realGradleHome = Join-Path $env:USERPROFILE '.gradle' }
        elseif ($env:HOME) { $script:realGradleHome = Join-Path $env:HOME '.gradle' }

        $script:realCache = $null
        if ($script:realGradleHome) {
            $script:realCache = Join-Path $script:realGradleHome 'caches/modules-2/files-2.1'
        }
    }

    Context 'cache scanning' {

        It 'finds every module version with a jar' {
            $libs = @(Get-CachedLibraries $script:cache)
            $libs.Count | Should -Be 3
        }

        It 'derives group, module and version from the cache path' {
            $ids = @(Get-CachedLibraries $script:cache | ForEach-Object { "$($_.Group):$($_.Module):$($_.Version)" })
            $ids | Should -Contain 'com.example:alpha:1.0.0'
            $ids | Should -Contain 'com.example:beta:2.0.0'
            $ids | Should -Contain 'org.other:gamma:3.1.4'
        }

        It 'records the source jar when present' {
            $alpha = @(Get-CachedLibraries $script:cache | Where-Object { $_.Module -eq 'alpha' })[0]
            $alpha.Sources | Should -Not -BeNullOrEmpty
            $alpha.Sources | Should -Match 'alpha-1\.0\.0-sources\.jar$'
        }

        It 'prefers the main jar over a classifier jar' {
            $alpha = @(Get-CachedLibraries $script:cache | Where-Object { $_.Module -eq 'alpha' })[0]
            $alpha.Binary | Should -Match 'alpha-1\.0\.0\.jar$'
        }

        It 'keeps binary-only libraries' {
            $beta = @(Get-CachedLibraries $script:cache | Where-Object { $_.Module -eq 'beta' })[0]
            $beta.Sources | Should -BeNullOrEmpty
            $beta.Binary | Should -Match 'beta-2\.0\.0\.jar$'
        }

        It 'ignores javadoc-only and natives-only modules' {
            $ids = @(Get-CachedLibraries $script:cache | ForEach-Object { $_.Module })
            $ids | Should -Not -Contain 'javadoc-only'
            $ids | Should -Not -Contain 'natives-only'
        }
    }

    Context 'pattern building' {

        It 'builds a case-insensitive pattern by default' {
            Get-Pattern 'hello' | Should -Be '(?i)hello'
        }

        It 'returns the raw pattern with -CaseSensitive' {
            $previous = $CaseSensitive
            $CaseSensitive = $true
            try {
                Get-Pattern 'hello' | Should -BeExactly 'hello'
            }
            finally {
                $CaseSensitive = $previous
            }
        }

        It 'returns null for empty values' {
            Get-Pattern '' | Should -Be $null
            Get-Pattern '   ' | Should -Be $null
        }
    }

    Context 'info command' {

        It 'reports the project model and cache counts' {
            $output = & $script:libsrcScript info -Cache $script:cache 2>&1
            $text = $output -join "`n"
            $text | Should -Match 'project\s+:'
            $text | Should -Match 'model\s+:'
            $text | Should -Match 'cache\s+: .*3 libraries, 2 with sources'
        }
    }

    Context 'libs command' {

        It 'lists all cached libraries with a source marker' {
            $output = & $script:libsrcScript libs -Cache $script:cache 2>&1
            $text = $output -join "`n"
            $text | Should -Match 'com\.example:alpha\s+1\.0\.0\s+src'
            $text | Should -Match 'com\.example:beta\s+2\.0\.0\s+bin'
            $text | Should -Match 'org\.other:gamma\s+3\.1\.4\s+src'
        }

        It 'filters by regex' {
            $output = & $script:libsrcScript libs alpha -Cache $script:cache 2>&1
            $text = $output -join "`n"
            $text | Should -Match 'com\.example:alpha'
            $text | Should -Not -Match 'beta'
            $text | Should -Not -Match 'gamma'
        }

        It 'honors -CaseSensitive' {
            $loose = & $script:libsrcScript libs ALPHA -Cache $script:cache 2>&1
            ($loose -join "`n") | Should -Match 'com\.example:alpha'

            $strict = & $script:libsrcScript libs ALPHA -CaseSensitive -Cache $script:cache 2>&1
            ($strict -join "`n") | Should -Match "no library matching 'ALPHA'"
        }

        It 'filters with -SourcesOnly' {
            $output = & $script:libsrcScript libs com.example -SourcesOnly -Cache $script:cache 2>&1
            $text = $output -join "`n"
            $text | Should -Match 'alpha'
            $text | Should -Not -Match 'beta'
        }

        It 'prints jar paths with -Paths' {
            $output = & $script:libsrcScript libs alpha -Paths -Cache $script:cache 2>&1
            $text = $output -join "`n"
            $text | Should -Match 'sources: .*alpha-1\.0\.0-sources\.jar'
            $text | Should -Match 'jar\s+: .*alpha-1\.0\.0\.jar'
        }

        It 'caps results with -Max and reports the cap' {
            $output = & $script:libsrcScript libs -Max 1 -Cache $script:cache 2>&1
            $text = $output -join "`n"
            $text | Should -Match 'capped at 1'
        }

        It 'removes the cap with -All' {
            $output = & $script:libsrcScript libs -Max 1 -All -Cache $script:cache 2>&1
            $text = $output -join "`n"
            $text | Should -Not -Match 'capped at'
        }

        It 'reports no match' {
            $output = & $script:libsrcScript libs no-such-library -Cache $script:cache 2>&1
            ($output -join "`n") | Should -Match "no library matching 'no-such-library'"
        }

        It 'resolves the cache from -GradleHome' {
            $output = & $script:libsrcScript libs delta -GradleHome $script:fakeHome -Global 2>&1
            ($output -join "`n") | Should -Match 'com\.home:delta'
        }
    }

    Context 'project scope' {

        It 'reads libraries from an explicit IntelliJ model' {
            $output = & $script:libsrcScript libs -IdeModel $script:ideModel -ProjectRoot $script:fakeProject 2>&1
            $text = $output -join "`n"
            $text | Should -Match '# scope : project \(IntelliJ Gradle model\)'
            $text | Should -Match 'com\.example:alpha\s+1\.0\.0\s+src'
            $text | Should -Match 'com\.example:beta\s+2\.0\.0\s+bin'
        }

        It 'deduplicates classifier entries and keeps the main jar' {
            $output = & $script:libsrcScript libs alpha -IdeModel $script:ideModel -ProjectRoot $script:fakeProject -Paths 2>&1
            $text = $output -join "`n"
            ([regex]::Matches($text, 'com\.example:alpha')).Count | Should -Be 1
            $text | Should -Match 'jar\s+: .*alpha-1\.0\.0\.jar'
            $text | Should -Not -Match 'natives-windows\.jar'
        }

        It 'expands $PROJECT_DIR$ in IDE roots' {
            $output = & $script:libsrcScript libs beta -IdeModel $script:ideModel -ProjectRoot $script:fakeProject -Paths 2>&1
            ($output -join "`n") | Should -Match 'jar\s+: .*fake-project\\libs\\beta-2\.0\.0\.jar'
        }

        It 'honors -SourcesOnly for project libraries' {
            $output = & $script:libsrcScript libs -IdeModel $script:ideModel -ProjectRoot $script:fakeProject -SourcesOnly 2>&1
            $text = $output -join "`n"
            $text | Should -Match 'com\.example:alpha'
            $text | Should -Not -Match 'com\.example:beta'
        }

        It 'finds the IntelliJ model for an explicit project root' {
            $previous = $env:LOCALAPPDATA
            $env:LOCALAPPDATA = $script:fakeLocalAppData
            try {
                $output = & $script:libsrcScript libs -ProjectRoot $script:fakeProject 2>&1
            }
            finally {
                $env:LOCALAPPDATA = $previous
            }
            $text = $output -join "`n"
            $text | Should -Match '# scope : project'
            $text | Should -Match 'com\.example:alpha'
            $text | Should -Match 'com\.example:beta'
        }

        It 'marks -Global as cache-wide' {
            $output = & $script:libsrcScript libs -Global -Cache $script:cache 2>&1
            ($output -join "`n") | Should -Match '# scope : cache-wide'
        }

        It 'rejects -Global with -IdeModel' {
            $output = & $script:libsrcScript libs -Global -IdeModel $script:ideModel 2>&1
            ($output -join "`n") | Should -Match 'cannot be used together'
        }
    }

    Context 'source queries' {

        It 'finds classes and prefixes the library id' {
            $output = & $script:libsrcScript find 'Alpha$' -Cache $script:cache -Global -Lib alpha 2>&1
            $text = $output -join "`n"
            $text | Should -Match 'com\.example:alpha:1\.0\.0!com\.example\.alpha\.Alpha'
        }

        It 'filters find by -Path' {
            $output = & $script:libsrcScript find '.*' -Cache $script:cache -Global -Lib alpha -Path com/example/alpha -Max 2 2>&1
            $text = $output -join "`n"
            $text | Should -Match 'com\.example\.alpha\.Alpha'
            $text | Should -Match 'capped at 2'
        }

        It 'greps source text with context' {
            $output = & $script:libsrcScript grep 'greet' -Cache $script:cache -Global -Lib alpha -Path com/example/alpha -Context 1 2>&1
            $text = $output -join "`n"
            $text | Should -Match '== com\.example:alpha:1\.0\.0!com/example/alpha/Alpha\.java \(1 match\)'
            $text | Should -Match 'return "alpha";'
        }

        It 'shows a class by lib!class' {
            $output = & $script:libsrcScript show 'com.example:alpha:1.0.0!com.example.alpha.Alpha' -Cache $script:cache -Global -Lines 1-10 2>&1
            $text = $output -join "`n"
            $text | Should -Match '# com\.example:alpha:1\.0\.0!com/example/alpha/Alpha\.java'
            $text | Should -Match 'public class Alpha'
        }

        It 'shows a class by simple name within -Lib' {
            $output = & $script:libsrcScript show Alpha -Cache $script:cache -Global -Lib alpha -Lines 1-5 2>&1
            ($output -join "`n") | Should -Match 'public class Alpha'
        }

        It 'reports ambiguous classes' {
            $output = & $script:libsrcScript show Alpha -Cache $script:cache -Global -Lib 'alpha|gamma' 2>&1
            $text = $output -join "`n"
            $text | Should -Match 'ambiguous'
            $text | Should -Match 'com\.example:alpha'
            $text | Should -Match 'org\.other:gamma'
        }

        It 'lists packages without a prefix' {
            $output = & $script:libsrcScript list -Cache $script:cache -Global -Lib alpha 2>&1
            ($output -join "`n") | Should -Match 'com/ \(2 classes\)'
        }

        It 'lists classes under a package' {
            $output = & $script:libsrcScript list com.example.alpha -Cache $script:cache -Global -Lib alpha -Max 5 2>&1
            $text = $output -join "`n"
            $text | Should -Match 'com\.example:alpha:1\.0\.0!com\.example\.alpha\.Alpha'
            $text | Should -Match 'com\.example:alpha:1\.0\.0!com\.example\.alpha\.Helper'
        }

        It 'reads project-scoped sources from the IntelliJ model' {
            $output = & $script:libsrcScript find 'Alpha$' -IdeModel $script:ideModel -ProjectRoot $script:fakeProject -Lib alpha 2>&1
            ($output -join "`n") | Should -Match 'com\.example:alpha:1\.0\.0!com\.example\.alpha\.Alpha'
        }

        It 'fails with libsrc: when -Lib has no match' {
            $output = & $script:libsrcScript find Alpha -Cache $script:cache -Global -Lib no-such-lib 2>&1
            ($output -join "`n") | Should -Match "libsrc: no library matching 'no-such-lib'"
        }
    }

    Context 'errors and help' {

        It 'fails with a libsrc: message and exit code 2 for a missing cache' {
            $pwshExe = Join-Path $PSHOME 'pwsh.exe'
            if (-not (Test-Path -LiteralPath $pwshExe)) { $pwshExe = (Get-Process -Id $PID).Path }

            $missing = Join-Path $TestDrive 'missing-cache'
            $output = & $pwshExe -NoProfile -File $script:libsrcScript libs -Cache $missing 2>&1
            $LASTEXITCODE | Should -Be 2
            ($output -join "`n") | Should -Match 'libsrc: -Cache not found'
        }

        It 'displays help text with the implemented commands' {
            $output = & $script:libsrcScript help 2>&1
            $text = $output -join "`n"
            $text | Should -Match 'libsrc'
            $text | Should -Match 'info'
            $text | Should -Match 'libs'
            $text | Should -Match 'SourcesOnly'
        }
    }

    Context 'real Gradle cache' {

        It 'lists a cached library' {
            if (-not $script:realCache -or -not (Test-Path -LiteralPath $script:realCache)) {
                Set-ItResult -Skipped -Because 'no real Gradle cache on this machine'
                return
            }
            $output = & $script:libsrcScript libs -SourcesOnly -Max 1 -Cache $script:realCache 2>&1
            ($output -join "`n") | Should -Match 'src'
        }
    }
}
