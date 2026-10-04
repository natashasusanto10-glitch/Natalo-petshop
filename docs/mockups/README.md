# Mockup admin Natalo

Buka `admin-premium.html` di browser. File ini mandiri, menggunakan data contoh, dan tidak memerlukan koneksi database atau layanan eksternal.

Pratinjau mencakup ringkasan, pesanan dan detail pesanan, katalog, tambah/edit produk, promosi, konten, pelanggan, laporan, dan susunan pengaturan. Halaman promosi/konten/pengaturan menunjukkan arah tata letak; tombol detailnya menjelaskan contoh tindakan.

Interaksi yang tersedia:

- Navigasi antarhalaman melalui menu.
- Pencarian dan filter produk contoh.
- Pilihan produk untuk gambaran tindakan massal.
- Edit harga dan stok dari daftar melalui nilai/ikon pensil dan dialog konfirmasi.
- Varian ditampilkan di bawah produk; editor harga/stok per varian mendukung Terapkan ke semua, Batal, dan Simpan. Terapkan hanya mengubah draft.
- Tambah/edit produk, pratinjau nama dan harga, serta simpan ke memori halaman.
- Editor variasi pada tambah/edit: nama kelompok, pilihan, variasi kedua, kombinasi otomatis, harga/stok/SKU/berat per kombinasi, dan isian massal. Harga produk tunggal disembunyikan dan dinonaktifkan saat variasi digunakan.
- Pencarian/filter pesanan, membuka detail contoh, dan pencarian pelanggan.
- Menu ponsel dan bilah simpan di atas navigasi bawah.

## Versi motion — 4 Oktober 2026

`admin-premium.html` kini menggunakan transisi halaman 180 ms, dialog masuk 200 ms/keluar 140 ms, menu mobile 220 ms, respons hover/tekan, indikator tab, fade varian, serta toast yang singkat. Form dan edit cepat menampilkan “Menyimpan…” dengan jeda demonstrasi 450 ms, kemudian feedback berhasil. Membatalkan edit cepat saat pending membatalkan perubahan contoh tersebut.

Tombol **Animasi aktif/nonaktif** di header memungkinkan perbandingan. Preferensi `prefers-reduced-motion` pada perangkat selalu diutamakan. Animasi menggunakan CSS dan Web Animations API tanpa library eksternal.

`admin-premium-before-motion.html` menyimpan versi sebelum penambahan motion untuk membandingkan desain asli. Kedua versi menggunakan data contoh yang terpisah di memori halaman. Laporan penilaian setelah perubahan tersedia di `admin-premium-motion-followup-2026-10-04.md`.

Perubahan contoh hilang setelah halaman dimuat ulang. Foto kemasan adalah ilustrasi sederhana untuk menunjukkan penempatan media. Angka ringkasan merupakan contoh tampilan, bukan laporan keuangan sebenarnya.

Fitur yang ada pada admin tetap menjadi persyaratan rancangan: impor, edit cepat harga/stok, pengelolaan varian, foto/video, tambah brand, bantuan deskripsi AI, serta kategori perawatan dan aturan dosis. Tombol unggah video, tambah brand, impor, pengaturan foto, dan ekstraksi dosis masih berupa representasi dalam mockup. Bantuan deskripsi menggunakan teks contoh, tanpa memanggil layanan AI. Implementasi produksi harus mempertahankan koneksi dan perilaku fitur aslinya.

Rancangan visual: sidebar putih, aksen biru Natalo, latar abu-abu lembut, batas kartu tipis, tabel ringkas, dan satu tindakan utama per area. Komponen dirancang untuk menjadi acuan penyelarasan seluruh halaman admin.

## Form mengikuti pola Shopee — 4 Oktober 2026

Susunan: Informasi produk (foto, nama, Kategori, Brand), Deskripsi, Informasi penjualan, dan Pengiriman. Sesuai permintaan pengguna, tidak ada bagian atau atribut Spesifikasi tambahan.

