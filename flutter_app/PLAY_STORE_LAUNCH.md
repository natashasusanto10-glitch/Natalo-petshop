# Play Store Launch Guide — Natalo Petshop (Flutter)

> **Jalur C: Listing baru** dengan `applicationId = com.natalo.petshop`. Listing Capacitor lama (`com.natalopetshop.app`) dibiarkan deprecated karena keystore asli hilang. Lihat [PLAY_STORE_LAUNCH.md → Bagian 0: Background](#0-background) untuk konteks lengkap.

---

## 0. Background

| Item | Value |
|------|-------|
| Strategi | **Listing BARU**, bukan replace listing Capacitor |
| applicationId | `com.natalo.petshop` |
| Version | `1.0.13` (versionCode `19`) |
| AAB file | `flutter_app/build/app/outputs/bundle/release/app-release.aab` (82 MB) |
| Keystore | `flutter_app/android/app/natalo-petshop-release.jks` ⚠️ BACKUP! |
| Keystore SHA-1 | `03:7F:2B:BA:9F:C6:F0:A3:D7:86:3B:6B:58:EB:7A:B6:F7:E6:CB:38` |

---

## Bagian 1 — Persiapan (lakukan SEBELUM masuk Play Console)

### 1.1 Backup keystore (WAJIB sebelum apa-apa)

Copy 2 file ini ke **minimal 2 lokasi terpisah** (Google Drive pribadi + USB / email diri):

```
flutter_app/android/app/natalo-petshop-release.jks
flutter_app/android/key.properties
```

Catat di password manager:
- Password keystore: `leO4564105`
- Key alias: `natalo-petshop`
- SHA-1: `03:7F:2B:BA:9F:C6:F0:A3:D7:86:3B:6B:58:EB:7A:B6:F7:E6:CB:38`

**Tanpa file ini, kamu tidak bisa update app setelah live di Play Store.**

### 1.2 Verifikasi privacy policy URL live

Buka di browser: https://www.natalopetshop.com/kebijakan-privasi

- ✅ Page LIVE → siap pakai
- ❌ Page 404 → harus upload dulu sebelum lanjut (lihat Lampiran A untuk template)

### 1.3 Pastikan email kontak publik aktif

Email `natalopetshop@gmail.com` harus bisa terima email Google (review reply, support inquiry). Test dengan kirim email dari Gmail pribadi ke email itu.

---

## Bagian 2 — Step-by-step Play Console

### Step 2.1 Create app

1. Login [play.google.com/console](https://play.google.com/console)
2. Halaman daftar app → klik **"Create app"** (kanan atas)
3. Isi form:

   | Field | Isi |
   |-------|-----|
   | App name | `Natalo Petshop` |
   | Default language | `Indonesian (Indonesia) – id-ID` |
   | App or game | `App` |
   | Free or paid | `Free` |

4. Centang 2 declaration:
   - ☑ Developer Program Policies
   - ☑ US export laws
5. Klik **Create app**

→ Kamu di-redirect ke **App dashboard**. Sidebar kiri = panel utama selama proses ini.

### Step 2.2 Upload AAB ke Internal Testing (DULUKAN ini)

Internal Testing live dalam ~1 jam, tidak ada review Google. Ini cara paling cepat untuk verifikasi build jalan.

1. Sidebar kiri → **Testing → Internal testing**
2. Tab **"Releases"** → klik **"Create new release"**
3. Section **"App bundles"** → drag file:
   ```
   C:\Users\USER\Desktop\natalopetshopflutter\flutter_app\build\app\outputs\bundle\release\app-release.aab
   ```
4. Section **"Release details"**:
   - **Release name**: biarkan auto (`19 (1.0.13)`)
   - **Release notes**: paste dari [Lampiran B.1](#lampiran-b-release-notes)
5. Klik **Next**
6. Page selanjutnya akan muncul warning kalau ada item dashboard yang belum diisi → **abaikan dulu**, klik **Save**

> **App belum bisa rollout** sampai semua dashboard item di Step 2.3 selesai. AAB tersimpan sebagai draft.

### Step 2.3 Lengkapi dashboard items

Sidebar kiri → **Policy → App content**. Isi semua sub-section berikut secara urut:

#### 2.3.1 Privacy policy
- Klik **Privacy Policy** → **Manage**
- URL: `https://www.natalopetshop.com/kebijakan-privasi`
- **Save**

#### 2.3.2 App access
- Klik **App access** → **Manage**
- Pilih: **"All functionality is available without special access"**
- **Save**

#### 2.3.3 Ads
- Klik **Ads** → **Manage**
- Pilih: **"No, my app does not contain ads"**
- **Save**

#### 2.3.4 Content rating
- Klik **Content ratings** → **Start questionnaire**
- Email: `natalopetshop@gmail.com`
- Category: **"Reference, News, or Educational"** (Shopping app jatuh di sini)
- Jawab pertanyaan sesuai [Lampiran B.2](#lampiran-b2-content-rating-answers)
- Submit → Apply rating
- Expected: **PEGI 3 / ESRB Everyone / IARC 3+**

#### 2.3.5 Target audience
- Klik **Target audience** → **Manage**
- Target age: **18 and over** (karena ada payment & shopping)
- Appeals to children: **No**
- **Save**

#### 2.3.6 News app
- Klik **News apps** → **Manage**
- Pilih: **"No, this is not a news app"**
- **Save**

#### 2.3.7 COVID-19 contact tracing
- Klik **COVID-19 contact tracing...** → **Manage**
- Pilih: **"This app is neither..."**
- **Save**

#### 2.3.8 Data safety (PALING TELITI)
- Klik **Data safety** → **Manage**
- Pilih: **"Yes, my app collects or shares user data"**
- Isi tabel sesuai [Lampiran B.3](#lampiran-b3-data-safety-matrix)
- **Save**

#### 2.3.9 Government apps
- Pilih: **"No"** (Save)

#### 2.3.10 Financial features
- Pilih: **"My app doesn't have any financial features"** (Save)

#### 2.3.11 Health
- Pilih: **"No, my app doesn't access health data"** (Save)

### Step 2.4 Store listing

Sidebar → **Grow → Store presence → Main store listing**

1. **App name**: `Natalo Petshop` (biarkan, sudah terisi)
2. **Short description**: paste dari [Lampiran B.4](#lampiran-b4-short-description)
3. **Full description**: paste dari [Lampiran B.5](#lampiran-b5-full-description)
4. **App icon**: upload `flutter_app/play_store_assets/icon-512.png`
5. **Feature graphic**: upload `flutter_app/play_store_assets/feature-graphic-1024x500.png`
6. **Phone screenshots**: upload semua 5 file dari `flutter_app/play_store_assets/screenshots-phone/`
7. **7-inch tablet** (opsional tapi recommended): upload dari `screenshots-tablet-7/`
8. **10-inch tablet** (opsional): upload dari `screenshots-tablet-10/`
9. **Save**

### Step 2.5 Store settings

Sidebar → **Grow → Store presence → Store settings**

| Field | Isi |
|-------|-----|
| App category | `Shopping` |
| Tags | `Pet`, `Shopping`, `E-commerce`, `Pet Food`, `Petshop` |
| Email | `natalopetshop@gmail.com` |
| Phone | `+62 821-xxxx-xxxx` *(ganti dengan nomor WhatsApp aktif kamu)* |
| Website | `https://www.natalopetshop.com` |
| External marketing | **Yes, my app is marketed externally** *(asumsi kamu pernah promote di sosmed)* |

**Save**.

### Step 2.6 Tambah Internal Testers

Sidebar → **Testing → Internal testing** → tab **"Testers"**

1. Klik **"Create email list"**
2. List name: `Natalo Internal Testers`
3. Add emails: ketik Gmail kamu sendiri + tim (max 100)
4. **Save changes**
5. Centang list-nya supaya aktif
6. **Save**

### Step 2.7 Rollout ke Internal Testing

1. Sidebar → **Testing → Internal testing** → tab **"Releases"**
2. Klik **"Review release"** pada draft yang tadi
3. Cek semua item ✓ green → klik **"Start rollout to Internal testing"**
4. Confirm

→ Status: **Rolled out**. Tester dapat opt-in link dalam ~15 menit, install via Play Store dalam ~1 jam.

### Step 2.8 Test di device (WAJIB sebelum production)

1. Di sidebar **Internal testing** → tab **"Testers"** → copy **"Join on Android"** link
2. Buka link itu di Android device kamu (yang Google account-nya ada di tester list)
3. Klik **"Become a tester"** → install via Play Store
4. Verifikasi semua fitur jalan:
   - [ ] Login & register
   - [ ] Browsing produk
   - [ ] Add to cart
   - [ ] Checkout (skip pembayaran asli)
   - [ ] Push notification masuk
   - [ ] Kamera (upload foto review)
   - [ ] Lokasi (auto-fill alamat)
   - [ ] Deep link wa.me ke WhatsApp

### Step 2.9 Promote ke Production (kalau testing pass)

1. Sidebar → **Production**
2. **Create new release**
3. Cara cepat: klik **"Use existing app bundle"** → pilih AAB versi 19 yang sudah di internal
4. **Release notes**: sama dengan internal (Lampiran B.1)
5. **Save → Review release → Start rollout to Production**
6. Pilih **% rollout**: mulai dari **10%** (safer, bisa monitor crash report sebelum push ke 100%)

→ Review Google: **3-7 hari** (first submission biasanya 3-5 hari).

→ Setelah approved & rollout: app **LIVE di Play Store**, dicari publik via search `Natalo Petshop`.

---

## Lampiran A — Privacy Policy Template

Kalau page `natalopetshop.com/kebijakan-privasi` belum ada / perlu update untuk fitur Flutter baru (kamera, lokasi, biometric), pakai template di [PRIVACY_POLICY.md](./PRIVACY_POLICY.md).

---

## Lampiran B — Copy-paste content

### Lampiran B.1 Release notes

**Bahasa Indonesia (kode `<id>` di Play Console, bukan `id-ID`)**:
```
Versi 1.0.13 — Rilis perdana app native Natalo Petshop.

• Performa 3x lebih cepat dibanding versi web app
• Tampilan baru dengan animasi halus & responsif
• Push notification untuk update pesanan
• Kamera & galeri terintegrasi untuk upload foto review
• Lokasi otomatis untuk pengisian alamat pengiriman
• Login dengan biometric (sidik jari / Face Unlock)
• Deep link langsung ke WhatsApp customer service
• Hemat data — gambar produk di-cache otomatis
```

### Lampiran B.2 Content rating answers

| Pertanyaan | Jawaban |
|------------|---------|
| Contains violence? | **No** |
| Contains sexual content / nudity? | **No** |
| Contains profanity? | **No** |
| References alcohol, tobacco, drugs? | **No** |
| Simulates gambling? | **No** |
| Allows users to interact with each other (chat, posts)? | **Yes** *(review produk)* |
| Shares user location with other users? | **No** |
| Allows user-generated content? | **Yes** *(review & rating)* |
| Enables digital purchases? | **Yes** *(in-app shopping)* |

Expected outcome: **IARC 3+ / PEGI 3 / ESRB Everyone**

### Lampiran B.3 Data safety matrix

#### Data collected (declare YES untuk yang berikut):

| Data type | Collected | Shared with 3rd party | Required/Optional | Purpose |
|-----------|-----------|----------------------|-------------------|---------|
| **Personal → Name** | Yes | No | Required | Account management, Customer support |
| **Personal → Email address** | Yes | No | Required | Account management, Customer support |
| **Personal → Phone number** | Yes | No | Required | Account management, Shipping |
| **Personal → Physical address** | Yes | No | Required | Shipping & delivery |
| **Financial → Purchase history** | Yes | No | Required | Account management, Analytics |
| **Photos and videos → Photos** | Yes | No | Optional | App functionality (review/feed upload) |
| **Photos and videos → Videos** | Yes | No | Optional | App functionality (feed upload) |
| **Location → Approximate location** | Yes | No | Optional | App functionality (alamat pengiriman) |
| **Location → Precise location** | Yes | No | Optional | App functionality (alamat pengiriman) |
| **App activity → App interactions** | Yes | No | Required | Analytics |
| **App activity → In-app search history** | Yes | No | Required | Personalization |
| **App info and performance → Crash logs** | Yes | No | Required | Analytics *(Firebase Crashlytics)* |
| **App info and performance → Diagnostics** | Yes | No | Required | Analytics *(Firebase Crashlytics)* |
| **Device or other IDs** | Yes | No | Required | Analytics, Push notifications *(Firebase Messaging)* |

#### Data NOT collected (declare NO):

- Payment info (ditangani Midtrans, kita tidak simpan card data)
- Health & fitness
- Messages (SMS, email content)
- Audio (mic dipakai cuma untuk record video Feed, tidak disimpan server)
- Files & docs
- Contacts
- Calendar
- Web browsing history
- Sexual orientation, race, religion, political views

#### Security practices:

- ✅ **Data is encrypted in transit** (HTTPS only — Android Network Security Config blokir cleartext)
- ✅ **You can request that data be deleted** → link: `https://www.natalopetshop.com/akun/hapus-akun`
- ✅ **Committed to Play Families Policy**: No (app not designed for children)
- ✅ **Independent security review**: No (skip)

### Lampiran B.4 Short description

**80 char max — paste di Play Console:**
```
Belanja pakan & kebutuhan hewan peliharaan — diantar ke rumah di Medan.
```
*(71 char ✓)*

### Lampiran B.5 Full description

**4000 char max — paste di Play Console:**

```
Natalo Petshop adalah aplikasi belanja online untuk semua kebutuhan
hewan peliharaan kesayangan kamu — kucing, anjing, ikan, burung,
kelinci, hingga reptil. Belanja mudah, harga bersaing, dan barang
diantar langsung ke rumah di kota Medan dan sekitarnya.

🐾 KENAPA NATALO PETSHOP?

• Ribuan produk original — pakan, vitamin, aksesoris, mainan, kandang,
  hingga peralatan aquarium dari brand terpercaya (Royal Canin, Whiskas,
  Pro Plan, Vitakraft, dan banyak lagi).
• Harga member khusus — daftar gratis, nikmati harga spesial untuk
  produk pilihan.
• Loyalty points — setiap pembelian dapat poin, tukar jadi voucher
  diskon.
• Voucher & promo rutin — diskon mingguan, gratis ongkir, dan bundling
  hemat.
• Antar cepat di Medan — pesanan diproses hari yang sama, kurir
  terpercaya dengan tracking real-time.
• Pembayaran aman — Midtrans (transfer bank, e-wallet, QRIS,
  Indomaret/Alfamart, kartu kredit).

📱 APP NATIVE ANDROID — VERSI BARU

Versi 1.0 ini adalah rewrite penuh ke teknologi native Android (Flutter):
• Performa hingga 3x lebih cepat
• Animasi halus, scroll mulus
• Push notification real-time untuk update pesanan
• Login dengan biometric (sidik jari / Face Unlock)
• Hemat kuota — gambar produk di-cache otomatis

🛒 FITUR UTAMA

• Katalog produk lengkap dengan filter kategori, harga, dan rating.
• Notifikasi update pesanan — tahu kapan dibayar, dikemas, dikirim,
  dan sampai.
• Lacak paket langsung dari app, tahu posisi paket setiap saat.
• Wishlist — simpan produk favorit untuk dibeli nanti.
• Review & rating — bantu pet parent lain pilih produk terbaik.
• Profil hewan peliharaan — simpan data kucing/anjing kamu untuk
  rekomendasi produk yang pas.

📦 LAYANAN ANTAR

Kami melayani pengiriman ke seluruh Medan dan kota-kota besar di
Sumatera Utara. Untuk area di luar jangkauan, tersedia opsi
pengiriman via kurir nasional.

🌟 KOMUNITAS PET LOVER MEDAN

Natalo Petshop bukan sekadar toko — kami komunitas pencinta hewan
peliharaan di Medan. Ikuti tips perawatan, info adopsi, dan event
komunitas di app & sosial media kami.

Download sekarang dan kasih yang terbaik untuk sahabat berbulu kamu.

Layanan Pelanggan:
WhatsApp: +62 821-xxxx-xxxx
Email: natalopetshop@gmail.com
Web: https://www.natalopetshop.com
```

*(±1900 char ✓)*

---

## Lampiran C — Troubleshooting

| Error di Play Console | Penyebab | Solusi |
|----------------------|----------|--------|
| "Your app uses unsupported permissions" | Manifest declare permission yang tidak diperlukan | Cek `flutter_app/android/app/src/main/AndroidManifest.xml`, hapus yang tidak dipakai |
| "Privacy policy URL not accessible" | Page belum live atau redirect | Akses URL di incognito browser, pastikan 200 OK |
| "Target SDK below requirement" | `targetSdk < 35` | Cek `build.gradle.kts:42` → harus `targetSdk = 35` ✓ sudah |
| "App not signed properly" | Pakai debug keystore | Cek `build.gradle.kts:55-58` → harus pakai `signingConfigs.release` ✓ sudah |
| Closed beta listing lama nampak duplicate | User confusing 2 listing berbeda | Unpublish listing Capacitor lama setelah Flutter live |

---

## Lampiran D — Setelah app LIVE

### Unpublish listing Capacitor lama
Setelah Flutter listing `com.natalo.petshop` live di Production dan stabil ~2 minggu:

1. Login Play Console → app `Natalo Petshop` (com.natalopetshop.app — listing Capacitor lama)
2. Sidebar → **Setup → Advanced settings → App availability**
3. Klik **"Unpublish app"**
4. Confirm

→ Listing Capacitor hilang dari search Play Store. Tester closed beta lama harus install ulang dari listing Flutter baru.

### Migrate testers
Email semua tester lama, kasih link install ke listing baru:
```
https://play.google.com/store/apps/details?id=com.natalo.petshop
```

---

**Status saat dokumen ini ditulis (19 Mei 2026):**
- ✅ Keystore production generated & signed
- ✅ AAB built (82 MB)
- ✅ build.gradle.kts wired
- ✅ Play Store assets staged (icon, feature graphic, screenshots)
- ⏳ Belum upload ke Play Console (manual oleh kamu, panduan di Bagian 2)
