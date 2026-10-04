# Review lanjutan halaman admin — 4 Oktober 2026

## Cakupan perubahan

- Pesanan: empat kartu ringkasan operasional, pintasan ke verifikasi/pengemasan/pickup/semua pesanan. Pencarian, filter, daftar, dan pagination dalam satu panel. Filter mobile dapat digeser horizontal. Nominal total tidak terpotong. Tanggal memakai WIB.
- Pelanggan: pencarian dan daftar dalam satu panel, judul kolom konsisten, fallback nama kosong, tanggal registrasi WIB. Data dan pagination tetap dari query yang sudah ada.
- Pantau stok: judul dan hierarki diperjelas, filter dan daftar dalam satu panel, angka menipis/habis dibedakan dengan warna serta label. Edit tetap membuka tab admin baru.
- Laporan: kartu putih dengan penekanan pada angka pendapatan, header selaras dengan Ringkasan. Definisi dan periode metrik sebelumnya dipertahankan.
- Promosi dan Pengaturan: header dan identitas visual diselaraskan. Fitur yang belum tersedia tetap tidak dapat digunakan; layanan di Pengaturan tetap baca saja.
- Kartu ringkasan tidak melompat saat hover; perubahan border, bayangan, dan warna berlangsung 180 ms. Reduced motion meniadakan transisi baru.

## Review yang dilakukan

Komponen React aktual dibundel di viewer lokal port 8770 menggunakan data contoh. Review visual dilakukan pada desktop 1440 × 1000 dan mobile 390 × 844 untuk keenam halaman.

- Pintasan verifikasi membuka satu pesanan contoh dan menunjukkan banner filter.
- Disclosure pengiriman/pembayaran membuka konten dengan aria-expanded=true.
- Pencarian pelanggan yang tidak ditemukan menampilkan keadaan kosong; Reset mengembalikan daftar.
- Tab varian stok terbuka, tautan Kelola tetap target=_blank.
- Pada mobile Pesanan dan Promosi, lebar dokumen sama dengan viewport; daftar tidak menyebabkan scroll horizontal halaman.
- Console viewer tidak menunjukkan warning/error pada review akhir.
- ESLint pada berkas TypeScript yang diubah: lulus.
- TypeScript proyek (--noEmit --incremental false): lulus.
- Build viewer: lulus. git diff --check: tidak ada whitespace error (terdapat pemberitahuan konversi line ending pada workspace Windows).

Review menemukan dan memperbaiki dua masalah: nominal harga terpotong menjadi dua baris di desktop, serta filter mobile yang mengambil terlalu banyak tinggi layar. Ikon kartu accent juga diberi warna biru agar terlihat di atas kartu putih.

## Review query

Pesanan menambah dua query count baca saja untuk bukti pembayaran menunggu verifikasi dan pesanan pickup lunas yang siap diambil. Predikat count sesuai dengan filter tujuan kartu. Kartu menampilkan ringkasan seluruh pesanan, bukan hasil pencarian aktif. Angka tersebut diberi nama region "Ringkasan semua pesanan".

Query tidak dijalankan terhadap database produksi. Tidak ada migrasi atau operasi data saat review. Biaya dan performa query produksi belum diukur. Viewer tidak membuktikan alur pembayaran, pengiriman, atau tindakan detail pesanan berjalan end-to-end.

## Penilaian desain lokal (subjektif)

| Halaman | UI | UX |
| --- | --- | --- |
| Pesanan | 8,7 | 8,6 |
| Pelanggan | 8,6 | 8,5 |
| Pantau stok | 8,5 | 8,4 |
| Laporan | 8,6 | 8,4 |
| Promosi | 8,5 | 8,4 |
| Pengaturan | 8,6 | 8,4 |

Motion: 8,5 untuk interaksi yang direview; bukan sertifikasi kelancaran semua perangkat. Halaman stok mobile masih memerlukan scroll melewati lima kartu ringkasan; halaman laporan mempertahankan periode metrik berbeda dengan label eksplisit.

Halaman detail, promosi anak, konten, moderasi, dan alat pengelolaan lainnya tidak termasuk review visual ulang pada sesi ini. Perubahan sebelumnya tetap ada. Belum commit, push, atau deploy.

## Bukti

- `implementation-review/orders-refined-desktop.png`
- `implementation-review/orders-refined-mobile.png`
- `implementation-review/customers-refined-desktop.png`
- `implementation-review/stock-refined-desktop.png`
