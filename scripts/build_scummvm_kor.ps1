[CmdletBinding()]
param(
	[string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
	[string]$ScummvmRoot = "",
	[string]$GamePath = "",
	[string]$ConfigPath = "",
	[string]$SmokeLogPath = "",
	[string]$VcpkgInstalledDir = "",
	[string]$CustomBuildDir = "",
	[string]$Configuration = "Release",
	[string]$Platform = "x64",
	[string]$PlatformToolset = "v143",
	[int]$SmokeSeconds = 15,
	[switch]$MinimalLastExpress,
	[switch]$SkipCopyToCustomBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
	param([string]$Message)
	Write-Host "[STEP] $Message" -ForegroundColor Cyan
}

function Fail {
	param(
		[int]$Code,
		[string]$Message
	)
	Write-Error $Message
	exit $Code
}

function Resolve-MSBuildPath {
	$cmd = Get-Command msbuild -ErrorAction SilentlyContinue
	if ($cmd) {
		return $cmd.Source
	}

	$candidates = @(
		"C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe",
		"C:\Program Files\Microsoft Visual Studio\18\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
		"C:\Program Files\Microsoft Visual Studio\17\Community\MSBuild\Current\Bin\MSBuild.exe",
		"C:\Program Files\Microsoft Visual Studio\17\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
	)

	foreach ($candidate in $candidates) {
		if (Test-Path $candidate) {
			return $candidate
		}
	}

	return $null
}

function Resolve-VcpkgPath {
	$cmd = Get-Command vcpkg -ErrorAction SilentlyContinue
	if ($cmd) {
		return $cmd.Source
	}

	$candidates = @(
		"C:\Program Files\Microsoft Visual Studio\18\Community\VC\vcpkg\vcpkg.exe",
		"C:\Program Files\Microsoft Visual Studio\18\BuildTools\VC\vcpkg\vcpkg.exe",
		"C:\Program Files\Microsoft Visual Studio\17\Community\VC\vcpkg\vcpkg.exe",
		"C:\Program Files\Microsoft Visual Studio\17\BuildTools\VC\vcpkg\vcpkg.exe"
	)

	foreach ($candidate in $candidates) {
		if (Test-Path $candidate) {
			return $candidate
		}
	}

	return $null
}

function Invoke-Native {
	param(
		[string]$StepName,
		[string]$FilePath,
		[string[]]$Arguments,
		[string]$WorkingDirectory = "",
		[int]$FailureCode = 1
	)

	Write-Step $StepName
	if ($WorkingDirectory) {
		Push-Location $WorkingDirectory
	}

	try {
		& $FilePath @Arguments
		$exitCode = $LASTEXITCODE
	} finally {
		if ($WorkingDirectory) {
			Pop-Location
		}
	}

	if ($exitCode -ne 0) {
		Fail $FailureCode "$StepName 실패 (exit code: $exitCode)"
	}
}

if ([string]::IsNullOrWhiteSpace($ScummvmRoot)) {
	$ScummvmRoot = Join-Path $WorkspaceRoot "scummvm-2026.1.0"
}
if ([string]::IsNullOrWhiteSpace($GamePath)) {
	$GamePath = Join-Path $WorkspaceRoot "The Last Express"
}
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
	$ConfigPath = Join-Path $WorkspaceRoot "translation\scummvm_kor_test.ini"
}
if ([string]::IsNullOrWhiteSpace($SmokeLogPath)) {
	$SmokeLogPath = Join-Path $WorkspaceRoot "translation\scummvm_kor_smoke.log"
}
if ([string]::IsNullOrWhiteSpace($VcpkgInstalledDir)) {
	$VcpkgInstalledDir = Join-Path $ScummvmRoot "vcpkg_installed"
}
if ([string]::IsNullOrWhiteSpace($CustomBuildDir)) {
	$CustomBuildDir = Join-Path $WorkspaceRoot "Custom Build"
}

$msbuild = Resolve-MSBuildPath
if (-not $msbuild) {
	Fail 10 "MSBuild.exe 경로를 찾지 못했습니다."
}

$vcpkg = Resolve-VcpkgPath
if (-not $vcpkg) {
	Fail 11 "vcpkg.exe 경로를 찾지 못했습니다."
}

