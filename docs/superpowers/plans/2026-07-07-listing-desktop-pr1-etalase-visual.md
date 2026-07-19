# Listing & Discovery Desktop — PR1 (Etalase Visual & Container) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the low-risk visual layer of the "Rak Etalase" listing redesign — 1280 container across the four discovery pages, the warm "lit-shelf" product-card signature, a reusable `EtalaseBand` header (used on `/kategori` & `/brands`), a shared `FilterChip`, and the `/search` rating-sort option — without changing any data source, API, or transaction logic.

**Architecture:** Additive CSS utilities + small presentational components layered on the existing G1 design system (`PageContainer`, tokens in `app/globals.css`). `ProductCard` gains a subtle static pedestal + hover shelf-line + a rose discount badge (Flutter-aligned tokens) applied globally to the default variant. `/products` data flow is untouched in PR1 (it converges onto the search stack in PR2); PR1 only widens its container and inherits the new card. The `EtalaseBand` is built here and consumed by `/kategori` and `/brands`; `/products` receives the band in PR2 together with sticky-header suppression, so desktop `/products` never shows redundant chrome mid-sequence.

**Tech Stack:** Next.js App Router, React, Tailwind CSS v4 (`@theme` + CSS vars), Prisma (read-only, untouched here), `node:test` via `tsx` for pure-logic unit tests.

## Global Constraints

- **No changes** to `flutter_app/**`, `prisma/schema.prisma`, `app/api/**`, or cart/checkout/voucher/loyalty/auth logic. Verified by `git diff --name-only` in the final task.
- **Brand identity fixed:** primary blue `#1E5FBF` (token `natalo-500`), font Nunito (`--font-sans`). Do **not** introduce the app's `#2568C7` or any aqua/teal accent. Pedestal tint is **warm/neutral only** (amber + faint natalo), uniform across all categories.
- **Container width:** `1280px` via `max-w-[var(--nat-container)]`; responsive gutter via `px-[var(--nat-gutter)]` (both already defined in `app/globals.css`). Prefer the `PageContainer` primitive where a page owns its wrapper.
- **Confirmed trust claims (must be literally true, owner-approved):** `"Kirim hari ini se-Medan"`, `"100% Original"`, `"Toko fisik sejak 2018"`, rating `"4.9"`. Rating is a single exported constant.
- **Mobile web preserved:** every enhancement is either universally gentle or `md:`-gated. Existing mobile chrome (`ProductCatalogStickyHeader`, `ProductFilterChips`, `BottomSheet`) is not removed in PR1.
- **Premium visible at rest** — the pedestal is static (not hover-only); only the shelf-line intensifies on hover.
- **Testing convention (repo reality):** pure helpers in `lib/` get `node:test` unit tests (run with `npx tsx --test`); React components have **no** unit tests and are verified via `npx tsc --noEmit` + `npm run lint` + `npx next build` + browser preview at 375/768/1024/1280/1440/1920. Follow this — do not scaffold a React test runner.
- **Commit after every task.** Conventional-commit messages.

---

## File Structure

**Created:**
- `lib/etalase.ts` — pure helpers `etalaseHeading()`, `etalaseTagline()` + constants `ETALASE_TRUST`, `NATALO_RATING`. One responsibility: derive band copy.
- `tests/etalase.test.ts` — unit tests for the above.
- `components/products/EtalaseBand.tsx` — presentational band header (breadcrumb + heading + tagline + meta line + static shelf-line + optional bleed thumbnail).
- `components/products/FilterChip.tsx` — shared removable filter chip (extracted from `/search`).

**Modified:**
- `app/globals.css` — add `.nat-lit-shelf` + `.nat-shelf-line` utilities.
- `components/ProductCard.tsx` — default variant: pedestal + hover shelf-line + rose discount badge + gold rating star.
- `app/search/page.tsx` — import shared `FilterChip` (drop local copy); add `rating_desc` sort option; migrate `max-w-6xl` → 1280 (3 spots).
- `app/products/page.tsx` — wrapper `max-w-6xl px-4` → `PageContainer` (1280).
- `components/CategoryTabPage.tsx` — container → 1280; `EtalaseBand` (md+); lit-shelf tiles.
- `components/brands/BrandDirectoryClient.tsx` — `max-w-2xl` → 1280; responsive brand grid; `EtalaseBand` (md+); lit-shelf tiles; constrain search input width.

---

## Task 1: Lit-shelf + shelf-line CSS utilities

**Files:**
- Modify: `app/globals.css` (append near end, after the skeleton/animation block)

**Interfaces:**
- Produces: two global CSS classes — `.nat-lit-shelf` (static warm pedestal via `::before`, always faintly visible) and `.nat-shelf-line` (2px natalo underline via `::after`, `opacity:0` → `1` on `.group:hover`). Consumed by Tasks 2, 7, 8.

