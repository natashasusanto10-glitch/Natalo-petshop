# Build .ipa Natalo Petshop — Tanpa Mac, Lewat GitHub Actions

Workflow: GitHub Actions runner macOS-15 yang otomatis build & sign `.ipa`, lalu upload ke TestFlight. Kamu kerja **100% dari Windows + browser**.

---

## Prasyarat

- ✅ Apple Developer Program **berbayar** ($99/tahun) — status "Membership Active".
- ✅ App Store Connect API key (file `.p8`, Key ID, Issuer ID).
- ✅ GitHub repo Natalo-petshop (sudah ada).
- ✅ GitHub Personal Access Token dengan akses repo.
- ⚠️ Private GitHub repo kedua untuk Fastlane match (`natalo-ios-certs` — kosong, akan diisi otomatis oleh CI).

---

## SETUP PERTAMA KALI (sekali saja)

### Langkah 1 — App ID & App Store Connect

Begitu enrollment kamu **APPROVED**:

#### 1a. Register App ID
[developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers/list) → **+** :
- App IDs → App
- Description: `Natalo Petshop`
- Bundle ID: **Explicit** → `com.natalo.petshop`
- Capabilities: leave default (kosongin)
- Continue → Register

#### 1b. Create App di App Store Connect
[appstoreconnect.apple.com](https://appstoreconnect.apple.com/apps) → **+** → New App:
- Platforms: iOS
- Name: **Natalo Petshop**
- Primary Language: Indonesian
- Bundle ID: pilih `com.natalo.petshop`
- SKU: `natalo-petshop-001`
- User Access: Full Access

### Langkah 2 — App Store Connect API Key

[App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys](https://appstoreconnect.apple.com/access/integrations/api):

1. Klik **+** → Generate Key
2. Name: `GitHub Actions Build`
3. Access: **App Manager** (atau Admin)
4. Generate
5. **DOWNLOAD `.p8` FILE SEKARANG** — Apple cuma kasih sekali. Simpan di `~/Downloads/AuthKey_XXXXXXXXXX.p8`.
6. Catat **Issuer ID** (di header tabel, format UUID) dan **Key ID** (10 karakter).

### Langkah 3 — Private Repo untuk Match Certs

[github.com/new](https://github.com/new):
- Name: `natalo-ios-certs`
- Visibility: **Private** (WAJIB — isinya cert encrypted, jangan public)
- Initialize: **Add a README**
- Create

Jangan push apapun ke repo ini — fastlane match akan isi otomatis.

### Langkah 4 — GitHub Personal Access Token (PAT)

[github.com/settings/personal-access-tokens/new](https://github.com/settings/personal-access-tokens/new) (Fine-grained):
- Token name: `Natalo iOS CI match`
- Expiration: 1 year
- Repository access: **Only select repositories** → pilih `natalo-ios-certs`
- Permissions → Repository permissions:
  - **Contents**: Read and write
  - **Metadata**: Read-only (auto)
- Generate token
- **COPY TOKEN SEKARANG** — Apple-style, GitHub cuma tampilkan sekali.

### Langkah 5 — Set GitHub Secrets

[github.com/natashasusanto10-glitch/Natalo-petshop/settings/secrets/actions](https://github.com/natashasusanto10-glitch/Natalo-petshop/settings/secrets/actions) → New repository secret:

| Secret Name | Isi | Cara dapatkan |
|---|---|---|
| `APP_STORE_CONNECT_API_KEY_ID` | 10 karakter (mis. `ABCDE12345`) | Dari Langkah 2 |
| `APP_STORE_CONNECT_API_ISSUER_ID` | UUID | Dari Langkah 2 |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | Buka file `.p8` di Notepad, copy SELURUH ISI termasuk `-----BEGIN PRIVATE KEY-----` dan `-----END PRIVATE KEY-----` | File `.p8` dari Langkah 2 |
| `MATCH_PASSWORD` | Password kamu pilih sendiri (contoh: `NataloIOS2026!@#`). Catat baik-baik — dipakai untuk decrypt cert kalau kamu rebuild kemudian. | Bikin sendiri, password kuat |
| `MATCH_GIT_URL` | URL clone repo certs, mis. `https://github.com/natashasusanto10-glitch/natalo-ios-certs.git` | Dari Langkah 3 |
| `MATCH_GIT_BASIC_AUTHORIZATION` | Hasil base64 dari `username:PAT_TOKEN` (lihat di bawah) | Generate via PowerShell |

#### Cara generate `MATCH_GIT_BASIC_AUTHORIZATION` di PowerShell Windows:

```powershell
$user = "natashasusanto10-glitch"
$pat = "github_pat_XXXXXXXXXXXX"  # ganti dengan PAT dari Langkah 4
$pair = "$user`:$pat"
[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
```

Output (string panjang) → paste sebagai value secret `MATCH_GIT_BASIC_AUTHORIZATION`.

---

## BUILD `.ipa` PERTAMA

Setelah semua secret ter-set:

1. **Update `capacitor.config.ts`** — pastikan `server.url` sudah pakai domain produksi yang benar (sekarang masih placeholder `https://natalo-petshop.vercel.app`).

2. **Push tag versi pertama** dari Windows:
   ```powershell
   git tag v1.0.0
   git push origin v1.0.0
   ```

3. **Tunggu di GitHub UI**: [Actions tab](https://github.com/natashasusanto10-glitch/Natalo-petshop/actions) → workflow "iOS Build & TestFlight" → klik run yang sedang jalan.

4. **Yang terjadi otomatis di runner macOS GitHub** (~10-15 menit):
   - npm install
   - `npx cap add ios` (generate folder iOS) — auto-commit balik ke repo
   - `cap sync` (copy capacitor.config + plugin native ke ios/)
   - `cap:assets` (generate icon dari `resources/icon-only.png`)
   - `pod install`
   - Fastlane match: generate Distribution cert + App Store profile, simpan encrypted ke `natalo-ios-certs`
   - Fastlane gym: archive Xcode → `.ipa`
   - Fastlane pilot: upload ke TestFlight
   - Upload `.ipa` sebagai GitHub artifact

5. **Hasil**: build muncul di TestFlight ~5 menit setelah upload (Apple proses ulang). Cek email TestFlight.

---

## INSTALL DI iPHONE LEWAT TESTFLIGHT

1. Di iPhone, buka App Store → cari **TestFlight** → install.
2. Login pakai Apple ID kamu (yang sama dengan Apple Developer).
3. Buka TestFlight → Natalo Petshop muncul di **Apps**.
4. Tap **Install** → app terpasang di home screen.

**Untuk tester lain (bukan kamu):**

- **Internal Testers** (s/d 100 orang, tanpa Apple review): tambah Apple ID mereka di App Store Connect → Users and Access → Sandbox / Internal Testers.
- **External Testers** (s/d 10.000 orang, perlu Beta Review Apple 1-2 hari): set up Public Link di TestFlight tab.

---

## UPDATE APP

### Update isi web (UI, halaman, logic)
Karena strategi WebView remote-load di `capacitor.config.ts → server.url`:

```powershell
git push origin main  # auto-deploy Vercel → app di iPhone refresh, dapat versi baru
```

**Tidak perlu rebuild .ipa.** iPhone tinggal pull-to-refresh atau buka ulang.

### Update native (capacitor config, plugin, icon, splash)

```powershell
git tag v1.0.1
git push origin v1.0.1
```

GitHub Actions trigger build baru → upload TestFlight → tester dapat notifikasi update.

---

## TROUBLESHOOTING

### "Match: Could not find Repository"
Cek `MATCH_GIT_URL` benar (HTTPS, ada `.git` di akhir) dan PAT (`MATCH_GIT_BASIC_AUTHORIZATION`) punya akses write ke repo certs.

### "Could not find provisioning profile"
Cek bundle ID di App Store Connect = `com.natalo.petshop` PERSIS sama dengan `capacitor.config.ts` dan `fastlane/Appfile`.

### "App Store Connect API: Authentication credentials are missing"
Salah satu dari 3 secret API key salah/typo:
- `APP_STORE_CONNECT_API_KEY_ID` — 10 char
- `APP_STORE_CONNECT_API_ISSUER_ID` — UUID
- `APP_STORE_CONNECT_API_KEY_CONTENT` — termasuk header/footer `-----BEGIN/END PRIVATE KEY-----`

### Build sukses tapi TestFlight kosong
Tunggu 5-30 menit, Apple proses ulang. Cek **App Store Connect → My Apps → Natalo Petshop → TestFlight tab → Builds**.

### "Code signing identity not found"
First run `match` belum sukses generate cert. Cek log fastlane match step. Coba:
- Hapus repo `natalo-ios-certs`, bikin ulang fresh, push tag baru.
- Atau jalankan workflow manual via "Run workflow" → pilih lane `beta`.

---

## ARCHITECTURE NOTES

**Mengapa WebView remote-load (server.url) bukan static export?**

Project Natalo punya:
- API routes (`app/api/*`) yang butuh Node runtime
- Prisma client yang butuh DB connection
- jose JWT auth via httpOnly cookie
- Server actions untuk admin CRUD

Static export (`output: 'export'`) akan break semua di atas. WebView remote-load = `.ipa` cuma shell tipis yang membuka URL Vercel produksi. Konsekuensi positif: update UI = tinggal `git push`, bukan rebuild + redistribute.

**Plugin native yang bisa ditambah nanti** (kalau perlu):
- `@capacitor/push-notifications` — APNS push native iOS (vs web push terbatas)
- `@capacitor/camera` — akses kamera native (vs `<input type="file">` mobile web)
- `@capacitor/geolocation` — GPS lebih akurat
- `@capacitor/share` — system share sheet

Setiap habis tambah plugin: `git push tag v1.x.0` → CI rebuild `.ipa` → distribute via TestFlight.
