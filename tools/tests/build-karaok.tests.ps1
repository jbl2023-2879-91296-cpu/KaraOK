$ErrorActionPreference = 'Stop'

$toolsDirectory = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $toolsDirectory
$buildScript = Join-Path $toolsDirectory 'build_karaok.ps1'
$gradlePath = Join-Path $repositoryRoot 'frontend/android/app/build.gradle.kts'

if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
    throw "FAIL: KaraOK build tool is missing: $buildScript"
}

$validationOutput = @(
    & $buildScript `
        -ProjectDirectory (Join-Path $repositoryRoot 'frontend') `
        -NonInteractive `
        -ValidateProjectOnly
)
if ($LASTEXITCODE -ne 0) {
    throw 'FAIL: project validation returned a non-zero exit code.'
}
if (($validationOutput -join "`n") -notmatch 'KaraOK Flutter project') {
    throw 'FAIL: project validation did not identify the KaraOK application.'
}
Write-Output 'PASS: build tool locates and validates the KaraOK Flutter project'

$planOutput = @(
    & $buildScript `
        -ProjectDirectory (Join-Path $repositoryRoot 'frontend') `
        -NonInteractive `
        -Mode debug `
        -Format apk `
        -ApiBaseUrl 'http://127.0.0.1:5000/api' `
        -PlanOnly
)
if ($LASTEXITCODE -ne 0) {
    throw 'FAIL: debug build planning returned a non-zero exit code.'
}
$planText = $planOutput -join "`n"
foreach ($expected in @('KaraOK', 'debug', 'apk', 'http://127.0.0.1:5000/api')) {
    if ($planText -notmatch [regex]::Escape($expected)) {
        throw "FAIL: build plan omitted '$expected'."
    }
}
Write-Output 'PASS: debug build plan contains the expected KaraOK configuration'

$defaultDebugPlan = @(
    & $buildScript `
        -ProjectDirectory (Join-Path $repositoryRoot 'frontend') `
        -NonInteractive `
        -Mode debug `
        -PlanOnly
)
if ($LASTEXITCODE -ne 0 -or
    ($defaultDebugPlan -join "`n") -notmatch 'http://127\.0\.0\.1:5000/api') {
    throw 'FAIL: a non-interactive debug plan did not select the local API default.'
}
Write-Output 'PASS: non-interactive debug builds use the documented local API default'

$gradle = Get-Content -Raw -LiteralPath $gradlePath
if ($gradle -match 'release\s*\{[\s\S]*?signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)') {
    throw 'FAIL: Android release builds still use the debug signing key.'
}
foreach ($expected in @(
        'KARAOK_KEYSTORE_PATH',
        'KARAOK_KEY_ALIAS',
        'KARAOK_STORE_PASSWORD',
        'KARAOK_KEY_PASSWORD',
        'key.properties'
    )) {
    if ($gradle -notmatch [regex]::Escape($expected)) {
        throw "FAIL: Android signing configuration omitted '$expected'."
    }
}
Write-Output 'PASS: Android release signing accepts private properties or environment variables'

$testRoot = Join-Path $PSScriptRoot ".tmp-build-karaok-$PID"
$resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
$resolvedTestsDirectory = [IO.Path]::GetFullPath($PSScriptRoot)
if (-not $resolvedTestRoot.StartsWith(
        $resolvedTestsDirectory + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )) {
    throw "Refusing to use an unexpected test path: $resolvedTestRoot"
}

try {
    $testProject = Join-Path $resolvedTestRoot 'frontend'
    $testAndroid = Join-Path $testProject 'android'
    New-Item -ItemType Directory -Path (
        Join-Path $testAndroid 'app/src/main'
    ) -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $testProject 'pubspec.yaml') -Value @(
        'name: karaok_app',
        'version: 1.0.0+1'
    )
    Set-Content -LiteralPath (Join-Path $testAndroid 'app/build.gradle.kts') -Value @(
        'android {',
        '    defaultConfig { applicationId = "com.jrpbone.karaok" }',
        '}'
    )
    Set-Content -LiteralPath (Join-Path $testAndroid 'app/src/main/AndroidManifest.xml') -Value '<manifest />'

    $testKeystore = Join-Path $testAndroid 'keystore/disposable-test.jks'
    $testPassword = ConvertTo-SecureString 'Disposable1!' -AsPlainText -Force
    & $buildScript `
        -ProjectDirectory $testProject `
        -NonInteractive `
        -SetupSigningOnly `
        -KeystorePath $testKeystore `
        -KeyAlias 'disposable-test' `
        -StorePassword $testPassword `
        -KeyPassword $testPassword
    if ($LASTEXITCODE -ne 0) {
        throw 'FAIL: guided release-signing setup returned a non-zero exit code.'
    }

    $testProperties = Join-Path $testAndroid 'key.properties'
    if (-not (Test-Path -LiteralPath $testKeystore -PathType Leaf) -or
        -not (Test-Path -LiteralPath $testProperties -PathType Leaf)) {
        throw 'FAIL: guided signing setup did not create both required private files.'
    }
    Write-Output 'PASS: guided signing setup creates a private keystore and ignored properties file'
}
finally {
    if (Test-Path -LiteralPath $resolvedTestRoot) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
