# natalo_feed (Flutter)

Port modul **Feed** dari toko-pwa-starter ke Flutter. Mirror Wave 1-4 dari Next.js source.

## Status Wave

| Wave | Web Commit | Status Flutter |
|------|-----------|----------------|
| Wave 1 — network-aware quality + bulk admin | `247c9cf2` | Scaffold |
| Wave 2 — blurhash LQIP + HLS adaptive WiFi | `fac10751` | Scaffold |
| Wave 3 — TUS resumable + app lifecycle | `8cec099b` | Scaffold |
| Wave 4 — push rich content + cinema mode | `79f012a5` | Scaffold |

## Bootstrap

Folder ini berisi **lib/** + **pubspec.yaml** saja (kerangka). Untuk dapat folder `android/`, `ios/`, `web/`, `test/`, jalankan sekali:

```bash
cd flutter_feed
flutter create . --org com.natalo.feed --project-name natalo_feed --platforms=android,ios
flutter pub get
```

`flutter create` tidak overwrite file existing — jadi `lib/` + `pubspec.yaml` aman.

## Run

```bash
flutter run -d <device>
```

Set `API_BASE_URL` di [lib/api/feed_api.dart](lib/api/feed_api.dart) — default `http://10.0.2.2:3000` (Android emulator → host) atau IP LAN saat di device fisik.

## Struktur

```
lib/
├── main.dart                          ← entry point + ProviderScope + go_router
├── models/
│   ├── feed_post.dart                 ← mirror Prisma FeedPost
│   └── feed_comment.dart              ← mirror Prisma FeedComment (1-level threading)
├── api/
│   ├── feed_api.dart                  ← dio client → /api/feed/**
│   └── bunny_upload.dart              ← TUS resumable (Wave 3) + simple PUT fallback
├── services/
│   ├── network_tier.dart              ← Wave 1: getNetworkTier + getRecommendedVideoQuality
│   ├── upload_lifecycle.dart          ← Wave 3: pending upload state TTL 24h
│   └── push_notifications.dart        ← Wave 4: FCM + categories (feed_review/feed_result)
├── state/
│   └── feed_provider.dart             ← Riverpod async notifier (feed list + like toggle)
├── screens/
│   ├── feed_screen.dart               ← PageView.builder vertical (replaces CSS scroll-snap)
│   └── upload_screen.dart             ← 5-step wizard (pick → preview → trim → detail → success)
└── widgets/
    ├── feed_video_card.dart           ← single card (player + actions + caption)
    ├── feed_video_player.dart         ← better_player wrapper + cinema mode (Wave 4)
    ├── blurhash_canvas.dart           ← Wave 2 LQIP placeholder
    └── comment_sheet.dart             ← bottom sheet 42-56% viewport
```

## Pemetaan ke Web Source

| Flutter file | Web source |
|--------------|------------|
| `models/feed_post.dart` | `prisma/schema.prisma:681-775` |
| `api/feed_api.dart` | `app/api/feed/posts/**` |
| `api/bunny_upload.dart` | `lib/feed/tus-upload.ts` + `lib/feed/bunny.ts` |
| `services/network_tier.dart` | `lib/feed/runtime-config.ts` |
| `services/upload_lifecycle.dart` | `lib/feed/upload-lifecycle.ts` |
| `services/push_notifications.dart` | `lib/feed/notification-center.ts` + `lib/apns.ts` + `lib/fcm.ts` |
| `screens/feed_screen.dart` | `components/feed/FeedClient.tsx` |
| `widgets/feed_video_card.dart` | `components/feed/FeedVideoCard.tsx` |
| `widgets/feed_video_player.dart` | `components/feed/FeedVideoPlayer.tsx` |
| `widgets/blurhash_canvas.dart` | `components/feed/BlurhashCanvas.tsx` |
| `widgets/comment_sheet.dart` | `components/feed/FeedCommentSheet.tsx` |

## TODO setelah scaffold

1. **Auth** — JWT cookie session. Web pakai httpOnly cookie via Next API. Mobile bisa pakai header `Cookie` manual via `cookie_jar` (sudah di pubspec) atau migrate ke Bearer token endpoint.
2. **Firebase setup** — `flutter_feed/android/app/google-services.json` + `ios/Runner/GoogleService-Info.plist` dari Firebase console.
3. **iOS NSE reuse** — copy `ios/App/NotificationServiceExtension/` dari Capacitor app (`natalo-petshop-app/`) ke project ini.
4. **Endpoint base URL** — set di `lib/api/feed_api.dart` constructor.
5. **Lottie asset** — copy file success animation ke `assets/lottie/upload_success.json` (atau ganti `LottieBuilder.network`).

## Catatan Design

- **PageView vs ListView**: web pakai CSS `snap-y snap-mandatory` + `max-w-2xl`. Flutter equivalent paling natural = `PageView.builder(scrollDirection: Axis.vertical)`. Side-effect: native momentum scroll, no JS snap-back hack needed (iOS WKWebView bug irrelevant).
- **Aspect 9/16 letterbox**: `BoxFit.contain` dengan `Container(color: Colors.black)` background.
- **Dynamic viewport height (100dvh)**: `MediaQuery.of(context).size.height` + `SafeArea` ambil insets — tidak ada keyboard offset weirdness.
- **Cinema mode**: `better_player_plus` punya `enterFullScreen()` built-in (native AVPlayer/ExoPlayer) — Wave 4 web hack (`webkitEnterFullscreen`) tidak perlu.
