[CmdletBinding()]
param(
    [string]$WorkspaceRoot = "",
    [string]$InputTsv = "",
    [string]$OutputTsv = "",
    [switch]$NoBackup,
    [switch]$NoCollapseSpaces
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

function Normalize-SubtitleText([string]$Text, [bool]$CollapseSpaces) {
    $segments = [regex]::Split($Text, '\\n')
    $normalized = New-Object System.Collections.Generic.List[string]
    foreach ($seg in $segments) {
        $s = $seg.Replace("`t", " ").Trim()
        if ($CollapseSpaces) {
            $s = [regex]::Replace($s, ' {2,}', ' ')
        }
        $normalized.Add($s)
    }
    return [string]::Join('\n', $normalized)
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
    $backupPath = "{0}.bak.normalize.{1}" -f $InputTsv, (Get-Date -Format "yyyyMMdd_HHmmss")
    Copy-Item -LiteralPath $InputTsv -Destination $backupPath -Force
    Write-Host ("  Backup: {0}" -f $backupPath)
}

Step "Normalize subtitle text"

$collapseSpaces = -not $NoCollapseSpaces
$lines = Get-Content -LiteralPath $InputTsv -Encoding UTF8
$outLines = New-Object System.Collections.Generic.List[string]
$dataRows = 0
$changedRows = 0

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#")) {
        $outLines.Add($line)
        continue
    }

    $parts = $line -split "`t"
    if ($parts.Count -lt 3) {
        $outLines.Add($line)
        continue
    }
    if ($parts[1].Trim() -notmatch '^[0-9]+$') {
        # Header
        $outLines.Add($line)
        continue
    }

    $dataRows += 1
    $newLine = $line

    if ($parts.Count -ge 6) {
        # 7-col template format: sbe, entry, start, end, full-src, full-tr, snd
        $oldTr = $parts[5]
        $newTr = Normalize-SubtitleText $oldTr $collapseSpaces
        if ($newTr -ne $oldTr) {
            $changedRows += 1
        }

        $prefix = $parts[0..4]
        $suffix = @()
        if ($parts.Count -ge 7) {
            $suffix = $parts[6..($parts.Count - 1)]
        }
        $newParts = @($prefix + @($newTr) + $suffix)
        $newLine = ($newParts -join "`t")
    } else {
        # 3-col runtime format: sbe, entry, full-tr
        $oldTr = ($parts[2..($parts.Count - 1)] -join "`t")
        $newTr = Normalize-SubtitleText $oldTr $collapseSpaces
        if ($newTr -ne $oldTr) {
            $changedRows += 1
        }
        $newLine = ("{0}`t{1}`t{2}" -f $parts[0], $parts[1], $newTr)
    }

    $outLines.Add($newLine)
}

$outDir = Split-Path -Parent $OutputTsv
if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$outText = [string]::Join("`n", $outLines)
if ($outLines.Count -gt 0) { $outText += "`n" }
[System.IO.File]::WriteAllText($OutputTsv, $outText, [System.Text.UTF8Encoding]::new($false))

Write-Host ("  Rows    : {0}" -f $dataRows)
Write-Host ("  Changed : {0}" -f $changedRows)
Write-Host ("  Output  : {0}" -f $OutputTsv)
Write-Host ""
Write-Host "normalize_subtitles.ps1 complete" -ForegroundColor Green
exit 0
