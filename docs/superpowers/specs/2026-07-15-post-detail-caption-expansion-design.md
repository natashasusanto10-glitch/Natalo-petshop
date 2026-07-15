# Post Detail Caption Expansion

## Tujuan

Membuat caption panjang pada halaman detail **Postingan** mengikuti perilaku Instagram: ringkas pada awalnya, dapat dibuka sekali, dan tetap terbuka selama sesi aplikasi aktif.

## Ruang lingkup

- Berlaku hanya untuk halaman detail postingan.
- Caption awal ditampilkan maksimal dua baris.
- Caption yang melewati dua baris berakhir dengan `... selengkapnya` pada baris kedua.
- Hanya teks `selengkapnya` yang menjadi target interaksi.
- Setelah ditekan, caption penuh muncul dengan animasi perubahan tinggi sekitar 280 ms; konten setelah caption terdorong turun.
- Caption yang sudah terbuka tidak menyediakan aksi tutup atau `lebih sedikit`.
- Status terbuka disimpan di memori aplikasi per ID postingan.
- Semua postingan yang caption-nya pernah dibuka tetap terbuka saat pengguna berpindah halaman, kembali ke detail postingan, atau aplikasi berada di background.
- Status kembali ringkas setelah cold start aplikasi.

## Di luar ruang lingkup

- Caption pada feed utama, feed video, komentar, dan halaman lain tidak berubah.
- Tidak ada perubahan API, model backend, maupun penyimpanan database/persisten.
- Tidak ada tombol atau interaksi untuk menutup kembali caption dalam satu sesi.

## Arsitektur

Tambahkan store sesi ringan yang menyimpan `Set<String>` berisi ID postingan dengan caption yang sudah dibuka. Store hanya hidup selama proses aplikasi berjalan dan tidak ditulis ke disk.

Widget caption di `member_post_detail_screen.dart` membaca status dari store menggunakan ID postingan. Bila caption masih ringkas, widget mengukur teks berdasarkan lebar aktual agar suffix `... selengkapnya` pasti muat dalam dua baris. Menekan suffix menandai ID postingan sebagai terbuka di store dan menjalankan animasi ekspansi.

## Perilaku dan edge case

- Caption kosong atau yang muat dalam dua baris tampil penuh tanpa `selengkapnya` dan tanpa interaksi.
- Perhitungan ringkas mengikuti ukuran font serta lebar layar aktual agar tidak memotong suffix pada perangkat berbeda atau saat text scaling aktif.
- Bila data postingan diperbarui tetapi ID-nya sama, status terbuka sesi tetap berlaku.
- Store tidak memicu network request dan tidak memengaruhi data caption asli.

## Validasi

1. Caption panjang tampil dua baris dengan suffix yang terlihat.
2. Satu kali tap `selengkapnya` membuka caption penuh dengan transisi halus.
3. Caption tidak dapat ditutup kembali.
4. Kembali ke postingan yang sama atau berpindah ke postingan lain lalu kembali mempertahankan status terbuka.
5. Setelah cold start, caption kembali ringkas.
6. Caption pendek, ukuran teks besar, dan caption dengan emoji tetap dapat dirender tanpa overflow.
