[CmdletBinding()]
param(
    [string]$WorkspaceRoot = "",
    [string]$GameDir = "",
    [string]$AllSubsHpf = "",
    [string]$OutputTsv = "",
    [string]$MergeSubkoTsv = ""
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

if ([string]::IsNullOrWhiteSpace($GameDir)) {
    $candidates = @(
        (Join-Path $WorkspaceRoot "The Last Express"),
        (Join-Path $WorkspaceRoot "lastexpress")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            $GameDir = $candidate
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($OutputTsv)) {
    $OutputTsv = Join-Path $WorkspaceRoot "translation\kosubs.user.tsv"
}
if ([string]::IsNullOrWhiteSpace($MergeSubkoTsv)) {
    $MergeSubkoTsv = Join-Path $WorkspaceRoot "translation\subko.tsv"
}

if ([string]::IsNullOrWhiteSpace($AllSubsHpf)) {
    $allSubsCandidates = @()
    if (-not [string]::IsNullOrWhiteSpace($GameDir)) {
        $allSubsCandidates += (Join-Path $GameDir "HD_AllSubs.HPF")
    }
    $allSubsCandidates += @(
        (Join-Path $WorkspaceRoot "translation\HD_AllSubs.HPF"),
        (Join-Path $WorkspaceRoot "HD_AllSubs.HPF")
    )
    foreach ($candidate in $allSubsCandidates) {
        if (Test-Path $candidate) {
            $AllSubsHpf = $candidate
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($AllSubsHpf)) {
    Fail 10 "HD_AllSubs archive was not found. Pass -AllSubsHpf explicitly."
}
if (-not (Test-Path $AllSubsHpf)) {
    Fail 11 "HD_AllSubs archive does not exist: $AllSubsHpf"
}

$extractScript = Join-Path $WorkspaceRoot "tools\extract_kosubs_template.py"
if (-not (Test-Path $extractScript)) {
    Fail 12 "Extract script not found: $extractScript"
}

$pythonExe = Resolve-PythonExe $WorkspaceRoot
if ([string]::IsNullOrWhiteSpace($pythonExe)) {
    Fail 13 "Python 3 runtime not available. Install Python 3, or use a release package that includes runtime\python\python.exe."
}

Step "Extract editable subtitle template"
$args = @("--hpf", $AllSubsHpf, "--out", $OutputTsv)
if (Test-Path $MergeSubkoTsv) {
    $args += @("--merge-subko", $MergeSubkoTsv)
}

& $pythonExe $extractScript @args
if ($LASTEXITCODE -ne 0) {
    Fail 20 "Subtitle template extraction failed (exit code: $LASTEXITCODE)"
}

Write-Host ""
Write-Host "extract_subtitle_template.ps1 complete" -ForegroundColor Green
Write-Host "Output: $OutputTsv"
exit 0
