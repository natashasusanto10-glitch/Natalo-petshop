import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/screens/home_screen.dart';
import 'package:natalo_petshop_flutter/state/cart_store.dart';
import 'package:natalo_petshop_flutter/state/home_snapshot_store.dart';
import 'package:natalo_petshop_flutter/widgets/natalo_paw_refresh_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> productJson(String id, String name) => {
      'id': id,
      'slug': id,
      'name': name,
      'price': 10000,
      'image_url': '',
    };

/// Bounded pump — JANGAN pumpAndSettle: marquee header + shimmer skeleton
/// beranimasi terus, settle tidak pernah tercapai (gotcha dikenal).
Future<void> pumpBounded(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> mountHome(WidgetTester tester, void Function() suppress) async {
  suppress();
  // Surface ukuran ponsel (logical 390x844) — default test 800x600 membuat
  // header brand row overflow (didesain untuk lebar ponsel, bukan tablet).
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  await pumpBounded(tester);
}

/// Unmount + drain supaya timer periodik (marquee/countdown) dibatalkan
/// oleh dispose — tanpa ini test gagal "Timer is still pending".
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

void stubOthersEmpty() {
  homeSnapshotStore.debugBrandsFetcher = () async => [];
  homeSnapshotStore.debugCategoriesFetcher = () async => [];
  homeSnapshotStore.debugBannersFetcher = () async => [];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    homeSnapshotStore.resetForTest();
    cartStore.clear();
  });

  /// Telan HANYA error overflow; error lain tetap diteruskan. Header Beranda
  /// punya _TrustMarquee (OverflowBox — konten bergilir sengaja lebih lebar
  /// dari layar) + brand-row terlipat via Align.heightFactor saat collapse;
  /// keduanya memicu RenderFlex overflow transient yang tidak relevan dengan
  /// logika banner/store yang diuji (layout header dijaga golden + device).
  /// Dipasang di dalam mountHome (bukan setUp) karena test binding meng-reset
  /// FlutterError.onError saat test body mulai.
  void suppressOverflowErrors() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('overflowed')) return;
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  testWidgets('fetch in-flight: banner "Belum berhasil memuat" TIDAK tampil',
      (tester) async {
    final gate = Completer<List<Map<String, dynamic>>?>();
    homeSnapshotStore.debugProductsFetcher = () => gate.future;
    stubOthersEmpty();
    await mountHome(tester, suppressOverflowErrors);
    // Regresi utama bug A: selama loading tidak boleh ada pesan gagal.
    expect(find.textContaining('Belum berhasil memuat'), findsNothing);
    gate.complete(const []);
    await pumpBounded(tester);
    await unmount(tester);
  });

  testWidgets('store kosong + fetch gagal: banner tampil', (tester) async {
    homeSnapshotStore.debugProductsFetcher = () async => null;
    stubOthersEmpty();
    await mountHome(tester, suppressOverflowErrors);
    expect(find.textContaining('Belum berhasil memuat'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
      'konten cache tampil + refresh gagal: konten render, banner absen',
      (tester) async {
    // Seed konten (simulasi hydrate/sesi sebelumnya) via refresh sukses.
    homeSnapshotStore.debugProductsFetcher =
        () async => [productJson('p1', 'Produk Cache Uji')];
    stubOthersEmpty();
    await homeSnapshotStore.refresh();
    // Refresh berikutnya gagal.
    homeSnapshotStore.debugProductsFetcher = () async => null;
    await mountHome(tester, suppressOverflowErrors);
    await homeSnapshotStore.refresh(force: true);
    await pumpBounded(tester);
    // CustomScrollView lazy — section produk (Terlaris) bisa di bawah
    // fold viewport ponsel (390x844); scroll dulu supaya kartunya ter-build.
    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -600),
    );
    await pumpBounded(tester, 3);
    expect(find.textContaining('Produk Cache Uji'), findsWidgets);
    expect(find.textContaining('Belum berhasil memuat'), findsNothing);
    await unmount(tester);
  });

  testWidgets('pull-to-refresh me-retry fetch produk (bypass throttle)',
      (tester) async {
    var calls = 0;
    homeSnapshotStore.debugProductsFetcher = () async {
      calls++;
      return [productJson('p1', 'Produk Uji')];
    };
    stubOthersEmpty();
    await mountHome(tester, suppressOverflowErrors);
    expect(calls, 1); // refresh dari initState
    final indicator = tester.widget<NataloPawRefreshIndicator>(
      find.byType(NataloPawRefreshIndicator),
    );
    // Panggil handler langsung — gesture pull dengan indikator custom
    // pinContent tidak deterministik di test.
    await indicator.onRefresh();
    await pumpBounded(tester);
    // force:true bypass soft-throttle 30s → fetch benar-benar diulang.
    expect(calls, 2);
    await unmount(tester);
  });
}
