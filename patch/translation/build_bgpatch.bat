@echo off
setlocal EnableExtensions
call :init_utf8

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"
for %%I in ("%SCRIPT_DIR%..") do set "PATCH_ROOT=%%~fI"

set "GAME_DIR=%~1"
if not defined GAME_DIR set "GAME_DIR=%PATCH_ROOT%"
set "BMP_DIR=%PATCH_ROOT%\translation\output_user"
set "OUT_DIR=%PATCH_ROOT%\translation\bgpatch"
set "BUILD_SCRIPT=%PATCH_ROOT%\tools\build_bg_patchset.py"
set "PY_EMBED=%PATCH_ROOT%\runtime\python\python.exe"
set "PY_MODE="

if not exist "%BUILD_SCRIPT%" (
    echo [ERROR] 필수 파일이 없습니다: tools\build_bg_patchset.py
    goto :fail
)
if not exist "%BMP_DIR%" (
    echo [ERROR] BMP 폴더가 없습니다: translation\output_user
    goto :fail
)

if not exist "%GAME_DIR%\HD.HPF" (
    echo [INFO] 기본 경로에서 HD.HPF를 찾지 못했습니다.
    set /p "GAME_DIR=게임 폴더 경로를 입력하세요 (예: C:\Games\The Last Express): "
)
if not defined GAME_DIR (
    echo [ERROR] 게임 폴더 경로가 비어 있습니다.
    goto :fail
)

if not exist "%GAME_DIR%\HD.HPF" (
    echo [ERROR] HD.HPF가 게임 루트에 없습니다: %GAME_DIR%
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

if exist "%PY_EMBED%" (
    set "PY_MODE=embedded"
) else (
    where py >nul 2>&1
    if not errorlevel 1 set "PY_MODE=py"
)
if not defined PY_MODE (
    where python >nul 2>&1
    if not errorlevel 1 set "PY_MODE=python"
)
if not defined PY_MODE (
    echo [ERROR] Python 실행 파일을 찾지 못했습니다.
    echo [HINT] 권장: runtime\python\python.exe 포함 릴리즈를 사용하세요.
    goto :fail
)

echo [STEP] 기존 BG 패치셋 정리
if exist "%OUT_DIR%" (
    rmdir /s /q "%OUT_DIR%"
)
mkdir "%OUT_DIR%" >nul 2>&1

echo [STEP] BMP -> BGP 패치셋 생성
echo        GameDir : %GAME_DIR%
echo        BmpDir  : %BMP_DIR%
echo        OutDir  : %OUT_DIR%

if /I "%PY_MODE%"=="embedded" (
    "%PY_EMBED%" "%BUILD_SCRIPT%" --game-dir "%GAME_DIR%" --bmp-dir "%BMP_DIR%" --out-dir "%OUT_DIR%"
) else if /I "%PY_MODE%"=="py" (
    py -3 "%BUILD_SCRIPT%" --game-dir "%GAME_DIR%" --bmp-dir "%BMP_DIR%" --out-dir "%OUT_DIR%"
) else (
    python "%BUILD_SCRIPT%" --game-dir "%GAME_DIR%" --bmp-dir "%BMP_DIR%" --out-dir "%OUT_DIR%"
)

if errorlevel 1 (
    echo [ERROR] BG 패치셋 생성에 실패했습니다.
    goto :fail
)

echo.
echo [DONE] BG 패치셋 생성이 완료되었습니다.
echo        출력 폴더: translation\bgpatch
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
pause
call :restore_cp
exit /b 1
