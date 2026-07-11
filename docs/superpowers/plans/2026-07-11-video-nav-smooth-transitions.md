# Video Nav Smooth Transitions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tap-video from "Postingan Terkait" opens a scoped, immersive feed-style video viewer with a scale-morph transition from the thumbnail (Flow A). Tap-video inside the existing profile "Postingan" list expands in-place to a fullscreen immersive overlay without restarting playback, and shrinks back on close (Flow B).

**Architecture:** Extract the private `_FeedPostView` (feed_screen.dart) into a public, reusable `FeedVideoPostView` widget so both `FeedScreen` (unchanged behavior) and a new `ScopedVideoFeedScreen` (Flow A) render identical feed UI. Flow A uses a custom `PageRouteBuilder` that morphs a thumbnail's on-screen rect into fullscreen before revealing the immersive `PageView`. Flow B stays inside `member_post_detail_screen.dart`: the existing `_InlineVideoPlayer` gains a tap handler that hands its live `VideoPlayerController`/`CachedVideoPlayerPlus` to a new fullscreen overlay (replacing the dead, restart-prone `_FullScreenVideoRoute`), so playback position is never interrupted.

**Tech Stack:** Flutter/Dart, `video_player` + `cached_video_player_plus`, `visibility_detector`, existing `feedService`/`feedStore` singletons.

## Global Constraints

- Foto/carousel behavior must NOT change anywhere (existing Hero `post-thumb-${post.id}` stays exactly as-is).
- No new implementation for the "swipe scope" outside what's in the design: Flow A swipes only within the caller-supplied `posts` list (already scoped by the caller); Flow B has no swipe (single post, fullscreen only).
- Do not touch `public_profile_screen.dart` or `member_screen.dart` navigation — Flow B lives entirely inside `member_post_detail_screen.dart`; those two screens keep pushing `MemberPostDetailScreen` exactly as today.
- `_FullScreenVideoRoute` and its instantiation are dead code today (grep-confirmed, no callers) — remove it as part of Task 6, do not leave both old and new fullscreen implementations coexisting.
- Reuse `feedService`/`feedStore` for all like/comment/share actions — never write a second state source for like counts (this is how counts stay in sync across `FeedScreen`, `ScopedVideoFeedScreen`, and `MemberPostDetailScreen`).
- Run `flutter analyze` and the full test suite before each commit that touches `feed_screen.dart` or `member_post_detail_screen.dart` — both are large, high-traffic files.

---

## File Structure

**Create:**
- `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart` — `FeedVideoPostView` (public, extracted from `_FeedPostView`).
- `flutter_app/lib/screens/scoped_video_feed_screen.dart` — `ScopedVideoFeedScreen` (Flow A immersive PageView).
- `flutter_app/lib/widgets/scaled_video_feed_route.dart` — `pushScaledVideoFeed()` helper + `_ScaledVideoFeedRoute` (custom `PageRouteBuilder`, shared by Flow A).
- `flutter_app/lib/screens/member_post_detail_screen.dart` — (modify) add `_FullscreenInlineVideoOverlay` replacing dead `_FullScreenVideoRoute`, wire tap handler.
- `flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart`
- `flutter_app/test/screens/scoped_video_feed_screen_test.dart`
- `flutter_app/test/screens/member_post_detail_screen_fullscreen_test.dart`

**Modify:**
- `flutter_app/lib/screens/feed_screen.dart` — remove `_FeedPostView`/`_FeedPostViewState`, import + use `FeedVideoPostView`.
- `flutter_app/lib/screens/product_detail_screen.dart` — `_CustomerPostCard._openPost` branches on `isVideo`.
- `flutter_app/lib/screens/member_post_detail_screen.dart` — `_InlineVideoPlayer` gains tap-to-expand; dead `_FullScreenVideoRoute`/`_RoundIconButton` removed and replaced.

---

### Task 1: Extract `FeedVideoPostView` from `feed_screen.dart`

**Files:**
- Create: `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart`
- Modify: `flutter_app/lib/screens/feed_screen.dart`
- Test: `flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart`

**Interfaces:**
- Consumes: nothing new — `FeedPost` (`lib/models/feed_post.dart`), `feedStore`/`feedService` singletons, `appSettingsStore`, `FeedActionRail` (`lib/features/feed/widgets/feed_action_rail.dart`), `FeedCreatorIdentity`/`FeedExpandableCaption` (`lib/features/feed/widgets/feed_creator_overlay.dart`) — all already used by the code being moved.
- Produces: `FeedVideoPostView` public widget with this exact constructor (same shape as the current private `_FeedPostView`, just renamed and made public):

```dart
class FeedVideoPostView extends StatefulWidget {
  final FeedPost post;
  final bool isActive;
  final VideoPlayerController? preloadedController;
  final CachedVideoPlayerPlus? preloadedCachedPlayer;
  final ValueChanged<bool> onOverlayStateChanged;
  final ValueChanged<bool> onMediaZoomChanged;

  const FeedVideoPostView({
    super.key,
    required this.post,
    required this.isActive,
    required this.preloadedController,
    required this.onOverlayStateChanged,
    required this.onMediaZoomChanged,
    this.preloadedCachedPlayer,
  });

  @override
  State<FeedVideoPostView> createState() => _FeedVideoPostViewState();
}
```

Later tasks (2, 3) instantiate `FeedVideoPostView` exactly like `FeedScreen` does today — same required params, same optional `preloadedCachedPlayer`.

- [ ] **Step 1: Locate the exact bounds of the code to move**

Run:
```bash
cd flutter_app
grep -n "^class _FeedPostView\|^class _FeedPostViewState\|^class _PhotoCarouselPostView\|^class _ProductAnchorTapZone\|^Product _productFromFeedLink\|^class _FeedProductPricing" lib/screens/feed_screen.dart
```

