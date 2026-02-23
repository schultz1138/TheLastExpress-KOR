# Engine Maintenance

This folder is for long-term ScummVM maintenance.

## Structure

- `snapshots/custom-2026.1.0/`: tracked custom source snapshot
- `patches/scummvm-2026.1.0/`: generated source patch + changed file list
- `clean/`: local clean upstream source checkout (gitignored)
- `scripts/`: maintenance scripts

## Typical flow

1. Sync snapshot from clean source:

```powershell
.\engine\scripts\update_custom_scummvm_snapshot.ps1
```

2. Regenerate patch and validate apply:

```powershell
.\engine\scripts\make_scummvm_patch.ps1 -ValidateApply
```

3. Optional engine build + smoke:

```powershell
.\engine\scripts\build_scummvm_kor.ps1
```
