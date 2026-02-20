[CmdletBinding()]
param(
	[string]$WorkspaceRoot = "",
	[string]$SourceRoot = "",
	[string]$TargetRoot = "",
	[switch]$DryRun
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

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
	$SourceRoot = Join-Path $WorkspaceRoot "..\scummvm-2026.1.0"
}
if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
	$TargetRoot = Join-Path $WorkspaceRoot "custom_scummvm-2026.1.0"
}

$SourceRoot = (Resolve-Path $SourceRoot).Path
if (-not (Test-Path $TargetRoot)) {
	New-Item -ItemType Directory -Path $TargetRoot | Out-Null
}
$TargetRoot = (Resolve-Path $TargetRoot).Path

if (-not (Test-Path $SourceRoot)) {
	Fail 10 "SourceRoot를 찾을 수 없습니다: $SourceRoot"
}

$robocopy = Get-Command robocopy -ErrorAction SilentlyContinue
if (-not $robocopy) {
	Fail 11 "robocopy 명령을 찾지 못했습니다."
}

$excludeDirs = @(
	".git",
	".vs",
	"vcpkg_installed",
	"dists\msvc\Debug",
	"dists\msvc\Debugx64",
	"dists\msvc\Debugx86",
	"dists\msvc\Release",
	"dists\msvc\Releasex64",
	"dists\msvc\Releasex86",
	"devtools\create_project\msvc\Debug",
	"devtools\create_project\msvc\Release"
) | ForEach-Object { Join-Path $SourceRoot $_ }

$excludeFiles = @(
	"*.obj",
	"*.pdb",
	"*.ilk",
	"*.idb",
	"*.tlog",
	"*.lastbuildstate",
	"*.exe",
	"*.dll"
)

$args = @(
	$SourceRoot,
	$TargetRoot,
	"/MIR",
	"/R:1",
	"/W:1",
	"/NP",
	"/NDL",
	"/NJH",
	"/NJS",
	"/XD"
) + $excludeDirs + @(
	"/XF"
) + $excludeFiles

if ($DryRun) {
	$args += "/L"
}

Step "custom_scummvm-2026.1.0 스냅샷 동기화"
& $robocopy.Source @args | Out-Host
$exitCode = $LASTEXITCODE

# Robocopy exit code 0-7 are success conditions
if ($exitCode -gt 7) {
	Fail 20 "robocopy 실패 (exit code: $exitCode)"
}

Write-Host ""
Write-Host "Snapshot sync complete" -ForegroundColor Green
Write-Host "  Source: $SourceRoot"
Write-Host "  Target: $TargetRoot"
Write-Host "  Robocopy exit code: $exitCode"
exit 0
