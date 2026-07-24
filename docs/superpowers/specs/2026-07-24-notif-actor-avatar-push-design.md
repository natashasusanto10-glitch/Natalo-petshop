# Notifikasi — Foto Aktor di Push + Real-time List — Design

Tanggal: 2026-07-24. Status: disetujui user (keputusan tercatat di bawah).

## Ringkasan

Saat seseorang menandai/berinteraksi dengan user, notifikasi push menampilkan **foto aktor** (yang menandai/mengomentari/menyukai) — seperti Instagram/Shopee. Sekarang push hanya mengirim thumbnail postingan.

- **Android:** migrasi push ke **data-only** untuk SEMUA jenis notifikasi; app merender sendiri tiap notifikasi → avatar tampil sebagai `largeIcon` **bulat** (di semua kondisi: foreground/background/terminated).
- **iOS:** tetap `alert` + `mutable-content` (data-only tidak andal di iOS); Notification Service Extension (NSE) melampirkan foto aktor sebagai thumbnail **kotak** (persis IG di iOS).
- **In-app:** notif `feed_tagged` dapat ikon + label **"Ditandai"** dan masuk tab **Aktivitas** (bukan fallback generik).
- **Bonus P0 (#2):** layar notifikasi yang sedang terbuka **auto-refresh** saat push baru masuk.
- **Cleanup:** hapus komentar "stub" basi di composer `feed_new_post_screen.dart`.

## Keputusan user (tercatat)

1. Foto di push berbentuk **avatar bulat ala IG** (largeIcon) — bukan gambar besar.
2. iOS: **kotak via NSE saja** (tanpa Notification Content Extension). Banner iOS memang tak bisa bulat (batas OS; IG pun kotak di iOS).
3. Migrasi push Android data-only: **langsung pindah semua sekaligus**, tanpa flag/fallback. (Rekomendasi awal saya "bertahap+fallback" tidak diambil — risiko regresi lebih tinggi, dikompensasi pengujian menyeluruh; tercatat.)
4. Ruang lingkup: avatar-push (P0) + real-time list (#2). Sisa temuan audit (agregasi luas, pagination, preferensi granular, push chat, quiet hours, throttling, retry) **di luar scope** — jadi backlog terpisah.

## Kondisi saat ini (hasil audit — yang relevan)

- Backend punya satu helper feed `createFeedNotification` (`lib/feed/notification-center.ts:116`) yang fan-out ke web push + FCM + tulis baris `Announcement`. Dispatcher tag `sendTaggedUserNotifications` (`lib/feed/activity-notifications.ts:289`) sudah brand-safe & sudah membawa `actor.avatarUrl`.
- Push payload (`PushPayload`, `lib/push.ts:17`) sekarang set `imageUrl = thumbnailUrl` (thumbnail post), **tidak** membawa avatar aktor di `data`.
- FCM dikirim via `sendFcmToUser` (`lib/fcm.ts`); web push via `sendPushToUser` (`lib/push.ts`). Gating preferensi (`isPushCategoryEnabled`) sudah ada di kedua jalur.
- Baris notifikasi **in-app sudah menampilkan foto aktor** (`actorAvatarUrl` → `_IdentityAvatar`, `notifications_screen.dart`). Jadi in-app tidak butuh perubahan avatar — hanya ikon/label `feed_tagged`.
- Flutter push: `push_notification_service.dart` hanya render lokal saat **foreground** (`shouldDisplayLocally` butuh `isForeground && hasNotificationPayload`); background handler (`:32`) sengaja no-op karena OS auto-display. Ada plumbing download gambar (`_buildBigPictureStyle`, `:659`) yang bisa dipakai ulang, tapi `largeIcon` belum pernah di-set.
- iOS NSE (`ios/NotificationService/NotificationService.swift:33`) cuma memanggil `FIRMessagingExtensionHelper().populateNotificationContent` (lampirkan `fcm_options.image`); belum baca key custom.
- Badge/refresh count murni pull-based (`AppNotificationButton` dengar `notificationRefreshTick`), tapi **layar notifikasi terbuka tidak** ikut dengar tick itu → tidak auto-refresh.

## Arsitektur

### 1. Data contract push (backend → client)

Tambah field ke `data` map push (dibaca Android Dart + iOS NSE):
- `actor_avatar_url` — URL foto aktor (brand-safe; sudah tersedia di dispatcher). Kosong/absen untuk notif tanpa aktor tunggal (order/promo/milestone) → client render tanpa avatar (ikon kategori).
- Field tampilan yang sudah ada tetap: `type` (=eventType), `feed_post_id`/`post_id`, `url` (deep link), `thumbnail_url`.
- Tambah `title`/`body` ke `data` juga (untuk Android yang kini render dari data) — sudah ada di payload tapi kini WAJIB terbaca dari `data` di sisi Android.
- Tambah `channel`/`pref_category` hint (opsional) supaya Android bisa pilih channel + gating konsisten.

### 2. Lapisan kirim FCM — satu pesan, dua bentuk platform

Ubah shaping pesan FCM (`lib/fcm.ts`) supaya **satu** pesan FCM menghasilkan:
- **Android: data-only** — HILANGKAN blok `notification` top-level (agar OS tidak auto-display). Semua field tampilan pindah ke `data`. `android.priority=high`.
- **iOS: alert + mutable-content** — set `apns.payload.aps.alert` (title/body) + `apns.payload.aps.mutable-content = 1` + `apns.payload.aps.category` bila perlu. `data` tetap ikut (NSE membacanya). `fcm_options.image` (thumbnail) tetap sebagai fallback bila `actor_avatar_url` kosong.

Ini pola standar cross-platform "data-only-Android + alert-iOS". Web push (`sendPushToUser`) tetap seperti sekarang (browser tampilkan image di body) + tambahkan `actor_avatar_url` di data untuk konsistensi.

`createFeedNotification` (`notification-center.ts`): isi `pushData.actor_avatar_url = params.actor?.avatarUrl` bila ada. Baris `Announcement` tetap tak berubah.

**Cakupan "semua notif":** perubahan shaping ada di chokepoint `lib/fcm.ts` sehingga SETIAP pemanggil (order/promo/chat-none/feed/admin) otomatis ikut data-only-Android. Tidak ada perubahan per-dispatcher selain menambah `actor_avatar_url` di yang punya aktor.

### 3. Android (Flutter) — render semua notifikasi sendiri

- **Background handler** (`push_notification_service.dart:32`, kini no-op) → render notifikasi via `flutter_local_notifications`: init plugin + channel di isolate background, ambil title/body/channel/url/thumbnail/`actor_avatar_url` dari `message.data`, tampilkan.
- **Foreground** disatukan ke fungsi render yang sama. Gate `shouldDisplayLocally` dialihkan dari `hasNotificationPayload` → **`hasDataPayload`** (karena Android kini data-only, `message.notification` null).
- **Avatar bulat:** helper baru `_circleAvatarBitmap(url)` — download (reuse fetch dari `_buildBigPictureStyle`) → crop lingkaran via `dart:ui` (`Canvas` + `clipPath`/`drawImage` ke kanvas bulat) → `ByteArrayAndroidBitmap` → set `AndroidNotificationDetails.largeIcon`. `bigPicture` = thumbnail post (bila ada) tetap dari `_buildBigPictureStyle`.
- **Tap routing:** notifikasi lokal → `onDidReceiveNotificationResponse` (+ `getNotificationAppLaunchDetails` untuk terminated) → route via deep-link handler yang ada memakai `url` di payload. Pastikan tidak ada dobel dengan `onMessageOpenedApp` (yang untuk background/terminated tetap dipakai bila OS yang display — kini tidak, jadi routing lokal jadi jalur utama Android).
- **Channel & gating:** gunakan channel per prefCategory; hormati toggle preferensi (client sudah punya `categoryEnabled`).

### 4. iOS (native) — NSE lampirkan foto aktor

`NotificationService.swift`: sebelum/at gantinya panggilan Firebase helper —
- Baca `request.content.userInfo["actor_avatar_url"]`. Bila ada: download → tulis ke temp file → `UNNotificationAttachment` → set `bestAttemptContent.attachments`.
- Bila kosong: fallback ke perilaku sekarang (`FIRMessagingExtensionHelper().populateNotificationContent` untuk `fcm_options.image` = thumbnail).
- Tetap panggil `contentHandler(bestAttemptContent)`; tangani `serviceExtensionTimeWillExpire`.
- Backend WAJIB set `mutable-content:1` (sudah bila ada image; set eksplisit untuk notif tag walau tanpa thumbnail).

### 5. In-app — visual `feed_tagged` + tab

- `_NotificationVisual.from()` (`notifications_screen.dart:~1865`): tambah case `feed_tagged` → ikon `Icons.local_offer_rounded` (atau `person_pin_rounded`), warna brand, label **"Ditandai"** — ditaruh sebelum fallback feed generik.
- Tab: `feed_tagged` sudah masuk tab **Aktivitas** (karena `_NotificationFilter.feed` cocok via keyword) — verifikasi; bila perlu perkuat dengan match `eventType == 'feed_tagged'` eksplisit supaya tak bergantung keyword.

### 6. Real-time list terbuka (#2)

`_NotificationsScreenState` dengarkan `pushNotificationService.notificationRefreshTick` (`ValueNotifier<int>`, `push_notification_service.dart:91`). Saat tick naik DAN layar aktif → `_load()` senyap (tanpa spinner, pertahankan posisi scroll). Ini melengkapi badge yang sudah refresh; sekarang list ikut hidup.

### 7. Cleanup

Hapus komentar doc usang di `feed_new_post_screen.dart` (dekat `_openTagPeople`, ~baris 201-203) yang menyatakan picker "masih stub" — kode sebenarnya sudah lengkap.

## Risiko & pengujian

**Risiko utama (pilihan user: pindah semua sekaligus, tanpa fallback):** setiap jenis notifikasi Android ikut jalur render baru. Bug di background handler bisa mempengaruhi SEMUA notif. Mitigasi = pengujian + device-verify menyeluruh, bukan flag.

**Matriks device-verify wajib (sebelum rilis):**
- Android: foreground / background / terminated × (tag dgn avatar) / (order tanpa avatar) / (promo broadcast) — notifikasi muncul, avatar bulat pada tag, thumbnail pada yang punya, tap membuka tujuan benar, tidak dobel.
- iOS: tag menampilkan lampiran foto aktor (kotak); order/promo tetap normal; tanpa avatar → fallback thumbnail; tap membuka tujuan.
- Preferensi: toggle kategori OFF benar-benar membungkam (Android render path hormati gating).
- In-app: baris `feed_tagged` tampil ikon/label "Ditandai" + foto aktor; tab Aktivitas; layar terbuka auto-refresh saat push masuk.

**Unit test:**
- Backend: shaping pesan FCM → Android data-only (tanpa `notification`), iOS punya `aps.alert` + `mutable-content`, `actor_avatar_url` ada untuk event beraktor.
- Dart: `_circleAvatarBitmap` menghasilkan bitmap (bulat) dari bytes; render builder set `largeIcon` saat `actor_avatar_url` ada; tap parser ambil `url`.
- `flutter analyze` + suite existing hijau.

## Di luar scope (backlog audit)

Agregasi luas (komentar/follow/mention "X dan N lainnya"), pagination/infinite-scroll, preferensi per-jenis-event, push chat (Firestore→push), quiet hours/DND, throttling burst, retry/dead-letter, badge count endpoint murah + dot bottom-nav, kategorisasi tab berbasis `eventType` (bukan keyword), swipe-hapus/mute per-notif, jenis event baru (price-drop wishlist, review-reply, loyalty-tier). Semua ini proyek terpisah.
