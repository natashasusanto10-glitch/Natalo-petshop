# Penilaian mockup admin Natalo — 4 Oktober 2026

## Kesimpulan

Mockup sudah memiliki arah visual yang bersih dan konsisten. Hierarki kerja admin dan edit cepat harga/stok sudah tepat. Kesan premium masih tertahan oleh teks kecil, beberapa target klik kecil, perlindungan draf yang belum tersedia, dan perpindahan antarkeadaan yang mendadak.

Skor berikut merupakan penilaian desain subjektif, bukan hasil pengukuran performa atau sertifikasi aksesibilitas.

| Aspek | Skor | Dasar penilaian |
|---|---:|---|
| UI visual | 8/10 | Warna, whitespace, kartu, sidebar dan aksi utama konsisten; metadata terlalu kecil dan pucat. |
| UX operasional | 7/10 | Edit cepat dan varian mudah diakses; draf dan konteks kembali ke daftar perlu dilindungi. |
| Transisi | 4/10 | Menu mobile dan toast memiliki transisi; halaman, dialog, tab dan varian berubah seketika. |
| Micro interaction | 5/10 | Hover, focus, validasi dan toast tersedia; feedback tekan serta tahapan penyimpanan belum dirancang lengkap. |
| Motion design | 4/10 | Gerak masih terpisah, belum memakai aturan durasi, easing dan arah yang konsisten. |

## Cakupan dan metode

- Skill `ui-ux-pro-max`: checklist review, pencarian design system, dan panduan animation/easing/reduced motion/loading.
- Inspeksi sumber HTML/CSS/JavaScript mockup untuk perilaku bersama seluruh halaman.
- Inspeksi browser langsung pada ringkasan desktop, daftar produk, form tambah produk, serta dialog harga varian di desktop dan mobile.
- Ukuran inspeksi: 1440 × 1000 dan 390 × 844. Ukuran browser dikembalikan setelah penilaian.
- Fokus pada mockup lokal dengan data contoh. Koneksi backend, proses unggah nyata, dan kecepatan perangkat fisik tidak dinilai.
- Rekomendasi otomatis skill yang mengarah ke landing page dengan judul sangat besar tidak dipakai: konteks Natalo adalah workspace admin dengan tabel dan formulir.

## Yang sudah kuat

1. Sidebar mengelompokkan pekerjaan toko; judul halaman, breadcrumb dan tombol utama mudah dikenali.
2. Dashboard menempatkan prioritas harian di dekat metrik, sehingga pekerjaan berikutnya terlihat jelas.
3. Harga dan stok bisa diedit langsung dari daftar melalui dialog. Produk bervarian memiliki edit per varian dan penerapan massal. Pola ini harus dipertahankan.
4. Form produk dibagi menjadi informasi produk, penjualan dan pengiriman, dengan pratinjau katalog.
5. Tombol simpan mobile sudah berada di atas navigasi bawah. Pada ukuran yang diperiksa, keduanya tidak saling menutupi.
6. Fokus keyboard terlihat; dialog mengarahkan fokus ke input pertama. Penyimpanan quick edit mengembalikan fokus ke pemicu.
7. Toast menggunakan pengumuman untuk pembaca layar. Preferensi reduced motion sudah mematikan transisi.

## Temuan dan prioritas

### P1 — Keterbacaan dan kenyamanan klik

Metadata/SKU berukuran 9–11 px. `.sku` terukur 10 px dengan warna `#8e9aad`. Kontras warna ini terhadap putih sekitar 2,85:1; warna muted `#758196` sekitar 3,93:1. Warna utama `#1a2941` memiliki kontras yang kuat.

Rekomendasi: metadata minimal 12 px, teks utama 14–16 px, dan warna metadata lebih gelap. Pertahankan angka harga/stok sebagai informasi dominan. Gunakan angka tabular agar kolom mudah dibandingkan.

Tombol membuka varian hanya sekitar 13,5 px tinggi pada desktop; quick edit 32 px, ikon tutup/menu 36 px. Pada mobile, beberapa tombol dialog masih 38 px. Perbesar area interaksi mobile menjadi setidaknya 44 px tanpa harus memperbesar ikon. Input form mobile masih 13 px; naikkan menjadi 16 px agar lebih nyaman dibaca, lalu periksa pada perangkat nyata.

