# Popup Pembuka Aplikasi — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menampilkan satu popup promo/pengumuman "Hybrid" di atas Beranda tiap cold start untuk member, dengan konten hardcoded yang mudah di-upgrade ke API.

**Architecture:** Sebuah gate stateful (`LaunchPromoGate`) disisipkan di rantai `MaterialApp.builder` `main.dart`. Setelah frame pertama, gate mengumpulkan kondisi dari singleton yang sudah ada, memanggil fungsi keputusan murni `launchPromoShouldShow(...)`, lalu menampilkan `LaunchPromoDialog` lewat `showGeneralDialog` pada root navigator. Konten datang dari satu fungsi `activeLaunchPopup()` (sekat bersih → nanti diganti fetch API).

**Tech Stack:** Flutter/Dart, `flutter_test`, `shared_preferences` (mock di test), Firebase Analytics (via wrapper `AppAnalytics`), `cached_network_image`/`shimmer` (via `AppProductImage`).

**Spec:** `docs/superpowers/specs/2026-07-07-launch-promo-popup-design.md`

## Global Constraints

- Package name untuk import test: `natalo_petshop_flutter` (mis. `package:natalo_petshop_flutter/widgets/launch_promo_gate.dart`).
- Semua perintah dijalankan dari direktori `flutter_app/`.
- Frekuensi = **tiap cold start**: TIDAK ada flag persist ke `SharedPreferences`. Guard hanya penanda in-memory per mount.
- Popup **member-only**; skip juga saat: dibuka via deep-link/push, belum lewat onboarding, atau offline.
- Warna & tipografi dari `NataloColors`/`NataloTextStyles`. Nada: promo = `#E11D48` (soft `#FFEEF2`), pengumuman = `#20B26B` (soft `#E8F8F0`) — paritas dengan `announcement_detail_screen.dart`.
- Copy berbahasa Indonesia, sentence case.
- **Aturan test (WAJIB):** jangan pakai `pumpAndSettle` bila `AppProductImage` merender gambar network — shimmer-nya tak pernah settle. Pakai bounded pump loop (contoh: `for (var i=0;i<20;i++) await tester.pump(const Duration(milliseconds:50));`). Test dialog memakai `imageUrl: null` agar bebas shimmer.
- TDD: tiap task tulis test dulu, lihat gagal, implement minimal, lihat lulus, commit.
- Jalankan **file test spesifik** (bukan `flutter test` penuh) — suite penuh punya 2 golden failure pra-ada di Windows (natalo_colors, status_pill) yang tidak relevan.

---

### Task 1: Content layer — model + provider hardcoded

**Files:**
- Create: `flutter_app/lib/models/launch_popup_campaign.dart`
- Create: `flutter_app/lib/config/launch_popup_campaigns.dart`
- Test: `flutter_app/test/launch_popup_campaign_test.dart`

**Interfaces:**
- Produces:
  - `enum LaunchPopupTone { promo, announcement }`
  - `class LaunchPopupCampaign` — const ctor dengan field: `String id`, `LaunchPopupTone tone`, `String? imageUrl`, `String title`, `String body`, `String categoryLabel`, `String? ctaLabel`, `String? ctaHref`, `String dismissLabel` (default `'Nanti saja'`); getter `bool get hasImage`, `bool get hasCta`.
  - `LaunchPopupCampaign? activeLaunchPopup()` — kembalikan campaign aktif atau null.

- [ ] **Step 1: Write the failing test**

```dart
// flutter_app/test/launch_popup_campaign_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/config/launch_popup_campaigns.dart';
import 'package:natalo_petshop_flutter/models/launch_popup_campaign.dart';

void main() {
  test('activeLaunchPopup mengembalikan campaign promo dengan CTA', () {
    final c = activeLaunchPopup();
    expect(c, isNotNull);
    expect(c!.tone, LaunchPopupTone.promo);
    expect(c.title, isNotEmpty);
    expect(c.hasCta, isTrue);
    expect(c.ctaHref, startsWith('/produk/'));
  });

  test('hasImage false saat imageUrl null', () {
    const c = LaunchPopupCampaign(
      id: 'x', tone: LaunchPopupTone.announcement,
      title: 't', body: 'b', categoryLabel: 'Pengumuman',
    );
    expect(c.hasImage, isFalse);
    expect(c.hasCta, isFalse);
    expect(c.dismissLabel, 'Nanti saja');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/launch_popup_campaign_test.dart`
Expected: FAIL — `Target of URI doesn't exist` / tipe belum ada.

- [ ] **Step 3: Write the model**

