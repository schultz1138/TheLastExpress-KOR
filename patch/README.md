# The Last Express KOR Patch

이 폴더는 사용자 배포용 작업 공간입니다.

## 구성

- `patch_and_install.bat`: `KOREAN.HPF` 생성/설치 메인 스크립트
- `uninstall.bat`: 설치 매니페스트 기준으로 패치 파일 제거
- `runtime/`: 런처/런타임 파일(`scummvm_k.exe`, `scummvm_k.ini`, `*.dll`, `python/`, 아이콘)
- `translation/`: 자막 테이블 및 BG 패치셋
  - `translation\convert_tsv_utf8.bat`: 엑셀 저장 후 TSV 인코딩 UTF-8 복구
- `scripts/`: PowerShell 패치 스크립트
  - `check_translation_consistency.ps1`: 동일 원문의 번역 불일치 검사
  - `add_review_subtitle_ids.ps1` / `remove_review_subtitle_ids.ps1`: 검수용 자막 ID 붙이기/제거
  - `lint_subtitles.ps1`: 자막 품질 린트(길이/이스케이프/탭/공백)
  - `normalize_subtitles.ps1`: 자막 텍스트 자동 정리(공백/\n 주변 정리)
  - `suggest_linebreaks.ps1`: 자동 줄바꿈 제안 TSV 생성
  - `preview_subtitle_width.ps1`: 폰트 기준 줄 폭 미리보기 리포트
- `tools/`: Python 보조 도구
- `licenses/`: 배포 구성요소 라이선스 문서

## 설치 방법 (사용자)

### 1. 게임을 준비합니다
- 본 패치는 『라스트 익스프레스』 1997년 출시 버전이 필요합니다.    
- 현재 디지털 버전은 **GOG**에서 구매할 수 있습니다. [구매 링크](https://www.gog.com/en/game/last_express_the) 
- 리테일 CD 버전(삼성전자판 / 브로더번드판 / 인터플레이판)도 지원합니다.
- ⚠️ **Steam에서 판매 중인 2011년 출시한 Gold Edition은 지원하지 않습니다.**  
  **Gold Edition은 iOS 이식판을 재이식한 것으로, 파일 구조가 다르기 때문입니다.**

| 버전                        | 지원 여부 |
| ------------------------- | ----- |
| GOG 오리지널 버전 (DOSbox 버전 및 ScummVM 런처)          | ✅ 지원  |
| 리테일 CD (정식발매 및 영문판)                    | ✅ 지원  |
| Steam 및 GOG의 Gold Edition (2011) | ❌ 미지원 |
| 다국어판 (프랑스, 독일, 이탈리아, 스페인)                      | ❌ 미지원 |

### 2. 게임 파일을 확인합니다
게임 폴더에 아래 파일이 있어야 합니다:

- `HD.HPF`
- `CD1.HPF`
- `CD2.HPF`
- `CD3.HPF`

리테일 CD 및 GOG에서 구매하신 버전의 경우, CD1~CD3.HPF 파일은 data 또는 Data에 있습니다.  
해당 경로에 있어도 패치 설치는 무사히 진행됩니다.  
파일이 없다면 설치가 올바르게 되었는지 확인하세요.  

### 3. (선택) 영어 자막 파일 준비
이 게임의 시스템은 원래 영어 음성에는 자막을 지원하지 않습니다.
영어 대사에도 자막을 함께 표시하고 싶다면  
GOG 포럼 사용자 **qwerty0**가 제작한 팬 자막을 준비합니다.

- 본 프로젝트는 해당 파일을 직접 배포하지 않습니다.   
- 파일 관련 글은 [GOG 포럼](https://www.gog.com/forum/the_last_express/any_way_to_get_subtitles/page1) 에서 확인하실 수 있습니다.
- 다운로드 후 `HD.HPF` → `HD_ALLSUBS.HPF`로 이름을 변경합니다.
- 변경한 파일을 게임 폴더에 넣습니다.

※ 영어에 대한 자막이 필요 없다면 이 단계는 생략 가능합니다.

### 4. 한국어 패치 설치
1. 배포된 `TheLastExpress_Kor_v1.0.0.zip` 파일을 압축 해제합니다.
2. 모든 파일을 게임 폴더에 복사합니다.
3. `patch_and_install.bat`를 실행합니다.
    - 실행 전 SHA256 해시를 자동 검사합니다.
    - 빌드 전 `translation\*.tsv` 인코딩을 UTF-8(BOM 없음)으로 자동 정규화합니다.

### 5. 실행 및 제거
- `start.bat` 또는 바탕화면의 **THE LAST EXPRESS (KOR)** 아이콘으로 실행합니다.    
- 제거하려면 `uninstall.bat`를 실행하세요.

## 아카이브 해시 검사 (SHA256)

기준 스냅샷 날짜: `2026-02-23` (프로젝트 진행자 로컬 GOG 설치본 기준).

| File | SHA256 |
|---|---|
| `HD.HPF` | `0526D68F4D91212CD180CACCF8EB7F08AE1B8489FE0AC75AE60BDBC4A7D74C8C` |
| `CD1.HPF` | `A594136C5DC020EB9A444E3AA60E6A341998A93E590CC8AD7C6B976E0907F83A` |
| `CD2.HPF` | `F26293A597DBBDC6D782A1FAA38D9B33A786055A9C96F1D1A26CBFD6ED0EC6D7` |
| `CD3.HPF` | `909542B8CDF3FFC58016FEF757858F9A4DF48D0E6A3DEBC3C873BDAB551E10BA` |
| `HD_ALLSUBS.HPF` | `F7FCC14E87731BAB2EC5A02E5634DD3189A46D0D002636560FFB51E9F5493F42` |

PowerShell 검사 예시:

```powershell
Get-FileHash -Algorithm SHA256 ".\HD.HPF"
Get-FileHash -Algorithm SHA256 ".\data\CD1.HPF"
Get-FileHash -Algorithm SHA256 ".\data\CD2.HPF"
Get-FileHash -Algorithm SHA256 ".\data\CD3.HPF"
Get-FileHash -Algorithm SHA256 ".\HD_ALLSUBS.HPF"
```

`patch_and_install.bat`는 빌드 전에 위 SHA256 검사를 자동 수행합니다.
검사를 건너뛰려면 `KOR_SKIP_HASH_CHECK=1`로 실행하세요.

TSV 인코딩 자동 정규화를 건너뛰려면 `KOR_SKIP_TSV_NORMALIZE=1`로 실행하세요.

`HD_ALLSUBS.HPF`가 존재하고 해시가 일치하면 음성 자막 시드 데이터가 자동으로 포함됩니다.
