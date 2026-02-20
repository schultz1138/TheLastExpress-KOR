[CmdletBinding()]
param(
    [string]$WorkspaceRoot = "",
    [string]$GameDir = "",
    [string]$OutputBmpDir = "",
    [string]$BgPatchDir = "",
    [string]$NamesFile = "",
    [switch]$AllowMissing,
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
if ([string]::IsNullOrWhiteSpace($OutputBmpDir)) {
    $OutputBmpDir = Join-Path $WorkspaceRoot "translation\output_user"
}
if ([string]::IsNullOrWhiteSpace($BgPatchDir)) {
    $BgPatchDir = Join-Path $WorkspaceRoot "translation\bgpatch"
}

if ([string]::IsNullOrWhiteSpace($GameDir)) {
    Fail 10 "GameDir was not found. Pass -GameDir with your game folder."
}
if (-not (Test-Path $GameDir)) {
    Fail 11 "Game folder does not exist: $GameDir"
}

$baseHpf = Join-Path $GameDir "HD.HPF"
$cd1Hpf = Join-Path $GameDir "CD1.HPF"
$cd2Hpf = Join-Path $GameDir "CD2.HPF"
$cd3Hpf = Join-Path $GameDir "CD3.HPF"
foreach ($path in @($baseHpf, $cd1Hpf, $cd2Hpf, $cd3Hpf)) {
    if (-not (Test-Path $path)) {
        Fail 12 "Required archive not found: $path"
    }
}

$extractSelectedScript = Join-Path $WorkspaceRoot "tools\hpf_extract_selected.py"
$bgToBmpScript = Join-Path $WorkspaceRoot "tools\bg_to_bmp.py"
foreach ($path in @($extractSelectedScript, $bgToBmpScript)) {
    if (-not (Test-Path $path)) {
        Fail 13 "Required tool not found: $path"
    }
}

$py = Get-Command py -ErrorAction SilentlyContinue
if (-not $py) {
    $py = Get-Command python -ErrorAction SilentlyContinue
}
if (-not $py) {
    Fail 14 "Python launcher 'py' or 'python' was not found."
}

$bgNames = New-Object System.Collections.Generic.List[string]
if (-not [string]::IsNullOrWhiteSpace($NamesFile)) {
    if (-not (Test-Path $NamesFile)) {
        Fail 15 "Names file not found: $NamesFile"
    }
    foreach ($line in Get-Content -Path $NamesFile -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $name = $line.Trim().ToUpperInvariant()
        if (-not $name.EndsWith(".BG")) {
            $name = "$name.BG"
        }
        $bgNames.Add($name)
    }
} else {
    $manifestPath = Join-Path $BgPatchDir "manifest.json"
    if (-not (Test-Path $manifestPath)) {
        Fail 16 "Manifest not found: $manifestPath (pass -NamesFile to provide targets manually)"
    }

    $manifest = Get-Content -Path $manifestPath -Encoding UTF8 | ConvertFrom-Json
    if (-not $manifest.entries) {
        Fail 17 "No entries found in manifest: $manifestPath"
    }

    foreach ($entry in $manifest.entries) {
        $name = [string]$entry.name
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }
        $name = $name.Trim().ToUpperInvariant()
        if (-not $name.EndsWith(".BG")) {
            $name = "$name.BG"
        }
        $bgNames.Add($name)
    }
}

$bgNames = @($bgNames | Sort-Object -Unique)
if ($bgNames.Count -eq 0) {
    Fail 18 "No BG names to extract."
}

$workDir = Join-Path $WorkspaceRoot "translation\_work_extract_bg"
$extractDir = Join-Path $workDir "bg_raw"
$nameListPath = Join-Path $workDir "bg_names.txt"

Step "Prepare work directory"
if (Test-Path $workDir) {
    Remove-Item -Recurse -Force $workDir
}
New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
New-Item -ItemType Directory -Path $OutputBmpDir -Force | Out-Null
[System.IO.File]::WriteAllLines($nameListPath, $bgNames, [System.Text.UTF8Encoding]::new($false))

Step "Extract BG files from HPF"
$extractArgs = @(
    $extractDir,
    "--archives",
    $baseHpf,
    $cd1Hpf,
    $cd2Hpf,
    $cd3Hpf,
    "--names-file",
    $nameListPath
)
if (-not $AllowMissing) {
    $extractArgs += "--strict"
}
& $py.Source $extractSelectedScript @extractArgs
if ($LASTEXITCODE -ne 0) {
    Fail 20 "BG extract failed (exit code: $LASTEXITCODE)"
}

Step "Convert BG -> BMP"
& $py.Source $bgToBmpScript $extractDir $OutputBmpDir
if ($LASTEXITCODE -ne 0) {
    Fail 21 "BG conversion failed (exit code: $LASTEXITCODE)"
}

if (-not $KeepWorkDir) {
    Step "Cleanup work directory"
    Remove-Item -Recurse -Force $workDir
}

Write-Host ""
Write-Host "extract_bg_templates.ps1 complete" -ForegroundColor Green
Write-Host "Output BMP dir: $OutputBmpDir"
exit 0