```dart
// flutter_app/lib/models/launch_popup_campaign.dart

/// Nada visual popup — menentukan warna chip/aksen. Merah untuk promo,
/// hijau untuk pengumuman (paritas dengan announcement_detail_screen.dart).
enum LaunchPopupTone { promo, announcement }

/// Satu konten popup pembuka aplikasi. Model murni — sumber datanya
/// (hardcoded sekarang, API nanti) tidak tercermin di sini.
class LaunchPopupCampaign {
  final String id;
  final LaunchPopupTone tone;

  /// Hero opsional. Boleh asset path ('assets/...') ATAU URL http.
  /// null / kosong = mode teks (tanpa gambar).
  final String? imageUrl;
  final String title;
  final String body;
  final String categoryLabel;

  /// Label tombol utama. null/kosong = sembunyikan tombol utama (mode info).
  final String? ctaLabel;

  /// Target tombol utama, mis. '/produk/<slug>' — diteruskan ke
  /// deepLinkService.handleExternalUri().
  final String? ctaHref;
  final String dismissLabel;

  const LaunchPopupCampaign({
    required this.id,
    required this.tone,
    this.imageUrl,
    required this.title,
    required this.body,
    required this.categoryLabel,
    this.ctaLabel,
    this.ctaHref,
    this.dismissLabel = 'Nanti saja',
  });

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
  bool get hasCta =>
      ctaLabel != null &&
      ctaLabel!.isNotEmpty &&
      ctaHref != null &&
      ctaHref!.isNotEmpty;
}
```

- [ ] **Step 4: Write the provider (sekat bersih)**

```dart
// flutter_app/lib/config/launch_popup_campaigns.dart
import '../models/launch_popup_campaign.dart';

/// Sumber konten popup pembuka — V1 HARDCODED.
///
/// Untuk upgrade ke admin-managed: ganti isi fungsi ini agar membaca hasil
/// fetch API (lihat spec §11). UI, gate, dan logika skip tidak berubah.
/// Set `_campaign` ke null untuk mematikan popup tanpa hapus kode.
LaunchPopupCampaign? activeLaunchPopup() => _campaign;

const LaunchPopupCampaign? _campaign = LaunchPopupCampaign(
  id: 'promo-juli-2026',
  tone: LaunchPopupTone.promo,
  imageUrl: null, // isi 'assets/...' atau URL saat aset poster siap
  title: 'Diskon 30% khusus member',
  body: 'Hemat 30% untuk vitamin dan makanan. Berlaku sampai 13 Juli.',
  categoryLabel: 'Promo',
  ctaLabel: 'Lihat produk',
  // Pastikan slug ini cocok dengan produk nyata sebelum rilis.
  ctaHref: '/produk/royal-canin-kitten',
  dismissLabel: 'Nanti saja',
);
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/launch_popup_campaign_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/models/launch_popup_campaign.dart flutter_app/lib/config/launch_popup_campaigns.dart flutter_app/test/launch_popup_campaign_test.dart
git commit -m "feat(popup): model + provider hardcoded konten popup pembuka"
```

---

### Task 2: Decision logic (pure function)

**Files:**
- Create: `flutter_app/lib/widgets/launch_promo_decision.dart`
- Test: `flutter_app/test/launch_promo_decision_test.dart`

**Interfaces:**
- Produces: `bool launchPromoShouldShow({required bool hasCampaign, required bool isLoggedIn, required bool hasSeenOnboarding, required bool isOnline, required bool launchedExternally, required bool routeStackedAboveHome})` — true hanya bila semua syarat positif terpenuhi dan tak ada kondisi skip.

- [ ] **Step 1: Write the failing test**

```dart
// flutter_app/test/launch_promo_decision_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/launch_promo_decision.dart';

/// Semua kondisi lolos kecuali override yang dikirim.
bool show({
  bool hasCampaign = true,
  bool isLoggedIn = true,
  bool hasSeenOnboarding = true,
  bool isOnline = true,
  bool launchedExternally = false,
  bool routeStackedAboveHome = false,
}) =>
    launchPromoShouldShow(
      hasCampaign: hasCampaign,
      isLoggedIn: isLoggedIn,
      hasSeenOnboarding: hasSeenOnboarding,
      isOnline: isOnline,
      launchedExternally: launchedExternally,
      routeStackedAboveHome: routeStackedAboveHome,
    );

void main() {
  test('tampil saat semua kondisi ideal', () {
    expect(show(), isTrue);
  });
  test('skip tanpa campaign', () => expect(show(hasCampaign: false), isFalse));
  test('skip belum login', () => expect(show(isLoggedIn: false), isFalse));
  test('skip belum onboarding', () => expect(show(hasSeenOnboarding: false), isFalse));
  test('skip offline', () => expect(show(isOnline: false), isFalse));
  test('skip dibuka dari deep-link/push', () => expect(show(launchedExternally: true), isFalse));
  test('skip bukan di root Home', () => expect(show(routeStackedAboveHome: true), isFalse));
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/launch_promo_decision_test.dart`
Expected: FAIL — fungsi belum ada.

