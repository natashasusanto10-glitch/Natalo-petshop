@echo off
title Generate Judul Produk dengan AI
echo ========================================
echo   GENERATE JUDUL PRODUK DENGAN GPT AI
echo ========================================
echo.
echo Script ini akan membuat ulang judul semua produk
echo menggunakan AI agar lebih rapi dan menarik.
echo.
echo ESTIMASI WAKTU: 10-15 menit untuk 2223 produk
echo Jangan tutup jendela ini selama proses berjalan!
echo.
pause

cd /d "%~dp0"

echo.
echo Memulai generate judul...
echo.

node prisma/generate-titles.mjs

echo.
if errorlevel 1 (
    echo ========================================
    echo   GAGAL! Cek pesan error di atas.
    echo ========================================
) else (
    echo ========================================
    echo   SELESAI! Judul produk sudah diperbarui.
    echo   Sekarang jalankan IMPORT-PRODUK.bat
    echo   untuk memasukkan ke database.
    echo ========================================
)

echo.
pause
