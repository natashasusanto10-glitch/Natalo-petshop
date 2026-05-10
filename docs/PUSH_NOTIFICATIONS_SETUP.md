# Push Notifications Setup — Natalo Petshop iOS

Notif order update muncul di lock screen iPhone — kerja saat app ditutup.
Major retention feature.

## Yang sudah saya kerjakan (otomatis lewat code)

### Client-side (iOS native + Web Push fallback)
- ✅ `@capacitor/push-notifications` plugin installed
- ✅ `components/PushSubscribe.tsx` — auto-detect platform: native iOS pakai
  Capacitor APNs, web pakai existing Web Push (VAPID)
- ✅ APNs token register via `PushNotifications.requestPermissions()` →
  `PushNotifications.register()` → token disimpan ke backend
- ✅ Disabled flow: instructional message ke iOS Settings (Apple gak kasih
  programmatic API untuk unregister)

### Server-side
- ✅ `app/api/push/subscribe-apns/route.ts` — endpoint terima APNs token,
  simpan di `PushSubscription` table dengan format `endpoint = "apns:<token>"`
- ✅ `lib/apns.ts` — APNs sender via `@parse/node-apn`. Read env vars
  (APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_CONTENT, APNS_BUNDLE_ID, APNS_PRODUCTION)
- ✅ `lib/push.ts` `sendOrderStatusPush()` — kirim ke BOTH Web Push dan APNs
  paralel. Existing `sendPushToUser()` di-filter cuma ke Web Push subs
  (endpoint HTTPS), `sendApnsToUser()` filter ke endpoint `apns:*`.

### iOS Entitlements
- ✅ `ios/App/App/App.entitlements` — tambah `aps-environment = production`

## Yang HARUS kamu kerjakan (4 step, ~15 menit)

### Step 1 — Enable "Push Notifications" capability di App ID

[developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers/list):

1. Klik App ID `com.natalo.petshop`
2. Scroll ke section **Capabilities**
3. Cari **"Push Notifications"** → centang ☑️
4. Save

### Step 2 — Generate APNs Auth Key (.p8)

