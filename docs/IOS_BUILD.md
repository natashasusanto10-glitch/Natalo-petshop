# Build .ipa Natalo Petshop untuk iOS

Panduan lengkap mengubah PWA Natalo Petshop jadi aplikasi iOS native (.ipa) lewat Capacitor. Strategi: shell native tipis yang membungkus URL produksi — Prisma + API routes tetap jalan di Vercel.

---

## Prasyarat (di Mac)

Wajib:

- **macOS 13+** dengan **Xcode 15+** (wajib App Store / Apple ID).
- **CocoaPods** — install: `sudo gem install cocoapods` (atau `brew install cocoapods`).
- **Node.js 18+** & **npm**.
- **Akun Apple Developer** ($99/tahun) — wajib untuk distribusi App Store / TestFlight. Untuk test di device sendiri saja cukup pakai free Apple ID.
- **iPhone fisik** (untuk test dengan device asli) atau pakai **Simulator** bawaan Xcode.

---

## Langkah 1 — Clone & Install di Mac

```bash
git clone https://github.com/natashasusanto10-glitch/Natalo-petshop.git
cd Natalo-petshop
npm install
```

---

## Langkah 2 — Set Domain Produksi

Edit `capacitor.config.ts`, ganti `server.url` dengan URL produksi yang sebenarnya:

```ts
server: {
  url: "https://DOMAIN-PRODUKSI-KAMU.com",  // ← ganti
  allowNavigation: ["DOMAIN-PRODUKSI-KAMU.com", "*.DOMAIN-PRODUKSI-KAMU.com"],
}
```

Domain harus HTTPS (Apple Transport Security menolak HTTP). Vercel default-nya HTTPS, jadi aman.

---

## Langkah 3 — Generate Folder iOS

```bash
npm run cap:add:ios
```

Ini menjalankan `npx cap add ios` yang membuat folder `ios/` lengkap dengan project Xcode (`ios/App/App.xcworkspace`). Internal-nya akan `pod install` otomatis.

> ⚠️ Jangan jalankan ini di Windows — `pod install` butuh Ruby + Xcode.

---

## Langkah 4 — Icon & Splash

Sumber sudah tersedia di `resources/`:

- `resources/icon-only.png` — 512×512 (saat ini). **Untuk produksi, ganti dengan 1024×1024.**
- `resources/icon-foreground.png` — versi maskable (boleh dibiarkan).

**Yang masih kurang:** `resources/splash.png` 2732×2732 (background brand `#1E5FBF`, logo di tengah). Bikin pakai Figma / Photoshop, simpan di path itu, lalu jalankan:

```bash
npm run cap:assets
```

Tool ini auto-generate semua ukuran iOS app icon (29px – 1024px) dan splash screen (semua ukuran iPhone & iPad), output ke `ios/App/App/Assets.xcassets/`.

**Kalau splash.png belum ada:** tetap bisa jalan — splash screen akan jadi default putih. Bisa diganti belakangan.

---

## Langkah 5 — Sync ke iOS

```bash
npm run cap:sync:ios
```

Sync `capacitor.config.ts` + plugin native ke project Xcode.

---

## Langkah 6 — Buka di Xcode

```bash
npm run cap:open:ios
```

Buka `App.xcworkspace` di Xcode. Yang harus di-set di Xcode:

1. **Project navigator → "App" → target "App" → Signing & Capabilities**
   - Centang **Automatically manage signing**.
   - **Team:** pilih Apple Developer team kamu (atau Apple ID free untuk personal test).
   - **Bundle Identifier:** `com.natalo.petshop` (sesuaikan kalau sudah punya bundle ID di App Store Connect).

2. **Display Name:** "Natalo Petshop" (sudah di-set via capacitor.config.ts).

3. **Deployment Info → iOS Deployment Target:** 14.0 atau lebih tinggi (default 13.0 sudah cukup).

---

## Langkah 7 — Test di Simulator atau Device

### Simulator (paling cepat)

1. Pilih device di toolbar atas Xcode (mis. "iPhone 15 Pro").
2. Tekan **▶ Run** (atau `Cmd+R`).
3. App jalan di Simulator, langsung load URL produksi.

### iPhone Fisik

1. Colok iPhone via USB.
2. **Settings → Privacy & Security → Developer Mode → On** (di iPhone, butuh restart).
3. Di Xcode toolbar, pilih device kamu.
4. ▶ Run → app dipasang & jalan.

