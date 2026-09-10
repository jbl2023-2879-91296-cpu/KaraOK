# Public build endpoints only. Never load backend/.env into a client build.
function Resolve-KaraOkBuildApi {
    param(
        [ValidateSet('debug', 'profile', 'release')] [string]$Mode,
        [string]$ExplicitUrl,
        [string]$EnvironmentUrl,
        [string[]]$AdditionalDefines
    )

    foreach ($definition in $AdditionalDefines) {
        if ($definition -match '^\s*(API_BASE_URL|APP_BASE_URL)\s*=') {
            throw 'Use -ApiBaseUrl (alias -AppBaseUrl), not -DartDefine, to configure the API URL.'
        }
    }
    $source = 'mode default'
    $url = if ($Mode -eq 'debug') {
        'http://10.0.2.2:5000/api'
    } else {
        'https://139.99.89.112/api'
    }
    if (-not [string]::IsNullOrWhiteSpace($EnvironmentUrl)) {
        $url = $EnvironmentUrl
        $source = 'KARAOK_API_BASE_URL'
    }
    if (-not [string]::IsNullOrWhiteSpace($ExplicitUrl)) {
        $url = $ExplicitUrl
        $source = '-ApiBaseUrl'
    }
    $url = $url.Trim().TrimEnd('/')
    $parsed = $null
    if (-not [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$parsed) -or
        $parsed.Scheme -notin @('http', 'https') -or -not $parsed.Host) {
        throw 'ApiBaseUrl must be an absolute HTTP or HTTPS URL.'
    }
    if ($parsed.UserInfo -or $parsed.Query -or $parsed.Fragment -or $parsed.AbsolutePath -cne '/api') {
        throw 'ApiBaseUrl must end in /api and contain no credentials, query, or fragment.'
    }
    if ($Mode -in @('release', 'profile') -and
        ($parsed.Scheme -ne 'https' -or $parsed.IsLoopback -or $parsed.Host -eq '10.0.2.2')) {
        throw 'Release and profile builds require a remote HTTPS API URL.'
    }
    [pscustomobject]@{ Url = $url; Source = $source; DartDefine = "--dart-define=API_BASE_URL=$url" }
}