- [ ] **Step 1: Add the utilities**

Append to `app/globals.css`:

```css
/* ── Rak Etalase — lit-shelf pedestal + shelf-line (listing signature) ──
   Warm/neutral pedestal (amber + faint natalo), uniform across categories.
   Static so it reads "premium at rest"; shelf-line intensifies on hover. */
.nat-lit-shelf {
  position: relative;
}
.nat-lit-shelf::before {
  content: "";
  position: absolute;
  left: 8%;
  right: 8%;
  bottom: 0;
  height: 44%;
  border-radius: 999px;
  background: radial-gradient(
    62% 100% at 50% 100%,
    rgba(245, 158, 11, 0.12),
    rgba(30, 95, 191, 0.05) 55%,
    transparent 72%
  );
  pointer-events: none;
  z-index: 0;
  opacity: 0.85;
  transition: opacity 220ms ease;
}
.group:hover .nat-lit-shelf::before {
  opacity: 1;
}
.nat-shelf-line::after {
  content: "";
  position: absolute;
  left: 10%;
  right: 10%;
  bottom: 0;
  height: 2px;
  border-radius: 999px;
  background: linear-gradient(
    90deg,
    transparent,
    #1e5fbf 22%,
    #4a90e2 78%,
    transparent
  );
  opacity: 0;
  transition: opacity 220ms ease;
}
.group:hover .nat-shelf-line::after {
  opacity: 1;
}
```

- [ ] **Step 2: Verify the stylesheet compiles**

Run: `npx next build` (or rely on `npm run lint` if faster locally; a full build in the verification task also catches this)
Expected: build succeeds, no CSS parse error.

- [ ] **Step 3: Commit**

```bash
git add app/globals.css
git commit -m "feat(listing): add lit-shelf pedestal + shelf-line CSS utilities"
```

---

## Task 2: ProductCard lit-shelf + rose discount badge + rating star

**Files:**
- Modify: `components/ProductCard.tsx` (default variant only — the `return (...)` at L132–217; do NOT touch the `isCompact` branch)

**Interfaces:**
- Consumes: `.nat-lit-shelf`, `.nat-shelf-line` (Task 1); existing `computeDiscountPercent` (already in file), `discountPercent`, `hasMarkdown`, `memberPrice`, `rankBadge`, `badge` locals.
- Produces: no new exports; the default `ProductCard` visual now shows the pedestal, a hover shelf-line, a rose `-N%` badge, and a gold rating star. All consumers (homepage, search, products) inherit this.

- [ ] **Step 1: Add pedestal + shelf-line to the image container**

In `components/ProductCard.tsx`, the default-variant image wrapper currently reads (L136–139):

```tsx
        <div
          className="relative aspect-square rounded-2xl bg-white"
          style={{ viewTransitionName: `nat-prod-${product.slug}` }}
        >
```

Replace with:

```tsx
        <div
          className="nat-lit-shelf nat-shelf-line relative aspect-square rounded-2xl bg-white"
          style={{ viewTransitionName: `nat-prod-${product.slug}` }}
        >
```

- [ ] **Step 2: Ensure the image paints above the pedestal**

In the same block, the `<Image>` className (L149) currently ends with `object-contain p-2 transition duration-200 group-hover:scale-[1.03]`. Prepend `relative z-[1]` so the contained image sits above the `::before` pedestal:

```tsx
              className="relative z-[1] object-contain p-2 transition duration-200 group-hover:scale-[1.03]"
```

Also add `relative z-[1]` to the no-image fallback (L152):

```tsx
            <div className="relative z-[1] flex h-full items-center justify-center text-5xl text-gray-300">🐾</div>
```

- [ ] **Step 3: Add the rose discount badge and shift the optional `badge` chip when present**

The default variant has no percent badge today. Immediately AFTER the closing `)}` of the no-image fallback and BEFORE the `{memberPrice !== null && (` block (i.e. right after L153), insert:

```tsx
          {discountPercent > 0 && (
            <span className="absolute right-1.5 top-1.5 z-10 rounded-bl-xl rounded-tr-2xl bg-[#E11D48] px-1.5 py-0.5 text-[11px] font-black text-white shadow-sm">
              -{discountPercent}%
            </span>
          )}
```

Then update the optional `badge` prop chip (L167–171) so it drops below the discount badge when both are present. Replace:

```tsx
          {badge && (
            <span className="absolute right-1.5 top-1.5 rounded-full border border-white/80 bg-white/95 px-2 py-0.5 text-[10px] font-black text-natalo-500 shadow-[var(--shadow-card)]">
              {badge}
            </span>
          )}
```

with:

