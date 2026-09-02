$ErrorActionPreference = "Stop"

$resolverPath = Join-Path (Split-Path -Parent $PSScriptRoot) `
    "dev-command-resolution.ps1"
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
