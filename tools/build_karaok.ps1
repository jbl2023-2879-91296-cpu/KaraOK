<#
.SYNOPSIS
Builds a tested, versioned, and signed KaraOK Android artifact.

.DESCRIPTION
Builds an APK or Android App Bundle from the repository's frontend project.
Release builds require a private signing key and never fall back to the debug
key. Signing can come from frontend/android/key.properties, the KARAOK signing
environment variables, or secure parameters supplied to this command.

.EXAMPLE
.\tools\build_karaok.ps1 -SetupSigningOnly

.EXAMPLE
.\tools\build_karaok.ps1 -Format aab -NonInteractive

.EXAMPLE
.\tools\build_karaok.ps1 -Mode debug -ApiBaseUrl http://127.0.0.1:5000/api
#>
[CmdletBinding()]
param(
    [Parameter()] [string]$ApplicationName = 'KaraOK',
    [Parameter()] [Alias('PackageId')] [string]$ApplicationId,
    [Parameter()] [ValidateSet('apk', 'aab')] [string]$Format = 'apk',
    [Parameter()] [ValidateSet('debug', 'profile', 'release')] [string]$Mode = 'release',
    [Parameter()] [Alias('AppBaseUrl')] [string]$ApiBaseUrl,
    [Parameter()] [string]$VersionName,
    [Parameter()] [int]$BuildNumber,
    [Parameter()] [string]$OutputDirectory = 'dist',
    [Parameter()] [string]$Target = 'lib/main.dart',
    [Parameter()] [string[]]$DartDefine,
    [Parameter()] [switch]$Clean,
    [Parameter()] [switch]$SkipPubGet,
    [Parameter()] [switch]$SkipChecks,
    [Parameter()] [switch]$Obfuscate,
    [Parameter()] [switch]$SplitPerAbi,
    [Parameter()] [switch]$OpenOutputDirectory,
    [Parameter()] [switch]$NonInteractive,
    [Parameter()] [string]$ProjectDirectory,
    [Parameter()] [switch]$ValidateProjectOnly,
    [Parameter()] [switch]$PlanOnly,
    [Parameter()] [switch]$SetupSigning,
    [Parameter()] [switch]$SetupSigningOnly,
    [Parameter()] [string]$KeystorePath,
    [Parameter()] [string]$KeyAlias = 'karaok-release',
    [Parameter()] [Security.SecureString]$StorePassword,
    [Parameter()] [Security.SecureString]$KeyPassword,
    [Parameter()] [string]$DistinguishedName = 'CN=KaraOK, OU=Mobile, O=KaraOK, L=Manila, ST=Metro Manila, C=PH',
    [Parameter()] [ValidateRange(365, 36500)] [int]$KeyValidityDays = 10000
)

$ErrorActionPreference = 'Stop'
$previousDirectory = (Get-Location).Path
$temporaryPlainSecrets = @()
$signingEnvironmentNames = @(
    'KARAOK_APPLICATION_NAME',
    'KARAOK_APPLICATION_ID',
    'KARAOK_KEYSTORE_PATH',
    'KARAOK_KEY_ALIAS',
    'KARAOK_STORE_PASSWORD',
    'KARAOK_KEY_PASSWORD'
)
$originalSigningEnvironment = @{}
foreach ($name in $signingEnvironmentNames) {
    $originalSigningEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

function Test-KaraOkProjectRoot {
    param([Parameter(Mandatory)] [string]$Candidate)

    if (-not (Test-Path -LiteralPath $Candidate -PathType Container)) { return $false }
    $pubspecPath = Join-Path $Candidate 'pubspec.yaml'
    $gradlePath = Join-Path $Candidate 'android/app/build.gradle.kts'
    $manifestPath = Join-Path $Candidate 'android/app/src/main/AndroidManifest.xml'
    if (-not (
            (Test-Path -LiteralPath $pubspecPath -PathType Leaf) -and
            (Test-Path -LiteralPath $gradlePath -PathType Leaf) -and
            (Test-Path -LiteralPath $manifestPath -PathType Leaf)
        )) {
        return $false
    }

    return (Get-Content -Raw -LiteralPath $pubspecPath) -match '(?m)^name:\s*karaok_app\s*$'
}

function Find-KaraOkProjectRoot {
    param([Parameter(Mandatory)] [string]$StartPath)

    if (-not (Test-Path -LiteralPath $StartPath)) { return $null }
    $item = Get-Item -LiteralPath $StartPath
    if (-not $item.PSIsContainer) { $item = $item.Directory }
    while ($null -ne $item) {
        if (Test-KaraOkProjectRoot -Candidate $item.FullName) { return $item.FullName }
        $frontendCandidate = Join-Path $item.FullName 'frontend'
        if (Test-KaraOkProjectRoot -Candidate $frontendCandidate) { return $frontendCandidate }
        $item = $item.Parent
    }
    return $null
}

function Read-DefaultValue {
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$DefaultValue
    )

    $suffix = if ([string]::IsNullOrWhiteSpace($DefaultValue)) { '' } else { " [$DefaultValue]" }
    $answer = Read-Host "$Prompt$suffix"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultValue }
    return $answer.Trim()
}

