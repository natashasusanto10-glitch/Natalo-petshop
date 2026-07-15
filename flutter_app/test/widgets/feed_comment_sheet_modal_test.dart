import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/state/feed_comment_session_store.dart';
import 'package:natalo_petshop_flutter/widgets/feed_comment_sheet.dart';

FeedPost _post() => FeedPost.fromJson({
      'id': 'comment-post',
      'slug': 'comment-post',
      'kind': 'USER_PHOTO',
      'mediaUrl': 'https://example.com/photo.jpg',
      'author': {'id': 'author-1', 'name': 'Tester'},
      'createdAt': '2026-07-15T00:00:00.000Z',
    });

class _CountingNavigatorObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

void main() {
  setUp(feedCommentSessionStore.clear);
  tearDown(feedCommentSessionStore.clear);

  testWidgets('photo post uses one shared draggable comment drawer',
      (tester) async {
    final navigatorObserver = _CountingNavigatorObserver();
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [navigatorObserver],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFeedCommentDrawer(context, post: _post()),
              child: const Text('Komentar'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Komentar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(FeedCommentSheet), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);

    final sheetTop = tester.getTopLeft(find.byType(FeedCommentSheet)).dy;
    await tester.dragFrom(
      Offset(200, sheetTop + 14),
      const Offset(0, 700),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(FeedCommentSheet), findsNothing);
    expect(find.text('Komentar'), findsOneWidget);
    expect(navigatorObserver.popCount, 1,
        reason: 'one drag must dismiss only the modal route once');
  });

  testWidgets('system back closes the shared comment drawer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFeedCommentDrawer(context, post: _post()),
              child: const Text('Buka'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buka'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(FeedCommentSheet), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(FeedCommentSheet), findsNothing);
  });

  testWidgets('drag dismiss racing system back never pops the page below',
      (tester) async {
    final navigatorObserver = _CountingNavigatorObserver();
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [navigatorObserver],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFeedCommentDrawer(context, post: _post()),
              child: const Text('Race'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Race'));
    await tester.pumpAndSettle();
    final sheetTop = tester.getTopLeft(find.byType(FeedCommentSheet)).dy;
    await tester.dragFrom(
      Offset(200, sheetTop + 14),
      const Offset(0, 700),
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(FeedCommentSheet), findsNothing);
    expect(find.text('Race'), findsOneWidget);
    expect(navigatorObserver.popCount, 1);
  });

  testWidgets('draft survives closing and reopening the same post drawer',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/member/login': (_) => const Scaffold(body: Text('Login')),
        },
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFeedCommentDrawer(context, post: _post()),
              child: const Text('Draft'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Draft'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byType(TextField), 'komentar belum selesai');
    Navigator.of(tester.element(find.byType(FeedCommentSheet))).pop();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.text('Draft'));
    await tester.pump(const Duration(milliseconds: 350));

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller?.text, 'komentar belum selesai');
  });
}
