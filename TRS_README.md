# The Last Express 한국어화 기여 및 수정 가이드

이 문서는 번역/그래픽 수정본을 관리하는 개발자용 문서입니다.

## 1. 정책 요약

- 공개 릴리즈에는 완성 `KOREAN.HPF`를 포함하지 않습니다.
- 공개 릴리즈에는 원본 게임 자산(`HD.HPF`, `CD1~3.HPF`)을 포함하지 않습니다.
- 공개 릴리즈에는 수정 BMP를 직접 포함하지 않고 `BG Patchset` 형태로 배포합니다.
- 최종 `KOREAN.HPF`는 사용자 로컬 원본 파일에서 자동 생성합니다.

## 2. 자막 수정

- 배포 기본 소스: `translation/subko.tsv` (3컬럼: `파일명 / 인덱스 / 한국어`)
- 편집 템플릿(로컬 추출): `translation/kosubs.user.tsv` (7컬럼: `파일명 / 인덱스 / 시작 / 종료 / 영어 / 한국어 / 비고`)
- 개발 원본(내부): `translation/kosubs.tsv`
- 실제 런타임용 `SUBKO.TSV`는 빌드 시 자동 생성됩니다.

## 3. 그래픽 수정

- 작업 원본: `translation/output_user/*.BMP` (로컬 추출 템플릿)
- 공개 배포용 산출: `translation/bgpatch/*` + `translation/bgpatch/manifest.json`

로컬 템플릿 추출:

```bat
prepare_edit_workspace.bat
```

BG 패치셋 생성:

```powershell
py .\tools\build_bg_patchset.py `
  --game-dir "D:\Games\The Last Express" `
  --bmp-dir ".\translation\output_user" `
  --out-dir ".\translation\bgpatch"
```

## 4. KOREAN.HPF 생성

다음 입력이 있으면 자동 생성됩니다.

- 게임 원본 폴더: `HD.HPF`, `CD1.HPF`, `CD2.HPF`, `CD3.HPF`
- 자막 소스: `translation/kosubs.user.tsv` 우선, 없으면 `translation/subko.tsv` 사용
- 그래픽: `translation/bgpatch` (우선) 또는 `translation/output_user` (`translation/output`도 지원)
- 음성 자막 시드(권장): `HD_AllSubs.HPF` (자동 탐색)

실행:

```powershell
.\scripts\build_korean_hpf.ps1 -GameDir "D:\Games\The Last Express"
```

참고:

- `-AllSubsHpf`를 지정하면 해당 파일에서 `.SBE`를 자동 시드합니다.
- `-AllSubsHpf`를 생략하면 아래 경로를 순서대로 자동 탐색합니다.
  - `<GameDir>\HD_AllSubs.HPF`
  - `<Workspace>\translation\HD_AllSubs.HPF`
  - `<Workspace>\HD_AllSubs.HPF`
- 자막 TSV를 직접 지정하려면 `-SubtitleTsv`를 사용합니다.
- 그래픽 리소스 없이 자막만 생성하려면 `-AllowSubtitleOnly`를 사용합니다.

편집 템플릿만 별도로 생성:

```powershell
.\scripts\extract_subtitle_template.ps1 -GameDir "D:\Games\The Last Express"
.\scripts\extract_bg_templates.ps1 -GameDir "D:\Games\The Last Express"
```

## 5. 유저용 원클릭 패처

권장:

```bat
patch_and_install.bat
```

기본 동작:

- 현재 폴더를 게임 폴더로 보고 `KOREAN.HPF`를 생성합니다.
- 릴리즈에 포함된 임베디드 Python이 `python\python.exe`로 복사되어 시스템 Python 없이 동작합니다.
- `runtime\*`를 게임 폴더로 복사한 뒤 `runtime` 폴더를 삭제합니다.
- 같은 폴더에 `HD_AllSubs.HPF`가 있으면 자동으로 `.SBE` 시드를 사용합니다.
- 바탕화면에 `The Last Express (KOR).lnk` 바로가기를 생성합니다. (`LastExpress.ico`가 있으면 아이콘 적용)

고급 실행:

```powershell
.\scripts\apply_korean_patch.ps1 -GameDir "D:\Games\The Last Express"
```

```powershell
.\scripts\apply_korean_patch.ps1 -GameDir "D:\Games\The Last Express" -AllSubsHpf "D:\Mods\HD_AllSubs.HPF"
```

## 6. 릴리즈 ZIP 만들기

```powershell
.\scripts\build_release_package.ps1
```

옵션:

- 기본값: 일반 사용자용 최소 구성(패처, 런타임, 번역/패치 데이터)만 포함
- `-IncludeSourceFiles`: `patches`, `docs` 등 개발용 소스까지 포함한 배포본 생성
- `runtime\python\python.exe`가 워크스페이스에 없으면 릴리즈 빌드는 실패 (임베디드 Python 필수)

## 7. ScummVM 소스 패치 관리

```powershell
.\scripts\update_custom_scummvm_snapshot.ps1
.\scripts\make_scummvm_patch.ps1 -ValidateApply
```
