@echo off
net session >nul 2>&1
if %errorLevel% == 0 goto :run

powershell -WindowStyle Hidden -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs -WindowStyle Hidden"
exit /b

:run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0disk_check.ps1"

if %errorLevel% neq 0 (
    echo.
    echo ERROR: PowerShell exited with code %errorLevel%
    echo Make sure disk_check.ps1 is in the same folder as this .bat file.
    pause
)
