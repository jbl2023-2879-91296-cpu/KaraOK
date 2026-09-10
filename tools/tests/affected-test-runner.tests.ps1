$ErrorActionPreference = 'Stop'

$runnerPath = Join-Path (Split-Path -Parent $PSScriptRoot) `
    'run-affected-tests.ps1'
if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
    throw "FAIL: affected-test runner is missing: $runnerPath"
}

. $runnerPath

function Assert-TestGroups {
    param(
        [Parameter(Mandatory = $true)][string]$Scenario,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Expected,
        [AllowEmptyCollection()][string[]]$Actual
    )

    $expectedText = $Expected -join ','
    $actualText = @($Actual) -join ','
    if ($actualText -ne $expectedText) {
        throw "FAIL: $Scenario expected '$expectedText', got '$actualText'"
    }
}

$settingsGroups = @(Get-AffectedTestGroups -ChangedPaths @(
        'backend/settings_recommendations/engine.py'
        'frontend/lib/features/sound_settings/data/settings_api.dart'
        'tools/lib/dev-command-resolution.ps1'
    ))
Assert-TestGroups `
    -Scenario 'known settings changes select focused groups' `
    -Expected @('backend-settings', 'flutter-settings', 'flutter-analyze', 'powershell-tools') `
    -Actual $settingsGroups
Write-Output 'PASS: known settings changes select focused groups'

$calibrationGroups = @(Get-AffectedTestGroups -ChangedPaths @(
        'backend/audio_thresholds/amplifier_control_priors.json'
        'frontend/lib/features/sound_settings/domain/settings_profile_metadata.dart'
    ))
Assert-TestGroups `
    -Scenario 'calibration artifacts and metadata select all focused layers' `
    -Expected @('backend-settings', 'flutter-settings', 'flutter-analyze') `
    -Actual $calibrationGroups
Write-Output 'PASS: calibration artifacts and metadata select all focused layers'

$backendSettingsModules = @(Get-BackendSettingsTestModules)
Assert-TestGroups `
    -Scenario 'backend settings runs every calibration and security module' `
    -Expected @(
        'tests.test_config'
        'tests.test_audio_pipeline'
        'tests.test_genre_profile_derivation'
        'tests.test_genre_profiles'
        'tests.test_settings_recommendation_api'
        'tests.test_settings_recommendation_engine'
        'tests.test_settings_trial_validation'
        'tests.test_control_priors'
        'tests.test_good_audio_thresholds'
        'tests.test_audio_validation'
        'tests.test_admin_data_api'
        'tests.test_security'
    ) `
    -Actual $backendSettingsModules
Write-Output 'PASS: backend settings includes calibration and security modules'

$runnerGroups = @(Get-AffectedTestGroups -ChangedPaths @(
        'tools/run-affected-tests.ps1'
    ))
Assert-TestGroups `
    -Scenario 'runner changes execute the focused backend command they define' `
    -Expected @('backend-settings', 'powershell-tools') `
    -Actual $runnerGroups
Write-Output 'PASS: runner changes execute backend settings and tool tests'

$fallbackGroups = @(Get-AffectedTestGroups -ChangedPaths @(
        'backend/karaok/new_module.py'
        'frontend/lib/features/profile/new_screen.dart'
    ))
Assert-TestGroups `
    -Scenario 'unknown application changes select full layer suites' `
    -Expected @('backend-full', 'flutter-full', 'flutter-analyze') `
    -Actual $fallbackGroups
Write-Output 'PASS: unknown application changes select full layer suites'

$documentationGroups = @(Get-AffectedTestGroups -ChangedPaths @(
        'README.md'
        'docs/notes.md'
    ))
Assert-TestGroups `
    -Scenario 'documentation-only changes require no code tests' `
    -Expected @() `
    -Actual $documentationGroups
Write-Output 'PASS: documentation-only changes require no code tests'

$allGroups = @(Get-AffectedTestGroups `
        -ChangedPaths @() `
        -RunAll `
        -IncludeIntegration)
