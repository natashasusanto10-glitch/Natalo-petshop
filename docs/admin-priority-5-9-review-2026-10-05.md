# Review perbaikan admin 5–9

Tanggal: 5 Oktober 2026. Perubahan lokal; belum dipublikasikan.

## 5. Voucher

- Ganti input ID pelanggan, produk, dan kategori dengan pencarian nama dan pilihan yang dapat dihapus.
- Endpoint target hanya dapat diakses sesi ADMIN; respons tidak di-cache.
- Nominal memakai pemisah ribuan, tanpa spinner atau awalan Rp pada input. Nilai yang dikirim tetap angka mentah.
- Pilih satu bentuk diskon; contoh potongan memperhitungkan batas maksimum.
- Validasi server menolak angka pecahan/tidak valid, persentase di luar 1–100, diskon kosong, serta tanggal akhir sebelum mulai.
- Review integrasi saran AI: sinkronkan state komponen melalui event; tanggal saran mengikuti jenis input tanggal.
- Review UI fixture: 875000 tampil 875.000; diskon 20% dengan batas 15.000 menghasilkan contoh potongan 15.000; kategori dapat dipilih melalui nama lengkap.
- Review error: kegagalan resolusi nama target dipisahkan dari kegagalan pencarian agar pesan tidak hilang. Pilihan lama tetap dipertahankan.
- Batas: hasil pencarian maksimal 25; persempit kata pencarian untuk hasil lain. Penyimpanan voucher nyata belum dijalankan.

## 6. Flash Sale

- Semua dan Kedaluwarsa menggunakan seluruh data Flash Sale terakhir yang masih tersimpan; penghitung menggunakan cakupan yang sama. Ini bukan log riwayat setiap kampanye.
- Server memvalidasi produk, persentase, waktu akhir WIB, dan kelayakan produk saat disimpan.
- Seluruh perubahan produk berada dalam transaksi Serializable; kegagalan tidak menyimpan sebagian pilihan.
- Sinkronkan pencarian dan invalidasi cache sesudah simpan.
- Submit dinonaktifkan selama proses; error tampil di form.
- Review UI menemukan reset isian saat error pada form action. Diganti submit client agar tanggal, persentase, dan pilihan tetap utuh. Review ulang fixture menunjukkan ketiganya tetap tersedia setelah simulasi gagal.
- Batas: picker maksimal 2.000 produk; transaksi database produksi belum dieksekusi. Konflik transaksi meminta admin memuat ulang dan mencoba kembali.

## 7. Impor produk

- Judul dan sumber sesuai implementasi: JSON products_import_new.json, bukan unggah Excel.
- Pratinjau read-only menunjukkan jumlah produk, kategori, brand, dan contoh nama sebelum impor diaktifkan.
- Reset katalog/pesanan dipisahkan dari halaman impor; tidak ada tombol reset di alur ini.
- Arsipkan produk di luar sumber hanya jika admin mengaktifkan pilihan tersebut; default mempertahankan produk lama.
- Rincian proses memuat nama produk yang gagal. Ringkasan menampilkan jumlah arsip dan kegagalan sinkronisasi pencarian.
- Review fixture: tombol impor awalnya nonaktif; pratinjau mengaktifkannya; opsi arsip tetap tidak dipilih.
- Batas: tidak menjalankan impor nyata atau pengarsipan. Proses tetap bertahap; batch yang sudah selesai tidak dibatalkan bila batch berikutnya gagal.

## 8. Detail pesanan

- Tombol refund item tidak ditawarkan untuk DELIVERED, CANCELLED, atau REFUNDED, sesuai guard yang sudah ada di server.
- Pickup memakai nama ramah pengguna, termasuk WAITING_PAYMENT, PREPARING, READY, dan PICKED_UP.
- Label pembayaran di luar saldo memperjelas nominal transfer/gateway; nominal dan perhitungan tidak berubah.
- Review melalui kode UI dan guard server. Tidak melakukan refund atau mengubah pesanan nyata.

## 9. Stok dan konfirmasi brand

- Stok memiliki pencarian nama produk/SKU; query daftar dan jumlah memakai filter sama.
- Kata pencarian tetap terbawa saat berpindah tab, filter, dan pagination; pencarian baru kembali ke halaman pertama.
- Empty state pencarian tidak mengklaim stok aman saat hasil kosong.
- Kartu stok mobile dipadatkan; badge status tidak dipotong menjadi beberapa baris.
- Konfirmasi brand menggunakan dropdown ringkas dan pencarian. Pagination mempertahankan brand dan pencarian.
- Aksi konfirmasi semua menjelaskan cakupan seluruh brand, termasuk produk di luar pencarian. Tautan edit membuka tab baru.
- Review stok menggunakan fixture desktop dan 390×844. Review query stok, pagination, serta konfirmasi brand melalui kode; belum diperiksa dengan database produksi.

## Pemeriksaan

- ESLint terarah pada seluruh file perubahan: lolos.
- TypeScript noEmit: lolos pada pemeriksaan akhir.
- Viewer komponen lokal dibangun dengan data contoh; tidak memanggil mutasi produksi.
- Tidak menambahkan atau menjalankan test suite; tidak menjalankan perintah build yang memuat migrasi database.

## Bukti visual lokal

- admin-priority-5-voucher.png: aturan voucher dan target.
- admin-priority-6-flash-sale.png: error simpan dengan isian yang tetap utuh.
- admin-priority-7-import.png: pratinjau sumber.
- admin-priority-9-stock-mobile.png: kartu ringkas dan pencarian mobile.

Screenshot berada di docs/implementation-review dan memakai data contoh. Review visual fixture tidak membuktikan penyimpanan backend produksi.