function Read-YesNo {
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [Parameter(Mandatory)] [bool]$DefaultValue
    )

    $defaultText = if ($DefaultValue) { 'Y' } else { 'N' }
    while ($true) {
        $answer = Read-Host "$Prompt [Y/N, default: $defaultText]"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultValue }
        if ($answer -match '^(y|yes)$') { return $true }
        if ($answer -match '^(n|no)$') { return $false }
        Write-Host 'Enter Y or N.' -ForegroundColor Yellow
    }
}

function ConvertFrom-SecureValue {
    param([Parameter(Mandatory)] [Security.SecureString]$Value)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Find-KeyTool {
    $command = Get-Command keytool -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        $candidates += Join-Path $env:JAVA_HOME 'bin/keytool.exe'
    }
    $candidates += @(
        'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe',
        'C:\Program Files\Android\Android Studio\jre\bin\keytool.exe'
    )
    $javaDirectories = @(Get-ChildItem 'C:\Program Files\Java' -Directory -ErrorAction SilentlyContinue)
    foreach ($directory in $javaDirectories) {
        $candidates += Join-Path $directory.FullName 'bin/keytool.exe'
    }
    return $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

function Find-ApkSigner {
    $command = Get-Command apksigner -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $sdkRoots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, (Join-Path $env:LOCALAPPDATA 'Android\Sdk')) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Container) } |
        Select-Object -Unique
    foreach ($sdkRoot in $sdkRoots) {
        $buildTools = Join-Path $sdkRoot 'build-tools'
        if (-not (Test-Path -LiteralPath $buildTools -PathType Container)) { continue }
        $candidate = Get-ChildItem -LiteralPath $buildTools -Directory |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Select-Object -First 1
        if ($candidate) { return $candidate }
    }
    return $null
}

function Find-JarSigner {
    $command = Get-Command jarsigner -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        $candidates += Join-Path $env:JAVA_HOME 'bin/jarsigner.exe'
    }
    $candidates += 'C:\Program Files\Android\Android Studio\jbr\bin\jarsigner.exe'
    $javaDirectories = @(Get-ChildItem 'C:\Program Files\Java' -Directory -ErrorAction SilentlyContinue)
    foreach ($directory in $javaDirectories) {
        $candidates += Join-Path $directory.FullName 'bin/jarsigner.exe'
    }
    return $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

function Read-KeyProperties {
    param([Parameter(Mandatory)] [string]$Path)

    $values = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $values }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*(storeFile|storePassword|keyPassword|keyAlias)\s*=\s*(.*)\s*$') {
            $propertyName = $Matches[1]
            $propertyValue = $Matches[2]
            $values[$propertyName] = [regex]::Replace(
                $propertyValue, '\\(u[0-9a-fA-F]{4}|.)', {
                    param($escape)
                    $value = $escape.Groups[1].Value
                    switch -CaseSensitive ($value) {
                        't' { return "`t" }
                        'r' { return "`r" }
                        'n' { return "`n" }
                        'f' { return "`f" }
                        default {
                            if ($value -cmatch '^u[0-9a-fA-F]{4}$') {
                                return [string][char][Convert]::ToInt32($value.Substring(1), 16)
                            }
                            return $value
                        }
                    }
                }
            )
        }
    }
    return $values
}

function ConvertTo-JavaPropertyValue {
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Value)

    $escaped = $Value.Replace('\', '\\')
    $escaped = $escaped.Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
    return [regex]::Replace($escaped, '([ :=#!])', '\$1')
}

