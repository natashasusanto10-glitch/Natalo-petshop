# Task 1 Report: Deterministic `shareVersion`

## Status

`DONE_WITH_CONCERNS`

Commit: `0c6edad3 feat(share): expose deterministic preview versions`

## Implementation

- Added `buildShareVersion` with SHA-256 base64url output truncated to 16 characters, plus `stripEphemeralUrlQuery` to remove signed CDN query parameters before hashing.
- Added deterministic feed versions to the existing canonical feed serializer and the public single-post response. Inputs are post id, title, description, unsigned thumbnail URL, duration, brand-safe author display name/avatar, and official flag.
- Added a profile version to the public `user` payload from username, brand-safe public identity, public bio, official flag, and post/follower/following counts. Profile response feed items carry their own feed version.
- Added product version to the existing product payload using slug, name, unsigned image URL, existing effective price (`discountPrice ?? price`), base price, and stock.
- No Flutter, Prisma, Android/iOS, or dependency changes were made. `package-lock.json` was deliberately excluded from the commit.

## Files

- Created `lib/share/share-version.ts`
- Created `tests/share-version.test.ts`
- Modified `lib/feed/queries.ts`
- Modified `app/api/feed/posts/[id]/route.ts`
- Modified `app/api/u/[username]/route.ts`
- Modified `app/api/products/[slug]/route.ts`

## TDD Evidence

### RED

Command:

```powershell
npx tsx --test tests/share-version.test.ts
```

Result: exit `1`, expected failure: `Cannot find module '../lib/share/share-version'`. The test file reported one failing test file and zero passing tests because the production helper did not yet exist.

### GREEN

Command:

```powershell
npx tsx --test tests/share-version.test.ts
```

Result: exit `0`; 2/2 tests passed:

- `shareVersion stabil dan berubah ketika data preview berubah`
- `signed query media tidak membuat versi berubah`

## Validation

Focused regression command:

```powershell
npx tsx --test tests/share-version.test.ts tests/brand-user.test.ts tests/feed-product-discount.test.ts
```

Result: exit `0`; 9/9 tests passed.

Required project typecheck command:

```powershell
npx tsc --noEmit
```

Result: exit `1` due to six pre-existing tests importing unavailable `vitest` (`admin-brand-schema`, `admin-product-form`, `admin-product-media`, `admin-product-schema`, `admin-product-visibility`, and `product-video-draft`). The task base `package.json` has no `vitest`, while root `tsconfig.json` includes all `**/*.ts` test files.

Isolated Task 1 typecheck was run with a temporary `tsconfig.task-1.json` limited to the six changed source/test files, then the temporary config and its build artifact were removed:

```powershell
npx tsc --noEmit --project tsconfig.task-1.json
```

Result: exit `0`.

## Self-Review

- The change uses existing `brandDisplayName` and `brandPhotoUrl` helpers, so admin identity is never hashed from private owner data.
- Version inputs use original media URLs after stripping query strings, avoiding signature expiry churn while preserving content-path changes.
- Existing response serializers were extended in place; no parallel feed serializer was introduced.
- The staged diff was reviewed and whitespace-checked before commit. The commit contains only the six task files.

## Concerns

1. Full root typecheck remains unavailable until the existing missing `vitest` dependency/type configuration is resolved. This is outside Task 1 scope and was not changed.

## Reviewer Fix

Reviewer found that the Feed serializer emitted `shareVersion` while the
`FeedPostListItem` API contract did not declare it. The type is now required
and a focused serialized Feed-response fixture locks that contract.

### RED

The new contract check failed before the fix with:

```text
Type '"shareVersion"' is not assignable to type 'keyof FeedPostListItem'.
```

### GREEN

```powershell
npx tsc --ignoreConfig --noEmit --module NodeNext --moduleResolution NodeNext --target ES2022 --skipLibCheck --types node tests/share-version.test.ts
npx tsx --test tests/share-version.test.ts tests/brand-user.test.ts tests/feed-product-discount.test.ts
git diff --check
```

Results: contract typecheck passed, 10/10 focused tests passed, and the diff
check passed.
