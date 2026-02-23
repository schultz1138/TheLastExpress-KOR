# The Last Express KOR Patch

This folder is the user-facing release workspace.

## Contents

- `patch_and_install.bat`: main installer for `KOREAN.HPF`
- `uninstall.bat`: remove installed patch files using install manifest
- `runtime/`: launcher/runtime files (`scummvm_k.exe`, `scummvm_k.ini`, `*.dll`, `python/`, icon)
- `translation/`: subtitle table and BG patchset
- `scripts/`: PowerShell patch scripts
- `tools/`: Python helper tools
- `licenses/`: license text files for distributed components

## User Install

1. Ensure game archives exist:
   - `HD.HPF` in game root
   - `CD1.HPF`, `CD2.HPF`, `CD3.HPF` in game root or `data`/`Data` folder
2. Prepare fan English subtitle archive:
   - Get fan subtitle `HD.HPF`.
   - Rename it to `HD_ALLSUBS.HPF`.
   - Place `HD_ALLSUBS.HPF` in game root (or `data`/`Data` folder).
3. Copy this folder's contents into the game folder.
4. Run `patch_and_install.bat`.
5. Start with `runtime/start.bat` (or copied `start.bat` in game folder).
6. To remove the patch later, run `uninstall.bat`.

## Archive Hash Check (SHA256)

Reference snapshot date: `2026-02-23` (local GOG install in maintainer workspace).

| File | SHA256 |
|---|---|
| `HD.HPF` | `0526D68F4D91212CD180CACCF8EB7F08AE1B8489FE0AC75AE60BDBC4A7D74C8C` |
| `CD1.HPF` | `A594136C5DC020EB9A444E3AA60E6A341998A93E590CC8AD7C6B976E0907F83A` |
| `CD2.HPF` | `F26293A597DBBDC6D782A1FAA38D9B33A786055A9C96F1D1A26CBFD6ED0EC6D7` |
| `CD3.HPF` | `909542B8CDF3FFC58016FEF757858F9A4DF48D0E6A3DEBC3C873BDAB551E10BA` |
| `HD_ALLSUBS.HPF` | `F7FCC14E87731BAB2EC5A02E5634DD3189A46D0D002636560FFB51E9F5493F42` |

PowerShell check example:

```powershell
Get-FileHash -Algorithm SHA256 ".\HD.HPF"
Get-FileHash -Algorithm SHA256 ".\data\CD1.HPF"
Get-FileHash -Algorithm SHA256 ".\data\CD2.HPF"
Get-FileHash -Algorithm SHA256 ".\data\CD3.HPF"
Get-FileHash -Algorithm SHA256 ".\HD_ALLSUBS.HPF"
```

`patch_and_install.bat` runs this SHA256 check automatically before build.
If you need to bypass the check, run with `KOR_SKIP_HASH_CHECK=1`.

If `HD_ALLSUBS.HPF` is present and hash-matched, spoken subtitle seed data is included automatically.
