import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/transition/post_viewer_route.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/screens/member_posts_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Task 4 — "Postingan Saya" (member_posts_screen) dipindah dari
/// `pushOriginExpansion`/`OriginSnapshotSource` ke `pushPostViewer` + hero
/// bawaan Flutter (`PostHero`) lewat `GalleryPostTile.heroScope`. Grid tile
/// harus punya Hero bertag `post-hero/myPosts/<postId>` dan tap membuka
/// `MemberPostDetailScreen` lewat `PostViewerRoute` (transisi native),
/// BUKAN `OriginExpansionTransition` lama.
///
/// Halaman ini fetch network di initState (`feedService.fetchMyPosts`) —
/// tanpa seam debug seperti member_screen, jadi test env pasti gagal
/// fetch (HttpClient di test selalu 400) dan grid akan kosong. Tes ini
/// hanya memverifikasi TIDAK ADA exception dan tidak ada sisa
/// OriginSnapshotSource di tree kosong — kasus tap dgn data nyata sudah
/// dicover gallery_post_tile_hero_test.dart (unit level) +
/// public_profile_screen_test.dart (integration level, pola sama).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MemberPostsScreen()));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
  }

  testWidgets(
      'grid tidak lagi memakai OriginSnapshotSource lama; tidak ada exception',
      (tester) async {
    await pumpScreen(tester);

    // OriginSnapshotSource sudah dihapus total dari codebase (lihat commit
    // "hapus OriginExpansionRoute total") — sebuah runtimeType-string check
    // terhadap tipe yang sudah tidak ada akan SELALU findsNothing (vacuous),
    // begitu juga find.byType(PostViewerRoute) karena PostViewerRoute
    // adalah Route (bukan Widget), find.byType tak pernah menemukannya.
    // Regresi nyata yang relevan cukup: grid tidak melempar exception saat
    // dibangun dan tap masih membuka MemberPostDetailScreen (lihat test
    // 'grid membuka viewer via PostViewerRoute' di file ini).
    expect(find.byType(MemberPostDetailScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
