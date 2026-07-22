# Task 5 - Secure Feed Open Graph image

## Status

Complete. The Feed preview image is now rendered by an explicit public OG
endpoint and uses a bounded, allowlisted image loader.

## Implementation

- Added `GET /api/share/og/feed/[id]`, which resolves only through
  `getPublicShareFeedPost()`. Non-public, deleted, or not-ready posts return
  `404` before any preview data is rendered.
- Added a 1200 x 630 Feed card for video, photo, carousel, official identity,
  duration/play indication, and a local Natalo fallback when media is absent.
- Extended public Feed preview data with duration and media count, so the card
  does not infer private media data or use a second query.
- Added strict URL validation: HTTPS only, no credentials, port, fragment, IP
  literal, localhost, or lookalike host. The allowed hosts are Natalo's
  canonical domains, configured Bunny CDN hosts, and UploadThing's official
  public CDN suffix.
- Added a bounded image loader: redirects are rejected, requests time out
  after four seconds, responses are capped at 4 MB, and only JPEG, PNG, WebP,
  or GIF is accepted. Failed media and avatar loads render the local fallback
  instead of retrying the remote URL in `ImageResponse`.
- The endpoint cache is `s-maxage=3600` with one-day stale-while-revalidate.
  The `v` query remains a cache key only; canonical object identity is
  unchanged and no `og:video` is emitted.

## Validation

- RED: both new test files initially failed because the security and card
  modules did not exist.
- GREEN: `npx tsx --test tests/share-og-security.test.ts
  tests/share-feed-card.test.ts tests/share-feed-data.test.ts
  tests/share-metadata.test.ts` passed 19/19.
- Targeted source typecheck passed using a temporary Task 5 tsconfig, removed
  after verification.
- Targeted ESLint completed with no errors.
- `git diff --check` passed.
- Root `npx tsc --noEmit` remains blocked only by the six pre-existing test
  files that import an unavailable `vitest` dependency. No Task 5 type error
  remains.

## Commit

`6081a421 feat(web): render secure Feed share cards`

## Concerns

The route fetches image bytes itself so redirect, timeout, MIME, and size
policy are enforceable. Product and profile OG routes are intentionally left
for Task 6, where they will reuse the same validator and loader.
