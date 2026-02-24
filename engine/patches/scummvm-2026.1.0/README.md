# ScummVM 소스 패치 (The Last Express KOR)

이 디렉터리에는 ScummVM 2026.1.0용 소스 패치가 들어 있습니다.

## 파일

- `lastexpress_kor_scummvm.patch`
- `CHANGED_FILES.txt`

## 예상 로컬 트리

- Clean 소스: `engine/clean/scummvm-2026.1.0`
- Custom 스냅샷: `engine/snapshots/custom-2026.1.0`

## 패치 적용 가능 여부 검사

```powershell
git -C ".\engine\clean\scummvm-2026.1.0" apply --check ".\engine\patches\scummvm-2026.1.0\lastexpress_kor_scummvm.patch"
```

## 패치 적용

```powershell
git -C ".\engine\clean\scummvm-2026.1.0" apply ".\engine\patches\scummvm-2026.1.0\lastexpress_kor_scummvm.patch"
```
