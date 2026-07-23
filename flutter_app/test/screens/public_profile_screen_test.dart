import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_viewer_route.dart';
import 'package:natalo_petshop_flutter/features/feed/video/post_video_warm_handoff.dart';
import 'package:natalo_petshop_flutter/features/feed/video/video_player_session.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/screens/public_profile_screen.dart';
import 'package:natalo_petshop_flutter/services/profile_service.dart';
import 'package:natalo_petshop_flutter/widgets/liquid_glass.dart';
import 'package:natalo_petshop_flutter/widgets/natalo_paw_refresh_indicator.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_chrome_overlay.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    addTearDown(() {
      VisibilityDetectorController.instance.updateInterval =
          const Duration(milliseconds: 500);
    });
  });

  testWidgets('entry refreshes chat config exactly once', (tester) async {
    var fetchCount = 0;
    const result = PublicProfileResult(
      profile: PublicProfile(
        id: 'creator-1',
        name: 'Creator',
        username: 'creator',
        isOwner: true,
      ),
      posts: [],
    );
    final screen = PublicProfileScreen(
      username: 'creator',
      initialResult: result,
      fetchChatConfig: () async => fetchCount++,
    );

    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpWidget(MaterialApp(home: screen));

    expect(fetchCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('public profile tile keys stay stable and scoped to their content tab',
      () {
    final keys = ProfilePostOriginKeyCache();

    final allTile = keys.forPost(PublicProfileContentFilter.all, 'video-1');

    expect(
      keys.forPost(PublicProfileContentFilter.all, 'video-1'),
      same(allTile),
    );
    expect(
      keys.forPost(PublicProfileContentFilter.video, 'video-1'),
      isNot(same(allTile)),
    );
  });

  testWidgets(
      'video tile has PostHero scoped to username+content, opens via PostViewerRoute and returns',
      (tester) async {
    final post = FeedPost.fromJson({
      'id': 'video-1',
      'slug': 'video-1',
      'kind': 'USER_VIDEO',
      'videoUrl': 'https://example.com/video-1.mp4',
      'thumbnailUrl': 'https://example.com/video-1.jpg',
      'author': {'id': 'creator-1', 'name': 'Creator'},
      'createdAt': DateTime(2026).toIso8601String(),
    });
    final result = PublicProfileResult(
      profile: const PublicProfile(
        id: 'creator-1',
        name: 'Creator',
        username: 'creator',
        isOwner: true,
      ),
      posts: [post],
    );
    var disposeCount = 0;
    final warmSession = VideoPlayerSession(
      url: post.videoPlaybackUrl,
      debugInitAttempt: (_) async {},
      debugDisposePlayer: () async => disposeCount++,
    );
    final warmHandoff = PostVideoWarmHandoff(
      postId: post.id,
      url: post.videoPlaybackUrl,
      hasAudio: post.hasAudio != false,
      session: warmSession,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PublicProfileScreen(
          username: 'creator',
          initialResult: result,
          warmHandoffFactory: (_) => warmHandoff,
          fetchChatConfig: _noOpFetch,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Hero && w.tag == 'post-hero/publicProfile-creator-all/video-1',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('profile-post-video-1')));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(MemberPostDetailScreen), findsOneWidget);
    final detailState =
        tester.state(find.byType(MemberPostDetailScreen)) as dynamic;
    expect(detailState.debugVideoCoordinator.sessionFor(post.id),
        same(warmSession));
    expect(disposeCount, 0);

    Navigator.of(tester.element(find.byType(MemberPostDetailScreen))).pop();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(tester.takeException(), isNull);
    expect(find.byType(MemberPostDetailScreen), findsNothing);
    expect(find.byKey(const ValueKey('profile-post-video-1')), findsOneWidget);
  });

  testWidgets(
      'real scroll collapses and reverses chrome without resetting content',
      (tester) async {
    final post = FeedPost.fromJson({
      'id': 'post-1',
      'slug': 'post-1',
      'kind': 'USER_VIDEO',
      'videoUrl': 'https://example.com/post-1.mp4',
      'thumbnailUrl': 'not-a-network-url',
      'author': {'id': 'creator-1', 'name': 'Creator'},
      'createdAt': DateTime(2026).toIso8601String(),
    });
    final result = PublicProfileResult(
      profile: const PublicProfile(
        id: 'creator-1',
        name: 'Creator',
        username: 'creator',
        bio: 'Profil kreator',
        isOwner: true,
      ),
      posts: [post],
    );

    await tester.pumpWidget(MaterialApp(
      home: PublicProfileScreen(
        username: 'creator',
        initialResult: result,
        fetchChatConfig: _noOpFetch,
      ),
    ));
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.bottomNavigationBar, isNull);
    expect(
        find.byKey(const Key('public_profile_grid_underlay')), findsOneWidget);
    expect(find.byType(PublicProfileChromeOverlay), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-post-post-1')), findsOneWidget);

    await tester.drag(find.byType(TabBarView), const Offset(-420, 0));
    await tester.pumpAndSettle();

    final videoSelected = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const Key('public_tab_video_pill')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(videoSelected.properties.selected, isTrue);

    final scrollView = find.byType(NestedScrollView);
    final dragPoint = tester.getBottomLeft(scrollView) + const Offset(200, -80);
    await tester.dragFrom(dragPoint, const Offset(0, -360));
    await tester.pump();
    // Tab labels now render inside PublicProfileIdentityTabHeader's sliver
    // (Key('public_profile_tab_group')), not inside PublicProfileChromeOverlay
    // (which only owns the toolbar row since Task 2's refactor).
    final tabGroup = find.byKey(const Key('public_profile_tab_group'));
    expect(find.descendant(of: tabGroup, matching: find.text('Postingan')),
        findsOneWidget);
    expect(find.descendant(of: tabGroup, matching: find.text('Video')),
        findsOneWidget);
    expect(find.descendant(of: tabGroup, matching: find.text('Ditandai')),
        findsOneWidget);

    final selected = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const Key('public_tab_video_pill')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(selected.properties.selected, isTrue);

    await tester.dragFrom(dragPoint, const Offset(0, 360));
    await tester.pump();
    final reversedSelected = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const Key('public_tab_video_pill')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(reversedSelected.properties.selected, isTrue);

    await tester.tap(find.byKey(const Key('public_tab_posts_pill')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('profile-post-post-1')), findsOneWidget);
  });

  testWidgets('real grid enters glass chrome before full collapse',
      (tester) async {
    final posts = List.generate(18, (index) {
      return FeedPost.fromJson({
        'id': 'geometry-$index',
        'slug': 'geometry-$index',
        'kind': 'USER_VIDEO',
        'videoUrl': 'https://example.com/geometry-$index.mp4',
        'thumbnailUrl': 'not-a-network-url',
        'author': {'id': 'creator-1', 'name': 'Creator'},
        'createdAt': DateTime(2026).toIso8601String(),
      });
    });
    final result = PublicProfileResult(
      profile: const PublicProfile(
        id: 'creator-1',
        name: 'Creator',
        username: 'creator',
        bio: 'Profil kreator',
        isOwner: true,
      ),
      posts: posts,
    );

    await tester.pumpWidget(MaterialApp(
      home: PublicProfileScreen(
        username: 'creator',
        initialResult: result,
        fetchChatConfig: _noOpFetch,
      ),
    ));
    await tester.pump();

    final overlayFinder = find.byType(PublicProfileChromeOverlay);
    PublicProfileChromeOverlay overlay() =>
        tester.widget<PublicProfileChromeOverlay>(overlayFinder);
    final nestedScrollables = find.descendant(
      of: find.byType(NestedScrollView),
      matching: find.byType(Scrollable),
    );
    final outerPosition =
        tester.state<ScrollableState>(nestedScrollables.first).position;
    final metrics = overlay().metrics;
    // The header sliver list now leads with a PINNED spacer reserving
    // topPadding+toolbarHeight (fix for the tab-bar-under-status-bar
    // regression) — that spacer consumes real scroll extent before the
    // identity+tab sliver's own shrink begins, so every offset that targets
    // "N% through the identity shrink" must add this inset first.
    final headerLeadInset = metrics.topPadding + metrics.toolbarHeight;

    // Midway through the identity shrink — well before the grid can reach
    // the chrome — the glass must already be gradually fading in (never an
    // instant snap from 0 straight to full opacity).
    final midOffset = headerLeadInset + metrics.identityHeight * 0.75;
    outerPosition.jumpTo(midOffset);
    await tester.pump();
    expect(overlay().t, closeTo(0.75, 0.01));
    final midOpacities = tester
        .widgetList<LiquidGlass>(find.byType(LiquidGlass))
        .map((glass) => glass.opacity)
        .toList();
    expect(midOpacities, isNotEmpty);
    expect(midOpacities.any((o) => o > 0 && o < 1), isTrue);

    // One logical pixel beyond identity collapse is the first moment the real
    // grid enters beneath the collapsed chrome. Chrome and the tab bar now
    // share the exact same shrink progress `t` (the fix for the old
    // independent-timing bug that used to let the chrome glass lag behind),
    // so by the time t reaches 1 the glass has ALREADY finished fading in —
    // there is no frame where the grid is visible beneath a still-partial
    // chip.
    final intermediateOffset = headerLeadInset + metrics.identityHeight + 1;
    outerPosition.jumpTo(intermediateOffset);
    await tester.pump();
    final intermediateTile = tester.getRect(
      find.byKey(const ValueKey('profile-post-geometry-0')),
    );
    expect(overlay().t, 1.0);
    expect(intermediateTile.top, lessThan(metrics.collapsedChromeHeight));
    expect(intermediateTile.bottom, greaterThan(0));
    final intermediateOpacities = tester
        .widgetList<LiquidGlass>(find.byType(LiquidGlass))
        .map((glass) => glass.opacity)
        .toList();
    expect(intermediateOpacities, isNotEmpty);
    expect(intermediateOpacities.every((o) => o == 0 || o >= 0.99), isTrue);

    outerPosition.jumpTo(metrics.scrollSpaceHeight);
    await tester.pump();
    final collapsedTile = tester.getRect(
      find.byKey(const ValueKey('profile-post-geometry-0')),
    );
    expect(overlay().t, 1.0);
    expect(collapsedTile.top, lessThanOrEqualTo(0.5));
    expect(collapsedTile.bottom, greaterThan(0));
    expect(find.byType(BackdropFilter), findsWidgets);
    final collapsedOpacities = tester
        .widgetList<LiquidGlass>(find.byType(LiquidGlass))
        .map((glass) => glass.opacity)
        .toList();
    expect(collapsedOpacities.any((o) => o >= 0.99), isTrue);
  });

  testWidgets(
      'tab Ditandai di profil publik langsung kosong tanpa network call',
      (tester) async {
    const result = PublicProfileResult(
      profile: PublicProfile(
        id: 'creator-1',
        name: 'Creator',
        username: 'creator',
        isOwner: false,
      ),
      posts: [],
    );
    await tester.pumpWidget(const MaterialApp(
      home: PublicProfileScreen(
        username: 'creator',
        initialResult: result,
        fetchChatConfig: _noOpFetch,
      ),
    ));
    await tester.pump();

    // Tap langsung tab "Ditandai" via pill key (tooltip sudah dihapus di
    // Task 3). Bukan drag TabBarView — drag gesture pada PageView biasanya
    // cuma pindah satu halaman per drag, tidak reliable untuk lompat dari
    // tab 0 ke tab 2 dalam satu gerakan.
    await tester.tap(find.byKey(const Key('public_tab_tagged_pill')));
    // Bounded pump (bukan pumpAndSettle) — tab 0->2 loncat lebih dari satu
    // index, jadi TabBarView lewat mekanisme internal Flutter
    // _warpToNonAdjacentTab: jump ke halaman tetangga dulu lalu animate ke
    // tujuan selama kTabScrollDuration (~300ms). Pump pertama (tanpa durasi)
    // WAJIB ada duluan supaya ticker TabController mengambil tick pertamanya
    // (yang menetapkan start-time animasi, elapsed=0) — baru pump kedua
    // dengan durasi 400ms (> 300ms) bisa menghitung elapsed time yang benar
    // dan membawa animasi tab sampai selesai, hingga halaman "Ditandai"
    // ter-mount. 400ms tetap jauh lebih pendek dari network round-trip
    // nyata. Ini penting: pumpAndSettle akan ikut menunggu fetch nyata
    // selesai/timeout kalau guard "jangan fetch" untuk filter shoppable
    // dilepas, sehingga assertion di bawah tidak lagi membuktikan apa-apa.
    // Dengan bounded pump, checkpoint ini bisa membedakan kedua kasus secara
    // deterministik: guard branch untuk shoppable di _activateContent tidak
    // pernah menyentuh contentState.loading, sedangkan _loadSelectedContent
    // (fetch asli) set loading = true secara sinkron sebelum await pertama.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('Belum ada postingan yang menandai akun ini'),
      findsOneWidget,
    );
  });

  testWidgets('refresh saat tab Ditandai aktif tidak ikut memicu network fetch',
      (tester) async {
    const result = PublicProfileResult(
      profile: PublicProfile(
        id: 'creator-1',
        name: 'Creator',
        username: 'creator',
        isOwner: false,
      ),
      posts: [],
    );
    await tester.pumpWidget(const MaterialApp(
      home: PublicProfileScreen(
        username: 'creator',
        initialResult: result,
        fetchChatConfig: _noOpFetch,
      ),
    ));
    await tester.pump();

    // Pindah ke tab Ditandai dulu — sama pola dengan test tab-tap di atas.
    // Guard _activateContent sudah dibuktikan benar di test itu; di sini kita
    // hanya butuh BERADA di tab tsb supaya bisa memicu _refresh() (dipanggil
    // pull-to-refresh) saat _selectedContent == shoppable.
    await tester.tap(find.byKey(const Key('public_tab_tagged_pill')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text('Belum ada postingan yang menandai akun ini'),
      findsOneWidget,
    );

    // Trigger refresh dengan memanggil langsung callback `onRefresh` milik
    // NataloPawRefreshIndicator, bukan simulasi drag/fling fisik. Ini PERSIS
    // callback yang sama yang dipanggil gesture pull-to-refresh nyata (widget
    // itu, saat armed & dilepas, melakukan `await widget.onRefresh()` di
    // `_doRefresh()`) — dipilih karena mekanisme overscroll widget ini
    // menggabungkan BouncingScrollPhysics (pixel negatif) + threshold
    // akumulasi + ScrollConfiguration custom yang sulit direplikasi presisi
    // via tester.fling/drag di widget test bersarang (NestedScrollView >
    // CustomScrollView), dan physics gesture itu sendiri tidak relevan dengan
    // guard yang sedang diuji (guard-nya ada di `_load`, bukan di deteksi
    // gesture). Memanggil callback langsung menguji persis yang ingin
    // dibuktikan — refresh apa pun pemicunya tidak boleh fetch saat shoppable.
    final refreshIndicator = tester.widget<NataloPawRefreshIndicator>(
      find.byType(NataloPawRefreshIndicator),
    );
    unawaited(refreshIndicator.onRefresh());

    // Bounded pump (bukan pumpAndSettle) — alasan sama persis dengan test
    // tab-tap di atas: contentState.loading di-set true SECARA SINKRON di
    // awal _load(), sebelum await pertama (network call), begitu guard
    // dilepas. pumpAndSettle akan ikut menunggu request nyata (atau timeout
    // di ApiClient.getJson) kalau guard hilang, sehingga tidak bisa lagi
    // membedakan "guard fired" dari "fetch asli fired" secara deterministik.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Empty state Ditandai TETAP tampil setelah refresh — bukti tidak ada
    // fetch yang mengubah state. Slivers di `_buildContentPage` bersifat
    // if/else-if/else (loading skeleton XOR error XOR empty XOR grid), jadi
    // text kosong ini hanya bisa tetap ada kalau cabang loading skeleton
    // TIDAK aktif dan grid TIDAK terisi ulang — satu assertion ini sekaligus
    // membuktikan keduanya.
    expect(
      find.text('Belum ada postingan yang menandai akun ini'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _noOpFetch() async {}
