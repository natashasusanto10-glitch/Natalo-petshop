// Model IG/TikTok (rewrite): route viewer memakai transisi FADE (bukan slide
// native), jadi Hero terbang tile↔slot pada KEDUA arah — push (buka) DAN pop
// (tutup) — tanpa gating apa pun. Invariant jujur: shuttle Hero
// (`post-hero-shuttle`) muncul di Overlay SAAT push berjalan DAN saat pop
// berjalan (bukti flight NYATA tertangkap di dua arah).
//
// Menggantikan member_post_detail_hero_close_only_test.dart (konsep
// close-only dibuang). Konvensi sama: mock prefs, bounded pump loops (no
// pumpAndSettle — shimmer never settles).

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

  bool shuttleVisible(WidgetTester tester) =>
      find.byKey(const ValueKey('post-hero-shuttle')).evaluate().isNotEmpty;

  testWidgets(
      'hero terbang di KEDUA arah: shuttle muncul saat push DAN saat pop',
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

    // ── PUSH: shuttle NYATA harus muncul mid-transisi (flight aktif) ──
    var sawShuttleDuringPush = false;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (shuttleVisible(tester)) {
        sawShuttleDuringPush = true;
        break;
      }
    }
    expect(sawShuttleDuringPush, isTrue,
        reason: 'push harus menerbangkan media (shuttle) — hero dua-arah');

    // Selesaikan push.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(MemberPostDetailScreen), findsOneWidget);
    expect(shuttleVisible(tester), isFalse,
        reason: 'push selesai — tidak ada flight lagi');

    // ── POP: shuttle NYATA harus muncul lagi mid-transisi (fly-back) ──
    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.pop();
    var sawShuttleDuringPop = false;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (shuttleVisible(tester)) {
        sawShuttleDuringPop = true;
        break;
      }
    }
    expect(sawShuttleDuringPop, isTrue,
        reason: 'pop harus menerbangkan media kembali ke tile — fly-back');

    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  });
}
