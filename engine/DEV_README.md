# 엔진 유지보수

이 폴더는 ScummVM 장기 유지보수를 위한 작업 공간입니다.

## 구조

- `snapshots/custom-2026.1.0/`: 추적되는 커스텀 소스 스냅샷
- `patches/scummvm-2026.1.0/`: 생성된 소스 패치 + 변경 파일 목록
- `clean/`: 로컬 클린 업스트림 소스 체크아웃(gitignore)
- `scripts/`: 유지보수 스크립트

## 기본 작업 흐름

1. clean 소스 기준으로 스냅샷 동기화:

```powershell
.\engine\scripts\update_custom_scummvm_snapshot.ps1
```

2. 패치 재생성 및 적용 검증:

```powershell
.\engine\scripts\make_scummvm_patch.ps1 -ValidateApply
```

3. 선택: 엔진 빌드 + 스모크 테스트:

```powershell
.\engine\scripts\build_scummvm_kor.ps1
```