- [ ] **Step 3: Write the implementation**

```dart
// flutter_app/lib/widgets/launch_promo_decision.dart

/// Keputusan MURNI apakah popup pembuka boleh tampil. Sengaja dipisah dari
/// widget supaya bisa diuji cepat & deterministik tanpa render (menghindari
/// shimmer AppProductImage yang tak pernah settle di test).
bool launchPromoShouldShow({
  required bool hasCampaign,
  required bool isLoggedIn,
  required bool hasSeenOnboarding,
  required bool isOnline,
  required bool launchedExternally,
  required bool routeStackedAboveHome,
}) {
  if (!hasCampaign) return false;
  if (!isLoggedIn) return false; // member-only
  if (!hasSeenOnboarding) return false;
  if (!isOnline) return false;
  if (launchedExternally) return false; // jangan tutupi tujuan deep-link/push
  if (routeStackedAboveHome) return false; // hanya saat masih di root Home
  return true;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/launch_promo_decision_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/launch_promo_decision.dart flutter_app/test/launch_promo_decision_test.dart
git commit -m "feat(popup): fungsi keputusan murni launchPromoShouldShow"
```

---

### Task 3: Dialog UI (`LaunchPromoDialog` + `showLaunchPromoDialog`)

**Files:**
- Create: `flutter_app/lib/widgets/launch_promo_dialog.dart`
- Test: `flutter_app/test/launch_promo_dialog_test.dart`

**Interfaces:**
- Consumes: `LaunchPopupCampaign`, `LaunchPopupTone` (Task 1); `NataloColors`; `AppProductImage`; `AppHaptics`; `MotionPrefs`.
- Produces:
  - `enum LaunchPromoOutcome { cta, dismiss }`
  - `Future<LaunchPromoOutcome> showLaunchPromoDialog(BuildContext context, {required LaunchPopupCampaign campaign})` — barrier/back → `dismiss`.
  - `class LaunchPromoDialog extends StatelessWidget` — konten kartu. Tombol berkunci key `ValueKey('launch-popup-cta')` & `ValueKey('launch-popup-dismiss')`, tombol X `ValueKey('launch-popup-close')`.

- [ ] **Step 1: Write the failing test**

```dart
// flutter_app/test/launch_promo_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:natalo_petshop_flutter/models/launch_popup_campaign.dart';
import 'package:natalo_petshop_flutter/widgets/launch_promo_dialog.dart';

const _promo = LaunchPopupCampaign(
  id: 'p1', tone: LaunchPopupTone.promo, imageUrl: null,
  title: 'Diskon 30% khusus member',
  body: 'Hemat 30% untuk vitamin dan makanan.',
  categoryLabel: 'Promo', ctaLabel: 'Lihat produk',
  ctaHref: '/produk/abc', dismissLabel: 'Nanti saja',
);

const _infoOnly = LaunchPopupCampaign(
  id: 'a1', tone: LaunchPopupTone.announcement, imageUrl: null,
  title: 'Libur Idul Adha', body: 'Toko tutup 6-7 Juli.',
  categoryLabel: 'Pengumuman', dismissLabel: 'Mengerti',
);

Future<LaunchPromoOutcome?> _open(WidgetTester tester, LaunchPopupCampaign c) async {
  LaunchPromoOutcome? outcome;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async =>
                outcome = await showLaunchPromoDialog(context, campaign: c),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
  return outcome;
}

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('menampilkan judul, body, dan kedua tombol', (tester) async {
    await _open(tester, _promo);
    expect(find.text('Diskon 30% khusus member'), findsOneWidget);
    expect(find.text('Hemat 30% untuk vitamin dan makanan.'), findsOneWidget);
    expect(find.byKey(const ValueKey('launch-popup-cta')), findsOneWidget);
    expect(find.byKey(const ValueKey('launch-popup-dismiss')), findsOneWidget);
  });

  testWidgets('tap CTA mengembalikan outcome cta', (tester) async {
    final future = _open(tester, _promo);
    await tester.tap(find.byKey(const ValueKey('launch-popup-cta')));
    await _drain(tester);
    expect(await future, LaunchPromoOutcome.cta);
  });

  testWidgets('tap dismiss mengembalikan outcome dismiss', (tester) async {
    final future = _open(tester, _promo);
    await tester.tap(find.byKey(const ValueKey('launch-popup-dismiss')));
    await _drain(tester);
    expect(await future, LaunchPromoOutcome.dismiss);
  });

  testWidgets('mode info: tombol CTA disembunyikan', (tester) async {
    await _open(tester, _infoOnly);
    expect(find.byKey(const ValueKey('launch-popup-cta')), findsNothing);
    expect(find.byKey(const ValueKey('launch-popup-dismiss')), findsOneWidget);
    expect(find.text('Mengerti'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/launch_promo_dialog_test.dart`