```tsx
          {badge && (
            <span
              className={`absolute right-1.5 ${discountPercent > 0 ? "top-9" : "top-1.5"} rounded-full border border-white/80 bg-white/95 px-2 py-0.5 text-[10px] font-black text-natalo-500 shadow-[var(--shadow-card)]`}
            >
              {badge}
            </span>
          )}
```

- [ ] **Step 4: Add a gold star to the rating line**

The `showRating` block (L192–197) currently renders text only. Replace:

```tsx
          {showRating && (product.avgRating > 0 || product.reviewCount > 0) && (
            <p className="mt-1.5 truncate text-[11px] font-semibold text-zinc-500">
              {product.avgRating > 0 ? `Rating ${product.avgRating.toFixed(1)}` : "Baru"}
              {product.reviewCount > 0 ? ` · ${product.reviewCount} ulasan` : ""}
            </p>
          )}
```

with:

```tsx
          {showRating && (product.avgRating > 0 || product.reviewCount > 0) && (
            <p className="mt-1.5 flex items-center gap-1 truncate text-[11px] font-semibold text-zinc-500">
              <span className="text-[#FACC15]" aria-hidden="true">★</span>
              {product.avgRating > 0 ? product.avgRating.toFixed(1) : "Baru"}
              {product.reviewCount > 0 ? ` · ${product.reviewCount} ulasan` : ""}
            </p>
          )}
```

- [ ] **Step 5: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no errors.

- [ ] **Step 6: Preview verify (no regression on homepage/search cards)**

Start the worktree preview (see verification task for launch setup). Load `/` and `/products` at 1280px. Confirm: pedestal is faintly visible at rest, hovering a card brightens the shelf-line, discounted products show the rose `-N%` badge, no layout shift, homepage cards still look correct.

- [ ] **Step 7: Commit**

```bash
git add components/ProductCard.tsx
git commit -m "feat(product-card): warm lit-shelf pedestal, rose discount badge, gold rating star"
```

---

## Task 3: `lib/etalase.ts` — band copy helpers (pure, TDD)

**Files:**
- Create: `lib/etalase.ts`
- Test: `tests/etalase.test.ts`

**Interfaces:**
- Produces:
  - `etalaseHeading(opts: { brandName?: string | null; categoryName?: string | null; isSearch?: boolean; query?: string | null }): string`
  - `etalaseTagline(opts: { brandName?: string | null; categoryName?: string | null; isSearch?: boolean }): string`
  - `ETALASE_TRUST: readonly string[]` and `NATALO_RATING: string`
- Consumed by: `EtalaseBand` (Task 4) and its callers (Tasks 7, 8).

- [ ] **Step 1: Write the failing test**

Create `tests/etalase.test.ts`:

```ts
import test from "node:test";
import assert from "node:assert/strict";
import {
  etalaseHeading,
  etalaseTagline,
  ETALASE_TRUST,
  NATALO_RATING,
} from "../lib/etalase";

test("etalaseHeading: search query wins over everything", () => {
  assert.equal(
    etalaseHeading({ isSearch: true, query: "kucing", brandName: "Whiskas" }),
    'Hasil untuk "kucing"',
  );
});

test("etalaseHeading: brand takes precedence over category", () => {
  assert.equal(
    etalaseHeading({ brandName: "Royal Canin", categoryName: "Anjing" }),
    "Produk Royal Canin",
  );
});

test("etalaseHeading: category when no brand/search", () => {
  assert.equal(etalaseHeading({ categoryName: "Aquarium" }), "Aquarium");
});

test("etalaseHeading: default catalog label", () => {
  assert.equal(etalaseHeading({}), "Katalog Produk");
});

test("etalaseTagline: default mentions Medan store", () => {
  assert.match(etalaseTagline({}), /Medan/);
});

test("trust claims are the owner-confirmed set incl. rating", () => {
  assert.deepEqual(ETALASE_TRUST, [
    "Kirim hari ini se-Medan",
    "100% Original",
    "Toko fisik sejak 2018",
  ]);
  assert.equal(NATALO_RATING, "4.9");
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx tsx --test tests/etalase.test.ts`
Expected: FAIL — cannot find module `../lib/etalase`.

- [ ] **Step 3: Implement `lib/etalase.ts`**

Create `lib/etalase.ts`:

