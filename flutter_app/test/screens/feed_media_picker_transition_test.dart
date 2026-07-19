import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/models/feed_post.dart';
import 'package:natalo_petshop_flutter/models/member_profile.dart';
import 'package:natalo_petshop_flutter/screens/feed_media_picker_screen.dart';
import 'package:natalo_petshop_flutter/screens/feed_screen.dart';
import 'package:natalo_petshop_flutter/screens/member_screen.dart';
import 'package:natalo_petshop_flutter/state/member_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

FeedPost _photoPost() => FeedPost.fromJson({
      'id': 'composer-origin-photo',
      'slug': 'composer-origin-photo',
      'kind': 'PHOTO_CAROUSEL',
      'mediaItems': [
        {
          'id': 'composer-origin-media',
          'mediaType': 'image',
          'mediaUrl': 'https://example.com/photo.jpg',
          'sortOrder': 0,
        },
      ],
      'author': {'id': 'author-1', 'name': 'Tester'},
      'createdAt': '2026-07-15T00:00:00.000Z',
    });

void main() {
  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    SharedPreferences.setMockInitialValues({
      'feed_offline_cache_v2::guest': jsonEncode([_photoPost().toJson()]),
    });
  });

  testWidgets('Feed plus expands into the media picker and reverses on cancel',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/member/login': (_) => const Scaffold(body: Text('Login')),
        },
        home: const FeedScreen(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('feed-create-post')));
    await _pumpUntil(tester, find.byType(FeedMediaPickerScreen));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(FeedMediaPickerScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('origin-expansion-snapshot')),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));

    expect(
      find.byKey(const ValueKey('origin-expansion-snapshot')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();
    expect(find.byType(FeedMediaPickerScreen), findsNothing);
    expect(find.byKey(const ValueKey('feed-create-post')), findsOneWidget);
  });

  testWidgets('Feed plus opens one picker route across rapid taps and back',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/member/login': (_) => const Scaffold(body: Text('Login')),
        },
        home: const FeedScreen(),
      ),
    );
    await tester.pump();

    final createPost = find.byKey(const ValueKey('feed-create-post'));
    expect(createPost, findsOneWidget);
    final button = tester.widget<InkResponse>(
      find.descendant(of: createPost, matching: find.byType(InkResponse)),
    );
    button.onTap!.call();
    button.onTap!.call();
    await _pumpUntil(tester, find.byType(FeedMediaPickerScreen));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(FeedMediaPickerScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('origin-expansion-snapshot')),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();
    expect(find.byType(FeedMediaPickerScreen), findsNothing);
    expect(createPost, findsOneWidget);
  });

  testWidgets('media picker falls back to a reversible fade without an origin',
      (tester) async {
    final missingOrigin = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => unawaited(
                  FeedMediaPickerScreen.openFromOrigin(context, missingOrigin),
                ),
                child: const Text('Open composer'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open composer'));
    await _pumpUntil(tester, find.byType(FeedMediaPickerScreen));
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.byType(FeedMediaPickerScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('origin-expansion-fade')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('origin-expansion-snapshot')),
      findsNothing,
    );

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();
    expect(find.byType(FeedMediaPickerScreen), findsNothing);
  });

  testWidgets(
      'owned Profile plus opens one picker route across rapid taps and back',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    memberStore.setProfile(
      const MemberProfile(id: 'owner-1', name: 'Owner', username: 'owner'),
    );
    addTearDown(memberStore.logout);

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/member/login': (_) => const Scaffold(body: Text('Login')),
        },
        home: const MemberScreen(),
      ),
    );
    await tester.pump();

    final createPost = find.byKey(const ValueKey('profile-create-post'));
    expect(createPost, findsOneWidget);

    final createButton = tester.widget<IconButton>(createPost);
    createButton.onPressed!.call();
    createButton.onPressed!.call();
    await _pumpUntil(tester, find.byType(FeedMediaPickerScreen));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(FeedMediaPickerScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('origin-expansion-snapshot')),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();
    expect(find.byType(FeedMediaPickerScreen), findsNothing);
    expect(createPost, findsOneWidget);
  });
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (finder.evaluate().isNotEmpty) return;
  }
}
