# Beranda Desktop Kohesif — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Next.js homepage feel desktop-native (header, shortcuts, and three swipe-rails) while keeping mobile web intact, the Natalo brand unchanged, and Flutter/business-logic untouched.

**Architecture:** Additive, responsive-branch edits. Desktop changes ride on Tailwind `md:` classes; mobile markup stays. Rails become grids at `md+` via a CSS-only responsive container (same DOM) except "Produk Terlaris", which dual-renders (mobile bespoke ranked rail unchanged + desktop standard-card grid). New reusable bits: a `rankBadge` prop on `ProductCard`/`HomeProductCard`.

**Tech Stack:** Next.js 15 App Router, React, TypeScript, Tailwind v4 (`@theme` in `app/globals.css`), node test runner (`tsx --test`).

## Global Constraints

- Brand unchanged: Natalo blue `#1E5FBF`, Nunito, G1 tokens (`--nat-container` = 1280px).
- Content max-width: `max-w-[var(--nat-container)]` (1280px) for header + sections.
- Do NOT change: any file under `app/api/**`, `flutter_app/**`, payment/voucher/loyalty/cart/checkout logic, auth, DB schema, or any product/category/price/promo data source.
- Do NOT hardcode product/category/price/promo/contact data.
- Mobile web (`< md`) behavior stays; only `md:`/desktop branches change. Exception: Task 6 dual-renders Terlaris (mobile rail kept byte-identical).
- Announcement bar is REMOVED entirely (spec decision).
- Null-safe TypeScript; `npm run lint` stays clean vs the repo's pre-existing baseline (64 pre-existing warnings, unrelated).
- Verification for UI tasks = `npx tsc --noEmit` + `npm run lint` + (where noted) `npm run build` + preview at 375/768/1024/1280/1440/1920. Commit after each task.
- Repo has NO React unit-test setup; only pure helpers get `tsx --test` unit tests.

---

### Task 1: Remove AnnouncementBar + align header width to 1280

**Files:**
- Modify: `components/Header.tsx` (remove import line 10, remove `<AnnouncementBar />` render ~line 255, swap `max-w-6xl` → `max-w-[var(--nat-container)]`)
- Delete: `components/header/AnnouncementBar.tsx` (only after confirming no other importer)

**Interfaces:**
- Produces: header no longer renders an announcement bar; header inner rows use the 1280 container width.

- [ ] **Step 1: Confirm AnnouncementBar has no other importers**

Run: `git grep -n "AnnouncementBar"`
Expected: references only in `components/Header.tsx` and `components/header/AnnouncementBar.tsx`. If any other file imports it, STOP and report.

- [ ] **Step 2: Remove the import and render from Header.tsx**

In `components/Header.tsx`, delete this import line:

```tsx
import { AnnouncementBar } from "@/components/header/AnnouncementBar";
```

And delete the render line (it sits right after `<header …>` opens, before the `{isProductDetail && (` block):

```tsx
      <AnnouncementBar />
```

- [ ] **Step 3: Swap header container widths to the 1280 token**

In `components/Header.tsx`, replace every `max-w-6xl` occurrence with `max-w-[var(--nat-container)]`. There are 4 (the auth-branch inner ~line 208, the product-detail inner ~line 257, and the two branches of the main header inner ~lines 328–329). Use find/replace on the exact substring `max-w-6xl` within this file only.

- [ ] **Step 4: Delete the now-unused component**

Run: `git rm components/header/AnnouncementBar.tsx`

