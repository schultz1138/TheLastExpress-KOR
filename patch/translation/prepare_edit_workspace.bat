@echo off
setlocal
call :init_utf8

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"
for %%I in ("%SCRIPT_DIR%..") do set "PATCH_ROOT=%%~fI"
set "GAME_DIR=%PATCH_ROOT%"

set "SUB_SCRIPT=%PATCH_ROOT%\scripts\extract_subtitle_template.ps1"
set "BG_SCRIPT=%PATCH_ROOT%\scripts\extract_bg_templates.ps1"

if not exist "%SUB_SCRIPT%" (
    echo [ERROR] 필수 파일이 없습니다: scripts\extract_subtitle_template.ps1
    goto :fail
)
if not exist "%BG_SCRIPT%" (
    echo [ERROR] 필수 파일이 없습니다: scripts\extract_bg_templates.ps1
    goto :fail
)

if not exist "%GAME_DIR%\HD.HPF" (
    echo [ERROR] 현재 폴더에 HD.HPF가 없습니다.
    goto :fail
)
call :has_archive "%GAME_DIR%" "CD1.HPF"
if errorlevel 1 (
    echo [ERROR] CD1.HPF가 게임 루트 또는 data/Data 폴더에 없습니다.
    goto :fail
)
call :has_archive "%GAME_DIR%" "CD2.HPF"
if errorlevel 1 (
    echo [ERROR] CD2.HPF가 게임 루트 또는 data/Data 폴더에 없습니다.
    goto :fail
)
call :has_archive "%GAME_DIR%" "CD3.HPF"
if errorlevel 1 (
    echo [ERROR] CD3.HPF가 게임 루트 또는 data/Data 폴더에 없습니다.
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
    echo [STEP] 편집용 자막 템플릿 추출
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SUB_SCRIPT%" -WorkspaceRoot "%PATCH_ROOT%" -GameDir "%GAME_DIR%" -AllSubsHpf "%ALLSUBS_HPF%"
    if errorlevel 1 (
        echo [ERROR] 자막 템플릿 추출에 실패했습니다.
        goto :fail
    )
) else (
    echo [WARN] HD_ALLSUBS.HPF를 찾지 못해 자막 템플릿 추출을 건너뜁니다.
)

echo [STEP] HPF에서 BG 템플릿 추출
powershell -NoProfile -ExecutionPolicy Bypass -File "%BG_SCRIPT%" -WorkspaceRoot "%PATCH_ROOT%" -GameDir "%GAME_DIR%"
if errorlevel 1 (
    echo [ERROR] BG 템플릿 추출에 실패했습니다.
    goto :fail
)

echo.
echo [DONE] 편집 작업 폴더 준비가 완료되었습니다.
echo        자막 템플릿 : translation\kosubs.user.tsv
echo        BG 템플릿   : translation\output_user\*.bmp
echo        BGP 생성    : translation\build_bgpatch.bat
pause
call :restore_cp
exit /b 0

:init_utf8
for /f "tokens=2 delims=:" %%A in ('chcp') do set "_KOR_PREV_CP=%%A"
set "_KOR_PREV_CP=%_KOR_PREV_CP: =%"
if not "%_KOR_PREV_CP%"=="65001" chcp 65001 >nul
exit /b 0

:restore_cp
if defined _KOR_PREV_CP if not "%_KOR_PREV_CP%"=="65001" chcp %_KOR_PREV_CP% >nul
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
echo [FAILED] 실패했습니다.
echo [HINT] 이 도구는 이미 PowerShell ExecutionPolicy Bypass로 실행됩니다.
echo [HINT] 계속 실패하면 아래를 확인하세요:
echo        1) ZIP을 Program Files가 아닌 쓰기 가능한 폴더에 압축 해제
echo        2) Python ^(py/python^) 설치 후 재시도
pause
call :restore_cp
exit /b 1
