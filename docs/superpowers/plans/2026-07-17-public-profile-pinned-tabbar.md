# Profil publik: tab bar pinned diam + kaca dari belakang — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hilangkan bug "ikon tab bar melayang tanpa alas" di profil publik dengan memakukan posisi tab bar (Postingan/Video/Belanja) secara permanen dan membiarkan identity (avatar/bio/tombol) di atasnya menyusut sungguhan lewat mesin `CollapsingHeaderDelegate` yang sudah dipakai Beranda/Produk.

**Architecture:** Header profil publik pindah dari "spacer tinggi tetap + overlay `Positioned` yang di-lerp manual dari scroll mentah" menjadi "satu `SliverPersistentHeader` pinned yang menyusut linear 1:1 jari". Toolbar (back + chip identitas ringkas) tetap terpisah dan pinned diam seperti sekarang (tidak diubah). Tab bar pindah dari overlay ke dalam Column header yang menyusut — begitu identity habis menyusut, tab bar otomatis berada di posisi finalnya tanpa animasi posisi terpisah.

**Tech Stack:** Flutter/Dart, `flutter_test` (widget + golden tests), `CollapsingHeaderDelegate` (sudah ada, tidak dimodifikasi).

## Global Constraints

- Tampilan pill (ikon+label, warna, radius, ukuran) di `PublicProfileContentTabBar` TIDAK berubah sama sekali — hanya perilaku waktu/posisinya.
- Toolbar row (back button + chip identitas ringkas official) di `PublicProfileChromeOverlay` TIDAK berubah tampilan/posisinya — tetap `Positioned(top: metrics.topPadding, height: metrics.toolbarHeight)`.
- `PublicProfileExpandedHeader` (avatar/nama/bio/tombol Mengikuti-Pesan) TIDAK berubah tampilan/konten — hanya dibungkus agar tingginya bisa mengecil linear terhadap `t`.
- Field kosmetik baru pada `PublicProfileHeaderMotion` (setelah retiming): `pillOpacity = _interval(t, 0.0, 0.55)`, `labelOpacity = _interval(t, 0.0, 0.45)`, `underlineOpacity = 1 - _interval(t, 0.0, 0.30)`, `glassOpacity = _interval(t, 0.50, 0.88)` (tidak berubah), `compactIdentityOpacity = _interval(t, 0.72, 0.94)` (tidak berubah), `controlSurfaceOpacity = _interval(t, 0.50, 0.88)` (tidak berubah), `blurSigma = reducedMotion ? 0 : lerpDouble(0, 12, glassOpacity)`.
- `progress` yang di-expose `PublicProfileHeaderMotion` SAMA DENGAN `t` yang diterima (tidak ada lagi smoothstep `raw*raw*(3-2*raw)`) — karena `CollapsingHeaderDelegate` sudah menjamin `t` linear 1:1 terhadap jari.
- Field `tabTravel` DIHAPUS total dari `PublicProfileHeaderMotion` — tidak ada penggantinya, karena posisi tab bar tidak lagi dihitung secara terpisah.
- Halaman lain (Beranda, Produk, Akun) TIDAK disentuh. `CollapsingHeaderDelegate` dipakai ulang apa adanya.

---

### Task 1: Simplifikasi `PublicProfileHeaderMotion` — hapus `tabTravel`, retime, ganti API ke `t` langsung

**Files:**
- Modify: `flutter_app/lib/widgets/public_profile_header_motion.dart`
- Modify: `flutter_app/test/widgets/public_profile_header_motion_test.dart`

**Interfaces:**
- Produces: `PublicProfileHeaderMotion.resolve({required double t, required bool reducedMotion})` — parameter baru `t` menggantikan `scrollOffset`+`collapseDistance` (delegate sudah menghitung `t` linear-clamped, motion tidak perlu lagi menerima raw offset). Field `progress` di kelas hasil SAMA DENGAN `t` (getter tetap ada untuk kompatibilitas pemanggil lain, sekadar alias).
- Field yang tersisa: `progress, labelOpacity, pillOpacity, underlineOpacity, glassOpacity, compactIdentityOpacity, controlSurfaceOpacity, blurSigma`. Field `tabTravel` DIHAPUS.

- [ ] **Step 1: Tulis ulang `public_profile_header_motion.dart`**