- [ ] **Step 5: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no new errors; no unresolved `AnnouncementBar` reference.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(web): remove header announcement bar, align header to 1280 width"
```

---

### Task 2: Header desktop 1-row — inline search, drop main-row nav, add Wishlist

**Files:**
- Modify: `components/Header.tsx`

**Interfaces:**
- Consumes: existing `HomeSearchBar` (accepts `className`), `NotificationBell`, `CartCount`.
- Produces: desktop main header row = Logo · wide inline search (flex-1) · actions (Wishlist, Bell, Cart, Masuk/avatar). Mobile main row + mobile search unchanged.

- [ ] **Step 1: Remove the desktop text nav from the main row**

In `components/Header.tsx`, delete the `NAV_LINKS` constant near the top:

```tsx
const NAV_LINKS = [
  { href: "/", label: "Beranda" },
  { href: "/products", label: "Produk" },
  { href: "/feed", label: "Feed" },
  { href: "/tentang-kami", label: "Tentang Kami" },
];
```

And delete the `{/* Desktop nav */}` block that maps it (the `<nav className="hidden items-center gap-8 …md:flex"> … {NAV_LINKS.map(…)} … </nav>`). The search bar replaces this center slot on desktop; the nav lives in `DesktopCategoryNav` (Task 3).

- [ ] **Step 2: Add an inline desktop search bar in the main row**

In the main header row (the flex row containing Logo and the right-actions `<div>`), insert this BETWEEN the Logo `<Link>` and the right-actions `<div>` (i.e. where the removed `<nav>` was):

```tsx
{/* Desktop: wide search inline in the main row (native e-commerce pattern). */}
<HomeSearchBar className="hidden min-w-0 flex-1 md:mx-6 md:flex lg:mx-10" />
```

- [ ] **Step 3: Remove the separate desktop search row**

Delete the standalone desktop search line that currently sits after the main row's closing `</div>`:

```tsx
{/* Desktop: search bar selalu tampil di header (semua halaman), center. */}
<HomeSearchBar className="mx-auto hidden w-full max-w-xl px-0 md:flex md:pb-2" />
```

Leave the mobile search line `{isHome && <HomeSearchBar />}` exactly as-is (it is `md:hidden` via its default className and only renders on the homepage).

- [ ] **Step 4: Add the Wishlist action (desktop only)**

In the right-actions `<div className="flex shrink-0 items-center …">`, add this as the FIRST child (before `{showBell && <NotificationBell compact />}`):

```tsx
{/* Wishlist — desktop header action. */}
<Link
  href="/wishlist"
  aria-label="Wishlist"
  className="hidden h-10 w-10 items-center justify-center rounded-full text-gray-700 transition hover:bg-gray-100 md:inline-flex"
>
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className="h-5 w-5">
    <path d="M12 21s-7-4.35-9.5-8.5C1 9 2.5 5.5 6 5.5c2 0 3.2 1.2 4 2.3.8-1.1 2-2.3 4-2.3 3.5 0 5 3.5 3.5 7C19 16.65 12 21 12 21Z" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
</Link>
```

- [ ] **Step 5: Typecheck + lint + build**

Run: `npx tsc --noEmit && npm run lint && npm run build`
Expected: compile succeeds. (A pre-existing unrelated failure may appear only if `app/api/admin/upload/route.ts` regresses — it should NOT, that was fixed on main.)

- [ ] **Step 6: Preview verify header at desktop + mobile**

Start preview (Task 9 covers `.claude/launch.json` setup if absent). Load `/`:
- 1440px: ONE main row = logo + wide centered-ish search (flex-1) + actions (heart, bell/cart, Masuk). No announcement bar. Category nav row below.
- 375px: mobile header unchanged; mobile search still shows on homepage; no inline desktop search, no wishlist icon.

- [ ] **Step 7: Commit**

```bash
git add components/Header.tsx
git commit -m "feat(web): desktop 1-row header with inline search + wishlist action"
```

---

### Task 3: Add Feed to the desktop category nav

**Files:**
- Modify: `components/header/DesktopCategoryNav.tsx`

**Interfaces:**
- Produces: desktop nav row = Kategori ▾ · Brand · Promo · Terlaris · Produk Baru · Feed.

- [ ] **Step 1: Append Feed to STATIC_LINKS**

In `components/header/DesktopCategoryNav.tsx`, change the `STATIC_LINKS` array to add Feed at the end:

```tsx
const STATIC_LINKS = [
  { href: "/brands", label: "Brand" },
  { href: "/products?sort=promo", label: "Promo" },
  { href: "/products?sort=terlaris", label: "Terlaris" },
  { href: "/products?sort=baru", label: "Produk Baru" },
  { href: "/feed", label: "Feed" },
];
```

- [ ] **Step 2: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add components/header/DesktopCategoryNav.tsx
git commit -m "feat(web): add Feed to desktop category nav"
```

