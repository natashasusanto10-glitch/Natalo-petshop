# Review foto varian — 5 Oktober 2026

## Penilaian sebelum implementasi

Penilaian subjektif mockup: UI 8/10, UX 7/10. Thumbnail lebih jelas, tetapi target aksi perlu diperbesar, preview perlu dipisahkan dari crop, dan kegagalan upload harus mempertahankan foto lama.

## Implementasi

- Foto utuh 76 px digabung dengan nama varian. Tombol edit/hapus tidak lagi menutup gambar dengan lingkaran merah besar.
- Preview terpisah dari editor crop persegi; mendukung geser, panah keyboard, zoom, putar 90 derajat, reset, dan ganti foto.
- Hasil crop diekspor maksimal 1200 px, JPEG 0.88, lalu melalui helper kompresi/upload admin yang ada.
- Foto lama baru diganti setelah upload sukses. Saat menyimpan, kontrol dan penutupan dialog diblokir.
- Pelepasan foto membutuhkan konfirmasi dan berlaku setelah produk disimpan; file di server tidak dihapus.
- Animasi dialog memakai komponen bersama (buka 200 ms/tutup 120 ms) dan reduced motion. Isi dialog dipertahankan selama animasi tutup.

## Review selesai

- ESLint dan TypeScript (`tsc --noEmit`) lolos.
- Viewer lokal dengan data contoh: preview, putar, zoom, panah keyboard, reset, pembatalan dan tampilan 390 x 844 diperiksa.
- Kegagalan upload di fixture menampilkan pesan, mengaktifkan kembali kontrol, dan mempertahankan foto lama.
- Build terbaru diperiksa pada tab baru: isi crop tetap utuh selama penutupan; membuka ulang foto yang sama memuat ulang gambar dan mengaktifkan tombol simpan.
- Bukti gambar: `implementation-review/variant-photo-crop-review.png` (gambar fixture, bukan produk produksi).

Penilaian subjektif setelah implementasi: UI 8.5/10, UX 8.5/10. Target aksi jelas, gambar terbaca, dan alur crop lebih aman.

## Batas review

Upload sukses ke storage produksi dan CORS foto lama belum diverifikasi. Foto remote yang menolak CORS memunculkan pesan untuk memilih foto dari perangkat. Review motion bersifat fungsional/visual, tanpa pengukuran frame rate.

Perubahan masih lokal; belum commit, push, atau deploy.
