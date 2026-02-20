# The Last Express KOR (Release Repo)

This folder is prepared as a public-release repository.
Repo: https://github.com/schultz1138/TheLastExpress-KOR

## Purpose

- Provide source patch for ScummVM 2026.1.0.
- Keep a modified source snapshot (`custom_scummvm-2026.1.0`) for long-term reproducibility.
- Provide scripts to build/test ScummVM and pack `Korean.HPF`.
- Provide Korean subtitle source (`translation/kosubs.tsv`).

## Included

- `patches/scummvm-2026.1.0/`
- `custom_scummvm-2026.1.0/` (tracked source snapshot, no build artifacts)
- `scripts/`
- `tools/` (HPF/BG helper scripts)
- `translation/kosubs.tsv`
- `launcher/start.bat`
- `docs/`

## Not Included

- Original game files (`HD.HPF`, `CD1/2/3.HPF`, etc.)
- Extracted bulk assets
- Build outputs (`scummvm.exe`, DLL, packaged binaries)

## Quick Start

1. Clone this repository:
```powershell
git clone https://github.com/schultz1138/TheLastExpress-KOR.git
cd .\TheLastExpress-KOR
```
2. Prepare a clean ScummVM 2026.1.0 tree outside this repo (example: `..\clean_scummvm-2026.1.0`).
3. Apply source patch to clean ScummVM:
```powershell
git -C "..\clean_scummvm-2026.1.0" apply --check ".\patches\scummvm-2026.1.0\lastexpress_kor_scummvm.patch"
git -C "..\clean_scummvm-2026.1.0" apply ".\patches\scummvm-2026.1.0\lastexpress_kor_scummvm.patch"
```
4. Build ScummVM via `scripts/build_scummvm_kor.ps1`.
5. Build `Korean.HPF` via `scripts/build_korean_hpf_from_moded.ps1`.

See `docs/PUBLISH_CHECKLIST.md` for release checks.

## Snapshot Workflow

Sync local modified ScummVM source into this repo snapshot:

```powershell
& ".\scripts\update_custom_scummvm_snapshot.ps1"
```

Then regenerate source patch:

```powershell
& ".\scripts\make_scummvm_patch.ps1" -ValidateApply
```