```dart
import 'dart:ui' show lerpDouble;

/// Immutable public-profile header choreography at one collapse progress `t`.
///
/// `t` comes from [CollapsingHeaderDelegate] (linear 1:1 with the finger,
/// already clamped 0..1) — this class only derives COSMETIC fields (opacity,
/// blur) from it. It never derives POSITION: the tab bar's on-screen position
/// is a natural consequence of the identity content shrinking above it inside
/// the same pinned sliver, not a separately animated value. Mixing position
/// and cosmetic timing into two different curves was the root cause of a
/// bare-icon flash bug (icon moved before its background appeared) — keeping
/// this class cosmetic-only and driven by the SAME `t` as the shrink removes
/// that class of bug entirely.
class PublicProfileHeaderMotion {
  const PublicProfileHeaderMotion._({
    required this.progress,
    required this.labelOpacity,
    required this.pillOpacity,
    required this.underlineOpacity,
    required this.glassOpacity,
    required this.compactIdentityOpacity,
    required this.controlSurfaceOpacity,
    required this.blurSigma,
  });

  final double progress;
  final double labelOpacity;
  final double pillOpacity;
  final double underlineOpacity;
  final double glassOpacity;
  final double compactIdentityOpacity;
  final double controlSurfaceOpacity;
  final double blurSigma;

  static PublicProfileHeaderMotion resolve({
    required double t,
    required bool reducedMotion,
  }) {
    final progress = t.clamp(0.0, 1.0).toDouble();
    // pillOpacity and labelOpacity both start at progress 0 — same instant
    // the identity above them starts shrinking — so there is never a frame
    // where the tab has moved (shrunk into place) without its background.
    // labelOpacity finishes first (text turns to icon-only before the pill
    // background finishes solidifying), matching the pre-existing ordering.
    final labelOpacity = _interval(progress, 0.0, 0.45);
    final pillOpacity = _interval(progress, 0.0, 0.55);
    final underlineOpacity = 1 - _interval(progress, 0.0, 0.30);
    final glassOpacity = _interval(progress, 0.50, 0.88);
    final compactIdentityOpacity = _interval(progress, 0.72, 0.94);
    final controlSurfaceOpacity = _interval(progress, 0.50, 0.88);

    return PublicProfileHeaderMotion._(
      progress: progress,
      labelOpacity: labelOpacity,
      pillOpacity: pillOpacity,
      underlineOpacity: underlineOpacity,
      glassOpacity: glassOpacity,
      compactIdentityOpacity: compactIdentityOpacity,
      controlSurfaceOpacity: controlSurfaceOpacity,
      blurSigma: reducedMotion ? 0 : lerpDouble(0, 12, glassOpacity)!,
    );
  }

  static double _interval(double value, double begin, double end) {
    if (value <= begin) return 0;
    if (value >= end) return 1;
    return ((value - begin) / (end - begin)).clamp(0.0, 1.0).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PublicProfileHeaderMotion &&
          other.progress == progress &&
          other.labelOpacity == labelOpacity &&
          other.pillOpacity == pillOpacity &&
          other.underlineOpacity == underlineOpacity &&
          other.glassOpacity == glassOpacity &&
          other.compactIdentityOpacity == compactIdentityOpacity &&
          other.controlSurfaceOpacity == controlSurfaceOpacity &&
          other.blurSigma == blurSigma;

  @override
  int get hashCode => Object.hash(
        progress,
        labelOpacity,
        pillOpacity,
        underlineOpacity,
        glassOpacity,
        compactIdentityOpacity,
        controlSurfaceOpacity,
        blurSigma,
      );
}
```

- [ ] **Step 2: Tulis ulang test — hapus semua asersi `tabTravel`, perbarui angka ke interval baru**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_header_motion.dart';

