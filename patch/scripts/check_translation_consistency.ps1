[CmdletBinding()]
param(
    [string]$WorkspaceRoot = "",
    [string]$InputTsv = "",
    [string]$ReportTsv = "",
    [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Step([string]$Message) {
    Write-Host "[STEP] $Message" -ForegroundColor Cyan
}

function Fail([int]$Code, [string]$Message) {
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit $Code
}

function Resolve-PythonExe([string]$RootPath) {
    foreach ($exe in @(
        (Join-Path $RootPath "runtime\python\python.exe"),
        (Join-Path $RootPath "python\python.exe")
    )) {
        if (-not (Test-Path $exe)) {
            continue
        }
        try {
            & $exe -c "import sys" *> $null
            if ($LASTEXITCODE -eq 0) {
                return $exe
            }
        } catch {
        }
    }

    foreach ($name in @("py", "python", "python3")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq "Application" } | Select-Object -First 1
        if (-not $cmd) {
            continue
        }

        $exe = [string]$cmd.Source
        if ([string]::IsNullOrWhiteSpace($exe)) {
            continue
        }
        if ($exe -match '\\Microsoft\\WindowsApps\\') {
            continue
        }

        try {
            & $exe -c "import sys" *> $null
            if ($LASTEXITCODE -eq 0) {
                return $exe
            }
        } catch {
        }
    }
    return $null
}

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $scriptDir = ""
    if ($PSScriptRoot) {
        $scriptDir = $PSScriptRoot
    } elseif ($MyInvocation.MyCommand.Path) {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    } else {
        $scriptDir = (Get-Location).Path
    }

    try {
        $WorkspaceRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path
    } catch {
        $WorkspaceRoot = (Get-Location).Path
    }
}

if ([string]::IsNullOrWhiteSpace($InputTsv)) {
    foreach ($candidate in @(
        (Join-Path $WorkspaceRoot "translation\kosubs.user.tsv"),
        (Join-Path $WorkspaceRoot "translation\kosubs.tsv")
    )) {
        if (Test-Path $candidate) {
            $InputTsv = $candidate
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($InputTsv)) {
    Fail 10 "Input TSV not found. Pass -InputTsv explicitly."
}
if (-not (Test-Path $InputTsv)) {
    Fail 11 "Input TSV does not exist: $InputTsv"
}

$checkScript = Join-Path $WorkspaceRoot "tools\check_translation_consistency.py"
if (-not (Test-Path $checkScript)) {
    Fail 12 "Checker script not found: $checkScript"
}

$pythonExe = Resolve-PythonExe $WorkspaceRoot
if ([string]::IsNullOrWhiteSpace($pythonExe)) {
    Fail 13 "Python 3 runtime not available. Install Python 3, or use a release package that includes runtime\python\python.exe."
}

Step "Check translation consistency (same source -> different translation)"
$args = @("--input", $InputTsv)
if (-not [string]::IsNullOrWhiteSpace($ReportTsv)) {
    $args += @("--out-tsv", $ReportTsv)
}
if ($Strict) {
    $args += "--strict-exit"
}

& $pythonExe $checkScript @args
if ($LASTEXITCODE -ne 0) {
    Fail 20 "Translation consistency check failed (exit code: $LASTEXITCODE)"
}

Write-Host ""
Write-Host "check_translation_consistency.ps1 complete" -ForegroundColor Green
Write-Host "Input: $InputTsv"
if (-not [string]::IsNullOrWhiteSpace($ReportTsv)) {
    Write-Host "Report: $ReportTsv"
}
exit 0
