import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:natalo_petshop_flutter/widgets/feed_comment_sheet.dart';
import 'package:visibility_detector/visibility_detector.dart';

FeedPost _partialAuthorPost() => FeedPost.fromJson({
      'id': 'post-partial-author',
      'slug': 'post-partial-author',
      'kind': 'PHOTO_CAROUSEL',
      'caption': 'Burger buger',
      'mediaItems': [
        {
          'id': 'media-1',
          'mediaType': 'image',
          'mediaUrl': 'https://example.com/burger.jpg',
          'sortOrder': 0,
        },
      ],
      'author': {'id': 'author-1'},
      'createdAt': '2026-07-16T00:00:00.000Z',
    });

void main() {
  // WAJIB: post-visibility VisibilityDetector (lihat member_post_detail_
  // screen.dart) butuh updateInterval=0 supaya timer internalnya tak pending
  // saat widget tree di-dispose akhir test.
  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  testWidgets('Postingan comment drawer uses the resolved page author identity',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const photoUrl = 'https://example.com/asiong.jpg';
    await tester.pumpWidget(
      MaterialApp(
        home: MemberPostDetailScreen(
          post: _partialAuthorPost(),
          authorName: 'Asiong Silalahi',
          authorPhotoUrl: photoUrl,
          authorInitial: 'A',
          isOwner: false,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.bySemanticsLabel('Buka komentar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final drawer = find.byType(FeedCommentSheet);
    expect(drawer, findsOneWidget);
    final sheet = tester.widget<FeedCommentSheet>(drawer);
    expect(sheet.post.author.name, 'Asiong Silalahi');
    expect(sheet.post.author.displayHandle, 'Asiong Silalahi');
    expect(sheet.post.author.profilePhotoUrl, photoUrl);
  });
}
