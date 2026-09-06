<#
.SYNOPSIS
Starts the KaraOK backend, local Admin Console, and Flutter application.

.EXAMPLE
.\tools\run-dev.ps1

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\tools\run-dev.ps1

.EXAMPLE
.\tools\run-dev.ps1 -DeviceId R3CM908XHSK
#>

[CmdletBinding()]
param(
    [string]$DeviceId
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "dev-command-resolution.ps1")

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$backendDirectory = Join-Path $repositoryRoot "backend"
$adminDirectory = Join-Path $repositoryRoot "admin"
$frontendDirectory = Join-Path $repositoryRoot "frontend"
$backendHealthUrl = "http://127.0.0.1:5000/api/health"
$adminLoginUrl = "http://127.0.0.1:8080/login"
$flutterApiUrl = "http://127.0.0.1:5000/api"
$backendProcess = $null
$backendListenerIds = @()
$backendStartedHere = $false
$adminProcess = $null
$adminListenerIds = @()
$adminStartedHere = $false
$logSuffix = [System.Diagnostics.Process]::GetCurrentProcess().Id
$backendOutputLog = Join-Path $env:TEMP "karaok-backend-$logSuffix-output.log"
$backendErrorLog = Join-Path $env:TEMP "karaok-backend-$logSuffix-error.log"
$adminOutputLog = Join-Path $env:TEMP "karaok-admin-$logSuffix-output.log"
$adminErrorLog = Join-Path $env:TEMP "karaok-admin-$logSuffix-error.log"

function Test-BackendReady {
    try {
        $response = Invoke-RestMethod `
            -Uri $backendHealthUrl `
            -Method Get `
            -TimeoutSec 2
        return $response.status -eq "ok"
    }
    catch {
        return $false
    }
}

function Get-BackendListenerProcessIds {
    $processIds = @()
    $lines = netstat -ano -p TCP | Select-String "LISTENING"

    foreach ($line in $lines) {
        $columns = $line.Line.Trim() -split "\s+"
        if ($columns.Count -ge 5 -and $columns[1] -match ":5000$") {
            $processIds += [int]$columns[4]
        }
    }

    return @($processIds | Sort-Object -Unique)
}

function Test-AdminReady {
    try {
        $response = Invoke-WebRequest `
            -Uri $adminLoginUrl `
            -Method Get `
            -UseBasicParsing `
            -TimeoutSec 2
        return $response.StatusCode -eq 200 -and `
            $response.Content -match "KaraOK Admin Console"
    }
    catch {
        return $false
    }
}

function Get-AdminListenerProcessIds {
    $processIds = @()
    $lines = netstat -ano -p TCP | Select-String "LISTENING"

    foreach ($line in $lines) {
        $columns = $line.Line.Trim() -split "\s+"
        if ($columns.Count -ge 5 -and $columns[1] -match ":8080$") {
            $processIds += [int]$columns[4]
        }
    }

    return @($processIds | Sort-Object -Unique)
}

function Stop-StartedBackend {
    foreach ($processId in $backendListenerIds) {
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }

    if ($null -ne $backendProcess) {
        Stop-Process -Id $backendProcess.Id -Force -ErrorAction SilentlyContinue
    }
}

function Stop-StartedAdmin {
    foreach ($processId in $adminListenerIds) {
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }

    if ($null -ne $adminProcess) {
        Stop-Process -Id $adminProcess.Id -Force -ErrorAction SilentlyContinue
    }
}

