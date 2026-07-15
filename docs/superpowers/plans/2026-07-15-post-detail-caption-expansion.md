# Post Detail Caption Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Caption panjang pada detail postingan terbuka sekali dan tetap terbuka selama sesi aplikasi.

**Architecture:** `ChangeNotifier` in-memory menyimpan ID postingan yang sudah dibuka. Widget caption detail mengukur teks pada lebar aktual, memasang suffix `... selengkapnya` dalam dua baris, dan memakai `AnimatedSize` untuk ekspansi satu arah.

**Tech Stack:** Flutter, Dart, `ChangeNotifier`, `TextPainter`, `AnimatedSize`, `flutter_test`.

## Global Constraints

- Hanya mengubah halaman detail postingan.
- Caption awal maksimal dua baris dengan suffix `... selengkapnya`.
- Hanya suffix `selengkapnya` yang dapat ditekan.
- Tidak ada aksi tutup caption dalam sesi yang sama.
- State per ID postingan hidup hanya dalam memori; reset pada cold start.
- Tidak ada perubahan pada feed utama, API, database, atau penyimpanan permanen.

---

### Task 1: Store sesi caption

**Files:**
- Create: `flutter_app/lib/state/post_caption_session_store.dart`
- Test: `flutter_app/test/state/post_caption_session_store_test.dart`

**Interfaces:**
- Produces `PostCaptionSessionStore`, `postCaptionSessionStore`, `isExpanded(String postId)`, dan `markExpanded(String postId)`.

- [ ] **Step 1: Write a failing test**

```dart
test('records each expanded post only for the active store session', () {
  final store = PostCaptionSessionStore();
  expect(store.isExpanded('post-a'), isFalse);
  store.markExpanded('post-a');
  expect(store.isExpanded('post-a'), isTrue);
  expect(store.isExpanded('post-b'), isFalse);
});
```

- [ ] **Step 2: Run the failing test**

Run: `flutter test test/state/post_caption_session_store_test.dart`

Expected: FAIL because the store does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
class PostCaptionSessionStore extends ChangeNotifier {
  final Set<String> _expandedPostIds = <String>{};
  bool isExpanded(String postId) => _expandedPostIds.contains(postId);
  void markExpanded(String postId) {
    if (postId.isEmpty || !_expandedPostIds.add(postId)) return;
    notifyListeners();
  }
}
final postCaptionSessionStore = PostCaptionSessionStore();
```

- [ ] **Step 4: Verify and commit**

Run: `flutter test test/state/post_caption_session_store_test.dart`

Expected: PASS.

Commit: `git add flutter_app/lib/state/post_caption_session_store.dart flutter_app/test/state/post_caption_session_store_test.dart && git commit -m "feat(feed): retain expanded post captions in session"`

### Task 2: Caption detail dua baris dan ekspansi satu arah

**Files:**
- Modify: `flutter_app/lib/screens/member_post_detail_screen.dart`
- Test: `flutter_app/test/screens/member_post_detail_screen_caption_test.dart`

**Interfaces:**
- Consumes `postCaptionSessionStore`.
- `_PostCaption` menerima `postId`, `memberName`, `caption`, dan `isOfficial`.

- [ ] **Step 1: Write failing widget tests**

```dart
testWidgets('long caption displays selengkapnya without a close action', (tester) async {
  await tester.pumpWidget(buildCaptionHarness(
    postId: 'post-a',
    caption: List.filled(30, 'caption panjang').join(' '),
  ));
  expect(find.text('selengkapnya'), findsOneWidget);
  expect(find.text('lebih sedikit'), findsNothing);
});

testWidgets('opened caption stays open when rebuilt in the same session', (tester) async {
  const caption = 'caption panjang caption panjang caption panjang';
  await tester.pumpWidget(buildCaptionHarness(postId: 'post-a', caption: caption));
  await tester.tap(find.text('selengkapnya'));
  await tester.pumpAndSettle();
  await tester.pumpWidget(buildCaptionHarness(postId: 'post-a', caption: caption));
  expect(find.text('selengkapnya'), findsNothing);
});
```

- [ ] **Step 2: Run the failing tests**

Run: `flutter test test/screens/member_post_detail_screen_caption_test.dart`

Expected: FAIL because `_PostCaption` always renders the full caption.

- [ ] **Step 3: Implement the widget**

Replace `_PostCaption` with a stateful widget. Pass `post.id` at its existing call site. Measure the complete `TextSpan` with `TextPainter(maxLines: 2)` and use binary search on the caption text so the collapsed candidate ending in `... selengkapnya` fits in two lines. Render `selengkapnya` as a `TextSpan` with `TapGestureRecognizer` that only calls `postCaptionSessionStore.markExpanded(postId)`. Listen to the store, use `AnimatedSize(duration: Duration(milliseconds: 280), curve: Curves.easeOutCubic)`, and dispose listener plus recognizer.

- [ ] **Step 4: Verify and commit**

Run: `flutter test test/screens/member_post_detail_screen_caption_test.dart test/state/post_caption_session_store_test.dart && dart format lib/state/post_caption_session_store.dart lib/screens/member_post_detail_screen.dart test/state/post_caption_session_store_test.dart test/screens/member_post_detail_screen_caption_test.dart && flutter analyze lib/state/post_caption_session_store.dart lib/screens/member_post_detail_screen.dart`

Expected: all tests and analysis PASS.

Commit: `git add flutter_app/lib/screens/member_post_detail_screen.dart flutter_app/test/screens/member_post_detail_screen_caption_test.dart && git commit -m "feat(feed): expand post detail captions once"`

### Task 3: Regression boundary

**Files:**
- Modify: none unless a narrow correction is required.
- Test: `flutter_app/test/feed_creator_overlay_test.dart`, `flutter_app/test/features/feed/widgets/feed_expandable_caption_test.dart`

- [ ] **Step 1: Run independent feed-caption regression tests**

Run: `flutter test test/feed_creator_overlay_test.dart test/features/feed/widgets/feed_expandable_caption_test.dart test/screens/member_post_detail_screen_caption_test.dart`

Expected: PASS; feed-main caption behavior remains unchanged.

- [ ] **Step 2: Review final scope**

Run: `git diff --check && git diff -- flutter_app/lib/state/post_caption_session_store.dart flutter_app/lib/screens/member_post_detail_screen.dart flutter_app/test/state/post_caption_session_store_test.dart flutter_app/test/screens/member_post_detail_screen_caption_test.dart`

Expected: no whitespace errors and no unrelated code changes.
