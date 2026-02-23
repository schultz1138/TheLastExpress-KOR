@echo off
setlocal

cd /d "%~dp0"

if not exist "scummvm_k.exe" (
    echo [ERROR] scummvm_k.exe not found.
    pause
    exit /b 1
)

set "INI_FILE=scummvm_k.ini"

if not exist "scummvm_k.ini" (
    echo [INFO] scummvm_k.ini not found. A new file may be created on first run.
)

start "" "scummvm_k.exe" -c "%INI_FILE%" --setup
exit /b 0
