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
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit $Code
}

function Resolve-PythonExe([string]$RootPath) {
    foreach ($exe in @(
        (Join-Path $RootPath "runtime\python\python.exe"),
        (Join-Path $RootPath "python\python.exe")
    )) {
        if (-not (Test-Path $exe)) {
            continue
        }
        try {
            & $exe -c "import sys" *> $null
            if ($LASTEXITCODE -eq 0) {
                return $exe
            }
        } catch {
        }
    }

    foreach ($name in @("py", "python", "python3")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq "Application" } | Select-Object -First 1
        if (-not $cmd) {
            continue
        }

        $exe = [string]$cmd.Source
        if ([string]::IsNullOrWhiteSpace($exe)) {
            continue
        }
        if ($exe -match '\\Microsoft\\WindowsApps\\') {
            continue
        }

        try {
            & $exe -c "import sys" *> $null
            if ($LASTEXITCODE -eq 0) {
                return $exe
            }
        } catch {
        }
    }
    return $null
}

function Resolve-ArchivePath([string]$GameRoot, [string]$FileName) {
    $candidates = @(
        (Join-Path $GameRoot $FileName),
        (Join-Path $GameRoot ("data\{0}" -f $FileName)),
        (Join-Path $GameRoot ("Data\{0}" -f $FileName))
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }
    return $candidates[0]
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

$baseHpf = Resolve-ArchivePath $GameDir "HD.HPF"
$cd1Hpf = Resolve-ArchivePath $GameDir "CD1.HPF"
$cd2Hpf = Resolve-ArchivePath $GameDir "CD2.HPF"
$cd3Hpf = Resolve-ArchivePath $GameDir "CD3.HPF"
foreach ($path in @($baseHpf, $cd1Hpf, $cd2Hpf, $cd3Hpf)) {
    if (-not (Test-Path $path)) {
        Fail 12 "Required archive not found (searched root/data/Data): $path"
    }
}

$extractSelectedScript = Join-Path $WorkspaceRoot "tools\hpf_extract_selected.py"
$bgToBmpScript = Join-Path $WorkspaceRoot "tools\bg_to_bmp.py"
foreach ($path in @($extractSelectedScript, $bgToBmpScript)) {
    if (-not (Test-Path $path)) {
        Fail 13 "Required tool not found: $path"
    }
}

$pythonExe = Resolve-PythonExe $WorkspaceRoot
if ([string]::IsNullOrWhiteSpace($pythonExe)) {
    Fail 14 "Python 3 runtime not available. Install Python 3, or use a release package that includes runtime\python\python.exe."
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
& $pythonExe $extractSelectedScript @extractArgs
if ($LASTEXITCODE -ne 0) {
    Fail 20 "BG extract failed (exit code: $LASTEXITCODE)"
}

Step "Convert BG -> BMP"
& $pythonExe $bgToBmpScript $extractDir $OutputBmpDir
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
