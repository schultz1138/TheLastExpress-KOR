# The Last Express KOR

This repository is split into two areas:

- `patch/`: user-facing release files (installer, runtime, translation data, patch scripts/tools)
- `engine/`: long-term engine maintenance (custom snapshot, source patch, dev scripts)

## Quick Start (User)

1. Prepare a game folder with:
   - `HD.HPF` in game root
   - `CD1.HPF`, `CD2.HPF`, `CD3.HPF` in game root or `data`/`Data` folder
2. Add the fan English subtitle archive:
   - rename fan subtitle `HD.HPF` to `HD_ALLSUBS.HPF`
   - place `HD_ALLSUBS.HPF` in game root (or `data`/`Data`)
3. Copy the contents of `patch/` into that game folder.
4. Run `patch_and_install.bat`.
5. Launch the game with `start.bat`.
6. To remove patch files later, run `uninstall.bat`.

## Required Archive Hashes (SHA256)

Reference snapshot date: `2026-02-23` (local GOG install in maintainer workspace).

| File | SHA256 |
|---|---|
| `HD.HPF` | `0526D68F4D91212CD180CACCF8EB7F08AE1B8489FE0AC75AE60BDBC4A7D74C8C` |
| `CD1.HPF` | `A594136C5DC020EB9A444E3AA60E6A341998A93E590CC8AD7C6B976E0907F83A` |
| `CD2.HPF` | `F26293A597DBBDC6D782A1FAA38D9B33A786055A9C96F1D1A26CBFD6ED0EC6D7` |
| `CD3.HPF` | `909542B8CDF3FFC58016FEF757858F9A4DF48D0E6A3DEBC3C873BDAB551E10BA` |
| `HD_ALLSUBS.HPF` | `F7FCC14E87731BAB2EC5A02E5634DD3189A46D0D002636560FFB51E9F5493F42` |

## Quick Start (Developer)

- Engine maintenance guide: `engine/DEV_README.md`
- Snapshot sync workflow: `engine/SNAPSHOT_WORKFLOW.md`
- Publish checklist: `engine/PUBLISH_CHECKLIST.md`
- Source patch: `engine/patches/scummvm-2026.1.0/`
