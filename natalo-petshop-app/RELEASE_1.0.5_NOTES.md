# Release 1.0.5 (versionCode 6) — Production Hardening

Audit & fix berdasarkan checklist senior Android dev. Lihat juga
[PLAY_STORE_CHECKLIST.md](PLAY_STORE_CHECKLIST.md) untuk submission flow.

## A. Code-level audit (sudah selesai di commit ini)

- [x] **Hardware back button**: `OnBackPressedCallback` di `MainActivity` —
      kalau WebView bisa goBack(), back. Kalau di root URL, AlertDialog
      "Keluar?". Tidak accidental close dari halaman lain.
- [x] **allowBackup**: `false` di Manifest. Plus `data_extraction_rules.xml`
      (Android 12+) dan `backup_rules.xml` (legacy) — semua state app-level
      di-exclude dari Google Auto Backup.
- [x] **App Links / Deep Links**: intent-filter dgn `autoVerify="true"`
      untuk paths /, /products, /products/*, /cart, /member/*. Host
      www.natalopetshop.com + natalopetshop.com.
- [x] **External navigation**: WhatsApp/mailto/tel/sms/intent/market →
      app native. Domain natalopetshop.com + midtrans.com → tetap di
      WebView (checkout flow tidak putus). Domain lain → Chrome eksternal.
- [x] **Offline error**: `WebViewClient.onReceivedError` untuk main-frame
      → load `file:///android_asset/offline.html` dgn tombol "Coba Lagi"
      + "Tutup App". Auto-retry saat `window.online` event.
- [x] **AAB config**: `bundle { language/density/abi split }` di
      build.gradle. Script `npm run build:bundle` → output di
      `android/app/build/outputs/bundle/release/app-release.aab`.
- [x] **versionCode bumped**: 5 → 6, versionName 1.0.4 → 1.0.5.

## B. Pre-build — yang HARUS diisi user

### 1. Digital Asset Links (untuk App Links autoVerify)

Tanpa file ini, link WhatsApp/Instagram tetap buka di app tapi via
"Open with..." dialog (tidak seamless).

**Cara dapat SHA-256 fingerprint:**

```bash
keytool -list -v -keystore <path-to-release.keystore> -alias <key-alias>
# Cari baris "SHA256: AA:BB:CC:...:ZZ"
```

**Paste fingerprint ke** `public/.well-known/assetlinks.json`
ganti `REPLACE_WITH_SHA256_RELEASE_KEYSTORE_FINGERPRINT_COLON_SEPARATED`.

**Deploy ke website:** file harus accessible di
`https://www.natalopetshop.com/.well-known/assetlinks.json`
dengan `Content-Type: application/json` dan status 200.

**Verifikasi:**
```bash
curl -i https://www.natalopetshop.com/.well-known/assetlinks.json

# Google's verifier:
# https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://www.natalopetshop.com&relation=delegate_permission/common.handle_all_urls
```

### 2. Keystore.properties

File `android/keystore.properties` (gitignored) wajib ada untuk
build release. Format:

```properties
storeFile=/absolute/path/to/release.keystore
storePassword=YOUR_STORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

## C. Build release AAB

```bash
cd natalo-petshop-app/
npm run build:bundle

# Output:
# android/app/build/outputs/bundle/release/app-release.aab
```

Upload `.aab` ini ke Play Console → Production → Create new release.

## D. QA Flows (manual test sebelum release)

Test di Android device fisik (bukan emulator), minimum Android 7 (API 24)
dan Android 14 (API 34).

| # | Flow | Expected |
|---|---|---|
| 1 | Buka app dari launcher | Splash blue → WebView load homepage natalopetshop.com |
| 2 | Cold start tanpa internet | offline.html tampil, tombol "Coba Lagi" → retry |
| 3 | Login member | Form login → dashboard member |
| 4 | Product search | Search bar → ketik → hasil filter |
| 5 | Product detail page | Tap produk → halaman detail, gambar carousel |
| 6 | Tambah ke keranjang | Tombol + Keranjang → toast/sheet, badge bottom-nav update |
| 7 | Cart update quantity | +/- button → harga total update |
| 8 | Hapus cart item | Tap trash → modal konfirmasi → konfirmasi → item hilang |
| 9 | Checkout | Tap Checkout → halaman alamat → metode → bayar |
| 10 | Ganti alamat tersimpan | Tap "Ubah alamat" → list alamat → pilih → kembali ke checkout |
| 11 | Voucher modal | Tap claim voucher → bottom sheet → pilih → applied |
| 12 | Shipping method | Tap pilih kurir → list rates → pilih → harga update |
| 13 | Payment redirect (Midtrans) | Tap bayar → Snap WebView di-load **di app** (jangan keluar) |
| 14 | Order success page | Setelah bayar sukses → redirect ke /orders/success |
| 15 | **Back @ root** | Press back di homepage → AlertDialog "Keluar?" |
| 16 | **Back @ product detail** | Press back → kembali ke products list (bukan close app) |
| 17 | **Back @ cart** | Press back → kembali ke previous page |
| 18 | **Back @ checkout** | Press back → kembali ke cart (bukan close) |
| 19 | WhatsApp link | Tap link WA di product → buka app WA, BUKAN WebView |
| 20 | Deep link dari WhatsApp | Share `https://www.natalopetshop.com/products/xxx` di WA → tap di chat → buka app langsung (perlu assetlinks.json valid) |
| 21 | Rotate orientation | Portrait → landscape → portrait → state preserved |
| 22 | Background → foreground | Home button → re-open app → state preserved |
| 23 | Kill app → re-open | Force quit → re-open → load homepage fresh |
| 24 | App icon, name, splash | Sesuai brand: ikon NL+paw, nama "Natalo Petshop" |

## E. Post-build sanity check

```bash
# Verify AAB content (need bundletool)
bundletool build-apks --bundle=app-release.aab --output=app.apks
bundletool install-apks --apks=app.apks

# Atau simpler: unzip & dump manifest
unzip -p app-release.aab base/manifest/AndroidManifest.xml | aapt2 dump xmltree --
```

Cek:
- versionCode = 6, versionName = 1.0.5
- allowBackup = false
- App Links intent-filter ada dgn autoVerify=true
- Permissions: hanya INTERNET + ACCESS_NETWORK_STATE

## F. Play Console upload checklist

- [ ] Upload AAB ke Production track
- [ ] Release notes: "v1.0.5 — perbaikan back button, offline handling,
      App Links untuk link WhatsApp/Instagram"
- [ ] Verify Data safety form (no PII collection beyond cookies)
- [ ] Verify Target API 35 declaration
- [ ] Rollout 10% → monitor crash rate 24 jam → 100%