Expected: FAIL — `showLaunchPromoDialog` belum ada.

- [ ] **Step 3: Write the implementation**

```dart
// flutter_app/lib/widgets/launch_promo_dialog.dart
import 'package:flutter/material.dart';

import '../models/launch_popup_campaign.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';
import '../utils/motion_prefs.dart';
import 'app_product_image.dart';

/// Hasil interaksi popup pembuka.
enum LaunchPromoOutcome { cta, dismiss }

class _Tone {
  final Color color;
  final Color softBg;
  const _Tone(this.color, this.softBg);

  /// Paritas dengan _AnnouncementTone di announcement_detail_screen.dart.
  factory _Tone.of(LaunchPopupTone tone) => tone == LaunchPopupTone.promo
      ? const _Tone(Color(0xFFE11D48), Color(0xFFFFEEF2))
      : const _Tone(Color(0xFF20B26B), Color(0xFFE8F8F0));
}

/// Tampilkan popup pembuka di atas layar sekarang. Return outcome:
/// [LaunchPromoOutcome.cta] bila user tap tombol utama; selain itu
/// (tombol dismiss / X / tap area gelap / back Android) → dismiss.
Future<LaunchPromoOutcome> showLaunchPromoDialog(
  BuildContext context, {
  required LaunchPopupCampaign campaign,
}) async {
  final reduce = MotionPrefs.shouldReduce(context);
  final result = await showGeneralDialog<LaunchPromoOutcome>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Tutup',
    barrierColor: const Color(0x8C0F172A), // rgba(15,23,42,.55)
    transitionDuration:
        Duration(milliseconds: reduce ? 120 : 240),
    pageBuilder: (context, _, __) => LaunchPromoDialog(campaign: campaign),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      if (reduce) return FadeTransition(opacity: curved, child: child);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
  return result ?? LaunchPromoOutcome.dismiss;
}

class LaunchPromoDialog extends StatelessWidget {
  final LaunchPopupCampaign campaign;
  const LaunchPromoDialog({super.key, required this.campaign});

  void _close(BuildContext context, LaunchPromoOutcome outcome) {
    AppHaptics.tap();
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final tone = _Tone.of(campaign.tone);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Material(
            color: NataloColors.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (campaign.hasImage)
                  Stack(
                    children: [
                      AppProductImage(
                        imageUrl: campaign.imageUrl,
                        width: double.infinity,
                        height: 172,
                        borderRadius: BorderRadius.zero,
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: _CategoryChip(label: campaign.categoryLabel, tone: tone),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: _CloseButton(
                          onTap: () => _close(context, LaunchPromoOutcome.dismiss),
                        ),
                      ),
                    ],
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 10, 0),
                    child: Row(
                      children: [
                        _CategoryChip(label: campaign.categoryLabel, tone: tone),
                        const Spacer(),
                        _CloseButton(
                          onTap: () => _close(context, LaunchPromoOutcome.dismiss),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        campaign.title,
                        style: const TextStyle(
                          color: NataloColors.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        campaign.body,
                        style: const TextStyle(
                          color: NataloColors.textSecondary,
                          fontSize: 14,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _Actions(
                        campaign: campaign,
                        onCta: () => _close(context, LaunchPromoOutcome.cta),
                        onDismiss: () => _close(context, LaunchPromoOutcome.dismiss),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final LaunchPopupCampaign campaign;
  final VoidCallback onCta;
  final VoidCallback onDismiss;
  const _Actions({
    required this.campaign,
    required this.onCta,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final dismiss = _PillButton(
      key: const ValueKey('launch-popup-dismiss'),
      label: campaign.dismissLabel,
      filled: false,
      onTap: onDismiss,
    );
    if (!campaign.hasCta) {
      return SizedBox(width: double.infinity, child: dismiss);
    }
    return Row(
      children: [
        Expanded(child: dismiss),
        const SizedBox(width: 10),
        Expanded(
          flex: 3,
          child: _PillButton(
            key: const ValueKey('launch-popup-cta'),
            label: campaign.ctaLabel!,
            filled: true,
            onTap: onCta,
          ),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _PillButton({
    super.key,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Material(
        color: filled ? NataloColors.primary : NataloColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: filled ? Colors.white : NataloColors.primary,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final _Tone tone;
  const _CategoryChip({required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tone.color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('launch-popup-close'),
      color: NataloColors.surfaceElevated,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: NataloColors.border),
          ),
          child: const Icon(Icons.close_rounded,
              size: 18, color: NataloColors.textPrimary),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/launch_promo_dialog_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/launch_promo_dialog.dart flutter_app/test/launch_promo_dialog_test.dart
git commit -m "feat(popup): dialog Hybrid launch promo + showLaunchPromoDialog"
```