function Test-SigningConfiguration {
    param(
        [Parameter(Mandatory)] [string]$AndroidDirectory,
        [Parameter(Mandatory)] [string]$PropertiesPath
    )

    $properties = Read-KeyProperties -Path $PropertiesPath
    $valueSources = [ordered]@{
        storeFile = 'KARAOK_KEYSTORE_PATH'
        storePassword = 'KARAOK_STORE_PASSWORD'
        keyPassword = 'KARAOK_KEY_PASSWORD'
        keyAlias = 'KARAOK_KEY_ALIAS'
    }
    $effectiveValues = @{}
    foreach ($key in $valueSources.Keys) {
        $environmentValue = [Environment]::GetEnvironmentVariable($valueSources[$key], 'Process')
        $effectiveValues[$key] = if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
            $environmentValue
        }
        elseif ($properties.ContainsKey($key)) {
            $properties[$key]
        }
        else {
            $null
        }
        if ([string]::IsNullOrWhiteSpace($effectiveValues[$key])) {
            return $false
        }
    }
    $configuredStoreFile = $effectiveValues['storeFile']
    $resolvedStoreFile = if ([IO.Path]::IsPathRooted($configuredStoreFile)) {
        $configuredStoreFile
    }
    else {
        Join-Path (Join-Path $AndroidDirectory 'app') $configuredStoreFile
    }
    return Test-Path -LiteralPath $resolvedStoreFile -PathType Leaf
}

function Set-ProcessSigningEnvironment {
    param(
        [Parameter(Mandatory)] [string]$StorePath,
        [Parameter(Mandatory)] [string]$Alias,
        [Parameter(Mandatory)] [Security.SecureString]$StoreSecret,
        [Parameter(Mandatory)] [Security.SecureString]$KeySecret
    )

    $plainStorePassword = ConvertFrom-SecureValue -Value $StoreSecret
    $plainKeyPassword = ConvertFrom-SecureValue -Value $KeySecret
    $script:temporaryPlainSecrets = @($plainStorePassword, $plainKeyPassword)
    [Environment]::SetEnvironmentVariable('KARAOK_KEYSTORE_PATH', [IO.Path]::GetFullPath($StorePath), 'Process')
    [Environment]::SetEnvironmentVariable('KARAOK_KEY_ALIAS', $Alias, 'Process')
    [Environment]::SetEnvironmentVariable('KARAOK_STORE_PASSWORD', $plainStorePassword, 'Process')
    [Environment]::SetEnvironmentVariable('KARAOK_KEY_PASSWORD', $plainKeyPassword, 'Process')
}

