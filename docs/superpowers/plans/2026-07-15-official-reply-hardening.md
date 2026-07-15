# Natalo Official Reply Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify and harden the existing admin-in-app feed reply flow so it consistently renders as Natalo Official without exposing staff identity.

**Architecture:** Keep the existing `POST /api/feed/posts/[id]/comments` flow and the existing Flutter comment/reply UI. Add only regression coverage and remove stale documentation that claims admin replies are unsupported. Keep authorization server-derived from the authenticated ADMIN session; request JSON cannot set official identity.

**Tech Stack:** Next.js App Router, TypeScript, Prisma/PostgreSQL, Flutter/Dart, Node test runner (`tsx --test`), existing Flutter widget/model tests.

## Global Constraints

- Do not create a separate staff inbox or duplicate comment composer.
- Public admin replies must render as `Natalo Official`; staff name/photo must not leak.
- Keep one-level comment threads; replying to a reply remains attached to the root.
- Keep existing optimistic comment, like, notification, and sync behavior.
- Preserve unrelated dirty working-tree files and do not commit them.

---

### Task 1: Align endpoint documentation with the implemented behavior

**Files:**
- Modify: `app/api/feed/posts/[id]/comments/route.ts` (module comment and nearby admin-role comments)
- Test: `tests/official-feed-reply.test.ts`

**Interfaces:**
- Consumes: `SessionPayload` from `lib/auth.ts`, `brandDisplayName`/`brandPhotoUrl` from `lib/social/brand-user.ts`.
- Produces: documented contract that `session.role === "ADMIN"` sets `isAdminOfficial` and response author is brand-masked.

- [ ] **Step 1: Write failing pure-contract tests**

Create tests that assert the policy used by the route:

```ts
import assert from "node:assert/strict";
import test from "node:test";
import { brandDisplayName, brandPhotoUrl } from "@/lib/social/brand-user";

test("admin public comment identity is Natalo Official", () => {
  assert.equal(brandDisplayName("ADMIN", "Private Staff"), "Natalo Official");
  assert.equal(brandPhotoUrl("ADMIN", "https://private.example/avatar.jpg"), null);
});

test("customer public comment identity remains customer identity", () => {
  assert.equal(brandDisplayName("CUSTOMER", "Aurelia"), "Aurelia");
  assert.equal(brandPhotoUrl("CUSTOMER", "https://cdn.example/avatar.jpg"), "https://cdn.example/avatar.jpg");
});
```

- [ ] **Step 2: Run the focused test and verify the baseline**

Run: `npx tsx --test tests/official-feed-reply.test.ts`

Expected: PASS for the existing identity helper; this test documents the policy before route comments are changed.

- [ ] **Step 3: Update stale route comments**

Replace the header claim that admin reply is not implemented with the actual contract: the same endpoint accepts admin sessions, sets `isAdminOfficial` from the server-side role, masks the response identity, and keeps `authorId` for internal traceability. Do not change request behavior or introduce a client-provided `isAdminOfficial` field.

- [ ] **Step 4: Run the focused test again**

Run: `npx tsx --test tests/official-feed-reply.test.ts tests/brand-user.test.ts`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "app/api/feed/posts/[id]/comments/route.ts" tests/official-feed-reply.test.ts
git commit -m "test(feed): document official admin reply identity"
```

### Task 2: Add Flutter regression coverage for official replies

**Files:**
- Modify: `flutter_app/test/models/feed_comment_test.dart`
- Inspect only: `flutter_app/lib/models/feed_comment.dart`, `flutter_app/lib/widgets/feed_comment_sheet.dart`

**Interfaces:**
- Consumes: API JSON with `isAdminOfficial: true`, `author.role: "ADMIN"`, and brand-masked author name.
- Produces: regression coverage that official replies parse/render as official while ordinary customer comments remain ordinary.

- [ ] **Step 1: Add model parsing tests**

Add tests using `FeedComment.fromApiJson` with an official reply payload and assert `isAdminOfficial == true`, `author.isOfficialAccount == true`, and `parentCommentId` is preserved. Add a second customer payload asserting the flag stays false.

- [ ] **Step 2: Run the Flutter-focused tests**

Run from `flutter_app`: `flutter test test/models/feed_comment_test.dart`

Expected: PASS with the existing model suite and the new official reply assertions.

- [ ] **Step 3: Commit**

```bash
git add flutter_app/test/models/feed_comment_test.dart
git commit -m "test(feed): cover official reply rendering contract"
```

### Task 3: Verify the complete existing flow

**Files:**
- Test: `tests/official-feed-reply.test.ts`
- Test: `flutter_app/test/models/feed_comment_test.dart`
- Inspect: `app/api/feed/posts/[id]/comments/route.ts`, `flutter_app/lib/services/feed_service.dart`, `flutter_app/lib/widgets/feed_comment_sheet.dart`

**Interfaces:**
- Consumes: the server-derived ADMIN identity and existing reply/notification behavior.
- Produces: release evidence; no new runtime interface.

- [ ] **Step 1: Run backend focused tests**

Run: `npx tsx --test tests/official-feed-reply.test.ts tests/brand-user.test.ts tests/feed-comment-rate-limit.test.ts tests/feed-comment-sync.test.ts`

Expected: PASS.

- [ ] **Step 2: Run Flutter comment tests**

Run from `flutter_app`: `flutter test test/models/feed_comment_test.dart test/state/feed_comment_session_store_test.dart test/widgets/feed_comment_sheet_drag_test.dart`

Expected: PASS.

- [ ] **Step 3: Run static checks relevant to changed TypeScript**

Run: `npx tsc --noEmit`

Expected: no new errors attributable to the changed files; record any pre-existing environment/type errors separately.

- [ ] **Step 4: Perform manual two-login smoke test**

Log in to the Natalo app as customer on one device and ADMIN on another. Customer posts a comment; ADMIN opens the same Feed post, replies through the normal comment sheet, and likes the reply. Confirm customer sees `Natalo Official`, the reply is nested under the root comment, notification arrives, reload preserves the result, and no staff name/photo appears.

- [ ] **Step 5: Commit verification notes only if needed**

Do not commit generated logs, screenshots, local environment files, or unrelated dirty files. If a test exposes a real defect, add a focused fix and test commit before shipping.
