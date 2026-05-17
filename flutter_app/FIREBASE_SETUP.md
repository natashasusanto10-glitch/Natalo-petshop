# Firebase / FCM Setup — Quick Start

App Flutter sudah **infrastructure push notification lengkap** + **Gradle plugin sudah di-config**. Tinggal **2 langkah manual** untuk aktifkan FCM (sisanya sudah auto-setup oleh Claude).

Tanpa langkah ini, app **tetap jalan normal** — service no-op silently. Setelah selesai, push notification langsung aktif.

---

## Yang Sudah Auto-Setup (Selesai)

- ✅ Firebase CLI ter-install global (`firebase-tools` via npm)
- ✅ FlutterFire CLI ter-install (`flutterfire_cli` via dart pub global)
- ✅ Gradle plugin `com.google.gms.google-services` v4.4.2 sudah di-config di:
  - `android/settings.gradle.kts` (plugin declaration)
  - `android/app/build.gradle.kts` (plugin apply)
- ✅ Flutter packages: `firebase_core`, `firebase_messaging`, `flutter_local_notifications`
- ✅ Service `PushNotificationService` (init, foreground handler, token register/unregister, deep link routing)
- ✅ Wired di `main.dart`, login flow, logout flow
- ✅ Backend endpoint `/api/push/subscribe-fcm` (POST + DELETE) sudah ada di PWA

---

## Yang Harus Anda Lakukan (2 Langkah, ~10 menit)

### Langkah 1 — Firebase Login (browser auth, 1 menit)

Buka **Command Prompt biasa** (cmd.exe / PowerShell), lalu:

```cmd
firebase login
```

Browser akan terbuka → login Google → klik "Allow" → kembali ke terminal. Selesai.

### Langkah 2 — Pakai project Firebase yang sudah ada (~5 menit)

Project Firebase "**natalopetshop**" sudah ada (dari Capacitor APK). Kita tambah Android app baru untuk Flutter (`com.natalopetshop.app`) ke project yang sama.

Di Command Prompt, masuk ke folder flutter_app:

```cmd
cd C:\Users\USER\Desktop\natalopetshopflutter\flutter_app
"%LOCALAPPDATA%\Pub\Cache\bin\flutterfire.bat" configure ^
  --project=natalopetshop ^
  --platforms=android ^
  --android-package-name=com.natalopetshop.app ^
  --yes
```

> Kalau project ID Anda bukan persis `natalopetshop`, run `firebase projects:list` dulu untuk lihat project ID yang benar (kadang ada suffix random mis. `natalopetshop-abc12`).

Atau **interactive mode**:

```cmd
"%LOCALAPPDATA%\Pub\Cache\bin\flutterfire.bat" configure
```

CLI tanya:
- **"Select a Firebase project"** → pilih **`natalopetshop`** (yang sudah ada)
- **"Which platforms?"** → centang **android** saja (space toggle, enter confirm)
- CLI akan tanya tentang Android package — pakai `com.natalopetshop.app`

CLI akan:
1. **Register Android app baru** (`com.natalopetshop.app`) di project `natalopetshop` — Capacitor APK lama (`com.natalo.petshop`) tidak terpengaruh, tetap di project yang sama
2. **Download `google-services.json`** otomatis ke `android/app/`
3. **Generate `lib/firebase_options.dart`** (tidak kita pakai — `Firebase.initializeApp()` baca dari google-services.json)
4. Cloud Messaging API sudah enabled (project sudah pakai FCM untuk Capacitor)

Setelah selesai, verify:

```cmd
dir android\app\google-services.json
```

Harus muncul file tersebut.

### Langkah 3 (Optional) — Backend FCM credential

Untuk **kirim** push dari PWA backend (mis. saat order shipped), butuh service account.

1. Firebase Console → ⚙ **Project Settings** → tab **Service accounts**
2. Klik **Generate new private key** → download JSON (mis. `natalopetshop-818c4-firebase-adminsdk-xxxxx.json`)
3. Buka file JSON, copy 3 field ini ke `.env.local` di **toko-pwa-starter**:

```env
FCM_PROJECT_ID="natalopetshop-818c4"
FCM_CLIENT_EMAIL="firebase-adminsdk-xxxxx@natalopetshop-818c4.iam.gserviceaccount.com"
# Private key PEM full, escape newline jadi \n literal kalau di Vercel/.env single-line:
FCM_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAA...etc...\n-----END PRIVATE KEY-----\n"
```

> Field-field ini ada di JSON: `project_id`, `client_email`, `private_key`.
> Untuk `FCM_PRIVATE_KEY` di Vercel/single-line `.env`, replace newline asli dengan `\n` literal — `lib/fcm.ts` akan auto-decode kembali (`replace(/\\n/g, "\n")`).

4. Restart Next.js dev server: `npm run dev` di `toko-pwa-starter`
5. Trigger order status update di admin panel → user dapat push otomatis di Flutter app.

⚠️ **SECRET** — jangan commit JSON service account ke git. `.gitignore` `.env.local` sudah default di Next.js.

---

## Build & Test

```cmd
cd C:\Users\USER\Desktop\natalopetshopflutter\flutter_app
flutter pub get
flutter run
```

App akan minta **permission notification** saat first launch. Accept → cek log:

```
[push] FCM token: dXXXXxxxXXX...
```

Test kirim:
1. Firebase Console → **Cloud Messaging** → "Send test message"
2. Paste token dari log → Send
3. Notification muncul di status bar HP

---

## Troubleshooting

**`firebase: command not found`**
- Buka cmd baru (PATH perlu reload setelah npm install -g)
- Atau jalankan: `npx firebase-tools login`

**`flutterfire: command not found`**
- Pakai full path: `"%LOCALAPPDATA%\Pub\Cache\bin\flutterfire.bat"` (Windows)
- Atau tambahkan `%LOCALAPPDATA%\Pub\Cache\bin` ke PATH env var

**Build error: "Could not find google-services.json"**
- Pastikan file ada di `android/app/google-services.json` (bukan `android/`)
- Re-run `flutterfire configure` kalau tidak otomatis di-download

**Token kosong / `[push] Init failed`**
- `google-services.json` belum ada → app tetap jalan, push silent disabled
- Cek Firebase project → Cloud Messaging API enabled (default sudah enabled)

**Notif tidak muncul saat foreground**
- Normal kalau native FCM. App handle via `flutter_local_notifications` (sudah implemented).

---

## Cara Kirim Push dari Backend

Pakai existing helper di PWA: `lib/fcm.ts` di `toko-pwa-starter`.

```typescript
import { sendToUser } from "@/lib/fcm";

await sendToUser(userId, {
  title: "Pesanan kamu sudah dikirim! 📦",
  body: "Order NAT-20260516-001 dalam perjalanan via Gojek.",
  data: {
    deepLink: "natalo://member/orders",
  },
});
```

User tap notif → deep link handler parse path → navigate langsung ke screen.