This prints every top-level class/function boundary near `_FeedPostView`. `_FeedPostView` starts at the `class _FeedPostView extends StatefulWidget` line; its full body (widget + `_FeedPostViewState`) ends at the line immediately before the NEXT top-level `class`/`Product`/etc. declaration printed by this grep. Note that exact start/end line numbers — they will differ slightly from any line numbers quoted elsewhere in this plan because earlier edits to the file shift line numbers.

Also run:
```bash
grep -n "_productFromFeedLink\|_FeedProductPricing\|_feedProductPricing" lib/screens/feed_screen.dart
```
`_FeedPostViewState` calls `_productFromFeedLink()` (which calls `_feedProductPricing()`, returning a `_FeedProductPricing` record) when rendering a tagged-product chip tap. These three symbols must move together with `_FeedPostView` — confirm none of them are used by any OTHER class still remaining in `feed_screen.dart` (grep for other callers) before moving. If `_productFromFeedLink`/`_feedProductPricing`/`_FeedProductPricing` are used elsewhere in the file (e.g. by `_PhotoCarouselPostView` for its own product chips), duplicate them into the new file instead of moving (do not leave `feed_screen.dart` broken).

- [ ] **Step 2: Create the new file with package header + copied class**

Create `flutter_app/lib/features/feed/widgets/feed_video_post_view.dart` starting with:

```dart
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../models/feed_post.dart';
import '../../../models/product.dart';
import '../../../services/app_analytics.dart';
import '../../../services/feed_service.dart';
import '../../../services/video_quality_service.dart';
import '../../../state/feed_store.dart';
import '../../../state/follow_override_store.dart';
import '../../../state/settings_store.dart';
import '../../../utils/haptics.dart';
import '../../../widgets/feed_comment_sheet.dart';
import 'feed_action_rail.dart';
import 'feed_creator_overlay.dart';
```

Then paste the verbatim class bodies identified in Step 1 (`_FeedPostView` → renamed `FeedVideoPostView`, `_FeedPostViewState` → renamed `_FeedVideoPostViewState`, plus `_productFromFeedLink`/`_feedProductPricing`/`_FeedProductPricing` if they moved). Do the rename with a project-wide search-replace scoped to this new file only (`_FeedPostView` → `FeedVideoPostView`, `_FeedPostViewState` → `_FeedVideoPostViewState`) — do not rename anything in `feed_screen.dart` yet.

Fix the import list by running `dart fix --dry-run` against the new file and adding/removing imports it flags (the list above is a best-effort starting point based on symbols known to be used — `CachedNetworkImageProvider`/`precacheImage`, `FeedCommentSheet`, `showModerationActions`, `Share.share`, `FeedProductLink`, `videoQualityService`, `followOverrideStore` etc. are all referenced by the moved code per the existing behavior).

- [ ] **Step 3: Remove the moved code from `feed_screen.dart` and import the new widget**

Delete the `_FeedPostView`/`_FeedPostViewState` classes (and any helpers moved in Step 2) from `feed_screen.dart`. Add:

```dart
import '../features/feed/widgets/feed_video_post_view.dart';
```

Update the `PageView.builder` itemBuilder (search `return _FeedPostView(` in `feed_screen.dart`) to instantiate the new public widget name instead:

```dart
                      return FeedVideoPostView(
                        post: post,
                        isActive: index == _activeIndex,
                        preloadedController:
                            _preloadedControllers.remove(post.id),
                        preloadedCachedPlayer:
                            _preloadedCachedPlayers.remove(post.id),
                        onOverlayStateChanged: _setFeedInteractionLocked,
                        onMediaZoomChanged: _setFeedMediaZooming,
                      );
```

(This is a pure rename at the call site — every argument is unchanged from what `feed_screen.dart` already passes today.)

- [ ] **Step 4: Verify `feed_screen.dart` still compiles standalone**

Run:
```bash
cd flutter_app
flutter analyze lib/screens/feed_screen.dart lib/features/feed/widgets/feed_video_post_view.dart
```
Expected: no errors. Fix any leftover references to the old private names or missing imports until this is clean.

- [ ] **Step 5: Write a smoke test for the extracted widget**

```dart
// flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalopetshopflutter/features/feed/widgets/feed_video_post_view.dart';
import 'package:natalopetshopflutter/models/feed_post.dart';

FeedPost _fakeVideoPost({String id = 'post-1'}) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'USER_VIDEO',
    'videoUrl': 'https://example.com/$id.mp4',
    'thumbnailUrl': 'https://example.com/$id.jpg',
    'durationSec': 10,
    'aspectRatio': 0.5625,
    'author': {'id': 'author-1', 'name': 'Tester'},
    'likeCount': 0,
    'commentCount': 0,
    'shareCount': 0,
    'createdAt': DateTime.now().toIso8601String(),
  });
}

void main() {
  testWidgets('FeedVideoPostView renders without preloaded controller', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FeedVideoPostView(
          post: _fakeVideoPost(),
          isActive: true,
          preloadedController: null,
          onOverlayStateChanged: (_) {},
          onMediaZoomChanged: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(FeedVideoPostView), findsOneWidget);
  });
}
```

Adjust the `FeedPost.fromJson` payload keys to match the actual required/optional fields if `flutter analyze`/the test run surfaces missing-field errors — the model's exact `fromJson` contract should be checked in `lib/models/feed_post.dart` if this fails.

- [ ] **Step 6: Run the test**

Run: `cd flutter_app && flutter test test/features/feed/widgets/feed_video_post_view_test.dart`
Expected: PASS (1 test). If it hangs (this repo has a known shimmer/`pumpAndSettle` hang issue with product/feed image widgets — use bounded `tester.pump(Duration(...))` loops instead of `pumpAndSettle()` if that happens, per existing test patterns in `flutter_app/test/`).

- [ ] **Step 7: Full regression check + commit**