```ts
// Pure copy helpers for the "Etalase Natalo" band header.
// No data access — callers pass resolved names. Keeps band text consistent
// across /products, /kategori, /brands, /search.

export const ETALASE_TRUST = [
  "Kirim hari ini se-Medan",
  "100% Original",
  "Toko fisik sejak 2018",
] as const;

// Owner-confirmed store rating. Single source of truth — change here only.
export const NATALO_RATING = "4.9";

type HeadingOpts = {
  brandName?: string | null;
  categoryName?: string | null;
  isSearch?: boolean;
  query?: string | null;
};

export function etalaseHeading({
  brandName,
  categoryName,
  isSearch,
  query,
}: HeadingOpts): string {
  if (isSearch && query && query.trim()) return `Hasil untuk "${query.trim()}"`;
  if (brandName && brandName.trim()) return `Produk ${brandName.trim()}`;
  if (categoryName && categoryName.trim()) return categoryName.trim();
  return "Katalog Produk";
}

type TaglineOpts = {
  brandName?: string | null;
  categoryName?: string | null;
  isSearch?: boolean;
};

export function etalaseTagline({
  brandName,
  categoryName,
  isSearch,
}: TaglineOpts): string {
  if (isSearch) return "Menampilkan produk yang cocok dengan pencarianmu.";
  if (brandName && brandName.trim())
    return `Koleksi ${brandName.trim()} original, siap kirim dari toko kami di Medan.`;
  if (categoryName && categoryName.trim())
    return `Pilihan ${categoryName.trim()} lengkap, langsung dari rak Natalo.`;
  return "Semua kebutuhan hewan & aquarium, langsung dari toko kami di Medan.";
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npx tsx --test tests/etalase.test.ts`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/etalase.ts tests/etalase.test.ts
git commit -m "feat(listing): pure etalase heading/tagline helpers + trust constants"
```

---

## Task 4: `EtalaseBand` component

**Files:**
- Create: `components/products/EtalaseBand.tsx`

**Interfaces:**
- Consumes: nothing from other tasks at runtime (callers pass strings from `lib/etalase`).
- Produces: `EtalaseBand` with props:
  ```ts
  type Crumb = { label: string; href?: string };
  type EtalaseBandProps = {
    heading: string;
    tagline: string;
    meta?: string[];
    breadcrumb?: Crumb[];
    thumbnailUrl?: string | null;
    className?: string;
  };
  ```
  Consumed by Tasks 7 (`/kategori`) and 8 (`/brands`); reused for `/products` in PR2.

- [ ] **Step 1: Implement the component**

Create `components/products/EtalaseBand.tsx`:

```tsx
import Link from "next/link";
import Image from "next/image";

type Crumb = { label: string; href?: string };

type Props = {
  heading: string;
  tagline: string;
  meta?: string[];
  breadcrumb?: Crumb[];
  thumbnailUrl?: string | null;
  className?: string;
};

export function EtalaseBand({
  heading,
  tagline,
  meta = [],
  breadcrumb = [],
  thumbnailUrl,
  className = "",
}: Props) {
  return (
    <section
      className={`relative overflow-hidden rounded-[var(--radius-xl)] border border-natalo-100 bg-gradient-to-br from-natalo-50 to-white px-5 py-5 md:px-7 md:py-6 ${className}`}
    >
      <div className="relative z-10 max-w-2xl">
        {breadcrumb.length > 0 && (
          <nav className="mb-2 flex flex-wrap items-center gap-1.5 text-xs font-semibold text-natalo-600">
            {breadcrumb.map((c, i) => (
              <span key={`${c.label}-${i}`} className="flex items-center gap-1.5">
                {i > 0 && <span className="text-natalo-300">/</span>}
                {c.href ? (
                  <Link href={c.href} className="transition hover:text-natalo-800">
                    {c.label}
                  </Link>
                ) : (
                  <span className="text-natalo-800">{c.label}</span>
                )}
              </span>
            ))}
          </nav>
        )}
        <h1 className="text-2xl font-extrabold tracking-tight text-natalo-900 md:text-3xl">
          {heading}
        </h1>
        <p className="mt-1.5 max-w-prose text-sm text-zinc-600 md:text-[15px]">
          {tagline}
        </p>
        {meta.length > 0 && (
          <p className="mt-3 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs font-semibold text-natalo-700">
            {meta.map((m, i) => (
              <span key={`${m}-${i}`} className="flex items-center gap-2">
                {i > 0 && <span className="text-natalo-300">·</span>}
                {m}
              </span>
            ))}
          </p>
        )}
      </div>

      {thumbnailUrl && (
        <div className="pointer-events-none absolute -right-6 -top-6 hidden h-40 w-40 rotate-6 overflow-hidden rounded-3xl opacity-[0.14] md:block">
          <Image src={thumbnailUrl} alt="" fill sizes="160px" className="object-cover" />
        </div>
      )}

      {/* static shelf-line — the unifying 2px natalo accent at the band base */}
      <span
        aria-hidden="true"
        className="absolute inset-x-0 bottom-0 h-0.5 bg-gradient-to-r from-transparent via-natalo-500 to-transparent"
      />
    </section>
  );
}
```

- [ ] **Step 2: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no errors (component is unused until Tasks 7–8 — that is fine; it exports a named symbol).

- [ ] **Step 3: Commit**

```bash
git add components/products/EtalaseBand.tsx
git commit -m "feat(listing): reusable EtalaseBand header component"
```

---

## Task 5: Extract shared `FilterChip`

**Files:**
- Create: `components/products/FilterChip.tsx`
- Modify: `app/search/page.tsx` (remove local `FilterChip` def L848–859; import the shared one)

**Interfaces:**
- Produces: `FilterChip({ label, onRemove }: { label: string; onRemove: () => void })` — identical markup to the current `/search` chip, self-contained X icon. Consumed by `/search` now, `/products` in PR2.

- [ ] **Step 1: Create the shared component**

Create `components/products/FilterChip.tsx` (self-contained X icon so it carries no `/search`-local dependency):

```tsx
type Props = {
  label: string;
  onRemove: () => void;
};