---

### Task 4: rankBadge support on ProductCard + HomeProductCard

**Files:**
- Create: `lib/rank-badge.ts`
- Test: `tests/rank-badge.test.ts`
- Modify: `components/ProductCard.tsx`, `components/home/HomeProductCard.tsx`

**Interfaces:**
- Produces:
  - `export function rankBadgeClass(rank: number): string` in `lib/rank-badge.ts` — returns the Tailwind color classes for a rank pill (1 gold, 2 silver, 3 bronze/blue, 4+ neutral).
  - `ProductCard` and `HomeProductCard` accept `rankBadge?: number`. When set and ≥1, render a small numbered pill at the image top-left of the default variant.

- [ ] **Step 1: Write the failing test for rankBadgeClass**

```ts
// tests/rank-badge.test.ts
import test from "node:test";
import assert from "node:assert/strict";
import { rankBadgeClass } from "../lib/rank-badge";

test("top 3 ranks get distinct colors", () => {
  assert.equal(rankBadgeClass(1), "bg-amber-400 text-white");
  assert.equal(rankBadgeClass(2), "bg-zinc-300 text-zinc-700");
  assert.equal(rankBadgeClass(3), "bg-blue-300 text-white");
});

test("rank 4+ uses neutral", () => {
  assert.equal(rankBadgeClass(4), "bg-white/95 text-zinc-700");
  assert.equal(rankBadgeClass(10), "bg-white/95 text-zinc-700");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx tsx --test tests/rank-badge.test.ts`
Expected: FAIL — cannot find module `../lib/rank-badge`.

- [ ] **Step 3: Implement rankBadgeClass**

```ts
// lib/rank-badge.ts
// Warna pill peringkat "Terlaris". 1 emas, 2 perak, 3 perunggu-biru, 4+ netral.
export function rankBadgeClass(rank: number): string {
  if (rank === 1) return "bg-amber-400 text-white";
  if (rank === 2) return "bg-zinc-300 text-zinc-700";
  if (rank === 3) return "bg-blue-300 text-white";
  return "bg-white/95 text-zinc-700";
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx tsx --test tests/rank-badge.test.ts`
Expected: PASS (2 tests).

- [ ] **Step 5: Add rankBadge prop to ProductCard**

In `components/ProductCard.tsx`, add the import near the top:

```tsx
import { rankBadgeClass } from "@/lib/rank-badge";
```

Add to the `Props` type (alongside `badge`, `showCta`, `showRating`):

```tsx
  rankBadge?: number;
```

Add `rankBadge` to the destructured params (default undefined — no default needed).

In the DEFAULT variant's image `<div>` (the one containing the `{memberPrice !== null && (…)}` member pill), add this right after that member pill, so the rank pill sits top-left:

```tsx
{rankBadge != null && rankBadge >= 1 && (
  <span
    className={`absolute left-1.5 top-1.5 z-10 flex h-5 w-5 items-center justify-center rounded-full text-[10px] font-black shadow ${rankBadgeClass(rankBadge)}`}
    aria-label={`Peringkat ${rankBadge}`}
  >
    {rankBadge}
  </span>
)}
```

- [ ] **Step 6: Forward rankBadge through HomeProductCard**

In `components/home/HomeProductCard.tsx`, add `rankBadge?: number` to its props type, accept it in the destructure, and pass it through to `<ProductCard … rankBadge={rankBadge} />`.

- [ ] **Step 7: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no errors.

- [ ] **Step 8: Commit**

```bash
git add lib/rank-badge.ts tests/rank-badge.test.ts components/ProductCard.tsx components/home/HomeProductCard.tsx
git commit -m "feat(web): add rankBadge prop to ProductCard/HomeProductCard with tested color helper"
```

---

