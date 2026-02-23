@echo off
setlocal EnableExtensions EnableDelayedExpansion

cd /d "%~dp0"
set "GAME_DIR=%cd%"
set "MANIFEST_PATH=%GAME_DIR%\KOR_PATCH_INSTALL_MANIFEST.txt"

echo [STEP] 바탕화면 바로가기 삭제
set "DESKTOP_PATH="
for /f "usebackq delims=" %%D in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "[Environment]::GetFolderPath('Desktop')"`) do set "DESKTOP_PATH=%%D"
if defined DESKTOP_PATH (
    if exist "%DESKTOP_PATH%\The Last Express (KOR).lnk" (
        del /f /q "%DESKTOP_PATH%\The Last Express (KOR).lnk" >nul 2>&1
        if exist "%DESKTOP_PATH%\The Last Express (KOR).lnk" (
            echo [WARN] 바탕화면 바로가기를 삭제하지 못했습니다.
        ) else (
            echo [OK] 바탕화면 바로가기를 삭제했습니다.
        )
    )
)

if exist "%MANIFEST_PATH%" (
    echo [STEP] 매니페스트 기준 설치 파일 삭제
    for /f "usebackq delims=" %%L in ("%MANIFEST_PATH%") do call :process_line "%%L"
) else (
    echo [WARN] 설치 매니페스트를 찾지 못했습니다: %MANIFEST_PATH%
    echo [WARN] KOREAN.HPF와 바로가기만 삭제합니다.
)

if exist "%GAME_DIR%\KOREAN.HPF" (
    del /f /q "%GAME_DIR%\KOREAN.HPF" >nul 2>&1
)

if exist "%MANIFEST_PATH%" (
    del /f /q "%MANIFEST_PATH%" >nul 2>&1
)

if exist "%GAME_DIR%\python" (
    rmdir /s /q "%GAME_DIR%\python" >nul 2>&1
)

echo.
echo [DONE] 제거가 완료되었습니다.
pause
exit /b 0

:process_line
set "LINE=%~1"
if not defined LINE exit /b 0
if "!LINE:~0,1!"=="#" exit /b 0

if /I "!LINE:~0,4!"=="REL|" (
    set "REL=!LINE:~4!"
    call :delete_rel "!REL!"
    exit /b 0
)
if /I "!LINE:~0,9!"=="SHORTCUT|" (
    set "SC=!LINE:~9!"
    call :delete_abs "!SC!"
    exit /b 0
)
exit /b 0

:delete_rel
set "REL=%~1"
if not defined REL exit /b 0

if /I "%REL%"=="HD.HPF" exit /b 0
if /I "%REL%"=="CD1.HPF" exit /b 0
if /I "%REL%"=="CD2.HPF" exit /b 0
if /I "%REL%"=="CD3.HPF" exit /b 0
if /I "%REL%"=="HD_ALLSUBS.HPF" exit /b 0

set "TARGET=%GAME_DIR%\%REL%"
if exist "%TARGET%" (
    attrib -r -h -s "%TARGET%" >nul 2>&1
    del /f /q "%TARGET%" >nul 2>&1
    if exist "%TARGET%" (
        echo [WARN] "%REL%" 파일을 삭제하지 못했습니다.
    ) else (
        echo [OK] "%REL%" 파일을 삭제했습니다.
    )
)
exit /b 0

:delete_abs
set "TARGET=%~1"
if not defined TARGET exit /b 0
if exist "%TARGET%" (
    del /f /q "%TARGET%" >nul 2>&1
)
exit /b 0
