# ScummVM Source Patch (The Last Express KOR)

This directory contains the source patch for ScummVM 2026.1.0.

## Files

- `lastexpress_kor_scummvm.patch`
- `CHANGED_FILES.txt`

## Expected local trees

- Clean source: `engine/clean/scummvm-2026.1.0`
- Custom snapshot: `engine/snapshots/custom-2026.1.0`

## Validate patch

```powershell
git -C ".\engine\clean\scummvm-2026.1.0" apply --check ".\engine\patches\scummvm-2026.1.0\lastexpress_kor_scummvm.patch"
```

## Apply patch

```powershell
git -C ".\engine\clean\scummvm-2026.1.0" apply ".\engine\patches\scummvm-2026.1.0\lastexpress_kor_scummvm.patch"
```
