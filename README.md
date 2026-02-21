게임 「The Last Express (1997)」 한국어화 패치

버전: 1.0
기반: ScummVM 2026.1.0 (전용 빌드)
저장소: https://github.com/schultz1138/TheLastExpress-KOR

## 배포 정책

본 프로젝트는 다음 원칙을 따릅니다.

- 완성 `KOREAN.HPF`는 기본 릴리즈에 포함하지 않습니다.
- 원본 게임 자산(`HD.HPF`, `CD1~3.HPF`)은 절대 배포하지 않습니다.
- `HD_AllSubs.HPF`는 더 이상 빌드 필수 입력이 아닙니다.
- 패처가 사용자 로컬 게임 파일에서 최종 산출물을 생성합니다.
- 릴리즈에는 영어 원문 자막 테이블(`kosubs.tsv`)을 포함하지 않고, 한글 라인 테이블(`translation/subko.tsv`)만 포함합니다.

## 영어 전체 자막 (선택)

원작 구조를 유지하기 위해 영어 전체 자막은 기본값이 아닙니다.

영어 음성까지 자막으로 표시하려면 커뮤니티 제작 파일인 `HD_AllSubs.HPF`가 필요합니다.

- 제작자: GOG 포럼 사용자 `qwerty0`
- 관련 글: https://www.gog.com/forum/the_last_express/any_way_to_get_subtitles/page1
- 본 프로젝트는 해당 파일을 직접 배포하지 않습니다.

플레이어는 다음 중 선택할 수 있습니다.

- 원작 구조를 유지한 플레이
- 영어 포함 전체 자막 플레이

## 설치 (유저용)

1. 게임 폴더에 `HD.HPF`, `CD1.HPF`, `CD2.HPF`, `CD3.HPF`가 있는지 확인합니다.
2. 영어 음성 대사 자막까지 포함하려면, 팬이 수정한 HD 아카이브를 `HD_AllSubs.HPF` 이름으로 같은 폴더에 둡니다.
3. 릴리즈 ZIP을 게임 폴더에 그대로 압축 해제합니다.
4. `patch_and_install.bat`를 실행합니다.
5. 완료 후 `KOREAN.HPF`가 생성되고 `runtime` 파일이 게임 폴더로 자동 복사됩니다.
6. 바탕화면에 `The Last Express (KOR).lnk` 바로가기가 생성됩니다. (`LastExpress.ico`가 있으면 아이콘 적용)
7. `start.bat`로 실행합니다.

`HD_AllSubs.HPF`가 없으면 일부 음성 대사 구간은 자막이 비어 있을 수 있습니다.
릴리즈에 임베디드 Python(`runtime/python/python.exe`)이 포함되므로 Python 설치 없이 패치가 동작합니다.
기본적으로 관리자 권한은 필요하지 않습니다. (단, 게임 폴더가 `Program Files` 아래면 관리자 권한이 필요할 수 있습니다.)
배치 파일은 `-ExecutionPolicy Bypass`로 PowerShell을 호출합니다.

고급 사용자용 PowerShell 실행 예시:

```powershell
.\scripts\apply_korean_patch.ps1 -GameDir "D:\Games\The Last Express"
```

`HD_AllSubs.HPF` 탐색 경로:

- `<GameDir>\HD_AllSubs.HPF`
- `<PatchWorkspace>\translation\HD_AllSubs.HPF`
- `<PatchWorkspace>\HD_AllSubs.HPF`

직접 지정 예시:

```powershell
.\scripts\apply_korean_patch.ps1 -GameDir "D:\Games\The Last Express" -AllSubsHpf "D:\Mods\HD_AllSubs.HPF"
```

## 포함/미포함

포함:

- 설치 배치 (`patch_and_install.bat`)
- 자동 패처 스크립트
- 전용 ScummVM 실행 파일
- 런처 아이콘(`LastExpress.ico`)
- 한국어 자막 소스(`translation/subko.tsv`)
- BG 패치셋(`translation/bgpatch`, 있는 경우)
- 자막/BG 편집용 추출 도구 (`prepare_edit_workspace.bat`, `scripts/extract_*`)

미포함:

- `KOREAN.HPF` 완성본
- 원본 게임 아카이브(`HD.HPF`, `CD1~3.HPF`)
- 원본 또는 수정 BMP/BG 완성 리소스
- 영어 원문 자막 TSV 완성본(`kosubs.tsv`)

## 번역/그래픽 수정 (고급)

게임 폴더에서 아래를 실행하면 로컬 파일로 편집용 템플릿을 생성할 수 있습니다.

```bat
prepare_edit_workspace.bat
```

생성물:

- `translation/kosubs.user.tsv`: 로컬 `HD_AllSubs.HPF`에서 추출한 영문+타임코드 템플릿(한글 열은 `subko.tsv`로 자동 병합)
- `translation/output_user/*.bmp`: 로컬 HPF에서 추출한 BG 편집용 BMP

BG 편집 후 패치셋 재생성:

```powershell
py .\tools\build_bg_patchset.py --game-dir "D:\Games\The Last Express" --bmp-dir ".\translation\output_user" --out-dir ".\translation\bgpatch"
```

그 다음 `patch_and_install.bat`를 다시 실행하면 수정 내용이 `KOREAN.HPF`에 반영됩니다.

## 폰트

- 기본 폰트 파일명: `Korean.ttf`
- 사용자가 게임 폴더에 같은 이름의 TTF를 두면 우선 적용됩니다.

## 라이선스

- ScummVM: GPL v3
- 본 패치: 비공식 사용자 제작물
- 폰트: SIL Open Font License 1.1 (NAVER 나눔폰트 계열)