$vcpkgJson = Join-Path $ScummvmRoot "vcpkg.json"
$createProjectSln = Join-Path $ScummvmRoot "devtools\create_project\msvc\create_project.sln"
$createProjectExe = Join-Path $ScummvmRoot "dists\msvc\create_project.exe"
$distsMsvcDir = Join-Path $ScummvmRoot "dists\msvc"
$scummvmProj = Join-Path $distsMsvcDir "scummvm.vcxproj"
$platformDirName = switch ($Platform.ToLowerInvariant()) {
	"x64" { "x64" }
	"x86" { "x86" }
	"win32" { "x86" }
	"arm64" { "arm64" }
	default { $Platform }
}
$vcpkgTriplet = switch ($Platform.ToLowerInvariant()) {
	"x64" { "x64-windows" }
	"x86" { "x86-windows" }
	"win32" { "x86-windows" }
	"arm64" { "arm64-windows" }
	default { "$Platform-windows" }
}
$scummvmExe = Join-Path $distsMsvcDir ("{0}{1}\scummvm.exe" -f $Configuration, $platformDirName)

foreach ($requiredPath in @($ScummvmRoot, $GamePath, $ConfigPath, $vcpkgJson, $createProjectSln, $distsMsvcDir)) {
	if (-not (Test-Path $requiredPath)) {
		Fail 12 "필수 경로가 없습니다: $requiredPath"
	}
}

if (-not (Test-Path $VcpkgInstalledDir)) {
	New-Item -Path $VcpkgInstalledDir -ItemType Directory -Force | Out-Null
}

$legacyNested = Join-Path $VcpkgInstalledDir (Join-Path $vcpkgTriplet $vcpkgTriplet)
if (Test-Path $legacyNested) {
	Write-Host "[INFO] 레거시 중첩 경로 감지: $legacyNested" -ForegroundColor Yellow
	Write-Host "[INFO] 이번 빌드는 표준 루트 VcpkgInstalledDir=$VcpkgInstalledDir 를 사용합니다." -ForegroundColor Yellow
}

Write-Step "baseline 체크"
$baselineExists = $false
try {
	$vcpkgJsonContent = Get-Content -Path $vcpkgJson -Raw | ConvertFrom-Json
	$baselineExists = $vcpkgJsonContent.PSObject.Properties.Name -contains "builtin-baseline"
} catch {
	Fail 20 "vcpkg.json 파싱 실패: $($_.Exception.Message)"
}

