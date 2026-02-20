[CmdletBinding()]
param(
    [string]$WorkspaceRoot = "",
    [string]$GameDir = "",
    [string]$KoOverrideDir = "",
    [string]$OutputHpf = "",
    [string]$WorkDir = "",
    [string]$BgPatchDir = "",
    [string]$CustomBmpDir = "",
    [string]$ModedHpf = "",
    [string]$SubtitleTsv = "",
    [switch]$AllowSeedOnly,
    [switch]$AllowSubtitleOnly,
    [switch]$KeepWorkDir
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
    $GameDir = Join-Path $WorkspaceRoot "lastexpress"
}
if ([string]::IsNullOrWhiteSpace($KoOverrideDir)) {
    $KoOverrideDir = Join-Path $WorkspaceRoot "overlay_in"
}
if ([string]::IsNullOrWhiteSpace($OutputHpf)) {
    $OutputHpf = Join-Path $GameDir "KOREAN.HPF"
}
if ([string]::IsNullOrWhiteSpace($WorkDir)) {
    $WorkDir = Join-Path $WorkspaceRoot "translation\_work_korean_hpf"
}
if ([string]::IsNullOrWhiteSpace($BgPatchDir)) {
    $BgPatchDir = Join-Path $WorkspaceRoot "translation\bgpatch"
}
if ([string]::IsNullOrWhiteSpace($CustomBmpDir)) {
    $CustomBmpDir = Join-Path $WorkspaceRoot "translation\output"
}
if ([string]::IsNullOrWhiteSpace($SubtitleTsv)) {
    $subtitleCandidates = @(
        (Join-Path $WorkspaceRoot "translation\kosubs.user.tsv"),
        (Join-Path $WorkspaceRoot "translation\subko.tsv"),
        (Join-Path $WorkspaceRoot "translation\kosubs.tsv")
    )
    foreach ($candidate in $subtitleCandidates) {
        if (Test-Path $candidate) {
            $SubtitleTsv = $candidate
            break
        }
    }
}

if ($AllowSeedOnly) {
    Write-Host "[WARN] -AllowSeedOnly is currently unused." -ForegroundColor Yellow
}

$baseHpf = Join-Path $GameDir "HD.HPF"
$cd1Hpf = Join-Path $GameDir "CD1.HPF"
$cd2Hpf = Join-Path $GameDir "CD2.HPF"
$cd3Hpf = Join-Path $GameDir "CD3.HPF"
$templateArchives = @($baseHpf, $cd1Hpf, $cd2Hpf, $cd3Hpf)

$py = Get-Command py -ErrorAction SilentlyContinue
if (-not $py) {
    $py = Get-Command python -ErrorAction SilentlyContinue
}
if (-not $py) {
    Fail 10 "Python launcher 'py' or 'python' was not found."
}

$packScript = Join-Path $WorkspaceRoot "tools\hpf_pack.py"
$validateScript = Join-Path $WorkspaceRoot "tools\validate_korean_hpf.py"
$bmpToBgScript = Join-Path $WorkspaceRoot "tools\bmp_to_bg.py"
$unpackScript = Join-Path $WorkspaceRoot "tools\hpf_unpack.py"
$extractSelectedScript = Join-Path $WorkspaceRoot "tools\hpf_extract_selected.py"
$applyPatchsetScript = Join-Path $WorkspaceRoot "tools\apply_bg_patchset.py"

foreach ($path in @($packScript, $validateScript, $bmpToBgScript, $unpackScript, $extractSelectedScript, $applyPatchsetScript)) {
    if (-not (Test-Path $path)) {
        Fail 11 "Required file not found: $path"
    }
}
if ([string]::IsNullOrWhiteSpace($SubtitleTsv)) {
    Fail 11 "Subtitle source TSV not found. Expected one of: translation\\kosubs.user.tsv, translation\\subko.tsv, translation\\kosubs.tsv"
}
if (-not (Test-Path $SubtitleTsv)) {
    Fail 11 "Subtitle source TSV not found: $SubtitleTsv"
}

if (-not (Test-Path $GameDir)) {
    Fail 12 "Game directory was not found: $GameDir"
}

$hasAllArchives = $true
foreach ($arc in $templateArchives) {
    if (-not (Test-Path $arc)) {
        $hasAllArchives = $false
        Write-Host "[WARN] Missing archive: $arc" -ForegroundColor Yellow
    }
}
if (-not (Test-Path $baseHpf)) {
    Write-Host "[WARN] Base HPF not found for validation compare: $baseHpf" -ForegroundColor Yellow
}