### Task 5: Shortcut row → large tiles on desktop

**Files:**
- Modify: `app/page.tsx` (the shortcut `PageContainer` section, the `SHORTCUT_ITEMS.map` block)

**Interfaces:**
- Consumes: existing `SHORTCUT_ITEMS`, `HomeIcon`, `ExternalLink`, `Link`.
- Produces: mobile keeps 3-col circular icons; desktop shows 6 filled tiles (icon + label).

- [ ] **Step 1: Make the grid responsive to a tile layout on desktop**

In `app/page.tsx`, find the shortcut grid wrapper `<div className="grid grid-cols-3 gap-2 sm:grid-cols-6">` and replace with:

```tsx
<div className="grid grid-cols-3 gap-2 sm:grid-cols-6 md:gap-4">
```

- [ ] **Step 2: Give each shortcut item a tile treatment on desktop**

In the same section, both the `content` fragment and the wrapping `Link`/`ExternalLink` need desktop tile classes. Replace the shared `content` fragment with:

```tsx
const content = (
  <>
    <div
      className={`flex h-14 w-14 items-center justify-center rounded-full ${s.bg} ${s.color} shadow-sm md:h-12 md:w-12`}
    >
      <HomeIcon name={s.icon} className="h-7 w-7 md:h-6 md:w-6" />
    </div>
    <span className="text-center text-[11px] font-medium leading-tight text-zinc-700 md:text-sm md:font-semibold">
      {s.label}
    </span>
  </>
);
```

And on BOTH the `ExternalLink` and `Link` wrappers, replace their `className="flex flex-col items-center gap-1.5 rounded-xl p-2 transition active:opacity-90"` with:

```tsx
className="flex flex-col items-center gap-1.5 rounded-xl p-2 transition active:opacity-90 md:flex-row md:justify-center md:gap-3 md:rounded-2xl md:border md:border-[#eef3fb] md:bg-white md:p-4 md:shadow-sm md:hover:-translate-y-0.5 md:hover:shadow-md"
```

This makes each item a bordered white tile with the icon beside the label on desktop, while mobile keeps the stacked circular icon.

- [ ] **Step 3: Typecheck + lint + build**

Run: `npx tsc --noEmit && npm run lint && npm run build`
Expected: compile succeeds.

- [ ] **Step 4: Preview verify shortcuts**

Load `/`: at 1440px the six shortcuts are wide tiles filling the row (icon + label, hover lifts); at 375px they remain small stacked circular icons in 3 columns.

- [ ] **Step 5: Commit**

```bash
git add app/page.tsx
git commit -m "feat(web): desktop shortcut tiles (mobile icons unchanged)"
```

---

### Task 6: Produk Terlaris — desktop ProductCard grid beside mobile rail

**Files:**
- Modify: `app/page.tsx` (the "🏆 Produk Terlaris" section)

**Interfaces:**
- Consumes: `HomeProductCard` with `rankBadge` (Task 4), `ResponsiveGrid`, existing `bestSellers` array.
- Produces: mobile shows the existing bespoke ranked rail (unchanged); desktop shows a standard-card grid with numbered rank badges.

Rationale for dual-render here (not the CSS-only responsive container): the user chose the STANDARD product card for the desktop grid, but mobile keeps its distinct compact ranked rail card. Different card components per breakpoint require dual-render; the duplication is bounded to this one section.

- [ ] **Step 1: Wrap the existing mobile rail so it only shows on mobile**

In `app/page.tsx`, find the Produk Terlaris rail container `<div className="mt-3 flex snap-x snap-mandatory gap-2.5 overflow-x-auto pb-2 …">` (the one iterating `bestSellers` with the bespoke ranked `<Link>` cards). Wrap that entire `<div>…</div>` in:

```tsx
<div className="md:hidden">
  {/* existing bespoke ranked rail — unchanged */}
</div>
```

Leave the rail's inner markup exactly as-is.

- [ ] **Step 2: Add the desktop grid right after it**

Immediately after that `md:hidden` wrapper (still inside the same `PageContainer`/section, after the `SectionHeader`), add:

