[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("add", "remove")]
    [string]$Mode,
    [string]$WorkspaceRoot = "",
    [string]$InputTsv = "",
    [string]$OutputTsv = "",
    [switch]$NoBackup
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
        (Join-Path $WorkspaceRoot "translation\subko.tsv"),
        (Join-Path $WorkspaceRoot "translation\kosubs.tsv")
    )) {
        if (Test-Path $candidate) {
            $InputTsv = $candidate
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($InputTsv)) {
    Fail 10 "Input TSV was not found. Pass -InputTsv explicitly."
}
if (-not (Test-Path $InputTsv)) {
    Fail 11 "Input TSV does not exist: $InputTsv"
}

if ([string]::IsNullOrWhiteSpace($OutputTsv)) {
    $OutputTsv = $InputTsv
}

$inPlace = $false
try {
    $inPath = (Resolve-Path -LiteralPath $InputTsv).Path
    $outPath = [System.IO.Path]::GetFullPath($OutputTsv)
    $inPlace = [string]::Equals($inPath, $outPath, [System.StringComparison]::OrdinalIgnoreCase)
} catch {
}

if ($inPlace -and -not $NoBackup) {
    $suffix = if ($Mode -eq "add") { "addreview" } else { "rmreview" }
    $backupPath = "{0}.bak.{1}.{2}" -f $InputTsv, $suffix, (Get-Date -Format "yyyyMMdd_HHmmss")
    Copy-Item -LiteralPath $InputTsv -Destination $backupPath -Force
    Write-Host ("  Backup: {0}" -f $backupPath)
}

Step ("{0} review subtitle IDs" -f ($Mode.ToUpperInvariant()))
$reviewTagPattern = '\s*\[[A-Za-z0-9]+_[0-9]+\]\s*$'

$lines = Get-Content -LiteralPath $InputTsv -Encoding UTF8
$outLines = New-Object System.Collections.Generic.List[string]
$rowCount = 0
$changedCount = 0

foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        $outLines.Add($line)
        continue
    }
    if ($line.TrimStart().StartsWith("#")) {
        $outLines.Add($line)
        continue
    }

    $parts = $line -split "`t", 3
    if ($parts.Count -lt 3) {
        $outLines.Add($line)
        continue
    }
    if ($parts[1].Trim() -notmatch '^[0-9]+$') {
        $outLines.Add($line)
        continue
    }

    $rowCount += 1
    $sbeName = $parts[0].Trim()
    $entryIndex = $parts[1].Trim()
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($sbeName)
    if ([string]::IsNullOrWhiteSpace($baseName)) {
        $baseName = $sbeName
    }
    $idTag = "[{0}_{1}]" -f $baseName.ToUpperInvariant(), $entryIndex

    $fullTr = $parts[2]
    $baseText = [regex]::Replace($fullTr, $reviewTagPattern, '')
    $newTr = $fullTr

    if ($Mode -eq "add") {
        if (-not [string]::IsNullOrWhiteSpace($baseText)) {
            $newTr = $baseText.TrimEnd() + " " + $idTag
        }
    } else {
        $newTr = $baseText.TrimEnd()
    }

    if ($newTr -ne $fullTr) {
        $changedCount += 1
    }

    $outLines.Add(("{0}`t{1}`t{2}" -f $parts[0], $parts[1], $newTr))
}

$outputDir = Split-Path -Parent $OutputTsv
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$textOut = [string]::Join("`n", $outLines)
if ($outLines.Count -gt 0) {
    $textOut += "`n"
}
[System.IO.File]::WriteAllText($OutputTsv, $textOut, [System.Text.UTF8Encoding]::new($false))

Write-Host ("  Input rows : {0}" -f $rowCount)
Write-Host ("  Changed    : {0}" -f $changedCount)
Write-Host ("  Output     : {0}" -f $OutputTsv)
Write-Host ""
Write-Host "toggle_review_subtitle_ids.ps1 complete" -ForegroundColor Green
exit 0