Run: `cd flutter_app && flutter analyze && flutter test`
Expected: no new failures versus the pre-change baseline (feed-related widget/golden tests must still pass — this is a pure extraction, no behavior change).

```bash
git add flutter_app/lib/features/feed/widgets/feed_video_post_view.dart flutter_app/lib/screens/feed_screen.dart flutter_app/test/features/feed/widgets/feed_video_post_view_test.dart
git commit -m "refactor(feed): extract FeedVideoPostView from feed_screen for reuse"
```

---

### Task 2: `pushScaledVideoFeed()` transition helper

**Files:**
- Create: `flutter_app/lib/widgets/scaled_video_feed_route.dart`

**Interfaces:**
- Consumes: nothing from other tasks (pure Flutter `PageRouteBuilder` + `RenderBox` geometry).
- Produces:

```dart
Future<void> pushScaledVideoFeed(
  BuildContext context, {
  required GlobalKey thumbnailKey,
  required String thumbnailImageUrl,
  required double thumbnailBorderRadius,
  required WidgetBuilder destinationBuilder,
})
```

Task 3 calls this with `destinationBuilder: (_) => ScopedVideoFeedScreen(posts: ..., initialIndex: ...)`.

- [ ] **Step 1: Write the route + helper**

```dart
// flutter_app/lib/widgets/scaled_video_feed_route.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Pushes [destinationBuilder] with a scale/morph transition: the
/// on-screen rect of the widget attached to [thumbnailKey] grows to fill
/// the screen (~440ms, easeOutCubic) before the destination becomes
/// interactive. A snapshot image ([thumbnailImageUrl]) is shown scaling
/// up — NOT the destination's live video — so no video frame renders at
/// a "shrunk" size mid-animation.
Future<void> pushScaledVideoFeed(
  BuildContext context, {
  required GlobalKey thumbnailKey,
  required String thumbnailImageUrl,
  required double thumbnailBorderRadius,
  required WidgetBuilder destinationBuilder,
}) {
  final renderBox = thumbnailKey.currentContext?.findRenderObject() as RenderBox?;
  final origin = renderBox != null
      ? renderBox.localToGlobal(Offset.zero) & renderBox.size
      : null;

  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 440),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) {
        return destinationBuilder(context);
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        final screenSize = MediaQuery.of(context).size;
        return Stack(
          fit: StackFit.expand,
          children: [
            // Destination fades in once the scale is mostly complete —
            // avoids a visible "cut" from snapshot to live video.
            FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: const Interval(0.55, 1.0, curve: Curves.easeIn),
              ),
              child: child,
            ),
            if (origin != null)
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: curved,
                  builder: (context, _) {
                    final t = curved.value;
                    // Snapshot rect morphs from `origin` to fullscreen.
                    final left = origin.left + (0 - origin.left) * t;
                    final top = origin.top + (0 - origin.top) * t;
                    final width = origin.width + (screenSize.width - origin.width) * t;
                    final height = origin.height + (screenSize.height - origin.height) * t;
                    final radius = thumbnailBorderRadius * (1 - t);
                    return Positioned(
                      left: left,
                      top: top,
                      width: width,
                      height: height,
                      child: Opacity(
                        // Snapshot fades OUT over the same interval the
                        // destination fades in, so there is no double-
                        // exposure flash.
                        opacity: 1 - CurvedAnimation(
                          parent: animation,
                          curve: const Interval(0.55, 1.0, curve: Curves.easeIn),
                        ).value,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(radius),
                          child: CachedNetworkImage(
                            imageUrl: thumbnailImageUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    ),
  );
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd flutter_app && flutter analyze lib/widgets/scaled_video_feed_route.dart`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add flutter_app/lib/widgets/scaled_video_feed_route.dart
git commit -m "feat(feed): add pushScaledVideoFeed thumbnail-to-fullscreen transition helper"
```

---

### Task 3: `ScopedVideoFeedScreen` (Flow A immersive PageView)

**Files:**
- Create: `flutter_app/lib/screens/scoped_video_feed_screen.dart`
- Test: `flutter_app/test/screens/scoped_video_feed_screen_test.dart`

**Interfaces:**
- Consumes: `FeedVideoPostView` (Task 1), `FeedPost` model, `feedStore`/`feedService`.
- Produces:

```dart
class ScopedVideoFeedScreen extends StatefulWidget {
  final List<FeedPost> posts;   // video-only, caller filters
  final int initialIndex;

  const ScopedVideoFeedScreen({
    super.key,
    required this.posts,
    required this.initialIndex,
  });
}
```

Task 4 (product detail entry point) constructs this directly as the `destinationBuilder` passed to `pushScaledVideoFeed`.

- [ ] **Step 1: Write the screen**

```dart
// flutter_app/lib/screens/scoped_video_feed_screen.dart
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../features/feed/widgets/feed_video_post_view.dart';
import '../models/feed_post.dart';
import '../state/feed_store.dart';

/// Immersive, vertically swipeable video viewer scoped to a caller-
/// supplied list of videos (e.g. "videos tagged to this product", or
/// "videos posted by this user"). Reuses [FeedVideoPostView] so visuals
/// are identical to the main Feed tab. Swiping never leaves [posts].
class ScopedVideoFeedScreen extends StatefulWidget {
  final List<FeedPost> posts;
  final int initialIndex;

  const ScopedVideoFeedScreen({
    super.key,
    required this.posts,
    required this.initialIndex,
  });

  @override
  State<ScopedVideoFeedScreen> createState() => _ScopedVideoFeedScreenState();
}

class _ScopedVideoFeedScreenState extends State<ScopedVideoFeedScreen> {
  late final PageController _pageController;
  late int _activeIndex;
  final Map<String, VideoPlayerController> _preloadedControllers = {};
  final Map<String, CachedVideoPlayerPlus> _preloadedCachedPlayers = {};