```tsx
<div className="mt-3 hidden md:block">
  <ResponsiveGrid cols={{ base: 2, sm: 3, lg: 6 }}>
    {bestSellers.map((p, i) => (
      <HomeProductCard key={p.id} product={p} rankBadge={i + 1} priority={i < 6} />
    ))}
  </ResponsiveGrid>
</div>
```

(`ResponsiveGrid` and `HomeProductCard` are already imported in `app/page.tsx`.)

- [ ] **Step 3: Typecheck + lint + build**

Run: `npx tsc --noEmit && npm run lint && npm run build`
Expected: compile succeeds.

- [ ] **Step 4: Preview verify Terlaris**

Load `/`: at 1440px Produk Terlaris is a grid of standard product cards each with a rank number pill (1 gold, 2 silver, 3 blue, 4-6 neutral), no horizontal scroll; at 375px it is the original swipeable ranked rail, unchanged.

- [ ] **Step 5: Commit**

```bash
git add app/page.tsx
git commit -m "feat(web): desktop grid for Produk Terlaris with rank badges (mobile rail kept)"
```

---

### Task 7: Kategori Populer — rail → grid on desktop (CSS-only)

**Files:**
- Modify: `app/page.tsx` (the "Kategori Populer" section)

**Interfaces:**
- Produces: same category cards; mobile swipe rail, desktop grid — one DOM.

- [ ] **Step 1: Make the rail container a grid on desktop**

In `app/page.tsx`, find the Kategori Populer rail `<div className="mt-2 flex snap-x snap-mandatory gap-2.5 overflow-x-auto pb-2 …">` and add desktop grid classes so it becomes:

```tsx
<div className="mt-2 flex snap-x snap-mandatory gap-2.5 overflow-x-auto pb-2 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden md:grid md:grid-cols-3 md:gap-4 md:overflow-visible lg:grid-cols-6">
```

- [ ] **Step 2: Neutralize the mobile card width on desktop**

Each category `<Link>` inside uses a fixed rail width (e.g. `min-w-…`/`w-…`/`shrink-0`/`snap-start`). Append `md:w-auto md:min-w-0 md:max-w-none md:basis-auto` to that `<Link>`'s className so the grid controls sizing on desktop. (Add only the `md:` classes; keep the existing mobile classes.)

- [ ] **Step 3: Typecheck + lint + build**

Run: `npx tsc --noEmit && npm run lint && npm run build`
Expected: compile succeeds.

- [ ] **Step 4: Preview verify Kategori**

Load `/`: 1440px = 6-up category grid, no horizontal scroll; 375px = original swipe rail.

- [ ] **Step 5: Commit**

```bash
git add app/page.tsx
git commit -m "feat(web): Kategori Populer rail becomes grid on desktop"
```

---

### Task 8: Brand Favorit — rail → grid on desktop, cap 12 (CSS-only)

**Files:**
- Modify: `components/home/BrandChoiceSection.tsx`

**Interfaces:**
- Produces: mobile keeps the auto-slide rail (all brands); desktop shows a 6-col grid capped at 12 items. Existing "Lihat semua" → `/brands` kept.

- [ ] **Step 1: Make the scroller a grid on desktop, cap to 12**

In `components/home/BrandChoiceSection.tsx`, find the scroller `<div ref={scrollerRef} … className="scrollbar-hide mt-3 flex snap-x snap-mandatory gap-2.5 overflow-x-auto scroll-smooth px-4 pb-2">` and change its className to add desktop grid + cap-12 (mobile keeps the rail; on desktop items 13+ are hidden):

```tsx
className="scrollbar-hide mt-3 flex snap-x snap-mandatory gap-2.5 overflow-x-auto scroll-smooth px-4 pb-2 md:grid md:grid-cols-4 md:gap-4 md:overflow-visible lg:grid-cols-6 md:[&>*:nth-child(n+13)]:hidden"
```

- [ ] **Step 2: Neutralize the mobile brand-card width on desktop**

