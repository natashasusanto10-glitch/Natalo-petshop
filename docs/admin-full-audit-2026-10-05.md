# Audit seluruh admin Natalo — 5 Oktober 2026

> Tindak lanjut: prioritas 1–4 telah diperbaiki dan direview di kode lokal. Lihat [hasil review perbaikan](admin-priority-1-4-review-2026-10-05.md). Temuan di bawah merekam kondisi saat audit, sebelum perbaikan; belum diverifikasi pada deployment baru.

## Kesimpulan

Admin sudah memiliki fondasi visual yang baik, tetapi kualitas antarhalaman belum merata. Produk, brand, feed, dashboard, dan form Promo Toko paling mendekati arah premium. Voucher, Flash Sale, impor, konfirmasi brand, dan beberapa halaman sistem masih membutuhkan perbaikan alur kerja.

Penilaian keseluruhan secara heuristik: **UI sekitar 8/10; UX sekitar 7/10; motion sekitar 8/10**. Angka ini merupakan penilaian pemeriksa, bukan hasil studi pengguna atau pengukuran performa. Nilai visual tidak menggantikan pemeriksaan keamanan dan ketepatan data.

## Metode dan cakupan

- Membaca halaman admin produksi melalui sesi admin aktif di `www.natalopetshop.com`.
- Memeriksa seluruh kelompok menu, halaman tambah, contoh edit produk, detail pesanan, modal brand, pemilih produk promo, dan pratinjau foto.
- Meninjau 26 halaman pada viewport 390 × 844 serta halaman desktop pada viewport browser normal.
- Membaca implementasi UI, query laporan, aksi kategori/voucher/brand/Flash Sale, dan komponen dialog/motion. Login dan packing slip diperiksa melalui kode saja.
- Kode lokal berubah selama audit karena pekerjaan lain; HEAD terakhir yang diamati adalah `835ce9e9`. Temuan produksi dan temuan kode lokal dibedakan di bawah. Tidak diasumsikan semua kode lokal identik dengan deployment.
- Tidak mengirim perubahan produk, promo, voucher, pesanan, moderasi, broadcast, impor, atau penghapusan. Tidak menjalankan build, migrasi, atau test suite.
- Screenshot bukti tersimpan lokal di `docs/implementation-review/audit-*`. Sebagian memuat data operasional/pelanggan; jangan dipublikasikan otomatis.

## Nilai per bagian

Skala 10. Nilai UX mencakup kejelasan, efisiensi, feedback, dan konsistensi; bukan sertifikasi fungsi backend. Baris dengan data kosong dinilai terutama dari struktur dan empty state.

