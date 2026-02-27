[CmdletBinding()]
param(
    [string]$WorkspaceRoot = "",
    [string]$InputTsv = "",
    [string]$OutputTsv = "",
    [int]$MaxCharsPerLine = 24,
    [int]$MaxLines = 2
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

function Get-LineLengths([string]$Text) {
    $segments = [regex]::Split($Text, '\\n')
    $lengths = New-Object System.Collections.Generic.List[int]
    foreach ($seg in $segments) {
        $lengths.Add($seg.Length)
    }
    return @($segments, $lengths)
}

function Get-BestBreakPosition([string]$Text, [int]$MaxCharsPerLine) {
    if ($Text.Length -le $MaxCharsPerLine) {
        return -1
    }

    $bestPos = -1
    $bestScore = [double]::PositiveInfinity

    for ($i = 1; $i -lt $Text.Length; $i++) {
        $leftRaw = $Text.Substring(0, $i)
        $rightRaw = $Text.Substring($i)
        $left = $leftRaw.TrimEnd()
        $right = $rightRaw.TrimStart()
        if ([string]::IsNullOrWhiteSpace($left) -or [string]::IsNullOrWhiteSpace($right)) {
            continue
        }

        $leftLen = $left.Length
        $rightLen = $right.Length
        $leftOverflow = [Math]::Max(0, $leftLen - $MaxCharsPerLine)
        $rightOverflow = [Math]::Max(0, $rightLen - $MaxCharsPerLine)

        $prevChar = $Text[$i - 1]
        $nextChar = $Text[$i]
        $isNaturalBoundary = ($prevChar -match '[\s\.,\?!:;)\]\}]') -or ($nextChar -match '[\s\(\[\{]')
        $boundaryPenalty = if ($isNaturalBoundary) { 0.0 } else { 1.5 }

        $balance = [Math]::Abs($leftLen - $rightLen) / 10.0
        $overflowPenalty = ($leftOverflow + $rightOverflow) * 10.0

        $score = $overflowPenalty + $balance + $boundaryPenalty
        if ($score -lt $bestScore) {
            $bestScore = $score
            $bestPos = $i
        }
    }

    if ($bestPos -ge 1) {
        return $bestPos
    }

    return [Math]::Min($MaxCharsPerLine, $Text.Length - 1)
}

function Suggest-TwoLines([string]$Text, [int]$MaxCharsPerLine) {
    $compact = [regex]::Replace($Text, '\\n', ' ')
    $compact = [regex]::Replace($compact, '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($compact)) {
        return $Text
    }
    if ($compact.Length -le $MaxCharsPerLine) {
        return $compact
    }

    $pos = Get-BestBreakPosition $compact $MaxCharsPerLine
    if ($pos -lt 1) {
        return $compact
    }

    $left = $compact.Substring(0, $pos).TrimEnd()
    $right = $compact.Substring($pos).TrimStart()
    if ([string]::IsNullOrWhiteSpace($left) -or [string]::IsNullOrWhiteSpace($right)) {
        return $compact
    }
    return "$left\n$right"
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
    $dir = Split-Path -Parent $InputTsv
    $base = [System.IO.Path]::GetFileNameWithoutExtension($InputTsv)
    $OutputTsv = Join-Path $dir ($base + ".suggested.tsv")
}

Step "Generate line-break suggestion TSV"

$lines = Get-Content -LiteralPath $InputTsv -Encoding UTF8
$outLines = New-Object System.Collections.Generic.List[string]
$dataRows = 0
$suggestedRows = 0
$unresolvedRows = 0

$reviewTagRegex = '\s*\[[A-Za-z0-9]+_[0-9]+\]\s*$'

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
        $outLines.Add($line)
        continue
    }

    $dataRows += 1
    $newLine = $line

    $is7Col = $parts.Count -ge 6
    $oldTr = if ($is7Col) { $parts[5] } else { ($parts[2..($parts.Count - 1)] -join "`t") }
    $newTr = $oldTr

    if (-not [string]::IsNullOrWhiteSpace($oldTr)) {
        $tagMatch = [regex]::Match($oldTr, $reviewTagRegex)
        $tagText = ""
        $core = $oldTr
        if ($tagMatch.Success) {
            $tagText = $tagMatch.Value.Trim()
            $core = [regex]::Replace($oldTr, $reviewTagRegex, '').TrimEnd()
        }

        $parsed = Get-LineLengths $core
        $segments = [string[]]$parsed[0]
        $lengths = [System.Collections.Generic.List[int]]$parsed[1]
        $needsSuggest = $false

        if ($segments.Count -gt $MaxLines) {
            $needsSuggest = $true
        } else {
            foreach ($len in $lengths) {
                if ($len -gt $MaxCharsPerLine) {
                    $needsSuggest = $true
                    break
                }
            }
        }

        if ($needsSuggest) {
            $coreSuggested = Suggest-TwoLines $core $MaxCharsPerLine
            $newTr = if ([string]::IsNullOrWhiteSpace($tagText)) { $coreSuggested } else { "$coreSuggested $tagText" }
            if ($newTr -ne $oldTr) {
                $suggestedRows += 1
            }

            $checkSuggested = Get-LineLengths $coreSuggested
            $segments2 = [string[]]$checkSuggested[0]
            $lengths2 = [System.Collections.Generic.List[int]]$checkSuggested[1]
            $bad = $segments2.Count -gt $MaxLines
            if (-not $bad) {
                foreach ($len2 in $lengths2) {
                    if ($len2 -gt $MaxCharsPerLine) {
                        $bad = $true
                        break
                    }
                }
            }
            if ($bad) {
                $unresolvedRows += 1
            }
        }
    }

    if ($is7Col) {
        $prefix = $parts[0..4]
        $suffix = @()
        if ($parts.Count -ge 7) { $suffix = $parts[6..($parts.Count - 1)] }
        $newParts = @($prefix + @($newTr) + $suffix)
        $newLine = ($newParts -join "`t")
    } else {
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

Write-Host ("  Rows       : {0}" -f $dataRows)
Write-Host ("  Suggested  : {0}" -f $suggestedRows)
Write-Host ("  Unresolved : {0}" -f $unresolvedRows)
Write-Host ("  Output     : {0}" -f $OutputTsv)
Write-Host ""
Write-Host "suggest_linebreaks.ps1 complete" -ForegroundColor Green
exit 0
