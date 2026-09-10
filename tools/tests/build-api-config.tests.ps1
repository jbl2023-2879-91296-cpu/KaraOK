$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/build-api-config.ps1')

foreach ($mode in @('release', 'profile', 'debug')) {
    $expected = if ($mode -eq 'debug') { 'http://10.0.2.2:5000/api' } else { 'https://139.99.89.112/api' }
    $result = Resolve-KaraOkBuildApi -Mode $mode
    if ($result.Url -ne $expected -or $result.DartDefine -ne "--dart-define=API_BASE_URL=$expected") {
        throw "Wrong endpoint or Flutter define for $mode"
    }
}
$result = Resolve-KaraOkBuildApi -Mode release -EnvironmentUrl 'https://staging.example.com/api/'
if ($result.Url -ne 'https://staging.example.com/api' -or $result.Source -ne 'KARAOK_API_BASE_URL') {
    throw 'Environment override or trailing slash normalization failed'
}
$result = Resolve-KaraOkBuildApi -Mode release -EnvironmentUrl 'https://staging.example.com/api' -ExplicitUrl ' https://other.example.com/api/ '
if ($result.Url -ne 'https://other.example.com/api' -or $result.Source -ne '-ApiBaseUrl') {
    throw 'Explicit override must win'
}
foreach ($url in @('invalid', 'http://example.com/api', 'https://localhost/api', 'https://10.0.2.2/api', 'https://example.com', 'https://example.com/api?token=x', 'https://user:password@example.com/api', 'https://example.com/api#x')) {
    $rejected = $false
    try { Resolve-KaraOkBuildApi -Mode release -ExplicitUrl $url | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Invalid endpoint was accepted' }
}
foreach ($key in @('API_BASE_URL', 'APP_BASE_URL')) {
    $rejected = $false
    try { Resolve-KaraOkBuildApi -Mode release -AdditionalDefines "$key=https://example.com/api" | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Conflicting Dart define was accepted' }
}
Write-Output 'PASS: API defaults, Flutter key, precedence, normalization, and invalid overrides'
