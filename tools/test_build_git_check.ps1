$ErrorActionPreference = 'Stop'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'build_karaok.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw "Build script parse errors: $parseErrors" }
foreach ($name in @('Get-KaraOkGitState', 'Assert-KaraOkBuildGitState')) {
    $helper = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $false))
    if ($helper.Count -ne 1) { throw "Expected helper: $name" }
    . ([scriptblock]::Create($helper[0].Extent.Text))
}
function Assert-True($Condition, $Message) {
    if (-not $Condition) { throw $Message }
    Write-Output "PASS: $Message"
}
function Invoke-TestGit {
    & git -C $fixture @args | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Fixture Git command failed.' }
}
# Synthetic files only; never copy project data or invoke a build.
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('karaok-build-git-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path (Join-Path $fixture 'frontend') -Force | Out-Null
try {
    Invoke-TestGit init --quiet
    Invoke-TestGit config user.name 'Build Test'
    Invoke-TestGit config user.email 'build-test@example.invalid'
    Set-Content -LiteralPath (Join-Path $fixture 'tracked.txt') -Value 'original'
    Invoke-TestGit add -- tracked.txt
    Invoke-TestGit commit --quiet -m 'fixture'
    $frontend = Join-Path $fixture 'frontend'
    $state = Get-KaraOkGitState -Directory $frontend
    $head = & git -C $fixture rev-parse HEAD
    Assert-True ($state.GitDirty -is [bool] -and -not $state.GitDirty) 'Clean repository records boolean false'
    Assert-True ($state.GitCommit -eq $head) 'Commit matches HEAD'
    Assert-KaraOkBuildGitState -State $state -Mode release
    Set-Content -LiteralPath (Join-Path $fixture 'untracked.txt') -Value 'user data'
    Invoke-TestGit config status.showUntrackedFiles no
    $state = Get-KaraOkGitState -Directory $frontend
    Assert-True ($state.GitDirty -eq $true) 'Untracked sibling is dirty even when Git hides untracked files by default'
    $refused = $false
    try { Assert-KaraOkBuildGitState -State $state -Mode release } catch { $refused = $_ -match 'Release build refused.*AllowDirty' }
    Assert-True $refused 'Dirty release refuses with actionable override message'
    foreach ($mode in @('debug', 'profile', 'release')) {
        $warnings = @()
        Assert-KaraOkBuildGitState -State $state -Mode $mode -AllowDirty:($mode -eq 'release') -WarningVariable warnings -WarningAction SilentlyContinue
        Assert-True ($warnings.Count -eq 1) "$mode dirty build warns (release explicitly allowed)"
    }
    Invoke-TestGit add -- untracked.txt
    Assert-True ((Get-KaraOkGitState -Directory $frontend).GitDirty) 'Staged changes are dirty'
    Invoke-TestGit commit --quiet -m 'second fixture'
    $newState = Get-KaraOkGitState -Directory $frontend
    Assert-True (-not $newState.GitDirty -and $newState.GitCommit -ne $head) 'Commit refresh follows the current HEAD'
    Add-Content -LiteralPath (Join-Path $fixture 'tracked.txt') -Value 'changed'
    Assert-True ((Get-KaraOkGitState -Directory $frontend).GitDirty) 'Unstaged tracked changes are dirty'
    $json = $state | ConvertTo-Json | ConvertFrom-Json
    Assert-True ($json.GitDirty -is [bool] -and $json.GitCommit -eq $head) 'Provenance survives JSON as a boolean and exact commit'
    $source = $ast.Extent.Text
    Assert-True ($source.Contains('gitDirty = [bool]$gitDirty')) 'Manifest writes boolean gitDirty'
    Assert-True (([regex]::Matches($source, 'Assert-KaraOkBuildGitState -State \$gitState -Mode \$Mode -AllowDirty:\$AllowDirty')).Count -eq 2) 'Resolved mode and pre-build refresh both enforce policy'
    Write-Output 'Build provenance checks passed. No build was executed.'
}
finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedFixture.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolvedFixture) -notlike 'karaok-build-git-*') { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
