# Review prioritas 10 — Pelanggan

Tanggal: 5 Oktober 2026.

## Status deployment sebelumnya

Perbaikan prioritas 1–9 sudah dicommit dan dipush ke main pada commit `ac8c0f8ab986a1e5dc72bbb845ca54c3778c56f4`. Deployment Vercel `dpl_HUvbqXy34kRihz7nZHkgrcAyho9G` berstatus READY untuk production dan memiliki alias natalopetshop.com serta www.natalopetshop.com.

## Lingkup prioritas 10

Nomor 10 diasumsikan sebagai halaman Pelanggan berdasarkan temuan audit tentang belum adanya jalur menuju detail dan riwayat pesanan. Klarifikasi opsional sudah diajukan; belum ada jawaban ketika implementasi dilanjutkan. Perubahan nomor 10 masih lokal, belum dicommit atau dideploy.

- Nama pelanggan dan tombol riwayat membuka detail admin.
- Detail berisi kontak, ringkasan jumlah pesanan, dan riwayat dengan tautan ke detail pesanan.
- Tombol kembali mempertahankan pencarian serta halaman asal daftar pelanggan.
- Riwayat menggunakan pagination 20 pesanan dan urutan deterministik.
- Tampilan mobile menggunakan kartu; desktop menggunakan tabel.
- Akun tanpa pesanan dan halaman di luar rentang memiliki keadaan kosong yang berbeda.

## Review kode

- Guard admin dijalankan sebelum query pelanggan atau pesanan.
- Pelanggan dibatasi pada role CUSTOMER; pesanan dibatasi pada userId pelanggan tersebut.
- Query memilih atribut yang diperlukan, tanpa password atau token.
- Parameter kembali dibuat dari q dan nomor halaman yang disanitasi, tanpa arbitrary return URL.
- Nominal order.total diberi label pembayaran di luar saldo, bukan total belanja pelanggan.
- Tidak ada perubahan database, mutation pelanggan, atau migrasi.
- Review memperbaiki posisi kolom Aksi dan keadaan halaman daftar di luar rentang.

## Pemeriksaan

- Targeted ESLint: lulus.
- TypeScript noEmit: lulus.
- Build viewer fixture: lulus.
- Browser fixture: daftar halaman 2 → detail → kembali ke halaman 2; pencarian Rina → detail mempertahankan pencarian; keadaan tanpa pesanan; keadaan halaman 99.
- Mobile: document scrollWidth sama dengan clientWidth (375 px), tanpa overflow horizontal seluruh halaman.

Pemeriksaan browser menggunakan data contoh pada viewer lokal. Query database dan akses detail pesanan pada produksi belum diverifikasi untuk perubahan ini. Tidak menjalankan suite tes atau menambahkan tes baru.

## Bukti tampilan

- `implementation-review/admin-priority-10-customer-desktop.png`
- `implementation-review/admin-priority-10-customer-mobile.png`
