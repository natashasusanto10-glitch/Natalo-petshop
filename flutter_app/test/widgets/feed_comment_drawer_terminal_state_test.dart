// Regression tests untuk kontrak terminal-state comment drawer Feed
// (2026-07-16-feed-comment-drawer-terminal-state-reliability-design.md).
//
// Kontrak inti: drawer hanya punya tiga resting state — closed, initial
// (0.60), expanded — dan SETIAP jalur pelepasan pointer (release, cancel,
// recognizer mati mid-gesture) wajib berakhir di salah satunya. Tidak boleh
// ada sliver partial ataupun keadaan invisible-tapi-terbuka yang mengunci
// overlay Feed.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_action_rail.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/feed_screen.dart';
import 'package:natalo_petshop_flutter/state/feed_comment_session_store.dart';
import 'package:natalo_petshop_flutter/utils/android_back_overlays.dart';
import 'package:natalo_petshop_flutter/widgets/feed_comment_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

FeedPost _photoPost() => FeedPost.fromJson({
      'id': 'terminal-state-regression',
      'slug': 'terminal-state-regression',
      'kind': 'PHOTO_CAROUSEL',
      'mediaItems': [
        {
          'id': 'photo-media-1',
          'mediaType': 'image',
          'mediaUrl': 'https://example.com/photo-1.jpg',
          'sortOrder': 0,
        },
      ],
      'author': {'id': 'author-1', 'name': 'Tester'},
      'caption': 'Caption uji terminal state',
      'createdAt': '2026-07-15T00:00:00.000Z',
    });