> Pertama kali, iPhone akan complain "Untrusted Developer". Buka **Settings → General → VPN & Device Management** di iPhone, trust profile developer kamu.

---

## Langkah 8 — Build .ipa (Archive)

Untuk menghasilkan file `.ipa` yang bisa dibagikan / di-upload ke App Store:

1. Di Xcode toolbar, ganti device target ke **"Any iOS Device (arm64)"** (BUKAN simulator).
2. Menu **Product → Archive**. Tunggu build selesai (~3–5 menit).
3. Window **Organizer** akan otomatis muncul. Klik archive yang baru jadi.
4. **Distribute App** → pilih method:

| Method | Gunanya |
|---|---|
| **App Store Connect** | Upload ke TestFlight & App Store. Butuh app sudah terdaftar di App Store Connect. |
| **TestFlight Internal Only** | Hanya untuk internal team (s/d 100 tester). Tidak butuh review Apple. |
| **Ad Hoc** | Untuk install di device tertentu (UDID harus terdaftar). Output `.ipa` bisa dipasang via tools mis. Diawi, AltStore, atau Apple Configurator 2. |
| **Enterprise** | Cuma kalau punya Apple Enterprise Program ($299/tahun). |
| **Development** | Untuk development & internal test. Limit device sesuai daftar di Apple Dev Portal. |

5. **Next → Next → Export** — pilih folder, dapat file `Natalo Petshop.ipa`.

---

## Distribusi via TestFlight (paling umum)

Setelah Archive → Distribute → "App Store Connect":

1. Login App Store Connect (https://appstoreconnect.apple.com/).
2. **My Apps → + → New App.** Isi nama, bundle ID (`com.natalo.petshop`), SKU.
3. Upload archive dari Xcode Organizer **"Upload"**.
4. Tunggu Apple proses (~10–30 menit), masuk ke **TestFlight** tab.
5. Tambah **Internal Testers** (anggota team) — mereka instant dapat email & bisa langsung pasang lewat TestFlight app.
6. Untuk **External Testers** (sampai 10.000 orang), butuh Beta Review dari Apple (1–2 hari).

---

## Update App (setiap kali ada perubahan kode di repo)

Karena strategi-nya WebView remote-load:

- **Perubahan UI / halaman web** → tinggal `git push` ke production. iPhone tidak perlu re-install, refresh app langsung dapat versi baru.
- **Perubahan native** (plugin Capacitor, splash, icon, capacitor.config.ts) → wajib build ulang `.ipa` & distribusi lagi via TestFlight.

---

## Plugin Native (kalau mau ditambah)

Kalau nanti butuh fitur native dari iPhone (kamera, push, geo, dll):

```bash
npm install @capacitor/push-notifications @capacitor/camera @capacitor/geolocation
npx cap sync ios
```

Lalu di code web bisa import dan pakai. Ingat tambah usage description di `ios/App/App/Info.plist` (mis. `NSCameraUsageDescription`).

---

## Troubleshooting

**`pod install` gagal di langkah `cap add ios`:**
```bash
cd ios/App && pod repo update && pod install
```

**Build error "No matching profile":**
- Login Xcode → Preferences → Accounts → tambah Apple ID.
- Manage Certificates → +Apple Development.

**App buka cuma layar putih:**
- Cek `server.url` di capacitor.config.ts sudah HTTPS & valid.
- Buka URL itu di Safari Mac dulu, pastikan jalan.

**Cookie auth tidak persisten:**
- `limitsNavigationsToAppBoundDomains: false` di capacitor.config.ts (sudah).
- Pastikan domain produksi pakai cookie `Secure; SameSite=None` atau `Lax` (jose JWT cookie kita default `Lax`, aman).

**Splash screen flicker:**
- Setting `SplashScreen.launchAutoHide: true` (sudah).
- Manual hide via plugin: `import { SplashScreen } from '@capacitor/splash-screen'; SplashScreen.hide();` setelah app ready.

---

## Ringkasan command (di Mac, setelah pull dari git)

```bash
npm install
# edit capacitor.config.ts → set server.url
npm run cap:add:ios          # sekali saja, generate folder ios/
npm run cap:assets           # generate icon & splash dari resources/
npm run cap:sync:ios         # tiap habis ubah config / install plugin
npm run cap:open:ios         # buka Xcode
# di Xcode: Product → Archive → Distribute App → pilih method → Export
```

Output akhir: `Natalo Petshop.ipa` siap upload ke TestFlight / App Store / Ad Hoc.