### P1 — Draf dan konteks kerja

`route()` membangun ulang isi halaman dan memanggil `window.scrollTo(0,0)`. Form belum memiliki pemeriksaan perubahan yang belum disimpan. Berpindah menu dapat membuang isi form; kembali ke katalog membawa pengguna ke atas halaman.

Rekomendasi: tampilkan status “Ada perubahan belum disimpan”, lindungi navigasi setelah form berubah, dan pulihkan posisi daftar serta fokus ke produk yang baru diedit. Filter dan pencarian yang sudah tersedia perlu tetap dipertahankan.

### P2 — Dialog dan kontinuitas

Dialog harga/stok terukur tanpa animation dan transition duration 0 s. Backdrop juga muncul seketika. Footer dialog masih `position: static`; dua varian muat pada ukuran mobile yang diperiksa, tetapi daftar panjang dan keyboard layar belum dinilai.

Rekomendasi: animasi masuk singkat, keluar lebih cepat, serta area isi yang menggulir dengan tombol aksi tetap mudah dicapai. Pertahankan judul produk dan label varian saat scrolling.

### P2 — Feedback penyimpanan

Quick edit saat ini mengubah fixture langsung, menutup dialog, membangun ulang baris, lalu menampilkan toast. Hover tombol tersedia, tetapi belum memiliki transisi halus atau keadaan ditekan yang konsisten.

Rekomendasi: saat dihubungkan ke backend, urutkan keadaan “Simpan” → “Menyimpan…” → berhasil/gagal. Cegah pengiriman ganda. Jika gagal, pertahankan nilai yang diketik dan tampilkan pesan di dialog. Setelah berhasil, sorot singkat sel yang berubah dan kembalikan fokus. Jangan menganggap animasi sukses sebagai bukti penyimpanan server.

## Spesifikasi motion yang disarankan

| Interaksi | Gerak | Durasi yang disarankan |
|---|---|---|
| Hover tombol/nav | Perubahan warna latar, border dan ikon | 120–160 ms |
| Tekan tombol | Scale ringan 0,98 untuk tombol aksi; kembali saat dilepas | 80–120 ms |
| Pergantian halaman | Fade konten, perpindahan vertikal maksimal 4 px; sidebar tetap stabil | 160–180 ms |
| Dialog masuk | Opacity 0 → 1, scale 0,98 → 1; backdrop fade | 200 ms / backdrop 150 ms |
| Dialog keluar | Fade dan scale ringan menuju keadaan awal | 140 ms |
| Menu mobile | Slide horizontal dengan ease-out saat masuk, ease-in saat keluar; veil ikut fade | 200–240 ms |
| Tab/filter | Perubahan warna dan indikator aktif; hasil tetap segera tersedia | 150 ms |
| Membuka varian | Fade isi yang baru terlihat, parent tetap menjadi jangkar | 150–180 ms |
| Harga/stok berhasil berubah | Sorotan warna lembut pada sel terkait, kemudian kembali normal | Transisi 180 ms; sorotan sekitar 1 detik |
| Toast | Fade + translateY maksimal 8 px, keluar lebih cepat | Masuk 160 ms, keluar 120 ms; terbaca 3–4 detik |

Gunakan token durasi dan easing bersama. Prioritaskan transform/opacity dan sebutkan properti transisi secara eksplisit. Hindari animasi besar pada seluruh tabel, stagger panjang, counter angka dashboard yang berjalan setiap navigasi, dan efek memantul berulang.

Reduced motion: pertahankan perubahan warna, pesan dan fokus; hilangkan perpindahan/scale. Aturan existing perlu mencakup animation juga jika keyframes ditambahkan. Transisi tidak boleh menunda tersedianya aksi utama.

## Urutan peningkatan

1. Keterbacaan, target sentuh, perlindungan draf dan pemulihan konteks daftar.
2. Dialog harga/stok, tombol hover/press, feedback simpan dan sorotan sel.
3. Transisi halaman, menu mobile, tab dan varian menggunakan token yang sama.
4. Evaluasi lanjutan dengan keyboard layar, varian panjang, kegagalan jaringan dan data katalog nyata saat implementasi siap.

Penilaian ini tidak mengubah HTML mockup atau aplikasi produksi.
