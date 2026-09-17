function Resolve-KaraOkBuildOptions {
    param(
        [string]$ApplicationName = 'KaraOK',
        [string]$ApplicationId = 'com.jrpbone.karaok',
        [string]$VersionName,
        [string]$BuildNumber,
        [string]$Format = 'apk',
        [string]$Mode = 'release',
        [switch]$Interactive
    )

    $fields = @(
        @{ Key = 'ApplicationName'; Prompt = 'Application name'; Value = $ApplicationName;
            Valid = { param($v) $v -match '^[^<>:"/\\|?*\x00-\x1f]+$' -and $v -notmatch '[. ]$' -and $v -notmatch '^[@?]' };
            Error = 'Enter an application name without filename-invalid characters or a trailing dot.' },
        @{ Key = 'ApplicationId'; Prompt = 'Android package ID'; Value = $ApplicationId;
            Valid = { param($v) $v -cmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$' };
            Error = 'Use a dotted Android package ID, such as com.jrpbone.karaok.' },
        @{ Key = 'VersionName'; Prompt = 'Version (MAJOR.MINOR.PATCH)'; Value = $VersionName;
            Valid = { param($v) $v -match '^\d+\.\d+\.\d+$' };
            Error = 'Use a version such as 1.0.0.' },
        @{ Key = 'BuildNumber'; Prompt = 'Build number'; Value = $BuildNumber;
            Valid = { param($v) $n = 0; $v -match '^\d+$' -and [int]::TryParse($v, [ref]$n) -and $n -gt 0 -and $n -le 2100000000 };
            Error = 'Enter a build number from 1 to 2100000000.' },
        @{ Key = 'Format'; Prompt = 'Output format (apk/aab)'; Value = $Format;
            Valid = { param($v) $v -in @('apk', 'aab') };
            Error = 'Enter apk or aab.' },
        @{ Key = 'Mode'; Prompt = 'Build mode (release/debug/profile)'; Value = $Mode;
            Valid = { param($v) $v -in @('release', 'debug', 'profile') };
            Error = 'Enter release, debug, or profile.' }
    )
    $result = [ordered]@{}
    foreach ($field in $fields) {
        do {
            $value = $field.Value.Trim()
            if ($Interactive) {
                $answer = Read-Host "$($field.Prompt) [$value]"
                if (-not [string]::IsNullOrWhiteSpace($answer)) { $value = $answer.Trim() }
            }
            $valid = -not [string]::IsNullOrWhiteSpace($value) -and (& $field.Valid $value)
            if (-not $valid) {
                if (-not $Interactive) { throw "$($field.Key): $($field.Error)" }
                Write-Host $field.Error -ForegroundColor Yellow
            }
        } until ($valid)
        $result[$field.Key] = $value
    }
    $result.BuildNumber = [int]$result.BuildNumber
    $result.Format = $result.Format.ToLowerInvariant()
    $result.Mode = $result.Mode.ToLowerInvariant()
    return [pscustomobject]$result
}
