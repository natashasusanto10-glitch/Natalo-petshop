# Kawan Setia — popup dan halaman detail native

Halaman Flutter: `/services/kawan-setia`. Tap popup membuka layar native,
bukan website. Empat layanan, tanpa Pet Hotel, nama kontak, atau nomor yang
ditampilkan. Tombol WhatsApp membuka `wa.me/6281330003880` dengan pesan awal.

## Pengaturan admin

Setelah versi aplikasi dengan halaman ini dirilis:

1. Buka admin → Popup Pembuka, unggah `kawan-setia-popup.jpg` di folder ini.
2. Isi alt: `Layanan Kawan Setia untuk anjing kesayanganmu`.
3. Pilih jenis link **URL**, isi
   `https://www.natalopetshop.com/services/kawan-setia`.
4. Pilih audiens **Semua** jika popup ditujukan untuk seluruh pengguna.
5. Aktifkan promo. Mekanisme admin yang ada menonaktifkan popup lama.

Gambar siap unggah: JPG 1080×1350, di bawah 1 MB. Kemunculan tetap melalui
LaunchPromoGate yang ada (cold start dengan syarat onboarding, koneksi,
audiens, dan tidak sedang membuka deep link lain).

Halaman web cadangan tersedia di `/services/kawan-setia`. Publikasikan
perubahan web sebelum mengaktifkan link: versi aplikasi lama menampilkan
halaman web tersebut di browser dalam aplikasi, sedangkan versi baru
membuka layar native. Keduanya menggunakan kontak dan empat layanan yang sama.
Implementasi lokal ini tidak mengubah data promo produksi atau merilis app.

Hero dibuat dengan tool imagegen bawaan dari desain yang disetujui.
Prompt: susun logo Kawan Setia dan tiga anjing (Pomeranian, Beagle, Golden
Retriever) menjadi hero landscape 16:9, krem/kuning/sage, tanpa teks layanan
atau tombol. Ekspor hero JPG untuk aset Flutter; popup JPG 4:5 untuk admin.
