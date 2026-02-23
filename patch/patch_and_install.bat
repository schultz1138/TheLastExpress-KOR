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
        echo [ERROR] Missing required files.
        echo         Expected:
        echo           HD.HPF in game root
        echo           CD1.HPF, CD2.HPF, CD3.HPF in game root or data/Data folder
        goto :fail
    )
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

echo [STEP] Build KOREAN.HPF
if defined ALLSUBS_HPF (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -GameDir "%GAME_DIR%" -AllSubsHpf "%ALLSUBS_HPF%"
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
)

echo [STEP] Create desktop shortcut
set "GAME_DIR_PS=%GAME_DIR%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$ErrorActionPreference='Stop';" ^
 "$DesktopPath=[Environment]::GetFolderPath('Desktop');" ^
 "if([string]::IsNullOrWhiteSpace($DesktopPath)){throw 'Desktop path not found.'};" ^
 "$WshShell=New-Object -ComObject WScript.Shell;" ^
 "$Shortcut=$WshShell.CreateShortcut((Join-Path $DesktopPath 'The Last Express (KOR).lnk'));" ^
 "$GameDir=$env:GAME_DIR_PS;" ^
 "$TargetPath=(Join-Path $GameDir 'start.bat');" ^
 "if(-not (Test-Path $TargetPath)){throw 'start.bat not found in game folder.'};" ^
 "$Shortcut.TargetPath=$TargetPath;" ^
 "$Shortcut.WorkingDirectory=$GameDir;" ^
 "$IconPath=(Join-Path $GameDir 'lastexpress.ico');" ^
 "if(Test-Path $IconPath){$Shortcut.IconLocation=$IconPath};" ^
 "$Shortcut.Save()"
if errorlevel 1 (
    echo [WARN] Desktop shortcut creation failed.
) else (
    if exist "%GAME_DIR%\lastexpress.ico" (
        echo [INFO] Desktop shortcut created with lastexpress.ico
    ) else (
        echo [WARN] lastexpress.ico not found. Shortcut uses default icon.
    )
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
call :has_archive "%CHK_DIR%" "CD1.HPF"
if errorlevel 1 exit /b 1
call :has_archive "%CHK_DIR%" "CD2.HPF"
if errorlevel 1 exit /b 1
call :has_archive "%CHK_DIR%" "CD3.HPF"
if errorlevel 1 exit /b 1
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
echo [HINT] This patcher already uses PowerShell ExecutionPolicy Bypass.
echo [HINT] If it still fails, try:
echo        1) Extract ZIP to a writable folder (not Program Files)
echo        2) Right-click ZIP or files and use "Unblock" before running
echo        3) Re-extract the latest release ZIP and run again
pause
exit /b 1
