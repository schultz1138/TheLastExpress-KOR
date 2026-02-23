[CmdletBinding()]
param(
    [string]$WorkspaceRoot = "",
    [string]$CustomBuildDir = "",
    [string]$OutputZip = "",
    [switch]$IncludeSourceFiles
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

$repoRoot = (Resolve-Path (Join-Path $WorkspaceRoot "..")).Path

function Copy-IfExists([string]$SourcePath, [string]$DestPath, [switch]$Required) {
    if (-not (Test-Path $SourcePath)) {
        if ($Required) {
            Fail 20 "Required file not found: $SourcePath"
        }
        return
    }
    $destDir = Split-Path $DestPath -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    Copy-Item -Path $SourcePath -Destination $DestPath -Force
}

function Resolve-FirstExisting([string[]]$Candidates) {
    foreach ($path in $Candidates) {
        if (Test-Path $path) {
            return $path
        }
    }
    return $null
}

if ([string]::IsNullOrWhiteSpace($CustomBuildDir)) {
    $CustomBuildDir = Join-Path $WorkspaceRoot "runtime"
}
if ([string]::IsNullOrWhiteSpace($OutputZip)) {
    $stamp = Get-Date -Format "yyyyMMdd"
    $OutputZip = Join-Path $WorkspaceRoot ("dist\TheLastExpress-KoreanEdition-{0}.zip" -f $stamp)
}

if (-not (Test-Path $CustomBuildDir)) {
    Fail 10 "CustomBuildDir was not found: $CustomBuildDir"
}

$distDir = Split-Path $OutputZip -Parent
if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}

$stageDir = Join-Path $distDir "_release_stage"
if (Test-Path $stageDir) {
    Remove-Item -Recurse -Force $stageDir
}
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

Step "Copy runtime files"
$runtimeExeSrc = Resolve-FirstExisting @(
    (Join-Path $CustomBuildDir "scummvm_k.exe"),
    (Join-Path $CustomBuildDir "scummvm.exe")
)
if (-not $runtimeExeSrc) {
    Fail 20 "Required runtime executable not found in $CustomBuildDir (expected scummvm_k.exe or scummvm.exe)"
}

$runtimeIniSrc = Resolve-FirstExisting @(
    (Join-Path $CustomBuildDir "scummvm_k.ini"),
    (Join-Path $CustomBuildDir "scummvm.ini")
)
$runtimeFontSrc = Resolve-FirstExisting @(
    (Join-Path $CustomBuildDir "korean.ttf")
)
$runtimeIconSrc = Resolve-FirstExisting @(
    (Join-Path $CustomBuildDir "lastexpress.ico"),
    (Join-Path $WorkspaceRoot "runtime\lastexpress.ico")
)
if (-not $runtimeIconSrc) {
    Fail 20 "Required icon file not found (expected lastexpress.ico)"
}

Copy-IfExists $runtimeExeSrc (Join-Path $stageDir ("runtime\{0}" -f (Split-Path $runtimeExeSrc -Leaf))) -Required
Copy-IfExists (Join-Path $CustomBuildDir "start.bat") (Join-Path $stageDir "runtime\start.bat")
Copy-IfExists (Join-Path $CustomBuildDir "config.bat") (Join-Path $stageDir "runtime\config.bat")
if ($runtimeIniSrc) {
    Copy-IfExists $runtimeIniSrc (Join-Path $stageDir ("runtime\{0}" -f (Split-Path $runtimeIniSrc -Leaf)))
}
if ($runtimeFontSrc) {
    Copy-IfExists $runtimeFontSrc (Join-Path $stageDir ("runtime\{0}" -f (Split-Path $runtimeFontSrc -Leaf)))
}
Copy-IfExists $runtimeIconSrc (Join-Path $stageDir "runtime\lastexpress.ico") -Required
Get-ChildItem -Path $CustomBuildDir -Filter *.dll -File | ForEach-Object {
    Copy-IfExists $_.FullName (Join-Path $stageDir ("runtime\{0}" -f $_.Name)) -Required
}