---

### Task 4: Flag launch-intent pada deep-link & push service

**Files:**
- Modify: `flutter_app/lib/services/deep_link_service.dart`
- Modify: `flutter_app/lib/services/push_notification_service.dart`
- Test: `flutter_app/test/launch_intent_flags_test.dart`

**Interfaces:**
- Produces: `bool deepLinkService.launchedFromDeepLink` (default false), `bool pushNotificationService.launchedFromColdPush` (default false). Di-set true saat cold start dipicu link/notif.

- [ ] **Step 1: Write the failing test**

```dart
// flutter_app/test/launch_intent_flags_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/services/deep_link_service.dart';
import 'package:natalo_petshop_flutter/services/push_notification_service.dart';

void main() {
  test('flag deep-link default false sebelum ada launch link', () {
    expect(deepLinkService.launchedFromDeepLink, isFalse);
  });
  test('flag cold push default false sebelum ada launch notif', () {
    expect(pushNotificationService.launchedFromColdPush, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/launch_intent_flags_test.dart`
Expected: FAIL — getter `launchedFromDeepLink` / `launchedFromColdPush` belum ada.

- [ ] **Step 3a: Tambah flag di `deep_link_service.dart`**

Di kelas `DeepLinkService`, tambah field publik (dekat `bool _initialized = false;` di sekitar baris 30):

```dart
  /// True bila app cold-start dipicu tap deep-link (bukan buka app biasa).
  /// Dibaca LaunchPromoGate untuk skip popup agar tidak menutupi tujuan link.
  bool launchedFromDeepLink = false;
```

Lalu di `initialize()`, ubah penanganan initial link (sekitar baris 39):

```dart
      // Initial link — kalau app dibuka via tap link (cold start).
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        launchedFromDeepLink = true;
        _handle(initial);
      }
```

- [ ] **Step 3b: Tambah flag di `push_notification_service.dart`**

Di kelas `PushNotificationService`, tambah field publik (dekat `bool _initialized = false;` di sekitar baris 69):

```dart
  /// True bila app cold-start dipicu tap notifikasi (app tadinya terminated).
  /// Dibaca LaunchPromoGate untuk skip popup agar tidak menutupi tujuan notif.
  bool launchedFromColdPush = false;
```

Lalu di `initialize()`, ubah blok `getInitialMessage()` (sekitar baris 192):

```dart
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        launchedFromColdPush = true;
        // Delay supaya navigator ready setelah app launch.
        Future.delayed(const Duration(milliseconds: 800), () {
          _handleMessage(initial);
        });
      }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/launch_intent_flags_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/services/deep_link_service.dart flutter_app/lib/services/push_notification_service.dart flutter_app/test/launch_intent_flags_test.dart
git commit -m "feat(popup): expose flag launch-intent deep-link & cold push"
```

---

### Task 5: Gate widget (`LaunchPromoGate`)

**Files:**
- Create: `flutter_app/lib/widgets/launch_promo_gate.dart`
- Test: `flutter_app/test/launch_promo_gate_test.dart`

**Interfaces:**
- Consumes: `activeLaunchPopup` (Task 1), `launchPromoShouldShow` (Task 2), `showLaunchPromoDialog` + `LaunchPromoOutcome` (Task 3), flag launch-intent (Task 4), `memberStore`, `connectivityService`, `deepLinkService`, `OnboardingScreen.hasSeen`, `AppAnalytics.logEvent`.
- Produces: `class LaunchPromoGate extends StatefulWidget` — ctor `const LaunchPromoGate({required Widget child, required GlobalKey<NavigatorState> navigatorKey, ...test seams..., Duration settleDelay = const Duration(milliseconds: 900)})`. `build` mengembalikan `child` apa adanya. Test seams (semua opsional, null → implementasi produksi): `campaignProvider`, `ensureAuthReady`, `isLoggedIn`, `hasSeenOnboarding`, `isOnline`, `launchedExternally`, `routeStackedAboveHome`, `showDialogFn`, `openHref`, `logEvent`.

- [ ] **Step 1: Write the failing test**

