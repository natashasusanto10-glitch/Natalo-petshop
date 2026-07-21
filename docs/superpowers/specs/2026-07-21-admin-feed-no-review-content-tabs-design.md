# Admin Feed: remove review UI, split by content type

## Context

Since [PR #225](https://github.com/natashasusanto10-glitch/natalopetshopflutter/pull/225) (merged, backend live), every feed post auto-publishes to `ACTIVE` on creation — there is no more moderation queue. `FeedPostStatus.PENDING_REVIEW` and `REJECTED` are now dead states: nothing transitions into them anymore (moderation is only used reactively via `/admin/feed/reports`, a separate page).

The admin Feed list ([components/admin/feed/AdminFeedClient.tsx](../../../components/admin/feed/AdminFeedClient.tsx)) still presents review-era UI:
- Tabs: `Semua · Video Admin · Video User · Menunggu Review · Ditolak · Disembunyikan · Sampah`
- Per-row `Setujui`/`Tolak` buttons, gated on `encodingStatus === "ready"`
- Header subtitle showing `"X menunggu review"`

This is confusing now that review doesn't happen, and the tab split ("Video Admin" / "Video User") doesn't reflect what admins actually care about day to day: managing photo posts vs video posts.

## Goal

Replace the review-oriented UI with a content-type-oriented one, keeping the same list-row visual style (approved direction: **list view**, not a grid/gallery — smaller, safer change).

## Tabs

Replace the current 7 tabs with:

`Semua · Foto/Carousel · Video · Diskusi · Disembunyikan · Sampah`

Mapping to `FeedPostKind`:
- **Foto/Carousel** → `kind: PHOTO_CAROUSEL`
- **Video** → `kind in (VIDEO_ONLY, VIDEO_PRODUCT, USER_VIDEO)` — single tab, no admin/user split (confirmed with user; author name still shows per-row so admin/user is still visible at a glance)
- **Diskusi** → `kind: COMMUNITY` (text-only posts, no media)
- **Disembunyikan** → `status: HIDDEN` (unchanged)
- **Sampah** → `deletedAt: not null` (unchanged, trash view)
- **Semua** → all non-deleted (unchanged default)

`Menunggu Review` and `Ditolak` tabs are removed entirely. `Video Admin`/`Video User` split is removed (superseded by Foto/Video/Diskusi split).

Note: `PRODUCT_ONLY` and `PROMO` kinds exist but aren't primary content — they still appear in `Semua` but don't need their own tab (out of scope; no admin-facing count/tab requested for them).

## Header

Subtitle changes from `"{total} post · {pending} menunggu review"` to `"{total} post · {photo} foto · {video} video · {discussion} diskusi"` — reflects composition, not moderation backlog.

## Row actions

Remove:
- `Setujui` / `Tolak` buttons entirely
- The `isApprovable` / encoding-not-ready disabled-state messaging tied to approval (the encoding badge itself — `Encoding…` / `Upload…` / `Encoding gagal` — stays, it's still useful status info, just no longer gates an action)

Keep unchanged:
- `Sembunyikan` (status ACTIVE → HIDDEN, with optional reason prompt)
- `Tampilkan` (status HIDDEN → ACTIVE)
- `Restore` (trash view only)
- `Hapus` / `Hapus permanen` (soft-delete outside trash, hard-delete inside trash)
- `Edit` icon (admin-authored posts only)
- External-link icon (open video URL)

Add:
- Preview (eye icon) action per row — opens the public post detail in a new tab (`/akun/postingan-saya/{id}` pattern or equivalent public URL), giving admins a fast way to see the actual post now that there's no review-detail flow to click into. Uses existing `feedPostOwnerUrl`-style URL building if available; otherwise link to the public feed post permalink already used elsewhere in the codebase — confirm at implementation time which permalink helper exists.

Bulk action bar: remove `Setujui`/`Tolak` bulk buttons; keep `Sembunyikan`/`Tampilkan`/`Ke Sampah` (non-trash view) and `Restore`/`Hapus Permanen` (trash view), matching per-row changes.

## Backend changes

[app/api/admin/feed/posts/route.ts](../../../app/api/admin/feed/posts/route.ts):

- `AdminFilter` type: replace `"pending" | "rejected"` with `"photo" | "video" | "discussion"`. Remove `"admin_video" | "user_video"`.
- `VALID_FILTERS` updated to match.
- `ADMIN_KINDS` constant and the `admin_video`/`user_video` branches removed.
- `buildWhere`: add cases —
  - `photo` → `{ ...notDeleted, kind: "PHOTO_CAROUSEL" }`
  - `video` → `{ ...notDeleted, kind: { in: ["VIDEO_ONLY", "VIDEO_PRODUCT", "USER_VIDEO"] } }`
  - `discussion` → `{ ...notDeleted, kind: "COMMUNITY" }`
  - remove `pending` / `rejected` cases
- `orderBy`: the special-case FIFO (`createdAt: asc`) for `filter === "pending"` is removed — all filters now use `createdAt: desc` (newest first), since there's no queue to process oldest-first.
- Counts payload: replace `{ pending, total, deleted }` with `{ total, deleted, photo, video, discussion }` (four `prisma.feedPost.count` calls run in parallel via `Promise.all`, same pattern as today).

`components/admin/feed/AdminFeedClient.tsx`:
- `AdminFilter` type and `FILTERS` array updated to match the new backend filter values/labels.
- `AdminFeedResponse.counts` type updated to the new shape.
- Header subtitle string updated (see above).
- `moderate()` function: drop `"approve" | "reject"` from the action union; drop the `note` prompt branch tied to `reject`.
- `bulkAction()` function: drop `"approve" | "reject"` from the action union and the `reject` note-prompt branch; drop from `labels` record.
- `AdminFeedRow`: remove `isApprovable` logic and the `Setujui`/`Tolak` JSX block (the `post.status === "PENDING_REVIEW"` branch). Add the preview icon button.
- `STATUS_META`: `PENDING_REVIEW` and `REJECTED` entries can stay (harmless — legacy rows, if any exist, still render a readable badge) or be removed since no new rows will ever have these statuses. Keep them for safety (defensive rendering of any pre-existing rows still in these states from before the migration) rather than assuming DB is clean.

## Out of scope

- No Prisma schema change — `PENDING_REVIEW`/`REJECTED` enum values stay (historical data may still reference them; removing the enum value would be a breaking migration for no benefit).
- `/admin/feed/reports` (the separate moderation-via-reports safety net) is untouched.
- No change to the public-facing Flutter app or the feed publish/push pipeline.
- Grid/gallery view was considered and explicitly rejected in favor of keeping the list view.

## Testing

- Manual verification in the admin web UI (Next.js, not Flutter — this is a `components/admin` change) after implementation: each new tab returns the right subset, counts match, bulk actions still work for hide/unhide/delete/restore, no leftover approve/reject buttons anywhere.