export function FilterChip({ label, onRemove }: Props) {
  return (
    <button
      type="button"
      onClick={onRemove}
      className="inline-flex h-7 max-w-full items-center gap-1 rounded-full bg-natalo-50 px-2.5 text-xs font-extrabold text-natalo-700 active:bg-natalo-100"
    >
      <span className="truncate">{label}</span>
      <svg
        viewBox="0 0 24 24"
        className="h-3.5 w-3.5 shrink-0"
        fill="none"
        stroke="currentColor"
        strokeWidth="2.5"
        strokeLinecap="round"
        aria-hidden="true"
      >
        <path d="M6 6l12 12M18 6L6 18" />
      </svg>
    </button>
  );
}
```

- [ ] **Step 2: Remove the local def in `app/search/page.tsx` and import the shared one**

Delete the local `function FilterChip(...)` block (L848–859). Add to the import group at the top of `app/search/page.tsx` (near the other `@/components` imports, e.g. after the `SearchFilters` import block ~L13):

```tsx
import { FilterChip } from "@/components/products/FilterChip";
```

- [ ] **Step 3: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no errors. (If `XIcon` becomes unused after removing the local chip, either leave it — it is used elsewhere in the file — or remove it only if lint flags it as unused.)

- [ ] **Step 4: Preview verify**

Load `/search?q=makanan`, apply a category + brand filter. Confirm the active-filter chips still render and remove correctly (unchanged behavior).

- [ ] **Step 5: Commit**

```bash
git add components/products/FilterChip.tsx app/search/page.tsx
git commit -m "refactor(search): extract shared FilterChip component"
```

---

## Task 6: `/search` — rating sort option + 1280 container

**Files:**
- Modify: `app/search/page.tsx` (`SORT_OPTIONS` L85–91; three `max-w-6xl` occurrences L257, L538, L951)

**Interfaces:**
- Consumes: existing `Sort` type (already includes `"rating_desc"` at L63–69) and the existing sort `BottomSheet` renderer (no new control needed — the new option flows through the existing map).

- [ ] **Step 1: Add the rating option to `SORT_OPTIONS`**

Replace (L85–91):

```tsx
const SORT_OPTIONS: { value: Sort; label: string }[] = [
  { value: "relevance", label: "Relevansi" },
  { value: "price_asc", label: "Harga terendah" },
  { value: "price_desc", label: "Harga tertinggi" },
  { value: "newest", label: "Terbaru" },
  { value: "best_seller", label: "Terlaris" },
];
```

with:

```tsx
const SORT_OPTIONS: { value: Sort; label: string }[] = [
  { value: "relevance", label: "Relevansi" },
  { value: "best_seller", label: "Terlaris" },
  { value: "newest", label: "Terbaru" },
  { value: "rating_desc", label: "Rating tertinggi" },
  { value: "price_asc", label: "Harga terendah" },
  { value: "price_desc", label: "Harga tertinggi" },
];
```

- [ ] **Step 2: Widen the three containers to 1280**

Replace the body container (L257):

```tsx
      <div className="mx-auto max-w-6xl px-3 py-4 md:px-4 md:py-6">
```
with:
```tsx
      <div className="mx-auto max-w-[var(--nat-container)] px-3 py-4 md:px-4 md:py-6">
```

Replace the header inner container (L538):

```tsx
      <div ref={wrapperRef} className="relative mx-auto flex max-w-6xl items-center gap-2">
```
with:
```tsx
      <div ref={wrapperRef} className="relative mx-auto flex max-w-[var(--nat-container)] items-center gap-2">
```

Replace the Suspense fallback container (L951):

```tsx
        <div className="mx-auto max-w-6xl px-3 py-4 md:px-4">
```
with:
```tsx
        <div className="mx-auto max-w-[var(--nat-container)] px-3 py-4 md:px-4">