```dart
// flutter_app/test/launch_promo_gate_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:natalo_petshop_flutter/models/launch_popup_campaign.dart';
import 'package:natalo_petshop_flutter/widgets/launch_promo_dialog.dart';
import 'package:natalo_petshop_flutter/widgets/launch_promo_gate.dart';

const _campaign = LaunchPopupCampaign(
  id: 'p1', tone: LaunchPopupTone.promo, imageUrl: null,
  title: 'Judul', body: 'Body', categoryLabel: 'Promo',
  ctaLabel: 'Lihat produk', ctaHref: '/produk/abc',
);

Future<void> _pump(
  WidgetTester tester, {
  required bool isLoggedIn,
  required LaunchPromoOutcome dialogReturns,
  required List<String> events,
  required List<String> openedHrefs,
  required List<int> shownCounter,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: LaunchPromoGate(
      navigatorKey: GlobalKey<NavigatorState>(),
      campaignProvider: () => _campaign,
      ensureAuthReady: () async {},
      isLoggedIn: () => isLoggedIn,
      hasSeenOnboarding: () async => true,
      isOnline: () => true,
      launchedExternally: () => false,
      routeStackedAboveHome: () => false,
      settleDelay: Duration.zero,
      showDialogFn: (ctx, c) async {
        shownCounter[0]++;
        return dialogReturns;
      },
      openHref: (href) async => openedHrefs.add(href),
      logEvent: (name, params) async => events.add(name),
      child: const Scaffold(body: Text('HOME')),
    ),
  ));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tampilkan dialog + buka href saat semua lolos & CTA', (tester) async {
    final events = <String>[]; final hrefs = <String>[]; final shown = [0];
    await _pump(tester,
        isLoggedIn: true, dialogReturns: LaunchPromoOutcome.cta,
        events: events, openedHrefs: hrefs, shownCounter: shown);
    expect(shown[0], 1);
    expect(hrefs, ['/produk/abc']);
    expect(events, containsAllInOrder(['launch_popup_shown', 'launch_popup_cta_click']));
  });

  testWidgets('dismiss: log dismiss, tidak buka href', (tester) async {
    final events = <String>[]; final hrefs = <String>[]; final shown = [0];
    await _pump(tester,
        isLoggedIn: true, dialogReturns: LaunchPromoOutcome.dismiss,
        events: events, openedHrefs: hrefs, shownCounter: shown);
    expect(shown[0], 1);
    expect(hrefs, isEmpty);
    expect(events, containsAllInOrder(['launch_popup_shown', 'launch_popup_dismiss']));
  });

  testWidgets('skip total saat belum login', (tester) async {
    final events = <String>[]; final hrefs = <String>[]; final shown = [0];
    await _pump(tester,
        isLoggedIn: false, dialogReturns: LaunchPromoOutcome.dismiss,
        events: events, openedHrefs: hrefs, shownCounter: shown);
    expect(shown[0], 0);
    expect(events, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd flutter_app && flutter test test/launch_promo_gate_test.dart`
Expected: FAIL — `LaunchPromoGate` belum ada.

- [ ] **Step 3: Write the implementation**

