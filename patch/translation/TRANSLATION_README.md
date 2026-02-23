# Translation Workflow

This folder contains release-safe translation assets.

## Files

- `subko.tsv`: shipped Korean subtitle table
- `kosubs.tsv`: local editable source (gitignored for release workflow)
- `bgpatch/manifest.json` + `*.BGP`: binary BG patchset
- `prepare_edit_workspace.bat`: helper to extract editable templates

## Prepare editable workspace

Run from game folder where archives exist:

```bat
translation\prepare_edit_workspace.bat
```

Archive location support:
- `HD.HPF` in game root
- `CD1.HPF`, `CD2.HPF`, `CD3.HPF` in game root or `data`/`Data` folder

Outputs:

- `translation\kosubs.user.tsv`
- `translation\output_user\*.bmp`

## Rebuild BG patchset

```powershell
py .\tools\build_bg_patchset.py --game-dir "D:\Games\The Last Express" --bmp-dir ".\translation\output_user" --out-dir ".\translation\bgpatch"
```

## Build + install patch

```bat
patch_and_install.bat
```

If `HD_ALLSUBS.HPF` is missing, some spoken lines may remain untranslated.
