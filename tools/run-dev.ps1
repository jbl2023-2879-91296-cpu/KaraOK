[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$backendDirectory = Join-Path $repositoryRoot "backend"
$frontendDirectory = Join-Path $repositoryRoot "frontend"
$backendHealthUrl = "http://127.0.0.1:5000/api/health"
$flutterApiUrl = "http://localhost:5000/api"
$backendProcess = $null
$backendListenerIds = @()
$backendStartedHere = $false
$logSuffix = [System.Diagnostics.Process]::GetCurrentProcess().Id
$backendOutputLog = Join-Path $env:TEMP "karaok-backend-$logSuffix-output.log"
$backendErrorLog = Join-Path $env:TEMP "karaok-backend-$logSuffix-error.log"

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

function Stop-StartedBackend {
    foreach ($processId in $backendListenerIds) {
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }

    if ($null -ne $backendProcess) {
        Stop-Process -Id $backendProcess.Id -Force -ErrorAction SilentlyContinue
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

$pythonLauncher = Get-Command py -ErrorAction Stop
$flutterCommand = Get-Command flutter -ErrorAction Stop

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

        Write-Host "Starting KaraOK backend with: py app.py" `
            -ForegroundColor Cyan
        $backendProcess = Start-Process `
            -FilePath $pythonLauncher.Source `
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

    Write-Host "Starting Flutter with API_BASE_URL=$flutterApiUrl" `
        -ForegroundColor Cyan
    Push-Location $frontendDirectory
    try {
        & $flutterCommand.Source run `
            "--dart-define=API_BASE_URL=$flutterApiUrl"
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
    if ($backendStartedHere) {
        Write-Host "Stopping the backend started by this script..." `
            -ForegroundColor Yellow
        Stop-StartedBackend
    }
}
- .\tools\run-dev.ps1
- OR 
- powershell -ExecutionPolicy Bypass -File .\tools\run-dev.ps1