```dart
// flutter_app/lib/widgets/launch_promo_gate.dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../config/launch_popup_campaigns.dart';
import '../models/launch_popup_campaign.dart';
import '../screens/onboarding_screen.dart';
import '../services/app_analytics.dart';
import '../services/connectivity_service.dart';
import '../services/deep_link_service.dart';
import '../services/push_notification_service.dart';
import '../state/member_store.dart';
import 'launch_promo_decision.dart';
import 'launch_promo_dialog.dart';

/// Gate di rantai MaterialApp.builder: setelah frame pertama, evaluasi
/// kondisi (sekali per mount = sekali per cold start) lalu tampilkan popup
/// pembuka via showGeneralDialog pada root navigator.
///
/// Semua seam (campaignProvider, isLoggedIn, dll) opsional — default null
/// menunjuk implementasi produksi (singleton). Test menyuntik fake supaya
/// hermetik & bebas shimmer/navigator nyata.
class LaunchPromoGate extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  final LaunchPopupCampaign? Function()? campaignProvider;
  final Future<void> Function()? ensureAuthReady;
  final bool Function()? isLoggedIn;
  final Future<bool> Function()? hasSeenOnboarding;
  final bool Function()? isOnline;
  final bool Function()? launchedExternally;
  final bool Function()? routeStackedAboveHome;
  final Future<LaunchPromoOutcome> Function(BuildContext, LaunchPopupCampaign)?
      showDialogFn;
  final Future<void> Function(String href)? openHref;
  final Future<void> Function(String, Map<String, Object>)? logEvent;
  final Duration settleDelay;

  const LaunchPromoGate({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.campaignProvider,
    this.ensureAuthReady,
    this.isLoggedIn,
    this.hasSeenOnboarding,
    this.isOnline,
    this.launchedExternally,
    this.routeStackedAboveHome,
    this.showDialogFn,
    this.openHref,
    this.logEvent,
    this.settleDelay = const Duration(milliseconds: 900),
  });

  @override
  State<LaunchPromoGate> createState() => _LaunchPromoGateState();
}

class _LaunchPromoGateState extends State<LaunchPromoGate> {
  bool _ran = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  // ── seam resolvers (fake bila di-inject, else produksi) ──
  LaunchPopupCampaign? _campaign() =>
      (widget.campaignProvider ?? activeLaunchPopup)();

  Future<void> _ensureAuthReady() =>
      (widget.ensureAuthReady ?? _realEnsureAuthReady)();

  bool _isLoggedIn() => (widget.isLoggedIn ?? () => memberStore.isLoggedIn)();

  Future<bool> _hasSeenOnboarding() =>
      (widget.hasSeenOnboarding ?? OnboardingScreen.hasSeen)();

  bool _isOnline() => (widget.isOnline ?? () => connectivityService.isOnline)();

  bool _launchedExternally() =>
      (widget.launchedExternally ??
          () =>
              deepLinkService.launchedFromDeepLink ||
              pushNotificationService.launchedFromColdPush)();

  bool _routeStacked() =>
      (widget.routeStackedAboveHome ??
          () => widget.navigatorKey.currentState?.canPop() ?? false)();

  Future<void> _openHref(String href) =>
      (widget.openHref ??
          (h) async => deepLinkService.handleExternalUri(h))(href);

  Future<void> _log(String name, Map<String, Object> params) =>
      (widget.logEvent ?? AppAnalytics.logEvent)(name, params);

  Future<LaunchPromoOutcome> _show(LaunchPopupCampaign c) {
    final ctx = widget.navigatorKey.currentContext ?? context;
    final fn = widget.showDialogFn ??
        (context, camp) => showLaunchPromoDialog(context, campaign: camp);
    return fn(ctx, c);
  }

  /// Tunggu memberStore selesai load profil dari disk (isLoggedIn bisa
  /// berubah false→true async). Timeout 3s sebagai jaring pengaman.
  Future<void> _realEnsureAuthReady() async {
    if (memberStore.initialized) return;
    final completer = Completer<void>();
    void listener() {
      if (memberStore.initialized && !completer.isCompleted) {
        memberStore.removeListener(listener);
        completer.complete();
      }
    }

    memberStore.addListener(listener);
    try {
      await completer.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // biarkan — pakai state login apa adanya.
    } finally {
      memberStore.removeListener(listener);
    }
  }

  Future<void> _maybeShow() async {
    if (_ran) return;
    _ran = true; // evaluasi sekali per mount

    final campaign = _campaign();
    if (campaign == null) return;

    await _ensureAuthReady();
    if (!mounted) return;
    if (widget.settleDelay > Duration.zero) {
      await Future<void>.delayed(widget.settleDelay);
    }
    if (!mounted) return;

    final show = launchPromoShouldShow(
      hasCampaign: true,
      isLoggedIn: _isLoggedIn(),
      hasSeenOnboarding: await _hasSeenOnboarding(),
      isOnline: _isOnline(),
      launchedExternally: _launchedExternally(),
      routeStackedAboveHome: _routeStacked(),
    );
    if (!mounted || !show) return;

    await _log('launch_popup_shown', {'campaign_id': campaign.id});
    final outcome = await _show(campaign);
    if (outcome == LaunchPromoOutcome.cta && campaign.hasCta) {
      await _log('launch_popup_cta_click', {'campaign_id': campaign.id});
      await _openHref(campaign.ctaHref!);
    } else {
      await _log('launch_popup_dismiss', {'campaign_id': campaign.id});
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd flutter_app && flutter test test/launch_promo_gate_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/launch_promo_gate.dart flutter_app/test/launch_promo_gate_test.dart
git commit -m "feat(popup): LaunchPromoGate — orkestrasi tampil/skip + analytics"
```

---

### Task 6: Pasang gate di `main.dart` + jaga smoke test

**Files:**
- Modify: `flutter_app/lib/main.dart` (import + sisipkan gate di builder chain, sekitar baris 76 & 242-247)
- Modify: `flutter_app/test/widget_test.dart` (jaga smoke test tetap hijau dengan gate baru)

**Interfaces:**
- Consumes: `LaunchPromoGate` (Task 5), `rootNavigatorKey` (sudah ada di main.dart).

- [ ] **Step 1: Update smoke test lebih dulu (akan gagal setelah gate dipasang bila tidak disesuaikan)**

Ganti isi `flutter_app/test/widget_test.dart` menjadi:

```dart
// Smoke test — pastikan app mount tanpa crash walau LaunchPromoGate aktif.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:natalo_petshop_flutter/main.dart';

void main() {
  testWidgets('app boots', (WidgetTester tester) async {
    // Gate membaca SharedPreferences (onboarding) — sediakan mock kosong.
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const NataloPetshopApp());
    // Drain kerja async gate (ensureAuthReady timeout 3s + settleDelay 900ms).
    // User tidak login di test → popup tidak muncul; cukup pastikan tidak crash.
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
```

- [ ] **Step 2: Tambah import di `main.dart`**

Setelah baris `import 'widgets/app_startup_splash.dart';` (baris ~74), tambah:

