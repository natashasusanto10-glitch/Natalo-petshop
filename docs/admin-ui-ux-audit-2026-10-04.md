# Audit UI/UX Admin Natalo Petshop

Tanggal: 4 Oktober 2026. Metode: inspeksi halaman admin setelah login dan pembacaan kode lokal. Tampilan desktop diperiksa pada 1365 × 900; alur produk dan pesanan diperiksa juga pada 390 × 844. Penilaian bersifat heuristik, bukan hasil pengukuran waktu kerja staf atau pengujian pengguna.

Tidak ada data produksi, konfigurasi, atau kode aplikasi yang diubah. Form tidak dikirim; tindakan hapus, broadcast, sinkronisasi, pembayaran, dan perubahan pesanan tidak dijalankan. Keberhasilan transaksi backend tidak dapat disimpulkan dari audit ini. Kode lokal bisa berbeda dari versi deployment.

## Kesimpulan

- UI visual: **7/10**. Identitas warna, kartu, badge, dan struktur dasar sudah cukup konsisten.
- UX operasional: **6/10**. Banyak fungsi tersedia, tetapi kepadatan daftar, istilah teknis, panjang form, dan prioritas tindakan memperlambat pekerjaan.
- Ponsel: belum nyaman untuk semua pekerjaan admin. Ada masalah nyata pada tombol simpan produk yang tertutup navigasi bawah.
- Arah terbaik: perbaikan bertahap pada komponen bersama dan alur paling sering dipakai, sambil menjaga batas tanggung jawab dengan ERP.

## Temuan prioritas

### P1 — Tombol simpan produk tertutup navigasi bawah pada ponsel

**Bukti visual dan DOM:** pada `/admin/products/new`, viewport 390 × 844, tombol Simpan Produk berada pada y=771–815. Elemen yang menerima sentuhan di tengah tombol adalah tautan Produk pada navigasi bawah. Dengan demikian tombol terlihat sebagian tetapi area sentuhnya tertutup.

**Dampak:** staf dapat kembali ke daftar produk ketika bermaksud menyimpan.

**Perbaikan:** tempatkan bilah simpan di atas navigasi bawah dan safe area; sediakan padding konten yang sesuai. Pada desktop, sejajarkan bilah tindakan dengan area form. Komponen terkait: `components/admin/ProductForm.tsx` (bilah sticky `bottom-4`) dan `components/AdminNav.tsx`.

### P1 — Makna angka laporan belum konsisten

**Bukti kode:** `app/admin/reports/page.tsx` memfilter pendapatan berdasarkan pembayaran PAID dan periode bulan, sedangkan query produk terlaris menggabungkan seluruh `orderItem` tanpa filter tanggal maupun status pembayaran. Produk dikelompokkan berdasarkan nama. Daftar status yang ditampilkan juga menggunakan daftar tetap berisi lima status.

**Dampak:** pengguna dapat mengira produk terlaris mengikuti bulan yang tampil pada judul, padahal datanya tidak memakai batas tersebut; item pesanan yang tidak dibayar dapat ikut dihitung.

**Perbaikan:** tambahkan periode yang jelas; samakan definisi setiap metrik atau beri label eksplisit; gunakan identitas produk untuk agregasi; cocokkan seluruh status bisnis yang masih digunakan. Konfirmasi definisi laporan dengan pemilik operasional sebelum mengubah query.

### P2 — Daftar produk terlalu renggang untuk katalog besar

**Bukti visual:** katalog berisi 1.646 produk. Pada desktop, tombol Edit, Arsipkan, dan Hapus bertumpuk sehingga hanya sekitar 3–4 baris terlihat dalam layar 900 piksel.

**Perbaikan:** gunakan baris tabel lebih ringkas; jadikan Edit tindakan utama; pindahkan arsip/hapus ke menu tambahan; pertahankan thumbnail kecil dan informasi SKU, harga, stok. Perluas pencarian ke SKU bila backend mendukungnya. Di ponsel, ringkas tinggi kartu dan hindari tombol hapus yang mendapat ruang setara dengan edit.

### P2 — Form voucher mengharuskan pengguna memahami ID internal

**Bukti visual dan kode:** form voucher baru/edit menyediakan kolom user ID, product ID, dan category ID. Pengguna juga harus memahami kombinasi nominal/persentase dan syarat penggunaan dari form panjang.

