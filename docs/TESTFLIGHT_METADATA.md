# TestFlight Metadata — Natalo Petshop

Draft semua field yang dibutuhkan untuk setup TestFlight Internal & External Testing
di App Store Connect. Tinggal copy-paste sesuai section.

URL halaman: [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → My Apps → **Natalo Petshop** → tab **TestFlight**.

---

## 1. Test Information

Sidebar kiri → **Test Information** (di bawah "Additional"). Ini wajib diisi sebelum
external beta review.

### Beta App Description (Indonesian — primary)

> Natalo Petshop & Aquarium adalah aplikasi e-commerce hewan peliharaan untuk pelanggan di Medan dan sekitarnya. App ini memungkinkan customer browse produk pakan kucing, anjing, ikan, kelinci, hamster, aksesoris, obat & vitamin hewan, serta kebutuhan aquarium lengkap.
>
> Fitur utama yang sudah berjalan:
> • Katalog produk dengan kategorisasi (kucing, anjing, ikan, dll)
> • Pencarian produk dengan auto-complete
> • Keranjang belanja & checkout dengan multiple alamat pengiriman
> • Pembayaran via Midtrans (kartu kredit, e-wallet, virtual account, QRIS)
> • Tracking status pesanan real-time
> • Riwayat pesanan & re-order satu klik
> • Loyalty points & voucher member
> • Wishlist & review produk
>
> Build ini untuk closed beta — internal testers (team Natalo) dan external testers (customer dekat) untuk validasi UX sebelum public release di App Store. Mohon report bug atau saran via email feedback yang tertera.
>
> Toko fisik Natalo: Jl. (alamat toko) Medan, Sumatera Utara. Operasional Senin-Sabtu.

### Feedback Email

```
hello@natalopetshop.com
```

(Atau email lain yang aktif kamu monitor — wajib email valid karena tester report
bug ke sini.)

### Marketing URL (optional)

```
https://natalo-petshop.vercel.app
```

### Privacy Policy URL (wajib)

```
https://natalo-petshop.vercel.app/kebijakan-privasi
```

### License Agreement

Pilih **"Use Apple's Standard License Agreement"** (default, gak perlu upload kontrak custom kecuali kamu mau license khusus).

---

## 2. What to Test (Test Notes — internal & external testers)

Field ini muncul saat kamu submit build ke tester group. Beritahu tester apa yang
perlu mereka test untuk fokus feedback yang relevan.

### Untuk Build 1.0 (initial release)

> ✨ Natalo Petshop versi 1.0 — first beta release.
>
> Mohon test flow utama berikut & report kalau ada masalah:
>
> 1. **Browsing & Pencarian**
>    • Buka home, scroll produk featured & terlaris
>    • Klik kategori (Kucing, Anjing, Ikan, dll) — cek produk muncul sesuai
>    • Pakai search bar — coba ketik "royal canin", "whiskas", brand yang ada
>    • Pull-to-refresh — tarik halaman ke bawah untuk refresh data
>
> 2. **Detail Produk**
>    • Klik salah satu produk
>    • Geser image carousel (kalau ada multiple foto)
>    • Pilih varian (size/flavor) kalau ada
>    • Check tombol "Tambah ke Keranjang" + "Beli Langsung"
>    • Test tombol Share — bagikan link produk via WhatsApp/Email
>
> 3. **Checkout (jangan submit pembayaran sungguhan)**
>    • Tambah produk ke keranjang
>    • Buka keranjang → checkout
>    • Isi alamat pengiriman atau pilih dari saved address
>    • Pilih kurir & metode pembayaran
>    • Stop sebelum confirm payment (kecuali kamu mau test full flow)
>
> 4. **Akun Member (kalau punya akun)**
>    • Login via email/password atau register baru
>    • Buka Profil → cek info, edit jika perlu
>    • Riwayat Pesanan
>    • Wishlist — add/remove produk
>    • Loyalty Points — cek balance & history
>
> 5. **UX Native iOS**
>    • Splash screen saat first launch — animasi "N → atalo PETSHOP"
>    • Swipe-from-left-edge untuk back ke halaman sebelumnya
>    • Pull-to-refresh dari halaman manapun
>    • Tombol Share native iOS (UIActivityView dengan WhatsApp, IG, Mail, dll)
>    • Status bar style adaptif per halaman
>
> 6. **Yang masih in-progress (belum perlu di-test)**
>    • Push notification (akan ditambah versi berikutnya)
>    • In-app chat customer service
>    • Live chat real-time
>
> Report bug via email feedback. Sertakan screenshot kalau ada UI yang aneh.
>
> Terima kasih sudah membantu test! 🐾

---

## 3. Beta App Review Information (untuk External Testing)

Saat submit build pertama untuk **External Beta Review**, Apple butuh info berikut.
Ini berbeda dari "Test Information" — yang ini KHUSUS untuk Apple reviewer.

### Sign-in Required

✅ **Yes** — Natalo butuh login customer untuk akses checkout, riwayat order, loyalty points.

### Demo Account

Apple reviewer butuh akun demo untuk login & test app. Buat satu akun di production
database, lalu kasih kredensial-nya:

| Field | Value |
|---|---|
| Username | `apple-reviewer@natalopetshop.com` |
| Password | (password kuat 16+ karakter, simpan di password manager) |

⚠️ **Cara bikin akun demo:**

1. Buat email khusus reviewer di Gmail (atau forwarding ke email kamu).
2. Register di Natalo via halaman register sebagai customer biasa.
3. Top up loyalty points (manual via admin) jadi mis. 50 points biar reviewer bisa
   test fitur loyalty.
4. Tambahkan 1-2 contact / alamat pengiriman supaya checkout bisa di-test.

### Contact Information

Kamu (Account Holder) sebagai contact untuk reviewer:

| Field | Value |
|---|---|
| First Name | `Leonardi` |
| Last Name | `Agustinus` |
| Phone | `+62 (nomor whatsapp aktif kamu)` |
| Email | `hello@natalopetshop.com` |

### Notes for Reviewer

> Halo Apple reviewer team,
>
> Natalo Petshop adalah aplikasi e-commerce hewan peliharaan dengan target market
> Indonesia (terutama Medan, Sumatera Utara). App ini berbasis Capacitor dengan
> WebView ke domain produksi natalo-petshop.vercel.app.
>
> Cara test:
> 1. Login pakai akun demo: apple-reviewer@natalopetshop.com / [password]
> 2. Browse produk, masukkan ke keranjang
> 3. Untuk test full checkout, gunakan kartu test Midtrans:
>    • Card number: 4811 1111 1111 1114
>    • CVV: 123
>    • Expiry: 01/30
>    (Ini sandbox card — tidak akan charge real money)
> 4. Untuk test riwayat pesanan, akun demo sudah punya 1-2 order historis
>
> App belum implement push notification iOS — feature itu di-roadmap untuk versi
> berikutnya. Saat ini notifikasi order via email + WhatsApp.
>
> App tidak collect/transmit sensitive personal data lebih dari yang dijelaskan
> di Privacy Policy. Encryption hanya HTTPS standar via OS (ITSAppUsesNonExemptEncryption
> = false, sudah di-set di Info.plist).
>
> Terima kasih, mohon bantuan review-nya.
>
> Leonardi Agustinus
> Founder Natalo Petshop & Aquarium

---

## 4. Action items kamu sekarang

Cek satu per satu:

### A. Buat akun demo (5-10 menit)

1. Bikin email khusus: `apple-reviewer@natalopetshop.com` di Gmail / domain kamu
   (atau pakai alias dari email utama)
2. Register di [natalo-petshop.vercel.app/member/register](https://natalo-petshop.vercel.app/member/register) sebagai customer
3. Login → buat 1-2 alamat di Profil → maybe top up loyalty points via admin
4. Catat password di password manager → akan jadi value untuk **Demo Account → Password**

### B. Isi Test Information (5 menit)

1. Buka [appstoreconnect.apple.com → Natalo Petshop → TestFlight → Test Information](https://appstoreconnect.apple.com)
2. Copy-paste **Beta App Description** di atas
3. Isi **Feedback Email**
4. Marketing URL & Privacy Policy URL
5. License Agreement: Standard
6. **Save**

### C. Setup External Group (5 menit)

1. TestFlight sidebar → **External Testing** → **+** create group
2. Group Name: `Beta Testers`
3. ✅ Enable automatic distribution
4. Add tester email(s) atau prep public link
5. Add Build (paling baru, mis. Build 11) ke group
6. Klik **Submit for Beta Review**

### D. Isi Beta App Review Information (saat submit)

Saat klik "Submit for Beta Review", form muncul. Isi sesuai section 3 di atas.
Encryption: pilih **"None of the algorithms mentioned above"** (karena
ITSAppUsesNonExemptEncryption sudah di-set false).

### E. Submit & tunggu

Apple review external beta biasanya 1-2 hari. Status di TestFlight:
- 🟡 **Waiting for Review** → 🟡 **In Review** → ✅ **Approved**

Setelah approved, tester di-email invite, atau pakai public link untuk distribusi.

---

## Catatan tambahan

### Update Test Notes per build

Setiap kamu submit build baru (mis. v1.0.X), kamu bisa update **What to Test**
spesifik untuk fitur baru di build itu. Pattern:

> Build 12 — focus test fitur baru:
> • Push notification (test menerima notif order baru)
> • Camera native untuk upload foto review
>
> Plus regression test fitur sebelumnya (pull-to-refresh, share, dll).

### Build berikutnya dari beta yang sama

Setelah first build di-approve external beta, build SUBSEQUENT (mis. v1.0.12, 13, dll)
biasanya gak perlu review ulang **kecuali ada major change**. Tester langsung dapat
update via TestFlight app.

### Public Link

Setelah external approved, di group "Beta Testers" toggle **Public Link** ON. Apple
generate URL `https://testflight.apple.com/join/AbCdEf12`. Bagikan via WhatsApp,
Instagram bio Natalo, customer email blast.