Assert-TestGroups `
    -Scenario 'full mode includes the historical baseline and integration' `
    -Expected @(
        'backend-full'
        'flutter-full'
        'flutter-analyze'
        'powershell-tools'
        'integration'
    ) `
    -Actual $allGroups
Write-Output 'PASS: full mode includes the historical baseline and integration'

$testRoot = Join-Path $PSScriptRoot ".tmp-affected-runner-$PID"
try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $failedResult = Invoke-CapturedTestGroup `
        -Name 'intentional-failure' `
        -LogDirectory $testRoot `
        -Action {
            Write-Output 'diagnostic marker'
            throw 'expected failure'
        }
    if ($failedResult.Passed) {
        throw 'FAIL: a throwing test group was reported as passing'
    }
    if ($failedResult.Output -notmatch 'diagnostic marker' -or
        $failedResult.Output -notmatch 'expected failure') {
        throw 'FAIL: failed group output did not retain its diagnostics'
    }
    Write-Output 'PASS: failed groups retain diagnostics'

    $passedResult = Invoke-CapturedTestGroup `
        -Name 'intentional-success' `
        -LogDirectory $testRoot `
        -Action { Write-Output 'successful detail that should stay captured' }
    if (-not $passedResult.Passed) {
        throw 'FAIL: a successful test group was reported as failing'
    }
    if ($passedResult.Output -notmatch 'successful detail') {
        throw 'FAIL: successful group output was not captured'
    }
    Write-Output 'PASS: successful groups can be summarized without printing details'

    $powerShellExecutable = (Get-Process -Id $PID).Path
    $closedWarningAction = {
        & $powerShellExecutable -NoProfile -Command `
            "[Console]::Error.WriteLine('closed native warning'); exit 0"
    }.GetNewClosure()
    $closedWarningResult = Invoke-CapturedTestGroup `
        -Name 'successful-closed-native-warning' `
        -LogDirectory $testRoot `
        -Action $closedWarningAction
    if (-not $closedWarningResult.Passed) {
        throw (
            'FAIL: a closed action promoted successful native stderr to failure'
        )
    }
    if ($closedWarningResult.Output -notmatch 'closed native warning') {
        throw 'FAIL: closed-action native stderr was not captured'
    }
    Write-Output 'PASS: closed actions use native exit code despite stderr'

    $closedFailureAction = {
        & $powerShellExecutable -NoProfile -Command `
            "[Console]::Error.WriteLine('closed native failure'); exit 7"
    }.GetNewClosure()
    $closedFailureResult = Invoke-CapturedTestGroup `
        -Name 'failed-closed-native-process' `
        -LogDirectory $testRoot `
        -Action $closedFailureAction
    if ($closedFailureResult.Passed) {
        throw 'FAIL: a nonzero closed native action was reported as passing'
    }
    if ($closedFailureResult.Output -notmatch 'closed native failure') {
        throw 'FAIL: closed native failure diagnostics were not captured'
    }
    Write-Output 'PASS: closed native failures retain stderr diagnostics'

    $warningResult = Invoke-CapturedTestGroup `
        -Name 'successful-native-warning' `
        -LogDirectory $testRoot `
        -Action {
            & $powerShellExecutable -NoProfile -Command `
                "[Console]::Error.WriteLine('native warning'); exit 0"
        }
    if (-not $warningResult.Passed) {
        throw 'FAIL: stderr from a successful native process was treated as failure'
    }
    if ($warningResult.Output -notmatch 'native warning') {
        throw 'FAIL: stderr from the native process was not captured'
    }
    Write-Output 'PASS: native stderr is captured without overriding a zero exit code'

    $warningScript = Join-Path $testRoot 'nested-native-warning.ps1'
    @(
        "`$ErrorActionPreference = 'Stop'"
        "& '$powerShellExecutable' -NoProfile -Command `"[Console]::Error.WriteLine('nested warning'); exit 0`""
        "if (`$LASTEXITCODE -ne 0) { throw 'native child failed' }"
    ) | Set-Content -LiteralPath $warningScript
    $nestedWarningResult = Invoke-CapturedPowerShellScript `
        -Name 'successful-nested-native-warning' `
        -ScriptPath $warningScript `
        -LogDirectory $testRoot
    if (-not $nestedWarningResult.Passed) {
        throw 'FAIL: nested native stderr overrode the successful script exit code'
    }
    if ($nestedWarningResult.Output -notmatch 'nested warning') {
        throw 'FAIL: nested native stderr was not retained in captured output'
    }
    Write-Output 'PASS: nested scripts use their exit code despite native stderr'
}
finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $resolvedTestsDirectory = [IO.Path]::GetFullPath($PSScriptRoot)
    if (-not $resolvedTestRoot.StartsWith(
            $resolvedTestsDirectory + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        throw "Refusing to clean an unexpected test path: $resolvedTestRoot"
    }
    if (Test-Path -LiteralPath $resolvedTestRoot) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