**Perbaikan:** gunakan pencarian pelanggan, produk, dan kategori berdasarkan nama; tampilkan item terpilih sebagai chip; pisahkan aturan dasar dan lanjutan; tampilkan simulasi potongan serta ringkasan masa berlaku dan cakupan sebelum menyimpan.

### P2 — Nama halaman dan fungsi aktual tidak selalu cocok

- **Import Produk dari Excel:** layar yang ditinjau tidak memiliki pemilih file Excel; instruksi mengandalkan file JSON yang sudah ada pada deployment dan batch size. Namanya menjanjikan alur yang belum tersedia di layar.
- **Stok & Gudang:** fungsi yang terlihat adalah pemantauan stok dan tautan kelola produk, belum menjadi alur gudang.
- **Pengaturan:** sebagian besar berupa informasi `.env` dan pemberitahuan bahwa pengaturan melalui UI akan hadir.
- **Flash Sale:** subtitle menyebut 11 produk pernah ikut, tetapi tab Semua menunjukkan Belum ada Flash Sale. Perbedaan sejarah dan daftar saat ini perlu dijelaskan.
- **Brand:** angka Perlu Review perlu menyebut unit produk agar tidak disangka jumlah brand.

**Perbaikan:** sesuaikan judul dengan kemampuan sekarang. Gunakan Pantau Stok dan Informasi Sistem bila itulah ruang lingkupnya. Bedakan status kosong aktif, riwayat, dan hasil filter.

### P2 — Tugas rutin bersaing dengan alat teknis

**Bukti visual:** dashboard menonjolkan Abuse Flags dan Audit Log; feed menampilkan Sync Bunny; impor memuat alat reset; sidebar panjang mencampurkan Customers, Reviews, Override Tgl Lahir, serta istilah Indonesia.

**Perbaikan:** gunakan bahasa Indonesia yang konsisten; kelompokkan katalog (produk, kategori, brand), pesanan, promosi, konten, pelanggan, dan sistem. Tempatkan alat pemeliharaan pada area sistem dengan hak akses yang sesuai. Dashboard sebaiknya mengutamakan pesanan yang perlu diproses dan stok yang perlu perhatian.

### P2 — Umpan balik dan aksesibilitas perlu diseragamkan

**Bukti kode:** beberapa alur menggunakan `confirm`, `prompt`, atau `alert` bawaan browser, sementara yang lain memakai dialog bersama. `FormField` mendukung `htmlFor`, tetapi sejumlah penggunaan pada form produk belum menghubungkan label dan input. Dialog bersama dan drawer mobile belum memperlihatkan penanganan fokus lengkap; toast belum memiliki pengumuman live region.

**Perbaikan:** gunakan satu pola dialog konfirmasi; fokus awal, jebakan fokus, pengembalian fokus, dan status pending; label input terhubung; error tepat di kolom terkait; toast mengumumkan status. Temuan ini berasal dari kode, belum merupakan audit aksesibilitas lengkap dengan pembaca layar.

## Penilaian per area