function Wait-ForBackendHealth {
    param(
        [int]$TimeoutSeconds
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if (Test-BackendReady) {
            return $true
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)

    return $false
}

function Wait-ForAdminReady {
    param(
        [int]$TimeoutSeconds
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if (Test-AdminReady) {
            return $true
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)

    return $false
}

function Stop-UnhealthyPythonListeners {
    param(
        [int[]]$ListenerIds
    )

    foreach ($listenerId in $ListenerIds) {
        $listenerProcess = Get-Process -Id $listenerId -ErrorAction SilentlyContinue
        if ($null -eq $listenerProcess) {
            continue
        }
        if ($listenerProcess.ProcessName -notin @("py", "python", "python3")) {
            throw "Port 5000 belongs to $($listenerProcess.ProcessName) (PID $listenerId), not a Python backend. Stop it manually or change the backend port."
        }
    }

    Write-Host "Replacing an unhealthy Python backend on port 5000..." `
        -ForegroundColor Yellow
    foreach ($listenerId in $ListenerIds) {
        Stop-Process -Id $listenerId -Force -ErrorAction SilentlyContinue
    }

    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while (@(Get-BackendListenerProcessIds).Count -gt 0) {
        if ([DateTime]::UtcNow -ge $deadline) {
            throw "The unhealthy Python backend did not release port 5000."
        }
        Start-Sleep -Milliseconds 250
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $backendDirectory "app.py"))) {
    throw "Backend entry point not found: $backendDirectory\app.py"
}

if (-not (Test-Path -LiteralPath (Join-Path $frontendDirectory "pubspec.yaml"))) {
    throw "Flutter project not found: $frontendDirectory\pubspec.yaml"
}

if (-not (Test-Path -LiteralPath (Join-Path $adminDirectory "composer.json"))) {
    throw "Admin Console Composer project not found: $adminDirectory\composer.json"
}

$flutterCommand = Get-Command flutter -ErrorAction Stop
$composerPath = Resolve-ComposerPath
$backendPythonPath = Resolve-BackendPythonPath `
    -BackendDirectory $backendDirectory

try {
    if (Wait-ForBackendHealth -TimeoutSeconds 2) {
        Write-Host "KaraOK backend is already healthy at $backendHealthUrl" `
            -ForegroundColor Yellow
    }
    else {
        $occupiedListenerIds = @(Get-BackendListenerProcessIds)
        if ($occupiedListenerIds.Count -gt 0) {
            Stop-UnhealthyPythonListeners -ListenerIds $occupiedListenerIds
        }

        Write-Host "Starting KaraOK backend with: $backendPythonPath app.py" `
            -ForegroundColor Cyan
        $backendProcess = Start-Process `
            -FilePath $backendPythonPath `
            -ArgumentList "app.py" `
            -WorkingDirectory $backendDirectory `
            -WindowStyle Hidden `
            -RedirectStandardOutput $backendOutputLog `
            -RedirectStandardError $backendErrorLog `
            -PassThru
        $backendStartedHere = $true

        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        while (-not (Test-BackendReady)) {
            if ($backendProcess.HasExited) {
                $errorDetails = ""
                if (Test-Path -LiteralPath $backendErrorLog) {
                    $errorDetails = (Get-Content $backendErrorLog -Tail 20) -join `
                        [Environment]::NewLine
                }
                throw "The backend stopped before becoming ready.`n$errorDetails"
            }

            if ([DateTime]::UtcNow -ge $deadline) {
                throw "The backend did not become healthy within 30 seconds. Logs: $backendOutputLog and $backendErrorLog"
            }

            Start-Sleep -Milliseconds 500
        }

        $backendListenerIds = @(Get-BackendListenerProcessIds)
        Write-Host "Backend ready at $backendHealthUrl" -ForegroundColor Green
    }

    if (Wait-ForAdminReady -TimeoutSeconds 2) {
        Write-Host "KaraOK Admin Console is already ready at $adminLoginUrl" `
            -ForegroundColor Yellow
    }
    else {
        $occupiedAdminListenerIds = @(Get-AdminListenerProcessIds)
        if ($occupiedAdminListenerIds.Count -gt 0) {
            $processList = $occupiedAdminListenerIds -join ", "
            throw "Port 8080 is already in use by PID(s) $processList, but the KaraOK Admin Console did not respond. Stop that process or change its port."
        }

        Write-Host "Installing Admin Console dependencies with Composer..." `
            -ForegroundColor Cyan
        Push-Location $adminDirectory
        try {
            & $composerPath install --no-interaction --no-progress
            if ($LASTEXITCODE -ne 0) {
                throw "composer install exited with code $LASTEXITCODE"
            }

            Write-Host "Running Admin Console tests with Composer..." `
                -ForegroundColor Cyan
            & $composerPath test
            if ($LASTEXITCODE -ne 0) {
                throw "composer test exited with code $LASTEXITCODE"
            }
        }
        finally {
            Pop-Location
        }

        Write-Host "Starting KaraOK Admin Console with: composer serve" `
            -ForegroundColor Cyan
        $escapedComposerPath = $composerPath.Replace("'", "''")
        $adminLaunchCommand = "& '$escapedComposerPath' serve"
        $encodedAdminCommand = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($adminLaunchCommand)
        )
        $powerShellExecutable = (Get-Process -Id $PID).Path
        $adminProcess = Start-Process `
            -FilePath $powerShellExecutable `
            -ArgumentList "-NoProfile", "-EncodedCommand", $encodedAdminCommand `
            -WorkingDirectory $adminDirectory `
            -WindowStyle Hidden `
            -RedirectStandardOutput $adminOutputLog `
            -RedirectStandardError $adminErrorLog `
            -PassThru
        $adminStartedHere = $true

        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        while (-not (Test-AdminReady)) {
            if ($adminProcess.HasExited) {
                $errorDetails = ""
                if (Test-Path -LiteralPath $adminErrorLog) {
                    $errorDetails = (Get-Content $adminErrorLog -Tail 20) -join `
                        [Environment]::NewLine
                }
                throw "The Admin Console stopped before becoming ready.`n$errorDetails"
            }

            if ([DateTime]::UtcNow -ge $deadline) {
                throw "The Admin Console did not become ready within 30 seconds. Logs: $adminOutputLog and $adminErrorLog"
            }

            Start-Sleep -Milliseconds 500
        }

        $adminListenerIds = @(Get-AdminListenerProcessIds)
        Write-Host "Admin Console ready at $adminLoginUrl" -ForegroundColor Green
    }

    $adbPath = Resolve-AdbPath
    $adbDevicesOutput = @()
    $developmentLaunchPlan = $null
    if ($null -ne $adbPath) {
        $adbDevicesOutput = @(& $adbPath devices)
        if ($LASTEXITCODE -eq 0) {
            $developmentLaunchPlan = Get-DevelopmentLaunchPlan `
                -ApiBaseUrl $flutterApiUrl `
                -DeviceId $DeviceId `
                -AdbDevicesOutput $adbDevicesOutput
            foreach ($androidDeviceId in $developmentLaunchPlan.AndroidDeviceIds) {
                & $adbPath -s $androidDeviceId reverse tcp:5000 tcp:5000 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host `
                        "Android API forwarding ready for $androidDeviceId." `
                        -ForegroundColor Green
                }
                else {
                    Write-Warning `
                        "Could not forward Android port 5000 for $androidDeviceId."
                }
            }
        }
        else {
            Write-Warning "ADB could not enumerate Android devices."
        }
    }

    if ($null -eq $developmentLaunchPlan) {
        $developmentLaunchPlan = Get-DevelopmentLaunchPlan `
            -ApiBaseUrl $flutterApiUrl `
            -DeviceId $DeviceId `
            -AdbDevicesOutput @()
    }

    Write-Host "Starting Flutter with API_BASE_URL=$flutterApiUrl" `
        -ForegroundColor Cyan
    $flutterRunArguments = @($developmentLaunchPlan.FlutterRunArguments)
    Push-Location $frontendDirectory
    try {
        & $flutterCommand.Source @flutterRunArguments
        $flutterExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($flutterExitCode -ne 0) {
        throw "flutter run exited with code $flutterExitCode"
    }
}
finally {
    if ($adminStartedHere) {
        Write-Host "Stopping the Admin Console started by this script..." `
            -ForegroundColor Yellow
        Stop-StartedAdmin
    }

    if ($backendStartedHere) {
        Write-Host "Stopping the backend started by this script..." `
            -ForegroundColor Yellow
        Stop-StartedBackend
    }
}