/// Host standalone FeedReelsCommentSurface 400x900. Drawer initial 0.60 →
/// tepi atas sheet di y=360. Batas layout ultra-compact 104px ≈ extent 0.115.
Future<void> _pumpSurface(
  WidgetTester tester, {
  required ValueNotifier<bool> open,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: open,
          builder: (context, isOpen, _) => FeedReelsCommentSurface(
            post: _photoPost(),
            open: isOpen,
            onClosed: () => open.value = false,
            child: const ColoredBox(color: Colors.orange),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _openSurface(WidgetTester tester, ValueNotifier<bool> open) async {
  open.value = true;
  // Rantai dua postFrame: didUpdateWidget → _openDrawer (setState +
  // postFrame) → _animateExtent baru MULAI di akhir frame kedua.
  await tester.pump();
  await tester.pump();
  // Animasi open 260ms + settle.
  await tester.pump(const Duration(milliseconds: 320));
  await tester.pump(const Duration(milliseconds: 40));
  expect(find.byType(FeedCommentSheet), findsOneWidget);
  // Drawer WAJIB sudah mendarat di initial sebelum gesture dimulai — tanpa
  // ini gesture balapan dengan animasi open dan hasil test tak deterministik.
  expect(
    tester.getTopLeft(find.byType(FeedCommentSheet)).dy,
    closeTo(900 * (1 - feedCommentInitialExtent), 2),
  );
  // PENTING: biarkan open watchdog 700ms kedaluwarsa sebagai no-op (extent
  // sudah di 0.60) SEBELUM gesture apa pun. Tanpa ini, drag yang menurunkan
  // extent < dismiss bisa "ditutup" oleh _failOpen watchdog — menutupi
  // mekanisme yang sebenarnya diuji (guard/release-settle). Dibuktikan via
  // mutation testing: tanpa langkah ini, menghapus guard+backstop pun test
  // tetap lulus.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(FeedCommentSheet), findsOneWidget,
      reason: 'watchdog open harus no-op pada extent initial');
}

/// Pump bebas-timer: cukup lama untuk animasi close (220ms) + watchdog close
/// (268ms) + backstop stranded-settle (160ms + 90ms resample) selesai semua.
Future<void> _settlePumps(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Offset _handleCenter(WidgetTester tester) {
  final handle = find.byKey(const ValueKey('feed-comment-drag-handle'));
  expect(handle, findsOneWidget);
  return tester.getCenter(handle);
}

void main() {
  setUp(() {
    feedCommentSessionStore.clear();
    resetAndroidBackOverlays();
  });
  tearDown(() {
    feedCommentSessionStore.clear();
    resetAndroidBackOverlays();
  });

  group('stable shell + release policy (handle)', () {
    testWidgets(
        'drag handle menembus batas 104px dalam SATU gesture → recognizer '
        'selamat, drag-end fire, drawer MENUTUP (bukan sliver)',
        (tester) async {
      final open = ValueNotifier<bool>(false);
      addTearDown(open.dispose);
      await _pumpSurface(tester, open: open);
      await _openSurface(tester, open);

      // Sheet top 360; tarik handle ke bawah 480px → extent ~0.067 (60px
      // tinggi — di bawah batas 104px). Dulu: root swap Column→ListView
      // meng-unmount recognizer di tengah gesture → dragEnd tak pernah fire
      // → sheet tertinggal sebagai sliver.
      final handleFinder =
          find.byKey(const ValueKey('feed-comment-drag-handle'));
      final handleElementBefore = tester.element(handleFinder);
      final gesture = await tester.startGesture(_handleCenter(tester));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump(const Duration(milliseconds: 16));
      }
      // MID-GESTURE, sudah di bawah 104px: shell stabil = element handle
      // TIDAK berganti identity (pin eksplisit — outcome "tertutup" saja
      // bisa dipenuhi mekanisme pertahanan lain, dibuktikan via mutation).
      expect(
          identical(tester.element(handleFinder), handleElementBefore), isTrue,
          reason: 'element drag handle wajib selamat melintasi batas 104px');
      // Recognizer masih hidup: sheet masih mengikuti jari setelah melintasi
      // batas (drag mati = top membeku walau jari terus bergerak).
      final topBeforeExtraMove =
          tester.getTopLeft(find.byType(FeedCommentSheet)).dy;
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump(const Duration(milliseconds: 16));
      final topAfterExtraMove =
          tester.getTopLeft(find.byType(FeedCommentSheet)).dy;
      expect((topBeforeExtraMove - topAfterExtraMove).abs(), greaterThan(30),
          reason: 'sheet wajib tetap mengikuti jari setelah melintasi 104px');
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await _settlePumps(tester);

      expect(tester.takeException(), isNull,
          reason: 'melintasi 104px tidak boleh overflow/flash exception');
      expect(find.byType(FeedCommentSheet), findsNothing,
          reason: 'release jauh di bawah dismiss → resting state = closed');
      expect(open.value, isFalse);
    });

    testWidgets(
        'pointer cancel di handle = release velocity nol → kembali ke initial '
        '(bukan partial extent)', (tester) async {
      final open = ValueNotifier<bool>(false);
      addTearDown(open.dispose);
      await _pumpSurface(tester, open: open);
      await _openSurface(tester, open);

      // Tarik turun 100px → extent ~0.49 (di atas dismiss 0.30), lalu CANCEL.
      final gesture = await tester.startGesture(_handleCenter(tester));
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.cancel();
      await _settlePumps(tester);

      expect(find.byType(FeedCommentSheet), findsOneWidget,
          reason: 'cancel di atas dismiss → resting state = initial');
      final sheetTop = tester.getTopLeft(find.byType(FeedCommentSheet)).dy;
      expect(sheetTop, closeTo(900 * (1 - feedCommentInitialExtent), 2),
          reason: 'extent wajib kembali TEPAT ke detent initial 0.60');
    });

    testWidgets(
        'pointer cancel di bawah dismiss → drawer menutup (policy sama '
        'dengan release)', (tester) async {
      final open = ValueNotifier<bool>(false);
      addTearDown(open.dispose);
      await _pumpSurface(tester, open: open);
      await _openSurface(tester, open);

      // Tarik turun 320px → extent ~0.24 (di bawah dismiss 0.30), lalu CANCEL.
      final gesture = await tester.startGesture(_handleCenter(tester));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.cancel();
      await _settlePumps(tester);

      expect(find.byType(FeedCommentSheet), findsNothing);
      expect(open.value, isFalse);
    });

    testWidgets('release di atas midpoint → expanded (detent max)',
        (tester) async {
      final open = ValueNotifier<bool>(false);
      addTearDown(open.dispose);
      await _pumpSurface(tester, open: open);
      await _openSurface(tester, open);

      // Tarik NAIK 260px → extent ~0.89 (midpoint (0.6+0.96)/2 = 0.78).
      final gesture = await tester.startGesture(_handleCenter(tester));
      for (var i = 0; i < 13; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await _settlePumps(tester);

      expect(find.byType(FeedCommentSheet), findsOneWidget);
      final sheetTop = tester.getTopLeft(find.byType(FeedCommentSheet)).dy;
      // maxExtent = clamp(1 - topInset/host) = 0.96 (topInset 0 di test env)
      // → top = 900 * 0.04 = 36.
      expect(sheetTop, closeTo(36, 2),
          reason: 'release di atas midpoint → resting state = expanded');
    });
  });

  group('terminal-extent guard + stranded settle (content drag)', () {
    testWidgets(
        'content-drag dari area komentar dilepas di bawah dismiss → drawer '
        'MENUTUP via guard min-extent, onClosed tepat sekali', (tester) async {
      final open = ValueNotifier<bool>(false);
      addTearDown(open.dispose);
      var closedCount = 0;
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: open,
              builder: (context, isOpen, _) => FeedReelsCommentSurface(
                post: _photoPost(),
                open: isOpen,
                onClosed: () {
                  closedCount++;
                  open.value = false;
                },
                child: const ColoredBox(color: Colors.orange),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await _openSurface(tester, open);

      // Mulai drag DI DALAM area komentar (bukan handle) — dimiliki
      // DraggableScrollableSheet. Turun 340px → extent ~0.22 (masih di atas
      // batas 104px), lalu lepas: ballistic framework snap ke min (0.0,
      // implied snap size) → guard terminal menutup. Dulu (tanpa guard):
      // sheet diam di extent 0 sementara _mountedDrawer tetap true →
      // invisible-open, overlay terkunci.
      final gesture =
          await tester.startGesture(const Offset(200, 520)); // area list
      for (var i = 0; i < 17; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await _settlePumps(tester);
      await _settlePumps(tester);

      expect(find.byType(FeedCommentSheet), findsNothing,
          reason: 'content-drag release di bawah dismiss wajib menutup — '
              'paritas dengan handle (Acceptance #4, perilaku IG Reels)');
      expect(closedCount, 1, reason: 'close lifecycle tepat satu kali');
      expect(open.value, isFalse);
    });

    testWidgets(
        'content-drag menembus batas 104px (scrollable mati mid-gesture) → '
        'backstop stranded-settle menutup, TIDAK ada sliver', (tester) async {
      final open = ValueNotifier<bool>(false);
      addTearDown(open.dispose);
      await _pumpSurface(tester, open: open);
      await _openSurface(tester, open);

      // Turun 470px → extent ~0.077 (69px — DI BAWAH batas 104px). Body
      // di-swap ke ultra-compact → scrollable pemilik drag ikut unmount →
      // drag mati tanpa ballistic. Setelah pointer dilepas, backstop
      // stranded-settle wajib mendeteksi extent diam di bawah initial dan
      // menyelesaikannya lewat policy bersama (0.077 ≤ 0.30 → close).
      final gesture = await tester.startGesture(const Offset(200, 520));
      for (var i = 0; i < 24; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await _settlePumps(tester);
      await _settlePumps(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(FeedCommentSheet), findsNothing,
          reason: 'sheet tidak boleh tertinggal sebagai sliver ultra-compact');
      expect(open.value, isFalse);
    });
  });

  group('Android back parity foto/carousel (FeedScreen)', () {
    Future<void> pumpFeedScreen(WidgetTester tester) async {
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'feed_offline_cache_v2::guest': jsonEncode([_photoPost().toJson()]),
      });

      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/member/login': (_) => const Scaffold(body: Text('Login')),
          },
          home: const FeedScreen(),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.bySemanticsLabel('Komentar').evaluate().isNotEmpty) break;
      }
      expect(find.bySemanticsLabel('Komentar'), findsOneWidget);
    }

    Future<void> openDrawerViaRail(WidgetTester tester) async {
      final rail = tester.widget<FeedActionRail>(find.byType(FeedActionRail));
      rail.onComment!.call();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.byType(FeedCommentSheet), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(FeedCommentSheet)).dy,
        closeTo(900 * (1 - feedCommentInitialExtent), 2),
        reason: 'drawer wajib settle di initial sebelum aksi berikutnya',
      );
      // Biarkan open watchdog 700ms kedaluwarsa sebagai no-op (lihat
      // _openSurface).
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(FeedCommentSheet), findsOneWidget);
    }

    /// PageView vertikal utama Feed — physics-nya adalah proxy lock overlay:
    /// NeverScrollable saat drawer aktif, pulih setelah close.
    PageView verticalFeedPager(WidgetTester tester) {
      return tester
          .widgetList<PageView>(find.byType(PageView))
          .firstWhere((p) => p.scrollDirection == Axis.vertical);
    }

    testWidgets(
        'Android back menutup drawer foto (bukan pindah tab), lalu back '
        'ownership dilepas & paging feed pulih setelah close', (tester) async {
      await pumpFeedScreen(tester);

      // Baseline: paging vertikal aktif sebelum drawer dibuka.
      expect(verticalFeedPager(tester).physics,
          isNot(isA<NeverScrollableScrollPhysics>()));

      await openDrawerViaRail(tester);

      // Lease lock aktif: paging vertikal terkunci selama drawer terbuka.
      expect(verticalFeedPager(tester).physics,
          isA<NeverScrollableScrollPhysics>(),
          reason: 'drawer terbuka wajib mengunci paging feed');

      // Back press pertama: WAJIB dikonsumsi drawer.
      expect(consumeAndroidBackOverlay(), isTrue,
          reason: 'drawer foto wajib memiliki Android back saat aktif');
      await _settlePumps(tester);

      expect(find.byType(FeedCommentSheet), findsNothing,
          reason: 'back menutup drawer');

      // Setelah close selesai, closer wajib sudah dilepas — back berikutnya
      // jatuh ke handler default (tab nav), bukan ditelan closer basi.
      expect(consumeAndroidBackOverlay(), isFalse,
          reason: 'tidak boleh ada closer basi setelah drawer tertutup');

      // Lease dilepas tepat lewat onClosed: paging vertikal pulih.
      expect(verticalFeedPager(tester).physics,
          isNot(isA<NeverScrollableScrollPhysics>()),
          reason: 'paging feed wajib pulih setelah drawer tertutup');
    });

    testWidgets('reopen setelah close via Android back kembali ke initial',
        (tester) async {
      await pumpFeedScreen(tester);
      await openDrawerViaRail(tester);

      expect(consumeAndroidBackOverlay(), isTrue);
      await _settlePumps(tester);
      expect(find.byType(FeedCommentSheet), findsNothing);

      // Reopen — wajib berhasil dan mendarat di extent initial.
      await openDrawerViaRail(tester);
      final sheetTop = tester.getTopLeft(find.byType(FeedCommentSheet)).dy;
      expect(sheetTop, closeTo(900 * (1 - feedCommentInitialExtent), 2));

      // Bersihkan: tutup lagi supaya tidak ada timer/closer tersisa.
      expect(consumeAndroidBackOverlay(), isTrue);
      await _settlePumps(tester);
      expect(find.byType(FeedCommentSheet), findsNothing);
    });
  });
}
