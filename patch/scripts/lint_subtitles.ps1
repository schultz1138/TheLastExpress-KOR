[CmdletBinding()]
param(
    [string]$WorkspaceRoot = "",
    [string]$InputTsv = "",
    [string]$ReportTsv = "",
    [int]$MaxCharsPerLine = 24,
    [int]$MaxTotalChars = 48,
    [switch]$StrictExit
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

if ($MaxCharsPerLine -lt 1 -or $MaxTotalChars -lt 1) {
    Fail 12 "MaxCharsPerLine / MaxTotalChars must be >= 1."
}

$lines = Get-Content -LiteralPath $InputTsv -Encoding UTF8
$issues = New-Object System.Collections.Generic.List[object]
$dataRows = 0

function Add-Issue([int]$LineNo, [string]$Sbe, [string]$Entry, [string]$Issue, [string]$Detail, [string]$Text) {
    $preview = $Text
    if ($preview.Length -gt 120) {
        $preview = $preview.Substring(0, 117) + "..."
    }
    $preview = $preview.Replace("`t", " ")
    $script:issues.Add([pscustomobject]@{
        line = $LineNo
        sbe = $Sbe
        entry = $Entry
        issue = $Issue
        detail = $Detail
        text = $preview
    })
}

Step "Lint subtitle TSV"

for ($i = 0; $i -lt $lines.Count; $i++) {
    $lineNo = $i + 1
    $line = $lines[$i]

    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line.TrimStart().StartsWith("#")) { continue }

    $parts = $line -split "`t"
    if ($parts.Count -lt 3) {
        Add-Issue $lineNo "" "" "malformed_row" "Less than 3 tab-separated columns" $line
        continue
    }

    if ($parts[1].Trim() -notmatch '^[0-9]+$') {
        # Header row or malformed identifier row.
        continue
    }

    $dataRows += 1
    $sbe = $parts[0].Trim()
    $entry = $parts[1].Trim()

    $translation = ""
    $formatType = "3col"
    if ($parts.Count -ge 6) {
        $formatType = "7col"
        $translation = $parts[5]
        if ($parts.Count -ne 7) {
            Add-Issue $lineNo $sbe $entry "column_count_7col" "Expected 7 columns for template TSV, got $($parts.Count)" $line
        }
    } else {
        if ($parts.Count -gt 3) {
            Add-Issue $lineNo $sbe $entry "extra_tab_3col" "3-column TSV contains extra tabs in translation field" $line
        }
        $translation = ($parts[2..($parts.Count - 1)] -join "`t")
    }

    if ([string]::IsNullOrWhiteSpace($translation)) {
        Add-Issue $lineNo $sbe $entry "empty_translation" "Translation is empty" $translation
        continue
    }

    if ($translation -match '^\s|\s$') {
        Add-Issue $lineNo $sbe $entry "edge_whitespace" "Leading or trailing whitespace in translation" $translation
    }
    if ($translation -match '\\n\s+') {
        Add-Issue $lineNo $sbe $entry "space_after_newline_escape" "Whitespace right after \n escape" $translation
    }

    $escapeMatches = [regex]::Matches($translation, '\\.')
    foreach ($m in $escapeMatches) {
        $esc = $m.Value
        if ($esc -ne '\n' -and $esc -ne '\\') {
            Add-Issue $lineNo $sbe $entry "unsupported_escape" "Unsupported escape sequence: $esc" $translation
        }
    }
    if ($translation.EndsWith("\")) {
        Add-Issue $lineNo $sbe $entry "dangling_backslash" "Translation ends with a single backslash" $translation
    }

    $segments = [regex]::Split($translation, '\\n')
    $lineCount = $segments.Count
    if ($lineCount -gt 2) {
        Add-Issue $lineNo $sbe $entry "line_count_over_2" "Contains $lineCount lines after \n split" $translation
    }

    $maxLen = 0
    foreach ($seg in $segments) {
        if ($seg.Length -gt $maxLen) {
            $maxLen = $seg.Length
        }
        if ($seg.Length -gt $MaxCharsPerLine) {
            Add-Issue $lineNo $sbe $entry "line_too_long" "Line length $($seg.Length) > $MaxCharsPerLine" $translation
        }
    }

    $totalChars = ($segments -join "").Length
    if ($totalChars -gt $MaxTotalChars) {
        Add-Issue $lineNo $sbe $entry "total_too_long" "Total chars $totalChars > $MaxTotalChars" $translation
    }
}

Write-Host "Input      : $InputTsv"
Write-Host "Rows       : $dataRows"
Write-Host "Issues     : $($issues.Count)"

if ($issues.Count -gt 0) {
    Write-Host ""
    Write-Host "Issue counts:"
    $issues |
        Group-Object -Property issue |
        Sort-Object -Property Count -Descending |
        ForEach-Object {
            Write-Host ("  - {0}: {1}" -f $_.Name, $_.Count)
        }
}

if (-not [string]::IsNullOrWhiteSpace($ReportTsv)) {
    $dir = Split-Path -Parent $ReportTsv
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $outLines = New-Object System.Collections.Generic.List[string]
    $outLines.Add("line`tsbe`tentry`tissue`tdetail`ttext")
    foreach ($row in $issues) {
        $outLines.Add(("{0}`t{1}`t{2}`t{3}`t{4}`t{5}" -f
                $row.line,
                $row.sbe,
                $row.entry,
                $row.issue,
                $row.detail,
                $row.text))
    }
    $outText = [string]::Join("`n", $outLines)
    if ($outLines.Count -gt 0) { $outText += "`n" }
    [System.IO.File]::WriteAllText($ReportTsv, $outText, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Report     : $ReportTsv"
}

if ($issues.Count -gt 0 -and $StrictExit) {
    exit 3
}
exit 0
