# Natalo Petshop — Flutter Native App

Native Android/iOS app untuk Natalo Petshop, dibangun dengan Flutter sebagai
parallel native version dari Capacitor PWA di `natalopetshop.com`. Sharing
backend API yang sama dengan PWA, dengan native superpowers tambahan
(biometric, push, share, quick actions, home widget, dll).

## Quick start

```bash
flutter pub get
flutter run                                    # debug mode di emulator
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000   # local backend
flutter run --release                          # release mode (test perf)
```

**API base URL conventions:**
- `http://10.0.2.2:3000` → Android emulator → host PC localhost
- `http://localhost:3000` → iOS simulator
- `http://LAN-IP:3000` → physical device on same Wi-Fi

## Build

```bash
flutter build apk --release                    # Universal APK (~105 MB)
flutter build apk --release --split-per-abi    # Per-arch APK (~60 MB arm64)
flutter build appbundle --release              # AAB untuk Play Store
flutter build ios --release                    # iOS (butuh Mac + Xcode)
```

## Project structure

```
lib/
├── main.dart                  # Entry point, route table, theme setup
├── theme/
│   ├── natalo_colors.dart     # Design tokens (single source of truth)
│   ├── natalo_theme.dart      # Material 3 ThemeData
│   └── app_theme.dart         # Legacy AppColors (alias ke NataloColors)
├── config/
│   └── api_config.dart        # Base URL resolution + fallback
├── models/                    # Plain data classes (Product, MemberProfile, ...)
├── services/                  # API clients (one per domain)
│   ├── api_client.dart        # HTTP wrapper + cookie session + 401 handler
│   ├── auth_service.dart      # Login/register/me/logout
│   ├── member_service.dart    # Profile, orders, vouchers
│   ├── feed_service.dart      # TikTok-style video feed
│   ├── biometric_service.dart # local_auth wrapper
│   └── ...
├── state/                     # ChangeNotifier stores (lightweight reactive)
│   ├── cart_store.dart
│   ├── member_store.dart
│   ├── favorite_store.dart
│   └── settings_store.dart
├── screens/                   # Top-level pages
├── widgets/                   # Reusable UI components
└── utils/                     # Pure helpers (formatters, haptics, ...)

assets/
├── brand/logo.png             # Wordmark horizontal "NL Natalo PETSHOP"
├── native/icon-only.png       # Square iOS-style icon (256×256, hero usage)
├── native/icon-foreground.png # Android adaptive icon foreground
├── native/splash.png          # Launch screen
├── fonts/NunitoSans*.ttf      # Brand typeface
├── brands/                    # Brand logos (Purina, Royal Canin, dll)
├── banners/                   # Promo banners
├── products/                  # Product photo fallbacks
└── lottie/                    # Lottie animations (empty box, success, dll)
```

## Architecture

**State management**: `ChangeNotifier` + `AnimatedBuilder`. Lightweight,
no Provider/Riverpod/Bloc — sesuai scope app yang relatively simple.

**Routing**: Named routes via `Navigator.pushNamed`. Route table di `main.dart`.

**Theme**: Material 3 dengan `NataloTheme.lightTheme` + `darkTheme`. Toggle
via `appSettingsStore.themeMode` (light/dark/system).

**API**: `apiClient` singleton dengan cookie-based session, fallback URL
resolution (Capacitor parity), 401 auto-clear + onUnauthorized callback.
Dev-only request logging via `dart:developer` (visible in DevTools Network).

**Native features yang PWA tidak bisa**:
- **Biometric auth** (`local_auth`) — fingerprint/Face ID untuk auto-login
- **Push notification** (`firebase_messaging` + `flutter_local_notifications`)
- **Share sheet** (`share_plus`) — share product/order ke WhatsApp dkk
- **Voice search** (`speech_to_text`) — partial result live transcript
- **Barcode scan** (`mobile_scanner`) — search produk by SKU/EAN
- **Quick actions** (`quick_actions`) — long-press app icon shortcuts
- **Home widget** (`home_widget`) — cart count di home screen launcher
- **Native video player** (`video_player`) — hardware-accelerated reels feed
- **In-app review** (`in_app_review`) — Play Store rating prompt
- **Deep link** (`app_links`) — handle natalopetshop.com URLs
- **Image cache** (`cached_network_image`) — instant load on repeat visit
- **In-app browser** (`flutter_inappwebview`) — for static pages (Bantuan, ToS)

## Code health

```bash
flutter analyze         # Lint + type check
flutter test            # Widget + unit tests
```

Target: 0 issues, 0 warnings.

## Manual smoke test checklist

Sebelum tagging release, jalankan checklist berikut di physical device:

