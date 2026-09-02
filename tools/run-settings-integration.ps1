[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$settingsE2eDb = 'karaok_settings_e2e'
$settingsE2ePort = 5100
$mysqlLoginPath = 'karaok-e2e'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$backendRoot = Join-Path $repositoryRoot 'backend'
$frontendRoot = Join-Path $repositoryRoot 'frontend'
$schemaPath = Join-Path $repositoryRoot 'database\schema.sql'
$pythonPath = Join-Path $backendRoot '.venv\Scripts\python.exe'
$backendProcess = $null
$settingsE2eTemp = $null
$mysqlExecutable = $null
$mysqlReady = $false
$runFailure = $null
$cleanupFailures = New-Object 'System.Collections.Generic.List[string]'

$environmentNames = @(
    'DB_HOST',
    'DB_PORT',
    'DB_NAME',
    'DB_USER',
    'DB_PASSWORD',
    'ADMIN_DATA_API_ENABLED',
    'ADMIN_DB_NAME',
    'ADMIN_DB_USER',
    'ADMIN_DB_PASSWORD',
    'APP_HOST',
    'APP_PORT',
    'FLASK_DEBUG',
    'DEV_MODE',
    'EXPOSE_REGISTRATION_OTP',
    'SETTINGS_RECOMMENDATIONS_ENABLED',
    'JWT_SECRET',
    'RATELIMIT_STORAGE_URI',
    'SMTP_HOST',
    'SMTP_USERNAME',
    'SMTP_PASSWORD',
    'SMTP_FROM',
    'AUDIO_UPLOAD_DIR',
    'AUDIO_ANALYSIS_OUTPUT_DIR',
    'PYTHONUNBUFFERED'
)
$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

function Set-BackendEnvironment {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowEmptyString()][string]$Value
    )
    [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
}

function Invoke-MySqlQuery {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string]$Query,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )
    & $Executable "--login-path=$mysqlLoginPath" --execute $Query
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage (mysql exit code $LASTEXITCODE)."
    }
}

function Invoke-MySqlInput {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string]$Database,
        [Parameter(Mandatory = $true)][string]$Sql,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )
    $Sql | & $Executable "--login-path=$mysqlLoginPath" "--database=$Database"
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage (mysql exit code $LASTEXITCODE)."
    }
}

