# Comment Likes and Order Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make comment likes consistent across every Feed comment drawer and show reliable, timestamped order progress with completed-order review and repurchase actions.

**Architecture:** A small Flutter `ChangeNotifier` owns only optimistic comment-like state, while existing comment sessions remain the source of comments, replies, drafts, and pagination. Order status history is first written canonically by the backend, exposed through existing member order payloads, then rendered by Flutter's tracking timeline and consumed by the completed-order CTA screens.

**Tech Stack:** Flutter/Dart (`ChangeNotifier`, widget tests), Next.js/TypeScript API routes, Prisma/PostgreSQL migrations, existing order transition helpers.

## Global Constraints

- Preserve all current local changes outside this worktree; do not use destructive Git commands.
- Comment drafts, reply targets, pagination, and comment drawer presentation stay unchanged.
- Comment likes must be optimistic, serialize repeated taps per comment, roll back on failed requests, and clear on viewer/account change.
- Backend migration must be additive and be applied before release.
- Every order event uses server timestamps; no client-side invented status timestamp.
- Pickup uses its own milestones; do not label pickup as shipment.
- Existing payment, checkout, cart, and review submission flows stay compatible.
- Android and iOS Flutter behavior must remain identical.

---

### Task 1: Global Comment-Like Interaction Store

**Files:**
- Create: `flutter_app/lib/state/feed_comment_interaction_store.dart`
- Modify: `flutter_app/lib/widgets/feed_comment_sheet.dart`
- Test: `flutter_app/test/state/feed_comment_interaction_store_test.dart`
- Test: `flutter_app/test/widgets/feed_comment_sheet_modal_test.dart`

**Interfaces:**
- Produces `FeedCommentLikeState({required bool liked, required int count})`.
- Produces singleton `feedCommentInteractionStore` with `seed`, `toggle`, `likeState`, `pendingCommentIdsForPost`, and `clearForViewer`.
- Consumes `feedService.setCommentLiked`, `memberStore.viewerGeneration`, and existing `mergeFeedCommentRefresh`.

- [ ] Write failing store tests for optimistic toggle, serialized rapid toggles, server rollback, and account switch clearing state.
- [ ] Implement a map keyed by `postId + '\\u0000' + commentId`; retain one confirmed state and one in-flight request per key.
- [ ] Update `FeedCommentSheet` to seed and render the global state, preserve only globally pending likes during refresh, and remove its per-sheet like queue.
- [ ] Run `flutter test test/state/feed_comment_interaction_store_test.dart test/widgets/feed_comment_sheet_modal_test.dart` and repair failures.
- [ ] Commit with `feat(feed): synchronize comment like interactions`.

### Task 2: Canonical Backend Order Status History

**Files:**
- Create: `prisma/migrations/20260716010000_add_order_status_history/migration.sql`
- Modify: `prisma/schema.prisma`
- Modify: `lib/order-transitions.ts`
- Modify: `lib/member-orders.ts`
- Modify: `lib/order-detail.ts`
- Modify: order creation, payment, cancellation, delivery-confirmation, cron, and admin status routes that change order state.
- Test: `tests/order-timeline.test.ts`
- Test: `tests/order-transitions.test.ts`
- Test: `tests/member-orders.test.ts`
- Test: `tests/order-detail.test.ts`

**Interfaces:**
- Produces an additive persisted order-status event model with `status`, `createdAt`, and optional actor/context.
- Member list/detail payloads include chronological event history without changing legacy status fields.
- All server transitions call one helper that records an event only after a real state transition.

- [ ] Write failing transition and payload tests for delivery and pickup histories, duplicate transition rejection, and timestamp ordering.
- [ ] Integrate the existing `codex/order-history-backend` implementation selectively, resolving conflicts against current `main` rather than merging its branch wholesale.
- [ ] Run Prisma validation/generation and the named backend tests; record the exact migration release requirement.
- [ ] Commit with `feat(orders): persist canonical status timeline`.

### Task 3: Flutter Timeline Rendering

**Files:**
- Modify: `flutter_app/lib/models/member_profile.dart`
- Modify: `flutter_app/lib/widgets/order_tracking_timeline.dart`
- Test: `flutter_app/test/models/order_timeline_event_test.dart`
- Test: `flutter_app/test/widgets/order_tracking_timeline_test.dart`

**Interfaces:**
- Consumes order history from Task 2.
- Produces timeline steps with title, server timestamp, state, and a separate pickup/shipping label set.

- [ ] Write failing model and widget tests for chronological timestamps, incomplete/current statuses, pickup milestones, and no-history legacy fallback.
- [ ] Integrate the focused `codex/order-timeline-worker` changes without introducing client-generated event times.
- [ ] Run `flutter test test/models/order_timeline_event_test.dart test/widgets/order_tracking_timeline_test.dart`.
- [ ] Commit with `feat(orders): render timestamped tracking timeline`.

### Task 4: Completed-Order Review and Repurchase UX

**Files:**
- Modify: `flutter_app/lib/screens/member_order_detail_screen.dart`
- Modify: `flutter_app/lib/screens/member_orders_screen.dart`
- Modify: `flutter_app/lib/screens/member_reviews_screen.dart`
- Test: `flutter_app/test/screens/member_order_detail_review_cta_test.dart`
- Test: `flutter_app/test/screens/member_reviews_pickup_context_test.dart`

**Interfaces:**
- Consumes completed/pickup context and review completion from current order models.
- Produces contextual completed-order actions: `Beri Ulasan` when eligible and `Beli Lagi` without losing pickup context.

- [ ] Write failing CTA tests covering shipped and pickup completed orders, reviewed orders, and return navigation from review.
- [ ] Integrate the focused `codex/order-ux-review` changes, retaining existing review page visuals unless the new CTA requires state wiring.
- [ ] Run `flutter test test/screens/member_order_detail_review_cta_test.dart test/screens/member_reviews_pickup_context_test.dart`.
- [ ] Commit with `feat(orders): connect completed order review actions`.

### Task 5: End-to-End Regression Gate

**Files:**
- Test: focused tests from Tasks 1-4.

- [ ] Run backend typecheck, backend tests for order history, and Flutter analyzer on every changed Dart file.
- [ ] Run all focused Flutter tests together.
- [ ] Review the full branch diff for interaction regressions, migration safety, and stale code from the source branches.
- [ ] Commit only fixes discovered during this gate.