### Auth
- [ ] Login dengan email + password sukses → redirect ke home
- [ ] Login dengan biometric (kalau enabled) sukses
- [ ] Lupa password → input email → request OTP
- [ ] Register dengan info banner OTP visible + manfaat box di bawah
- [ ] Logout dari Account screen → dialog konfirmasi → back to guest mode

### Home + Catalog
- [ ] Logo box 42×42 di header tampilkan NL icon (bukan wordmark crop)
- [ ] Search bar pill → tap → open full-screen search sheet
- [ ] Banner carousel auto-rotate, swipeable
- [ ] Shortcut grid 8 items (4 pet + 4 commerce)
- [ ] Tap kategori populer → buka produk list filtered

### Cart + Checkout
- [ ] Add product → snackbar "Berhasil tambah" + cart icon badge update
- [ ] Cart: multi-select dengan checkbox, qty stepper, remove
- [ ] Cart: voucher apply hybrid (API + static fallback)
- [ ] Checkout: protection toggle + order note section
- [ ] Buy Now dari product detail → langsung ke checkout (skip cart)
- [ ] Order success overlay + in-app review prompt

### Account
- [ ] Hero gradient blue card dengan "Member Resmi" pill + avatar + 2 stats
- [ ] Tukar Poin card → `/member/loyalty`
- [ ] Riwayat Poin card → in-app browser ke web history
- [ ] Pesanan Saya 4 status circles + red badge count untuk Dikirim/Selesai
- [ ] Menu Transaksi 2×2 grid (Pesanan/Voucher/Wishlist/Review/Alamat/...)
- [ ] Upload Video CTA → push ke Feed dengan auto-trigger upload action

### Feed
- [ ] Vertical PageView swipe video
- [ ] Tap heart → like count++
- [ ] Tap share → native share sheet
- [ ] Postingan Saya → 3-dots di AppBar → "Aksi postingan" bottom sheet
- [ ] Aksi sheet → "Edit caption / tag" → open web | "Hapus" → konfirmasi

### Detail Pengumuman
- [ ] Notifikasi screen → tap "Lihat Detail" pada item pengumuman
- [ ] Card megaphone + decorative dots + meta + info box + paw divider
- [ ] "Mengerti" button → back to notifications

### Voucher
- [ ] Empty state: illustration + CTA "Tukar Poin Sekarang"
- [ ] Card list: tap "Pakai" → snackbar "Kode disalin" + action "Ke Keranjang"

### Profile
- [ ] Edit Profile bottom sheet → fields validation (nama min 2, HP format)
- [ ] Save → snackbar success + hero update

### Address
- [ ] Empty state card with "Tambah Alamat" button
- [ ] Form sheet: nama, HP, area picker (Biteship), alamat, label
- [ ] Set primary toggle works

### Order detail
- [ ] Share icon di AppBar → native share sheet dengan summary
- [ ] Timeline 4-stage dengan animated pulse di stage aktif
- [ ] "Beli lagi" button di order list works (add ke cart)

### Native superpowers
- [ ] Long-press app icon di launcher → 4 shortcuts (Cart/Wishlist/Pesanan/Tukar)
- [ ] Search bar → tap mic → voice transcript live
- [ ] Products → tap barcode icon → scan EAN/SKU → search auto
- [ ] Setting → enable biometric → next launch → fingerprint prompt
- [ ] Push notif test (kirim dari Firebase Console)
- [ ] Theme toggle Light/Dark/Auto → semua screen consistent

### Performance
- [ ] Scroll cart/checkout/loyalty smooth tanpa jank
- [ ] Image grid produk tidak flicker saat scroll
- [ ] Hero animation produk card → detail smooth (rounded corner morph)
- [ ] First launch → splash → home dalam <2 detik

## Dev tips

- **DevTools Network tab**: Real-time API request log via `dart:developer` —
  cek `name: 'api'` filter.
- **Hot reload**: Save file → app auto-update tanpa hilang state.
- **Hot restart** (`R` di terminal): Reset state, semua singleton re-init.
- **Read-only mode**: Toggle dari Account → Settings → Mode Server saat
  testing di production backend supaya tidak menulis data palsu.
- **Skip onboarding**: First launch otomatis tampil onboarding. Untuk reset,
  uninstall + reinstall, atau clear SharedPreferences.

## Konteks proyek

App ini adalah parallel native version dari Capacitor PWA. Backend Next.js
+ Prisma + PostgreSQL tetap sama. Tujuan native version:

1. **Performance**: Better frame rate di entry-level Android (vs WebView)
2. **Native features**: Hardware access (biometric, camera ML Kit, etc)
3. **Distribution**: Play Store + AppStore visibility
4. **Engagement**: Push notifications + home widget + quick actions
5. **Reliability**: Offline cache + better error recovery

## License

Proprietary — Natalo Petshop © 2026
