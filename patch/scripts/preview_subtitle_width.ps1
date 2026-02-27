[CmdletBinding()]
param(
    [string]$WorkspaceRoot = "",
    [string]$InputTsv = "",
    [string]$FontPath = "",
    [float]$FontSize = 14.0,
    [int]$MaxCharsPerLine = 24,
    [int]$MaxLines = 2,
    [double]$MaxWidthPx = 0,
    [string]$ReportTsv = ""
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

if ([string]::IsNullOrWhiteSpace($FontPath)) {
    foreach ($candidate in @(
        (Join-Path $WorkspaceRoot "runtime\korean.ttf"),
        (Join-Path $WorkspaceRoot "korean.ttf")
    )) {
        if (Test-Path $candidate) {
            $FontPath = $candidate
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($FontPath) -or -not (Test-Path $FontPath)) {
    Fail 12 "Font file not found. Pass -FontPath explicitly."
}

if ([string]::IsNullOrWhiteSpace($ReportTsv)) {
    $ReportTsv = Join-Path $WorkspaceRoot "translation\subtitle_width_report.tsv"
}

Step "Preview subtitle line width with font metrics"

try {
    Add-Type -AssemblyName System.Drawing
} catch {
    Fail 13 "System.Drawing assembly is not available in this PowerShell environment."
}

$fontCollection = $null
$font = $null
$bitmap = $null
$graphics = $null
$stringFormat = $null

try {
    $fontCollection = New-Object System.Drawing.Text.PrivateFontCollection
    $fontCollection.AddFontFile((Resolve-Path -LiteralPath $FontPath).Path)
    if ($fontCollection.Families.Count -eq 0) {
        Fail 14 "Failed to load font family from: $FontPath"
    }

    $font = New-Object System.Drawing.Font($fontCollection.Families[0], $FontSize, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $bitmap = New-Object System.Drawing.Bitmap(1, 1)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $stringFormat = [System.Drawing.StringFormat]::GenericTypographic

    function Measure-TextWidth([string]$Text) {
        if ([string]::IsNullOrEmpty($Text)) { return 0.0 }
        $size = $graphics.MeasureString($Text, $font, [int]::MaxValue, $stringFormat)
        return [double]$size.Width
    }

    if ($MaxWidthPx -le 0) {
        $ref = ("가" * $MaxCharsPerLine)
        $MaxWidthPx = Measure-TextWidth $ref
    }

    $rows = Get-Content -LiteralPath $InputTsv -Encoding UTF8
    $issues = New-Object System.Collections.Generic.List[object]
    $dataRows = 0

    for ($i = 0; $i -lt $rows.Count; $i++) {
        $lineNo = $i + 1
        $line = $rows[$i]
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#")) { continue }

        $parts = $line -split "`t"
        if ($parts.Count -lt 3) { continue }
        if ($parts[1].Trim() -notmatch '^[0-9]+$') { continue }

        $dataRows += 1
        $sbe = $parts[0].Trim()
        $entry = $parts[1].Trim()
        $text = if ($parts.Count -ge 6) { $parts[5] } else { ($parts[2..($parts.Count - 1)] -join "`t") }
        if ([string]::IsNullOrWhiteSpace($text)) { continue }

        $segments = [regex]::Split($text, '\\n')
        $lineCount = $segments.Count
        $maxChars = 0
        $maxWidth = 0.0
        foreach ($seg in $segments) {
            $trimSeg = $seg
            if ($trimSeg.Length -gt $maxChars) { $maxChars = $trimSeg.Length }
            $w = Measure-TextWidth $trimSeg
            if ($w -gt $maxWidth) { $maxWidth = $w }
        }

        $overflowPx = $maxWidth - $MaxWidthPx
        $overflow = ($lineCount -gt $MaxLines) -or ($maxChars -gt $MaxCharsPerLine) -or ($overflowPx -gt 0.01)
        if ($overflow) {
            $preview = $text
            if ($preview.Length -gt 100) { $preview = $preview.Substring(0, 97) + "..." }
            $preview = $preview.Replace("`t", " ")
            $issues.Add([pscustomobject]@{
                line = $lineNo
                sbe = $sbe
                entry = $entry
                lines = $lineCount
                max_chars = $maxChars
                max_width_px = [Math]::Round($maxWidth, 2)
                width_limit_px = [Math]::Round($MaxWidthPx, 2)
                overflow_px = [Math]::Round([Math]::Max(0.0, $overflowPx), 2)
                text = $preview
            })
        }
    }

    Write-Host "Input         : $InputTsv"
    Write-Host "Font          : $FontPath"
    Write-Host "Font size(px) : $FontSize"
    Write-Host "Width limit   : $([Math]::Round($MaxWidthPx, 2)) px"
    Write-Host "Rows          : $dataRows"
    Write-Host "Overflow rows : $($issues.Count)"

    $outDir = Split-Path -Parent $ReportTsv
    if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    $outLines = New-Object System.Collections.Generic.List[string]
    $outLines.Add("line`tsbe`tentry`tlines`tmax_chars`tmax_width_px`twidth_limit_px`toverflow_px`ttext")
    foreach ($r in $issues) {
        $outLines.Add(("{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`t{7}`t{8}" -f
                $r.line, $r.sbe, $r.entry, $r.lines, $r.max_chars, $r.max_width_px, $r.width_limit_px, $r.overflow_px, $r.text))
    }
    $outText = [string]::Join("`n", $outLines)
    if ($outLines.Count -gt 0) { $outText += "`n" }
    [System.IO.File]::WriteAllText($ReportTsv, $outText, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Report        : $ReportTsv"
    Write-Host ""
    Write-Host "preview_subtitle_width.ps1 complete" -ForegroundColor Green
} finally {
    if ($stringFormat) { $stringFormat.Dispose() }
    if ($graphics) { $graphics.Dispose() }
    if ($bitmap) { $bitmap.Dispose() }
    if ($font) { $font.Dispose() }
    if ($fontCollection) { $fontCollection.Dispose() }
}

exit 0