function New-KaraOkSigningKey {
    param(
        [Parameter(Mandatory)] [string]$AndroidDirectory,
        [Parameter(Mandatory)] [string]$PropertiesPath
    )

    $keyTool = Find-KeyTool
    if (-not $keyTool) { throw 'Java keytool was not found. Install a JDK or Android Studio first.' }
    if ([string]::IsNullOrWhiteSpace($script:KeystorePath)) {
        $script:KeystorePath = Join-Path $AndroidDirectory 'keystore/karaok-release.jks'
    }
    $script:KeystorePath = [IO.Path]::GetFullPath($script:KeystorePath)
    if (Test-Path -LiteralPath $script:KeystorePath) {
        throw "Refusing to overwrite the existing keystore: $script:KeystorePath"
    }
    if ([string]::IsNullOrWhiteSpace($script:KeyAlias)) { throw 'The signing key alias cannot be empty.' }

    if ($null -eq $script:StorePassword) {
        if ($script:NonInteractive) { throw 'StorePassword is required for non-interactive signing setup.' }
        $script:StorePassword = Read-Host 'New keystore password (keep this safe)' -AsSecureString
    }
    if ($null -eq $script:KeyPassword) {
        if ($script:NonInteractive) { throw 'KeyPassword is required for non-interactive signing setup.' }
        Write-Host 'Enter a password for the signing key (it may match the keystore password).' -ForegroundColor DarkGray
        $script:KeyPassword = Read-Host 'New signing-key password' -AsSecureString
    }

    Set-ProcessSigningEnvironment `
        -StorePath $script:KeystorePath `
        -Alias $script:KeyAlias `
        -StoreSecret $script:StorePassword `
        -KeySecret $script:KeyPassword
    if ($script:temporaryPlainSecrets[0].Length -lt 8 -or $script:temporaryPlainSecrets[1].Length -lt 8) {
        throw 'Signing passwords must contain at least 8 characters.'
    }

    $keystoreDirectory = Split-Path -Parent $script:KeystorePath
    New-Item -ItemType Directory -Path $keystoreDirectory -Force | Out-Null
    $keyToolArguments = @(
        '-genkeypair',
        '-v',
        '-keystore', $script:KeystorePath,
        '-storetype', 'JKS',
        '-keyalg', 'RSA',
        '-keysize', '2048',
        '-validity', $script:KeyValidityDays.ToString(),
        '-alias', $script:KeyAlias,
        '-dname', $script:DistinguishedName,
        '-storepass:env', 'KARAOK_STORE_PASSWORD',
        '-keypass:env', 'KARAOK_KEY_PASSWORD'
    )
    Write-Host "Creating private release keystore: $script:KeystorePath" -ForegroundColor Cyan
    & $keyTool @keyToolArguments
    if ($LASTEXITCODE -ne 0) { throw "keytool failed with exit code $LASTEXITCODE." }

    $propertiesContent = @(
        "storeFile=$(ConvertTo-JavaPropertyValue -Value $script:KeystorePath.Replace('\', '/'))",
        "storePassword=$(ConvertTo-JavaPropertyValue -Value $script:temporaryPlainSecrets[0])",
        "keyPassword=$(ConvertTo-JavaPropertyValue -Value $script:temporaryPlainSecrets[1])",
        "keyAlias=$(ConvertTo-JavaPropertyValue -Value $script:KeyAlias)",
        ''
    ) -join "`n"
    [IO.File]::WriteAllText($PropertiesPath, $propertiesContent, [Text.UTF8Encoding]::new($false))
    Write-Host "Signing configuration created: $PropertiesPath" -ForegroundColor Green
    Write-Warning 'Back up the .jks file and its passwords securely. Losing the signing key can prevent future app updates.'
}

function Invoke-FlutterStep {
    param(
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [string[]]$Arguments
    )

    Write-Host "`n$Title" -ForegroundColor Cyan
    Write-Host "> flutter $($Arguments -join ' ')" -ForegroundColor DarkGray
    & flutter @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Title failed with exit code $LASTEXITCODE." }
}

