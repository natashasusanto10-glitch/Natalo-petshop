# Play Store Listing — Copy-Paste Ready

Bahasa Indonesia. Semua sudah comply dengan limit karakter Play Store.
URL public yang dipakai → produksi `https://www.natalopetshop.com`.

---

## 1. App details (Dashboard → App details)

| Field | Isi | Karakter |
|---|---|---|
| App name | `Natalo Petshop` | 14 / 30 |
| Short description | `Belanja pakan & kebutuhan hewan peliharaan — pesanan diantar ke rumah di Medan.` | 79 / 80 |
| Full description | (lihat di bawah) | ±1500 / 4000 |

### Full description (copy-paste ke Play Console)

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
Email: hello@natalopetshop.com
Web: https://www.natalopetshop.com
```

---

## 2. Store settings (Dashboard → Store settings)

| Field | Isi |
|---|---|
| App category | **Shopping** |
| Tags | Pet, Shopping, E-commerce, Pet Food, Petshop |
| Contact email | `hello@natalopetshop.com` *(ganti dengan email asli)* |
| Contact phone | `+62 821-xxxx-xxxx` *(opsional, tapi recommended)* |
| Website | `https://www.natalopetshop.com` |
| Privacy policy URL | `https://www.natalopetshop.com/kebijakan-privasi` ✓ sudah ada di production |

---

## 3. App content (Dashboard → App content) — WAJIB semua

### 3.1 Privacy policy
- URL: `https://www.natalopetshop.com/kebijakan-privasi`
- ✅ Sudah live di production

### 3.2 App access
Pilih: **"All functionality is available without special access"** 
*(kalau tidak ada login khusus admin/tester yang Google reviewer perlu)*

### 3.3 Ads
Pilih: **"No, my app does not contain ads"**

### 3.4 Content rating questionnaire
Jawaban untuk Natalo Petshop (shopping app, no violence/no gambling):

| Pertanyaan | Jawaban |
|---|---|
| Contains violence? | No |
| Contains sexual content? | No |
| Contains nudity? | No |
| Contains profanity? | No |
| Contains controlled substances (alcohol/drugs/tobacco)? | No |
| Simulates gambling? | No |
| Allows users to interact (chat/post)? | **Yes** *(ada review feature)* |
| Shares user location with other users? | No |
| Allows user-generated content? | **Yes** *(ada review/rating)* |
| Digital purchases? | **Yes** *(in-app shopping)* |

**Expected rating**: PEGI 3 / ESRB Everyone / IARC 3+

### 3.5 Target audience and content
- **Target age group**: 18+ *(karena ada payment & shopping)*
- Appeals to children? **No**

### 3.6 News app
**No** — bukan news app

### 3.7 COVID-19 contact tracing
**No** — bukan tracing app

### 3.8 Data safety form (PALING PENTING — wajib akurat)

Declare data yang dikumpulkan:

#### Data types collected:
| Category | Collected | Purpose |
|---|---|---|
| **Personal info → Name** | Yes | Account management, customer support |
| **Personal info → Email address** | Yes | Account management, customer support |
| **Personal info → Phone number** | Yes | Account management, customer support |
| **Personal info → Address** | Yes | Shipping, fulfillment |
| **Financial info → Purchase history** | Yes | Account management, analytics |
| **Financial info → Payment info** | No *(ditangani Midtrans, kita tidak simpan card data)* | — |
| **App activity → App interactions** | Yes | Analytics |
| **App activity → In-app search history** | Yes | Personalization |
| **Device or other IDs** | Yes | Analytics, push notifications |

#### Data handling:
- ✅ Data is encrypted in transit (HTTPS only)
- ✅ Users can request data deletion (link: `https://www.natalopetshop.com/akun/hapus-akun` ✓ sudah ada)
- ✅ App complies with Families policy: **Not designed for children**

### 3.9 Government apps
**No** — bukan government app

### 3.10 Financial features
- App provides financial services? **No** *(payment via Midtrans, kita bukan financial service)*

### 3.11 Health
- App offers health features? **No**

---

## 4. Store listing — Assets needed

