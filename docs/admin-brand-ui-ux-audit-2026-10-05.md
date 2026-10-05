# Penilaian halaman Brand — 5 Oktober 2026

## Cakupan

Review halaman produksi `/admin/brands`, tab Urutan di Aplikasi dan Semua Brand, dialog Tambah Brand, serta Edit Brand Angels Pet. Inspeksi kode komponen terkait. Tidak ada penyimpanan, unggah, penghapusan, atau perubahan urutan produksi. Halaman antrean review produk belum ditinjau dalam audit ini.

Saat review terlihat 74 brand, 74 aktif, 40 tanpa logo, 1.385 produk dengan brand otomatis yang perlu konfirmasi, serta 48 produk tanpa relasi brand.

## Nilai manual

| Aspek | Nilai | Dasar |
| --- | --- | --- |
| UI desktop | 7,8/10 | Hierarki judul, kartu ringkasan, tab dan badge terbaca; form edit belum mengikuti pola kartu form premium. |
| UX pengelolaan | 6,7/10 | Aksi utama jelas; tidak ada pencarian/filter pada daftar 74 brand dan beberapa label ambigu. |
| Motion dan akses interaksi | 5,5/10 | Hover sederhana tersedia; pengurutan belum memakai animasi perpindahan layout dan belum punya kendali keyboard. |
| Keseluruhan | 7/10 | Fondasi visual baik; penyelesaian alur operasional belum setara halaman produk. |

Nilai adalah pertimbangan manual, bukan hasil benchmark atau pengukuran performa animasi.

## Temuan dan prioritas

1. **Tinggi — pencarian/filter tidak tersedia.** Semua Brand menampilkan 74 baris tanpa pencarian, penyaringan aktif/nonaktif/tanpa logo, atau pengurutan berdasarkan nama/jumlah produk. Tambahkan toolbar sebelum daftar.
2. **Tinggi — fokus keyboard keluar dari dialog.** Pada produksi, Tab dari tombol Tambah Brand di dalam dialog berpindah ke tautan Perlu review di halaman belakang. Gunakan dialog admin bersama yang mengunci fokus dan mengembalikannya ke pemicu saat tutup.
3. **Tinggi — pengurutan belum setara interaksi foto produk.** Source memakai `draggable`, mengganti urutan array saat `onDragEnter`, tanpa FLIP/layout animation. Kartu tidak dapat difokuskan (`tabIndex=-1` pada DOM), tidak ada tombol/shortcut pengurutan atau sensor sentuh khusus. Tambahkan perpindahan layout halus, drag overlay, keyboard dan dukungan sentuh. Kelancaran aktual drag pada perangkat fisik belum diukur.
4. **Sedang — ringkasan mencampur unit brand dan produk.** Total, Aktif, Tanpa Logo adalah jumlah brand; Perlu Review adalah jumlah produk. Ubah menjadi “Produk perlu konfirmasi brand”, format angka menjadi 1.385, dan hindari menduplikasi angka yang sama pada kartu serta banner.
5. **Sedang — layout mobile terlalu panjang.** Pada lebar 390 px, empat ringkasan menjadi empat baris. Setiap kartu urutan brand setinggi 128 px, satu kolom untuk 18 brand. Tidak ada overflow horizontal, tetapi perlu banyak guliran. Gunakan ringkasan 2×2 dan baris pengurutan lebih ringkas.
6. **Sedang — uploader Edit Brand memakai terminologi foto produk.** Terlihat “1–1 gambar”, “Cover”, “Geser”, dan instruksi urutan walaupun logo hanya satu. Gunakan upload satu logo dengan Ganti/Hapus dan pratinjau contain, tanpa panduan foto katalog.
7. **Sedang — alur tambah tidak mencakup logo.** Brand dibuat lewat dialog nama/status; logo diunggah lewat daftar/form terpisah. Tambahkan unggah logo opsional saat tambah, dengan status yang jelas jika belum lengkap.
8. **Sedang — form edit belum konsisten.** Kontrol berdiri langsung di latar halaman, label Nama/Slug/Urutan tidak terhubung ke input, nomor urutan memakai 0 sementara daftar dimulai #1, dan tombol simpan baru terlihat setelah menggulir. Gunakan kartu Informasi Brand, unggah logo khusus, serta bilah Simpan/Batal yang konsisten. Tempatkan slug/urutan manual sebagai pengaturan lanjutan jika memang diperlukan.

## Arah perbaikan

Pertahankan tema putih, latar abu muda dan aksen biru. Default Semua Brand untuk tugas kelola data; Urutan di Aplikasi menjadi tampilan visual khusus. Utamakan pencarian, filter, arti metrik, dan form sebelum menambahkan animasi dekoratif. Gunakan motion 160–220 ms untuk hover, dialog, tab dan perpindahan layout; hormati reduced motion.

## Bukti

- `docs/implementation-review/brand-overview-audit.png`
- `docs/implementation-review/brand-edit-audit.png`
- `docs/implementation-review/brand-mobile-audit.png`

Tidak ada kode aplikasi yang diubah dalam audit ini.
