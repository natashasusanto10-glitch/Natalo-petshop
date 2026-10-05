# Review pratinjau produk admin — 5 Oktober 2026

## Perubahan

- Detail produk menjadi mode awal. Kartu katalog tetap tersedia sebagai mode kedua.
- Pratinjau membaca data form yang belum disimpan: nama, foto/video, harga, stok, varian, deskripsi, kategori, dan brand.
- Galeri, PriceBlock, SocialProofRow, TrustInfoCard dan renderer Markdown memakai komponen halaman pelanggan. Harga menggunakan mapper dan resolver diskon katalog yang sama, termasuk diskon per varian.
- Pilihan varian memengaruhi harga, stok dan foto. Varian tidak aktif tidak dapat menjadi kombinasi terpilih.
- Panel dapat digulir secara mandiri; bilah contoh pembelian tetap berada di bawah panel. Tombol pembelian disabled dan tidak memakai event keranjang, WhatsApp, favorit atau pelacak kunjungan.
- Transisi pilihan memakai 160–180 ms dan menghormati reduced motion. Navigasi galeri memakai carousel pelanggan yang sudah ada.

## Review yang dilakukan

- ESLint dan pemeriksaan TypeScript berhasil.
- Viewer lokal berhasil dibangun tanpa menjalankan migrasi atau mengakses database produksi.
- Review browser: nama dan harga berubah langsung; harga 300.000 tampil di detail maupun kartu; galeri berpindah ke foto 2/3.
- Review varian: harga Beef diubah menjadi 990.000 pada fixture. Pemilihan Beef menampilkan harga 990.000 dan stok 50.
- Review responsif pada lebar 390 px: tidak ada overflow horizontal halaman.
- Review menemukan bagian bawah panel tertutup bilah Simpan pada desktop. Tinggi area gulir dikurangi agar panel yang sticky berada di atas bilah tersebut.
- Review sumber menemukan risiko label pilihan lama setelah opsi diganti nama. Kombinasi kini hanya dihitung dari pilihan yang masih ada.

## Batas cakupan

Pratinjau mengikuti konten dan komponen detail produk web Natalo. Ini bukan replika penuh aplikasi iOS atau seluruh halaman publik: voucher yang memerlukan akun, rekomendasi, posting pelanggan dan formulir ulasan tidak dipasang pada preview. Tampilan menggunakan data fixture lokal untuk review. Pemutaran video produk nyata belum ditinjau pada pekerjaan ini. Belum commit/push/deploy.

Penilaian manual sementara UI/UX: 8,5/10. Panel lebih berguna dibanding kartu saja; kesesuaian dengan produk nyata dan promo perlu ditinjau kembali di lingkungan aplikasi sebelum dinilai final.
