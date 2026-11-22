@echo off
chcp 65001 > nul
title 🏪 2D SÜPERMARKET OYUNU
cd /d "%~dp0"

echo ======================================================================
echo           🏪 2D MARKET OYUNU BAŞLATILIYOR...
echo ======================================================================
echo.

if not exist "%~dp0build\web\index.html" (
    echo ==================================================================
    echo HATA: build\web klasoru bulunamadi!
    echo Lutfen ZIP dosyasini 'Tumunu Ayikla' diyerek tam cikardiginizdan emin olun.
    echo ==================================================================
    echo.
    pause
    exit /b
)

echo Oyun sunucusu baslatiliyor ve tarayicida aciliyor...
echo.

where node >nul 2>nul
if %ERRORLEVEL% equ 0 (
    node server.js
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
)

pause
