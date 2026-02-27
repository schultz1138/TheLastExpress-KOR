# 번역 작업 흐름

이 폴더에는 배포 가능한 번역 자산이 들어 있습니다.

## 파일 구성

- `subko.tsv`: 배포용 한국어 자막 테이블
- `kosubs.tsv`: 로컬 편집용 원본(배포 워크플로에서는 gitignore)
- `bgpatch/manifest.json` + `*.BGP`: BG 바이너리 패치셋
- `prepare_edit_workspace.bat`: 편집용 템플릿 추출 도구

## 자막 편집 규칙 (`subko.tsv`)

- 줄바꿈은 반드시 `\n`(역슬래시+n)으로 입력합니다.
- 실제 엔터(개행 문자)를 넣지 않습니다.
- 권장 형식: `첫 줄 문장.\n둘째 줄 문장`

## 검수 추적 ID 붙이기/제거

플레이 중 추적을 위해 한국어 자막 끝에 ID를 붙일 수 있습니다.
형식: `[SBE_EntryIndex]` (예: `[1002_0]`)

추가:

(`patch` 폴더 기준)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\add_review_subtitle_ids.ps1
```

제거(원복):

(`patch` 폴더 기준)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\remove_review_subtitle_ids.ps1
```

`patch\scripts` 폴더에서 직접 실행할 때는 `.\scripts\`를 빼고:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\add_review_subtitle_ids.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\remove_review_subtitle_ids.ps1
```

- 기본 입력 파일 우선순위: `translation\kosubs.user.tsv` -> `translation\subko.tsv` -> `translation\kosubs.tsv`
- 기본 동작은 입력 파일을 직접 수정(인플레이스)하며, 백업 파일(`*.bak.addreview.*` / `*.bak.rmreview.*`)을 생성합니다.
- 백업 없이 처리하려면 `-NoBackup` 옵션을 사용하세요.
- 다른 파일로 출력하려면 `-OutputTsv`를 지정하세요.

## 자막 린트(품질 검사)

길이(24/48), 줄 수(2줄), 공백/이스케이프/탭 문제를 자동 검사합니다.

(`patch` 폴더 기준)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\lint_subtitles.ps1 -ReportTsv ".\translation\subtitle_lint.tsv"
```

- 기본 기준: 줄당 24자, 총 48자
- 기준 변경: `-MaxCharsPerLine`, `-MaxTotalChars`
- 이슈 발생 시 종료코드를 실패로 처리하려면 `-StrictExit`

## 자막 자동 정리

수동 편집 후 일괄 정리를 수행합니다.

- 앞뒤 공백 trim
- `\n` 주변 공백 정리
- 연속 공백 정리(기본)

(`patch` 폴더 기준)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\normalize_subtitles.ps1
```

- 기본 동작은 인플레이스 수정 + 백업(`*.bak.normalize.*`)
- 출력 파일 지정: `-OutputTsv ".\translation\subko.cleaned.tsv"`
- 연속 공백 정리를 끄려면 `-NoCollapseSpaces`

## 자동 줄바꿈 제안 모드

원본을 직접 바꾸지 않고 줄바꿈 제안본(`*.suggested.tsv`)을 생성합니다.

(`patch` 폴더 기준)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\suggest_linebreaks.ps1
```

- 기본 출력: 입력 파일명 + `.suggested.tsv` (예: `subko.suggested.tsv`)
- 기준 변경: `-MaxCharsPerLine`, `-MaxLines`

## 폰트 폭 미리보기

`Korean.TTF` 기준으로 자막 줄 폭을 계산해서 잘릴 가능성이 있는 행을 리포트합니다.

(`patch` 폴더 기준)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\preview_subtitle_width.ps1 -ReportTsv ".\translation\subtitle_width_report.tsv"
```

- 기본 폰트: `runtime\korean.ttf`
- 기본 폰트 크기: `14px`
- 기본 폭 한계: 한글 24자(`가` * 24) 측정값을 자동 사용
- 수동 폭 지정: `-MaxWidthPx 360`

## 동일 원문의 번역 불일치 검사

같은 원문(`full-src`)에 대해 서로 다른 번역(`full-tr`)이 섞였는지 검사할 수 있습니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_translation_consistency.ps1
```

보고서를 파일로 저장하려면:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_translation_consistency.ps1 -ReportTsv ".\translation\translation_conflicts.tsv"
```

- 기본 입력 파일 우선순위: `translation\kosubs.user.tsv` -> `translation\kosubs.tsv`
- `subko.tsv`(3열)는 원문 컬럼이 없으므로 이 검사의 직접 입력으로는 쓰지 않습니다.

## 엑셀 저장 후 TSV 인코딩 복구

엑셀에서 저장한 TSV가 CP949/ANSI 또는 UTF-16으로 바뀐 경우, 아래 배치로 UTF-8(BOM 없음)으로 되돌릴 수 있습니다.

```bat
translation\convert_tsv_utf8.bat
```

- 인자를 주지 않으면 `subko.tsv`, `kosubs.tsv`를 자동 변환합니다.
- 파일 경로를 인자로 넘기면 해당 TSV만 변환합니다.
- 변환 전 원본 백업 파일(`*.bak.yyyymmdd_HHmmss`)을 생성합니다.

`patch_and_install.bat` 실행 시에도 빌드 전에 위 UTF-8 정규화를 자동 수행합니다.
이 자동 정규화는 설치 중 임시 처리이므로 백업 파일을 만들지 않습니다.
자동 정규화를 끄려면 `KOR_SKIP_TSV_NORMALIZE=1`로 실행하세요.

## 편집 작업 폴더 준비

아카이브가 있는 게임 폴더에서 실행:

```bat
translation\prepare_edit_workspace.bat
```

아카이브 위치 지원:

- `HD.HPF`: 게임 루트
- `CD1.HPF`, `CD2.HPF`, `CD3.HPF`: 게임 루트 또는 `data`/`Data`

생성 결과:

- `translation\kosubs.user.tsv`
- `translation\output_user\*.bmp`

## BG 패치셋 재생성

```powershell
py .\tools\build_bg_patchset.py --game-dir "D:\Games\The Last Express" --bmp-dir ".\translation\output_user" --out-dir ".\translation\bgpatch"
```

## 패치 빌드 + 설치

```bat
patch_and_install.bat
```

`HD_ALLSUBS.HPF`가 없으면 일부 음성 대사가 번역되지 않은 상태로 남을 수 있습니다.
