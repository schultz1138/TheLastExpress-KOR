[CmdletBinding()]
param(
    [string]$WorkspaceRoot = "",
    [string]$GameDir = "",
    [string]$ModedHpf = "",
    [string]$OutputTsv = "",
    [string]$MergeSubkoTsv = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Step([string]$Message) {
    Write-Host "[STEP] $Message" -ForegroundColor Cyan
}

function Fail([int]$Code, [string]$Message) {
    Write-Error $Message
    exit $Code
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

if ([string]::IsNullOrWhiteSpace($ModedHpf)) {
    $modedCandidates = @()
    if (-not [string]::IsNullOrWhiteSpace($GameDir)) {
        $modedCandidates += (Join-Path $GameDir "Moded_HD.HPF")
    }
    $modedCandidates += @(
        (Join-Path $WorkspaceRoot "translation\Moded_HD.HPF"),
        (Join-Path $WorkspaceRoot "Moded_HD.HPF")
    )
    foreach ($candidate in $modedCandidates) {
        if (Test-Path $candidate) {
            $ModedHpf = $candidate
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($ModedHpf)) {
    Fail 10 "Moded HD archive was not found. Pass -ModedHpf explicitly."
}
if (-not (Test-Path $ModedHpf)) {
    Fail 11 "Moded HD archive does not exist: $ModedHpf"
}

$extractScript = Join-Path $WorkspaceRoot "tools\extract_kosubs_template.py"
if (-not (Test-Path $extractScript)) {
    Fail 12 "Extract script not found: $extractScript"
}

$py = Get-Command py -ErrorAction SilentlyContinue
if (-not $py) {
    $py = Get-Command python -ErrorAction SilentlyContinue
}
if (-not $py) {
    Fail 13 "Python launcher 'py' or 'python' was not found."
}

Step "Extract editable subtitle template"
$args = @("--hpf", $ModedHpf, "--out", $OutputTsv)
if (Test-Path $MergeSubkoTsv) {
    $args += @("--merge-subko", $MergeSubkoTsv)
}

& $py.Source $extractScript @args
if ($LASTEXITCODE -ne 0) {
    Fail 20 "Subtitle template extraction failed (exit code: $LASTEXITCODE)"
}

Write-Host ""
Write-Host "extract_subtitle_template.ps1 complete" -ForegroundColor Green
Write-Host "Output: $OutputTsv"
exit 0
