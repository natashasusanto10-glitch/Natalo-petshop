# Mockup Promo Toko — 5 Oktober 2026

Referensi: screenshot Shopee dari pengguna. Mockup interaktif di `/admin/diskon/promo-toko/new?mockup` memakai data contoh dan state lokal; tidak menyimpan promo atau mengirim notifikasi.

## Desain
- Informasi dasar: nama internal, periode dan pilihan durasi.
- Produk dikelompokkan dengan thumbnail, kategori dan baris variasi.
- Harga awal, harga promo, persentase diskon, stok dan aktif/nonaktif.
- Harga memakai pemisah ribuan tanpa awalan Rp dalam input dan tanpa spinner.
- Seleksi massal, penerapan diskon, penghapusan pilihan dan penghapusan produk/variasi.
- Dialog lebar dengan kategori, pencarian, filter stok, pilih semua hasil tersedia, penanda sudah ditambahkan dan jumlah pilihan.
- Mobile menggunakan kartu variasi; tombol simpan di atas navigasi bawah.
- Motion 160–200 ms dengan reduced motion; dialog memakai komponen bersama admin.

## Review
Build viewer lulus. Browser review desktop 1440×1000 dan mobile 390×844: tidak ada overflow horizontal. Pencarian omega, pilih semua hasil, tambahkan 1 item dan penerapan diskon massal 15% diperiksa pada state lokal. Harga hasil membulat ke rupiah penuh sehingga persentase aktual dapat sedikit berbeda (8.650 menjadi 7.353 = 14,99%). Gambar contoh dengan ampersand diperbaiki agar SVG valid. Judul panjang pada mobile diberi ruang penuh, aksi hapus di baris berikutnya.

Penilaian subjektif: UI 8,8/10; UX 8,7/10; motion 8,5/10. Belum evaluasi penggunaan dengan ratusan produk atau profiling FPS. Belum terhubung dengan API produksi. Stok promosi dan batas pembelian Shopee tidak disimulasikan karena perlu desain dukungan backend terpisah.

Bukti: `implementation-review/promo-mockup-editor.png` dan `implementation-review/promo-mockup-picker.png`.
