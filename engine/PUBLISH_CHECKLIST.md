# Publish Checklist

## Repository hygiene

- [ ] No original game archives committed (`HD.HPF`, `CD1/2/3.HPF`, `HD_ALLSUBS.HPF`)
- [ ] No extracted bulk assets committed
- [ ] No raw editable BMP set committed for release
- [ ] `.gitignore` rules match current `patch/` + `engine/` layout

## Source patch validation

- [ ] `engine/patches/scummvm-2026.1.0/lastexpress_kor_scummvm.patch` exists
- [ ] Patch applies cleanly to clean source (`git apply --check`)
- [ ] `CHANGED_FILES.txt` matches intended scope

## Runtime/patch validation

- [ ] `patch/scripts/apply_korean_patch.ps1` builds `KOREAN.HPF`
- [ ] `patch/translation/bgpatch/manifest.json` exists (or release intentionally subtitle-only)
- [ ] Runtime launcher (`patch/runtime/start.bat`) runs
- [ ] Icon and shortcut flow references `lastexpress.ico`

## Release package validation

- [ ] Release ZIP includes only `patch/` payload
- [ ] Release ZIP excludes forbidden assets (`kosubs.tsv`, original archives, raw BMP inputs)
