@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"
for %%I in ("%SCRIPT_DIR%..") do set "PATCH_ROOT=%%~fI"
set "GAME_DIR=%PATCH_ROOT%"

set "SUB_SCRIPT=%PATCH_ROOT%\scripts\extract_subtitle_template.ps1"
set "BG_SCRIPT=%PATCH_ROOT%\scripts\extract_bg_templates.ps1"

if not exist "%SUB_SCRIPT%" (
    echo [ERROR] Missing required file: scripts\extract_subtitle_template.ps1
    goto :fail
)
if not exist "%BG_SCRIPT%" (
    echo [ERROR] Missing required file: scripts\extract_bg_templates.ps1
    goto :fail
)

if not exist "%GAME_DIR%\HD.HPF" (
    echo [ERROR] Missing HD.HPF in current folder.
    goto :fail
)
call :has_archive "%GAME_DIR%" "CD1.HPF"
if errorlevel 1 (
    echo [ERROR] Missing CD1.HPF in game root or data/Data folder.
    goto :fail
)
call :has_archive "%GAME_DIR%" "CD2.HPF"
if errorlevel 1 (
    echo [ERROR] Missing CD2.HPF in game root or data/Data folder.
    goto :fail
)
call :has_archive "%GAME_DIR%" "CD3.HPF"
if errorlevel 1 (
    echo [ERROR] Missing CD3.HPF in game root or data/Data folder.
    goto :fail
)

set "ALLSUBS_HPF="
if exist "%GAME_DIR%\HD_ALLSUBS.HPF" (
    set "ALLSUBS_HPF=%GAME_DIR%\HD_ALLSUBS.HPF"
)
if not defined ALLSUBS_HPF if exist "%GAME_DIR%\data\HD_ALLSUBS.HPF" (
    set "ALLSUBS_HPF=%GAME_DIR%\data\HD_ALLSUBS.HPF"
)
if not defined ALLSUBS_HPF if exist "%GAME_DIR%\Data\HD_ALLSUBS.HPF" (
    set "ALLSUBS_HPF=%GAME_DIR%\Data\HD_ALLSUBS.HPF"
)

if defined ALLSUBS_HPF (
    echo [STEP] Extract editable subtitle template
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SUB_SCRIPT%" -WorkspaceRoot "%PATCH_ROOT%" -GameDir "%GAME_DIR%" -AllSubsHpf "%ALLSUBS_HPF%"
    if errorlevel 1 (
        echo [ERROR] Subtitle template extraction failed.
        goto :fail
    )
) else (
    echo [WARN] HD_ALLSUBS.HPF not found. Subtitle template extraction skipped.
)

echo [STEP] Extract BG templates from HPF
powershell -NoProfile -ExecutionPolicy Bypass -File "%BG_SCRIPT%" -WorkspaceRoot "%PATCH_ROOT%" -GameDir "%GAME_DIR%"
if errorlevel 1 (
    echo [ERROR] BG template extraction failed.
    goto :fail
)

echo.
echo [DONE] Edit workspace prepared.
echo        Subtitle template: translation\kosubs.user.tsv
echo        BG templates     : translation\output_user\*.bmp
echo        Build BGP patch  : py tools\build_bg_patchset.py --game-dir "%GAME_DIR%" --bmp-dir ".\translation\output_user" --out-dir ".\translation\bgpatch"
pause
exit /b 0

:has_archive
set "ARCH_DIR=%~1"
set "ARCH_NAME=%~2"
if exist "%ARCH_DIR%\%ARCH_NAME%" exit /b 0
if exist "%ARCH_DIR%\data\%ARCH_NAME%" exit /b 0
if exist "%ARCH_DIR%\Data\%ARCH_NAME%" exit /b 0
exit /b 1

:fail
echo.
echo [FAILED]
echo [HINT] This helper already uses PowerShell ExecutionPolicy Bypass.
echo [HINT] If it still fails, try:
echo        1) Extract ZIP to a writable folder (not Program Files)
echo        2) Install Python (py/python) and retry
pause
exit /b 1
