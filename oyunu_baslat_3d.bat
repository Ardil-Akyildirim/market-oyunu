@echo off
chcp 65001 > nul
title 🏪 3D SÜPERMARKET SİMÜLATÖRÜ
cd /d "%~dp0"

echo ======================================================================
echo           🏪 3D SÜPERMARKET SİMÜLATÖRÜ BAŞLATILIYOR...
echo ======================================================================
echo.

if not exist "%~dp0supermarket_3d.html" (
    echo ==================================================================
    echo HATA: supermarket_3d.html dosyasi bulunamadi!
    echo ==================================================================
    echo.
    pause
    exit /b
)

echo Oyun tarayicinizda aciliyor...
echo.

start "" "%~dp0supermarket_3d.html"

echo Oyun acildi! Bu pencereyi kapatabilirsiniz.
timeout /t 3 > nul
exit
