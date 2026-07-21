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

`Semua · Foto/Carousel · Video · Disembunyikan · Sampah`

Mapping to `FeedPostKind` (the enum has exactly: `VIDEO_ONLY, PRODUCT_ONLY, VIDEO_PRODUCT, PROMO, COMMUNITY, PHOTO_CAROUSEL` — there is **no `USER_VIDEO`**; that string is dead defensive code in the client):
- **Foto/Carousel** → `kind: PHOTO_CAROUSEL`
- **Video** → `kind in (VIDEO_ONLY, VIDEO_PRODUCT, COMMUNITY)` — single tab, no admin/user split (confirmed with user; author name still shows per-row). **`COMMUNITY` is user-uploaded video**, not text: the create route requires `videoUrl + thumbnailUrl` for it. The admin UI currently mislabels `COMMUNITY` as "Diskusi" — that label is corrected to "Video" (see KIND_LABEL change below).
- **Disembunyikan** → `status: HIDDEN` (unchanged)
- **Sampah** → `deletedAt: not null` (unchanged, trash view)
- **Semua** → all non-deleted (unchanged default)

There is **no text-only/discussion post kind** — every post is either photo or video. So no "Diskusi" tab. This matches the user's original request: split photo/carousel vs video.

`Menunggu Review`, `Ditolak`, `Video Admin`, and `Video User` tabs are all removed.

Note: `PRODUCT_ONLY` (deprecated from create) and `PROMO` (admin promo, rare) kinds still exist in legacy data — they appear in `Semua` but get no dedicated tab and are not counted in the video/photo breakdown. They are neither pure photo nor pure user-video, so folding them into either content tab would be misleading.

## Header

Subtitle changes from `"{total} post · {pending} menunggu review"` to `"{total} post · {photo} foto · {video} video"` — reflects composition, not moderation backlog.

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

No new preview action is added: the only per-post URL helper (`feedPostOwnerUrl` → `/akun/postingan-saya/{id}`) is owner-scoped and wouldn't render for an admin viewing another user's post. The existing external-link icon already opens video posts; adding a broken/owner-only preview link is out of scope.

Bulk action bar: remove `Setujui`/`Tolak` bulk buttons; keep `Sembunyikan`/`Tampilkan`/`Ke Sampah` (non-trash view) and `Restore`/`Hapus Permanen` (trash view), matching per-row changes.

## Backend changes

[app/api/admin/feed/posts/route.ts](../../../app/api/admin/feed/posts/route.ts):

- `AdminFilter` type: replace `"admin_video" | "user_video" | "pending" | "rejected"` with `"photo" | "video"`.
- `VALID_FILTERS` updated to match (`all, photo, video, hidden, deleted`).
- `ADMIN_KINDS` constant and the `admin_video`/`user_video`/`pending`/`rejected` branches removed.
- `buildWhere`: add cases —
  - `photo` → `{ ...notDeleted, kind: "PHOTO_CAROUSEL" }`
  - `video` → `{ ...notDeleted, kind: { in: ["VIDEO_ONLY", "VIDEO_PRODUCT", "COMMUNITY"] } }`
  - remove `pending` / `rejected` / `admin_video` / `user_video` cases
- `orderBy`: the special-case FIFO (`createdAt: asc`) for `filter === "pending"` is removed — all filters now use `createdAt: desc` (newest first), since there's no queue to process oldest-first.
- Counts payload: replace `{ pending, total, deleted }` with `{ total, deleted, photo, video }` (four `prisma.feedPost.count` calls run in parallel via `Promise.all`; `photo` = `kind PHOTO_CAROUSEL, deletedAt null`, `video` = `kind in (VIDEO_ONLY, VIDEO_PRODUCT, COMMUNITY), deletedAt null`).

`components/admin/feed/AdminFeedClient.tsx`:
- `AdminFilter` type and `FILTERS` array updated to match the new backend filter values/labels (`Semua, Foto/Carousel, Video, Disembunyikan, Sampah`).
- `AdminFeedResponse.counts` type updated to the new shape; the pending-count badge on the tab is removed (no more `pending` count).
- Header subtitle string updated (see above).
- `moderate()` function: drop `"approve" | "reject"` from the action union; drop the `note` prompt branch tied to `reject` (keep the `hide` reason prompt).
- `bulkAction()` function: drop `"approve" | "reject"` from the action union and the `reject` note-prompt branch; drop from `labels` record.
- `AdminFeedRow`: remove `isApprovable` logic and the `Setujui`/`Tolak` JSX block (the `post.status === "PENDING_REVIEW"` branch). No preview button added.
- `KIND_LABEL`: change `COMMUNITY` from `"Diskusi"` to `"Video"` (it's user video, not discussion). The dead `USER_VIDEO` entry can stay as harmless defensive mapping.
- `STATUS_META`: keep `PENDING_REVIEW` and `REJECTED` entries for defensive rendering of any pre-existing legacy rows still in those states — don't assume the DB is clean.

## Out of scope

- No Prisma schema change — `PENDING_REVIEW`/`REJECTED` enum values stay (historical data may still reference them; removing the enum value would be a breaking migration for no benefit).
- `/admin/feed/reports` (the separate moderation-via-reports safety net) is untouched.
- No change to the public-facing Flutter app or the feed publish/push pipeline.
- Grid/gallery view was considered and explicitly rejected in favor of keeping the list view.

## Testing

- `npx tsc --noEmit` (or the project's typecheck) must pass — the `AdminFilter` union and `counts` shape change touch both the route and the client; a mismatch is a compile error, which is the primary safety net here.
- Manual verification in the admin web UI (Next.js, not Flutter — this is a `components/admin` change) after implementation: each new tab returns the right subset, counts match, bulk actions still work for hide/unhide/delete/restore, no leftover approve/reject buttons anywhere.
