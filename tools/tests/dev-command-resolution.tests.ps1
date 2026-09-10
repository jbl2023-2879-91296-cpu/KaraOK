$ErrorActionPreference = "Stop"

$resolverPath = Join-Path (Split-Path -Parent $PSScriptRoot) `
    "lib/dev-command-resolution.ps1"
if (-not (Test-Path -LiteralPath $resolverPath)) {
    throw "FAIL: Composer command resolver is missing: $resolverPath"
}

. $resolverPath

$originalPath = $env:Path
try {
    $env:Path = "$env:SystemRoot\System32"
    $expectedPath = (Resolve-Path -LiteralPath $PSCommandPath).Path
    $actualPath = Resolve-ComposerPath `
        -RegisteredPaths @() `
        -FallbackPaths @($expectedPath)

    if ($actualPath -ne $expectedPath) {
        throw "FAIL: expected fallback path '$expectedPath', got '$actualPath'"
    }
}
finally {
    $env:Path = $originalPath
}

Write-Output "PASS: Composer resolves from a fallback when PATH is stale"

$testRoot = Join-Path $PSScriptRoot ".tmp-command-resolution-$PID"
$composerDirectory = Join-Path $testRoot "composer"
$phpDirectory = Join-Path $testRoot "php"
try {
    New-Item -ItemType Directory -Path $composerDirectory, $phpDirectory `
        -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $composerDirectory "composer.bat") `
        -Value "@echo off`r`nphp --fake-composer %*"
    Set-Content -LiteralPath (Join-Path $phpDirectory "php.bat") `
        -Value "@echo off`r`necho Composer reached registered PHP"

    $env:Path = "$env:SystemRoot\System32"
    $actualPath = Resolve-ComposerPath `
        -RegisteredPaths @($phpDirectory, $composerDirectory) `
        -FallbackPaths @()
    $output = & $actualPath --version
    if ($LASTEXITCODE -ne 0 -or $output -ne "Composer reached registered PHP") {
        throw "FAIL: Composer wrapper could not use PHP from the registered PATH"
    }
}
finally {
    $env:Path = $originalPath
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

Write-Output "PASS: Composer and PHP resolve from registered paths"

$expectedMySqlPath = (Resolve-Path -LiteralPath $PSCommandPath).Path
$actualMySqlPath = Resolve-MySqlPath `
    -RegisteredPaths @() `
    -FallbackPaths @($expectedMySqlPath)
if ($actualMySqlPath -ne $expectedMySqlPath) {
    throw "FAIL: expected MySQL fallback '$expectedMySqlPath', got '$actualMySqlPath'"
}
Write-Output "PASS: MySQL resolves from a fallback when PATH is stale"

$expectedAdbPath = (Resolve-Path -LiteralPath $PSCommandPath).Path
$actualAdbPath = Resolve-AdbPath -FallbackPaths @($expectedAdbPath)
if ($actualAdbPath -ne $expectedAdbPath) {
    throw "FAIL: expected ADB fallback '$expectedAdbPath', got '$actualAdbPath'"
}
Write-Output "PASS: ADB resolves from a fallback when PATH is stale"

$deviceIds = @(Get-AuthorizedAndroidDeviceIds -AdbDevicesOutput @(
        "List of devices attached"
        "PHONE-123`tdevice product:test model:Phone device:test transport_id:1"
        "OFFLINE-456`toffline transport_id:2"
        "UNAUTHORIZED-789`tunauthorized transport_id:3"
        ""
    ))
if ($deviceIds.Count -ne 1 -or $deviceIds[0] -ne "PHONE-123") {
    throw "FAIL: expected only the authorized Android device, got '$($deviceIds -join ', ')'"
}
Write-Output "PASS: only authorized Android devices are selected for USB forwarding"

$phoneArguments = @(
    Get-FlutterRunArguments `
        -ApiBaseUrl "http://127.0.0.1:5000/api" `
        -DeviceId "R3CM908XHSK"
)
$expectedPhoneArguments = @(
    "run",
    "-d",
    "R3CM908XHSK",
    "--dart-define=API_BASE_URL=http://127.0.0.1:5000/api"
)
if (($phoneArguments -join "`n") -cne ($expectedPhoneArguments -join "`n")) {
    throw "FAIL: phone launch arguments were '$($phoneArguments -join ' ')'."
}

$defaultArguments = @(
    Get-FlutterRunArguments -ApiBaseUrl "http://127.0.0.1:5000/api"
)
$expectedDefaultArguments = @(
    "run",
    "--dart-define=API_BASE_URL=http://127.0.0.1:5000/api"
)
if (($defaultArguments -join "`n") -cne ($expectedDefaultArguments -join "`n")) {
    throw "FAIL: default launch arguments were '$($defaultArguments -join ' ')'."
}

$chromeLaunchPlan = Get-DevelopmentLaunchPlan `
    -ApiBaseUrl "http://127.0.0.1:5000/api" `
    -DeviceId "chrome" `
    -AdbDevicesOutput @(
        "List of devices attached",
        "R3CM908XHSK device product:beyond2lte model:SM_G977N transport_id:1"
    )
$expectedChromeArguments = @(
    "run",
    "-d",
    "chrome",
    "--dart-define=API_BASE_URL=http://127.0.0.1:5000/api"
)
if (($chromeLaunchPlan.FlutterRunArguments -join "`n") -cne `
        ($expectedChromeArguments -join "`n")) {
    throw "FAIL: Android discovery replaced the requested Chrome target."
}
if (($chromeLaunchPlan.AndroidDeviceIds -join "`n") -cne "R3CM908XHSK") {
    throw "FAIL: the connected Android device was not retained for API forwarding."
}
Write-Output "PASS: Android forwarding does not replace the requested Flutter target"

$runDevPath = Join-Path (Split-Path -Parent $PSScriptRoot) "run-dev.ps1"
$runDevContent = Get-Content -LiteralPath $runDevPath -Raw
if ($runDevContent -notmatch 'Get-DevelopmentLaunchPlan') {
    throw "FAIL: run-dev.ps1 does not use the tested development launch plan."
}
Write-Output "PASS: run-dev can target one connected phone without changing default behavior"
