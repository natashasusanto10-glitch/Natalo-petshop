// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/member_post_detail_screen.dart';
import 'package:visibility_detector/visibility_detector.dart';

FeedPost _photoPost() => FeedPost.fromJson({
      'id': 'bookmark-test-photo',
      'slug': 'bookmark-test-photo',
      'kind': 'PHOTO',
      'author': {'id': 'author-1', 'name': 'Rani', 'role': 'CUSTOMER'},
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

  testWidgets('bookmark icon is present in action row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: MemberPostDetailScreen(post: _photoPost())),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
  });
}
