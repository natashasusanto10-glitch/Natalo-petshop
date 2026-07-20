import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_page_zoom_route.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_posts_screen.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_expanded_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Captures every route pushed onto the navigator so tests can assert which
/// transition route type a tile tap opens.
class _RouteCaptureObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const hapticChannel = MethodChannel('haptic_feedback');
  final hapticCalls = <MethodCall>[];

  setUp(() {
    hapticCalls.clear();
    SharedPreferences.setMockInitialValues(const {});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hapticChannel, (call) async {
      hapticCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hapticChannel, null);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MemberPostsScreen()));
    // Bounded pump-loop (bukan pumpAndSettle) — fetch jaringan gagal cepat
    // di test env; loop menunggu state loading selesai tanpa risiko hang.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
  }

  testWidgets('own profile renders IG-style header with owner actions',
      (tester) async {
    await pumpScreen(tester);

    expect(find.byType(PublicProfileExpandedHeader), findsOneWidget);
    expect(find.text('Edit Profil'), findsOneWidget);
    expect(find.text('Bagikan Profil'), findsOneWidget);
    // Owner tidak pernah melihat tombol follow/pesan di profil sendiri.
    expect(find.text('Ikuti'), findsNothing);
    expect(find.text('Pesan'), findsNothing);
    // Stats horizontal ala IG.
    expect(find.text('Postingan'), findsOneWidget);
    expect(find.text('Pengikut'), findsOneWidget);
    expect(find.text('Mengikuti'), findsOneWidget);
  });

  testWidgets('filter tabs render as IG icon tabs with semantics',
      (tester) async {
    await pumpScreen(tester);

    for (final label in const ['Semua', 'Foto', 'Video', 'Menunggu']) {
      expect(find.byTooltip(label), findsOneWidget);
    }
    // Tab pertama aktif by default.
    final semantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byTooltip('Semua'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.selected, isTrue);

    await tester.tap(find.byTooltip('Video'));
    await tester.pump();
    final videoSemantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byTooltip('Video'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(videoSemantics.properties.selected, isTrue);
  });

  testWidgets('opens Postingan via the zoom route without entry haptic',
      (tester) async {
    final post = FeedPost.fromJson({
      'id': 'legacy-a',
      'slug': 'legacy-a',
      'kind': 'USER_PHOTO',
      'mediaUrl': 'https://example.com/legacy-a.jpg',
      'thumbnailUrl': 'https://example.com/legacy-a.jpg',
      'author': {'id': 'owner-1', 'name': 'Owner'},
      'createdAt': DateTime(2026, 7, 18).toIso8601String(),
    });
    final observer = _RouteCaptureObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: MemberPostsScreen(
          debugPostsPageLoader: (_) async => FeedPage(items: [post]),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find
          .byKey(const ValueKey('gallery-post-legacy-a'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    // Feedback disabled so no Material tap haptic fires on entry.
    final inkWell = tester.widget<InkWell>(
      find.byKey(const ValueKey('gallery-post-legacy-a')),
    );
    expect(inkWell.enableFeedback, isFalse);

    await tester.tap(find.byKey(const ValueKey('gallery-post-legacy-a')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    // Postingan Saya now opens through the dedicated full-page zoom route —
    // the SAME route type as Own/Public Profile — never the legacy
    // origin-expansion snapshot, and with zero entry haptic.
    expect(observer.pushed.whereType<PostPageZoomRoute>(), isNotEmpty);
    // The legacy origin-expansion snapshot must be gone — this path now pushes
    // the dedicated full-page zoom route instead. (The destination mounts once
    // geometry readiness is reported — a runtime/device-verify concern, so it
    // is not asserted here; the pushed route type is the authoritative signal,
    // matching the Own/Public Profile wiring tests.)
    expect(
      find.byKey(const ValueKey('origin-expansion-snapshot')),
      findsNothing,
    );
    expect(hapticCalls.where((call) => call.method == 'light'), isEmpty);
    expect(
      hapticCalls.where((call) => call.method == 'selectionClick'),
      isEmpty,
    );
  });
}