try {
    if ([string]::IsNullOrWhiteSpace($ProjectDirectory)) {
        foreach ($startPath in @($PSScriptRoot, (Get-Location).Path)) {
            $ProjectDirectory = Find-KaraOkProjectRoot -StartPath $startPath
            if ($ProjectDirectory) { break }
        }
    }
    else {
        $ProjectDirectory = [IO.Path]::GetFullPath($ProjectDirectory)
    }
    if (-not $ProjectDirectory -or -not (Test-KaraOkProjectRoot -Candidate $ProjectDirectory)) {
        throw 'Could not locate the KaraOK Flutter project (frontend/pubspec.yaml).'
    }

    $pubspecPath = Join-Path $ProjectDirectory 'pubspec.yaml'
    $targetPath = Join-Path $ProjectDirectory $Target
    $androidDirectory = Join-Path $ProjectDirectory 'android'
    $appGradlePath = Join-Path $androidDirectory 'app/build.gradle.kts'
    $keyPropertiesPath = Join-Path $androidDirectory 'key.properties'
    if ($ValidateProjectOnly) {
        Write-Output "KaraOK Flutter project: $ProjectDirectory"
        Write-Output "Android project: $androidDirectory"
        exit 0
    }

    if ($SetupSigningOnly) { $SetupSigning = $true }
    $explicitSigningParameters = @($KeystorePath, $StorePassword, $KeyPassword) |
        Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace($_.ToString()) }
    if ($explicitSigningParameters.Count -gt 0) {
        if ([string]::IsNullOrWhiteSpace($KeystorePath) -or $null -eq $StorePassword -or $null -eq $KeyPassword) {
            throw 'KeystorePath, StorePassword, and KeyPassword must be supplied together.'
        }
        if (-not (Test-Path -LiteralPath $KeystorePath -PathType Leaf) -and -not $SetupSigning) {
            throw "KeystorePath does not exist: $KeystorePath"
        }
        if (Test-Path -LiteralPath $KeystorePath -PathType Leaf) {
            Set-ProcessSigningEnvironment -StorePath $KeystorePath -Alias $KeyAlias -StoreSecret $StorePassword -KeySecret $KeyPassword
        }
    }

    $signingReady = Test-SigningConfiguration -AndroidDirectory $androidDirectory -PropertiesPath $keyPropertiesPath
    if ($SetupSigning) {
        if ($signingReady) {
            Write-Host 'Release signing is already configured; the existing key was not changed.' -ForegroundColor Green
        }
        else {
            New-KaraOkSigningKey -AndroidDirectory $androidDirectory -PropertiesPath $keyPropertiesPath
            $signingReady = Test-SigningConfiguration -AndroidDirectory $androidDirectory -PropertiesPath $keyPropertiesPath
        }
    }
    if ($SetupSigningOnly) {
        if (-not $signingReady) { throw 'Release signing setup did not produce a valid configuration.' }
        exit 0
    }

    $pubspec = Get-Content -Raw -LiteralPath $pubspecPath
    $versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$')
    if (-not $versionMatch.Success) { throw 'Could not read version: MAJOR.MINOR.PATCH+BUILD from pubspec.yaml.' }
    $appGradle = Get-Content -Raw -LiteralPath $appGradlePath
    $applicationIdMatch = [regex]::Match($appGradle, 'applicationId\s*=\s*"([^"]+)"')
    if (-not $applicationIdMatch.Success) { throw 'Could not read the Android application ID.' }
    if ([string]::IsNullOrWhiteSpace($ApplicationId)) { $ApplicationId = $applicationIdMatch.Groups[1].Value }
    if ([string]::IsNullOrWhiteSpace($VersionName)) { $VersionName = $versionMatch.Groups[1].Value }
    if (-not $PSBoundParameters.ContainsKey('BuildNumber')) { $BuildNumber = [int]$versionMatch.Groups[2].Value }

    . (Join-Path $PSScriptRoot 'lib/build-options.ps1')
    $options = Resolve-KaraOkBuildOptions -ApplicationName $ApplicationName -ApplicationId $ApplicationId `
        -VersionName $VersionName -BuildNumber $BuildNumber -Format $Format -Mode $Mode `
        -Interactive:(-not $NonInteractive -and -not $PlanOnly)
    $ApplicationName = $options.ApplicationName
    $ApplicationId = $options.ApplicationId
    $VersionName = $options.VersionName
    $BuildNumber = $options.BuildNumber
    $Format = $options.Format
    $Mode = $options.Mode

    . (Join-Path $PSScriptRoot 'lib/build-api-config.ps1')
    $apiConfiguration = Resolve-KaraOkBuildApi -Mode $Mode -ExplicitUrl $ApiBaseUrl `
        -EnvironmentUrl $env:KARAOK_API_BASE_URL -AdditionalDefines $DartDefine
    $ApiBaseUrl = $apiConfiguration.Url
    if ($VersionName -notmatch '^\d+\.\d+\.\d+$') { throw 'VersionName must use MAJOR.MINOR.PATCH.' }
    if ($BuildNumber -le 0) { throw 'BuildNumber must be greater than zero.' }
    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) { throw "Flutter target was not found: $Target" }
    if ($Obfuscate -and $Mode -ne 'release') { throw 'Obfuscation requires release mode.' }
    if ($Format -eq 'aab') { $SplitPerAbi = $false }
    if ($Mode -eq 'release' -and -not $signingReady -and -not $PlanOnly) {
        if (-not $NonInteractive -and (Read-YesNo -Prompt 'Release signing is missing. Create a private signing key now?' -DefaultValue $true)) {
            New-KaraOkSigningKey -AndroidDirectory $androidDirectory -PropertiesPath $keyPropertiesPath
            $signingReady = Test-SigningConfiguration -AndroidDirectory $androidDirectory -PropertiesPath $keyPropertiesPath
        }
        if (-not $signingReady) {
            throw 'Release signing is required. Run this tool with -SetupSigning or provide all four KARAOK signing environment variables.'
        }
    }

    $shouldClean = $Clean.IsPresent
    $shouldGetPackages = -not $SkipPubGet.IsPresent
    $shouldRunChecks = -not $SkipChecks.IsPresent
    $shouldObfuscate = $Obfuscate.IsPresent
    $shouldSplitPerAbi = $Format -eq 'apk' -and $SplitPerAbi.IsPresent
    $shouldOpenOutput = $OpenOutputDirectory.IsPresent
    if (-not $NonInteractive -and -not $PlanOnly) {
        $shouldClean = Read-YesNo -Prompt 'Run flutter clean first?' -DefaultValue $shouldClean
        $shouldGetPackages = Read-YesNo -Prompt 'Restore Flutter packages?' -DefaultValue $shouldGetPackages
        $shouldRunChecks = Read-YesNo -Prompt 'Run flutter analyze and flutter test?' -DefaultValue $shouldRunChecks
        if ($Mode -eq 'release') {
            $shouldObfuscate = Read-YesNo -Prompt 'Obfuscate Dart code and save debug symbols?' -DefaultValue $shouldObfuscate
        }
        if ($Format -eq 'apk') {
            $shouldSplitPerAbi = Read-YesNo -Prompt 'Create separate APKs per CPU architecture?' -DefaultValue $shouldSplitPerAbi
        }
        $shouldOpenOutput = Read-YesNo -Prompt 'Open the artifact directory after building?' -DefaultValue $shouldOpenOutput
    }

    Write-Output ''
    Write-Output 'KaraOK Android build plan'
    Write-Output '----------------------------------------'
    Write-Output "Project:         $ProjectDirectory"
    Write-Output "Application:     $ApplicationName"
    Write-Output "Package ID:      $ApplicationId"
    Write-Output "Format:          $Format"
    Write-Output "Mode:            $Mode"
    Write-Output "Version:         $VersionName+$BuildNumber"
    Write-Output "API base URL:    $ApiBaseUrl"
    Write-Output "URL source:      $($apiConfiguration.Source)"
    Write-Output "Flutter define:  $($apiConfiguration.DartDefine)"
    Write-Output "Release signing: $signingReady"
    Write-Output "Output:          $OutputDirectory"
    if ($PlanOnly) { exit 0 }
    if (-not $NonInteractive -and -not (Read-YesNo -Prompt 'Proceed with this build?' -DefaultValue $true)) {
        Write-Host 'Build cancelled.' -ForegroundColor Yellow
        exit 0
    }
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'Flutter was not found on PATH.' }

    Set-Location -LiteralPath $ProjectDirectory
    if ($shouldClean) { Invoke-FlutterStep -Title 'Cleaning build outputs...' -Arguments @('clean') }
    if ($shouldGetPackages) { Invoke-FlutterStep -Title 'Restoring Flutter packages...' -Arguments @('pub', 'get') }
    if ($shouldRunChecks) {
        Invoke-FlutterStep -Title 'Running static analysis...' -Arguments @('analyze', '--no-pub')
        Invoke-FlutterStep -Title 'Running automated tests...' -Arguments @('test', '--no-pub')
    }

    $flutterFormat = if ($Format -eq 'aab') { 'appbundle' } else { 'apk' }
    $arguments = @(
        'build', $flutterFormat, "--$Mode",
        '--target', $Target,
        '--build-name', $VersionName,
        '--build-number', $BuildNumber.ToString(),
        $apiConfiguration.DartDefine
    )
    foreach ($definition in $DartDefine) {
        if ([string]::IsNullOrWhiteSpace($definition)) { continue }
        if ($definition -match '^API_BASE_URL=') { throw 'Use -ApiBaseUrl instead of passing API_BASE_URL through -DartDefine.' }
        $arguments += "--dart-define=$definition"
    }
    if ($shouldSplitPerAbi) { $arguments += '--split-per-abi' }
    if ($shouldObfuscate) {
        $symbolDirectory = Join-Path $ProjectDirectory "build/symbols/$VersionName+$BuildNumber/android"
        New-Item -ItemType Directory -Path $symbolDirectory -Force | Out-Null
        $arguments += @('--obfuscate', "--split-debug-info=$symbolDirectory")
    }
    [Environment]::SetEnvironmentVariable('KARAOK_APPLICATION_NAME', $ApplicationName, 'Process')
    [Environment]::SetEnvironmentVariable('KARAOK_APPLICATION_ID', $ApplicationId, 'Process')
    Invoke-FlutterStep -Title "Building $ApplicationName Android artifact..." -Arguments $arguments

    if ($Format -eq 'aab') {
        $artifacts = @(Join-Path $ProjectDirectory "build/app/outputs/bundle/$Mode/app-$Mode.aab")
    }
    elseif ($shouldSplitPerAbi) {
        $apkDirectory = Join-Path $ProjectDirectory 'build/app/outputs/flutter-apk'
        $artifacts = @(
            (Join-Path $apkDirectory "app-armeabi-v7a-$Mode.apk"),
            (Join-Path $apkDirectory "app-arm64-v8a-$Mode.apk"),
            (Join-Path $apkDirectory "app-x86_64-$Mode.apk")
        )
    }
    else {
        $artifacts = @(Join-Path $ProjectDirectory "build/app/outputs/flutter-apk/app-$Mode.apk")
    }

    $repositoryRoot = Split-Path -Parent $ProjectDirectory
    $outputRoot = if ([IO.Path]::IsPathRooted($OutputDirectory)) {
        [IO.Path]::GetFullPath($OutputDirectory)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $repositoryRoot $OutputDirectory))
    }
    $releaseDirectory = Join-Path $outputRoot "$ApplicationName-v$VersionName+$BuildNumber-$Mode-android"
    if (Test-Path -LiteralPath $releaseDirectory) {
        $releaseDirectory += "-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    }
    New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null

    $records = @()
    foreach ($artifact in $artifacts) {
        if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) { throw "Expected artifact was not found: $artifact" }
        $extension = [IO.Path]::GetExtension($artifact)
        $architecture = if ($artifact -match 'app-(armeabi-v7a|arm64-v8a|x86_64)-') { "-$($Matches[1])" } else { '' }
        $fileName = "$ApplicationName-v$VersionName+$BuildNumber-$Mode$architecture$extension"
        $destination = Join-Path $releaseDirectory $fileName
        Copy-Item -LiteralPath $artifact -Destination $destination

        $signatureVerified = $false
        if ($Mode -eq 'release') {
            if ($Format -eq 'apk') {
                $verifier = Find-ApkSigner
                if (-not $verifier) { throw 'Android apksigner was not found, so the release signature could not be verified.' }
                & $verifier verify --verbose $destination
            }
            else {
                $verifier = Find-JarSigner
                if (-not $verifier) { throw 'Java jarsigner was not found, so the bundle signature could not be verified.' }
                & $verifier -verify $destination
            }
            if ($LASTEXITCODE -ne 0) { throw "Signature verification failed for $fileName." }
            $signatureVerified = $true
        }

        $records += [ordered]@{
            file = $fileName
            bytes = (Get-Item -LiteralPath $destination).Length
            sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
            signatureVerified = $signatureVerified
        }
    }

    [ordered]@{
        applicationName = $ApplicationName
        applicationId = $applicationId
        versionName = $VersionName
        buildNumber = $BuildNumber
        format = $Format
        mode = $Mode
        apiBaseUrl = $ApiBaseUrl
        apiBaseUrlSource = $apiConfiguration.Source
        releaseSigned = $Mode -eq 'release'
        obfuscated = $shouldObfuscate
        splitPerAbi = $shouldSplitPerAbi
        builtAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        artifacts = $records
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $releaseDirectory 'build-manifest.json') -Encoding utf8

    Write-Host "`nBuild completed successfully." -ForegroundColor Green
    Write-Host "Artifacts: $releaseDirectory"
    foreach ($record in $records) {
        Write-Host "  $($record.file)"
        Write-Host "    SHA256: $($record.sha256)" -ForegroundColor DarkGray
        if ($record.signatureVerified) { Write-Host '    Release signature: verified' -ForegroundColor DarkGray }
    }
    if ($shouldOpenOutput) { Start-Process explorer.exe -ArgumentList $releaseDirectory }
}
catch {
    Write-Error $_
    exit 1
}
finally {
    foreach ($name in $signingEnvironmentNames) {
        [Environment]::SetEnvironmentVariable($name, $originalSigningEnvironment[$name], 'Process')
    }
    $temporaryPlainSecrets = @()
    Set-Location -LiteralPath $previousDirectory
}
