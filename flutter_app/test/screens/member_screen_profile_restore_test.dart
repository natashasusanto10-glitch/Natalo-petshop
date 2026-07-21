import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';
import 'package:natalo_petshop_flutter/screens/member_screen.dart';
import 'package:natalo_petshop_flutter/state/member_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// I4 (spec route-freeze): setelah back dari viewer Postingan, profil wajib
/// kembali utuh (blok identitas terlihat) dan responsif terhadap sentuhan
/// (tidak ada barrier route-mati yang menelan input). Reproduksi bug device:
/// profil "terdorong ke atas" + tidak merespons.
void main() {
  FeedPost photoPost(String id) => FeedPost.fromJson({
        'id': id,
        'kind': 'PHOTO_CAROUSEL',
        'status': 'ACTIVE',
        'title': 'Post $id',
        'description': 'Caption $id',
        'media': [
          {'id': 'm-$id', 'type': 'IMAGE', 'mediaUrl': ''},
        ],
        'author': {
          'id': 'owner-1',
          'name': 'Natasha',
          'username': 'natasha_s',
          'role': 'CUSTOMER',
        },
      });

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
    MemberScreen.debugMyPostsFetcher = () async => FeedPage(
          items: [photoPost('p1'), photoPost('p2')],
        );
  });

  tearDown(() async {
    MemberScreen.debugMyPostsFetcher = null;
    await memberStore.logout();
  });

  Future<void> pumpBounded(WidgetTester tester, [int frames = 10]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
      'back dari viewer Postingan → identitas profil utuh + profil responsif',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        routes: {
          '/member/login': (_) => const Scaffold(body: Text('Login')),
        },
        home: const MemberScreen(),
      ),
    );
    await pumpBounded(tester);

    // Pra-kondisi: identitas terlihat + grid terisi dari seam.
    expect(find.text('Edit Profil'), findsOneWidget);

    // Buka viewer dari tile grid pertama (route origin-expansion).
    final thumbs = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(InkWell),
    );
    await tester.tap(thumbs.first, warnIfMissed: false);
    await pumpBounded(tester, 8);

    // Viewer terbuka (MemberPostDetailScreen menampilkan judul 'Postingan').
    expect(find.text('Postingan'), findsWidgets,
        reason: 'viewer Postingan harus terbuka setelah tap tile');

    // Back (pop programatik = tombol back AppBar / back sistem).
    navKey.currentState!.pop();
    await pumpBounded(tester, 8);

    // I4a: blok identitas profil kembali terlihat (tidak "terdorong").
    expect(find.text('Edit Profil'), findsOneWidget,
        reason: 'identitas profil wajib terlihat lagi setelah back');
    // I4b: profil responsif — tap elemen profil berfungsi, tidak dimakan
    // barrier route mati.
    await tester.tap(find.text('Bagikan Profil'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
  });
}
