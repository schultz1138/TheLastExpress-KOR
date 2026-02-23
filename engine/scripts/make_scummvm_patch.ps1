[CmdletBinding()]
param(
	[string]$WorkspaceRoot = "",
	[string]$CleanRoot = "",
	[string]$ModifiedRoot = "",
	[string]$OutputDir = "",
	[switch]$ValidateApply
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

if ([string]::IsNullOrWhiteSpace($CleanRoot)) {
	$CleanRoot = Join-Path $WorkspaceRoot "clean\scummvm-2026.1.0"
}
if ([string]::IsNullOrWhiteSpace($ModifiedRoot)) {
	$ModifiedRoot = Join-Path $WorkspaceRoot "snapshots\custom-2026.1.0"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
	$OutputDir = Join-Path $WorkspaceRoot "patches\scummvm-2026.1.0"
}

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
	Fail 10 "git 명령을 찾지 못했습니다."
}

foreach ($path in @($CleanRoot, $ModifiedRoot)) {
	if (-not (Test-Path $path)) {
		Fail 11 "경로를 찾지 못했습니다: $path"
	}
}

$files = @(
	"devtools/create_project/msvc.cpp",
	"engines/lastexpress/data/archive.cpp",
	"engines/lastexpress/data/archive.h",
	"engines/lastexpress/graphics.cpp",
	"engines/lastexpress/sound/subtitle.cpp",
	"engines/lastexpress/sound/subtitle.h"
)

$patchChunks = New-Object System.Collections.Generic.List[string]
$changedFiles = New-Object System.Collections.Generic.List[string]
$cleanName = Split-Path -Path $CleanRoot -Leaf
$modifiedName = Split-Path -Path $ModifiedRoot -Leaf

Step "clean 대비 변경 파일 diff 생성"
Push-Location $WorkspaceRoot
try {
foreach ($relPath in $files) {
	$src = Join-Path $CleanRoot $relPath
	$dst = Join-Path $ModifiedRoot $relPath
	$srcRel = "$cleanName/$relPath"
	$dstRel = "$modifiedName/$relPath"

	if (-not (Test-Path $src)) {
		Fail 20 "clean 파일이 없습니다: $src"
	}
	if (-not (Test-Path $dst)) {
		Fail 21 "modified 파일이 없습니다: $dst"
	}

	$raw = & $git.Source diff --no-index -- $srcRel $dstRel
	$exitCode = $LASTEXITCODE
	if ($exitCode -eq 0) {
		continue
	}
	if ($exitCode -ne 1) {
		Fail 22 "git diff 실패: $relPath (exit code: $exitCode)"
	}

	$diffText = [string]::Join("`n", $raw)
	$diffText = $diffText -replace ("a/{0}/" -f [regex]::Escape($cleanName)), "a/"
	$diffText = $diffText -replace ("b/{0}/" -f [regex]::Escape($modifiedName)), "b/"
	$patchChunks.Add($diffText.TrimEnd())
	$changedFiles.Add($relPath)
}
} finally {
	Pop-Location
}

if ($changedFiles.Count -eq 0) {
	Fail 30 "변경된 대상 파일이 없습니다."
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$patchPath = Join-Path $OutputDir "lastexpress_kor_scummvm.patch"
$listPath = Join-Path $OutputDir "CHANGED_FILES.txt"

$patchBody = [string]::Join("`n`n", $patchChunks) + "`n"
[System.IO.File]::WriteAllText($patchPath, $patchBody, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllLines($listPath, $changedFiles, [System.Text.UTF8Encoding]::new($false))

if ($ValidateApply) {
	Step "clean 트리에 patch apply --check"
	& $git.Source -C $CleanRoot apply --check $patchPath
	if ($LASTEXITCODE -ne 0) {
		Fail 40 "git apply --check 실패"
	}
}

Write-Host ""
Write-Host "Patch generated" -ForegroundColor Green
Write-Host "  Patch : $patchPath"
Write-Host "  Files : $listPath"
Write-Host "  Count : $($changedFiles.Count)"
exit 0
