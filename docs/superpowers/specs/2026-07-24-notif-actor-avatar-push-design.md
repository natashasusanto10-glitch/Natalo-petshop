# Notifikasi — Foto Aktor di Push + Real-time List — Design

Tanggal: 2026-07-24. Status: disetujui user (keputusan tercatat di bawah).

## Ringkasan

Saat seseorang menandai/berinteraksi dengan user, notifikasi push menampilkan **foto aktor** (yang menandai/mengomentari/menyukai) — seperti Instagram/Shopee. Sekarang push hanya mengirim thumbnail postingan.

- **Android:** migrasi push ke **data-only HANYA untuk notifikasi sosial/beraktor** (feed: tag/komentar/like/mention/follow); app merender sendiri → avatar tampil sebagai `largeIcon` **bulat** (di semua kondisi: foreground/background/terminated). **Order/pembayaran/promo TETAP notification-message** (keandalan pengiriman maksimal; tak punya avatar aktor). Lihat keputusan #3 + review D2.
- **iOS:** tetap `alert` + `mutable-content` (data-only tidak andal di iOS); Notification Service Extension (NSE) melampirkan foto aktor sebagai thumbnail **kotak** (persis IG di iOS).
- **In-app:** notif `feed_tagged` dapat ikon + label **"Ditandai"** dan masuk tab **Aktivitas** (bukan fallback generik).
- **Bonus P0 (#2):** layar notifikasi yang sedang terbuka **auto-refresh** saat push baru masuk.
- **Cleanup:** hapus komentar "stub" basi di composer `feed_new_post_screen.dart`.

## Keputusan user (tercatat)

1. Foto di push berbentuk **avatar bulat ala IG** (largeIcon) — bukan gambar besar.
2. iOS: **kotak via NSE saja** (tanpa Notification Content Extension). Banner iOS memang tak bisa bulat (batas OS; IG pun kotak di iOS).
3. Migrasi push Android data-only: **HANYA notifikasi sosial/beraktor** (revisi dari "semua" via engineering review D2). Alasan: push data-only Android tidak seandal notification-message — tidak terkirim ke app yang di-force-stop (umum di OEM agresif) + kena Doze lebih ketat. Order/pembayaran/promo yang kritis TETAP notification-message supaya terjamin sampai. Trade-off avatar-bulat hanya ditanggung notifikasi yang memang butuh avatar.
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

### 2. Lapisan kirim FCM — per-notif: data-only (sosial) vs notification-message (sisanya)

Tambah flag `renderClientSide` pada `PushPayload`, di-set dari **allowlist eksplisit event beraktor** (bukan dari kategori) — hanya `feed_new_comment`, `feed_new_like`, `feed_mention`, `feed_tagged`, `user_followed`. Alasan (engineering review A2): kategori `feed` juga memuat event TANPA aktor yang tetap harus andal — terutama `feed_encoding_failed` (masih aktif via `reconcile.ts`) dan event moderasi admin `feed_post_approved`/`feed_post_rejected` (kini hanya lewat endpoint admin moderasi laporan sejak auto-approve PR #225). Event-event itu TETAP notification-message. Ubah shaping FCM (`lib/fcm.ts`):
- **Sosial/beraktor (renderClientSide=true) → Android data-only:** HILANGKAN blok `notification` top-level (agar OS tidak auto-display; app render sendiri). Field tampilan pindah ke `data`. `android.priority=high`.
- **Semua notif lain (order/bayar/promo/status → renderClientSide=false) → Android notification-message SEPERTI SEKARANG.** Tidak berubah — keandalan pengiriman terjaga.
- **iOS (semua jenis): alert + mutable-content** — `apns.payload.aps.alert` + `mutable-content=1` (+ category bila perlu). `data` ikut (NSE baca). `fcm_options.image` tetap fallback bila `actor_avatar_url` kosong. iOS tidak pernah data-only.

Web push (`sendPushToUser`) tetap seperti sekarang + tambah `actor_avatar_url` di data untuk konsistensi.

`createFeedNotification` (`notification-center.ts`): isi `pushData.actor_avatar_url = params.actor?.avatarUrl` bila ada, dan set `renderClientSide=true` untuk event feed beraktor (tag/comment/like/mention/follow). Baris `Announcement` tetap tak berubah.

**Blast radius:** hanya event sosial yang ganti jalur kirim. Order/promo/admin tak tersentuh (regresi nol pada notifikasi kritis).

### 2b. Gate kapabilitas per-token (WAJIB — cegah notifikasi hilang di app lama)

Masalah version skew (engineering review A3): app versi lama tidak punya background-render, jadi pesan data-only tak akan tampil sama sekali di background/terminated → notifikasi sosial hilang senyap untuk seluruh basis pengguna sampai update.

Solusi: **backend hanya kirim data-only ke token yang app-nya mendukung render-klien.**
- Saat registrasi/refresh push token, simpan **kapabilitas** per token: kolom baru mis. `PushToken.clientRenderVersion Int?` (atau `appVersion`/`capabilities` string). App baru mengirim penanda "dukung client-render" saat register token.
- Di `lib/fcm.ts`, untuk event sosial (renderClientSide): **per-token** → token berkapabilitas dapat data-only; token TANPA kapabilitas (app lama / belum lapor) dapat **notification-message biasa** (dengan `fcm_options.image` = foto post/avatar, tanpa avatar bulat). Jadi selalu ada notifikasi yang tampil, hanya bentuk foto yang beda sampai user update.
- Konsekuensi: satu event bisa menghasilkan pesan berbeda per device token milik user yang sama (fan-out per-token, bukan per-user tunggal). Ini menambah percabangan di layer kirim FCM.

## Hardening (dari outside voice — wajib masuk implementasi/plan)

Semua ini bukan opsional — jadi kriteria di rencana implementasi:

- **Dedup / ID notifikasi (Android):** app-rendered `flutter_local_notifications` pakai notification `id` deterministik dari server notification id / `tag` (mis. hash `feed-tagged-<postId>-<userId>`), supaya tag baru tidak menimpa sembarang dan tidak ada dobel. PASTIKAN pesan sosial TIDAK pernah membawa blok `notification` sekaligus (kalau bocor → dobel: OS-drawn + app-drawn).
- **Background isolate init (Android):** handler background WAJIB `DartPluginRegistrant.ensureInitialized()` + (untuk panggilan plugin) `BackgroundIsolateBinaryMessenger.ensureInitialized(RootIsolateToken.instance)`. Catatan: `RootIsolateToken.instance` bisa null di isolate FCM — tangani dengan aman (kalau null, tetap tampilkan notifikasi tanpa avatar).
- **Download avatar di jalur kirim:** timeout eksplisit (mis. 3–5s) + downscale ke ukuran largeIcon (≈128–192px) sebelum decode/crop (cegah OOM di isolate hemat memori) + cache disk sederhana (jangan unduh ulang avatar sama tiap notif). **KRITIS:** kalau download/crop gagal/timeout → notifikasi TETAP tampil (largeIcon fallback ikon kategori atau tanpa largeIcon). Bungkus `_circleAvatarBitmap` try/catch; kegagalan avatar TIDAK boleh membatalkan notifikasi.
- **Gating preferensi = hanya di backend.** Backend sudah gate via `isPushCategoryEnabled` sebelum kirim. Client background render **TIDAK** boleh gate ulang (baca prefs dari background isolate rapuh) → client render tanpa cek ulang. Hilangkan gagasan "client cek `categoryEnabled`" di jalur render.
- **iOS payload budget & NSE:** total `data` (title/body/url/thumbnail/actor_avatar_url) + `aps.alert` harus < 4KB (batas APNs) — jangan duplikasi berlebihan. NSE: timeout-aware (`serviceExtensionTimeWillExpire` tetap panggil `contentHandler`), attachment ada batas ukuran (~10MB) & `UNNotificationAttachment(...)` bisa throw → fallback tetap tampil; bersihkan temp file.
- **Cold-start satu arbiter:** di startup, tentukan SATU sumber launch — untuk notif sosial (app-rendered) pakai `getNotificationAppLaunchDetails`; untuk OS-drawn (order/promo) pakai FCM `getInitialMessage`. Jangan konsultasi keduanya untuk notif yang sama → cegah navigasi dobel / deep-link kelewat.
- **Channel parity:** definisi channel (id, importance, sound) di jalur background HARUS identik dengan foreground — Android "first-definition-wins", beda importance nanti diabaikan.
- **Kuota high-priority:** FCM batasi kuota high-priority data message per-app; like bisa volume tinggi. Andalkan agregasi like yang sudah ada (jendela 30 menit) supaya tidak menghabiskan kuota; jangan naikkan volume push.
- **Real-time list (#2):** debounce tick (mis. 400–800ms) supaya burst push tidak menghajar endpoint; refresh senyap hanya prepend + anti-jump (anchor offset) — idealnya hanya auto-apply saat list di posisi atas, kalau user sedang scroll ke bawah tampilkan pil "notifikasi baru" alih-alih menggeser. Pastikan `_load()` tidak menaikkan tick (cegah loop).

### 3. Android (Flutter) — render semua notifikasi sendiri

- **Background handler** (`push_notification_service.dart:32`, kini no-op) → render notifikasi via `flutter_local_notifications` HANYA untuk pesan data-only (yang `message.notification == null`, yakni notif sosial). Init plugin + channel di isolate background, ambil title/body/channel/url/thumbnail/`actor_avatar_url` dari `message.data`. Pesan notification-message (order/promo) tetap digambar OS — handler tak menyentuhnya (tidak dobel).
- **Foreground** disatukan ke fungsi render yang sama. Gate `shouldDisplayLocally` dialihkan dari `hasNotificationPayload` → render bila **ada data payload yang perlu render-klien** (deteksi via `renderClientSide`/absennya `notification`), supaya notif sosial (kini data-only) tetap tampil di foreground.
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

**Risiko utama (revisi via D2):** hanya notifikasi SOSIAL yang ganti ke jalur render-klien; order/bayar/promo tetap notification-message (regresi nol pada notif kritis). Sisa risiko = keandalan data-only pada notif sosial di OEM agresif (bisa telat/hilang saat app di-force-stop) — dapat diterima karena notif sosial tidak kritis, dan trade-off ini yang membeli avatar-bulat.

**Matriks device-verify wajib (sebelum rilis):**
- Android sosial (data-only): foreground / background / terminated × (tag/komentar/like dgn avatar) — muncul, avatar bulat, tap membuka tujuan, TIDAK dobel.
- Android non-sosial (notification-message, JANGAN regresi): order (9 status) / promo broadcast tetap tampil andal seperti sebelum, action button ("Lacak Paket"/"Beri Review") utuh, tap membuka tujuan.
- iOS: tag menampilkan lampiran foto aktor (kotak); order/promo tetap normal; tanpa avatar → fallback thumbnail; tap membuka tujuan.
- Preferensi: toggle kategori OFF benar-benar membungkam (Android render path hormati gating).
- In-app: baris `feed_tagged` tampil ikon/label "Ditandai" + foto aktor; tab Aktivitas; layar terbuka auto-refresh saat push masuk.

**Unit test:**
- Backend: shaping pesan FCM → event sosial (renderClientSide) = Android data-only (tanpa `notification`); event non-sosial (order/promo) = TETAP punya blok `notification` (tak berubah). iOS semua punya `aps.alert` + `mutable-content`. `actor_avatar_url` ada untuk event beraktor.
- Dart: `_circleAvatarBitmap` menghasilkan bitmap (bulat) dari bytes; render builder set `largeIcon` saat `actor_avatar_url` ada; tap parser ambil `url`.
- `flutter analyze` + suite existing hijau.

## Di luar scope (backlog audit)

Agregasi luas (komentar/follow/mention "X dan N lainnya"), pagination/infinite-scroll, preferensi per-jenis-event, push chat (Firestore→push), quiet hours/DND, throttling burst, retry/dead-letter, badge count endpoint murah + dot bottom-nav, kategorisasi tab berbasis `eventType` (bukan keyword), swipe-hapus/mute per-notif, jenis event baru (price-drop wishlist, review-reply, loyalty-tier). Semua ini proyek terpisah.

## Urutan kerja bertahap (branch claude/notif-actor-avatar-push)

Fase, aman dirilis bertahap:
1. **Backend payload + capability gate** — kolom kapabilitas token, `renderClientSide` allowlist, shaping FCM per-token (`lib/fcm.ts`), `actor_avatar_url` di payload. Unit test shaping. (Boleh rilis lebih dulu: token lama otomatis dapat notification-message — tak ada regresi.)
2. **Android client render** — background handler render, `_circleAvatarBitmap`, largeIcon, dedup id, isolate init, download timeout+fallback, tap routing. App baru lapor kapabilitas saat register token.
3. **iOS NSE** — attach `actor_avatar_url`, fallback thumbnail, cleanup.
4. **In-app** — visual `feed_tagged` + tab; real-time list (#2) dengan debounce/anti-jump; cleanup komentar stub.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | issues_open→folded | 3 arsitektur (D2, A2, A3) semua dilipat ke spec |
| Outside Voice | subagent (opus) | Independent 2nd opinion | 1 | issues_found→folded | 1 P0 (version skew) + 10 hardening, semua dilipat |

- **CODEX:** tidak jalan (CLI tak terpasang) — outside voice via Claude subagent (opus).
- **CROSS-MODEL:** tidak ada tension — outside voice menambah temuan baru (version skew P0) yang tidak bertentangan dengan review; disetujui user via A3 (gate per kapabilitas token). Sisanya hardening yang diterima sebagai kriteria implementasi.
- **VERDICT:** ENG CLEARED (setelah D2 scope-reduction + A2 predikat allowlist + A3 capability-gate + hardening dilipat). Siap lanjut ke rencana implementasi (writing-plans) lalu kerjakan bertahap.

**UNRESOLVED DECISIONS:**
- Tidak ada — D2, A2, A3 (dan order D3) semua terjawab user; hardening outside-voice diterima sebagai kriteria wajib implementasi.
