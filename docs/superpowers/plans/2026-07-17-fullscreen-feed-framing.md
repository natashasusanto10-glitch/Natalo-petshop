# Fullscreen Feed Framing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make video fullscreen yang dibuka dari halaman Postingan memakai presentasi cover rata atas seperti Feed utama tanpa membawa aturan bottom navigation Feed.

**Architecture:** Tambahkan kebijakan presentasi `FeedVideoFraming.fullscreenFeed` pada widget bersama `FeedVideoPostView`. Kebijakan ini berbagi `BoxFit.cover` dan `Alignment.topCenter` dengan `mainFeed`, tetapi hanya `mainFeed` yang mengurangi viewport media dengan inset bottom navigation. `ScopedVideoFeedScreen` memilih kebijakan baru untuk jalur controller legacy dan managed tanpa mengubah ownership atau playback.

**Tech Stack:** Flutter, Dart, `video_player`, `cached_network_image`, `flutter_test`.

## Global Constraints

- Jangan mengubah ownership atau lifecycle `VideoPlayerController`.
- Jangan mengubah coordinator, preload, autoplay, mute global, atau audio arbiter.
- Jangan mengubah gesture, comment drawer, halaman Postingan inline, foto/carousel, data sosial, produk, atau backend.
- Compact comment preview harus tetap memakai `BoxFit.contain`.
- Thumbnail dan player fullscreen harus memakai fit serta alignment yang sama.
- Implementasi harus bekerja sama pada Android dan iOS tanpa fork platform.

---

### Task 1: Add the fullscreen cover framing policy

**Files:**
- Modify: `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart:64-68`
- Modify: `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart:3038-3042`
- Modify: `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart:3588-3622`
- Test: `flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart:1610-1735`

**Interfaces:**
- Consumes: Existing `FeedVideoFraming`, `_MediaBackground`, and `feed-video-media-viewport` key.
- Produces: `FeedVideoFraming.fullscreenFeed`, rendered with `BoxFit.cover`, `Alignment.topCenter`, and a zero bottom media inset.

- [ ] **Step 1: Write failing thumbnail and viewport tests**

Add these widget tests beside the existing `main Feed` framing tests:

```dart
testWidgets(
    'fullscreen Feed uses one top-aligned cover thumbnail without bottom inset',
    (tester) async {
  VisibilityDetectorController.instance.updateInterval = Duration.zero;
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(
        size: Size(393, 852),
        padding: EdgeInsets.only(bottom: 34),
      ),
      child: MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(aspectRatio: 9 / 16),
          isActive: false,
          preloadedController: null,
          framing: FeedVideoFraming.fullscreenFeed,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  final thumbnails = tester
      .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
      .where((image) => image.imageUrl.endsWith('.jpg'))
      .toList();
  expect(thumbnails, hasLength(1));
  expect(thumbnails.single.fit, BoxFit.cover);
  expect(thumbnails.single.alignment, Alignment.topCenter);

  final mediaViewport = tester.widget<Positioned>(
    find.byKey(const ValueKey('feed-video-media-viewport')),
  );
  expect(mediaViewport.top, 0);
  expect(mediaViewport.bottom, 0);
});
```

- [ ] **Step 2: Run the new test and verify it fails**

Run:

```powershell
flutter test test\features\feed\widgets\feed_video_post_view_test.dart --plain-name "fullscreen Feed uses one top-aligned cover thumbnail without bottom inset"
```

Working directory: `flutter_app`.

Expected: compilation fails because `FeedVideoFraming.fullscreenFeed` does not exist.

- [ ] **Step 3: Add the enum value and cover-family rendering**

Extend the enum:

```dart
enum FeedVideoFraming {
  immersive,
  mainFeed,
  fullscreenFeed,
}
```

Keep the media bottom inset exclusive to `mainFeed`:

```dart
final mainFeedFraming =
    widget.framing == FeedVideoFraming.mainFeed && !minimized;
final mediaBottomInset =
    mainFeedFraming ? MediaQuery.paddingOf(context).bottom : 0.0;
```

For initialized video and thumbnail rendering, treat both cover modes alike:

```dart
final coverFraming = framing == FeedVideoFraming.mainFeed ||
    framing == FeedVideoFraming.fullscreenFeed;
```

Use `coverFraming` in both existing branches that currently compare only
against `FeedVideoFraming.mainFeed`. Preserve the compact-preview branch before
this check so it remains `BoxFit.contain`.

- [ ] **Step 4: Add an initialized-player regression test**

Add a test based on the existing main Feed initialized-player test:

