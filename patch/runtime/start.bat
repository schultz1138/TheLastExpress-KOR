@echo off

cd /d "%~dp0"

set "INI_FILE=scummvm_k.ini"

if not exist "Saves" (
    mkdir "Saves"
)

start "" "scummvm_k.exe" ^
    -c "%INI_FILE%" ^
    --path="." ^
    --savepath=".\Saves" ^
    -n -f lastexpress

exit
