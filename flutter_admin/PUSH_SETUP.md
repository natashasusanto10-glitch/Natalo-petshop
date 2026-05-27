# Push Notification Setup — Natalo Admin

Push notif Firebase Cloud Messaging (FCM) untuk admin sudah ter-wire di code (`lib/services/fcm_service.dart` + `lib/main.dart`). Sebelum push beneran jalan, perlu setup Firebase project + drop `google-services.json`.

Tanpa file ini, app tetap jalan normal — push cuma tidak aktif (init dibungkus try/catch + fallback ke badge polling 60s).

## Status setelah setup

Setelah `google-services.json` di-drop dan rebuild APK, admin akan dapat notif HP saat:

| Event | Trigger | Tag |
|---|---|---|
| Order baru masuk | `POST /api/orders` success | `order-new-{orderNumber}` |
| Customer minta cancel | `POST /api/orders/{n}/cancel` (PAID mode) | `cancel-req-{orderNumber}` |
| Customer post feed komunitas | `POST /api/feed/posts` (customer role, PHOTO/VIDEO) | `feed-pending-{postId}` |
| Abuse flag severity HIGH | `lib/abuse-detection.ts` createFlag | `abuse-{flagId}` |

Backend helper: `lib/push-admin.ts` (auto-find semua user role=ADMIN, kirim parallel).

## Setup steps

### 1. Buat Firebase project & Android app

1. Buka [Firebase Console](https://console.firebase.google.com)
2. **Add project** → nama bebas misal "Natalo Admin"
3. Aktifkan Google Analytics (optional, untuk Crashlytics nanti)
4. Setelah project siap → **Add app** → **Android**
5. Isi:
   - **Package name**: `com.natalo.petshop.admin` (HARUS persis ini — match `applicationId` di `android/app/build.gradle.kts`)
   - **App nickname**: Natalo Admin
   - **SHA-1**: skip dulu (tidak wajib untuk FCM, hanya untuk Auth/Dynamic Links)
6. Klik **Register app**

### 2. Download & drop `google-services.json`

Firebase Console kasih file `google-services.json`. Drop ke:

```
flutter_admin/android/app/google-services.json
```

### 3. Wire Google Services Gradle plugin

Edit **`flutter_admin/android/build.gradle.kts`** (root project) — tambahkan dependency plugin (di section `buildscript` atau `plugins` block):

```kotlin
plugins {
    id("com.google.gms.google-services") version "4.4.2" apply false
}
```

Edit **`flutter_admin/android/app/build.gradle.kts`** — apply plugin di bagian `plugins`:

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")   // <-- tambah ini
}
```

### 4. (Opsional, untuk service account backend) Generate private key

Backend (`lib/fcm.ts`) butuh service account credentials untuk kirim push via Firebase Admin SDK. Cek apakah env var `FIREBASE_SERVICE_ACCOUNT_JSON` (atau setara) sudah ada di `.env` / Vercel. Kalau belum:

1. Firebase Console → Project settings → Service accounts
2. **Generate new private key** → download JSON
3. Salin isi JSON ke env var (single-line, escape kalau perlu). Lihat `lib/fcm.ts` untuk nama env var exact-nya.

> Note: Customer app sudah pakai Firebase. Kalau admin pakai **project Firebase yang sama**, service account credentials customer otomatis work. Tinggal tambah aplikasi Android baru ke project itu di Step 1 (skip "Add project", langsung "Add app").

### 5. Rebuild

```bash
cd flutter_admin
flutter clean
flutter pub get
flutter run    # dev
# atau
flutter build apk --release   # production
```

Pertama kali launch, app akan prompt permission notifikasi. Admin harus allow.

## Verifikasi

Setelah setup:

1. Login admin di app
2. Di terminal log device, cari `[fcm] token registered (len=...)` → token sudah ter-register ke backend
3. Buka backend DB → `SELECT * FROM "PushSubscription" WHERE endpoint LIKE 'fcm:%' AND "userId" = '<admin-user-id>'` → harus ada row
4. **Test self**: hit `POST /api/admin/push/test-self` (endpoint sudah ada) → HP admin harus terima notif test

Untuk test event beneran:
- Customer test bikin order baru → admin HP buzz
- Customer minta cancel order PAID → admin HP buzz

## Troubleshooting

**`Default FirebaseApp is not initialized`** saat run:
→ google-services.json salah path. Pastikan di `android/app/`, bukan di `android/`.

**Build error `Google Services plugin not applied`**:
→ Lupa edit `android/app/build.gradle.kts` di Step 3.

**Token registered tapi notif tidak masuk**:
→ Cek env var `FIREBASE_SERVICE_ACCOUNT_JSON` di backend. Tanpa ini, `lib/fcm.ts` skip kirim (graceful no-op).

**Notif masuk tapi tap tidak buka detail screen**:
→ Deep-link routing belum di-implement (lihat TODO di `fcm_service.dart` `_navigateTo`). Untuk MVP, tap notif cuma open app + refresh badge.

## Disable sementara

Mau matiin push tanpa hapus file? Comment baris `await FcmService.instance.init();` di `main.dart`. App jalan tanpa Firebase init.
