$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/build-options.ps1')

# A missing prompt, ignored answer, or invalid value reaching the build breaks these checks.
function Read-Host {
    param([string]$Prompt)
    if ($script:answers.Count -eq 0) { throw "Unexpected prompt: $Prompt" }
    $script:prompts.Add($Prompt)
    return $script:answers.Dequeue()
}
function Set-Answers([string[]]$Values) {
    $script:answers = [Collections.Generic.Queue[string]]::new()
    foreach ($value in $Values) { $script:answers.Enqueue($value) }
    $script:prompts = [Collections.Generic.List[string]]::new()
}
$defaults = @{
    ApplicationName = 'KaraOK'; ApplicationId = 'com.jrpbone.karaok'
    VersionName = '1.0.0'; BuildNumber = 2; Format = 'apk'; Mode = 'release'
}
Set-Answers @('', '', '', '', '', '')
$result = Resolve-KaraOkBuildOptions @defaults -Interactive
foreach ($key in $defaults.Keys) {
    if ($result.$key -ne $defaults[$key]) { throw "Default changed: $key" }
}
if ($prompts.Count -ne 6) { throw 'All six build settings must be prompted.' }
Write-Output 'PASS: blank answers preserve all six defaults'

Set-Answers @('My Karaoke', 'com.example.player', '2.3.4', '12', 'AAB', 'DEBUG')
$result = Resolve-KaraOkBuildOptions @defaults -Interactive
if ($result.ApplicationName -ne 'My Karaoke' -or $result.ApplicationId -ne 'com.example.player' -or
    $result.VersionName -ne '2.3.4' -or $result.BuildNumber -ne 12 -or
    $result.Format -cne 'aab' -or $result.Mode -cne 'debug') { throw 'User selections were not applied.' }
Write-Output 'PASS: custom identity, version, bundle format, and debug mode are applied'

Set-Answers @('../bad', 'KaraOK', 'invalid', 'com.example.app', 'v2', '2.0.0', '0', '2147483648', '3', 'exe', 'apk', 'invalid', 'profile')
$result = Resolve-KaraOkBuildOptions @defaults -Interactive
if ($answers.Count -ne 0 -or $result.BuildNumber -ne 3 -or $result.Mode -ne 'profile') {
    throw 'Invalid input did not re-prompt correctly.'
}
Write-Output 'PASS: invalid inputs re-prompt without reaching the build'

foreach ($invalid in @(
    @{ ApplicationName = '../escape' }, @{ ApplicationId = 'com.bad-id.app' },
    @{ VersionName = '1.0' }, @{ BuildNumber = 0 }, @{ BuildNumber = 2100000001 },
    @{ Format = 'exe' }, @{ Mode = 'unknown' }
)) {
    $options = $defaults.Clone()
    foreach ($key in $invalid.Keys) { $options[$key] = $invalid[$key] }
    $rejected = $false
    try { Resolve-KaraOkBuildOptions @options | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Invalid non-interactive setting was accepted.' }
}
Write-Output 'PASS: non-interactive values are validated without prompting'
