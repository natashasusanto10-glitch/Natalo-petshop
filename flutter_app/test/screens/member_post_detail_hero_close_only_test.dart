// Hero fires ONLY on close (pop), never on open (push). Device testing
// showed push's native slide + Hero flying media at once reads as "layered"
// motion; pop's fly-back-to-tile stays as-is (confirmed good on device).
//
// Mechanism: viewer's `_wrapHero` (member_post_detail_screen.dart) now
// gates PostHero presence on the pushed route's own transition animation
// status — present except while that animation is actively driving FORWARD
// (the push drive). Grid tile keeps its Hero unconditionally; with no
// viewer-side Hero to pair with during push, Flutter finds no match and
// renders a plain (benign) slide — proven-safe by the existing "no pair"
// behavior this branch already relies on for deep-link/no-scope cases.
//
// Same conventions as member_screen_hero_open_test.dart: mock prefs, bounded
// pump loops (no pumpAndSettle — shimmer never settles).

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

  bool activeTagPresent(WidgetTester tester) {
    return tester
        .widgetList<Hero>(find.byType(Hero))
        .any((h) => h.tag == 'post-hero/profile-all/p1');
  }

  int activeTagCount(WidgetTester tester) {
    return tester
        .widgetList<Hero>(find.byType(Hero))
        .where((h) => h.tag == 'post-hero/profile-all/p1')
        .length;
  }

  testWidgets(
      'push (buka viewer): TIDAK ada flight — hanya SATU Hero (tile grid) '
      'ber-tag aktif selama transisi push berjalan', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {'/member/login': (_) => const Scaffold(body: Text('Login'))},
        home: const MemberScreen(),
      ),
    );
    await pumpBounded(tester);

    // Sanity: tile grid punya Hero sebelum tap.
    expect(activeTagCount(tester), 1);

    await tester.tap(find.byWidgetPredicate(
      (w) => w is Hero && w.tag == 'post-hero/profile-all/p1',
    ));
    // Mid-push: satu frame pendek, JAUH sebelum transisi (~300ms) selesai.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // Kalau viewer juga mengekspos PostHero ber-tag sama selagi push masih
    // berjalan (forward), Flutter akan MENERBANGKAN media (dua Hero
    // berpasangan) — persis motion "layered" yang mau dihindari. Harus
    // cuma SATU Hero ber-tag itu di tree (tile grid saja, viewer belum
    // ekspos PostHero-nya sampai push selesai).
    expect(activeTagCount(tester), 1,
        reason: 'selama push berjalan seharusnya tidak ada pasangan Hero '
            '(tanpa flight) — cuma tile grid yang punya Hero ber-tag ini');

    // Selesaikan transisi push.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(MemberPostDetailScreen), findsOneWidget);

    // Setelah push selesai (status completed), viewer BOLEH mengekspos
    // PostHero-nya (harmless — halaman sudah penuh masuk, tidak ada
    // flight lagi karena tidak ada transisi berjalan).
    expect(activeTagPresent(tester), isTrue,
        reason: 'setelah push selesai, viewer tetap punya PostHero aktif '
            '(dibutuhkan supaya pop bisa fly-back)');
  });

  testWidgets(
      'pop (tutup viewer): flight TETAP terjadi — dua Hero berpasangan '
      'selama transisi pop berjalan', (tester) async {
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

    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.pop();
    // Mid-pop: satu frame pendek, JAUH sebelum transisi selesai.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // Selama pop, KEDUA sisi (tile grid + viewer) harus tetap mengekspos
    // Hero ber-tag sama supaya Flutter menerbangkan media kembali ke tile
    // — perilaku fly-back-to-tile yang sudah dikonfirmasi bagus di device.
    expect(activeTagCount(tester), 2,
        reason: 'selama pop berjalan Hero HARUS berpasangan (flight aktif) '
            '— fly-back-to-tile tidak boleh regresi');

    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  });
}
