# Notification Service Extension (NSE) — Setup

Wave 4 #9. Push notification rich content (image attachment + action buttons).

Files di folder ini (`NotificationService.swift`, `Info.plist`) **belum
otomatis ter-link ke Xcode project** — perlu add target manual sekali via
Xcode IDE. Setelah itu, `npx cap sync ios` akan keep file in sync.

## Steps (jalankan sekali setelah pull commit Wave 4):

1. **Open Xcode project**

   ```bash
   npx cap open ios
   ```

   Atau buka langsung `ios/App/App.xcworkspace`.

2. **Add Notification Service Extension target**

   - File → New → Target
   - Pilih **Notification Service Extension**
   - Product Name: `NotificationServiceExtension`
   - Language: Swift
   - Project: App
   - Embed in Application: App
   - Klik **Finish**
   - Saat ditanya "Activate scheme?", pilih **Cancel** (biar tetap pakai
     scheme App)

3. **Replace generated files dengan yang sudah ada di repo**

   Xcode generate `NotificationService.swift` + `Info.plist` default —
   replace dengan file dari folder ini (yang sudah punya implementasi
   download image + action handling):

   - Di Finder, navigate ke `ios/App/NotificationServiceExtension/`
   - Drag `NotificationService.swift` dan `Info.plist` ke Xcode target
     `NotificationServiceExtension`, replace existing files.
   - Atau: di Xcode delete generated files, lalu right-click target →
     Add Files to "NotificationServiceExtension" → pilih file dari folder
     repo.

4. **Set Bundle Identifier**

   - Target `NotificationServiceExtension` → General → Bundle Identifier:

     ```
     com.natalo.petshop.NotificationServiceExtension
     ```

   (Pattern: main bundle ID + suffix.)

5. **Deployment Target**

   - Target → General → Deployment Info → iOS 14.0 (atau match dengan
     main App target).

6. **Capabilities & Signing**

   - Target → Signing & Capabilities → Team: pilih Apple Developer Team
     yang sama dengan App target.
   - **No additional capabilities needed** — NSE sudah include APN entitlement
     via main app target.

7. **Build + Test**

   ```bash
   npx cap sync ios
   npx cap run ios
   ```

   Test dari Vercel: trigger admin feed approval → notif dengan thumbnail
   harusnya muncul di banner iOS.

## Cara debug

NSE tidak muncul di console aplikasi utama. Buka **Console.app** di Mac,
filter by `subsystem:com.natalo.petshop.NSE`. Atau di Xcode, attach to
process `NotificationServiceExtension` (Debug → Attach to Process by PID).

## Yang tidak terjadi tanpa NSE setup ini

- Push notification masih sampai ke device — text-only.
- Image attachment di payload diabaikan oleh iOS (mutable-content flag
  tidak ada target untuk dipanggil).
- Action buttons (Lihat / Buang) tetap muncul — itu di-register di
  AppDelegate, tidak butuh NSE.

Jadi NSE = optional UX upgrade, bukan blocker. Push tetap fungsional
sebelum setup ini selesai.
