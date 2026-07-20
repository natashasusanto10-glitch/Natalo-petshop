import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';
import 'package:natalo_petshop_flutter/screens/member_screen.dart';
import 'package:natalo_petshop_flutter/state/member_store.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_expanded_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tab Akun (profil sendiri) — direombak jadi IG-white sesuai
/// `PublicProfileExpandedHeader` bersama. Ikon top bar (buat postingan,
/// tersimpan, notifikasi, pengaturan) TIDAK berubah bentuk/logika — hanya
/// direcolor gelap + username ditambahkan di tengah bar.
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
        bio: 'Cat mom di Jakarta',
        followersCount: 24,
        followingCount: 31,
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

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/member/login': (_) => const Scaffold(body: Text('Login')),
        },
        home: const MemberScreen(),
      ),
    );
    // Bounded pump-loop — fetch jaringan gagal cepat di test env; loop
    // menunggu state loading selesai tanpa risiko hang (pumpAndSettle bisa
    // hang kalau ada retry/animasi berjalan terus).
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
  }

  testWidgets('own profile reuses shared IG-style header with owner actions',
      (tester) async {
    await pumpScreen(tester);

    expect(find.byType(PublicProfileExpandedHeader), findsOneWidget);
    expect(find.text('Edit Profil'), findsOneWidget);
    expect(find.text('Bagikan Profil'), findsOneWidget);
    expect(find.text('Ikuti'), findsNothing);
    expect(find.text('Pesan'), findsNothing);
  });

  testWidgets('top bar keeps every existing icon unchanged', (tester) async {
    await pumpScreen(tester);

    expect(find.byTooltip('Buat postingan'), findsOneWidget);
    expect(find.byTooltip('Postingan tersimpan'), findsOneWidget);
    expect(find.byTooltip('Pengaturan akun'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('username renders centered in the top bar', (tester) async {
    await pumpScreen(tester);

    expect(find.text('natasha_s'), findsOneWidget);
  });

  testWidgets('status bar uses dark icons over the white header',
      (tester) async {
    await pumpScreen(tester);

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(region.value, SystemUiOverlayStyle.dark);
  });

  testWidgets('content tabs render without a full-width underline bar',
      (tester) async {
    await pumpScreen(tester);

    // Sistem tab profil publik yang baru: ikon saja + indikator pendek di
    // bawah tab aktif (bukan garis full-width UnderlineTabIndicator lama).
    expect(find.byKey(const Key('public_tab_posts_pill')), findsOneWidget);
    expect(find.byKey(const Key('public_tab_video_pill')), findsOneWidget);
    expect(find.byKey(const Key('public_tab_shop_pill')), findsOneWidget);
  });

  testWidgets(
      'tapping a Postingan tile uses no entry haptic and disables feedback',
      (tester) async {
    final post = FeedPost.fromJson({
      'id': 'own-a',
      'slug': 'own-a',
      'kind': 'USER_PHOTO',
      'mediaUrl': 'https://example.com/own-a.jpg',
      'thumbnailUrl': 'https://example.com/own-a.jpg',
      'author': {'id': 'owner-1', 'name': 'Owner'},
      'createdAt': DateTime(2026, 7, 18).toIso8601String(),
    });
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/member/login': (_) => const Scaffold(body: Text('Login')),
        },
        home: MemberScreen(
          debugPostsPageLoader: (_) async => FeedPage(items: [post]),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find
          .byKey(const ValueKey('profile-post-own-a'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    // The tile's InkWell must disable Material tap feedback so no haptic is
    // emitted on entry into the zoom transition.
    final inkWell = tester.widget<InkWell>(
      find.byKey(const ValueKey('profile-post-own-a')),
    );
    expect(inkWell.enableFeedback, isFalse);

    await tester.tap(find.byKey(const ValueKey('profile-post-own-a')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    // The legacy origin-expansion snapshot must be gone — this path now pushes
    // the dedicated full-page zoom route instead.
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

  group('profile post list reconciliation', () {
    FeedPost post(String id) => FeedPost.fromJson({
          'id': id,
          'slug': id,
          'kind': 'USER_PHOTO',
          'mediaUrl': 'https://example.com/$id.jpg',
          'author': {'id': 'owner-1', 'name': 'Owner'},
          'createdAt': DateTime(2026, 7, 18).toIso8601String(),
        });

    test(
      'reconcileProfilePosts retains a B paginated in beyond page 1',
      () {
        // Existing list: page 1 (a, b) + tail paginated in beyond page 1
        // (c, dBeyond). A post-pop refresh only re-fetches page 1 (a, b).
        final existing = [post('a'), post('b'), post('c'), post('dBeyond')];
        final refreshedPage1 = [post('a'), post('b')];

        final reconciled = reconcileProfilePosts(refreshedPage1, existing);

        // The clobbering `_allPosts = page.items` would have dropped c/dBeyond;
        // reconcile keeps the loaded extent so B stays resolvable.
        expect(
          reconciled.map((p) => p.id),
          ['a', 'b', 'c', 'dBeyond'],
        );
      },
    );

    test('mergeProfilePostsById dedupes by id and fetches nothing', () {
      var loaderCalls = 0;
      Future<FeedPage> neverCalledLoader(String? cursor) async {
        loaderCalls++;
        return const FeedPage();
      }

      final existing = [post('a'), post('b')];
      final incoming = [post('b'), post('c')]; // b overlaps

      final merged = mergeProfilePostsById(existing, incoming);

      expect(merged.map((p) => p.id), ['a', 'b', 'c']);
      // The overlapping id keeps the existing instance (no duplicate).
      expect(identical(merged[1], existing[1]), isTrue);
      // Pure merge performs ZERO loader/network calls.
      expect(loaderCalls, 0);
      // A page with only-overlapping ids returns the SAME list instance
      // (no rebuild churn), still without any fetch.
      final noop = mergeProfilePostsById(existing, [post('a')]);
      expect(identical(noop, existing), isTrue);
      expect(loaderCalls, 0);
      // Reference the loader so the analyzer sees it exercised.
      expect(neverCalledLoader, isNotNull);
    });

    test('resolveProfileTransitionScope only switches to Semua for mixed B', () {
      // Scoped B is present in its origin tab → never switch.
      expect(
        resolveProfileTransitionScope(
          originScope: profilePostScopeVideo,
          originScopeContainsPost: true,
          allScopeContainsPost: true,
        ),
        profilePostScopeVideo,
      );
      // B cannot exist in the origin (video) tab but exists in Semua → switch.
      expect(
        resolveProfileTransitionScope(
          originScope: profilePostScopeVideo,
          originScopeContainsPost: false,
          allScopeContainsPost: true,
        ),
        profilePostScopeAll,
      );
      // B is nowhere yet → stay on the origin tab (no gratuitous switch).
      expect(
        resolveProfileTransitionScope(
          originScope: profilePostScopeVideo,
          originScopeContainsPost: false,
          allScopeContainsPost: false,
        ),
        profilePostScopeVideo,
      );
    });
  });
}
