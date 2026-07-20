import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_route.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/screens/member_posts_screen.dart';
import 'package:natalo_petshop_flutter/screens/member_screen.dart';
import 'package:natalo_petshop_flutter/screens/public_profile_screen.dart';
import 'package:natalo_petshop_flutter/services/profile_service.dart';
import 'package:natalo_petshop_flutter/state/member_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cross-origin invariant (Task 11 closes the trio): Own Profile, Public
/// Profile, and Postingan Saya all open Postingan through the SAME dedicated
/// full-page zoom route and none emits an entry haptic. (The A→B landing to the
/// visible B is exercised by the shared wiring / adapter unit coverage; the
/// runtime A→B flight is a device-verify item — Task 15.)
class _RouteCaptureObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

Future<void> _noOpFetch() async {}

FeedPost _post(String id, String authorId) => FeedPost.fromJson({
      'id': id,
      'slug': id,
      'kind': 'USER_PHOTO',
      'mediaUrl': 'https://example.com/$id.jpg',
      'thumbnailUrl': 'https://example.com/$id.jpg',
      'author': {'id': authorId, 'name': 'Someone'},
      'createdAt': DateTime(2026, 7, 18).toIso8601String(),
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const hapticChannel = MethodChannel('haptic_feedback');
  final hapticCalls = <MethodCall>[];

  setUp(() {
    hapticCalls.clear();
    SharedPreferences.setMockInitialValues(const {});
    memberStore.setProfile(
      const MemberProfile(
        id: 'owner-1',
        name: 'Natasha',
        username: 'natasha_s',
        role: 'CUSTOMER',
      ),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hapticChannel, (call) async {
      hapticCalls.add(call);
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hapticChannel, null);
    await memberStore.logout();
  });

  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (finder.evaluate().isNotEmpty) break;
    }
  }

  testWidgets(
      'all three origins push the same zoom route type with no entry haptic',
      (tester) async {
    // ── Own Profile (Akun) ─────────────────────────────────────────────
    final ownObserver = _RouteCaptureObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [ownObserver],
        routes: {'/member/login': (_) => const Scaffold(body: Text('Login'))},
        home: MemberScreen(
          debugPostsPageLoader: (_) async =>
              FeedPage(items: [_post('own-a', 'owner-1')]),
        ),
      ),
    );
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('profile-post-own-a')),
    );
    await tester.tap(find.byKey(const ValueKey('profile-post-own-a')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    // Fully unmount the previous origin before building the next. Each origin's
    // tap holds its zoom route at `preparingOpen` (proxy covering the screen)
    // because no real destination geometry is reported in a widget test — the
    // route never settles and is never popped here. Swapping the whole
    // MaterialApp out from under that live route would leave its full-screen
    // proxy overlay (+ absorb-pointer barrier) intercepting the next grid's
    // taps; unmounting to a bare box first disposes the stuck route/session
    // cleanly so each origin starts from an empty overlay. (In production each
    // route is popped normally on back — this teardown is a test-only concern.)
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // ── Postingan Saya ─────────────────────────────────────────────────
    final myPostsObserver = _RouteCaptureObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [myPostsObserver],
        home: MemberPostsScreen(
          debugPostsPageLoader: (_) async =>
              FeedPage(items: [_post('mine-a', 'owner-1')]),
        ),
      ),
    );
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('gallery-post-mine-a')),
    );
    await tester.tap(find.byKey(const ValueKey('gallery-post-mine-a')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    // ── Public Profile ─────────────────────────────────────────────────
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final publicObserver = _RouteCaptureObserver();
    final result = PublicProfileResult(
      profile: const PublicProfile(
        id: 'creator-1',
        name: 'Creator',
        username: 'creator',
      ),
      posts: [_post('public-a', 'creator-1')],
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [publicObserver],
        home: PublicProfileScreen(
          username: 'creator',
          initialResult: result,
          fetchChatConfig: _noOpFetch,
        ),
      ),
    );
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('profile-post-public-a')),
    );
    await tester.tap(find.byKey(const ValueKey('profile-post-public-a')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    // Same route type across all three origins.
    expect(ownObserver.pushed.whereType<PostPageZoomRoute>(), isNotEmpty);
    expect(myPostsObserver.pushed.whereType<PostPageZoomRoute>(), isNotEmpty);
    expect(publicObserver.pushed.whereType<PostPageZoomRoute>(), isNotEmpty);

    // No entry haptic from any origin.
    expect(hapticCalls.where((call) => call.method == 'light'), isEmpty);
    expect(
      hapticCalls.where((call) => call.method == 'selectionClick'),
      isEmpty,
    );
  });
}