```

- [ ] **Step 3: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no errors.

- [ ] **Step 4: Preview verify**

Load `/search?q=makanan` at 1280px. Confirm: content spans the wider 1280 container (was 1152), the sort sheet now lists "Rating tertinggi", and selecting it re-sorts results.

- [ ] **Step 5: Commit**

```bash
git add app/search/page.tsx
git commit -m "feat(search): add rating sort option + widen to 1280 container"
```

---

## Task 7: `/products` — 1280 container

**Files:**
- Modify: `app/products/page.tsx` (imports L1–6; wrapper L81–102)

**Interfaces:**
- Consumes: `PageContainer` (existing primitive). No band here in PR1 (band + sticky-header suppression ship together in PR2 to avoid redundant desktop chrome).

- [ ] **Step 1: Import `PageContainer`**

Add to the import block at the top of `app/products/page.tsx`:

```tsx
import { PageContainer } from "@/components/ui/PageContainer";
```

- [ ] **Step 2: Swap the width wrapper**

Replace the opening wrapper `<div ...>` (L81–87):

```tsx
    <div
      className={`mx-auto max-w-6xl px-4 ${
        isSearchResult
          ? "pb-[calc(1.5rem+env(safe-area-inset-bottom))] md:py-8"
          : "pb-[calc(6rem+env(safe-area-inset-bottom))] md:py-10"
      }`}
    >
```

with:

```tsx
    <PageContainer
      className={
        isSearchResult
          ? "pb-[calc(1.5rem+env(safe-area-inset-bottom))] md:py-8"
          : "pb-[calc(6rem+env(safe-area-inset-bottom))] md:py-10"
      }
    >
```

(Keep the default `as="div"` — the original wrapper was a `<div>`; do not introduce a nested `<main>`.)

Then replace the matching closing `</div>` of that wrapper (L101) with `</PageContainer>`. (It is the last element before the function's closing `);` — the one after the `</Suspense>` block.)

- [ ] **Step 3: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no errors.

- [ ] **Step 4: Preview verify**

Load `/products` at 1280 and 1440px. Confirm content is centered within 1280, cards show the new pedestal, no horizontal overflow, mobile (`375px`) unchanged.

- [ ] **Step 5: Commit**

```bash
git add app/products/page.tsx
git commit -m "feat(products): migrate listing wrapper to 1280 PageContainer"
```

---

## Task 8: `/kategori` — 1280 + EtalaseBand + lit-shelf tiles

**Files:**
- Modify: `components/CategoryTabPage.tsx` (container L76; heading area L77–89; tile L127 + image wrapper L129)

**Interfaces:**
- Consumes: `EtalaseBand` (Task 4), `etalaseHeading`/`etalaseTagline` (Task 3), `.nat-lit-shelf`/`.nat-shelf-line` (Task 1).

- [ ] **Step 1: Add imports**

At the top of `components/CategoryTabPage.tsx`, add:

```tsx
import { EtalaseBand } from "@/components/products/EtalaseBand";
```

(`CategoryTabPage` is a client component; `EtalaseBand` is a plain presentational component and imports fine into it.)

- [ ] **Step 2: Widen the container**

Replace (L76):

```tsx
    <div className="mx-auto max-w-6xl px-4 py-4 md:py-10">
```
with:
```tsx
    <div className="mx-auto max-w-[var(--nat-container)] px-[var(--nat-gutter)] py-4 md:py-10">
```

- [ ] **Step 3: Show `EtalaseBand` on desktop, keep the plain heading on mobile**

Replace the heading block (L77–89):

```tsx
      <div className="flex items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-black text-gray-900 md:text-3xl">Kategori</h1>
          <p className="mt-1 text-sm text-gray-500">
            Pilih kebutuhan hewan peliharaanmu tanpa menunggu halaman kosong.
          </p>
        </div>
        {refreshing && (
          <span className="mt-1 shrink-0 rounded-full bg-natalo-50 px-3 py-1 text-xs font-bold text-natalo-700">
            Memperbarui...
          </span>
        )}
      </div>
```

with:

```tsx
      <div className="md:hidden">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h1 className="text-2xl font-black text-gray-900">Kategori</h1>
            <p className="mt-1 text-sm text-gray-500">
              Pilih kebutuhan hewan peliharaanmu tanpa menunggu halaman kosong.
            </p>
          </div>
          {refreshing && (
            <span className="mt-1 shrink-0 rounded-full bg-natalo-50 px-3 py-1 text-xs font-bold text-natalo-700">
              Memperbarui...
            </span>
          )}
        </div>
      </div>

      <div className="hidden md:block">
        <EtalaseBand
          heading="Kategori — Jelajahi rak Natalo"
          tagline="Telusuri semua kebutuhan hewan & aquarium per kategori, langsung dari rak toko kami di Medan."
          breadcrumb={[{ label: "Beranda", href: "/" }, { label: "Kategori" }]}
        />
      </div>
