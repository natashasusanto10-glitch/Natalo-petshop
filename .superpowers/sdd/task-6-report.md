# Task 6 report

Implemented a shared `ProductForm` for create and edit flows.

- Both routes now render the same form with mode-specific copy.
- Create and edit use the same media rail, AI description field, draft variants, validation, and sticky save action.
- Create posts to `/api/admin/products`; edit patches `/api/admin/products/:id`; both return to `/admin/products`.
- Product media rail supports a parent video draft ref so video can be prepared and committed as part of the save flow.
- Legacy `NewProductForm` remains as a compatibility wrapper.

## Verification

`npx vitest run tests/admin-product-form.test.ts tests/admin-product-media.test.ts tests/product-video-draft.test.ts` — 17 tests passed.

`npx tsc --noEmit` still reports pre-existing schema/Prisma errors in `lib/product/admin-product-form.ts` and `lib/products.ts`, plus missing Vitest declarations in this worktree. The changed form/media files no longer produce TypeScript errors after the ref fix.

## Concern

The current video API exposes provisioning/upload and processing status but no explicit finalize endpoint for creation-state promotion. The form commits the video after product creation; final visibility remains governed by the existing video/webhook lifecycle.

## Follow-up fix

Added explicit `/finalize` and `/compensate` admin routes, hidden create finalization after video commit, draft removal DELETE handling, compensation for failed create/video flows, strict incomplete-variant rejection, and video metadata on POST. Focused tests remain 17 passed.

---

# Task 6 - Product and profile share previews

## Status

Complete. Product and public-profile links now use the same explicit, safe
Open Graph architecture as Feed previews while retaining their existing deep
link paths.

## Implementation

- Added public share-data resolvers for products and profiles. Product data
  reuses the customer price resolver and checks active/ready visibility before
  rendering metadata or a public page. Profiles reuse username resolution,
  normalize handles, sanitize bios, and count only public active posts.
- Added explicit `1200 x 630` endpoints:
  `/api/share/og/product/[slug]` and `/api/share/og/profile/[username]`.
  Both require the deterministic `v` cache token, return `404` for missing or
  unavailable resources, and render local fallbacks when an image cannot be
  loaded safely.
- Product cards show a contained product image, effective price, active
  discount, stock state, and Natalo identity. Profile cards show the avatar,
  official marker, sanitized profile text, and public stats.
- Public metadata now uses canonical `/products/<slug>` and `/u/<username>`
  paths without a query string. OG and Twitter images use only the explicit
  versioned image routes. No `og:video` tag is emitted.
- Reused the hardened image allowlist, bounded fetch, MIME/magic-byte checks,
  and cache policy from Task 5. No route accepts an arbitrary image URL.
- Official account previews use the official name and `/logo.png`; staff
  display name, avatar, and bio are not exposed through crawler metadata.
- Removed the legacy product `opengraph-image.tsx` implementation so there is
  one product preview architecture.

## Validation

- RED: `npx tsx --test tests/share-product-profile.test.ts` initially failed
  because `@/lib/share/product-share-data` did not exist.
- GREEN: `npx tsx --test tests/share-product-profile.test.ts
  tests/brand-user.test.ts tests/share-og-security.test.ts
  tests/share-feed-card.test.ts` passed 21/21.
- Targeted TypeScript validation passed with a temporary Task 6 tsconfig,
  removed after verification.
- Targeted ESLint completed with no errors and `git diff --check` passed.
- Root `npx tsc --noEmit` remains blocked only by six pre-existing test files
  importing unavailable `vitest` declarations. No Task 6 type error remains.

## Commit

`feat(web): add commerce and profile share previews`

## Concerns

The product and profile HTML metadata is intentionally dynamic because the
versioned OG URL must reflect current public price, stock, profile, and stats.
Only the immutable `v` image endpoints receive CDN caching. Task 7 was not
started.
