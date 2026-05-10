# Universal Links Setup — Natalo Petshop

Universal Links biar link `https://natalo-petshop.vercel.app/products/...` di WhatsApp/email/browser **buka langsung di app Natalo native**, bukan Safari.

## Yang sudah saya kerjakan (otomatis lewat code)

### Server-side
- ✅ AASA file di `app/.well-known/apple-app-site-association/route.ts`
  → Endpoint `/.well-known/apple-app-site-association` serve JSON ke iOS
- ✅ Daftar path yang harus open di app: `/products/*`, `/kategori/*`, `/pesanan/*`, `/order-status/*`, `/wishlist`, `/cart`, `/member/*`
- ✅ Path admin di-exclude (tetap di browser)

### iOS-side
- ✅ `ios/App/App/App.entitlements` dengan `applinks:natalo-petshop.vercel.app`
- ✅ `ios/debug.xcconfig` reference entitlements file (`CODE_SIGN_ENTITLEMENTS`)
- ✅ `components/DeepLinkHandler.tsx` listen `App.addListener("appUrlOpen")` + route via Next.js router
- ✅ `@capacitor/app` plugin installed

## Yang HARUS kamu kerjakan (Apple Developer Portal — ~5 menit)

### 1. Enable "Associated Domains" capability di App ID

1. Buka [developer.apple.com → Certificates, Identifiers & Profiles → Identifiers](https://developer.apple.com/account/resources/identifiers/list)
2. Klik App ID **`com.natalo.petshop`** (Natalo Petshop)
3. Scroll ke section **Capabilities**
4. Cari **"Associated Domains"** → centang ☑️
5. Klik **Save** kanan atas
6. Konfirmasi modal "Update App ID" yang muncul

⚠️ Tanpa ini, build berikutnya akan **error saat sign**: "Provisioning profile doesn't include the com.apple.developer.associated-domains entitlement".

### 2. Provisioning profile auto-update via fastlane match

Setelah capability enabled di App ID, fastlane match harus regenerate provisioning profile dengan capability baru. Saat CI build berikutnya jalan:

- Match detect bahwa profile current gak match capability App ID
- Auto-regenerate profile (kalau readonly: false)

⚠️ Tapi setup match kita sekarang **readonly true** (set via setup_ci di Fastfile). Untuk first regenerate, perlu temporary override:

#### Opsi A — Temporary disable readonly (recommended, sekali aja)

Di `fastlane/Fastfile`, line `before_all`:

```ruby
before_all do
  setup_ci if ENV["CI"]
  ENV["MATCH_READONLY"] = "false"  # ← UDAH ADA, biarkan
end
```

Confirm `MATCH_READONLY = false` (yang udah set sebelumnya untuk first cert generation). Saat CI build v1.0.14 jalan, match auto-regenerate profile dengan capability baru.

#### Opsi B — Manual force regenerate

Kalau opsi A gak work, hapus profile lama dulu dari Apple portal:
1. [developer.apple.com → Profiles](https://developer.apple.com/account/resources/profiles/list)
2. Cari `match AppStore com.natalo.petshop`
3. Delete
4. Push new tag → match generate fresh dengan capability associated-domains

## Test setelah Build 14 ready

### A. Verify AASA file accessible

Buka di browser:
```
https://natalo-petshop.vercel.app/.well-known/apple-app-site-association
```

Harus return JSON yang dimulai dengan `"applinks": { "details": ...`. Plus header `Content-Type: application/json`.

### B. Verify app entitlement

Setelah install Build 14 di iPhone, di Settings → Natalo Petshop, harusnya muncul kontrol baru (atau gak ada error di Console.app saat app launch).

### C. Test Universal Link

⚠️ **Penting**: Universal Link iOS punya quirk — link YANG SAMA yang baru di-tap **dari dalam app** akan tetap buka di Safari (gak loop ke app sendiri). Test pakai cara berikut:

#### Test method — paste link ke external app:

1. Copy URL produk Natalo, mis: `https://natalo-petshop.vercel.app/products/royal-canin-persian-adult-2kg`
2. Paste di **Notes app iPhone** (atau Mail / Messages)
3. Long-press link → muncul preview menu
4. Kalau Universal Link work: ada **"Open in Natalo Petshop"** option
5. Tap option itu → Natalo app buka langsung ke product detail
6. Kalau gak ada option itu / langsung buka Safari → AASA / entitlement belum link properly

#### Atau test via QR code:

1. Generate QR dari URL produk: pakai [qr-code-generator.com](https://qr-code-generator.com)
2. Scan QR via app Camera iPhone
3. Hasil: app Natalo buka langsung, navigate ke product detail

## Troubleshooting

### Link masih buka di Safari (gak ke app)

Possible causes:
1. **AASA file gak accessible / wrong format**
   - Buka URL di browser, harus return valid JSON
   - Header `Content-Type: application/json`
   - No redirect (200 OK direct)

2. **Capability belum enabled di App ID**
   - Cek developer.apple.com → App ID `com.natalo.petshop` → Capabilities → Associated Domains: ON

3. **Provisioning profile lama belum regenerate**
   - Re-run fastlane match dengan readonly: false
   - Atau delete profile manually dari Apple portal

4. **iOS cache AASA file**
   - iOS cache AASA selama 7 hari
   - Force refresh: delete app + restart iPhone + reinstall Build 14
   - Atau test di iPhone simulator dengan `xcrun simctl openurl booted https://natalo-petshop.vercel.app/products/xxx` (kalau punya Mac)

### Build error: "Missing entitlement"

```
error: Provisioning profile "match AppStore com.natalo.petshop" doesn't include
  the com.apple.developer.associated-domains entitlement.
```

Berarti capability belum aktif di App ID portal, atau profile lama. Step 1 di atas.

### Custom domain selain natalo-petshop.vercel.app

Kalau nanti pindah ke custom domain (mis. `app.natalopetshop.com`):

1. Update `app/.well-known/apple-app-site-association/route.ts` (cuma path config, gak perlu domain)
2. Update `ios/App/App/App.entitlements` — ganti `applinks:natalo-petshop.vercel.app` ke domain baru
3. Update `components/DeepLinkHandler.tsx` hostname check
4. Re-deploy AASA file di domain baru
5. Re-build .ipa
6. iOS cache AASA 7 hari, jadi efek-nya bertahap rolled out