if ((Test-Path $KoOverrideDir) -and -not (Get-Item $KoOverrideDir).PSIsContainer) {
    Fail 13 "KoOverrideDir must be a directory: $KoOverrideDir"
}

$stageDir = Join-Path $WorkDir "overlay_stage"
$templateDir = Join-Path $WorkDir "template_bg"

Step "Prepare work directory"
if (Test-Path $WorkDir) {
    Remove-Item -Recurse -Force $WorkDir
}
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
New-Item -ItemType Directory -Path $templateDir -Force | Out-Null

Step ("Generate subtitle runtime data ({0} -> SUBKO.TSV)" -f [System.IO.Path]::GetFileName($SubtitleTsv))
$subkoOut = Join-Path $stageDir "SUBKO.TSV"
$subkoLines = New-Object System.Collections.Generic.List[string]
foreach ($line in Get-Content -Path $SubtitleTsv -Encoding UTF8) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }
    if ($line.TrimStart().StartsWith("#")) {
        continue
    }
    $parts = $line -split "`t"
    if ($parts.Count -lt 3) {
        continue
    }
    if ($parts[1] -notmatch '^[0-9]+$') {
        continue
    }
    if ($parts.Count -ge 6) {
        $subkoLines.Add(("{0}`t{1}`t{2}" -f $parts[0], $parts[1], $parts[5]))
    } else {
        $subkoLines.Add(("{0}`t{1}`t{2}" -f $parts[0], $parts[1], $parts[2]))
    }
}
$subkoText = [string]::Join("`n", $subkoLines)
if ($subkoLines.Count -gt 0) {
    $subkoText += "`n"
}
[System.IO.File]::WriteAllText($subkoOut, $subkoText, [System.Text.UTF8Encoding]::new($false))

