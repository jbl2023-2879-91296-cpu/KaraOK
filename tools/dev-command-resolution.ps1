function Resolve-ComposerPath {
    [CmdletBinding()]
    param(
        [string[]]$FallbackPaths,
        [string[]]$RegisteredPaths
    )

    $command = Get-Command composer -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    if (-not $PSBoundParameters.ContainsKey("RegisteredPaths")) {
        $RegisteredPaths = @(
            [Environment]::GetEnvironmentVariable("Path", "Machine") -split ";"
            [Environment]::GetEnvironmentVariable("Path", "User") -split ";"
        )
    }

    $processPaths = @($env:Path -split ";")
    foreach ($registeredPath in $RegisteredPaths) {
        $expandedPath = [Environment]::ExpandEnvironmentVariables(
            $registeredPath.Trim().Trim('"')
        )
        if (
            $expandedPath -and
            (Test-Path -LiteralPath $expandedPath -PathType Container) -and
            $processPaths -notcontains $expandedPath
        ) {
            $env:Path = "$env:Path;$expandedPath"
            $processPaths += $expandedPath
        }
    }

    $command = Get-Command composer -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    if ($null -eq $FallbackPaths -or $FallbackPaths.Count -eq 0) {
        $FallbackPaths = @(
            (Join-Path `
                ([Environment]::GetFolderPath("LocalApplicationData")) `
                "ComposerSetup\bin\composer.bat")
            (Join-Path `
                ([Environment]::GetFolderPath("CommonApplicationData")) `
                "ComposerSetup\bin\composer.bat")
        )
    }

    foreach ($candidate in $FallbackPaths) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Composer was not found in PATH or its standard Windows installation locations. Install Composer from https://getcomposer.org/download/."
}

function Resolve-MySqlPath {
    [CmdletBinding()]
    param(
        [string[]]$FallbackPaths,
        [string[]]$RegisteredPaths
    )

    $command = Get-Command mysql -CommandType Application `
        -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    if (-not $PSBoundParameters.ContainsKey("RegisteredPaths")) {
        $RegisteredPaths = @(
            [Environment]::GetEnvironmentVariable("Path", "Machine") -split ";"
            [Environment]::GetEnvironmentVariable("Path", "User") -split ";"
        )
    }

    $processPaths = @($env:Path -split ";")
    foreach ($registeredPath in $RegisteredPaths) {
        $expandedPath = [Environment]::ExpandEnvironmentVariables(
            $registeredPath.Trim().Trim('"')
        )
        if (
            $expandedPath -and
            (Test-Path -LiteralPath $expandedPath -PathType Container) -and
            $processPaths -notcontains $expandedPath
        ) {
            $env:Path = "$env:Path;$expandedPath"
            $processPaths += $expandedPath
        }
    }

    $command = Get-Command mysql -CommandType Application `
        -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    if ($null -eq $FallbackPaths -or $FallbackPaths.Count -eq 0) {
        $mysqlRoot = Join-Path `
            ([Environment]::GetFolderPath("ProgramFiles")) `
            "MySQL"
        if (Test-Path -LiteralPath $mysqlRoot -PathType Container) {
            $FallbackPaths = @(Get-ChildItem -LiteralPath $mysqlRoot `
                -Directory -Filter "MySQL Server *" |
                Sort-Object Name -Descending |
                ForEach-Object { Join-Path $_.FullName "bin\mysql.exe" })
        }
    }

    foreach ($candidate in $FallbackPaths) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "MySQL was not found in PATH or its standard Windows installation locations. Install MySQL Server or add its bin directory to PATH."
}

function Resolve-BackendPythonPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackendDirectory,
        [string]$MachineName = [Environment]::MachineName,
        [scriptblock]$Validator
    )

    $safeMachineName = $MachineName -replace "[^A-Za-z0-9._-]", "-"
    $primaryPath = Join-Path $BackendDirectory ".venv\Scripts\python.exe"
    $fallbackPath = Join-Path $BackendDirectory `
        ".venv.$safeMachineName\Scripts\python.exe"

    if ($null -eq $Validator) {
        $Validator = {
            param([string]$Candidate)
            try {
                & $Candidate -c `
                    "import argon2, flask, flask_cors, flask_limiter, librosa, matplotlib, mysql.connector, mutagen, numpy, pandas, jwt, dotenv, scipy, soundfile" `
                    2>$null
                return $LASTEXITCODE -eq 0
            }
            catch {
                return $false
            }
        }
    }

    foreach ($candidate in @($primaryPath, $fallbackPath)) {
        if (
            (Test-Path -LiteralPath $candidate -PathType Leaf) -and
            (& $Validator $candidate)
        ) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "No working backend Python environment was found. Checked '$primaryPath' and '$fallbackPath'."
}

function Resolve-AdbPath {
    [CmdletBinding()]
    param([string[]]$FallbackPaths)

    $command = Get-Command adb -CommandType Application `
        -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    if ($null -eq $FallbackPaths -or $FallbackPaths.Count -eq 0) {
        $FallbackPaths = @(
            (Join-Path `
                ([Environment]::GetFolderPath("LocalApplicationData")) `
                "Android\Sdk\platform-tools\adb.exe")
        )
    }

    foreach ($candidate in $FallbackPaths) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function Get-AuthorizedAndroidDeviceIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$AdbDevicesOutput
    )

    foreach ($line in $AdbDevicesOutput) {
        if ($line -match '^([^\s]+)\s+device(?:\s|$)') {
            $Matches[1]
        }
    }
}

function Get-FlutterRunArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ApiBaseUrl,

        [string]$DeviceId
    )

    $arguments = @("run")
    if (-not [string]::IsNullOrWhiteSpace($DeviceId)) {
        $arguments += @("-d", $DeviceId.Trim())
    }
    $arguments += "--dart-define=API_BASE_URL=$ApiBaseUrl"
    return $arguments
}

function Get-DevelopmentLaunchPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ApiBaseUrl,

        [string]$DeviceId,

        [AllowEmptyCollection()]
        [string[]]$AdbDevicesOutput = @()
    )

    return [pscustomobject]@{
        AndroidDeviceIds = @(
            Get-AuthorizedAndroidDeviceIds `
                -AdbDevicesOutput $AdbDevicesOutput
        )
        FlutterRunArguments = @(
            Get-FlutterRunArguments `
                -ApiBaseUrl $ApiBaseUrl `
                -DeviceId $DeviceId
        )
    }
}
