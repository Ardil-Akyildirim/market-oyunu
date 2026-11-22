@echo off
title Village Market
cd /d "%~dp0"

echo ======================================================================
echo   VILLAGE MARKET - starting...
echo ======================================================================
echo.

if exist "%~dp0build\web\index.html" (
    echo Ready build found! Press R within 2 seconds to force a full rebuild,
    echo or wait to launch the latest build immediately.
    echo.
    choice /c LR /t 2 /d L /n /m "[L] Launch immediately (default) / [R] Rebuild from source: "
    if errorlevel 2 goto rebuild
    goto serve
)

:rebuild
where flutter >nul 2>nul
if errorlevel 1 (
    echo Flutter was not found. Open this folder in a terminal where "flutter" works.
    echo.
    pause
    exit /b
)

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
