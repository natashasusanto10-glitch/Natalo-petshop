# Review mockup Brand — 5 Oktober 2026

## Penyempurnaan lanjutan

Tab sekarang bernama **8 Brand Utama**, dengan batas delapan posisi (batas lama 18 telah diperbaiki). Setiap posisi mempunyai aksi Ganti brand dan dialog pencarian pengganti. Kandidat yang sudah terpilih tidak diduplikasi; brand nonaktif atau tanpa logo belum dapat dipilih. Brand yang diganti kembali ke daftar lainnya yang diurutkan A–Z. Baris daftar desktop dipadatkan dari 90 ke 76 px.

Build viewer berhasil. Review browser memastikan penggantian Royal Canin dengan Animal & Co mempertahankan delapan posisi, memunculkan status perubahan belum disimpan, dan pembatalan mengembalikan susunan awal. Pada lebar 390 px tidak ditemukan overflow horizontal; kartu urutan dengan tombol pengganti berukuran 108 px tinggi. Screenshot terbaru: `implementation-review/brand-mockup-polished.png`. Logo masih monogram contoh; performa drag pointer belum diukur.

## Ruang lingkup

Mockup interaktif di `http://127.0.0.1:8770/admin/brands`. Seluruh angka dan logo monogram merupakan data contoh. Penyimpanan hanya mengubah state lokal; reload mengembalikan data awal. Tidak ada perubahan ke database atau halaman Brand produksi.

## Perbaikan

- Semua Brand menjadi tampilan awal, dengan pencarian, filter status/logo, dan pengurutan nama atau jumlah produk.
- Ringkasan membedakan jumlah brand dari jumlah produk yang perlu konfirmasi.
- Tambah/edit memakai panel kanan, satu logo, nama, status, dan pengaturan lanjutan yang dilipat.
- Urutan di Aplikasi memiliki pengurutan pointer dan keyboard, animasi perpindahan 220 ms, serta animasi pelepasan 160 ms. Preferensi reduced motion dihormati.
- Perubahan urutan yang belum disimpan menawarkan simpan atau batalkan ketika pindah tab.
- Layar kecil memakai ringkasan 2×2, form selebar layar, dan kartu urutan setinggi 72 px.

## Review yang dilakukan

- Build viewer lokal berhasil; tidak memakai script build aplikasi yang menjalankan migrasi.
- Pencarian Kaniva, hasil kosong, tambah brand lokal, edit, dan pembatalan form ditinjau melalui browser.
- Pengurutan keyboard dan dialog perubahan urutan belum disimpan berhasil diperiksa.
- Fokus awal form berada pada nama, bukan input unggah file tersembunyi.
- Pada viewport 390×844, form selebar 390 px dan tidak ditemukan overflow horizontal.
- Tampilan desktop 1440 px diperiksa dan screenshot disimpan.
- `git diff --check` berhasil. ESLint default mengabaikan file JSX dokumentasi; hasilnya bukan kelulusan lint.

## Penilaian dan batasan

Penilaian visual subjektif: UI 8,5/10 dan UX 8,5/10. Hierarki, pencarian, dan form lebih jelas daripada tampilan sebelumnya. Durasi motion sudah ditetapkan, tetapi drag pointer dan performa frame belum diukur langsung. Penilaian kelancaran final perlu penggunaan langsung.

Upload dan antrean konfirmasi masih simulasi. Logo monogram perlu diganti logo asli ketika implementasi disetujui. Integrasi API, penyimpanan urutan, dan perilaku data produksi belum termasuk mockup ini.
