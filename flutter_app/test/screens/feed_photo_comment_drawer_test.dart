import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/features/feed/widgets/feed_action_rail.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/screens/feed_screen.dart';
import 'package:natalo_petshop_flutter/state/feed_comment_session_store.dart';
import 'package:natalo_petshop_flutter/widgets/feed_comment_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

FeedPost _photoPost() => FeedPost.fromJson({
      'id': 'photo-comment-regression',
      'slug': 'photo-comment-regression',
      'kind': 'PHOTO_CAROUSEL',
      'mediaItems': [
        {
          'id': 'photo-media-1',
          'mediaType': 'image',
          'mediaUrl': 'https://example.com/photo.jpg',
          'sortOrder': 0,
        },
      ],
      'author': {'id': 'author-1', 'name': 'Tester'},
      'createdAt': '2026-07-15T00:00:00.000Z',
    });

void main() {
  setUp(feedCommentSessionStore.clear);
  tearDown(feedCommentSessionStore.clear);

  testWidgets('photo action opens and reopens the shared comment drawer',
      (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'feed_offline_cache_v2': jsonEncode([_photoPost().toJson()]),
    });

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/member/login': (_) => const Scaffold(body: Text('Login')),
        },
        home: const FeedScreen(),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.bySemanticsLabel('Komentar').evaluate().isNotEmpty) break;
    }

    expect(find.bySemanticsLabel('Komentar'), findsOneWidget);
    final rail = tester.widget<FeedActionRail>(find.byType(FeedActionRail));
    rail.onComment!.call();
    rail.onComment!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(tester.takeException(), isNull);
    expect(find.byType(FeedCommentSheet), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);

    await tester.binding.handlePopRoute();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(FeedCommentSheet).evaluate().isEmpty) break;
    }

    expect(find.byType(FeedCommentSheet), findsNothing);
    await tester.tap(find.bySemanticsLabel('Komentar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(tester.takeException(), isNull);
    expect(find.byType(FeedCommentSheet), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 350));
  });
}
