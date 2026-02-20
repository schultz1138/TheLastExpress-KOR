# Snapshot Workflow

이 저장소는 수정된 ScummVM 소스의 스냅샷을 함께 보관합니다.

- `custom_scummvm-2026.1.0/`

목적은 단순합니다.

상위(Upstream) ScummVM이 변경되더라도,
현재 한국어화 패치가 적용된 정확한 소스를 언제든지 다시 빌드할 수 있도록 하기 위함입니다.

전문 개발자가 아니더라도 유지보수가 가능하도록 설계되었습니다.

## 1) 로컬 수정 소스로부터 스냅샷 동기화

저장소 루트 경로에서 아래 스크립트를 실행합니다.

```powershell
& ".\scripts\update_custom_scummvm_snapshot.ps1"
```

기본 소스 경로는 다음과 같습니다:

```
..\scummvm-2026.1.0
```

필요한 경우 스크립트 내 경로를 수정하여 사용할 수 있습니다.

## 2) 패치 파일 재생성

```powershell
& ".\scripts\make_scummvm_patch.ps1" -ValidateApply
```

생성되는 패치 파일:

- `patches/scummvm-2026.1.0/lastexpress_kor_scummvm.patch`

`-ValidateApply` 옵션을 사용하면, 깨끗한 원본 소스에 패치 적용이 정상적으로 가능한지 함께 검증합니다.

## 3) 커밋 대상 파일

ScummVM 소스에 변경이 발생한 경우, 다음 항목을 함께 커밋합니다.

1. `custom_scummvm-2026.1.0/*`
2. `patches/scummvm-2026.1.0/*`
3. 관련 문서 또는 스크립트 변경 사항

## 참고 사항

- 빌드 결과물(실행 파일, DLL 등)과 외부 설치 바이너리는
  스크립트 및 `.gitignore` 설정에 따라 자동 제외됩니다.
- 원본 게임 데이터 파일은 본 저장소에 포함하지 않습니다.