try {
    if ($settingsE2eDb -cne 'karaok_settings_e2e' -or
        $settingsE2eDb -notmatch '^[a-z0-9_]+$' -or
        $settingsE2eDb -eq 'karaok_db') {
        throw 'Refusing to run: the fixed integration database name failed validation.'
    }

    $mysqlCommand = Get-Command mysql -CommandType Application -ErrorAction Stop
    $mysqlExecutable = $mysqlCommand.Source
    if (-not (Test-Path -LiteralPath $pythonPath -PathType Leaf)) {
        throw "Backend virtual-environment Python was not found at $pythonPath."
    }
    $flutterCommand = Get-Command flutter -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
        throw "Required database script was not found: $schemaPath"
    }
    $dotenvSearchDirectory = Join-Path $backendRoot 'karaok'
    while ($null -ne $dotenvSearchDirectory) {
        $dotenvPath = Join-Path $dotenvSearchDirectory '.env'
        if (Test-Path -LiteralPath $dotenvPath -PathType Leaf) {
            $dotenvContents = Get-Content -LiteralPath $dotenvPath -Raw
            if ($dotenvContents -match '(?im)^\s*SMTP_(HOST|USERNAME|PASSWORD|FROM)\s*=') {
                throw "Refusing to run while $dotenvPath contains SMTP settings; the E2E registration must never send email."
            }
        }
        $dotenvParent = [IO.Directory]::GetParent($dotenvSearchDirectory)
        $dotenvSearchDirectory = if ($null -eq $dotenvParent) {
            $null
        }
        else {
            $dotenvParent.FullName
        }
    }
    if ([string]::IsNullOrWhiteSpace($env:KARAOK_E2E_DB_USER) -or
        [string]::IsNullOrWhiteSpace($env:KARAOK_E2E_DB_PASSWORD)) {
        throw 'Set KARAOK_E2E_DB_USER and KARAOK_E2E_DB_PASSWORD before running this harness.'
    }

    & $mysqlExecutable "--login-path=$mysqlLoginPath" --execute 'SELECT 1;'
    if ($LASTEXITCODE -ne 0) {
        throw "MySQL login path '$mysqlLoginPath' is missing or unusable."
    }
    $mysqlReady = $true

    $devicesJson = & $flutterCommand.Source devices --machine
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter could not enumerate devices (exit code $LASTEXITCODE)."
    }
    $windowsDevice = @($devicesJson | ConvertFrom-Json) |
        Where-Object { $_.id -eq 'windows' -or $_.platformType -eq 'windows' } |
        Select-Object -First 1
    if ($null -eq $windowsDevice) {
        throw 'Flutter Windows desktop support is required, but no Windows device is available.'
    }
    $doctorOutput = (& $flutterCommand.Source doctor -v 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter doctor failed while checking the Windows toolchain (exit code $LASTEXITCODE)."
    }
    $visualStudioLine = ($doctorOutput -split "`r?`n") |
        Where-Object { $_ -match 'Visual Studio - develop Windows apps' } |
        Select-Object -First 1
    if ($null -eq $visualStudioLine -or $visualStudioLine -notmatch '^\[(√|✓)\]') {
        throw 'A complete Visual Studio Windows desktop toolchain is required. Run flutter doctor for details.'
    }

    $portProbe = [Net.Sockets.TcpListener]::new(
        [Net.IPAddress]::Loopback,
        $settingsE2ePort
    )
    try {
        $portProbe.Start()
    }
    catch {
        throw "TCP port $settingsE2ePort is already in use."
    }
    finally {
        $portProbe.Stop()
    }

    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $tempRootPrefix = $tempRoot
    if (-not $tempRootPrefix.EndsWith([IO.Path]::DirectorySeparatorChar.ToString())) {
        $tempRootPrefix += [IO.Path]::DirectorySeparatorChar
    }
    $settingsE2eTemp = Join-Path $tempRootPrefix "karaok-settings-e2e-$([Guid]::NewGuid().ToString('N'))"
    $settingsE2eTemp = [IO.Path]::GetFullPath(
        (New-Item -ItemType Directory -Path $settingsE2eTemp).FullName
    )
    if (-not $settingsE2eTemp.StartsWith(
            $tempRootPrefix,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        throw 'The integration temporary directory is not beneath the system temporary root.'
    }
    $uploadDirectory = (New-Item -ItemType Directory -Path (Join-Path $settingsE2eTemp 'uploads')).FullName
    $analysisDirectory = (New-Item -ItemType Directory -Path (Join-Path $settingsE2eTemp 'analysis')).FullName

    Invoke-MySqlQuery -Executable $mysqlExecutable -Query "DROP DATABASE IF EXISTS $settingsE2eDb;" -FailureMessage 'Could not remove a stale integration database'
    Invoke-MySqlQuery -Executable $mysqlExecutable -Query "CREATE DATABASE $settingsE2eDb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" -FailureMessage 'Could not create the integration database'

    $schemaSql = Get-Content -LiteralPath $schemaPath -Raw
    $createDatabasePattern = '(?im)^\s*CREATE\s+DATABASE\s+IF\s+NOT\s+EXISTS\s+karaok_db\s*;\s*$'
    $useDatabasePattern = '(?im)^\s*USE\s+karaok_db\s*;\s*$'
    if ([regex]::Matches($schemaSql, $createDatabasePattern).Count -ne 1 -or
        [regex]::Matches($schemaSql, $useDatabasePattern).Count -ne 1) {
        throw 'Schema bootstrap database statements changed; refusing an unsafe import.'
    }
    $schemaSql = [regex]::Replace(
        $schemaSql,
        $createDatabasePattern,
        "CREATE DATABASE IF NOT EXISTS $settingsE2eDb;"
    )
    $schemaSql = [regex]::Replace(
        $schemaSql,
        $useDatabasePattern,
        "USE $settingsE2eDb;"
    )
    if ($schemaSql -match '(?im)^\s*(CREATE\s+DATABASE|USE)\s+[^;]*karaok_db') {
        throw 'The rewritten schema still contains an executable reference to karaok_db.'
    }
    Invoke-MySqlInput -Executable $mysqlExecutable -Database $settingsE2eDb -Sql $schemaSql -FailureMessage 'Could not import database/schema.sql into the integration database'

    Set-BackendEnvironment 'DB_HOST' '127.0.0.1'
    Set-BackendEnvironment 'DB_PORT' '3306'
    Set-BackendEnvironment 'DB_NAME' $settingsE2eDb
    Set-BackendEnvironment 'DB_USER' $env:KARAOK_E2E_DB_USER
    Set-BackendEnvironment 'DB_PASSWORD' $env:KARAOK_E2E_DB_PASSWORD
    Set-BackendEnvironment 'ADMIN_DATA_API_ENABLED' 'false'
    Set-BackendEnvironment 'ADMIN_DB_NAME' $settingsE2eDb
    Set-BackendEnvironment 'ADMIN_DB_USER' ''
    Set-BackendEnvironment 'ADMIN_DB_PASSWORD' ''
    Set-BackendEnvironment 'APP_HOST' '127.0.0.1'
    Set-BackendEnvironment 'APP_PORT' $settingsE2ePort.ToString()
    Set-BackendEnvironment 'FLASK_DEBUG' 'false'
    Set-BackendEnvironment 'DEV_MODE' 'true'
    Set-BackendEnvironment 'EXPOSE_REGISTRATION_OTP' 'true'
    Set-BackendEnvironment 'SETTINGS_RECOMMENDATIONS_ENABLED' 'true'
    Set-BackendEnvironment 'JWT_SECRET' '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
    Set-BackendEnvironment 'RATELIMIT_STORAGE_URI' 'memory://'
    Set-BackendEnvironment 'SMTP_HOST' ''
    Set-BackendEnvironment 'SMTP_USERNAME' ''
    Set-BackendEnvironment 'SMTP_PASSWORD' ''
    Set-BackendEnvironment 'SMTP_FROM' ''
    Set-BackendEnvironment 'AUDIO_UPLOAD_DIR' $uploadDirectory
    Set-BackendEnvironment 'AUDIO_ANALYSIS_OUTPUT_DIR' $analysisDirectory
    Set-BackendEnvironment 'PYTHONUNBUFFERED' '1'

    $standardOutput = Join-Path $settingsE2eTemp 'backend.stdout.log'
    $standardError = Join-Path $settingsE2eTemp 'backend.stderr.log'
    $backendStart = @{
        FilePath = $pythonPath
        ArgumentList = @('run.py')
        WorkingDirectory = $backendRoot
        WindowStyle = 'Hidden'
        RedirectStandardOutput = $standardOutput
        RedirectStandardError = $standardError
        PassThru = $true
    }
    $backendProcess = Start-Process @backendStart

    $healthUri = "http://127.0.0.1:$settingsE2ePort/api/health"
    $healthDeadline = [DateTime]::UtcNow.AddSeconds(30)
    $healthy = $false
    while ([DateTime]::UtcNow -lt $healthDeadline) {
        $backendProcess.Refresh()
        if ($backendProcess.HasExited) {
            $stderr = if (Test-Path -LiteralPath $standardError) {
                Get-Content -LiteralPath $standardError -Raw
            }
            else {
                ''
            }
            throw "The integration backend exited before becoming healthy. $stderr"
        }
        try {
            $health = Invoke-RestMethod -Uri $healthUri -TimeoutSec 2
            if ($health.status -eq 'ok') {
                $healthy = $true
                break
            }
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }
    if (-not $healthy) {
        throw "The integration backend did not become healthy within 30 seconds."
    }

    Push-Location $frontendRoot
    try {
        & $flutterCommand.Source test 'integration_test/settings_generation_flow_test.dart' -d windows '--dart-define=API_BASE_URL=http://127.0.0.1:5100/api'
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter settings integration test failed (exit code $LASTEXITCODE)."
        }
    }
    finally {
        Pop-Location
    }

    Write-Host 'Settings generation integration test passed.' -ForegroundColor Green
}
catch {
    $runFailure = $_
}
finally {
    if ($null -ne $backendProcess) {
        try {
            $backendProcess.Refresh()
            if (-not $backendProcess.HasExited) {
                Stop-Process -Id $backendProcess.Id -ErrorAction Stop
                if (-not $backendProcess.WaitForExit(10000)) {
                    throw "Backend process $($backendProcess.Id) did not stop within 10 seconds."
                }
            }
        }
        catch {
            $cleanupFailures.Add("Backend cleanup failed: $($_.Exception.Message)")
        }
    }

    if ($mysqlReady -and $null -ne $mysqlExecutable) {
        try {
            if ($settingsE2eDb -cne 'karaok_settings_e2e' -or
                $settingsE2eDb -notmatch '^[a-z0-9_]+$') {
                throw 'Integration database name failed its cleanup validation.'
            }
            & $mysqlExecutable "--login-path=$mysqlLoginPath" --execute "DROP DATABASE IF EXISTS $settingsE2eDb;"
            if ($LASTEXITCODE -ne 0) {
                throw "mysql exited with code $LASTEXITCODE."
            }
        }
        catch {
            $cleanupFailures.Add("Database cleanup failed: $($_.Exception.Message)")
        }
    }

    if ($null -ne $settingsE2eTemp) {
        try {
            $resolvedTemp = [IO.Path]::GetFullPath($settingsE2eTemp)
            $resolvedRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
            $resolvedRootPrefix = $resolvedRoot
            if (-not $resolvedRootPrefix.EndsWith([IO.Path]::DirectorySeparatorChar.ToString())) {
                $resolvedRootPrefix += [IO.Path]::DirectorySeparatorChar
            }
            if ($resolvedTemp -eq $resolvedRoot -or
                -not $resolvedTemp.StartsWith(
                    $resolvedRootPrefix,
                    [StringComparison]::OrdinalIgnoreCase
                )) {
                throw "Refusing to remove a path outside the temporary root: $resolvedTemp"
            }
            if (Test-Path -LiteralPath $resolvedTemp) {
                Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
            }
            if (Test-Path -LiteralPath $resolvedTemp) {
                throw "Temporary directory still exists: $resolvedTemp"
            }
        }
        catch {
            $cleanupFailures.Add("Temporary-directory cleanup failed: $($_.Exception.Message)")
        }
    }

    foreach ($name in $environmentNames) {
        try {
            [Environment]::SetEnvironmentVariable(
                $name,
                $savedEnvironment[$name],
                'Process'
            )
        }
        catch {
            $cleanupFailures.Add("Environment restoration failed for ${name}: $($_.Exception.Message)")
        }
    }
}

if ($null -ne $runFailure) {
    $message = $runFailure.Exception.Message
    if ($cleanupFailures.Count -gt 0) {
        $message += " Cleanup errors: $($cleanupFailures -join ' ')"
    }
    throw $message
}
if ($cleanupFailures.Count -gt 0) {
    throw "Integration cleanup failed: $($cleanupFailures -join ' ')"
}
