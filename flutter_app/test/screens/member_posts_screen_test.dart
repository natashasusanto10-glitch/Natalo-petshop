import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/screens/member_posts_screen.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_expanded_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('opens Postingan without entry haptic', (tester) async {
    final post = FeedPost.fromJson({
      'id': 'legacy-a',
      'slug': 'legacy-a',
      'kind': 'USER_PHOTO',
      'mediaUrl': 'https://example.com/legacy-a.jpg',
      'thumbnailUrl': 'https://example.com/legacy-a.jpg',
      'author': {'id': 'owner-1', 'name': 'Owner'},
      'createdAt': DateTime(2026, 7, 18).toIso8601String(),
    });
    await tester.pumpWidget(
      MaterialApp(
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

    await tester.tap(find.byKey(const ValueKey('gallery-post-legacy-a')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.byType(MemberPostDetailScreen), findsOneWidget);
    expect(hapticCalls.where((call) => call.method == 'light'), isEmpty);
  });
}
