[CmdletBinding()]
param(
    [Alias('Full')][switch]$All,
    [switch]$Integration,
    [string]$DeviceId = 'windows',
    [switch]$ListOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AffectedTestGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$ChangedPaths,
        [switch]$RunAll,
        [switch]$IncludeIntegration
    )

    if ($RunAll) {
        $allGroups = @(
            'backend-full'
            'flutter-full'
            'flutter-analyze'
            'powershell-tools'
        )
        if ($IncludeIntegration) {
            $allGroups += 'integration'
        }
        return $allGroups
    }

    $backendSettings = $false
    $backendFull = $false
    $flutterSettings = $false
    $flutterFull = $false
    $flutterAnalyze = $false
    $powershellTools = $false

    foreach ($path in $ChangedPaths) {
        $normalized = $path.Replace('\', '/').TrimStart('./')
        if (-not $normalized) {
            continue
        }

        if ($normalized -eq 'database/schema.sql') {
            $backendFull = $true
            continue
        }

        if ($normalized.StartsWith('backend/')) {
            if ($normalized -match '^backend/(audio_thresholds|settings_recommendations)/' -or
                $normalized -match '^backend/karaok/modules/(audio_analysis|settings_recommendations)/' -or
                $normalized -in @(
                    'backend/karaok/application.py'
                    'backend/karaok/config.py'
                ) -or
                $normalized -match '^backend/tests/test_(audio_pipeline|config|genre_|settings_)') {
                $backendSettings = $true
            }
            else {
                $backendFull = $true
            }
            continue
        }

        if ($normalized.StartsWith('frontend/')) {
            if ($normalized -match '^frontend/(lib/features/sound_settings|test/sound_settings)/' -or
                $normalized -match '^frontend/lib/features/assessments/(data/assessment_api|presentation/pages/audio_(settings_suggestion|test)_screen)\.dart$' -or
                $normalized -eq 'frontend/integration_test/settings_generation_flow_test.dart') {
                $flutterSettings = $true
            }
            else {
                $flutterFull = $true
            }
            $flutterAnalyze = $true
            continue
        }

        if ($normalized.StartsWith('tools/')) {
            if ($normalized -eq 'tools/run-affected-tests.ps1') {
                $backendSettings = $true
            }
            $powershellTools = $true
        }
    }

    $groups = @()
    if ($backendFull) {
        $groups += 'backend-full'
    }
    elseif ($backendSettings) {
        $groups += 'backend-settings'
    }
    if ($flutterFull) {
        $groups += 'flutter-full'
    }
    elseif ($flutterSettings) {
        $groups += 'flutter-settings'
    }
    if ($flutterAnalyze) {
        $groups += 'flutter-analyze'
    }
    if ($powershellTools) {
        $groups += 'powershell-tools'
    }
    if ($IncludeIntegration) {
        $groups += 'integration'
    }
    return $groups
}

function Get-BackendSettingsTestModules {
    return @(
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
    )
}