| Bagian | UI | UX | Catatan utama |
|---|---:|---:|---|
| Ringkasan/dashboard | 8,8 | 8,5 | Hierarki dan prioritas operasional jelas; ada error React saat muat baru |
| Daftar pesanan | 8,2 | 7,8 | Filter terlalu tinggi sebelum baris pertama, terutama ponsel |
| Detail pesanan | 8,0 | 7,2 | Aksi dan istilah pembayaran perlu mengikuti status pesanan |
| Validasi pickup | 8,0 | 8,0 | Fokus pada satu tugas; transaksi validasi tidak dijalankan |
| Daftar produk | 8,6 | 8,4 | Edit cepat tetap tersedia, edit membuka tab baru |
| Tambah/edit produk | 8,8 | 8,6 | Struktur rapi; panah keyboard pratinjau foto berfungsi |
| Kategori | 8,0 | 7,0 | Nama dan slug perlu dipisahkan saat menyimpan perubahan |
| Brand | 8,8 | 8,5 | Modal dan pengembalian fokus baik |
| Konfirmasi brand | 7,0 | 6,3 | Terlalu banyak chip filter sebelum daftar pekerjaan |
| Stok | 8,0 | 7,0 | Tidak ada pencarian; badge sempit dan ringkasan ponsel terlalu tinggi |
| Pusat diskon | 8,0 | 7,5 | Akses buat/list berulang dan istilah belum seragam |
| Daftar Promo Toko | 7,8 | 7,8 | Struktur cukup jelas; konfirmasi lama belum konsisten |
| Form Promo Toko | 8,8 | 8,6 | Pemilih produk/varian dan alur penyuntingan paling matang |
| Flash Sale | 7,3 | 6,4 | Cakupan tab Semua tidak sesuai ekspektasi; form masih sederhana |
| Voucher | 7,5 | 6,1 | Target berbasis ID, angka tanpa pemisah, aturan diskon kurang jelas |
| Banner | 7,8 | 7,2 | Preview besar berulang; pengurutan kurang efisien |
| Popup peluncuran | 7,8 | 7,5 | Empty state cukup baik; konten aktif belum dinilai |
| Broadcast | 7,7 | 7,2 | Instruksi panjang mendominasi sebelum tindakan utama |
| Feed dan editor | 8,7 | 8,4 | Visual konsisten; unggah/proses media tidak dijalankan |
| Laporan feed | 7,8 | 7,1 | Klaim bersih perlu menunggu data; error masih memakai alert |
| Pelanggan | 8,1 | 6,7 | Daftar belum menyediakan jalur ke detail/riwayat pesanan |
| Ulasan | 7,8 | 7,1 | Kepadatan informasi tinggi, pencarian belum tersedia |
| Perubahan tanggal lahir | 7,4 | 6,8 | Instruksi berulang dan bahasa kurang konsisten |
| Laporan penjualan | 8,2 | 6,5 | Definisi produk terlaris belum menjamin transaksi sah |
| Pengaturan | 8,0 | 7,0 | Jelas sebagai halaman baca; bukan bukti layanan integrasi sehat |
| Riwayat aktivitas | 7,7 | 6,8 | Kode aksi mentah dan tabel ponsel kurang mudah dibaca |
| Flag penyalahgunaan | 7,8 | 6,5 | Antrean kosong tidak cukup untuk menyatakan sistem aman |
| Impor produk | 6,6 | 5,5 | Judul Excel tidak sesuai alur JSON; reset terlalu dekat dengan impor |
| Danger Zone | 7,5 | 7,0 | Konfirmasi bertahap tersedia; eksekusi tidak diuji |

## Temuan prioritas

### P1 — Pemeriksaan admin harus berada di setiap Server Action

**Bukti kode lokal:** beberapa aksi kategori, voucher, konfirmasi brand, dan pembuatan Flash Sale langsung mengubah Prisma tanpa pemeriksaan sesi/role di dalam fungsi aksi. Contoh:

- `app/admin/(protected)/categories/new/page.tsx`: `createCategory`.
- `app/admin/(protected)/categories/[id]/edit/page.tsx:23`: `updateCategory`.
- `app/admin/(protected)/vouchers/new/page.tsx:12`: `createVoucher`.
- `app/admin/(protected)/vouchers/page.tsx:80`: `toggleVoucher`, serta `deleteVoucher`.
- `app/admin/(protected)/brands/review/page.tsx:42`: `confirmBrand` dan aksi terkait.
- `app/admin/(protected)/diskon/flash-sale/new/page.tsx`: `createFlashSale`.

Layout memang memanggil pemeriksaan admin. Namun dokumentasi Next lokal pada `node_modules/next/dist/docs/01-app/02-guides/authentication.md` bagian Server Actions mengharuskan autentikasi/otorisasi pada aksi sendiri. Perlindungan layout tidak cukup sebagai batas keamanan aksi.

**Tindakan:** tambahkan guard admin bersama pada setiap fungsi perubahan data, lalu audit seluruh aksi dan route handler. Ini temuan statis; tidak dilakukan percobaan akses tanpa login dan tidak diklaim telah terjadi penyalahgunaan.

### P1 — Produk terlaris belum menyaring pembayaran/status