- Satu atau dua kelompok variasi dengan maksimal 20 pilihan per kelompok pada mockup.
- Tabel kombinasi dibuat otomatis; pilihan yang berulang ditandai dan tidak dapat disimpan.
- Harga, stok, dan berat dapat diterapkan massal. Kolom kosong melewati nilai lama; SKU diisi per kombinasi.
- Nilai kombinasi dipertahankan berdasarkan identitas pilihan ketika namanya diedit atau pilihan lain ditambahkan. Kombinasi baru memakai harga kosong, stok 0, dan berat awal 500 gram yang perlu diperiksa.
- Enter pada pilihan menambah pilihan berikutnya; Enter pada isian massal menerapkan nilai, tanpa menyimpan seluruh produk.
- Foto per varian ditampilkan sebagai tombol representasi, seperti tombol unggah lainnya pada mockup.
- Tabel menjadi kartu kombinasi pada ponsel. Gerakan mengikuti pengaturan motion/reduced motion yang sudah ada.
- Edit cepat harga/stok di daftar produk tetap tersedia.

Referensi utama: form Shopee Seller Centre yang telah dibuka dan diloginkan pengguna, serta screenshot `Screenshot 2026-10-04 163855.png`. Halaman produk Shopee hanya dibaca; perubahan dilakukan pada mockup lokal. Referensi pelengkap: [Panduan Daftar Produk Shopee Mall](https://cdngarenanow-a.akamaihd.net/shopee/seller/seller_cms/f9fe5116c72b4bc8a54651cfdc4deeed/Panduan%20Daftar%20Produk%20Shopee%20Mall.pdf).

`admin-premium-before-shopee-form.html` menyimpan rancangan sebelum perubahan form. Seluruh penyimpanan menggunakan memori halaman dan hilang ketika dimuat ulang. ERP, backend, dan database tidak terhubung pada mockup.

## Foto dapat digeser langsung — 4 Oktober 2026

Tombol **Atur urutan foto** dihapus. Galeri menampilkan tiga ilustrasi contoh agar interaksi pengurutan dapat dicoba langsung pada tambah/edit produk.

- Tarik thumbnail; thumbnail mengambang mengikuti pointer melalui requestAnimationFrame.
- Foto lain berpindah menggunakan FLIP selama 200 ms, sehingga pergantian tempat tidak langsung meloncat.
- Saat dilepas, thumbnail meluncur ke slot akhirnya selama 200 ms. Foto pertama dan pratinjau otomatis menjadi sampul.
- Escape, pointercancel, atau pelepasan di luar galeri mengembalikan urutan sebelum drag.
- Keyboard: fokus thumbnail lalu panah kiri/kanan; Home/End ke awal/akhir. Status perubahan diumumkan melalui aria-live.
- Pengaturan animasi dan reduced motion tetap dihormati. Urutan disimpan hanya pada data contoh di memori halaman.

Unggah berkas tetap berupa representasi pada mockup. Produksi perlu menerapkan interaksi ini pada galeri dan penyimpanan media yang sudah ada.

## Navigasi edit pada tab baru — 4 Oktober 2026

- Nama produk dan tindakan **Edit produk** pada daftar sama-sama membuka form edit admin untuk produk itu di tab baru (`target=_blank`, `rel=noopener`).
- Tab daftar tidak berpindah; pencarian, filter, dan posisi halaman tetap berada pada tab asal.
- Snapshot produk contoh dikirim melalui transfer penyimpanan lokal yang kedaluwarsa dalam lima menit, kemudian dihapus setelah diterima. Ini memungkinkan produk contoh yang baru ditambahkan dan nilai katalog yang baru diubah tetap muncul pada tab edit yang benar. Penyimpanan mockup tetap berlangsung di memori masing-masing tab; ini bukan sinkronisasi backend.
- Jika penyimpanan browser tidak tersedia, transfer menggunakan fragment URL lokal; tidak dikirim ke server.
- Penanda **Kombinasi 1/2** pada baris variasi dihapus; nama variasinya tetap terlihat.

## Thumbnail video ringkas — 4 Oktober 2026

Tambah/edit produk memakai tile video 76 × 76 piksel, mengikuti referensi Shopee. Klik Tambah video menjalankan simulasi progres kompresi lalu menampilkan thumbnail kecil, ikon putar, durasi, serta Ganti/Hapus. Status diumumkan melalui aria-live. Timer dibersihkan saat pindah halaman; transisi mengikuti pengaturan reduced motion. Status video contoh ikut tersimpan pada data mockup.

Mockup tidak membaca, mengunggah, atau mengompresi berkas sungguhan. Kompresi video tetap menjadi persyaratan implementasi produksi; thumbnail ringkas tidak boleh menghilangkan proses tersebut. Alur produksi yang diperiksa memakai trim opsional dan unggah Bunny TUS lalu status processing; kompresi berkas belum diverifikasi pada perubahan mockup ini.

## Teks ringkas dan status Arsip — 4 Oktober 2026

Petunjuk drag/keyboard, tutorial variasi, keterangan implementasi, serta checklist statis di form dihapus dari tampilan. Operasi keyboard dan pengumuman pembaca layar tetap tersedia. Batas berkas, label kolom, status perubahan, dan validasi tetap ditampilkan; penanda mockup tunggal dipertahankan.

Label Draf pada contoh katalog diselaraskan menjadi Arsip sesuai alur produk nonaktif (`isActive=false`) pada backend saat ini. Arsip bukan draf produk yang belum diterbitkan. Form baru memakai badge Belum disimpan; pilihan statusnya Aktif/Arsip. Perubahan ini hanya berlaku pada mockup, tidak mengubah backend atau ERP.

## Pratinjau mengikuti kartu halaman depan — 4 Oktober 2026

Acuan: `HomeProductCard.tsx` memakai `ProductCard.tsx` dengan showCta=false dan showRating=true. Pratinjau mockup mengikuti foto persegi object-contain, radius 18 px, nama dua baris, harga biru, tanpa baris brand, serta tindakan hover desktop. Rating/promo/member hanya muncul jika nilai terkait ada pada data produk. Harga variasi menggunakan nilai terendah, sesuai mapper `lib/products.ts`; tidak lagi menampilkan rentang harga. Nama, harga, stok, variasi, foto utama, dan visibilitas mengikuti perubahan form. Arsip diberi keterangan tidak tampil di halaman depan di luar kartu. Pratinjau juga tersedia di bawah form pada layar kecil.

Mockup masih memakai ilustrasi foto dan simulasi video. Bentuk ini merupakan acuan berdasarkan kode, bukan render React kartu produksi yang sama. Pada implementasi produksi, pratinjau admin harus memakai komponen ProductCard dan mapper harga/media bersama agar tampilan serta aturan diskon/member/varian benar-benar identik, dengan transaksi dinonaktifkan dalam mode preview. Ranking/promosi yang bergantung posisi dan konteks sesi pelanggan perlu diberikan dari konteks halaman yang dipratinjau.

## Input harga dengan pemisah ribuan — 4 Oktober 2026

Semua input harga (produk tunggal, variasi, massal, dan editor cepat) menggunakan teks dengan keyboard numerik dan titik pemisah ribuan tanpa prefiks Rp. Contoh 875000 ditampilkan sebagai 875.000. Nilai dikonversi kembali menjadi bilangan 875000 untuk penyimpanan dan perhitungan. Harga kosong tetap kosong; harga tidak valid, nol, negatif, dan nilai di luar safe integer ditolak. Format mengikuti pengetikan dengan posisi kursor berdasarkan jumlah digit; penghapusan melewati pemisah ribuan. Spinner angka stok/berat juga disembunyikan. Rupiah pada kartu pelanggan tetap mengikuti komponen storefront.

Referensi DOM lama untuk catatan tutorial yang dihapus dibersihkan dari editor cepat agar harga/stok tetap dapat diedit dari daftar produk.


## Penyelarasan akhir UI, UX dan motion — 4 Oktober 2026

Teks pendukung, kontras, fokus keyboard dan target sentuh diperbaiki. Input ponsel 16 px; tombol utama ponsel minimal 44 px. Baris varian/footer bergerak melalui FLIP 220 ms, bagian Perawatan memakai transisi singkat, toast menghindari savebar, dan scroll bagian form mengikuti reduced motion. Tab filter tidak memiliki scrollbar vertikal yang tidak perlu.

Pemeriksaan ulang meliputi 11 route pada desktop, ponsel dan landscape (33 tampilan), edit harga manual/massal, validasi, simpan contoh, form edit produk yang benar, urutan foto, thumbnail video, toggle motion dan menu ponsel. Laporan terbaru: [Penilaian versi akhir](admin-premium-final-review-2026-10-04.md). Rekaman layout dan interaksi disimpan dalam dua berkas JSON audit final. Nilai adalah penilaian rancangan; tidak ada klaim FPS perangkat fisik atau kompresi berkas nyata.
