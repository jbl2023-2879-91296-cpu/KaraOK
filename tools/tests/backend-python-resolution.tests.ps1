$ErrorActionPreference = "Stop"

. (Join-Path (Split-Path -Parent $PSScriptRoot) `
    "dev-command-resolution.ps1")

$testRoot = Join-Path $PSScriptRoot ".tmp-backend-python-$PID"
$primaryPython = Join-Path $testRoot ".venv\Scripts\python.exe"
$fallbackPython = Join-Path $testRoot `
    ".venv.TEST-MACHINE\Scripts\python.exe"

try {
    New-Item -ItemType Directory `
        -Path (Split-Path -Parent $primaryPython), `
            (Split-Path -Parent $fallbackPython) `
        -Force | Out-Null
    New-Item -ItemType File -Path $primaryPython, $fallbackPython `
        -Force | Out-Null

    $bothValid = {
        param([string]$Candidate)
        return $Candidate -in @($primaryPython, $fallbackPython)
    }
    $selected = Resolve-BackendPythonPath `
        -BackendDirectory $testRoot `
        -MachineName "TEST-MACHINE" `
        -Validator $bothValid
    if ($selected -ne $primaryPython) {
        throw "FAIL: expected valid primary environment '$primaryPython', got '$selected'"
    }
    Write-Output "PASS: valid primary backend environment wins"

    $fallbackOnly = {
        param([string]$Candidate)
        return $Candidate -eq $fallbackPython
    }
    $selected = Resolve-BackendPythonPath `
        -BackendDirectory $testRoot `
        -MachineName "TEST-MACHINE" `
        -Validator $fallbackOnly
    if ($selected -ne $fallbackPython) {
        throw "FAIL: expected machine fallback '$fallbackPython', got '$selected'"
    }
    Write-Output "PASS: invalid primary falls through to machine environment"
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
