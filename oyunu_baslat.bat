@echo off
title Village Market
cd /d "%~dp0"

echo ======================================================================
echo   VILLAGE MARKET - starting...
echo ======================================================================
echo.

if not exist "%~dp0build\web\index.html" (
    echo ==================================================================
    echo build\web folder not found. Build the web version first:
    echo.
    echo     flutter build web --release
    echo.
    echo Then run this file again.
    echo ==================================================================
    echo.
    pause
    exit /b
)

echo Starting the local server and opening your browser...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"

pause
