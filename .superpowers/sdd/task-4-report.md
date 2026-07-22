# Task 4 - Public Feed share page and metadata

## Status

Complete. Final security/spec review found no Critical or Important issue.

## Implementation

- Added `getPublicShareFeedPost()` with the same public visibility gate as the existing Feed list: `ACTIVE`, not deleted, encoded, and renderable media kinds only.
- Added deterministic Feed `shareVersion` reuse so API and browser preview URLs stay aligned.
- Added `buildFeedShareMetadata()` with a canonical Feed URL that omits `v`, a versioned explicit Task 5 OG image URL, safe fallback copy, public robots, Open Graph, and Twitter large-image metadata.
- Added `/feed/[id]` server page with a cache-safe poster, author identity, caption, and store CTA. Missing or non-public posts use `notFound()` and no private data is selected.
- Added a canonical `/feed` alternate URL.

## Validation

- RED/GREEN focused tests: `npx tsx --test tests/share-feed-data.test.ts tests/share-metadata.test.ts` - 3 passed.
- Targeted source typecheck: `npx tsc --noEmit -p tsconfig.task4.json` - passed. The temporary config was removed after verification.
- `git diff --check` - passed.
- Root `npx tsc --noEmit` still fails only on six pre-existing test imports for missing `vitest`; Task 4-specific type errors were fixed and no longer appear.

## Commit

`2b3b38f5 feat(web): add public Feed share pages`

## Concerns

The explicit Feed OG image endpoint is intentionally only referenced here; it is implemented in Task 5.
