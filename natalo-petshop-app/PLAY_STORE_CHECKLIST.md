# Natalo Petshop - Play Store Submission Checklist

## Build Outputs (READY)

| File | Size | Tujuan |
|------|------|--------|
| `dist/natalo-petshop-v1.0.0.aab` | 2.56 MB | **Upload ke Play Console** |
| `dist/natalo-petshop-v1.0.0.apk` | 1.95 MB | Test di device langsung (sideload) |

**App ID:** `com.natalopetshop.app`
**Version:** 1.0.0 (versionCode: 1)
**Min SDK:** 23 (Android 6.0)
**Target SDK:** 35 (Android 15) — memenuhi syarat Play Store 2026

---

## ⚠️ KEYSTORE — JANGAN SAMPAI HILANG

Lokasi: `android/app/natalo-petshop-release.keystore`
Password: `NataloP3tshop2026!` (di `android/keystore.properties`)

**Backup keystore + password ke 2 tempat aman** (cloud + USB). Tanpa keystore yang sama, **tidak bisa update app** di Play Store. Solusinya cuma buat app baru dari nol.

> Saya rekomendasikan ganti password keystore default ini sebelum publish — bisa pakai `keytool -storepasswd` dan `keytool -keypasswd`.

---

## Sebelum Upload — Yang Sudah Beres

- [x] `versionCode = 1`, `versionName = "1.0.0"`
- [x] AAB sudah di-sign (V2 + V3 signature)
- [x] `targetSdk = 35` (memenuhi Play Store)
- [x] `minifyEnabled = true` + ProGuard rules untuk Capacitor
- [x] Network security config — HTTPS only, no cleartext
- [x] Permission minimal: hanya INTERNET + ACCESS_NETWORK_STATE
- [x] App ID unik: `com.natalopetshop.app`
- [x] Splash screen + status bar terkonfigurasi
- [x] Intent handler untuk WhatsApp/tel/mailto/external links

## Yang HARUS Disiapkan untuk Play Console

### Aset Toko
- [ ] **App icon high-res** — 512×512 PNG, max 1MB (sudah ada di `resources/icon.png`, 512×512)
- [ ] **Feature graphic** — 1024×500 PNG/JPG (BELUM, perlu dibuat)
- [ ] **Screenshot HP** — minimal 2, resolusi 1080×1920 atau lebih (BELUM)
- [ ] **Screenshot tablet** (opsional, tapi bagus)

### Konten Toko (Tulis di Play Console)
- [ ] **Judul app** — max 30 karakter (contoh: "Natalo Petshop & Aquarium")
- [ ] **Short description** — max 80 karakter
- [ ] **Full description** — max 4000 karakter
- [ ] **Kategori** — Shopping atau Lifestyle
- [ ] **Email kontak** — wajib publik
- [ ] **Privacy Policy URL** — WAJIB (host di natalopetshop.com/kebijakan-privasi)

### Compliance
- [ ] **Data safety form** — declare data apa yang dikumpulkan (email, lokasi, dll)
- [ ] **Content rating** — isi kuesioner IARC (~5 menit)
- [ ] **Target audience** — pilih usia
- [ ] **Ads** — declare ada iklan atau tidak
- [ ] **Government app** — No

---

## Cara Upload ke Play Store

1. Buka https://play.google.com/console
2. Bayar $25 sekali (kalau belum punya developer account)
3. **Create app** → Natalo Petshop → Bahasa Indonesia
4. Isi form di Dashboard (5 section utama, ikuti urutan)
5. **Production → Releases → Create new release**
6. Upload file: `dist/natalo-petshop-v1.0.0.aab`
7. Review release → Start rollout to Production

> **Tips:** Untuk release pertama, pakai **Internal testing** dulu. Tester max 100 orang, langsung live tanpa review (atau review cepat ~3 jam). Setelah stabil, baru promote ke Production.

---

## Test APK Sebelum Upload

```powershell
# Pastikan device terhubung via USB (Developer Options + USB Debugging ON)
$env:Path = "$env:LOCALAPPDATA\Android\Sdk\platform-tools;$env:Path"
adb install C:\Users\USER\Desktop\natalo-petshop-app\dist\natalo-petshop-v1.0.0.apk
```

App akan terinstall sebagai "Natalo Petshop" di device. Buka, pastikan:
- Splash screen muncul (warna teal #468284)
- Loading website www.natalopetshop.com
- Klik tombol WhatsApp → buka app WhatsApp native
- Klik link external → buka di Chrome
- Tombol Back navigate dengan benar

---

## Update App di Masa Depan

```powershell
# 1. Naikkan version di android/app/build.gradle:
#    versionCode 2  (harus selalu lebih tinggi dari sebelumnya)
#    versionName "1.0.1"

# 2. Sync + build ulang
cd C:\Users\USER\Desktop\natalo-petshop-app
npx cap sync android
cd android
.\gradlew.bat bundleRelease

# 3. Upload AAB baru ke Play Console → Production → Create new release
```

> Karena pakai **Hybrid Mode** (load website live), update konten website **TIDAK perlu rebuild APK**. Cukup deploy ke www.natalopetshop.com, semua user otomatis dapat update.