function Invoke-CapturedTestGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$LogDirectory
    )

    $safeName = $Name -replace '[^A-Za-z0-9._-]', '-'
    $logPath = Join-Path $LogDirectory "$safeName.log"
    $passed = $true
    $savedErrorActionPreference = $ErrorActionPreference
    $actionModule = $Action.Module
    $savedActionErrorPreference = $null
    try {
        $ErrorActionPreference = 'Continue'
        if ($null -ne $actionModule) {
            $savedActionErrorPreference = `
                $actionModule.SessionState.PSVariable.GetValue(
                    'ErrorActionPreference'
                )
            $actionModule.SessionState.PSVariable.Set(
                'ErrorActionPreference',
                'Continue'
            )
        }
        $global:LASTEXITCODE = 0
        & $Action *> $logPath
        if ($LASTEXITCODE -ne 0) {
            $passed = $false
        }
    }
    catch {
        $passed = $false
        $_ | Out-String | Out-File -LiteralPath $logPath -Append
    }
    finally {
        if ($null -ne $actionModule) {
            $actionModule.SessionState.PSVariable.Set(
                'ErrorActionPreference',
                $savedActionErrorPreference
            )
        }
        $ErrorActionPreference = $savedErrorActionPreference
    }

    $capturedOutput = if (Test-Path -LiteralPath $logPath -PathType Leaf) {
        Get-Content -LiteralPath $logPath -Raw
    }
    else {
        ''
    }
    return [PSCustomObject]@{
        Name = $Name
        Passed = $passed
        Output = $capturedOutput
    }
}

function Invoke-CapturedPowerShellScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [AllowEmptyCollection()][string[]]$ScriptArguments,
        [Parameter(Mandatory = $true)][string]$LogDirectory
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "PowerShell test script was not found: $ScriptPath"
    }
    $safeName = $Name -replace '[^A-Za-z0-9._-]', '-'
    $standardOutputPath = Join-Path $LogDirectory "$safeName.stdout.log"
    $standardErrorPath = Join-Path $LogDirectory "$safeName.stderr.log"
    $powerShellExecutable = (Get-Process -Id $PID).Path
    $processArguments = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        ('"' + $ScriptPath + '"')
    )
    if ($ScriptArguments) {
        $processArguments += $ScriptArguments
    }

    $passed = $false
    try {
        $process = Start-Process `
            -FilePath $powerShellExecutable `
            -ArgumentList $processArguments `
            -WindowStyle Hidden `
            -RedirectStandardOutput $standardOutputPath `
            -RedirectStandardError $standardErrorPath `
            -Wait `
            -PassThru
        $passed = $process.ExitCode -eq 0
    }
    catch {
        $_ | Out-String | Out-File `
            -LiteralPath $standardErrorPath -Append
    }

    $outputParts = @()
    foreach ($path in @($standardOutputPath, $standardErrorPath)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $outputParts += Get-Content -LiteralPath $path -Raw
        }
    }
    return [PSCustomObject]@{
        Name = $Name
        Passed = $passed
        Output = $outputParts -join [Environment]::NewLine
    }
}

function Get-RepositoryChangedPaths {
    $tracked = @(& git -c core.safecrlf=false diff --name-only HEAD -- 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw 'Git could not determine tracked changes.'
    }
    $untracked = @(& git -c core.safecrlf=false ls-files `
            --others --exclude-standard 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw 'Git could not determine untracked files.'
    }
    return @($tracked + $untracked | Where-Object { $_ } | Sort-Object -Unique)
}

