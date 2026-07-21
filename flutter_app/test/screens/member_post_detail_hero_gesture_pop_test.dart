// Regresi: hero HARUS aktif (berpasangan, siap fly-back) selama gesture
// back-swipe iOS berlangsung — bukan cuma saat pop terprogram
// (`navigator.pop()`, sudah dites di
// member_post_detail_hero_close_only_test.dart).
//
// Root cause: `_CupertinoBackGestureController.dragUpdate` menulis
// `controller.value -= delta` LANGSUNG (bukan lewat `animateTo`/`reverse`).
// `AnimationController.value` setter menghitung status dari `_direction`
// TERAKHIR (masih `forward` dari push sebelumnya) — jadi selama SELURUH
// drag, `animation.status` tetap `forward`. Gate lama (`_HeroFlightGate`)
// hanya baca status route → salah baca drag itu sebagai "push sedang
// jalan" → Hero tetap inert → fly-back tidak pernah terjadi untuk gesture
// close (paling umum di iOS).
//
// Fix: OR-kan dengan `navigator.userGestureInProgressNotifier`. Test ini
// simulasikan gesture pop TANPA GestureDetector sungguhan (tak perlu iOS
// platform variant) — panggil `navigator.didStartUserGesture()` lalu tulis
// `.value` route controller langsung persis seperti `dragUpdate`, sama
// seperti reproduksi asli.
//
// Same conventions as member_post_detail_hero_close_only_test.dart: mock
// prefs, bounded pump loops (no pumpAndSettle — shimmer never settles).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/screens/member_screen.dart';
import 'package:natalo_petshop_flutter/state/member_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  FeedPost post(String id) => FeedPost(
        id: id,
        slug: id,
        kind: 'PHOTO',
        videoUrl: '',
        thumbnailUrl: 'https://example.com/$id.jpg',
        author: const FeedAuthor(id: 'owner-1', name: 'Natasha'),
        createdAt: DateTime(2026, 1, 1),
        status: 'PUBLISHED',
      );

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    memberStore.setProfile(
      const MemberProfile(
        id: 'owner-1',
        name: 'Natasha',
        username: 'natasha_s',
        role: 'CUSTOMER',
        bio: 'Cat mom',
        followersCount: 1,
        followingCount: 1,
      ),
    );
    debugMyPostsFetcher = ({String filter = 'all', String? cursor}) async {
      return FeedPage(items: [post('p1'), post('p2')], nextCursor: null);
    };
  });

  tearDown(() async {
    debugMyPostsFetcher = null;
    await memberStore.logout();
  });

  Future<void> pumpBounded(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
  }

  int activeTagCount(WidgetTester tester) {
    return tester
        .widgetList<Hero>(find.byType(Hero))
        .where((h) => h.tag == 'post-hero/profile-all/p1')
        .length;
  }

  bool activeTagPresent(WidgetTester tester) {
    return tester
        .widgetList<Hero>(find.byType(Hero))
        .any((h) => h.tag == 'post-hero/profile-all/p1');
  }

  testWidgets(
      'gesture-pop (edge-swipe iOS): Hero TETAP berpasangan mid-drag walau '
      'status route masih forward (side-effect controller.value setter)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {'/member/login': (_) => const Scaffold(body: Text('Login'))},
        home: const MemberScreen(),
      ),
    );
    await pumpBounded(tester);

    await tester.tap(find.byWidgetPredicate(
      (w) => w is Hero && w.tag == 'post-hero/profile-all/p1',
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(MemberPostDetailScreen), findsOneWidget);
    // Push selesai: status completed, gate sudah active=true (idle) — sama
    // seperti sanity check di member_post_detail_hero_close_only_test.dart.
    expect(activeTagPresent(tester), isTrue,
        reason: 'setelah push selesai, viewer tetap punya PostHero aktif');

    final navigatorState =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    final route =
        ModalRoute.of(tester.element(find.byType(MemberPostDetailScreen)))!;
    // `route.controller` is @protected (only usable inside TransitionRoute
    // subclasses) — `route.animation` is a wrapping `ProxyAnimation`, NOT
    // the real controller, so it can't be cast back. Reaching into the
    // protected member is the only way from test code to drive `.value`
    // directly the way `_CupertinoBackGestureController.dragUpdate` does.
    // ignore: invalid_use_of_protected_member
    final controller = route.controller!;

    // Simulasi `_CupertinoBackGestureController`: constructor memanggil
    // didStartUserGesture() SEBELUM drag pertama.
    navigatorState.didStartUserGesture();
    // dragUpdate: controller.value -= delta — status jatuh ke `forward`
    // sebagai side-effect (BUKAN reverse), reproduksi persis bug asli.
    controller.value -= 0.3;
    expect(controller.status, AnimationStatus.forward,
        reason: 'reproduksi bug: value-setter langsung membuat status '
            'forward, bukan reverse, selama drag');

    // Resync di-defer satu frame (sama seperti listener status lain).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(activeTagCount(tester), 2,
        reason: 'selama gesture-pop drag, Hero HARUS tetap berpasangan '
            '(userGestureInProgress meng-override status=forward) — kalau '
            'gagal, cuma tile grid yang punya Hero (fly-back mati untuk '
            'gesture close iOS)');

    // Bersihkan: batalkan gesture (kembali ke completed) supaya tidak ada
    // exception tersisa saat widget dibuang.
    navigatorState.didStopUserGesture();
    controller.value = 1.0;
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  });
}
