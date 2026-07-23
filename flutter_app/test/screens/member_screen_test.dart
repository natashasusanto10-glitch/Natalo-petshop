import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';
import 'package:natalo_petshop_flutter/models/public_profile.dart';
import 'package:natalo_petshop_flutter/screens/member_screen.dart';
import 'package:natalo_petshop_flutter/services/profile_service.dart';
import 'package:natalo_petshop_flutter/state/member_store.dart';
import 'package:natalo_petshop_flutter/widgets/public_profile_expanded_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tab Akun (profil sendiri) — direombak jadi IG-white sesuai
/// `PublicProfileExpandedHeader` bersama. Ikon top bar (buat postingan,
/// tersimpan, notifikasi, pengaturan) TIDAK berubah bentuk/logika — hanya
/// direcolor gelap + username ditambahkan di tengah bar.
void main() {
  setUp(() {
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
  });

  tearDown(() async {
    // Reset SEMUA seam test di tearDown (bukan akhir badan test) supaya
    // tidak leak ke test berikutnya kalau ada `expect` yang throw duluan —
    // fix Minor Spec A yang tercatat di sdd/progress-spec-a.md (Task 4).
    debugMyPostsFetcher = null;
    debugTaggedPostsFetcher = null;
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
    expect(find.byKey(const Key('public_tab_tagged_pill')), findsOneWidget);
  });

  testWidgets(
      'tab Ditandai kosong genuinely (fetch sukses tanpa hasil) tetap tampilkan copy Spec A',
      (tester) async {
    // Spec B (Task 13): tab ini sekarang fetch sungguhan lewat
    // `_loadTaggedPosts` (endpoint profil publik milik sendiri,
    // `content=tagged`) — bukan lagi getter `const []` hardcoded (Spec A).
    // Mock KEDUA fetcher supaya deterministik & tanpa network nyata.
    debugMyPostsFetcher = ({String filter = 'all', String? cursor}) async {
      return const FeedPage(items: [], nextCursor: null);
    };
    debugTaggedPostsFetcher = (username) async {
      expect(username, 'natasha_s'); // sumber sama dengan header (@username)
      return const PublicProfileResult(
        profile: PublicProfile(id: 'owner-1', name: 'Natasha'),
        posts: [],
      );
    };

    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('public_tab_tagged_pill')));
    await tester.pumpAndSettle();

    // Genuinely-empty case: teks empty-state Spec A DIPERTAHANKAN persis.
    expect(
      find.text('Belum ada postingan yang menandaimu'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Saat orang lain menandaimu di sebuah postingan, itu akan muncul di sini.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'tab Ditandai menampilkan post sungguhan dari fetch (Spec B — bukan lagi selalu-kosong)',
      (tester) async {
    debugMyPostsFetcher = ({String filter = 'all', String? cursor}) async {
      return const FeedPage(items: [], nextCursor: null);
    };
    final taggedPost = FeedPost.fromJson({
      'id': 'tagged-1',
      'slug': 'tagged-1',
      'kind': 'PHOTO',
      'mediaUrl': 'https://example.com/tagged-1.jpg',
      'author': {'id': 'other-user', 'name': 'Teman'},
      'createdAt': DateTime(2026).toIso8601String(),
    });
    debugTaggedPostsFetcher = (username) async {
      return PublicProfileResult(
        profile: const PublicProfile(id: 'owner-1', name: 'Natasha'),
        posts: [taggedPost],
      );
    };

    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('public_tab_tagged_pill')));
    await tester.pumpAndSettle();

    // Empty-state TIDAK muncul lagi — grid terisi post sungguhan.
    expect(find.text('Belum ada postingan yang menandaimu'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is CachedNetworkImage &&
            w.imageUrl == 'https://example.com/tagged-1.jpg',
      ),
      findsOneWidget,
    );
  });
}