  @override
  void initState() {
    super.initState();
    _activeIndex = widget.initialIndex.clamp(0, widget.posts.length - 1);
    _pageController = PageController(initialPage: _activeIndex);
    feedStore.seed(widget.posts);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _preloadedCachedPlayers.values) {
      c.dispose();
    }
    for (final c in _preloadedControllers.values) {
      // Only dispose controllers that were never claimed by a
      // CachedVideoPlayerPlus wrapper above (avoid double-dispose).
      if (!_preloadedCachedPlayers.values.any((w) => w.controller == c)) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _activeIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            physics: const PageScrollPhysics(parent: BouncingScrollPhysics()),
            itemCount: widget.posts.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              final post = widget.posts[index];
              return FeedVideoPostView(
                post: post,
                isActive: index == _activeIndex,
                preloadedController: _preloadedControllers.remove(post.id),
                preloadedCachedPlayer: _preloadedCachedPlayers.remove(post.id),
                onOverlayStateChanged: (_) {},
                onMediaZoomChanged: (_) {},
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.maybePop(context),
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.chevron_left_rounded, color: Colors.white, size: 26),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

(No sliding preload window is implemented here — `posts` lists from Postingan Terkait / "videos by this user" are small, so preloading ±1 is out of scope for a first cut; `FeedVideoPostView` already lazily inits its own controller via `_maybeInitVideo()`-equivalent internal logic when `preloadedController` is null, matching how `FeedScreen` behaves for un-preloaded items.)

- [ ] **Step 2: Verify it compiles**

Run: `cd flutter_app && flutter analyze lib/screens/scoped_video_feed_screen.dart`
Expected: no errors.

- [ ] **Step 3: Write a widget test for initial-index scroll**

```dart
// flutter_app/test/screens/scoped_video_feed_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalopetshopflutter/models/feed_post.dart';
import 'package:natalopetshopflutter/screens/scoped_video_feed_screen.dart';

FeedPost _fakeVideoPost(String id) {
  return FeedPost.fromJson({
    'id': id,
    'slug': id,
    'kind': 'USER_VIDEO',
    'videoUrl': 'https://example.com/$id.mp4',
    'thumbnailUrl': 'https://example.com/$id.jpg',
    'durationSec': 10,
    'aspectRatio': 0.5625,
    'author': {'id': 'author-1', 'name': 'Tester'},
    'likeCount': 0,
    'commentCount': 0,
    'shareCount': 0,
    'createdAt': DateTime.now().toIso8601String(),
  });
}

void main() {
  testWidgets('ScopedVideoFeedScreen opens at initialIndex', (tester) async {
    final posts = [_fakeVideoPost('a'), _fakeVideoPost('b'), _fakeVideoPost('c')];
    await tester.pumpWidget(
      MaterialApp(
        home: ScopedVideoFeedScreen(posts: posts, initialIndex: 1),
      ),
    );
    await tester.pump();
    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.controller?.initialPage, 1);
  });
}
```

- [ ] **Step 4: Run the test**

Run: `cd flutter_app && flutter test test/screens/scoped_video_feed_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/scoped_video_feed_screen.dart flutter_app/test/screens/scoped_video_feed_screen_test.dart
git commit -m "feat(feed): add ScopedVideoFeedScreen for context-scoped video viewing"
```

---

### Task 4: Wire "Postingan Terkait" tap-video to Flow A

**Files:**
- Modify: `flutter_app/lib/screens/product_detail_screen.dart` (`_CustomerPostCard` class, `_openPost` method, and the `build()` method to attach a `GlobalKey`)

**Interfaces:**
- Consumes: `pushScaledVideoFeed` (Task 2), `ScopedVideoFeedScreen` (Task 3), existing `feedService.fetchPostById(String id) → Future<FeedPost?>`, existing `_ProductCustomerPost` model (`id`, `kind`, `title`, `thumbnailUrl`, `durationSec`, `likeCount`, `commentCount`, `authorName`, `authorIsOfficial`, and `bool get isVideo => kind != 'PHOTO_CAROUSEL'`).
- Produces: no new public API — this is a leaf UI change.

- [ ] **Step 1: Give `_CustomerPostCard` a `GlobalKey` and access to sibling posts**

`_CustomerPostCard` currently only receives a single `post` (the `_ProductCustomerPost` being rendered). It needs the full sibling list to build the scoped video list. Find where `_CustomerPostCard` is instantiated (inside `_ProductCustomerPostsSection.build()`, the `ListView.separated.itemBuilder` — search `_CustomerPostCard(post: posts[index])` in `product_detail_screen.dart`) and change it to also pass the full list + index:

```dart
                    itemBuilder: (context, index) {
                      return _CustomerPostCard(
                        post: posts[index],
                        allPosts: posts,
                        index: index,
                      );
                    },
```

Update the widget declaration:

```dart
class _CustomerPostCard extends StatelessWidget {
  final _ProductCustomerPost post;
  final List<_ProductCustomerPost> allPosts;
  final int index;

  const _CustomerPostCard({
    required this.post,
    required this.allPosts,
    required this.index,
  });

  final _thumbnailKey = GlobalKey(); // added as an instance field below in the State-equivalent — see Step 2 note
```

Note: `_CustomerPostCard` is currently a `StatelessWidget`. A `GlobalKey` must be stable across rebuilds but does NOT require converting to `StatefulWidget` — declare it as a `final` field initialized in the constructor body is not possible on a `const`-style stateless widget with `final` fields set via initializer list, so instead give it a plain (non-const) constructor and initialize the key with `GlobalKey()` directly as a field initializer:

```dart
class _CustomerPostCard extends StatelessWidget {
  final _ProductCustomerPost post;
  final List<_ProductCustomerPost> allPosts;
  final int index;
  final GlobalKey _thumbnailKey = GlobalKey();

  _CustomerPostCard({
    required this.post,
    required this.allPosts,
    required this.index,
  }); // no `const` — GlobalKey() can't be const
```

(Drop `const` from the constructor and from any `const _CustomerPostCard(...)` call sites — there are none today since it's built inside an `itemBuilder`.)

- [ ] **Step 2: Wrap the existing thumbnail `Stack` with the `GlobalKey`**

In `build()`, the outer `ClipRRect > Stack` currently has no key. Attach `_thumbnailKey` to the `AppPressable`'s child (the `ClipRRect`):

```dart
        child: AppPressable(
          onTap: () => _openPost(context),
          borderRadius: BorderRadius.circular(14),
          child: ClipRRect(
            key: _thumbnailKey,
            borderRadius: BorderRadius.circular(14),
```

- [ ] **Step 3: Branch `_openPost` on `post.isVideo`**

Replace the existing `_openPost` body's final `Navigator.of(context).push(...)` block with a branch. Keep the loading-dialog + `fetchPostById` logic identical (it still fetches the FULL `FeedPost` for the tapped post — needed either way), but for video, fetch the sibling video posts too and push the scoped feed instead:

```dart
  Future<void> _openPost(BuildContext context) async {
    AppHaptics.tap();
    final rootNav = Navigator.of(context, rootNavigator: true);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (_) => const Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      ),
    );

    if (!post.isVideo) {
      FeedPost? feedPost;
      var failed = false;
      try {
        feedPost = await feedService.fetchPostById(post.id);
      } catch (_) {
        failed = true;
      }
      rootNav.pop();
      if (!context.mounted) return;
      if (feedPost == null) {
        AppToast.show(
          context,
          failed
              ? 'Postingan belum bisa dibuka. Coba lagi.'
              : 'Postingan sudah tidak tersedia.',
          kind: ToastKind.warning,
        );
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MemberPostDetailScreen(
            post: feedPost!,
            authorName: feedPost.author.displayName,
            authorPhotoUrl: feedPost.author.profilePhotoUrl,
            authorInitial: feedPost.author.initial,
            isOwner: false,
          ),
        ),
      );
      return;
    }

    // Video path — fetch every video sibling in this "Postingan Terkait"
    // section so swipe stays scoped to videos tagged to this product.
    final videoSiblings = allPosts.where((p) => p.isVideo).toList();
    final fetched = <FeedPost>[];
    var anyFailed = false;
    for (final sibling in videoSiblings) {
      try {
        final fp = await feedService.fetchPostById(sibling.id);
        if (fp != null) fetched.add(fp);
      } catch (_) {
        anyFailed = true;
      }
    }

    rootNav.pop();
    if (!context.mounted) return;

    if (fetched.isEmpty) {
      AppToast.show(
        context,
        anyFailed
            ? 'Postingan belum bisa dibuka. Coba lagi.'
            : 'Postingan sudah tidak tersedia.',
        kind: ToastKind.warning,
      );
      return;
    }

    final tappedIndex = fetched.indexWhere((fp) => fp.id == post.id);
    await pushScaledVideoFeed(
      context,
      thumbnailKey: _thumbnailKey,
      thumbnailImageUrl: post.thumbnailUrl,
      thumbnailBorderRadius: 14,
      destinationBuilder: (_) => ScopedVideoFeedScreen(
        posts: fetched,
        initialIndex: tappedIndex >= 0 ? tappedIndex : 0,
      ),
    );
  }
```

Add the two new imports at the top of `product_detail_screen.dart`:

```dart
import 'scoped_video_feed_screen.dart';
import '../widgets/scaled_video_feed_route.dart';
```

- [ ] **Step 4: Verify it compiles**

Run: `cd flutter_app && flutter analyze lib/screens/product_detail_screen.dart`
Expected: no errors.

- [ ] **Step 5: Widget test — tap video routes to `ScopedVideoFeedScreen`, tap photo routes to `MemberPostDetailScreen`**

Check whether a test file already exists for `product_detail_screen.dart` under `flutter_app/test/screens/`; if so add to it, otherwise create `flutter_app/test/screens/product_detail_screen_related_posts_test.dart`. Because `_CustomerPostCard`/`_ProductCustomerPost` are private to `product_detail_screen.dart`, this test must pump the real `ProductDetailScreen` with a mocked `productService`/`feedService` response (mirror whatever mocking pattern existing `product_detail_screen` tests already use — check `flutter_app/test/` for an existing example before writing new mocks from scratch). At minimum assert:

```dart
testWidgets('tapping a video related-post pushes ScopedVideoFeedScreen', (tester) async {
  // ... pump ProductDetailScreen with a mocked customer-post feed
  //     containing one VIDEO kind post ...
  await tester.tap(find.byType(_customerPostCardVideoTileFinder)); // use whatever Finder locates the rendered tile (e.g. by Key or by icon)
  await tester.pumpAndSettle();
  expect(find.byType(ScopedVideoFeedScreen), findsOneWidget);
});

testWidgets('tapping a photo related-post pushes MemberPostDetailScreen', (tester) async {
  // ... same setup with a PHOTO_CAROUSEL kind post ...
  await tester.tap(find.byType(_customerPostCardPhotoTileFinder));
  await tester.pumpAndSettle();
  expect(find.byType(MemberPostDetailScreen), findsOneWidget);
});
```

Since `_CustomerPostCard` is private, locate the tile in tests via a public ancestor `Finder` such as `find.byIcon(Icons.play_arrow_rounded)` (the play glyph shown only on video tiles) or by wrapping the tappable `AppPressable` — inspect the actual rendered icon/text in `_CustomerPostTypeBadge` to pick a reliable `Finder` before finalizing this test.

- [ ] **Step 6: Run the tests**

Run: `cd flutter_app && flutter test test/screens/product_detail_screen_related_posts_test.dart` (or wherever Step 5 added them)
Expected: both PASS.

- [ ] **Step 7: Full regression + commit**

Run: `cd flutter_app && flutter analyze && flutter test`
Expected: no new failures.

```bash
git add flutter_app/lib/screens/product_detail_screen.dart flutter_app/test/screens/product_detail_screen_related_posts_test.dart
git commit -m "feat(product-detail): route video related-posts to scoped immersive feed"
```

---

### Task 5: Add tap-to-expand on `_InlineVideoPlayer` (Flow B, part 1)

**Files:**
- Modify: `flutter_app/lib/screens/member_post_detail_screen.dart` (`_InlineVideoPlayer`/`_InlineVideoPlayerState`)

**Interfaces:**
- Consumes: nothing from other tasks yet (Task 6 supplies the destination overlay).
- Produces: `_InlineVideoPlayerState` exposes its live controller via a new `onExpandRequested` callback fired on tap, carrying enough info for Task 6's overlay to attach to the SAME controller (not a new one).

```dart
class _InlineVideoPlayer extends StatefulWidget {
  final String postId;
  final String mediaUrl;
  final String? thumbnailUrl;
  final double aspectRatio;
  final void Function(VideoPlayerController controller, GlobalKey anchorKey)? onExpandRequested;

  const _InlineVideoPlayer({
    required this.postId,
    required this.mediaUrl,
    required this.thumbnailUrl,
    required this.aspectRatio,
    this.onExpandRequested,
  });
```

Task 6 reads this via the `_PostMediaSurface` call site, passing a callback that opens the fullscreen overlay.

- [ ] **Step 1: Add the callback param + a stable anchor `GlobalKey`**

In `_InlineVideoPlayerState`, add:

```dart
  final GlobalKey _anchorKey = GlobalKey();
```

Wrap the outermost `Stack` (currently returned directly by `build()`) with the key, and add a `GestureDetector` around the video content specifically (NOT the existing mute-button `GestureDetector`, which must keep working independently) that fires `widget.onExpandRequested`:

```dart
  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return VisibilityDetector(
      key: ValueKey('inline-video-${widget.postId}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: GestureDetector(
        key: _anchorKey,
        behavior: HitTestBehavior.opaque,
        onTap: ready && widget.onExpandRequested != null
            ? () => widget.onExpandRequested!(controller, _anchorKey)
            : null,
        child: AbsorbPointer(
          absorbing: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ... unchanged existing children (Container(color: Colors.black), video/thumbnail, spinner, error text) ...
```

Keep every existing child exactly as-is EXCEPT the mute-button's `Positioned(... GestureDetector(onTap: _toggleMute, ...))` — that one must remain reachable (tapping the mute icon should NOT also trigger expand). Since `GestureDetector`s in Flutter don't nest-cancel automatically, verify at Step 3 that tapping the mute icon toggles mute WITHOUT also firing `onExpandRequested` (the inner `GestureDetector`'s opaque hit-test on the smaller icon area wins over the outer one for taps landing inside the icon's bounds — this is standard Flutter gesture arena behavior, but confirm via the widget test in Step 3).

- [ ] **Step 2: Wire the callback through `_PostMediaSurface`**

`_PostMediaSurface` currently constructs `_InlineVideoPlayer` with no `onExpandRequested`. It needs to receive one from its own parent (`_PostFeedItem`) and forward it. Add a param to `_PostMediaSurface`:

```dart
class _PostMediaSurface extends StatelessWidget {
  final FeedPost post;
  final void Function(VideoPlayerController controller, GlobalKey anchorKey)? onVideoExpandRequested;

  const _PostMediaSurface({required this.post, this.onVideoExpandRequested});

  @override
  Widget build(BuildContext context) {
    final aspectRatio = _safeAspectRatio(
      post.aspectWidthInt,
      post.aspectHeightInt,
      type: post.contentType,
    );
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: switch (post.contentType) {
        FeedContentType.video => _InlineVideoPlayer(
            postId: post.id,
            mediaUrl: post.videoPlaybackUrl,
            thumbnailUrl: post.thumbnailUrl,
            aspectRatio: aspectRatio,
            onExpandRequested: onVideoExpandRequested,
          ),
        // ... carousel/photo branches unchanged ...
      },
    );
  }
}
```

Then find where `_PostMediaSurface(post: post)` is instantiated inside `_PostFeedItemState.build()` (the `GestureDetector` wrapping it for double-tap-to-like) and pass a callback through — for now (this task), pass a no-op placeholder; Task 6 replaces it with the real overlay-opening logic:

```dart
              _PostMediaSurface(
                post: post,
                onVideoExpandRequested: (controller, anchorKey) {
                  // TODO(Task 6): open fullscreen overlay with `controller`.
                },
              ),
```

(This TODO is intentional and temporary — Task 6 replaces this exact line in its Step 1. Do not leave it after Task 6 is done; this is flagged as a placeholder ONLY because Task 6 is the very next task and will overwrite it immediately.)

- [ ] **Step 3: Widget test — tapping video area fires the callback, tapping mute icon does not**

Add to (or create) `flutter_app/test/screens/member_post_detail_screen_fullscreen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

// NOTE: _InlineVideoPlayer is private to member_post_detail_screen.dart.
// This test must live in a test file that imports the screen and exercises
// the tap behavior through the public MemberPostDetailScreen widget tree,
// OR (preferred, faster, no network mocking needed) via a small harness
// that copies the same VideoPlayerController test pattern used elsewhere
// in this repo for `video_player` widget tests — check
// flutter_app/test/ for an existing VideoPlayerController fake/mock
// (search for "FakeVideoPlayerPlatform" or similar) before writing a new
// one from scratch.

void main() {
  testWidgets(
    'tapping inline video area requests expand; tapping mute icon does not',
    (tester) async {
      // Arrange: pump MemberPostDetailScreen with one video FeedPost using
      // the repo's existing video_player test-platform fake (see note
      // above for where to find it).
      // Act: tap the video area (avoid the mute icon's bottom-right
      // corner) -> expect onExpandRequested fired once.
      // Act: tap exactly on the mute icon location -> expect mute toggled
      // and onExpandRequested NOT fired again.
    },
    skip: true, // unskip once the video_player test-platform fake is wired in Step 3
  );
}
```

Before unskipping, search the repo for how existing tests fake `video_player`'s platform channel (grep `flutter_app/test` for `VideoPlayerPlatform` or `dart_test_platform`). If no existing fake exists in this repo, keep this test `skip: true` with the TODO comment explaining why (video_player requires platform-channel mocking not yet present in this test suite) rather than inventing an untested mock — flag this as a follow-up rather than blocking the task.

- [ ] **Step 4: Run analyze**

Run: `cd flutter_app && flutter analyze lib/screens/member_post_detail_screen.dart test/screens/member_post_detail_screen_fullscreen_test.dart`
Expected: no errors (the `skip: true` test still must compile).

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/member_post_detail_screen.dart flutter_app/test/screens/member_post_detail_screen_fullscreen_test.dart
git commit -m "feat(post-detail): add tap-to-expand hook on inline video player"
```

---

### Task 6: Fullscreen overlay with shared controller (Flow B, part 2) + remove dead code

**Files:**
- Modify: `flutter_app/lib/screens/member_post_detail_screen.dart` (remove `_FullScreenVideoRoute`/`_FullScreenVideoRouteState`/`_RoundIconButton`; add `_FullscreenInlineVideoOverlay`; wire the Task 5 TODO callback)

**Interfaces:**
- Consumes: `VideoPlayerController` handed from `_InlineVideoPlayer.onExpandRequested` (Task 5); `pushScaledVideoFeed`-style morph is NOT reused here verbatim (Task 2's helper snapshots a network image URL and pushes a whole new route/screen — Flow B instead must keep the SAME controller alive and morph in-place without navigating to a new full `Navigator` route, since re-pushing would force `_InlineVideoPlayer` to lose its controller reference across route boundaries in a way that risks double-dispose). Flow B uses a local `Overlay` entry instead of `Navigator.push`.
- Produces: nothing consumed by later tasks — this is the last task.

- [ ] **Step 1: Delete dead code**

Delete the entire `_FullScreenVideoRoute` class, `_FullScreenVideoRouteState` class, and `_RoundIconButton` class from `member_post_detail_screen.dart` (confirmed dead — no callers anywhere in the file per repo grep).

- [ ] **Step 2: Add `_FullscreenInlineVideoOverlay`**

Add this new private widget in `member_post_detail_screen.dart` (near where `_InlineVideoPlayer` is defined):

```dart
/// Fullscreen video overlay that ADOPTS an already-playing
/// [VideoPlayerController] — never creates its own, so playback position
/// and buffered state are preserved exactly (no restart). Shown via
/// [Overlay] (not Navigator.push) so the inline player beneath keeps its
/// controller reference alive the whole time; on close, this overlay is
/// simply removed and the inline player resumes normal visibility-driven
/// play/pause + its own mute preference.
class _FullscreenInlineVideoOverlay extends StatefulWidget {
  final VideoPlayerController controller;
  final Rect originRect;
  final VoidCallback onClose;

  const _FullscreenInlineVideoOverlay({
    required this.controller,
    required this.originRect,
    required this.onClose,
  });

  @override
  State<_FullscreenInlineVideoOverlay> createState() => _FullscreenInlineVideoOverlayState();
}

class _FullscreenInlineVideoOverlayState extends State<_FullscreenInlineVideoOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _morphController;
  late final Animation<double> _morph;
  double? _previousVolume;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
      reverseDuration: const Duration(milliseconds: 260),
    );
    _morph = CurvedAnimation(parent: _morphController, curve: Curves.easeOutCubic);
    // Unmute on entry — explicit fullscreen intent, independent of the
    // inline preference (same rationale the old dead code documented).
    _previousVolume = widget.controller.value.volume;
    widget.controller.setVolume(1);
    _morphController.forward();
  }