Step "Copy patcher files"
$patchFiles = @(
    "patch_and_install.bat",
    "translation\prepare_edit_workspace.bat",
    "translation\TRANSLATION_README.md",
    "scripts\apply_korean_patch.ps1",
    "scripts\build_korean_hpf.ps1",
    "scripts\extract_subtitle_template.ps1",
    "scripts\extract_bg_templates.ps1",
    "tools\extract_kosubs_template.py",
    "tools\bmp_to_bg.py",
    "tools\bg_to_bmp.py",
    "tools\build_bg_patchset.py",
    "tools\hpf_pack.py",
    "tools\hpf_unpack.py",
    "tools\validate_korean_hpf.py",
    "tools\hpf_extract_selected.py",
    "tools\apply_bg_patchset.py",
    "translation\subko.tsv",
    "README.md"
)
foreach ($rel in $patchFiles) {
    $src = Join-Path $WorkspaceRoot $rel
    $dst = Join-Path $stageDir $rel
    Copy-IfExists $src $dst -Required
}

$licensesDir = Join-Path $WorkspaceRoot "licenses"
if (Test-Path $licensesDir) {
    Step "Copy license files"
    Copy-Item -Path $licensesDir -Destination (Join-Path $stageDir "licenses") -Recurse -Force
}

$embeddedPythonDir = Join-Path $WorkspaceRoot "runtime\python"
if (Test-Path (Join-Path $embeddedPythonDir "python.exe")) {
    Step "Copy embedded Python runtime"
    Copy-Item -Path $embeddedPythonDir -Destination (Join-Path $stageDir "runtime\python") -Recurse -Force
} else {
    Fail 21 "Embedded Python runtime not found: $embeddedPythonDir\\python.exe"
}

$bgPatchDir = Join-Path $WorkspaceRoot "translation\bgpatch"
if (Test-Path (Join-Path $bgPatchDir "manifest.json")) {
    New-Item -ItemType Directory -Path (Join-Path $stageDir "translation\bgpatch") -Force | Out-Null
    Copy-Item -Path (Join-Path $bgPatchDir "*") -Destination (Join-Path $stageDir "translation\bgpatch") -Recurse -Force
} else {
    Write-Host "[WARN] translation/bgpatch/manifest.json is missing. Subtitle-only release will be built." -ForegroundColor Yellow
}

if ($IncludeSourceFiles) {
    Step "Copy source patch files"
    $sourceItems = @(
        "engine\patches",
        "engine\scripts",
        "engine\DEV_README.md",
        "engine\PUBLISH_CHECKLIST.md",
        "engine\SNAPSHOT_WORKFLOW.md",
        "README.md"
    )
    foreach ($rel in $sourceItems) {
        $src = Join-Path $repoRoot $rel
        if (Test-Path $src) {
            $dst = Join-Path $stageDir $rel
            if ((Get-Item $src).PSIsContainer) {
                Copy-Item -Path $src -Destination $dst -Recurse -Force
            } else {
                Copy-IfExists $src $dst -Required
            }
        }
    }
}

Step "Run forbidden-asset check"
$forbidden = @(
    "HD.HPF",
    "CD1.HPF",
    "CD2.HPF",
    "CD3.HPF",
    "HD_ALLSUBS.HPF",
    "kosubs.tsv",
    "*.BMP"
)
$hits = @()
foreach ($pattern in $forbidden) {
    $matches = Get-ChildItem -Path $stageDir -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue
    foreach ($m in $matches) {
        $hits += $m.FullName
    }
}
if ($hits.Count -gt 0) {
    $sample = ($hits | Select-Object -First 10) -join "`n"
    Fail 30 "Forbidden assets were found in release stage.`n$sample"
}

Step "Build ZIP package"
if (Test-Path $OutputZip) {
    Remove-Item -Path $OutputZip -Force
}
Compress-Archive -Path (Join-Path $stageDir "*") -DestinationPath $OutputZip -CompressionLevel Optimal

$zipSize = (Get-Item $OutputZip).Length
$fileCount = (Get-ChildItem -Path $stageDir -Recurse -File).Count

Write-Host ""
Write-Host "Release package created" -ForegroundColor Green
Write-Host "  ZIP   : $OutputZip"
Write-Host "  Files : $fileCount"
Write-Host ("  Size  : {0:N0} bytes" -f $zipSize)

Remove-Item -Recurse -Force $stageDir
exit 0