The brand `<Link>` uses `min-w-0 shrink-0 basis-[calc((100%_-_1.25rem)/3)] snap-start`. Append `md:basis-auto md:w-auto` to that className so the grid controls width on desktop. Keep existing mobile classes.

- [ ] **Step 3: Typecheck + lint + build**

Run: `npx tsc --noEmit && npm run lint && npm run build`
Expected: compile succeeds.

- [ ] **Step 4: Preview verify Brand**

Load `/`: 1440px = brand grid, at most 12 tiles (2 rows of 6), no horizontal scroll, "Lihat semua" visible; 375px = original auto-sliding rail showing all brands.

- [ ] **Step 5: Commit**

```bash
git add components/home/BrandChoiceSection.tsx
git commit -m "feat(web): Brand Favorit rail becomes 12-item grid on desktop"
```

---

### Task 9: Full verification pass + diff scope check

**Files:**
- Create (if absent): `.claude/launch.json`

- [ ] **Step 1: Ensure a dev-server launch config exists**

If `.claude/launch.json` is absent, create it:

```json
{
  "version": "0.0.1",
  "configurations": [
    { "name": "web", "runtimeExecutable": "npm", "runtimeArgs": ["run", "dev"], "port": 3000 }
  ]
}
```

- [ ] **Step 2: Lint + typecheck + build clean**

Run: `npm run lint && npx tsc --noEmit && npm run build`
Expected: lint 0 errors (pre-existing warnings only); tsc no new errors; build compiles.

- [ ] **Step 3: Run unit tests**

Run: `npx tsx --test tests/rank-badge.test.ts`
Expected: PASS.

- [ ] **Step 4: Preview matrix**

Serve the app; load `/` and check `preview_console_logs` (level error) + measured layout at 375, 768, 1024, 1280, 1440, 1920 px. Confirm: no console errors, no horizontal overflow, no announcement bar, desktop 1-row header, shortcut tiles on desktop, all three rails render as grids on desktop and rails on mobile.

- [ ] **Step 5: Confirm no forbidden files changed**

Run: `git diff --name-only <mergeBase>...HEAD` (mergeBase = `git merge-base main HEAD`).
Expected: only `components/Header.tsx`, `components/header/DesktopCategoryNav.tsx`, `components/header/AnnouncementBar.tsx` (deleted), `components/ProductCard.tsx`, `components/home/HomeProductCard.tsx`, `components/home/BrandChoiceSection.tsx`, `app/page.tsx`, `lib/rank-badge.ts`, `tests/rank-badge.test.ts`, `docs/**`, `.claude/launch.json`. NO `app/api/**`, NO `flutter_app/**`, NO cart/checkout logic.

- [ ] **Step 6: Commit (if launch.json created)**

```bash
git add .claude/launch.json
git commit -m "chore(web): add dev-server launch config for preview"
```

---

## Self-Review (completed by plan author)

**Spec coverage:** Announcement removal + header width → Task 1; header 1-row (inline search, drop nav, wishlist) → Task 2; nav Feed → Task 3; rankBadge → Task 4; shortcut tiles → Task 5; Terlaris grid → Task 6; Kategori grid → Task 7; Brand grid cap-12 → Task 8; verification + scope → Task 9. All spec sections mapped. Mobile polish (spec Bagian D) is folded into each task's "mobile unchanged" checks rather than a separate task — no dedicated restyle beyond what tiles/grids already give; if the reviewer wants explicit mobile spacing tweaks, raise it in Task 9.

**Placeholder scan:** No TBD/TODO. Task 7 Step 2 and Task 8 Step 2 reference "existing mobile classes" on real elements rather than quoting the full line — the implementer appends the named `md:` classes to the located element; exact `md:` values are given.

**Type consistency:** `rankBadge?: number` identical in `lib/rank-badge.ts` signature, `ProductCard` Props, `HomeProductCard` Props, and Task 6 usage (`rankBadge={i + 1}`); `rankBadgeClass(rank: number): string` matches its test.

**Out of scope (future plans):** listing/kategori/search/detail/cart/checkout desktop; SEO; performance.