  Future<void> _close() async {
    await _morphController.reverse();
    await widget.controller.setVolume(_previousVolume ?? 0);
    widget.onClose();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    widget.controller.setVolume(_muted ? 0 : 1);
  }

  @override
  void dispose() {
    _morphController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return AnimatedBuilder(
      animation: _morph,
      builder: (context, child) {
        final t = _morph.value;
        final origin = widget.originRect;
        final left = origin.left * (1 - t);
        final top = origin.top * (1 - t);
        final width = origin.width + (screenSize.width - origin.width) * t;
        final height = origin.height + (screenSize.height - origin.height) * t;
        return Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: ColoredBox(
            color: Colors.black.withValues(alpha: t),
            child: child,
          ),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 300) _close();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: widget.controller.value.aspectRatio,
                child: VideoPlayer(widget.controller),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _close,
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.chevron_left_rounded, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 32,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _toggleMute,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Wire the Task 5 TODO to insert this overlay**

In `_PostFeedItemState` (or wherever the Task 5 placeholder callback was added around `_PostMediaSurface(... onVideoExpandRequested: (controller, anchorKey) { ... })`), replace the `// TODO(Task 6)` body with:

```dart
                onVideoExpandRequested: (controller, anchorKey) {
                  final renderBox = anchorKey.currentContext?.findRenderObject() as RenderBox?;
                  if (renderBox == null) return;
                  final origin = renderBox.localToGlobal(Offset.zero) & renderBox.size;
                  late OverlayEntry entry;
                  entry = OverlayEntry(
                    builder: (context) => _FullscreenInlineVideoOverlay(
                      controller: controller,
                      originRect: origin,
                      onClose: () => entry.remove(),
                    ),
                  );
                  Overlay.of(context, rootOverlay: true).insert(entry);
                },
```

This requires `_PostFeedItemState.build()` to have a `BuildContext` in scope (it always does — it's inside a `State.build` method) and does not require converting `_PostFeedItem` to anything different.

- [ ] **Step 4: Verify it compiles**

Run: `cd flutter_app && flutter analyze lib/screens/member_post_detail_screen.dart`
Expected: no errors, and no more references to `_FullScreenVideoRoute`/`_RoundIconButton` anywhere in the file (`grep -n "_FullScreenVideoRoute\|_RoundIconButton" lib/screens/member_post_detail_screen.dart` returns nothing).

- [ ] **Step 5: Unskip and complete the Task 5 test, add a close-without-restart assertion**

Return to `flutter_app/test/screens/member_post_detail_screen_fullscreen_test.dart` (from Task 5). Using the same video_player test-platform fake located in Task 5 Step 3, extend the test file with:

```dart
testWidgets(
  'expanding to fullscreen and closing does not reset video position',
  (tester) async {
    // Arrange: pump with a fake VideoPlayerController seeded to a
    // non-zero position (e.g. simulate 3 seconds played).
    // Act: tap video area -> overlay appears (find _FullscreenInlineVideoOverlay
    //      is private; assert via find.byType(VideoPlayer) count == 1,
    //      i.e. still the SAME VideoPlayer widget instance/controller,
    //      not a second one).
    // Act: tap back chevron -> overlay removed.
    // Assert: the fake controller's `.value.position` is UNCHANGED from
    //         before expand (proves no re-initialization happened).
  },
  skip: true, // unskip once the fake VideoPlayerController from Task 5 is confirmed working
);
```

If the Task 5 fake was already unskipped successfully, unskip this one too and fill in the real assertions using that fake's API. If Task 5's fake infrastructure doesn't exist in this repo yet, leave both `skip: true` and note in the task's final commit message that video_player platform-channel test mocking is a follow-up (flag via `mcp__ccd_session__spawn_task` after this plan finishes, not silently).

- [ ] **Step 6: Full regression + commit**

Run: `cd flutter_app && flutter analyze && flutter test`
Expected: no new failures versus baseline.

```bash
git add flutter_app/lib/screens/member_post_detail_screen.dart flutter_app/test/screens/member_post_detail_screen_fullscreen_test.dart
git commit -m "feat(post-detail): expand inline video to fullscreen overlay without restart, remove dead _FullScreenVideoRoute"
```

---

### Task 7: Device/manual verification pass

**Files:** none (manual verification only, matches this repo's established pattern of device-verify checkpoints for Flutter UI work).

- [ ] **Step 1: Run the app and verify Flow A**

Run the Flutter app on a device/emulator, navigate to a product detail page with "Postingan Terkait" containing at least one video. Tap a video thumbnail:
- Confirm the thumbnail visibly grows into fullscreen (~440ms), no flash/pop.
- Confirm the video autoplays with SOUND ON immediately once fullscreen.
- Confirm swiping up/down only cycles through videos tagged to that product (not the global feed).
- Confirm like/comment/share act on the real post (compare like count against the same post opened via the main Feed tab — must match, proving `feedStore` sync).
- Confirm back (chevron) returns to the product detail page.
- Tap a PHOTO related-post — confirm it still opens `MemberPostDetailScreen` exactly as before (regression check).

- [ ] **Step 2: Run the app and verify Flow B**

Navigate to any user's profile ("Postingan Saya" or another user's public profile), tap a post thumbnail to open the "Postingan" list (must look IDENTICAL to before this change — no regressions). Let a video autoplay inline (muted). Tap the video area (not the mute icon):
- Confirm it expands to fullscreen WITHOUT the video visibly restarting or stuttering/flashing back to frame 0.
- Confirm audio turns ON automatically on entering fullscreen.
- Tap back (chevron) or swipe down — confirm it shrinks back to the card position and the video keeps playing (does not restart), muted again per the inline preference.
- Tap the mute icon specifically (inline, before expanding) — confirm it toggles mute WITHOUT triggering the fullscreen expand (regression check for the Task 5 gesture-arena concern).

- [ ] **Step 3: Record findings**

If either flow shows a regression or visual glitch, file it as a task via `TaskCreate` (do not silently patch without a task trail) before closing out this plan's execution. If everything matches the two mockups approved during brainstorming, mark this plan complete.

---

## Self-Review Notes

- **Spec coverage:** Flow A (thumbnail morph → scoped feed, video-only) — Tasks 1–4. Flow B (profile list unchanged, tap video → fullscreen no-restart, back → shrink) — Tasks 5–6. Foto/carousel untouched — explicitly preserved in Task 4 Step 3 (photo branch keeps old code path verbatim) and Task 5/6 (only `_InlineVideoPlayer`, used exclusively for `FeedContentType.video`, is touched). Dead `_FullScreenVideoRoute` removal — Task 6 Step 1. Device verification — Task 7.
- **Placeholder scan:** The one `// TODO(Task 6)` in Task 5 Step 2 is intentional and immediately resolved by Task 6 Step 3 in the very next task — flagged explicitly as such, not a dangling placeholder. The two `skip: true` tests are conditioned on a concrete, checkable fact (whether a `video_player` test-platform fake already exists in this repo) rather than being deferred indefinitely, and Task 6 Step 5 requires flagging them as a follow-up via `spawn_task` if they can't be completed — not silently left broken.
- **Type consistency:** `FeedVideoPostView` constructor (Task 1) is reused identically in Task 3's `ScopedVideoFeedScreen` and Task 1's own updated `feed_screen.dart` call site — same param names/types in all three places. `pushScaledVideoFeed` (Task 2) signature matches its only call site (Task 4 Step 3) exactly. `_InlineVideoPlayer.onExpandRequested` signature (Task 5) matches exactly what `_FullscreenInlineVideoOverlay` (Task 6) expects to receive (`VideoPlayerController controller, GlobalKey anchorKey`).