if ([string]::IsNullOrWhiteSpace($ModedHpf)) {
    $modedCandidates = @(
        (Join-Path $GameDir "Moded_HD.HPF"),
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

if (-not [string]::IsNullOrWhiteSpace($ModedHpf)) {
    if (-not (Test-Path $ModedHpf)) {
        Fail 14 "Moded HD archive not found: $ModedHpf"
    }

    Step "Seed SBE data from Moded_HD.HPF"
    $modedExtractDir = Join-Path $WorkDir "moded_extract"
    New-Item -ItemType Directory -Path $modedExtractDir -Force | Out-Null
    & $py.Source $unpackScript $ModedHpf $modedExtractDir
    if ($LASTEXITCODE -ne 0) {
        Fail 15 "hpf_unpack.py failed while reading Moded HD archive (exit code: $LASTEXITCODE)"
    }

    $sbeFiles = Get-ChildItem -Path $modedExtractDir -File -Filter *.SBE
    foreach ($sbe in $sbeFiles) {
        Copy-Item -Path $sbe.FullName -Destination (Join-Path $stageDir $sbe.Name) -Force
    }
    Write-Host ("  Seeded SBE files: {0}" -f $sbeFiles.Count)
} else {
    Write-Host "[WARN] Moded_HD.HPF not found. Some spoken lines may not show subtitles." -ForegroundColor Yellow
}

$appliedGraphics = $false
$patchManifest = Join-Path $BgPatchDir "manifest.json"
if (Test-Path $patchManifest) {
    Step "Apply BG patchset"
    if (-not $hasAllArchives) {
        Fail 26 "Applying BG patchset requires HD.HPF and CD1~CD3.HPF."
    }
    & $py.Source $applyPatchsetScript --game-dir $GameDir --patch-dir $BgPatchDir --out-dir $stageDir --strict-hash
    if ($LASTEXITCODE -ne 0) {
        Fail 27 "apply_bg_patchset.py failed (exit code: $LASTEXITCODE)"
    }
    $appliedGraphics = $true
} elseif (Test-Path $CustomBmpDir) {
    Step "Convert BMP overlays to BG"
    if (-not $hasAllArchives) {
        Fail 28 "BMP conversion requires HD.HPF and CD1~CD3.HPF."
    }

    $bmps = Get-ChildItem -Path $CustomBmpDir -File | Where-Object { $_.Extension -ieq ".bmp" }
    if ($bmps.Count -gt 0) {
        $bgNames = New-Object System.Collections.Generic.List[string]
        foreach ($bmp in $bmps) {
            $bgNames.Add(("{0}.BG" -f [System.IO.Path]::GetFileNameWithoutExtension($bmp.Name).ToUpperInvariant()))
        }
        $bgNames = @($bgNames | Sort-Object -Unique)
        $bgListPath = Join-Path $WorkDir "bg_names.txt"
        [System.IO.File]::WriteAllLines($bgListPath, $bgNames, [System.Text.UTF8Encoding]::new($false))

        $extractArgs = @(
            $templateDir,
            "--archives",
            $baseHpf,
            $cd1Hpf,
            $cd2Hpf,
            $cd3Hpf,
            "--names-file",
            $bgListPath,
            "--strict"
        )
        & $py.Source $extractSelectedScript @extractArgs
        if ($LASTEXITCODE -ne 0) {
            Fail 29 "hpf_extract_selected.py failed (exit code: $LASTEXITCODE)"
        }

        foreach ($bmp in $bmps) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($bmp.Name).ToUpperInvariant()
            $templateBg = Join-Path $templateDir "$baseName.BG"
            $outBg = Join-Path $stageDir "$baseName.BG"
            & $py.Source $bmpToBgScript $bmp.FullName $outBg --template-bg $templateBg
            if ($LASTEXITCODE -ne 0) {
                Fail 30 "BMP->BG conversion failed: $($bmp.Name)"
            }
        }
        $appliedGraphics = $true
    }
}

if (-not $appliedGraphics) {
    if ($AllowSubtitleOnly) {
        Write-Host "[INFO] Building subtitle-only KOREAN.HPF (no graphic overrides)." -ForegroundColor Yellow
    } else {
        Fail 31 "No graphic input found. Provide translation/bgpatch or translation/output, or use -AllowSubtitleOnly."
    }
}

Step "Merge font and optional overrides"
$foundFont = $false
foreach ($fontPath in @(
    (Join-Path $GameDir "Korean.TTF"),
    (Join-Path $WorkspaceRoot "Korean.TTF"),
    (Join-Path $KoOverrideDir "Korean.TTF")
)) {
    if (Test-Path $fontPath) {
        Copy-Item -Path $fontPath -Destination $stageDir -Force
        Write-Host "  Included font: $fontPath"
        $foundFont = $true
        break
    }
}
if (-not $foundFont) {
    Write-Host "  [INFO] Korean.TTF not found. User-provided font remains optional." -ForegroundColor Yellow
}

if (Test-Path $KoOverrideDir) {
    $overrideFiles = @(Get-ChildItem -Path $KoOverrideDir -File -Recurse)
    foreach ($f in $overrideFiles) {
        if ($f.Name -ieq "Korean.TTF") {
            continue
        }
        $dest = Join-Path $stageDir $f.Name
        Copy-Item -Path $f.FullName -Destination $dest -Force
    }
    Write-Host "  Copied additional override files"
}

Step "Pack KOREAN.HPF"
if (-not (Test-Path (Split-Path $OutputHpf))) {
    New-Item -ItemType Directory -Path (Split-Path $OutputHpf) -Force | Out-Null
}
if (Test-Path $OutputHpf) {
    $backupPath = "$OutputHpf.bak.$(Get-Date -Format yyyyMMdd_HHmmss)"
    Copy-Item -Path $OutputHpf -Destination $backupPath -Force
}
& $py.Source $packScript $stageDir $OutputHpf
if ($LASTEXITCODE -ne 0) {
    Fail 40 "hpf_pack.py failed (exit code: $LASTEXITCODE)"
}

Step "Validate KOREAN.HPF"
if (Test-Path $baseHpf) {
    & $py.Source $validateScript $OutputHpf --base-hpf $baseHpf
} else {
    & $py.Source $validateScript $OutputHpf
}
if ($LASTEXITCODE -ne 0) {
    Fail 50 "validate_korean_hpf.py failed (exit code: $LASTEXITCODE)"
}

if (-not $KeepWorkDir) {
    Step "Cleanup work directory"
    Remove-Item -Recurse -Force $WorkDir
}

Write-Host ""
Write-Host "build_korean_hpf_from_moded.ps1 complete" -ForegroundColor Green
Write-Host "Output: $OutputHpf"
exit 0