| Asset | Resolusi | Status | Lokasi |
|---|---|---|---|
| App icon | 512 × 512 PNG | ✅ Ready | `natalo-petshop-app/resources/icon.png` |
| Feature graphic | 1024 × 500 PNG | ⚠️ Need create | TBD |
| Phone screenshots (min 2, max 8) | 1080 × 1920 PNG | ⚠️ Need capture | Via `npm run gen:appstore-screenshots` atau capture manual |
| 7" Tablet screenshots (opsional) | 1200 × 1920 PNG | ⚠️ Optional | — |
| 10" Tablet screenshots (opsional) | 1920 × 1200 PNG | ⚠️ Optional | — |
| Promotional video (opsional) | YouTube URL | ⚠️ Optional | — |

### Screenshot capture checklist (min 2 wajib, recommended 4-6)

Sarankan capture screen berikut:
1. **Beranda** (`/`) — hero + product categories
2. **Katalog produk** (`/products`) — list view dengan filter
3. **Product detail** (`/products/[slug]`) — gambar carousel + add to cart
4. **Cart + checkout** (`/cart`) — keranjang dengan items
5. **Member dashboard** (`/member`) — profile, points, history
6. **Order status** (`/order-status`) — tracking page

---

## 5. Release tracks

### Strategi rekomendasi: Internal Testing → Production

**Step A. Internal Testing (LIVE dalam ~1-2 jam, no public review)**
1. Dashboard → Testing → **Internal testing** → Create release
2. Upload AAB: `natalo-petshop-app/dist/natalo-petshop-v1.0.0.aab` (ada file 2.56 MB)
   *(Sebelum upload, naikkan versionCode ke 9 di build.gradle karena versionCode 8 sudah pernah ditandai)*
3. Add internal tester emails (max 100) → 1 jam aktif → install via link tester

**Step B. Production (review 3-7 hari)**
Setelah Internal Testing pass:
1. Dashboard → Production → Create release
2. Copy AAB dari Internal Testing → upload ke Production track
3. Submit for review → tunggu approval

---

## 6. Versioning info untuk first release

Update di `natalo-petshop-app/android/app/build.gradle` sebelum build:

```gradle
defaultConfig {
    ...
    versionCode 1        // ← FIRST release di Play Store: mulai dari 1
    versionName "1.0.0"  // ← Public version
    ...
}
```

⚠️ **Catatan**: Kemarin versionCode sudah pernah ditandai 8 (di RELEASE_1.0.5_NOTES.md context).
Itu OK kalau belum pernah upload ke Play Console — saat first upload, set fresh dari 1.
Tapi kalau ke depan setelah live, **versionCode harus selalu naik** (1 → 2 → 3 ...) — gak boleh turun atau sama.

---

## 7. Quick action plan (urutan submission)

Setelah Create app done:

1. **Set up your app** section di dashboard:
   - [ ] Privacy policy → paste URL
   - [ ] App access → All functionality available
   - [ ] Ads → No
   - [ ] Content rating → fill questionnaire
   - [ ] Target audience → 18+
   - [ ] News app → No
   - [ ] Data safety → fill form di atas
   - [ ] Government apps → No
   - [ ] Financial features → No
   - [ ] Health → No

2. **Store listing**:
   - [ ] Paste short description
   - [ ] Paste full description
   - [ ] Upload icon (sudah ada)
   - [ ] Upload feature graphic (perlu buat 1024×500)
   - [ ] Upload min 2 phone screenshots
   - [ ] Set category = Shopping

3. **Store settings**:
   - [ ] Contact email
   - [ ] Website URL
   - [ ] Tags

4. **Release**:
   - [ ] Internal testing → upload AAB
   - [ ] Add tester emails
   - [ ] Test di device → verify all works
   - [ ] Promote to Production
   - [ ] Submit for review

---

## 8. Asset yang masih perlu dibuat

**Feature graphic 1024×500** — biasanya horizontal banner dengan:
- Logo Natalo (kiri)
- Tagline "Toko Online Hewan Peliharaan Medan"
- Visual mascot pet (kucing / anjing)
- Warna brand: Natalo Blue `#1E5FBF` background

Bisa dibuat di Canva (template "App Store Banner") atau Figma. Atau saya bisa
generate via script kalau ada library tertentu yang mau dipakai.

**Phone screenshots** — bisa capture manual di Chrome DevTools mobile emulation
(iPhone Pro Max 1290 × 2796) atau via `gen:appstore-screenshots` script yang sudah ada di repo.