```dart
import 'widgets/launch_promo_gate.dart';
```

- [ ] **Step 3: Sisipkan gate di builder chain**

Di `main.dart`, ubah bagian dalam `builder:` (sekitar baris 242-247) dari:

```dart
            return AppStartupSplash(
              child: AppLockGate(
                child: ReadOnlyWelcomeGate(
                  child: ColoredBox(
```

menjadi:

```dart
            return AppStartupSplash(
              child: AppLockGate(
                child: ReadOnlyWelcomeGate(
                  child: LaunchPromoGate(
                    navigatorKey: rootNavigatorKey,
                    child: ColoredBox(
```

Lalu tutup kurung `LaunchPromoGate` yang baru: cari penutup `ColoredBox` → `ReadOnlyWelcomeGate` (sekitar baris 279-281) dan tambah satu penutup `)` untuk `LaunchPromoGate` **sebelum** penutup `ReadOnlyWelcomeGate`. Struktur akhir:

```dart
                  child: LaunchPromoGate(
                    navigatorKey: rootNavigatorKey,
                    child: ColoredBox(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? NataloColors.feedBlack
                          : NataloColors.background,
                      child: NotificationListener<ScrollUpdateNotification>(
                        onNotification: (notification) {
                          updateBottomNavScroll(notification);
                          return false;
                        },
                        child: Stack(
                          children: [
                            child ?? const SizedBox.shrink(),
                            const Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: OfflineBanner(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
```

- [ ] **Step 4: Run analyzer + smoke test**

Run: `cd flutter_app && flutter analyze lib/main.dart lib/widgets/launch_promo_gate.dart && flutter test test/widget_test.dart`
Expected: analyze bersih (no error); smoke test PASS.

- [ ] **Step 5: Run seluruh test baru sekaligus (regresi)**

Run: `cd flutter_app && flutter test test/launch_popup_campaign_test.dart test/launch_promo_decision_test.dart test/launch_promo_dialog_test.dart test/launch_intent_flags_test.dart test/launch_promo_gate_test.dart test/widget_test.dart`
Expected: semua PASS.

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/main.dart flutter_app/test/widget_test.dart
git commit -m "feat(popup): pasang LaunchPromoGate di builder chain main.dart"
```

- [ ] **Step 7: Verifikasi manual di device/emulator (checklist)**

Jalankan app (`cd flutter_app && flutter run`) dan konfirmasi:
- Login sebagai member → cold start (swipe app dari recent, buka lagi) → popup muncul di atas Beranda.
- Tap "Lihat produk" → popup tutup → halaman detail produk terbuka.
- Tap X / "Nanti saja" / area gelap / back Android → popup tutup, tetap di Beranda.
- Cold start berikutnya → popup muncul lagi (tiap cold start).
- Logout (guest) → cold start → popup TIDAK muncul.
- Matikan internet → cold start → popup TIDAK muncul.
- Buka app via tap notifikasi/deep-link ke layar lain → popup TIDAK muncul.

---

## Self-Review

**1. Spec coverage:**
- §5.1 model → Task 1 ✅ · §5.2 provider/sekat bersih → Task 1 ✅
- §5.3 gate → Task 5 ✅ · §5.4 dialog → Task 3 ✅
- §6 logika tampil/skip → Task 2 (murni) + Task 5 (orkestrasi) ✅
- §6 "route teratas masih Home" → `routeStackedAboveHome`/`canPop()` di Task 5 ✅
- §6 "tunggu memberStore settle" → `_realEnsureAuthReady` di Task 5 ✅
- §7.1/§7.2 flag deep-link & push → Task 4 ✅ · §7.3 sisip main.dart → Task 6 ✅
- §8 tampilan Hybrid (hero opsional, nada, tombol pill, X, mode info) → Task 3 ✅
- §9 analytics (shown/cta_click/dismiss + campaign_id) → Task 5 ✅
- §10 test + aturan anti-shimmer → Task 2/3/5, imageUrl null di test ✅
- §11 jalur upgrade → provider terisolasi di Task 1 ✅

**2. Placeholder scan:** Tidak ada TODO/TBD di langkah. `ctaHref` berisi slug konkret `/produk/royal-canin-kitten` dengan catatan verifikasi (bukan placeholder kode). ✅

**3. Type consistency:** `LaunchPopupCampaign`, `LaunchPopupTone`, `LaunchPromoOutcome{cta,dismiss}`, `launchPromoShouldShow(...)` bool params, `showLaunchPromoDialog(context, {required campaign})`, key `launch-popup-cta/dismiss/close`, event `launch_popup_shown/cta_click/dismiss`, flag `launchedFromDeepLink`/`launchedFromColdPush` — dipakai konsisten lintas Task 1→6. ✅
