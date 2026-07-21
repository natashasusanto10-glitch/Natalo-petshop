// ignore_for_file: depend_on_referenced_packages
//
// Regresi: header (avatar + nama) di atas media harus bisa ditap untuk
// membuka profil author, sama seperti nama di caption (lihat
// member_post_detail_screen_caption_test.dart). Foto pakai _PostAuthorRow
// (row putih di atas media), video pakai _VideoPostAuthorOverlay (overlay
// gradient di dalam media) — keduanya widget privat berbeda, jadi diuji
// lewat MemberPostDetailScreen penuh (bukan construct langsung).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/screens/public_profile_screen.dart';
import 'package:visibility_detector/visibility_detector.dart';

FeedPost _photoPost({String? username}) => FeedPost.fromJson({
      'id': 'header-tap-photo',
      'slug': 'header-tap-photo',
      'kind': 'PHOTO',
      'author': {
        'id': 'author-1',
        'name': 'Rani',
        if (username != null) 'username': username,
        'role': 'CUSTOMER',
      },
      'caption': '',
      'createdAt': '2026-07-18T00:00:00.000Z',
    });

void main() {
  // WAJIB: post-visibility VisibilityDetector (lihat member_post_detail_
  // screen.dart) butuh updateInterval=0 supaya timer internalnya tak pending
  // saat widget tree di-dispose akhir test.
  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  testWidgets('photo header (avatar+nama) tap opens author profile',
      (tester) async {
    final post = _photoPost(username: 'rani_official');

    await tester.pumpWidget(MaterialApp(
      home: MemberPostDetailScreen(
        post: post,
        isOwner: false,
        authorName: 'Rani',
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.text('Rani').first);
    await tester.pumpAndSettle();

    expect(find.byType(PublicProfileScreen), findsOneWidget);
    expect(
      tester
          .widget<PublicProfileScreen>(find.byType(PublicProfileScreen))
          .username,
      'rani_official',
    );
  });

  testWidgets('photo header without username stays non-tappable',
      (tester) async {
    final post = _photoPost();

    await tester.pumpWidget(MaterialApp(
      home: MemberPostDetailScreen(
        post: post,
        isOwner: false,
        authorName: 'Rani',
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.text('Rani').first);
    await tester.pumpAndSettle();

    expect(find.byType(PublicProfileScreen), findsNothing);
  });
}
