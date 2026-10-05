# Review implementasi Promo Toko — 5 Oktober 2026

## Implementasi

Komponen bersama `PromoTokoForm` untuk tambah dan edit memakai desain yang disepakati. CSS terisolasi dengan prefiks pt. Tidak ada perubahan schema atau migrasi database.

- Panel informasi dasar, nama internal, periode dan pilihan durasi.
- Grid produk/variasi menggantikan tabel yang menyebabkan kolom harga menyempit. Mobile memakai kartu dengan label setiap harga.
- Pemilih produk lebar, kategori dari API, pencarian nama/brand/SKU, filter stok, seleksi seluruh hasil yang tersedia, dan indikator item sudah dipilih atau diblokir promo lain.
- Diskon massal pada item terpilih. Harga promo dan persentase diskon terhubung, dibulatkan ke rupiah penuh.
- Input harga berformat ribuan tanpa awalan Rp dan tanpa spinner.
- Aktif/nonaktif serta hapus produk atau variasi. Menghapus item membersihkan seleksi massalnya.
- Konfirmasi meninggalkan form melalui tombol kembali/batal; reload dan tutup tab belum dilindungi.
- Simpan dikunci selama request; fieldset ikut dikunci untuk mencegah perubahan yang belum masuk payload.
- Aturan promo berjalan, validasi maksimal 90 hari, pemeriksaan konflik API, create POST/edit PUT dan pengiriman preferensi notifikasi dipertahankan. Harga sama dengan harga awal tetap diizinkan mengikuti perilaku sebelumnya.
- Pencarian dibatalkan ketika parameter berubah dan saat dialog ditutup. Pilihan lintas hasil pencarian disimpan pada cache produk selama dialog terbuka.

## Review dan pemeriksaan

- Review kode sendiri: alur payload, konflik, deduplikasi, pilihan massal, input harga, cleanup request dan CSS mobile.
- TypeScript `tsc --noEmit --incremental false`: lulus.
- ESLint pada komponen dan layout: lulus.
- Build viewer esbuild: lulus.
- Diff check file yang diubah: lulus dengan peringatan normal LF/CRLF Windows.
- Review browser memakai komponen produksi dengan fixture dan respons API lokal, bukan data produksi.
- Desktop 1440×1000 dan mobile 390×844 ditinjau; tidak ditemukan overflow horizontal pada form.
- Diskon massal 15% menghasilkan 12.100 → 10.285 dan 20.000 → 17.000.
- Filter kategori Obat & Suplemen menghasilkan produk yang sesuai.
- Pilih semua hasil dan penambahan 1 produk diperiksa.
- Input 7350 tampil 7.350; persentase terkait diperbarui.
- Waktu mulai promo berjalan disabled.
- Batal meninggalkan form menampilkan konfirmasi; membatalkan konfirmasi mempertahankan isian.
- Simpan form kosong menampilkan kesalahan nama, periode dan item. Fokus ke input invalid ditambahkan setelah review.
- Pilih semua pada mobile terlihat setelah perbaikan terakhir.

## Motion dan penilaian

Feedback hover dan switch 160–180 ms; entrance panel 200 ms; dialog memakai komponen admin bersama. Reduced motion tersedia. Penilaian subjektif: UI 8,8/10, UX 8,8/10, motion 8,5/10. Tidak ada pengukuran FPS atau review penggunaan ratusan produk.

## Batas verifikasi

Simpan/push produksi dan pemeriksaan konflik pada database nyata belum dijalankan. Tidak menjalankan migrasi atau suite tes. Stok promosi/batas pembelian tambahan dari Shopee belum ditambahkan. Belum commit, push atau deploy pada pekerjaan ini.

## Hasil lokal

http://127.0.0.1:8770/admin/diskon/promo-toko/review-promo/edit

Bukti gambar: `implementation-review/promo-implementation-editor.png`, `promo-implementation-picker.png`, `promo-implementation-mobile.png`.
