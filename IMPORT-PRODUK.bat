@echo off
title Import Produk ke Database
echo ========================================
echo   IMPORT PRODUK DARI EXCEL KE DATABASE
echo ========================================
echo.

cd /d "%~dp0"

echo Mengecek Node.js...
node --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Node.js tidak ditemukan!
    echo Silakan install Node.js dari https://nodejs.org
    pause
    exit /b 1
)

echo Node.js OK
echo.
echo Memulai import produk... (proses ini butuh beberapa menit)
echo.

node_modules\.bin\dotenv -e .env.local -- node_modules\.bin\tsx prisma/seed.ts

echo.
if errorlevel 1 (
    echo ========================================
    echo   GAGAL! Ada error saat import.
    echo   Screenshot pesan error di atas.
    echo ========================================
) else (
    echo ========================================
    echo   SELESAI! Produk berhasil diimport.
    echo ========================================
)

echo.
pause