**Bukti kode lokal:** `app/admin/reports/page.tsx:43` mengelompokkan `orderItem` berdasarkan `name`, tanpa filter pembayaran/status order. Label sudah menyebut semua periode, sehingga masalahnya bukan label bulanan.

**Dampak:** item dari order belum dibayar/dibatalkan dapat ikut dihitung; produk bernama sama bisa tergabung dan perubahan nama bisa memecah hitungan.

**Tindakan:** tentukan definisi transaksi sah, filter relasi order, kelompokkan dengan identitas produk/varian, dan jelaskan omzet bruto/neto. Samakan batas tanggal WIB dengan dashboard; laporan saat ini memakai batas bulan dari waktu server.

### P2 — Edit nama kategori turut mengubah slug

**Bukti kode lokal:** `app/admin/(protected)/categories/[id]/edit/page.tsx:28` membentuk ulang slug dari nama lalu menyimpannya pada baris 35.

**Dampak yang mungkin:** mengubah nama menjadi “Kandang & Carrier” dapat mengubah slug `kandang` menjadi `kandang-carrier`, sementara app/filter/link masih menggunakan slug lama. Ini risiko dari kode, bukan regresi app yang direproduksi dalam audit ini.

**Tindakan:** tampilkan `name` dan pertahankan `slug` saat rename. Perubahan slug harus melalui migrasi yang disengaja.

### P2 — Error React berulang pada dashboard produksi

**Bukti produksi:** console tab dashboard baru menampilkan `Minified React error #418`, juga teramati pada pembukaan awal tab audit. Halaman tetap merender.

**Tindakan:** telusuri perbedaan render server/client melalui build pengembangan. Akar penyebab belum ditentukan; jangan menganggap seluruh motion bermasalah atau mengaitkannya ke feed berdasarkan log tab yang terkumpul.

### P2 — Flash Sale: tab Semua menyembunyikan riwayat lama

**Bukti UI:** total pernah Flash Sale 11, tetapi tab default kosong. **Bukti kode:** `app/admin/(protected)/diskon/flash-sale/page.tsx:57` membatasi tab Semua ke akhir promo lebih baru dari tujuh hari lalu; tab berakhir hanya 30 hari, sedangkan total menghitung seluruh riwayat.

**Tindakan:** sediakan periode yang terlihat dan empty state “Tidak ada dalam periode ini”. Form juga perlu feedback per field untuk input tidak valid; aksi saat ini dapat `return` tanpa pesan. Proses batch memakai beberapa update terpisah, sehingga penanganan kegagalan parsial perlu ditinjau.

### P2 — Voucher dan impor paling membutuhkan desain ulang alur

**Voucher:** pemilihan pelanggan/produk/kategori masih meminta ID, input nominal belum memakai pemisah ribuan, dan prioritas diskon nominal/persen kurang jelas. Gunakan pencarian/pemilih, format angka, contoh hasil diskon, dan ringkasan syarat sebelum simpan.

**Impor:** judul mengacu Excel, tetapi alur membaca JSON yang disediakan di deployment. Tidak ada pemilih berkas Excel. Pisahkan reset produk dari tugas impor dan jelaskan sumber, pratinjau, jumlah valid/gagal, serta hasil batch.

### P2 — Aksi detail pesanan tidak mengikuti status

**Bukti produksi:** pesanan contoh yang selesai masih menampilkan “Tandai kosong”. **Bukti kode:** `app/admin/(protected)/orders/[id]/page.tsx:213` merender aksi tanpa kondisi status. Backend pada `actions.ts:956` sudah menolak order DELIVERED/CANCELLED.

**Tindakan:** sembunyikan/nonaktifkan aksi dengan alasan pada status final. Terjemahkan `PICKED_UP` dan sesuaikan label “Total Bayar Tunai” dengan metode pembayaran. Guard backend sudah ada; masalah yang terlihat adalah penawaran aksi yang tidak dapat dilakukan.

### P2 — Empty state dan feedback belum selalu jujur/konsisten

