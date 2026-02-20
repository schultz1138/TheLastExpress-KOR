@echo off
setlocal

cd /d "%~dp0"

set "PATCH_ROOT=%cd%"
set "GAME_DIR=%PATCH_ROOT%"
set "SCRIPT_PATH=%PATCH_ROOT%\scripts\apply_korean_patch.ps1"

if not exist "%SCRIPT_PATH%" (
    echo [ERROR] Missing required file: scripts\apply_korean_patch.ps1
    goto :fail
)

call :check_required "%GAME_DIR%"
if errorlevel 1 (
    echo.
    echo Required game archives were not found in:
    echo   %GAME_DIR%
    echo.
    set /p "GAME_DIR=Enter game folder path: "
    set "GAME_DIR=%GAME_DIR:"=%"
    if "%GAME_DIR%"=="" (
        echo [ERROR] Game folder path is empty.
        goto :fail
    )
    if not exist "%GAME_DIR%" (
        echo [ERROR] Game folder does not exist: %GAME_DIR%
        goto :fail
    )
    call :check_required "%GAME_DIR%"
    if errorlevel 1 (
        echo [ERROR] Missing required files. Expected HD.HPF, CD1.HPF, CD2.HPF, CD3.HPF.
        goto :fail
    )
)

set "MODED_HPF="
if exist "%GAME_DIR%\Moded_HD.HPF" (
    set "MODED_HPF=%GAME_DIR%\Moded_HD.HPF"
)

echo [STEP] Build KOREAN.HPF
if defined MODED_HPF (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -GameDir "%GAME_DIR%" -ModedHpf "%MODED_HPF%"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -GameDir "%GAME_DIR%"
)
if errorlevel 1 (
    echo [ERROR] Patch generation failed.
    goto :fail
)

if exist "%PATCH_ROOT%\runtime\" (
    echo [STEP] Copy runtime files to game folder
    robocopy "%PATCH_ROOT%\runtime" "%GAME_DIR%" /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP >nul
    if errorlevel 8 (
        echo [ERROR] Runtime copy failed.
        goto :fail
    )
    rmdir /s /q "%PATCH_ROOT%\runtime"
)

echo.
echo [DONE] Patch completed.
echo        Output: "%GAME_DIR%\KOREAN.HPF"
echo        Launch with "%GAME_DIR%\start.bat"
pause
exit /b 0

:check_required
set "CHK_DIR=%~1"
if not exist "%CHK_DIR%\HD.HPF" exit /b 1
if not exist "%CHK_DIR%\CD1.HPF" exit /b 1
if not exist "%CHK_DIR%\CD2.HPF" exit /b 1
if not exist "%CHK_DIR%\CD3.HPF" exit /b 1
exit /b 0

:fail
echo.
echo [FAILED]
echo [HINT] This patcher already uses PowerShell ExecutionPolicy Bypass.
echo [HINT] If it still fails, try:
echo        1) Extract ZIP to a writable folder (not Program Files)
echo        2) Right-click ZIP or files and use "Unblock" before running
pause
exit /b 1
