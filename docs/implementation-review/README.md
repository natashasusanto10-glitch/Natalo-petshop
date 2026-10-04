# Review lokal implementasi admin

Viewer ini memakai komponen React implementasi asli dengan data contoh. Tujuannya menilai tampilan dan interaksi tanpa menyentuh database atau layanan produksi.

## Menjalankan

Dari root repository, dengan dependensi yang sudah tersedia:

```powershell
node docs/implementation-review/build.mjs
python docs/implementation-review/serve.py
```

Buka `http://127.0.0.1:8770/admin/dashboard` atau `/admin/products`. Server hanya mendengarkan localhost. Aset hasil bundling `review.js` dan `review.css` diabaikan Git; jalankan kembali build setelah mengubah komponen.

## Cakupan

- Komponen asli: navigasi, form produk, editor variasi, media, dialog edit cepat, disclosure varian, pemilihan massal, tombol dan toast.
- Data contoh: produk tunggal/varian, pesanan, pelanggan, kategori, stok, metrik laporan, dan promosi.
- View asli dashboard, pesanan, pelanggan, laporan, pengaturan, promosi, kategori, dan stok memakai props fixture.
- Client asli banner, popup, broadcast, feed, form promo, dan flash sale juga tersedia.
- Pengganti lokal untuk `next/link`, `next/image`, dan `next/navigation`.
- Daftar produk dalam viewer adalah fixture representatif. Halaman server Next.js beserta query database tidak dijalankan oleh viewer ini.
- Request katalog ditangani fixture di `review.jsx`, request operasional yang didukung di `operational-review.jsx`; request lain ditolak. Perubahan contoh tidak menetap setelah halaman dimuat ulang.
- Tambahkan `?review-failure` pada URL daftar produk untuk melihat kegagalan GET varian, pesan error, dan Coba lagi.

- `?review-failure` pada banner/popup mensimulasikan respons gagal; pada form promo mensimulasikan GET pemilihan produk gagal.
- Halaman yang belum memiliki fixture menampilkan pemberitahuan cakupan, bukan tampilan rekaan dari halaman lain.

## Batas pemeriksaan

Viewer tidak membuktikan autentikasi server, transaksi Prisma, kompresi WASM, unggah TUS, pemrosesan video, sinkronisasi pencarian, email/restock, atau integrasi ERP. Pemeriksaan tersebut membutuhkan lingkungan backend pengujian terpisah.

Dokumentasi hasil per bagian ada di `../admin-premium-implementation-review-2026-10-04.md`. Screenshot lokal disimpan sebagai `desktop-form.jpg` dan `mobile-variants.jpg`.

Review lanjutan per halaman: `../admin-premium-operational-review-2026-10-04.md`.
