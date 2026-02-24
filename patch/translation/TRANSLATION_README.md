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
