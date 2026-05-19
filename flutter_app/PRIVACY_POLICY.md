# Kebijakan Privasi Natalo Petshop

**Berlaku efektif:** 19 Mei 2026
**Versi:** 2.0 (Flutter native)

PT Natalo Petshop ("kami") menghormati privasi pengguna ("Anda"). Dokumen ini menjelaskan data apa yang kami kumpulkan melalui aplikasi Android Natalo Petshop, bagaimana kami menggunakannya, dan hak Anda atas data tersebut.

---

## 1. Data yang Kami Kumpulkan

### 1.1 Data yang Anda berikan langsung

- **Informasi akun**: nama, alamat email, nomor telepon
- **Alamat pengiriman**: alamat lengkap, kota, provinsi, kode pos
- **Foto profil**: opsional, di-upload dari galeri atau kamera
- **Foto/video review produk**: opsional, di-upload dari galeri atau kamera

### 1.2 Data yang dikumpulkan otomatis

- **Riwayat pesanan**: produk yang dibeli, jumlah, total transaksi
- **Aktivitas in-app**: produk yang dilihat, halaman yang dibuka, kata kunci pencarian
- **Lokasi (opsional)**: lokasi GPS perangkat saat Anda menekan tombol "Pakai Lokasi Saya" untuk auto-fill alamat
- **Diagnostik & crash log**: error & crash report via Firebase Crashlytics untuk debugging
- **Device ID**: untuk push notification (Firebase Cloud Messaging) & analytics

### 1.3 Data yang TIDAK kami simpan

- **Data kartu kredit / metode pembayaran**: diproses langsung oleh Midtrans, kami tidak menyimpan nomor kartu Anda
- **Konten chat**: kami tidak mengakses SMS, email, atau chat WhatsApp Anda
- **Audio**: mikrofon hanya digunakan saat Anda record video Feed, audio tidak dikirim ke server
- **Kontak HP, kalender, riwayat browsing**: tidak diakses

---

## 2. Bagaimana Data Digunakan

| Tujuan | Data yang dipakai |
|--------|-------------------|
| Mengelola akun & autentikasi | Nama, email, telepon |
| Mengirim pesanan | Alamat, telepon |
| Memberikan customer support | Nama, email, telepon, riwayat pesanan |
| Push notification update pesanan | Device ID (FCM token) |
| Personalisasi rekomendasi produk | Aktivitas in-app, riwayat pencarian |
| Mendeteksi & memperbaiki bug | Crash log, diagnostik |
| Mengukur engagement & retention | Aktivitas in-app, device ID (anonymized) |

---

## 3. Pembagian Data dengan Pihak Ketiga

Kami **tidak menjual** data Anda. Kami berbagi data terbatas dengan service provider berikut, sesuai kebutuhan operasional app:

| Service | Data dibagi | Tujuan |
|---------|-------------|--------|
| **Midtrans** (PT Midtrans) | Nominal transaksi (bukan card data) | Memproses pembayaran |
| **Firebase** (Google LLC) | Crash log, device ID, event analytics | Crash reporting & push notification |
| **Jasa kurir** (JNE, J&T, SiCepat, dll) | Nama, telepon, alamat | Pengiriman pesanan |

Setiap pihak terikat kontrak yang membatasi penggunaan data hanya untuk service yang kami tunjuk.

---

## 4. Permission Aplikasi

Aplikasi meminta permission berikut. Anda boleh menolak — fitur terkait akan dinonaktifkan tetapi app tetap bisa dipakai.

| Permission | Untuk apa | Wajib? |
|------------|-----------|--------|
| Internet & Network State | Komunikasi dengan server Natalo | ✅ Wajib |
| Camera | Foto review produk, video Feed | ❌ Opsional |
| Microphone | Audio saat record video Feed | ❌ Opsional |
| Photos/Media | Pilih foto dari galeri untuk upload review | ❌ Opsional |
| Coarse/Fine Location | Auto-fill alamat pengiriman dengan GPS | ❌ Opsional |
| Post Notifications | Update status pesanan, promo | ❌ Opsional (recommended) |
| Biometric/Fingerprint | Login cepat dengan sidik jari | ❌ Opsional |
| Vibrate | Haptic feedback saat tap tombol | ❌ Opsional |

---

## 5. Keamanan Data

- Semua komunikasi app ↔ server pakai **HTTPS encryption** (Android Network Security Config memblokir cleartext)
- Password user di-hash dengan algoritma bcrypt sebelum disimpan
- Database server kami protected dengan firewall + access control
- Audit security berkala oleh tim internal

---

## 6. Penyimpanan Data

Data Anda disimpan di server cloud (Google Cloud / AWS) di region Asia Tenggara (Singapura/Jakarta) selama:

- **Akun aktif**: selama akun masih ada
- **Pesanan**: 5 tahun (untuk keperluan pajak & garansi)
- **Crash log & diagnostik**: 90 hari, lalu di-anonymize
- **Setelah akun dihapus**: data PII (Personally Identifiable Information) dihapus dalam 30 hari, kecuali yang wajib disimpan untuk kepatuhan hukum

---

## 7. Hak Anda

Sesuai UU Perlindungan Data Pribadi Indonesia (UU PDP No. 27/2022), Anda berhak:

1. **Mengakses** data pribadi yang kami simpan tentang Anda
2. **Mengoreksi** data yang tidak akurat
3. **Menghapus** akun & data terkait — link mandiri: https://www.natalopetshop.com/akun/hapus-akun
4. **Menarik persetujuan** kapan saja (cukup uninstall app & request data deletion)
5. **Portabilitas**: minta export data Anda dalam format yang machine-readable
6. **Mengadu** ke Komisi Perlindungan Data Pribadi jika ada pelanggaran

Untuk exercise hak ini, email **natalopetshop@gmail.com** dengan subject `[PDP Request] <tipe permintaan>`. Kami akan respons dalam 14 hari kerja.

---

## 8. Anak di Bawah Umur

App ini ditujukan untuk pengguna **18 tahun ke atas**. Kami tidak secara sengaja mengumpulkan data dari anak di bawah 18 tahun. Jika kamu adalah orang tua yang menemukan anak kamu memberikan data ke kami, hubungi natalopetshop@gmail.com untuk hapus segera.

---

## 9. Perubahan Kebijakan

Kebijakan ini bisa diperbarui sewaktu-waktu. Perubahan signifikan akan diberitahu via:
- In-app banner saat user buka app
- Email ke alamat terdaftar
- Update tanggal "Berlaku efektif" di atas

Versi sebelumnya disimpan di https://www.natalopetshop.com/kebijakan-privasi/arsip

---

## 10. Kontak

**PT Natalo Petshop**
Jl. [Alamat kantor Natalo], Medan, Sumatera Utara
Email: natalopetshop@gmail.com
WhatsApp: +62 821-xxxx-xxxx
Privacy Officer: natalopetshop@gmail.com

---

> **Untuk admin Natalo:** Host file ini di `natalopetshop.com/kebijakan-privasi` sebagai HTML page (bukan PDF). Pastikan accessible tanpa login, mobile-friendly, dan tidak ada redirect. Play Console akan crawl URL ini saat review — kalau 404 atau auth-gated, app ditolak.
