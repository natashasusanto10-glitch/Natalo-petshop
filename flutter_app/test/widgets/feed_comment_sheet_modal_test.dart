import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_comment.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/state/feed_comment_interaction_store.dart';
import 'package:natalo_petshop_flutter/state/feed_comment_session_store.dart';
import 'package:natalo_petshop_flutter/widgets/feed_comment_sheet.dart';
import 'package:natalo_petshop_flutter/widgets/natalo_paw_refresh_indicator.dart';

FeedPost _post() => FeedPost.fromJson({
      'id': 'comment-post',
      'slug': 'comment-post',
      'kind': 'USER_PHOTO',
      'mediaUrl': 'https://example.com/photo.jpg',
      'caption': 'Caption pengujian',
      'author': {
        'id': 'author-1',
        'name': 'Tester',
        'username': 'tester',
      },
      'createdAt': '2026-07-15T00:00:00.000Z',
    });

FeedComment _comment({required int likeCount, required bool viewerLiked}) =>
    FeedComment.fromApiJson({
      'id': 'comment-1',
      'postId': _post().id,
      'content': 'Komentar pengujian',
      'likeCount': likeCount,
      'viewerLiked': viewerLiked,
      'createdAt': '2026-07-15T00:00:00.000Z',
      'author': {
        'id': 'commenter-1',
        'name': 'Pemberi komentar',
        'username': 'commenter',
      },
    });

