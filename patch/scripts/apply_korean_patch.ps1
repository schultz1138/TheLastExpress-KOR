[CmdletBinding()]
param(
    [string]$WorkspaceRoot = "",
    [string]$GameDir = "",
    [string]$AllSubsHpf = "",
    [string]$SubtitleTsv = "",
    [switch]$AllowSubtitleOnly,
    [switch]$KeepWorkDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([int]$Code, [string]$Message) {
    Write-Host "[ERROR] $Message" -ForegroundColor Red
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

if ([string]::IsNullOrWhiteSpace($GameDir)) {
    Fail 10 "GameDir was not found. Pass -GameDir with your game folder."
}
if (-not (Test-Path $GameDir)) {
    Fail 11 "Game folder does not exist: $GameDir"
}

$buildScript = Join-Path $WorkspaceRoot "scripts\build_korean_hpf.ps1"
if (-not (Test-Path $buildScript)) {
    Fail 12 "Build script was not found: $buildScript"
}

$args = @{
    WorkspaceRoot = $WorkspaceRoot
    GameDir = $GameDir
    OutputHpf = (Join-Path $GameDir "KOREAN.HPF")
}

if ($AllowSubtitleOnly) {
    $args["AllowSubtitleOnly"] = $true
}
if (-not [string]::IsNullOrWhiteSpace($AllSubsHpf)) {
    $args["AllSubsHpf"] = $AllSubsHpf
}
if (-not [string]::IsNullOrWhiteSpace($SubtitleTsv)) {
    $args["SubtitleTsv"] = $SubtitleTsv
}
if ($KeepWorkDir) {
    $args["KeepWorkDir"] = $true
}

Write-Host "[STEP] Start Korean patch generation" -ForegroundColor Cyan
Write-Host "  GameDir: $GameDir"
& $buildScript @args
if ($LASTEXITCODE -ne 0) {
    Fail 20 "Patch generation failed (exit code: $LASTEXITCODE)"
}

Write-Host ""
Write-Host "apply_korean_patch.ps1 complete" -ForegroundColor Green
Write-Host "Output: $(Join-Path $GameDir 'KOREAN.HPF')"
exit 0