- Flag penyalahgunaan menyatakan sistem “clean/Aman” ketika antrean kosong. Ganti menjadi fakta “Tidak ada flag terbuka” serta waktu/status pemindaian terakhir.
- Laporan feed memakai hitungan awal nol untuk subtitle bersih sebelum data selesai dimuat. Bedakan loading, error, kosong, dan berhasil.
- `DeletePromoTokoButton.tsx:22` dan `EndFlashSaleButton.tsx:22` masih memakai confirm browser; penanganan error keduanya dan moderasi feed masih memakai alert.
- Beberapa aksi kategori gagal/menolak tanpa feedback yang jelas.

**Tindakan:** gunakan dialog bersama, error di konteks aksi, toast yang dapat dibaca teknologi bantu, dan status loading/pending yang konsisten.

## Responsive, aksesibilitas, dan motion

### Yang sudah baik

- Tidak ditemukan overflow horizontal seluruh halaman pada 26 halaman ponsel yang diperiksa. Tabel riwayat aktivitas melebar di dalam area scroll sendiri.
- Tombol Simpan Produk berada di atas navigasi bawah; pemeriksaan hit target menunjukkan tombol bisa disentuh.
- Klik nama/edit produk membuka tab admin baru.
- ArrowRight pada pratinjau foto berpindah ke “Foto 2 dari 6”.
- Modal brand ditutup dengan Escape dan fokus kembali ke tombol Edit.
- Dialog bersama memakai fokus native dan pemulihan fokus. Toast sudah memiliki live region.
- Motion sumber menggunakan transisi singkat: perpindahan halaman sekitar 180 ms, layout sekitar 220 ms, dialog masuk 200 ms/keluar 120 ms. Dukungan reduced motion tersedia.

### Yang perlu dipoles

- Stok: badge “Menipis” terpecah pada kolom desktop sempit; pencarian produk tidak tersedia. Ringkasan lima kartu terlalu tinggi pada ponsel.
- Pesanan: padatnya ringkasan/filter menunda baris data pertama. Prioritaskan pencarian dan filter utama, lipat filter tambahan.
- Konfirmasi brand: banyak chip menghabiskan ruang sebelum pekerjaan utama.
- Riwayat aktivitas: tampilkan ringkasan manusiawi, jadikan kode teknis detail sekunder, gunakan kartu pada ponsel.
- Label form kategori/Flash Sale dan login perlu dihubungkan ke input melalui `htmlFor`/`id` atau mekanisme label lain.
- Metadata kecil/pucat perlu pengukuran kontras. Belum dilakukan pengukuran rasio WCAG atau audit screen reader penuh.
- Motion drag foto, pemrosesan media, dan seluruh state error/sukses belum diukur FPS/perangkat nyata. Penilaian motion mengacu kode dan interaksi terbatas, bukan jaminan semua animasi 60 FPS.

## Urutan perbaikan yang disarankan

1. Guard Server Actions dan ketepatan query laporan.
2. Pertahankan slug kategori dan telusuri error React dashboard.
3. Voucher, Flash Sale, serta impor: perbaiki alur dan feedback.
4. Pesanan, stok, konfirmasi brand, pelanggan: percepat pekerjaan harian dan responsive.
5. Seragamkan dialog, error, empty state, bahasa, dan label aksesibel.
6. Poles banner/broadcast/halaman sistem, kemudian ukur motion pada perangkat nyata.

## Batas kesimpulan

Audit ini tidak membuktikan integrasi Shopee/Tokopedia, pembayaran, pengiriman, kompresi/unggah video, broadcast, atau sinkronisasi ERP berfungsi end-to-end. Halaman pengaturan yang mencantumkan provider bukan pemeriksaan kesehatan integrasi. Halaman kosong tidak menyediakan contoh konten untuk semua state. Seluruh menu dicakup, tetapi tidak setiap record, form edit, status bisnis, atau transaksi diuji.

Hasil audit dibuat sebagai laporan. Tidak ada perbaikan aplikasi, commit, push, atau deploy yang dilakukan dalam tugas ini.
