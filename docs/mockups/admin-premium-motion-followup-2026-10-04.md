# Penilaian mockup setelah motion — 4 Oktober 2026

## Hasil

Motion kini memberi kesinambungan saat berpindah halaman, membuka editor, memilih filter, menampilkan varian dan menyimpan perubahan. Aksi utama tersedia segera; transisi masuk tidak menunggu animasi keluar halaman sebelumnya.

| Aspek | Sebelum | Sesudah | Penjelasan |
|---|---:|---:|---|
| UI visual | 8 | 8 | Struktur visual dipertahankan; beberapa target sentuh mobile diperbesar. |
| UX | 7 | 7,5 | Pending, konfirmasi perubahan massal, fokus kembali dan pembatalan simpan lebih jelas. |
| Transisi | 4 | 8 | Durasi pendek, easing masuk/keluar dan backdrop selaras. |
| Micro interaction | 5 | 8 | Respons tekan, indikator tab, sorotan nilai, spinner dan toast tersedia. |
| Motion design | 4 | 8 | Gerak ringan menggunakan aturan durasi bersama dan reduced motion. |

Skor adalah penilaian desain subjektif. Tidak dilakukan pengukuran FPS atau evaluasi performa perangkat fisik.

## Yang diterapkan

- Perpindahan konten: fade + translateY 4 px selama 180 ms. Form memakai fade agar transform tidak mengubah posisi bilah simpan yang fixed.
- Dialog: fade + scale 0,98 → 1 selama 200 ms; keluar 140 ms. Backdrop mengikuti gerak. Isi menggulir terpisah dari header/footer.
- Tombol: perubahan warna/border sekitar 140 ms, tekanan scale 0,98 selama 100 ms.
- Menu mobile: masuk 220 ms, keluar 140 ms; veil ikut fade.
- Filter: hasil fade 150 ms; indikator tab berubah 180 ms. Pencarian tiap ketukan tetap langsung.
- Varian yang dibuka: fade 160 ms tanpa stagger panjang.
- Terapkan ke semua: sorotan draft dan pesan jumlah varian. Area pesan disediakan agar ukuran dialog multi varian tetap stabil.
- Penyimpanan harga/stok serta form: pending demonstrasi 450 ms, pencegahan kirim ganda, kemudian toast. Sel harga/stok yang berubah disorot sekitar 1,1 detik.
- Toast: masuk 160 ms, keluar 120 ms; perpindahan maksimal 8 px. Posisi mobile menyesuaikan keberadaan bilah simpan.
- Tombol header untuk mematikan motion; preferensi perangkat tetap diutamakan. Mode reduced motion menghentikan CSS animation/transition dan animasi JavaScript.

## Pemeriksaan langsung

- Edit harga Royal Canin: 285.000 → 289.000, status pending terlihat, dialog menutup dan fokus kembali ke tombol harga.
- Terapkan harga 400.000 ke dua varian Pro Plan: kedua input draft berubah dan pesan konfirmasi muncul.
- Simpan lalu segera Batal pada editor varian: harga induk tetap 365.000.
- Stok -1 ditolak dengan pesan validasi; Escape menutup editor.
- Motion nonaktif: transisi tombol terukur 0 s; navigasi tetap berjalan. Motion kemudian diaktifkan kembali.
- Form tambah produk pada mobile: contoh harga 45.000 tersimpan ke memori halaman setelah pending.
- Menu mobile membuka panel dan memindahkan fokus ke tombol tutup; konten belakang inert.
- Sintaks JavaScript diperiksa dengan parser Node. Tidak ada dependensi animasi baru.

## Perbaikan berikutnya

Keterbacaan teks pendukung, perlindungan draf belum disimpan, pemulihan posisi daftar setelah kembali dari form, dan keadaan kegagalan jaringan tetap menjadi prioritas berikutnya. Mockup belum terhubung ke backend, sehingga jeda simpan hanya memperagakan pending. Perilaku pada keyboard layar dan daftar varian panjang perlu dinilai pada tahap implementasi.

Seluruh perubahan berada pada mockup lokal. Produk dan transaksi nyata tidak digunakan.
