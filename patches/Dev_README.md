# The Last Express KOR (Release Repo)

This folder is prepared as a public-release repository.
Repo: https://github.com/schultz1138/TheLastExpress-KOR

## Purpose

- Provide source patch for ScummVM 2026.1.0.
- Keep a modified source snapshot (`custom_scummvm-2026.1.0`) for long-term reproducibility.
- Provide scripts to build/test ScummVM and pack `Korean.HPF`.
- Provide Korean subtitle source (`translation/subko.tsv`) and generated BG patchset (`translation/bgpatch`).

## Included

- `patches/scummvm-2026.1.0/`
- `custom_scummvm-2026.1.0/` (tracked source snapshot, no build artifacts)
- `scripts/`
- `tools/` (HPF/BG helper scripts)
- `translation/subko.tsv`
- `launcher/start.bat`
- `docs/`

## Not Included

- Original game files (`HD.HPF`, `CD1/2/3.HPF`, etc.)
- Extracted bulk assets
- Build outputs (`scummvm.exe`, DLL, packaged binaries)

## Quick Start

1. Clone this repository:
```powershell
git clone https://github.com/schultz1138/TheLastExpress-KOR.git
cd .\TheLastExpress-KOR
```
2. Prepare a clean ScummVM 2026.1.0 tree outside this repo (example: `..\clean_scummvm-2026.1.0`).
3. Apply source patch to clean ScummVM:
```powershell
git -C "..\clean_scummvm-2026.1.0" apply --check ".\patches\scummvm-2026.1.0\lastexpress_kor_scummvm.patch"
git -C "..\clean_scummvm-2026.1.0" apply ".\patches\scummvm-2026.1.0\lastexpress_kor_scummvm.patch"
```
4. Build ScummVM via `scripts/build_scummvm_kor.ps1`.
5. Build `Korean.HPF` via `scripts/build_korean_hpf_from_moded.ps1`.
   - **Note**: For full spoken subtitle coverage, also place `Moded_HD.HPF` locally and let the script seed `.SBE` from it.

See `docs/PUBLISH_CHECKLIST.md` for release checks.

## Technical Details

### 1. 자막 시스템 (Subtitle System)
원작 게임에는 한국어 자막이 없으므로, 본 프로젝트는 `translation/subko.tsv`(3컬럼) 또는 `translation/kosubs.user.tsv`(7컬럼)을 런타임 포맷 `SUBKO.TSV`로 자동 변환하여 `KOREAN.HPF`에 포함합니다.

### 2. 그래픽 시스템 (BG Patchset)
- 개발 중에는 `translation/output/*.BMP`를 수정합니다.
- 공개 배포 시에는 BMP를 직접 포함하지 않고 `translation/bgpatch`(binary patchset)만 포함합니다.
- 사용자 패처는 로컬 원본 HPF에서 BG를 읽어 patchset을 적용한 뒤 `KOREAN.HPF`를 생성합니다.

### 3. 번역 데이터 구조
- **배포 기본 소스**: `translation/subko.tsv` (3개 컬럼: 파일명|인덱스|한글 내용)
- **편집 템플릿**: `translation/kosubs.user.tsv` (7개 컬럼, 로컬 `Moded_HD.HPF`에서 추출)
- **런타임 데이터**: `SUBKO.TSV` (3개 컬럼: 파일명|인덱스|한글 내용)
- 빌드 과정에서 선택된 TSV가 엔진이 인식할 수 있는 `SUBKO.TSV` 형식으로 자동 정제되어 패킹됩니다.

### 4. 폰트 엔진 (Font Engine)
엔진은 한글 출력을 위해 `Korean.TTF` 파일을 찾습니다.
- **포함 방식**: `KOREAN.HPF` 내부에 `Korean.TTF` 이름으로 폰트를 패킹하여 배포합니다. (권장: 나눔스퀘어B)
* **유저 오버라이드 지원**: 사용자가 게임 폴더에 직접 `Korean.TTF`라는 이름으로 원하는 폰트 파일을 넣으면, 패키지 내부의 폰트 대신 해당 폰트가 우선적으로 적용됩니다.

## Snapshot Workflow

Sync local modified ScummVM source into this repo snapshot:

```powershell
& ".\scripts\update_custom_scummvm_snapshot.ps1"
```

Then regenerate source patch:

```powershell
& ".\scripts\make_scummvm_patch.ps1" -ValidateApply
```