function Invoke-AffectedTestRun {
    [CmdletBinding()]
    param(
        [switch]$RunAll,
        [switch]$IncludeIntegration,
        [Parameter(Mandatory = $true)][string]$TargetDeviceId,
        [switch]$OnlyList
    )

    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $backendRoot = Join-Path $repositoryRoot 'backend'
    $frontendRoot = Join-Path $repositoryRoot 'frontend'
    $changedPaths = @(Get-RepositoryChangedPaths)
    $groups = @(Get-AffectedTestGroups `
            -ChangedPaths $changedPaths `
            -RunAll:$RunAll `
            -IncludeIntegration:$IncludeIntegration)

    if ($groups.Count -eq 0) {
        Write-Output 'No affected test groups were selected.'
        return
    }
    if ($OnlyList) {
        $groups | ForEach-Object { Write-Output $_ }
        return
    }

    $resolverPath = Join-Path $PSScriptRoot 'lib/dev-command-resolution.ps1'
    . $resolverPath
    $backendPython = $null
    $flutterPath = $null
    $logRoot = Join-Path ([IO.Path]::GetTempPath()) `
        "karaok-affected-tests-$([Guid]::NewGuid().ToString('N'))"
    $logRoot = [IO.Path]::GetFullPath(
        (New-Item -ItemType Directory -Path $logRoot).FullName
    )
    $failures = New-Object 'System.Collections.Generic.List[object]'

    try {
        foreach ($group in $groups) {
            if ($group.StartsWith('backend-') -and $null -eq $backendPython) {
                $backendPython = Resolve-BackendPythonPath `
                    -BackendDirectory $backendRoot
            }
            if ($group.StartsWith('flutter-') -and $null -eq $flutterPath) {
                $flutterPath = (Get-Command flutter -ErrorAction Stop).Source
            }

            $action = switch ($group) {
                'backend-settings' {
                    $backendSettingsModules = @(Get-BackendSettingsTestModules)
                    {
                        Push-Location $backendRoot
                        try {
                            & $backendPython -m unittest @backendSettingsModules
                            if ($LASTEXITCODE -ne 0) {
                                throw "Backend settings tests exited with code $LASTEXITCODE."
                            }
                        }
                        finally {
                            Pop-Location
                        }
                    }.GetNewClosure()
                }
                'backend-full' {
                    {
                        Push-Location $backendRoot
                        try {
                            & $backendPython -m unittest discover `
                                -s tests -p 'test_*.py'
                            if ($LASTEXITCODE -ne 0) {
                                throw "Backend tests exited with code $LASTEXITCODE."
                            }
                        }
                        finally {
                            Pop-Location
                        }
                    }.GetNewClosure()
                }
                'flutter-settings' {
                    {
                        Push-Location $frontendRoot
                        try {
                            & $flutterPath test test/sound_settings `
                                --reporter compact
                            if ($LASTEXITCODE -ne 0) {
                                throw "Flutter settings tests exited with code $LASTEXITCODE."
                            }
                        }
                        finally {
                            Pop-Location
                        }
                    }.GetNewClosure()
                }
                'flutter-full' {
                    {
                        Push-Location $frontendRoot
                        try {
                            & $flutterPath test --reporter compact
                            if ($LASTEXITCODE -ne 0) {
                                throw "Flutter tests exited with code $LASTEXITCODE."
                            }
                        }
                        finally {
                            Pop-Location
                        }
                    }.GetNewClosure()
                }
                'flutter-analyze' {
                    {
                        Push-Location $frontendRoot
                        try {
                            & $flutterPath analyze
                            if ($LASTEXITCODE -ne 0) {
                                throw "Flutter analysis exited with code $LASTEXITCODE."
                            }
                        }
                        finally {
                            Pop-Location
                        }
                    }.GetNewClosure()
                }
                'powershell-tools' {
                    $captureScript = ${function:Invoke-CapturedPowerShellScript}
                    {
                        foreach ($testScript in (Get-ChildItem `
                                -LiteralPath (Join-Path $PSScriptRoot 'tests') `
                                -Filter '*.tests.ps1' -File | Sort-Object Name)) {
                            $scriptResult = & $captureScript `
                                -Name $testScript.BaseName `
                                -ScriptPath $testScript.FullName `
                                -LogDirectory $logRoot
                            if (-not $scriptResult.Passed) {
                                throw "PowerShell tests failed: $($testScript.Name)`n$($scriptResult.Output)"
                            }
                        }
                    }.GetNewClosure()
                }
                'integration' {
                    $null
                }
                default {
                    throw "Unknown test group: $group"
                }
            }

            Write-Host "Running $group..." -NoNewline
            if ($group -eq 'integration') {
                $result = Invoke-CapturedPowerShellScript `
                    -Name $group `
                    -ScriptPath (Join-Path $PSScriptRoot `
                        'run-settings-integration.ps1') `
                    -ScriptArguments @('-DeviceId', $TargetDeviceId) `
                    -LogDirectory $logRoot
            }
            else {
                $result = Invoke-CapturedTestGroup `
                    -Name $group `
                    -Action $action `
                    -LogDirectory $logRoot
            }
            if ($result.Passed) {
                Write-Host ' PASS' -ForegroundColor Green
            }
            else {
                Write-Host ' FAIL' -ForegroundColor Red
                $failures.Add($result)
                $result.Output -split "`r?`n" |
                    Select-Object -Last 80 |
                    ForEach-Object { Write-Output $_ }
            }
        }
    }
    finally {
        $resolvedLogRoot = [IO.Path]::GetFullPath($logRoot)
        $resolvedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        $tempPrefix = $resolvedTempRoot
        if (-not $tempPrefix.EndsWith(
                [IO.Path]::DirectorySeparatorChar.ToString()
            )) {
            $tempPrefix += [IO.Path]::DirectorySeparatorChar
        }
        if ($resolvedLogRoot -eq $resolvedTempRoot -or
            -not $resolvedLogRoot.StartsWith(
                $tempPrefix,
                [StringComparison]::OrdinalIgnoreCase
            )) {
            throw "Refusing to remove an unexpected log path: $resolvedLogRoot"
        }
        if (Test-Path -LiteralPath $resolvedLogRoot) {
            Remove-Item -LiteralPath $resolvedLogRoot -Recurse -Force
        }
    }

    if ($failures.Count -gt 0) {
        throw "$($failures.Count) affected test group(s) failed."
    }
    Write-Output "PASS: $($groups.Count) affected test group(s)."
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-AffectedTestRun `
        -RunAll:$All `
        -IncludeIntegration:$Integration `
        -TargetDeviceId $DeviceId `
        -OnlyList:$ListOnly
}
