# ScummVM Source Patch (The Last Express KOR)

이 폴더는 ScummVM `2026.1.0`의 클린 소스에서 수정 소스로의 패치를 담고 있습니다.

## 파일

- `lastexpress_kor_scummvm.patch`
- `CHANGED_FILES.txt`

## 패치 재생성

저장소 루트에서 다음 스크립트를 실행합니다:

```powershell
& ".\scripts\make_scummvm_patch.ps1" -ValidateApply
```

기본 입력 경로:

- 클린 소스: `..\clean_scummvm-2026.1.0`
- 수정 소스: `.\custom_scummvm-2026.1.0` 또는 로컬 작업 트리

## 클린 소스에 패치 적용

Dry run:

```powershell
git -C "..\clean_scummvm-2026.1.0" apply --check ".\patches\scummvm-2026.1.0\lastexpress_kor_scummvm.patch"
```

Apply:

```powershell
git -C "..\clean_scummvm-2026.1.0" apply ".\patches\scummvm-2026.1.0\lastexpress_kor_scummvm.patch"
```

## 참고 사항

- 이 패치는 소스 코드 변경 사항만 포함합니다.
- 빌드 결과물과 게임 에셋은 포함되지 않습니다.