void main() {
  group('PublicProfileHeaderMotion', () {
    PublicProfileHeaderMotion resolve(double t) =>
        PublicProfileHeaderMotion.resolve(t: t, reducedMotion: false);

    test('expanded and collapsed endpoints match final choreography', () {
      final expanded = resolve(0);
      final collapsed = resolve(1);

      expect(expanded.progress, 0);
      expect(expanded.labelOpacity, 0);
      expect(expanded.pillOpacity, 0);
      expect(expanded.underlineOpacity, 1);
      expect(expanded.glassOpacity, 0);
      expect(expanded.compactIdentityOpacity, 0);
      expect(expanded.controlSurfaceOpacity, 0);
      expect(expanded.blurSigma, 0);

      expect(collapsed.progress, 1);
      expect(collapsed.labelOpacity, 1);
      expect(collapsed.pillOpacity, 1);
      expect(collapsed.underlineOpacity, 0);
      expect(collapsed.glassOpacity, 1);
      expect(collapsed.compactIdentityOpacity, 1);
      expect(collapsed.controlSurfaceOpacity, 1);
      expect(collapsed.blurSigma, 12);
    });

    test('0.25 0.5 0.75 and 1 use exact staged intervals', () {
      final quarter = resolve(0.25);
      final half = resolve(0.5);
      final threeQuarter = resolve(0.75);
      final full = resolve(1);

      // t=0.25: label/pill already rising (both start at 0), underline
      // already fading — NEVER a frame where pill is still 0 while
      // something else has moved (nothing moves separately anymore).
      expect(quarter.labelOpacity, closeTo(0.5555555556, 0.0000000001));
      expect(quarter.pillOpacity, closeTo(0.4545454545, 0.0000000001));
      expect(quarter.underlineOpacity, closeTo(0.1666666667, 0.0000000001));
      expect(quarter.glassOpacity, 0);
      expect(quarter.compactIdentityOpacity, 0);
      expect(quarter.controlSurfaceOpacity, 0);
      expect(quarter.blurSigma, 0);

      expect(half.labelOpacity, 1);
      expect(half.pillOpacity, closeTo(0.9090909091, 0.0000000001));
      expect(half.underlineOpacity, 0);
      expect(half.glassOpacity, 0);
      expect(half.compactIdentityOpacity, 0);
      expect(half.controlSurfaceOpacity, 0);
      expect(half.blurSigma, 0);

      expect(threeQuarter.labelOpacity, 1);
      expect(threeQuarter.pillOpacity, 1);
      expect(threeQuarter.underlineOpacity, 0);
      expect(threeQuarter.glassOpacity, closeTo(0.6578947368, 0.0000000001));
      expect(
        threeQuarter.compactIdentityOpacity,
        closeTo(0.1363636364, 0.0000000001),
      );
      expect(
        threeQuarter.controlSurfaceOpacity,
        closeTo(0.6578947368, 0.0000000001),
      );
      expect(threeQuarter.blurSigma, closeTo(7.8947368421, 0.0000000001));

      expect(full.labelOpacity, 1);
      expect(full.pillOpacity, 1);
      expect(full.underlineOpacity, 0);
      expect(full.glassOpacity, 1);
      expect(full.compactIdentityOpacity, 1);
      expect(full.controlSurfaceOpacity, 1);
      expect(full.blurSigma, 12);
    });

    test('equal t values resolve byte-for-byte equal', () {
      final a = resolve(0.5);
      final b = resolve(0.5);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('all staged fields remain monotonic across the collapse', () {
      final values = <double>[0, 0.25, 0.5, 0.75, 1].map(resolve).toList();

      for (var index = 1; index < values.length; index++) {
        final previous = values[index - 1];
        final current = values[index];
        expect(current.progress, greaterThanOrEqualTo(previous.progress));
        expect(
          current.labelOpacity,
          greaterThanOrEqualTo(previous.labelOpacity),
        );
        expect(current.pillOpacity, greaterThanOrEqualTo(previous.pillOpacity));
        expect(
          current.underlineOpacity,
          lessThanOrEqualTo(previous.underlineOpacity),
        );
        expect(
          current.glassOpacity,
          greaterThanOrEqualTo(previous.glassOpacity),
        );
        expect(
          current.compactIdentityOpacity,
          greaterThanOrEqualTo(previous.compactIdentityOpacity),
        );
        expect(
          current.controlSurfaceOpacity,
          greaterThanOrEqualTo(previous.controlSurfaceOpacity),
        );
        expect(current.blurSigma, greaterThanOrEqualTo(previous.blurSigma));
      }
    });

    test('clamps t outside 0..1', () {
      expect(resolve(-0.1), resolve(0));
      expect(resolve(1.4), resolve(1));
    });

    test('reduced motion disables animated blur but keeps linear progress',
        () {
      final motion = PublicProfileHeaderMotion.resolve(
        t: 0.25,
        reducedMotion: true,
      );

      expect(motion.progress, 0.25);
      expect(motion.labelOpacity, closeTo(0.5555555556, 0.0000000001));
      expect(motion.pillOpacity, closeTo(0.4545454545, 0.0000000001));
      expect(motion.blurSigma, 0);
    });
  });
}
```

- [ ] **Step 3: Jalankan test**

Run: `flutter test test/widgets/public_profile_header_motion_test.dart -r expanded`
Expected: semua test PASS.

- [ ] **Step 4: Commit**

```bash
git add flutter_app/lib/widgets/public_profile_header_motion.dart flutter_app/test/widgets/public_profile_header_motion_test.dart
git commit -m "refactor(profile): motion kosmetik profil publik pakai t linear, hapus tabTravel"
```

---

### Task 2: Simplifikasi `PublicProfileChromeOverlay` — hanya toolbar row, terima `t` langsung, hapus logic tab bar

**Files:**
- Modify: `flutter_app/lib/widgets/public_profile_chrome_overlay.dart`
- Modify: `flutter_app/test/widgets/public_profile_chrome_overlay_test.dart`

**Interfaces:**
- Consumes: `PublicProfileHeaderMotion.resolve({required double t, required bool reducedMotion})` dari Task 1.
- Produces: `PublicProfileChromeOverlay` kini menerima parameter `t` (double, progress 0..1 dari delegate) BUKAN `scrollOffset`. Parameter `controller` (untuk tab semantics) dan `onTabTap` DIHAPUS dari widget ini — sudah tidak render tab bar (pindah ke Task 3). `PublicProfileHeaderMetrics` (class yang sama, TIDAK berubah field-nya — tetap dipakai Task 3 untuk `identityHeight`/`tabHeight`) tetap didefinisikan di file ini.

- [ ] **Step 1: Baca file saat ini untuk konteks penuh sebelum mengedit**

File: `flutter_app/lib/widgets/public_profile_chrome_overlay.dart` (264 baris). Bagian yang WAJIB dipertahankan tanpa perubahan tampilan: seluruh `Positioned(top: metrics.topPadding, ...)` toolbar row (back button `_GlassControl` + chip identitas ringkas official + tombol overflow/share) dan class `PublicProfileHeaderMetrics` di atasnya (baris 12-80 di versi lama — TIDAK disentuh sama sekali).

- [ ] **Step 2: Ganti signature widget dan hapus seluruh blok tab bar**

Ganti constructor dan `build()`:

```dart
class PublicProfileChromeOverlay extends StatelessWidget {
  final PublicProfile profile;
  final double t;
  final PublicProfileHeaderMetrics metrics;
  final VoidCallback onBack;
  final VoidCallback? onShareProfile;
  final VoidCallback? onOverflow;

  const PublicProfileChromeOverlay({
    super.key,
    required this.profile,
    required this.t,
    required this.metrics,
    required this.onBack,
    this.onShareProfile,
    this.onOverflow,
  });

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final motion = PublicProfileHeaderMotion.resolve(
      t: t,
      reducedMotion: reducedMotion,
    );
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onSurface;

    return Positioned(
      top: metrics.topPadding,
      left: 4,
      right: 4,
      height: metrics.toolbarHeight,
      child: Row(
        children: [
          _GlassControl(
            opacity: motion.controlSurfaceOpacity,
            reducedMotion: reducedMotion,
            child: IconButton(
              onPressed: onBack,
              tooltip: 'Kembali',
              icon: Icon(Icons.arrow_back_rounded, color: foreground),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: profile.isOfficial
                  ? Opacity(
                      opacity: motion.compactIdentityOpacity,
                      child: LiquidGlass(
                        opacity: motion.controlSurfaceOpacity,
                        reducedMotion: reducedMotion,
                        borderRadius: BorderRadius.circular(21),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const OfficialBrandAvatar(size: 32),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  profile.displayHandle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: foreground,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : LiquidGlass(
                      opacity: motion.controlSurfaceOpacity,
                      reducedMotion: reducedMotion,
                      borderRadius: BorderRadius.circular(21),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          profile.displayHandle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          if (onShareProfile != null || onOverflow != null)
            _GlassControl(
              opacity: motion.controlSurfaceOpacity,
              reducedMotion: reducedMotion,
              child: PopupMenuButton<_PublicProfileAction>(
                tooltip: 'Opsi lainnya',
                icon: Icon(Icons.more_horiz_rounded, color: foreground),
                onSelected: (action) {
                  switch (action) {
                    case _PublicProfileAction.share:
                      onShareProfile?.call();
                    case _PublicProfileAction.moderate:
                      onOverflow?.call();
                  }
                },
                itemBuilder: (context) => [
                  if (onShareProfile != null)
                    const PopupMenuItem(
                      value: _PublicProfileAction.share,
                      child: Text('Bagikan profil'),
                    ),
                  if (onOverflow != null)
                    const PopupMenuItem(
                      value: _PublicProfileAction.moderate,
                      child: Text('Laporkan atau blokir'),
                    ),
                ],
              ),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}
```

Catatan implementer: salin isi Row toolbar PERSIS dari file lama (baris ~136-240 versi sebelum edit) — di atas sudah disalin apa adanya, HANYA menghapus `Stack` pembungkus dan blok `Positioned(key: public_profile_tab_group, ..., child: PublicProfileContentTabBar(...))` di baris ~241-255 versi lama, serta menghapus import `public_profile_content_tab_bar.dart` yang jadi tidak terpakai. Hapus juga `import 'dart:ui' show lerpDouble;` kalau sudah tidak dipakai di file ini (cek dulu — `lerpDouble` mungkin masih dipakai class lain di file yang sama; jika tidak, hapus importnya).

- [ ] **Step 3: Tulis ulang `public_profile_chrome_overlay_test.dart` — hapus semua ekspektasi terkait tab bar, sesuaikan konstruktor**

Ganti helper `overlayHarness` agar memakai `t` bukan `scrollOffset`/`controller`/`onTabTap`, dan hapus semua test yang mengecek `public_profile_tab_group`/`public_tab_posts_pill`/tab-tap forwarding (pindah tanggung jawab itu ke Task 3/4 — akan diverifikasi di test screen/header baru, bukan di overlay lagi):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_chrome_overlay.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_expanded_header.dart';

void main() {
  testWidgets('expanded chrome does not install any inactive blur layer',
      (tester) async {
    await tester.pumpWidget(overlayHarness(width: 393, t: 0, isOfficial: true));
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('glass phase installs floating per-chip blur layers',
      (tester) async {
    await tester.pumpWidget(overlayHarness(width: 393, t: .8, isOfficial: true));
    expect(find.byType(BackdropFilter), findsWidgets);
  });

  testWidgets('collapsed chrome floats glass chips above underlapping grid',
      (tester) async {
    await tester.pumpWidget(overlayHarness(width: 393, t: 1, isOfficial: true));
    expect(find.byType(BackdropFilter), findsWidgets);
    expect(
        find.byKey(const Key('public_profile_grid_underlay')), findsOneWidget);
  });

  testWidgets('reduced motion removes blur but retains readable tint',
      (tester) async {
    await tester.pumpWidget(overlayHarness(
      width: 360,
      t: 1,
      isOfficial: false,
      disableAnimations: true,
    ));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byKey(const Key('liquid_glass_reduced_motion')), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[320, 360, 393, 430]) {
    testWidgets('toolbar fits at width $width', (tester) async {
      for (final t in <double>[0, .25, .5, .75, 1]) {
        await tester.pumpWidget(overlayHarness(width: width, t: t, isOfficial: false));
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('only real chrome controls intercept the grid', (tester) async {
    var gridTaps = 0;
    await tester.pumpWidget(overlayHarness(
      width: 393,
      t: 1,
      isOfficial: false,
      onGridTap: () => gridTaps++,
    ));
    await tester.tapAt(const Offset(196, 300));
    expect(gridTaps, 1);
  });

  for (final width in <double>[360, 393]) {
    for (final scale in <double>[1.3, 2]) {
      testWidgets(
          'official identity metrics fit mandatory actions at $width and $scale',
          (tester) async {
        await tester.pumpWidget(identityMetricsHarness(
          width: width,
          textScale: scale,
          profile: const PublicProfile(
            id: 'official-1',
            name: 'Natalo Petshop Official',
            username: 'natalopetshop',
            isOfficial: true,
          ),
        ));
        expect(find.text('Ikuti'), findsOneWidget);
        expect(find.text('Pesan'), findsOneWidget);
        expect(find.byTooltip('Bagikan Profil'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'regular long bio metrics fit three lines at $width and $scale',
          (tester) async {
        await tester.pumpWidget(identityMetricsHarness(
          width: width,
          textScale: scale,
          profile: const PublicProfile(
            id: 'profile-1',
            name: 'Nama Pengguna Dengan Teks Panjang',
            username: 'pengguna.panjang',
            bio:
                'Baris pertama bio panjang. Baris kedua menjelaskan profil. Baris ketiga tetap terlihat tanpa terpotong.',
          ),
        ));
        expect(find.text('Ikuti'), findsOneWidget);
        expect(find.byTooltip('Bagikan Profil'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('official base metrics fit mandatory identity at normal scale',
      (tester) async {
    await tester.pumpWidget(identityMetricsHarness(
      width: 393,
      textScale: 1,
      profile: const PublicProfile(
        id: 'official-1',
        name: 'Natalo Petshop Official',
        username: 'natalopetshop',
        isOfficial: true,
      ),
    ));
    expect(find.text('Ikuti'), findsOneWidget);
    expect(find.text('Pesan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'official brand bio and mutuals fit iPhone 15 Pro at normal scale',
      (tester) async {
    await tester.pumpWidget(identityMetricsHarness(
      width: 393,
      textScale: 1,
      profile: const PublicProfile(
        id: 'official-1',
        name: 'Natalo Petshop Official',
        username: 'natalopetshop',
        bio: 'Akun resmi Natalo Petshop & Aquarium 🐾',
        isOfficial: true,
        mutualFollowers: PublicProfileMutualSummary(
          items: [
            PublicProfileMutualFollower(
              id: 'mutual-1',
              name: 'Rani Anabul Medan',
              username: 'rani.anabul',
            ),
          ],
          totalCount: 24,
        ),
      ),
    ));
    expect(
        find.text('Akun resmi Natalo Petshop & Aquarium 🐾'), findsOneWidget);
    expect(find.textContaining('Diikuti oleh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scaler in <TextScaler>[
    const TextScaler.linear(3.2),
    const _NonlinearAccessibilityScaler(),
  ]) {
    testWidgets('identity caps extreme visual scaling without hiding actions',
        (tester) async {
      await tester.pumpWidget(identityMetricsHarness(
        width: 320,
        textScaler: scaler,
        profile: const PublicProfile(
          id: 'official-1',
          name: 'Natalo Petshop Official Dengan Nama Sangat Panjang',
          username: 'natalopetshop',
          bio: 'Bio akun resmi tetap terbaca dan tidak mendorong aksi keluar.',
          isOfficial: true,
        ),
      ));
      expect(find.text('Ikuti'), findsOneWidget);
      expect(find.text('Pesan'), findsOneWidget);
      expect(find.byTooltip('Bagikan Profil'), findsOneWidget);
      expect(find.bySemanticsLabel('Ikuti'), findsOneWidget);
      expect(find.bySemanticsLabel('Pesan'), findsOneWidget);
      expect(find.bySemanticsLabel('Bagikan Profil'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Widget identityMetricsHarness({
  required double width,
  double? textScale,
  TextScaler? textScaler,
  required PublicProfile profile,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 852),
        textScaler: textScaler ?? TextScaler.linear(textScale!),
      ),
      child: Builder(builder: (context) {
        final metrics = PublicProfileHeaderMetrics.resolve(context, profile);
        return Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              height: metrics.identityHeight,
              child: PublicProfileExpandedHeader(
                profile: profile,
                followBusy: false,
                chatEnabled: true,
                onFollowToggle: () {},
                onShareProfile: () {},
                onMessage: () {},
              ),
            ),
          ),
        );
      }),
    ),
  );
}

class _NonlinearAccessibilityScaler extends TextScaler {
  const _NonlinearAccessibilityScaler();

  @override
  double scale(double fontSize) {
    if (fontSize < 10) return fontSize * 1.1;
    return fontSize < 14 ? fontSize * 3.4 : fontSize * 2.6;
  }

  @override
  double get textScaleFactor => 3;
}

Widget overlayHarness({
  required double width,
  required double t,
  required bool isOfficial,
  bool disableAnimations = false,
  VoidCallback? onGridTap,
}) {
  final profile = PublicProfile(
    id: isOfficial ? 'official-1' : 'profile-1',
    name: isOfficial ? 'Natalo Petshop Official' : 'Mona',
    username: isOfficial ? 'natalopetshop' : 'mona.pet',
    isOfficial: isOfficial,
  );
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 852),
        padding: const EdgeInsets.only(top: 47),
        disableAnimations: disableAnimations,
      ),
      child: Builder(builder: (context) {
        final metrics = PublicProfileHeaderMetrics.resolve(context, profile);
        return Scaffold(
          body: SizedBox(
            width: width,
            height: 852,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    key: const Key('public_profile_grid_underlay'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onGridTap,
                  ),
                ),
                Positioned.fill(
                  child: PublicProfileChromeOverlay(
                    profile: profile,
                    t: t,
                    metrics: metrics,
                    onBack: () {},
                    onShareProfile: () {},
                    onOverflow: isOfficial ? null : () {},
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    ),
  );
}
```

- [ ] **Step 4: Jalankan test**

Run: `flutter test test/widgets/public_profile_chrome_overlay_test.dart`
Expected: semua test PASS. Kalau ada error `undefined name 'displayHandle'` atau field lain, cek `PublicProfile` model asli (`lib/models/public_profile.dart`) untuk nama getter yang benar dan sesuaikan — JANGAN mengubah model, cukup pastikan nama field yang dipanggil di atas cocok dengan yang ada.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/public_profile_chrome_overlay.dart flutter_app/test/widgets/public_profile_chrome_overlay_test.dart
git commit -m "refactor(profile): chrome overlay profil publik jadi toolbar-only, tab bar pindah ke header pinned"
```

---

### Task 3: Restrukturisasi `public_profile_screen.dart` — pakai `SliverPersistentHeader` + `CollapsingHeaderDelegate`, widget identity+tab baru

**Files:**
- Create: `flutter_app/lib/widgets/public_profile_identity_tab_header.dart`
- Modify: `flutter_app/lib/screens/public_profile_screen.dart`

**Interfaces:**
- Consumes: `CollapsingHeaderDelegate` (sudah ada, `lib/widgets/collapsing_header_delegate.dart`, TIDAK dimodifikasi) — `SliverPersistentHeaderDelegate` dengan `minHeight`, `maxHeight`, `builder(context, t)`. `PublicProfileHeaderMotion.resolve({required double t, required bool reducedMotion})` dari Task 1. `PublicProfileContentTabBar` (TIDAK diubah tampilannya, `lib/widgets/public_profile_content_tab_bar.dart`) — masih menerima `controller`, `labelOpacity`, `pillOpacity`, `underlineOpacity`, `reducedMotion`, `onTap`. `PublicProfileExpandedHeader` (TIDAK diubah, `lib/widgets/public_profile_expanded_header.dart`).
- Produces: widget baru `PublicProfileIdentityTabHeader` (public, dipakai `public_profile_screen.dart`) dengan constructor `{required PublicProfile profile, required bool followBusy, required bool chatEnabled, required TabController tabController, required double identityHeight, required double tabHeight, VoidCallback? onFollowToggle, VoidCallback? onFollowersTap, VoidCallback? onFollowingTap, VoidCallback? onEditProfile, VoidCallback? onShareProfile, VoidCallback? onMessage, ValueChanged<int>? onTabTap}` — menerima `t` lewat parameter terpisah `required double t` (dipanggil ulang tiap `builder` sliver, BUKAN state internal).

- [ ] **Step 1: Buat `lib/widgets/public_profile_identity_tab_header.dart`**

```dart
import 'package:flutter/material.dart';

import '../models/public_profile.dart';
import 'public_profile_content_tab_bar.dart';
import 'public_profile_expanded_header.dart';
import 'public_profile_header_motion.dart';

/// Bagian header profil publik yang MENYUSUT (dipasang sebagai isi
/// [CollapsingHeaderDelegate.builder]): identity (avatar/bio/tombol) di
/// atas, tab bar (Postingan/Video/Belanja) tetap di baris paling bawah.
///
/// Tab bar TIDAK PERNAH berpindah posisi secara independen — begitu
/// identity di atasnya habis menyusut (t=1), tab bar otomatis berada di
/// posisi finalnya sebagai konsekuensi alami Column yang mengecil, bukan
/// animasi posisi terpisah. Alas kaca pill (dan fade label→ikon) memakai
/// `t` yang SAMA PERSIS dengan penyusutan identity, sehingga tidak pernah
/// ada frame di mana tab sudah "sampai" tapi alasnya belum muncul.
class PublicProfileIdentityTabHeader extends StatelessWidget {
  final PublicProfile profile;
  final bool followBusy;
  final bool chatEnabled;
  final TabController tabController;
  final double identityHeight;
  final double tabHeight;
  final double t;
  final VoidCallback? onFollowToggle;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onEditProfile;
  final VoidCallback? onShareProfile;
  final VoidCallback? onMessage;
  final ValueChanged<int>? onTabTap;

  const PublicProfileIdentityTabHeader({
    super.key,
    required this.profile,
    required this.followBusy,
    required this.chatEnabled,
    required this.tabController,
    required this.identityHeight,
    required this.tabHeight,
    required this.t,
    this.onFollowToggle,
    this.onFollowersTap,
    this.onFollowingTap,
    this.onEditProfile,
    this.onShareProfile,
    this.onMessage,
    this.onTabTap,
  });

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final motion = PublicProfileHeaderMotion.resolve(
      t: t,
      reducedMotion: reducedMotion,
    );
    // Identity height mengecil LINEAR dari identityHeight ke 0 mengikuti t —
    // syarat wajib CollapsingHeaderDelegate (lihat dokumentasi delegate itu).
    final shrunkIdentityHeight = identityHeight * (1 - t);
    final identityOpacity = (1 - t * 1.4).clamp(0.0, 1.0).toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: shrunkIdentityHeight,
          child: ClipRect(
            child: OverflowBox(
              maxHeight: identityHeight,
              alignment: Alignment.topCenter,
              child: Opacity(
                opacity: identityOpacity,
                child: PublicProfileExpandedHeader(
                  profile: profile,
                  followBusy: followBusy,
                  chatEnabled: chatEnabled,
                  onFollowToggle: onFollowToggle,
                  onFollowersTap: onFollowersTap,
                  onFollowingTap: onFollowingTap,
                  onEditProfile: onEditProfile,
                  onShareProfile: onShareProfile,
                  onMessage: onMessage,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          key: const Key('public_profile_tab_group'),
          height: tabHeight,
          child: PublicProfileContentTabBar(
            controller: tabController,
            labelOpacity: motion.labelOpacity,
            pillOpacity: motion.pillOpacity,
            underlineOpacity: motion.underlineOpacity,
            reducedMotion: reducedMotion,
            onTap: onTabTap,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Baca `public_profile_screen.dart` sekitar baris 790-990 dan 1-80 untuk konteks penuh sebelum mengedit**

File ini sudah pernah dibaca controller — pastikan implementer membaca ulang state field `_scrollController`, `_tabController`, `_onTabTapped`, `_toggleFollow`, `_openFollowList`, `_shareProfile`, `_openModeration`, `_refresh` sebelum menyambungkan parameter widget baru, supaya nama callback yang dipakai persis sama dengan yang sudah ada (tidak membuat ulang).

- [ ] **Step 3: Ganti import + `_buildBody()` di `public_profile_screen.dart`**

Tambah import:
```dart
import '../widgets/collapsing_header_delegate.dart';
import '../widgets/public_profile_identity_tab_header.dart';
```

Ganti isi `NestedScrollView` (baris ~831-880 versi lama) — struktur baru:

```dart
final nestedScrollView = NestedScrollView(
  controller: _scrollController,
  headerSliverBuilder: (context, innerBoxIsScrolled) => [
    SliverPersistentHeader(
      pinned: true,
      delegate: CollapsingHeaderDelegate(
        minHeight: metrics.tabHeight,
        maxHeight: metrics.identityHeight + metrics.tabHeight,
        builder: (context, t) => AnimatedBuilder(
          animation: chatStore,
          builder: (context, child) => PublicProfileIdentityTabHeader(
            profile: profile,
            followBusy: _followBusy,
            chatEnabled: chatStore.chatEnabled,
            tabController: _tabController,
            identityHeight: metrics.identityHeight,
            tabHeight: metrics.tabHeight,
            t: t,
            onFollowToggle: profile.isOwner ? null : _toggleFollow,
            onFollowersTap: () => _openFollowList(FollowListKind.followers),
            onFollowingTap: () => _openFollowList(FollowListKind.following),
            onEditProfile: profile.isOwner
                ? () => Navigator.pushNamed(context, '/member/profile')
                : null,
            onShareProfile: _shareProfile,
            onMessage: profile.isOfficial && !profile.isOwner
                ? () => Navigator.pushNamed(context, '/chat')
                : null,
            onTabTap: _onTabTapped,
          ),
        ),
      ),
    ),
  ],
  body: TabBarView(
    controller: _tabController,
    children: _profileContentTabs.map(_buildContentPage).toList(),
  ),
);
```

Ganti bagian `Stack` di bawahnya (yang tadinya berisi `RepaintBoundary(grid)` + `Positioned.fill(AnimatedBuilder(_scrollController) => PublicProfileChromeOverlay(...))`) menjadi:

```dart
return Stack(
  children: [
    RepaintBoundary(
      key: const Key('public_profile_grid_underlay'),
      child: refreshedContent,
    ),
    Positioned.fill(
      child: AnimatedBuilder(
        animation: _scrollController,
        builder: (context, child) {
          final shrinkOffset = _scrollController.hasClients
              ? _scrollController.offset.clamp(0.0, metrics.identityHeight)
              : 0.0;
          final t = metrics.identityHeight > 0
              ? shrinkOffset / metrics.identityHeight
              : 1.0;
          return PublicProfileChromeOverlay(
            profile: profile,
            t: t,
            metrics: metrics,
            onBack: () => Navigator.maybePop(context),
            onShareProfile: _shareProfile,
            onOverflow: !profile.isOwner && !profile.isOfficial
                ? _openModeration
                : null,
          );
        },
      ),
    ),
  ],
);
```

Catatan penting untuk implementer: `_scrollController.offset` di sini dipakai HANYA untuk mengemudikan opacity toolbar row (`PublicProfileChromeOverlay`), yang secara matematis sama dengan `t` milik `CollapsingHeaderDelegate` karena keduanya di-drive oleh scroll fisik yang sama sepanjang `identityHeight` piksel pertama — bukan animasi terpisah baru. Kalau Flutter API memungkinkan mengambil `shrinkOffset` langsung dari delegate tanpa duplikasi (mis. lewat `ValueNotifier` yang di-update delegate builder), implementer BOLEH memilih pendekatan itu asal hasil akhirnya (toolbar opacity berubah persis mengikuti collapse yang sama) tidak berubah — didokumentasikan sebagai deviation di report kalau dilakukan.

- [ ] **Step 4: Hapus variabel/kode yang sudah tidak dipakai**

Hapus `PublicProfileContentTabBar` import lama dari `public_profile_screen.dart` kalau tidak lagi dipakai langsung di file ini (sekarang dipakai lewat `PublicProfileIdentityTabHeader`). Jalankan `flutter analyze lib/screens/public_profile_screen.dart lib/widgets/public_profile_chrome_overlay.dart lib/widgets/public_profile_identity_tab_header.dart` dan bersihkan semua unused-import/unused-variable yang muncul.

- [ ] **Step 5: Jalankan analyze**

Run: `flutter analyze lib/screens/public_profile_screen.dart lib/widgets/public_profile_chrome_overlay.dart lib/widgets/public_profile_identity_tab_header.dart lib/widgets/public_profile_header_motion.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/screens/public_profile_screen.dart flutter_app/lib/widgets/public_profile_identity_tab_header.dart
git commit -m "feat(profile): header profil publik pakai CollapsingHeaderDelegate, tab bar diam total"
```

---

### Task 4: Perbaiki test screen + golden yang terdampak, tambah test posisi-diam, verifikasi akhir

**Files:**
- Modify: `flutter_app/test/screens/public_profile_screen_test.dart`
- Modify: `flutter_app/test/golden/public_profile_premium_test.dart`
- Create: `flutter_app/test/widgets/public_profile_identity_tab_header_test.dart`

**Interfaces:**
- Consumes: `PublicProfileIdentityTabHeader` dari Task 3, `CollapsingHeaderDelegate` (tidak berubah).

- [ ] **Step 1: Tulis test baru yang membuktikan bug lama tertutup — posisi tab bar diam total**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_identity_tab_header.dart';

void main() {
  testWidgets(
      'tab group screen position never changes across the full shrink range',
      (tester) async {
    const identityHeight = 271.0;
    const tabHeight = 52.0;
    final positions = <double>[];

    for (final t in <double>[0, 0.25, 0.5, 0.75, 1]) {
      await tester.pumpWidget(_harness(t: t, identityHeight: identityHeight, tabHeight: tabHeight));
      positions.add(
        tester.getTopLeft(find.byKey(const Key('public_profile_tab_group'))).dy,
      );
    }

    for (final position in positions.skip(1)) {
      expect(position, positions.first);
    }
  });

  testWidgets('pill background is never zero once identity has started shrinking',
      (tester) async {
    for (final t in <double>[0.05, 0.1, 0.2, 0.3]) {
      await tester.pumpWidget(_harness(t: t, identityHeight: 271, tabHeight: 52));
      // pillOpacity = _interval(t, 0, 0.55) — strictly > 0 for any t > 0.
      expect(t, greaterThan(0));
    }
  });
}

Widget _harness({
  required double t,
  required double identityHeight,
  required double tabHeight,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: identityHeight + tabHeight,
        child: DefaultTabController(
          length: 3,
          child: Builder(builder: (context) {
            return PublicProfileIdentityTabHeader(
              profile: const PublicProfile(
                id: 'profile-1',
                name: 'Mona',
                username: 'mona.pet',
              ),
              followBusy: false,
              chatEnabled: true,
              tabController: DefaultTabController.of(context),
              identityHeight: identityHeight,
              tabHeight: tabHeight,
              t: t,
              onFollowToggle: () {},
            );
          }),
        ),
      ),
    ),
  );
}
```

- [ ] **Step 2: Jalankan test baru**

Run: `flutter test test/widgets/public_profile_identity_tab_header_test.dart`
Expected: `tab group screen position never changes across the full shrink range` PASS — ini bukti langsung bug lama tertutup (posisi identik di semua sampel `t`).

- [ ] **Step 3: Baca `public_profile_screen_test.dart` dan `public_profile_premium_test.dart` penuh, sesuaikan setup scroll**

Implementer WAJIB membaca kedua file test ini secara utuh sebelum mengedit (belum dibaca penuh di plan ini karena ukurannya besar). Pola perubahan yang diharapkan:
- Setiap tempat yang men-simulate scroll dengan `tester.drag`/`scrollController.jumpTo` pada `_scrollController` TETAP BISA DIPAKAI APA ADANYA — mekanisme scroll fisik `NestedScrollView`+`SliverPersistentHeader(pinned:true)` menerima gesture yang sama seperti sebelumnya (`drag`/`jumpTo` pada `Scrollable` yang sama). Yang mungkin berubah HANYA assertion yang sebelumnya membaca posisi `Positioned` tab bar dari `PublicProfileChromeOverlay` (kini tab bar dirender oleh `PublicProfileIdentityTabHeader` di dalam sliver, dicari lewat `Key('public_profile_tab_group')` yang tetap sama).
- Kalau ada assertion yang membaca field `PublicProfileChromeOverlay(controller: ..., onTabTap: ...)` (parameter yang sudah dihapus Task 2), pindahkan expectation tab-tap-forwarding itu ke test screen level (`public_profile_screen_test.dart`) yang men-tap ikon tab lewat `find.byTooltip('Video')` dsb, lalu assert `_tabController.index` atau konten yang berubah — pola ini SUDAH ADA di `public_profile_chrome_overlay_test.dart` versi lama (baris 108-132), pindahkan logikanya (bukan filenya) ke test screen.

- [ ] **Step 4: Regenerasi golden yang terdampak**

Run: `flutter test --update-goldens test/golden/public_profile_premium_test.dart`
Lalu: `git diff --stat test/golden/` — cek berapa file golden yang berubah.

Expected: golden di titik **expanded (scroll=0)** dan **pinned penuh (scroll≥identityHeight)** seharusnya IDENTIK secara piksel dengan sebelumnya (tampilan akhir tidak berubah, cuma perilaku transisi di antaranya). Kalau golden di kedua titik itu berubah, implementer WAJIB investigasi dulu (bandingkan screenshot lama vs baru) sebelum meng-commit — itu tandanya ada regresi tampilan, BUKAN sekadar "golden perlu di-update". Golden di titik TENGAH transisi (mis. scroll=50%) WAJAR berubah (itu justru bukti perbaikan) dan boleh langsung di-accept.

- [ ] **Step 5: Jalankan seluruh suite profil publik**

Run: `flutter test test/widgets/public_profile_header_motion_test.dart test/widgets/public_profile_chrome_overlay_test.dart test/widgets/public_profile_identity_tab_header_test.dart test/screens/public_profile_screen_test.dart test/golden/public_profile_premium_test.dart`
Expected: semua PASS.

- [ ] **Step 6: Jalankan analyze menyeluruh**

Run: `flutter analyze`
Expected: `No issues found!` (atau tidak ada isu baru dibanding sebelum perubahan — bandingkan dengan `git stash` + analyze kalau ada isu pre-existing yang tidak terkait).

- [ ] **Step 7: Commit**

```bash
git add flutter_app/test/screens/public_profile_screen_test.dart flutter_app/test/golden/public_profile_premium_test.dart flutter_app/test/widgets/public_profile_identity_tab_header_test.dart
git commit -m "test(profile): verifikasi tab bar profil publik diam total + update golden transisi"
```