class _CountingNavigatorObserver extends NavigatorObserver {
  int popCount = 0;
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

void main() {
  setUp(() {
    feedCommentSessionStore.clear();
    feedCommentInteractionStore.clearForViewer();
  });
  tearDown(() {
    feedCommentSessionStore.clear();
    feedCommentInteractionStore.clearForViewer();
  });

  testWidgets('sheet renders the global comment like state over stale cache',
      (tester) async {
    final sessions = FeedCommentSessionStore();
    sessions
        .sessionFor(viewerId: 'guest', postId: _post().id)
        .replaceComments([_comment(likeCount: 3, viewerLiked: false)], null);
    feedCommentInteractionStore.seed(
      postId: _post().id,
      commentId: 'comment-1',
      liked: true,
      count: 4,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedCommentSheet(post: _post(), sessionStore: sessions),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('4 suka'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });

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

  testWidgets('rapid double show admits one modal route and releases on close',
      (tester) async {
    final navigatorObserver = _CountingNavigatorObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [navigatorObserver],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                unawaited(showFeedCommentDrawer(context, post: _post()));
                unawaited(showFeedCommentDrawer(context, post: _post()));
              },
              child: const Text('Double'),
            ),
          ),
        ),
      ),
    );
    final pushesBefore = navigatorObserver.pushCount;

    await tester.tap(find.text('Double'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(FeedCommentSheet), findsOneWidget);
    expect(navigatorObserver.pushCount, pushesBefore + 1);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(FeedCommentSheet), findsNothing);

    await tester.tap(find.text('Double'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(FeedCommentSheet), findsOneWidget);
    expect(navigatorObserver.pushCount, pushesBefore + 2,
        reason: 'the admission lock must be released in finally');

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
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

    Navigator.of(tester.element(find.byType(FeedCommentSheet))).pop();
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('author navigation closes drawer and releases single-flight',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    feedCommentSessionStore
        .sessionFor(viewerId: 'guest', postId: _post().id)
        .replaceComments(const [], null);
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (settings) {
          if (settings.name == '/u') {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => Scaffold(
                body: Text('Profil ${settings.arguments}'),
              ),
            );
          }
          return null;
        },
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFeedCommentDrawer(
                context,
                post: _post(),
              ),
              child: const Text('Profil author'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Profil author'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final authorLink = find.bySemanticsLabel(RegExp(r'^Buka profil ')).first;
    await tester.tap(authorLink);
    await tester.pumpAndSettle();

    expect(find.byType(FeedCommentSheet), findsNothing);
    expect(find.text('Profil tester'), findsOneWidget);

    Navigator.of(tester.element(find.text('Profil tester'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profil author'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(FeedCommentSheet), findsOneWidget,
        reason: 'closing for navigation must release the admission lock');
    Navigator.of(tester.element(find.byType(FeedCommentSheet))).pop();
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('viewer generation change closes drawer and discards old draft',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sessions = FeedCommentSessionStore();
    final viewer = ValueNotifier<FeedCommentViewerIdentity>(
      const FeedCommentViewerIdentity(viewerId: 'guest', generation: 0),
    );
    addTearDown(viewer.dispose);
    final oldSession = sessions.sessionFor(
      viewerId: 'guest',
      postId: _post().id,
    )..replaceComments(const [], null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFeedCommentDrawer(
                context,
                post: _post(),
                sessionStore: sessions,
                viewerIdentityListenable: viewer,
              ),
              child: const Text('Ganti viewer'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ganti viewer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byType(TextField), 'draft milik guest');
    expect(oldSession.draftText, 'draft milik guest');

    viewer.value = const FeedCommentViewerIdentity(
      viewerId: 'member-1',
      generation: 1,
    );
    await tester.pumpAndSettle();

    expect(find.byType(FeedCommentSheet), findsNothing);
    expect(oldSession.draftText, isEmpty);
    expect(oldSession.replyTarget, isNull);

    sessions
        .sessionFor(viewerId: 'member-1', postId: _post().id)
        .replaceComments(const [], null);
    await tester.tap(find.text('Ganti viewer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller?.text, isEmpty);

    Navigator.of(tester.element(find.byType(FeedCommentSheet))).pop();
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets(
      'viewer change removes drawer below a nested modal and releases lock',
      (tester) async {
    final sessions = FeedCommentSessionStore();
    final viewer = ValueNotifier<FeedCommentViewerIdentity>(
      const FeedCommentViewerIdentity(viewerId: 'guest', generation: 0),
    );
    addTearDown(viewer.dispose);
    sessions
        .sessionFor(viewerId: 'guest', postId: _post().id)
        .replaceComments(const [], null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFeedCommentDrawer(
                context,
                post: _post(),
                sessionStore: sessions,
                viewerIdentityListenable: viewer,
              ),
              child: const Text('Drawer nested'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Drawer nested'));
    await tester.pump(const Duration(milliseconds: 350));
    final sheetContext = tester.element(find.byType(FeedCommentSheet));
    unawaited(showDialog<void>(
      context: sheetContext,
      builder: (_) => const AlertDialog(content: Text('Nested modal')),
    ));
    await tester.pumpAndSettle();

    viewer.value = const FeedCommentViewerIdentity(
      viewerId: 'member-1',
      generation: 1,
    );
    await tester.pumpAndSettle();

    expect(find.byType(FeedCommentSheet), findsNothing);
    expect(find.text('Nested modal'), findsOneWidget);

    Navigator.of(tester.element(find.text('Nested modal'))).pop();
    await tester.pumpAndSettle();
    sessions
        .sessionFor(viewerId: 'member-1', postId: _post().id)
        .replaceComments(const [], null);
    await tester.tap(find.text('Drawer nested'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(FeedCommentSheet), findsOneWidget,
        reason: 'removing a covered drawer must release single-flight');
    Navigator.of(tester.element(find.byType(FeedCommentSheet))).pop();
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('daftar komentar populated tidak punya pull-to-refresh',
      (tester) async {
    final sessions = FeedCommentSessionStore();
    sessions
        .sessionFor(viewerId: 'guest', postId: _post().id)
        .replaceComments([_comment(likeCount: 1, viewerLiked: false)], null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedCommentSheet(post: _post(), sessionStore: sessions),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(NataloPawRefreshIndicator), findsNothing,
        reason: 'tarik-bawah di puncak = tutup, bukan refresh');
  });
}