```dart
testWidgets('fullscreen Feed initialized player uses cover topCenter framing',
    (tester) async {
  VisibilityDetectorController.instance.updateInterval = Duration.zero;
  final platform = _FakeVideoPlayerPlatform();
  VideoPlayerPlatform.instance = platform;
  final controller = VideoPlayerController.networkUrl(
    Uri.parse('https://example.com/fullscreen-feed.m3u8'),
  );
  await controller.initialize();

  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(393, 852)),
      child: MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(aspectRatio: 9 / 16, hls: true),
          isActive: true,
          preloadedController: controller,
          framing: FeedVideoFraming.fullscreenFeed,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();

  final fittedBoxes = tester.widgetList<FittedBox>(
    find.descendant(
      of: find.byKey(const ValueKey('feed-video-media-viewport')),
      matching: find.byType(FittedBox),
    ),
  );
  expect(fittedBoxes, isNotEmpty);
  expect(fittedBoxes.last.fit, BoxFit.cover);
  expect(fittedBoxes.last.alignment, Alignment.topCenter);
});
```

- [ ] **Step 5: Run focused framing tests**

Run:

```powershell
flutter test test\features\feed\widgets\feed_video_post_view_test.dart
```

Expected: all tests pass, including existing `mainFeed`, compact preview, and
default `immersive` assertions.

- [ ] **Step 6: Commit Task 1**

```powershell
git add flutter_app/lib/features/feed/widgets/feed_video_post_view.dart flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart
git commit -m "feat(feed): add fullscreen cover framing"
```

---

### Task 2: Wire both scoped fullscreen ownership paths

**Files:**
- Modify: `flutter_app/lib/screens/scoped_video_feed_screen.dart:681-725`
- Test: `flutter_app/test/screens/scoped_video_feed_screen_test.dart`

**Interfaces:**
- Consumes: `FeedVideoFraming.fullscreenFeed` produced by Task 1.
- Produces: Identical fullscreen framing for legacy-owned and coordinator-managed `FeedVideoPostView` instances.

- [ ] **Step 1: Write a failing legacy-path wiring test**

Add near the initial-index screen tests:

```dart
testWidgets('legacy scoped fullscreen selects fullscreen Feed framing',
    (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ScopedVideoFeedScreen(
        posts: [_fakeVideoPost('legacy-framing')],
        initialIndex: 0,
      ),
    ),
  );
  await tester.pump();

  final view = tester.widget<FeedVideoPostView>(
    find.byType(FeedVideoPostView),
  );
  expect(view.framing, FeedVideoFraming.fullscreenFeed);
  await tester.pump(const Duration(milliseconds: 600));
});
```

- [ ] **Step 2: Write a failing managed-path wiring test**

Use the coordinator helper already defined in the managed test group and add:

```dart
testWidgets('managed scoped fullscreen selects fullscreen Feed framing',
    (tester) async {
  await pumpScoped(
    tester,
    posts: [_fakeVideoPost('managed-framing')],
  );

  final view = tester.widget<FeedVideoPostView>(
    find.byKey(const ValueKey('scoped-fs-managed-framing')),
  );
  expect(view.framing, FeedVideoFraming.fullscreenFeed);
});
```

- [ ] **Step 3: Run both tests and verify they fail**

Run:

```powershell
flutter test test\screens\scoped_video_feed_screen_test.dart --plain-name "legacy scoped fullscreen selects fullscreen Feed framing"
flutter test test\screens\scoped_video_feed_screen_test.dart --plain-name "managed scoped fullscreen selects fullscreen Feed framing"
```

Expected: both fail because the views still use `FeedVideoFraming.immersive`.

- [ ] **Step 4: Wire the policy into both `_buildItem` branches**

In the no-coordinator branch add:

```dart
framing: FeedVideoFraming.fullscreenFeed,
```

In the coordinator-managed branch add the same property after `isActive`:

```dart
framing: FeedVideoFraming.fullscreenFeed,
```

Do not change controller, visibility, playback, pause, or preload callbacks.

- [ ] **Step 5: Run scoped fullscreen tests**

Run:

```powershell
flutter test test\screens\scoped_video_feed_screen_test.dart
```

Expected: all tests pass, including ownership, preload, swipe, edge-back, and
return timestamp coverage.

- [ ] **Step 6: Run combined regression checks**

Run from `flutter_app`:

```powershell
flutter test test\features\feed\widgets\feed_video_post_view_test.dart test\screens\scoped_video_feed_screen_test.dart
flutter analyze lib\features\feed\widgets\feed_video_post_view.dart lib\screens\scoped_video_feed_screen.dart test\features\feed\widgets\feed_video_post_view_test.dart test\screens\scoped_video_feed_screen_test.dart
```

Expected: all tests pass and analyzer reports `No issues found!`.

- [ ] **Step 7: Review the final diff**

Confirm all of the following before committing:

- only the enum, cover-family checks, two scoped call sites, and focused tests changed;
- `mediaBottomInset` remains exclusive to `mainFeed`;
- compact comment preview still reaches its `BoxFit.contain` branch first;
- no controller or playback callback changed;
- no unrelated dirty file is staged.

- [ ] **Step 8: Commit Task 2**

```powershell
git add flutter_app/lib/screens/scoped_video_feed_screen.dart flutter_app/test/screens/scoped_video_feed_screen_test.dart
git commit -m "fix(feed): align scoped fullscreen framing"
```