if (-not $baselineExists) {
	Invoke-Native `
		-StepName "baseline 추가 (vcpkg x-update-baseline)" `
		-FilePath $vcpkg `
		-Arguments @("x-update-baseline", "--add-initial-baseline") `
		-WorkingDirectory $ScummvmRoot `
		-FailureCode 21
} else {
	Write-Host "  builtin-baseline 이미 존재"
}

Invoke-Native `
	-StepName "create_project 재빌드" `
	-FilePath $msbuild `
	-Arguments @(
		$createProjectSln,
		"/m",
		"/p:Configuration=Release",
		"/p:Platform=Win32",
		"/p:PlatformToolset=$PlatformToolset",
		"/verbosity:minimal"
	) `
	-FailureCode 30

if (-not (Test-Path $createProjectExe)) {
	$builtCreateProjectExe = Join-Path $ScummvmRoot "devtools\create_project\msvc\Release\create_project.exe"
	if (Test-Path $builtCreateProjectExe) {
		Copy-Item -Path $builtCreateProjectExe -Destination $createProjectExe -Force
	} else {
		Fail 31 "create_project.exe를 찾지 못했습니다: $createProjectExe"
	}
}

$regenArgs = @("..\..", "--msvc", "--enable-fluidsynth", "--vcpkg")
if ($MinimalLastExpress) {
	$regenArgs += @("--disable-all-engines", "--enable-engine=lastexpress")
}

Invoke-Native `
	-StepName "MSVC 프로젝트 재생성" `
	-FilePath $createProjectExe `
	-Arguments $regenArgs `
	-WorkingDirectory $distsMsvcDir `
	-FailureCode 40

Invoke-Native `
	-StepName "scummvm 빌드" `
	-FilePath $msbuild `
	-Arguments @(
		$scummvmProj,
		"/m",
		"/p:Configuration=$Configuration",
		"/p:Platform=$Platform",
		"/p:PlatformToolset=$PlatformToolset",
		"/p:VcpkgEnableManifest=true",
		"/p:VcpkgInstalledDir=$VcpkgInstalledDir",
		"/verbosity:minimal"
	) `
	-FailureCode 50

if (-not (Test-Path $scummvmExe)) {
	Fail 51 "빌드 산출물 없음: $scummvmExe"
}

Write-Step "smoke test 실행"
if (Test-Path $SmokeLogPath) {
	Remove-Item -Path $SmokeLogPath -Force
}

$smokeArgs = @(
	"--config=""$ConfigPath""",
	"--path=""$GamePath""",
	"--subtitles",
	"--debuglevel=2",
	"--logfile=""$SmokeLogPath""",
	"lastexpress"
)

try {
	$proc = Start-Process `
		-FilePath $scummvmExe `
		-ArgumentList $smokeArgs `
		-WorkingDirectory (Split-Path $scummvmExe -Parent) `
		-PassThru
} catch {
	Fail 60 "smoke test 실행 실패: $($_.Exception.Message)"
}

Start-Sleep -Seconds $SmokeSeconds

if (-not $proc.HasExited) {
	Stop-Process -Id $proc.Id -Force
	$proc.WaitForExit()
	Write-Host "  smoke test 타임아웃($SmokeSeconds s)으로 프로세스 종료"
} else {
	Write-Host "  smoke test 프로세스 자발 종료 (exit code: $($proc.ExitCode))"
}

if (-not (Test-Path $SmokeLogPath)) {
	Fail 61 "smoke 로그 파일이 생성되지 않았습니다: $SmokeLogPath"
}

Write-Step "로그 grep"
$fontLoaded = Select-String -Path $SmokeLogPath -Pattern "SubtitleManager: localized subtitle font loaded" -SimpleMatch -Quiet
$rowsLoaded = Select-String -Path $SmokeLogPath -Pattern "SubtitleManager: loaded [0-9]+ localized subtitle rows" -Quiet

if (-not $fontLoaded) {
	Fail 70 "로그 검증 실패: localized subtitle font loaded 항목이 없습니다."
}

if (-not $rowsLoaded) {
	Fail 71 "로그 검증 실패: localized subtitle rows 항목이 없습니다."
}

if (-not $SkipCopyToCustomBuild) {
	Write-Step "Custom Build 복사"
	if (-not (Test-Path $CustomBuildDir)) {
		New-Item -Path $CustomBuildDir -ItemType Directory -Force | Out-Null
	}

	$buildOutputDir = Split-Path $scummvmExe -Parent
	$targetExe = Join-Path $CustomBuildDir "scummvm.exe"
	if (Test-Path $targetExe) {
		Remove-Item -Path $targetExe -Force
	}

	Get-ChildItem -Path $CustomBuildDir -Filter "*.dll" -File -ErrorAction SilentlyContinue | ForEach-Object {
		Remove-Item -Path $_.FullName -Force
	}

	Copy-Item -Path $scummvmExe -Destination $targetExe -Force
	$dllFiles = Get-ChildItem -Path $buildOutputDir -Filter "*.dll" -File -ErrorAction SilentlyContinue
	foreach ($dll in $dllFiles) {
		Copy-Item -Path $dll.FullName -Destination (Join-Path $CustomBuildDir $dll.Name) -Force
	}

	if (-not (Test-Path $targetExe)) {
		Fail 80 "Custom Build 복사 실패: $targetExe"
	}

	Write-Host ("  copied: scummvm.exe + {0} dll(s) -> {1}" -f $dllFiles.Count, $CustomBuildDir)
}

Write-Host ""
Write-Host "build_scummvm_kor.ps1 완료: 모든 단계 성공" -ForegroundColor Green
Write-Host "로그: $SmokeLogPath"
if (-not $SkipCopyToCustomBuild) {
	Write-Host "Custom Build: $CustomBuildDir"
}
exit 0
