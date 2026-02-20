[CmdletBinding()]
param(
	[string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
	[string]$ModedHpf = "",
	[string]$KoOverrideDir = "",
	[string]$OutputHpf = "",
	[string]$BaseHpf = "",
	[string]$WorkDir = "",
	[switch]$AllowSeedOnly,
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

if ([string]::IsNullOrWhiteSpace($ModedHpf)) {
	$ModedHpf = Join-Path $WorkspaceRoot "translation\Moded_HD.HPF"
}
if ([string]::IsNullOrWhiteSpace($KoOverrideDir)) {
	$KoOverrideDir = Join-Path $WorkspaceRoot "overlay_in"
}
if ([string]::IsNullOrWhiteSpace($OutputHpf)) {
	$OutputHpf = Join-Path $WorkspaceRoot "The Last Express\KOREAN.HPF"
}
if ([string]::IsNullOrWhiteSpace($BaseHpf)) {
	$BaseHpf = Join-Path $WorkspaceRoot "The Last Express\HD.HPF"
}
if ([string]::IsNullOrWhiteSpace($WorkDir)) {
	$WorkDir = Join-Path $WorkspaceRoot "translation\_work_korean_hpf"
}

$py = Get-Command py -ErrorAction SilentlyContinue
if (-not $py) {
	Fail 10 "Python launcher 'py'를 찾지 못했습니다."
}

$unpackScript = Join-Path $WorkspaceRoot "tools\hpf_unpack.py"
$packScript = Join-Path $WorkspaceRoot "tools\hpf_pack.py"
$validateScript = Join-Path $WorkspaceRoot "tools\validate_korean_hpf.py"

foreach ($path in @($ModedHpf, $unpackScript, $packScript, $validateScript)) {
	if (-not (Test-Path $path)) {
		Fail 11 "필수 파일이 없습니다: $path"
	}
}

if (-not (Test-Path $BaseHpf)) {
	Write-Host "[WARN] Base HPF not found for compare: $BaseHpf" -ForegroundColor Yellow
}

if ((Test-Path $KoOverrideDir) -and -not (Get-Item $KoOverrideDir).PSIsContainer) {
	Fail 12 "KoOverrideDir는 폴더여야 합니다: $KoOverrideDir"
}

$extractDir = Join-Path $WorkDir "moded_extract"
$stageDir = Join-Path $WorkDir "overlay_stage"

Step "작업 디렉터리 준비"
if (Test-Path $WorkDir) {
	Remove-Item -Recurse -Force $WorkDir
}
New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

Step "Moded_HD.HPF 언패킹"
& $py.Source $unpackScript $ModedHpf $extractDir
if ($LASTEXITCODE -ne 0) {
	Fail 20 "hpf_unpack.py 실패 (exit code: $LASTEXITCODE)"
}

Step "SBE 시드 추출"
$seedSbe = Get-ChildItem -Path $extractDir -File -Filter *.SBE
if (-not $seedSbe -or $seedSbe.Count -eq 0) {
	Fail 21 "Moded_HD.HPF에서 SBE를 찾지 못했습니다."
}
$seedSbe | ForEach-Object { Copy-Item -Path $_.FullName -Destination $stageDir -Force }
Write-Host "  Seed SBE count: $($seedSbe.Count)"

if (Test-Path $KoOverrideDir) {
	Step "한글 오버라이드 파일 병합"
	$overrideFiles = @(Get-ChildItem -Path $KoOverrideDir -File -Recurse)
	if ($overrideFiles.Count -eq 0) {
		Write-Host "  override 파일 없음: $KoOverrideDir"
	} else {
		foreach ($f in $overrideFiles) {
			$dest = Join-Path $stageDir $f.Name
			Copy-Item -Path $f.FullName -Destination $dest -Force
		}
		Write-Host "  Override file count: $($overrideFiles.Count)"
	}
} else {
	if (-not $AllowSeedOnly) {
		Fail 22 "KoOverrideDir가 없습니다. SBE 시드만 패킹하려면 -AllowSeedOnly를 사용하세요: $KoOverrideDir"
	}
	Write-Host "[WARN] KoOverrideDir가 없어 SBE 시드만 패킹합니다: $KoOverrideDir" -ForegroundColor Yellow
}

Step "KOREAN.HPF 패킹"
if (Test-Path $OutputHpf) {
	$backupPath = "$OutputHpf.bak.$(Get-Date -Format yyyyMMdd_HHmmss)"
	Copy-Item -Path $OutputHpf -Destination $backupPath -Force
	Write-Host "  기존 Output 백업: $backupPath"
}
& $py.Source $packScript $stageDir $OutputHpf
if ($LASTEXITCODE -ne 0) {
	Fail 30 "hpf_pack.py 실패 (exit code: $LASTEXITCODE)"
}

Step "KOREAN.HPF 검증"
if (Test-Path $BaseHpf) {
	& $py.Source $validateScript $OutputHpf --base-hpf $BaseHpf
} else {
	& $py.Source $validateScript $OutputHpf
}
if ($LASTEXITCODE -ne 0) {
	Fail 40 "validate_korean_hpf.py 실패 (exit code: $LASTEXITCODE)"
}

if (-not $KeepWorkDir) {
	Step "임시 작업 디렉터리 정리"
	Remove-Item -Recurse -Force $WorkDir
}

Write-Host ""
Write-Host "build_korean_hpf_from_moded.ps1 완료" -ForegroundColor Green
Write-Host "Output: $OutputHpf"
exit 0