```

- [ ] **Step 4: Add lit-shelf to the category tiles**

Replace the tile `<Link>` opening + image wrapper (L123–129):

```tsx
              <Link
                key={category.id}
                href={`/products?kategori=${category.slug}`}
                prefetch
                className="group overflow-hidden rounded-2xl border border-gray-100 bg-white shadow-sm transition active:opacity-90 sm:hover:border-natalo-200 sm:hover:shadow-md"
              >
                <div className="relative aspect-[4/3] bg-natalo-50">
```

with:

```tsx
              <Link
                key={category.id}
                href={`/products?kategori=${category.slug}`}
                prefetch
                className="nat-shelf-line group relative overflow-hidden rounded-2xl border border-gray-100 bg-white shadow-sm transition active:opacity-90 sm:hover:border-natalo-200 sm:hover:shadow-md"
              >
                <div className="nat-lit-shelf relative aspect-[4/3] bg-natalo-50">
```

- [ ] **Step 5: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no errors.

- [ ] **Step 6: Preview verify**

Load `/kategori` at 375px (mobile heading + chips unchanged) and 1280px (EtalaseBand shows, tiles span 1280, pedestal + hover shelf-line on tiles). No overflow.

- [ ] **Step 7: Commit**

```bash
git add components/CategoryTabPage.tsx
git commit -m "feat(kategori): 1280 container, EtalaseBand, lit-shelf tiles"
```

---

## Task 9: `/brands` — structural widen (1280) + responsive grid + EtalaseBand + lit-shelf

**Files:**
- Modify: `components/brands/BrandDirectoryClient.tsx` (header inner L76; body container L94; search input L95–107; grid L118; tile L120–128)

**Interfaces:**
- Consumes: `EtalaseBand` (Task 4), `.nat-lit-shelf`/`.nat-shelf-line` (Task 1).

- [ ] **Step 1: Add the import**

At the top of `components/brands/BrandDirectoryClient.tsx`, add:

```tsx
import { EtalaseBand } from "@/components/products/EtalaseBand";
```

- [ ] **Step 2: Widen header inner + body containers to 1280**

Replace the header inner (L76):

```tsx
        <div className="mx-auto flex h-16 max-w-2xl items-center gap-3 px-4">
```
with:
```tsx
        <div className="mx-auto flex h-16 max-w-[var(--nat-container)] items-center gap-3 px-4">
```

Replace the body container (L94):

```tsx
      <div className="mx-auto max-w-2xl px-4 pt-4">
```
with:
```tsx
      <div className="mx-auto max-w-[var(--nat-container)] px-[var(--nat-gutter)] pt-4">
```

- [ ] **Step 3: Add the desktop `EtalaseBand` and constrain the search input width**

The `<label className="relative block">` search input (L95–107) will stretch to 1280 after widening. Wrap the band above it and cap the input. Replace the opening `<label className="relative block">` (L95) with:

```tsx
        <div className="mb-4 hidden md:block">
          <EtalaseBand
            heading="Brand Pilihan"
            tagline="Merek terpercaya yang kami stok — hasil 7 tahun kurasi toko Natalo di Medan."
            breadcrumb={[{ label: "Beranda", href: "/" }, { label: "Brand" }]}
          />
        </div>
        <label className="relative block md:max-w-md">
```

(Only the opening tag changes — the `FiSearch` + `<input>` inside and the closing `</label>` stay as-is.)

- [ ] **Step 4: Make the brand grid responsive and add lit-shelf to tiles**

Replace the grid container (L118):

```tsx
            <div className="grid grid-cols-3 gap-3">
```
with:
```tsx
            <div className="grid grid-cols-3 gap-3 sm:grid-cols-4 lg:grid-cols-6">
```

Replace the tile `<Link>` opening (L120–124):

```tsx
                <Link
                  key={brand.slug}
                  href={brandProductHref(brand)}
                  className="flex h-[112px] min-w-0 flex-col items-center justify-center rounded-[20px] border border-[#E5EAF3] bg-white px-2.5 py-3 shadow-[0_8px_22px_rgba(15,23,42,0.06)] transition active:scale-[0.97] active:opacity-90"
                  aria-label={`Lihat produk brand ${brand.name}`}
                >
