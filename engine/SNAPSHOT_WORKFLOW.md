# Snapshot Workflow

## Purpose

Keep a reproducible custom ScummVM snapshot in:

- `engine/snapshots/custom-2026.1.0/`

## Commands

Sync clean source into snapshot:

```powershell
.\engine\scripts\update_custom_scummvm_snapshot.ps1
```

Generate source patch from clean vs custom:

```powershell
.\engine\scripts\make_scummvm_patch.ps1 -ValidateApply
```

## Notes

- Default clean source path: `engine/clean/scummvm-2026.1.0`
- Generated patch path: `engine/patches/scummvm-2026.1.0/`
