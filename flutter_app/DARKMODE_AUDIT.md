# Dark Mode Coverage Audit

Generated: 2026-05-16

## Status overall

✅ **Theme infrastructure**: `NataloTheme.lightTheme` + `darkTheme` defined,
toggle via `appSettingsStore.themeMode` (light/dark/system). 12 occurrences
of `Theme.of(context).brightness` checks across 5 files (main.dart,
natalo_theme.dart, app_theme.dart, voice_search_modal.dart, settings_store.dart).

⚠️ **Hardcoded white**: 141 occurrences of `Colors.white` / `0xFFFFFFFF`
sebagai `color:` atau `backgroundColor:` di 28 screen files. Sebagian besar
adalah:
- **Card bg dalam light theme**: bg putih intentional (clean Material 3).
  Should react ke theme via `Theme.of(context).cardColor` atau
  `Theme.of(context).colorScheme.surface`.
- **Text di gradient hero**: putih intentional (kontras tinggi vs gradient
  bg). Tetap akurat di dark mode.

## Coverage per screen

### ✅ Sudah dark-mode aware (verified)
- `feed_screen.dart` — dark theme hardcoded by design (TikTok-style)
- `main.dart` — `ColoredBox` switches via `Theme.of(context).brightness`
- `theme/natalo_theme.dart` — both themes defined

### ⚠️ Potentially drift (verify visual di device)
| Screen | Hardcoded white count | Risiko |
|--------|----------------------|--------|
| `member_screen.dart` | 22 | High — hero card + tiles + menu cards |
| `home_screen.dart` | 15 | Medium — shortcut grid + section cards |
| `cart_screen.dart` | 9 | Medium — item cards + summary bar |
| `member_post_detail_screen.dart` | 6 | Low — content card |
| `register_screen.dart` | 6 | Low — form card bg (Color(0xFFEFF2F6)) |
| `login_screen.dart` | 5 | Low — form card bg |
| `member_loyalty_history_screen.dart` | 5 | Low — entry cards |
| `member_loyalty_screen.dart` | 4 | Low — tier + how-it-works cards |
| `products_screen.dart` | 5 | Low — filter pills + grid bg |
| ... | ... | ... |

### 🌑 Dark theme intentional hardcodes (DO NOT REFACTOR)
- Gradient hero cards (`_ProfileHero`, `_UploadVideoCta`, `_BalanceCard`,
  `_LoyaltyHeaderCard`) — text putih di gradient blue bg, akurat di dark mode
- Feed screen — full dark theme by design (Capacitor parity)
- Image viewer — full dark for photo focus
- Lottie animations — preserve color palette artwork

## Audit findings

### 1. Card backgrounds
Mayoritas card pakai `color: Colors.white` literal. Di dark theme, ini
muncul sebagai card putih di atas dark scaffold = jelas terlihat tapi
mungkin tidak match expectation user.

**Recommendation**: Audit visual di dark mode untuk setiap screen,
ganti hardcoded `Colors.white` ke `Theme.of(context).colorScheme.surface`
**di card bg only** (bukan text/icon). Pertahankan untuk gradient hero
text.

### 2. Text colors
Banyak `Color(0xFF111111)` (textPrimary) hardcoded. Di dark theme, ini
muncul gelap di scaffold gelap = invisible.

**Recommendation**: Ganti ke `Theme.of(context).colorScheme.onSurface`
untuk text body. Atau pakai `NataloColors.textPrimary` yang seharusnya
adaptif (tapi saat ini juga hardcoded).

### 3. Surface tints
`Color(0xFFEFF2F6)` (light gray bg) hardcoded di beberapa hero section
(login/register). Di dark mode jadi terlalu terang.

**Recommendation**: Pakai `Theme.of(context).colorScheme.surfaceContainerLow`
atau define `NataloColors.surfaceTint` light/dark variants.

## Action plan (prioritized)

### P0 — Visual smoke test di dark mode
Setiap kali toggle ke dark theme di Settings, screen-by-screen verify:
- [ ] Home — header readable, cards visible, search bar readable
- [ ] Products grid — cards visible, prices readable
- [ ] Product detail — text readable, buy button visible
- [ ] Cart — items + summary readable
- [ ] Checkout — sections readable, payment summary clear
- [ ] Account / Member — hero card kontras OK, menu grid visible
- [ ] Loyalty + Loyalty History — gradient hero + entry cards
- [ ] Orders list + detail — status pills readable
- [ ] Voucher — empty state + card
- [ ] Login + Register — form readable

### P1 — Code fixes per priority screens
Refactor 3 high-risk files dari audit:
1. `member_screen.dart` (22 hardcodes)
2. `home_screen.dart` (15 hardcodes)
3. `cart_screen.dart` (9 hardcodes)

Pattern:
```dart
// Before
decoration: BoxDecoration(color: Colors.white, ...)

// After (dark-aware)
decoration: BoxDecoration(
  color: Theme.of(context).colorScheme.surface,
  ...
)
```

### P2 — Extend NataloColors with dark variants
Tambah ke `lib/theme/natalo_colors.dart`:
```dart
// Surfaces (dark variants)
static const Color backgroundDark = Color(0xFF0A0F1A);
static const Color surfaceDark = Color(0xFF1A1F2E);
static const Color borderDark = Color(0xFF2A2F3E);

// Text (dark variants)
static const Color textPrimaryDark = Color(0xFFF1F5F9);
static const Color textSecondaryDark = Color(0xFF94A3B8);
```

Lalu update `NataloTheme.darkTheme` consume tokens ini.

## Estimate effort

- **P0 visual audit**: 1-2 jam manual testing
- **P1 code fixes**: ~4 jam refactor 3 files
- **P2 token expansion**: ~1 jam (additive, low risk)

Total: ~7 jam untuk full dark mode coverage parity.

## Test command

```bash
# Toggle dark mode di app: Settings → Theme → Gelap
flutter run --release

# Atau test via system setting:
adb shell "cmd uimode night yes"   # force dark di Android
adb shell "cmd uimode night no"    # back to light
```

## References
- Material 3 Dark Theme: https://m3.material.io/styles/color/dark-theme/overview
- Flutter ThemeData: https://api.flutter.dev/flutter/material/ThemeData-class.html