| Area | Yang sudah baik | Perbaikan utama |
|---|---|---|
| Dashboard | Kartu ringkasan dan identitas visual jelas | Dahulukan antrean kerja; kurangi dominasi alat teknis dan panjang ringkasan di ponsel |
| Pesanan | Filter lengkap, status berbentuk badge, kartu mobile terbaca | Ringkas filter; tampilkan tindakan berikutnya sesuai status; letakkan aksi operasional lebih dekat ringkasan detail |
| Validasi pickup | Tugas tunggal relatif fokus | Petunjuk input dan umpan balik perlu diuji dengan skenario pickup terpisah |
| Produk | Media, varian, harga, stok, pengiriman tersedia | Perbaiki bilah simpan mobile, kepadatan daftar, label dan error form |
| Kategori | Daftar sederhana | Jaga konsistensi tombol edit/hapus dan bahasa |
| Brand | Logo, status, urutan, dan review tersedia | Jelaskan unit review; masukkan ke kelompok katalog |
| Stok | Menunjukkan stok kritis dan habis | Jelaskan bahwa ini pemantauan; tambah pencarian jika diperlukan staf |
| Promo toko | Pintu masuk berbagai tipe promosi tersedia | Kurangi duplikasi kartu buat/daftar; pisahkan fitur belum tersedia |
| Flash sale | Waktu dan status membantu operasional | Selaraskan ringkasan riwayat dan empty state |
| Voucher | Aturan cukup lengkap | Ganti ID internal dengan pemilih bernama; tampilkan ringkasan/simulasi |
| Banner | Petunjuk rasio, ukuran dan pratinjau berguna | Standarkan konfirmasi dan feedback perubahan |
| Popup promo | Pratinjau dan panduan ukuran gambar tersedia | Pertahankan kejelasan status aktif dan prioritas simpan |
| Broadcast | Draft, uji ke diri sendiri, dan konfirmasi penerima berguna | Ringkas instruksi awal; konsistenkan bahasa; pisahkan pengujian dan pengiriman massal |
| Feed | Daftar cukup padat; form baru punya pratinjau langsung | Pindahkan Sync Bunny ke pemeliharaan; seragamkan dialog; jelaskan status notifikasi |
| Moderasi | Struktur filter dan ringkasan tersedia | Status loading/kosong perlu dibedakan; tampilan data laporan terisi belum dinilai menyeluruh |
| Pelanggan | Pencarian tersedia dan informasi dasar mudah dipindai | Tautkan profil, riwayat pesanan dan tindakan layanan pelanggan |
| Ulasan | Daftar khusus memudahkan pengawasan | Konsistenkan istilah dan pola tindakan dengan moderasi |
| Override tanggal lahir | Ada konteks kehati-hatian | Jadikan tindakan di profil pelanggan; kurangi judul/instruksi berulang |
| Laporan | Ringkasan pendapatan mudah ditemukan | Prioritaskan ketepatan definisi metrik dan pemilihan periode |
| Pengaturan | Informasi integrasi dapat ditemukan | Bedakan informasi teknis dengan konfigurasi toko yang bisa diedit |
| Audit log / abuse | Berguna untuk pemeriksaan internal | Istilah ramah staf, timestamp pemeriksaan, hindari klaim aman hanya karena daftar kosong |
| Danger zone / import | Konfirmasi berlapis untuk reset merupakan hal positif | Pisahkan dari pekerjaan sehari-hari; nama import sesuai kemampuan sebenarnya |

## Cakupan pemeriksaan

Halaman utama ditinjau secara visual: dashboard, produk, pesanan, stok, kategori, brand, promo, voucher, banner, popup, broadcast, feed, moderasi, pelanggan, ulasan, laporan, pengaturan, pickup, abuse flags, audit log, override tanggal lahir, impor, dan danger zone.

Form/detail representatif: tambah produk, detail pesanan demo, voucher baru dan edit, promo toko baru, flash sale baru, dan feed baru. Daftar promo toko, flash sale, serta voucher juga diperiksa. Tampilan mobile berfokus pada dashboard, daftar produk, tambah produk, dan daftar pesanan.

Tidak semua variasi edit, setiap status data, setiap dialog, maupun semua ukuran layar diperiksa. Halaman moderasi sempat menampilkan loading; penilaian detail data terisi terbatas. Pemeriksaan ini tidak membuktikan keberhasilan unggah file, penyimpanan, sinkronisasi marketplace, atau transaksi produksi.

## Urutan perbaikan yang disarankan

1. Perbaiki tombol simpan mobile dan ketepatan/label laporan.
2. Ringkas daftar produk dan buat tindakan pesanan berdasarkan status lebih mudah ditemukan.
3. Perbaiki voucher dengan pemilih bernama, ringkasan, dan simulasi.
4. Rapikan navigasi, istilah, empty state, serta pisahkan pemeliharaan sistem.
5. Seragamkan form, dialog, toast, dan aksesibilitas komponen bersama.

## Batas dengan ERP

Perubahan presentasi, navigasi, kepadatan daftar, label, dan posisi tombol dapat dikerjakan terpisah dari pengembangan ERP. Tetapkan dahulu sumber data utama untuk stok, harga, dan produk sebelum menambah fitur mutasi gudang atau sinkronisasi. Admin website dapat berfokus pada konten katalog, foto, promosi, dan operasi pesanan website. Rancangan ini adalah rekomendasi pembagian tanggung jawab; koneksi ERP yang berjalan belum diverifikasi dalam audit UI ini.
