@echo off
title Village Market
cd /d "%~dp0"

echo ======================================================================
echo   VILLAGE MARKET - starting...
echo ======================================================================
echo.

where flutter >nul 2>nul
if errorlevel 1 (
    echo Flutter was not found. Open this folder in a terminal where "flutter" works.
    echo.
    pause
    exit /b
)

echo Rebuilding the game from the current code so you always play the latest version.
echo Press N within 5 seconds to skip the rebuild and use the last build.
echo.
choice /c YN /t 5 /d Y /n /m "Rebuild now? [Y/N] "
if errorlevel 2 goto serve

call flutter pub get
if errorlevel 1 goto failed
call flutter build web --release
if errorlevel 1 goto failed

:serve
if not exist "%~dp0build\web\index.html" (
    echo.
    echo build\web was not found and the build did not run. Run this file again and press Y.
    echo.
    pause
    exit /b
)

echo.
echo Starting the local server and opening your browser...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
pause
exit /b

:failed
echo.
echo ==================================================================
echo The build failed. Check the messages above, fix the errors, then run this file again.
echo ==================================================================
echo.
pause
exit /b