[developer.apple.com → Keys](https://developer.apple.com/account/resources/authkeys/list):

1. Klik **+** create new key
2. Name: `Natalo APNs Production`
3. Centang **"Apple Push Notifications service (APNs)"**
4. Continue → **Register**
5. **DOWNLOAD `AuthKey_XXXXXXXXXX.p8`** sekarang juga (Apple cuma kasih sekali!)
6. **Catat 2 nilai:**
   - **Key ID**: 10 karakter (di nama file `AuthKey_XXXXXXXXXX.p8`)
   - **Team ID**: `87FXPV558A` (sudah kamu tahu)
7. Pindahkan file `.p8` ke `~/Documents/keys/AuthKey_APNS_XXXXXXXXXX.p8`

⚠️ **Beda dari App Store Connect API key (yang udah kita pakai untuk fastlane).**
Yang ini KHUSUS untuk APNs.

### Step 3 — Set GitHub Secrets / Vercel Environment Variables

APNs sender perlu jalankan di **production server (Vercel)**, bukan di
GitHub Actions runner. Set environment variable di Vercel project, bukan
GitHub Secrets.

Buka [vercel.com/dashboard](https://vercel.com/dashboard) → project Natalo-petshop → **Settings → Environment Variables**:

| Name | Value | Environments |
|---|---|---|
| `APNS_KEY_ID` | 10-char Key ID dari Step 2 | Production + Preview |
| `APNS_TEAM_ID` | `87FXPV558A` | Production + Preview |
| `APNS_KEY_CONTENT` | Buka file `.p8` di Notepad, copy SELURUH ISI termasuk `-----BEGIN PRIVATE KEY-----` dan `-----END PRIVATE KEY-----` | Production + Preview |
| `APNS_BUNDLE_ID` | `com.natalo.petshop` | Production + Preview |
| `APNS_PRODUCTION` | `true` | Production |
| `APNS_PRODUCTION` | `false` | Preview |

Klik Save untuk masing-masing.

⚠️ **Provisioning profile auto-update**: setelah capability "Push Notifications"
enabled di App ID, fastlane match akan auto-regenerate profile dengan
capability baru saat CI build berikutnya jalan.

### Step 4 — Trigger redeploy + new build

```powershell
# Trigger Vercel redeploy biar env vars baru kepick
git commit --allow-empty -m "trigger: pickup APNs env vars"
git push origin main

# Trigger CI iOS build dengan capability Push Notifications baru
git tag v1.0.16
git push origin v1.0.16
```

## Test setelah Build 16 ready

### A. Subscribe APNs di iPhone
1. Update Natalo via TestFlight ke Build 16
2. Login ke akun member
3. Buka halaman order — di bagian atas page, harus muncul tombol:
   **"🔔 Aktifkan notifikasi update pesanan"**
4. Tap tombol → iOS native permission dialog: **"Natalo Petshop ingin mengirim notifikasi"**
5. Tap **Allow**
6. Tombol berubah jadi **"🔔 Notifikasi order aktif"** (warna hijau)

### B. Trigger push dari admin
1. Login admin di app web
2. Buka order yang status PENDING
3. Update status ke **PAID**
4. ~5 detik kemudian, iPhone kamu **dapat push notif**:
   ```
   📲 Update Pesanan 🛍️
   Pembayaranmu sudah dikonfirmasi! Pesanan sedang disiapkan.
   ```
5. Tap notif → app buka langsung ke detail order

### C. Verify iOS Settings
**Settings → Natalo Petshop → Notifications**:
- Allow Notifications: ON
- Lock Screen / Notification Center / Banners: bisa di-config user
- Sounds: ON (default)
- Badges: ON (default)

## Troubleshooting

### "BadDeviceToken" di backend log

Token sandbox dipakai untuk production APNs (atau sebaliknya). Cek
`APNS_PRODUCTION` env var:
- TestFlight build pakai production APNs → set `true`
- Xcode debug build pakai sandbox APNs → set `false`

`aps-environment` di entitlements harus match. Kita sekarang `production` —
match TestFlight default.

### App ke-prompt "Notif diblokir" walau pertama kali tap

User mungkin sebelumnya pernah tap "Don't Allow" di permission dialog.
Apple cache pilihan ini. User harus manual: Settings → Natalo → Notifications
→ Allow Notifications: ON.

### Push gak sampai walau token register sukses

1. Cek Vercel logs untuk error dari `sendApnsToUser()`
2. Common issues:
   - `APNS_KEY_CONTENT` salah (BEGIN/END line tidak include)
   - `APNS_TEAM_ID` typo
   - APNs key sudah revoked di Apple portal
   - Token expired (re-register via app)

### Multiple devices per user

Code current: setiap kali user subscribe di device baru, token baru disimpan
sebagai row baru di `PushSubscription`. Kalau user logout dari device A,
token-nya tetap aktif (bug minor, tapi push masih berhasil sampai ke device A).

Future improvement: track device-userId mapping, cleanup token saat logout.

## Architecture summary

```
User di iPhone
  ↓ subscribe push (PushSubscribe.tsx)
  ↓ Capacitor PushNotifications.register()
  ↓ APNs server kasih device token via "registration" event
  ↓ POST /api/push/subscribe-apns dengan token
  ↓ Disimpan di PushSubscription dengan endpoint "apns:<token>"

Admin update order status (mis. PAID)
  ↓ Backend trigger sendOrderStatusPush(orderId, status)
  ↓ Function panggil:
    - sendPushToUser(userId, ...) → kirim ke web subs
    - sendApnsToUser(userId, ...) → kirim ke APNs subs

sendApnsToUser(userId)
  ↓ Read env: APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_CONTENT
  ↓ Init @parse/node-apn provider
  ↓ Filter PushSubscription: endpoint LIKE "apns:%"
  ↓ Untuk each token: provider.send(notification, token)
  ↓ Kalau token invalid (BadDeviceToken / Unregistered) → cleanup dari DB

iPhone receive APNs push
  ↓ iOS show notification di lock screen + notification center
  ↓ User tap → app buka, route ke URL dari payload
```
