@echo off
setlocal EnableExtensions
call :init_utf8

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PATCH_ROOT=%%~fI"
set "CONVERT_SCRIPT=%PATCH_ROOT%\scripts\convert_tsv_to_utf8.ps1"

if not exist "%CONVERT_SCRIPT%" (
    echo [ERROR] Required file not found: scripts\convert_tsv_to_utf8.ps1
    goto :fail
)

if "%~1"=="" (
    echo [STEP] Convert default TSV files in translation folder
    if exist "%SCRIPT_DIR%subko.tsv" (
        powershell -NoProfile -ExecutionPolicy Bypass -File "%CONVERT_SCRIPT%" "%SCRIPT_DIR%subko.tsv"
        if errorlevel 1 goto :fail
    ) else (
        echo [WARN] Missing: "%SCRIPT_DIR%subko.tsv"
    )
    if exist "%SCRIPT_DIR%kosubs.tsv" (
        powershell -NoProfile -ExecutionPolicy Bypass -File "%CONVERT_SCRIPT%" "%SCRIPT_DIR%kosubs.tsv"
        if errorlevel 1 goto :fail
    ) else (
        echo [WARN] Missing: "%SCRIPT_DIR%kosubs.tsv"
    )
) else (
    :arg_loop
    if "%~1"=="" goto :done
    powershell -NoProfile -ExecutionPolicy Bypass -File "%CONVERT_SCRIPT%" "%~1"
    if errorlevel 1 goto :fail
    shift
    goto :arg_loop
)

:done
echo.
echo [DONE] TSV encoding conversion complete.
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

:fail
echo.
echo [FAILED] TSV encoding conversion failed.
pause
call :restore_cp
exit /b 1
