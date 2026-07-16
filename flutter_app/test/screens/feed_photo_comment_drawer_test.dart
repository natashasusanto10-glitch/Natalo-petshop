import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
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
          'mediaUrl': 'https://example.com/photo-1.jpg',
          'sortOrder': 0,
        },
        {
          'id': 'photo-media-2',
          'mediaType': 'image',
          'mediaUrl': 'https://example.com/photo-2.jpg',
          'sortOrder': 1,
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

  testWidgets(
      'photo media stays above the drawer scrim and ends at the drawer edge',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var mediaTaps = 0;
    var closed = false;
    final mediaKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedReelsCommentSurface(
            post: _photoPost(),
            open: true,
            onClosed: () => closed = true,
            child: GestureDetector(
              key: mediaKey,
              behavior: HitTestBehavior.opaque,
              onTap: () => mediaTaps++,
              child: const ColoredBox(color: Colors.orange),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final sheetTop = tester.getTopLeft(find.byType(FeedCommentSheet)).dy;
    final mediaRect = tester.getRect(find.byKey(mediaKey));
    expect(
      mediaRect.bottom,
      closeTo(sheetTop, 1),
      reason: 'photo media must be laid out only in the space above drawer',
    );

    await tester.tapAt(const Offset(200, 100));
    await tester.pump();

    expect(mediaTaps, 1,
        reason: 'the fullscreen scrim must not cover visible photo media');
    expect(closed, isFalse);
    expect(find.byType(FeedCommentSheet), findsOneWidget);
  });

  testWidgets('photo carousel uses contain fit without cropping',
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
      if (find.byType(FeedActionRail).evaluate().isNotEmpty) break;
    }

    final photoPageView = find.descendant(
      of: find.byType(FeedReelsCommentSurface),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is PageView && widget.scrollDirection == Axis.horizontal,
      ),
    );
    expect(photoPageView, findsOneWidget);
    final photoController = tester.widget<PageView>(photoPageView).controller!;

    CachedNetworkImage photoByUrl(String url) =>
        tester.widget<CachedNetworkImage>(
          find.byWidgetPredicate(
            (widget) => widget is CachedNetworkImage && widget.imageUrl == url,
          ),
        );

    final firstFit = photoByUrl('https://example.com/photo-1.jpg').fit;
    photoController.jumpToPage(1);
    await tester.pump();
    final secondFit = photoByUrl('https://example.com/photo-2.jpg').fit;
    expect(photoController.page, closeTo(1, 0.01));
    expect([firstFit, secondFit], everyElement(BoxFit.contain));
  });
}