```

with:

```tsx
                <Link
                  key={brand.slug}
                  href={brandProductHref(brand)}
                  className="nat-lit-shelf nat-shelf-line group relative flex h-[112px] min-w-0 flex-col items-center justify-center rounded-[20px] border border-[#E5EAF3] bg-white px-2.5 py-3 shadow-[0_8px_22px_rgba(15,23,42,0.06)] transition active:scale-[0.97] active:opacity-90 sm:hover:border-natalo-200"
                  aria-label={`Lihat produk brand ${brand.name}`}
                >
```

- [ ] **Step 5: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no errors.

- [ ] **Step 6: Preview verify**

Load `/brands` at 375px (still 3-col, search full width, no band) and 1280px (band shows, grid is 6-col across 1280, search input capped at `max-w-md`, tiles have pedestal + hover shelf-line). This is the biggest structural change — confirm no cramped/floating layout remains.

- [ ] **Step 7: Commit**

```bash
git add components/brands/BrandDirectoryClient.tsx
git commit -m "feat(brands): widen to 1280 grid, EtalaseBand, lit-shelf tiles"
```

---

## Task 10: Full verification + diff scope

**Files:** none (verification only)

- [ ] **Step 1: Full static checks**

Run: `npx tsc --noEmit`
Expected: no errors.

Run: `npm run lint`
Expected: clean.

Run: `npm test`
Expected: green (includes `tests/etalase.test.ts` — 6 passing; pre-existing suite unchanged).

Run: `npx next build`
Expected: compiles successfully.

- [ ] **Step 2: Preview at all breakpoints**

Ensure a launch entry for this worktree exists in the MAIN repo `.claude/launch.json` (a `cmd.exe /c cd /d <worktree> && npx.cmd --yes --no-install next dev -p <port>` config), start it, and load each of `/products`, `/kategori`, `/brands`, `/search?q=makanan` at **375 / 768 / 1024 / 1280 / 1440 / 1920**. Confirm for each:
  - No horizontal overflow / layout shift.
  - Desktop content is centered within 1280.
  - Product cards show the static warm pedestal; hovering brightens the shelf-line; discounted cards show the rose `-N%` badge.
  - `/kategori` & `/brands` show `EtalaseBand` at `md+`, plain mobile heading below `md`.
  - `/brands` desktop grid is a comfortable 6-col (not the old narrow 3-col cramped in `max-w-2xl`).
  - `/search` lists "Rating tertinggi" in the sort sheet and it re-sorts.
  - Mobile (`375px`) chrome for all four pages is visually unchanged from `main`.

- [ ] **Step 3: Capture before/after screenshots**

Screenshot desktop (1280) `/brands`, `/kategori`, `/products`, and a product card hover for the PR description.

- [ ] **Step 4: Confirm diff scope**

Run: `git diff --name-only main...HEAD`
Expected: only these paths —
```
app/globals.css
app/products/page.tsx
app/search/page.tsx
components/CategoryTabPage.tsx
components/ProductCard.tsx
components/brands/BrandDirectoryClient.tsx
components/products/EtalaseBand.tsx
components/products/FilterChip.tsx
docs/superpowers/plans/2026-07-07-listing-desktop-pr1-etalase-visual.md
docs/superpowers/specs/2026-07-07-listing-desktop-etalase-design.md
lib/etalase.ts
tests/etalase.test.ts
```
Assert there is **no** `app/api/**`, `flutter_app/**`, or `prisma/schema.prisma` in the diff.

- [ ] **Step 5: Final commit (if screenshots or notes were added)**

```bash
git add -A
git commit -m "chore(listing): PR1 verification notes" --allow-empty
```

---

## Self-Review (completed at authoring time)

- **Spec coverage (PR1 slice of §9):** container 1280 on all four pages → Tasks 6,7,8,9; `EtalaseBand` built → Task 4, consumed → Tasks 8,9 (`/products` band deferred to PR2 by design, noted in §0 architecture); lit-shelf card + Flutter card tokens → Task 2; extract `FilterChip` → Task 5; "Rating Tertinggi" on `/search` → Task 6; widen `/brands` & `/kategori` → Tasks 8,9. Warm/neutral pedestal (no aqua) → Task 1. Rating as constant → Task 3.
- **Deferred to PR2 (out of scope here):** `/products` → search stack, `SearchFilters` sidebar on `/products`, page-based hook, active-filter chips on `/products`, `ProductCatalogStickyHeader` md+ suppression, mobile filter/sort bottom-sheets on `/products`, empty/recently-viewed. PR3 (backend carve-outs) remains deferred per owner.
- **Placeholder scan:** none — every code step shows literal code.
- **Type/name consistency:** `etalaseHeading`/`etalaseTagline`/`ETALASE_TRUST`/`NATALO_RATING` defined in Task 3 and consumed with matching signatures in Tasks 8–9; `EtalaseBand` prop names match between Task 4 and Tasks 8–9; `FilterChip` signature identical across Task 5 create + `/search` consume.
