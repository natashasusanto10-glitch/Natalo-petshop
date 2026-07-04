# Web Desktop Redesign — G1 (Fondasi + Homepage + Header/Footer) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable responsive design-system layer (tokens + `components/ui/` primitives + unified ProductCard) and use it to give the Next.js storefront a premium desktop Homepage, Header, and Footer — without touching mobile-web behavior destructively, business logic, or the Flutter app.

**Architecture:** Additive "thin responsive layer" (spec Opsi A). New primitives live in `components/ui/` and new header pieces in `components/header/`; existing components are refactored to consume them per-area. No rewrites, no route/API/logic changes.

**Tech Stack:** Next.js 15 App Router, React, TypeScript, Tailwind CSS v4 (CSS-based `@theme` in `app/globals.css`), `next/image`, node test runner (`tsx --test`).

## Global Constraints

- Content max-width: **1280px** (`--nat-container`). Applied via `PageContainer`.
- Product grid columns: mobile **2** / sm **3** / lg **4** / xl **5** (default; `xl:grid-cols-6` allowed ≥1440px where noted). Never fewer than 2.
- Breakpoints (verbatim): `xs 380`, `sm 640`, `md 768`, `lg 1024`, `xl 1280`, `2xl 1440`.
- Do NOT change: any file under `app/api/**`, `flutter_app/**`, payment/voucher/loyalty/cart/checkout logic, auth, DB schema.
- Do NOT hardcode product/category/price/promo/contact data — read existing sources. WhatsApp from `process.env.NEXT_PUBLIC_WHATSAPP_NUMBER` / `NEXT_PUBLIC_WA_NUMBER`.
- Mobile-web (Safari phone) may be polished but must remain fully usable; verify at 375px every task that touches shared components.
- Announcement bar is static (not dismissible) for G1.
- Null-safe TypeScript; `npm run lint` must stay clean.
- Verification cycle for UI tasks = `npx tsc --noEmit` + `npm run lint` + (where noted) `npm run build` + preview screenshots. Commit after each task.

---

### Task 1: Design tokens in globals.css

**Files:**
- Modify: `app/globals.css` (the `@theme` block region near top, after the existing `--color-natalo-*` block ~line 33)

**Interfaces:**
- Produces (CSS custom properties usable as Tailwind arbitrary values `[var(--x)]` and in raw CSS):
  `--nat-container: 1280px`, `--nat-gutter`, `--nat-section-y`, `--radius-sm|md|lg|xl`, `--shadow-card`, `--shadow-card-hover`, `--shadow-pop`, plus breakpoints `--breakpoint-{sm,md,lg,xl,2xl}`.

- [ ] **Step 1: Add breakpoint + layout + radius + shadow tokens**

In `app/globals.css`, locate the existing `@theme { --breakpoint-xs: 380px; }` block and replace it with:

```css
@theme {
  --breakpoint-xs: 380px;
  --breakpoint-sm: 640px;
  --breakpoint-md: 768px;
  --breakpoint-lg: 1024px;
  --breakpoint-xl: 1280px;
  --breakpoint-2xl: 1440px;
}
```

Then, immediately AFTER the `--color-natalo-950` `@theme` block, add:

```css
/* ── Layout / spacing / radius / elevation scale (design-system G1).
   Dipakai via PageContainer, ResponsiveGrid, SectionHeader, Button, dan
   ProductCard supaya nilai tidak tersebar hardcode. ── */
:root {
  /* Lebar konten desktop maksimum (spec: 1280px). */
  --nat-container: 1280px;
  /* Gutter horizontal responsif (padding kiri/kanan container). */
  --nat-gutter: 1rem;
  /* Jarak vertikal antar section homepage. */
  --nat-section-y: 2.5rem;

  --radius-sm: 10px;
  --radius-md: 14px;
  --radius-lg: 18px;
  --radius-xl: 24px;

  --shadow-card: 0 6px 18px rgba(15, 23, 42, 0.05);
  --shadow-card-hover: 0 12px 28px rgba(15, 23, 42, 0.09);
  --shadow-pop: 0 18px 42px rgba(15, 23, 42, 0.16);
}

@media (min-width: 768px) {
  :root {
    --nat-gutter: 1.5rem;
    --nat-section-y: 3.5rem;
  }
}

@media (min-width: 1280px) {
  :root {
    --nat-gutter: 2rem;
  }
}
```

- [ ] **Step 2: Verify build compiles the CSS**

Run: `npx tsc --noEmit && npm run lint`
Expected: no errors. (Tailwind v4 compiles `@theme` at build; a full `npm run build` runs in Task 13.)

- [ ] **Step 3: Commit**

```bash
git add app/globals.css
git commit -m "feat(web): add layout/radius/shadow/breakpoint design tokens"
```

---

### Task 2: Responsive grid helper (pure, unit-tested)

**Files:**
- Create: `lib/responsive.ts`
- Test: `tests/responsive.test.ts`

**Interfaces:**
- Produces: `export function gridColsClass(opts?: { base?: number; sm?: number; lg?: number; xl?: number; xxl?: number }): string` — returns a Tailwind class string. Defaults: base 2, sm 3, lg 4, xl 5. Only emits a breakpoint class when the value is provided.

- [ ] **Step 1: Write the failing test**

```ts
// tests/responsive.test.ts
import test from "node:test";
import assert from "node:assert/strict";
import { gridColsClass } from "../lib/responsive";

test("default columns 2/3/4/5", () => {
  assert.equal(
    gridColsClass(),
    "grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5",
  );
});

test("respects overrides and xxl", () => {
  assert.equal(
    gridColsClass({ base: 2, sm: 2, lg: 4, xl: 5, xxl: 6 }),
    "grid-cols-2 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6",
  );
});

test("omits unset breakpoints", () => {
  assert.equal(gridColsClass({ base: 3 }), "grid-cols-3");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx tsx --test tests/responsive.test.ts`
Expected: FAIL — cannot find module `../lib/responsive`.

- [ ] **Step 3: Write minimal implementation**

```ts
// lib/responsive.ts
type Cols = { base?: number; sm?: number; lg?: number; xl?: number; xxl?: number };

// Static class list so Tailwind v4's content scanner keeps them (dynamic
// class name interpolation is safe here because every value we emit also
// literally appears in this file).
const COLS: Record<number, { base: string; sm: string; lg: string; xl: string; xxl: string }> = {
  2: { base: "grid-cols-2", sm: "sm:grid-cols-2", lg: "lg:grid-cols-2", xl: "xl:grid-cols-2", xxl: "2xl:grid-cols-2" },
  3: { base: "grid-cols-3", sm: "sm:grid-cols-3", lg: "lg:grid-cols-3", xl: "xl:grid-cols-3", xxl: "2xl:grid-cols-3" },
  4: { base: "grid-cols-4", sm: "sm:grid-cols-4", lg: "lg:grid-cols-4", xl: "xl:grid-cols-4", xxl: "2xl:grid-cols-4" },
  5: { base: "grid-cols-5", sm: "sm:grid-cols-5", lg: "lg:grid-cols-5", xl: "xl:grid-cols-5", xxl: "2xl:grid-cols-5" },
  6: { base: "grid-cols-6", sm: "sm:grid-cols-6", lg: "lg:grid-cols-6", xl: "xl:grid-cols-6", xxl: "2xl:grid-cols-6" },
};

export function gridColsClass(opts: Cols = {}): string {
  const { base = 2, sm = 3, lg = 4, xl = 5, xxl } = opts;
  const parts = [COLS[base].base];
  if (opts.sm !== undefined || sm) parts.push(COLS[sm].sm);
  if (opts.lg !== undefined || lg) parts.push(COLS[lg].lg);
  if (opts.xl !== undefined || xl) parts.push(COLS[xl].xl);
  if (xxl !== undefined) parts.push(COLS[xxl].xxl);
  return parts.join(" ");
}
```

Note: the third test (`{ base: 3 }`) expects ONLY `grid-cols-3`. Adjust logic so defaults apply only when NO opts object keys are given. Replace the function body with:

```ts
export function gridColsClass(opts?: Cols): string {
  if (!opts) {
    return "grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5";
  }
  const parts = [COLS[opts.base ?? 2].base];
  if (opts.sm !== undefined) parts.push(COLS[opts.sm].sm);
  if (opts.lg !== undefined) parts.push(COLS[opts.lg].lg);
  if (opts.xl !== undefined) parts.push(COLS[opts.xl].xl);
  if (opts.xxl !== undefined) parts.push(COLS[opts.xxl].xxl);
  return parts.join(" ");
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx tsx --test tests/responsive.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/responsive.ts tests/responsive.test.ts
git commit -m "feat(web): add gridColsClass responsive helper with tests"
```

---

### Task 3: PageContainer primitive

**Files:**
- Create: `components/ui/PageContainer.tsx`

**Interfaces:**
- Produces: `export function PageContainer({ children, className, as, wide }: { children: ReactNode; className?: string; as?: "div" | "section" | "main"; wide?: boolean }): JSX.Element` — centered wrapper, max-width `--nat-container` (or `max-w-none` when `wide`), horizontal padding from `--nat-gutter`.

- [ ] **Step 1: Write the component**

```tsx
// components/ui/PageContainer.tsx
import type { ReactNode } from "react";

type Props = {
  children: ReactNode;
  className?: string;
  as?: "div" | "section" | "main";
  /** When true, drops the max-width (for full-bleed hero rows). */
  wide?: boolean;
};

export function PageContainer({ children, className = "", as = "div", wide = false }: Props) {
  const Tag = as;
  return (
    <Tag
      className={`mx-auto w-full px-[var(--nat-gutter)] ${wide ? "max-w-none" : "max-w-[var(--nat-container)]"} ${className}`}
    >
      {children}
    </Tag>
  );
}
```

- [ ] **Step 2: Verify typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add components/ui/PageContainer.tsx
git commit -m "feat(web): add PageContainer primitive (1280px content width)"
```

---

### Task 4: ResponsiveGrid primitive

**Files:**
- Create: `components/ui/ResponsiveGrid.tsx`

**Interfaces:**
- Consumes: `gridColsClass` from `lib/responsive.ts`.
- Produces: `export function ResponsiveGrid({ children, cols, className }: { children: ReactNode; cols?: Parameters<typeof gridColsClass>[0]; className?: string }): JSX.Element`.

- [ ] **Step 1: Write the component**

```tsx
// components/ui/ResponsiveGrid.tsx
import type { ReactNode } from "react";
import { gridColsClass } from "@/lib/responsive";

type Props = {
  children: ReactNode;
  cols?: Parameters<typeof gridColsClass>[0];
  className?: string;
};

export function ResponsiveGrid({ children, cols, className = "" }: Props) {
  return (
    <div className={`grid gap-3 sm:gap-4 lg:gap-5 ${gridColsClass(cols)} ${className}`}>
      {children}
    </div>
  );
}
```

- [ ] **Step 2: Verify typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add components/ui/ResponsiveGrid.tsx
git commit -m "feat(web): add ResponsiveGrid primitive"
```

---

### Task 5: SectionHeader + Button primitives

**Files:**
- Create: `components/ui/SectionHeader.tsx`
- Create: `components/ui/Button.tsx`

**Interfaces:**
- Produces:
  - `export function SectionHeader({ title, subtitle, href, ctaLabel }: { title: string; subtitle?: string; href?: string; ctaLabel?: string }): JSX.Element` — `ctaLabel` defaults to "Lihat Semua"; the CTA link renders only when `href` is set.
  - `export function Button(props)` — polymorphic: renders `<Link>` when `href` given, else `<button>`. Props: `variant?: "primary" | "secondary" | "ghost"` (default primary), `size?: "sm" | "md"` (default md), `href?`, `className?`, standard button/anchor children + onClick.

- [ ] **Step 1: Write SectionHeader**

```tsx
// components/ui/SectionHeader.tsx
import Link from "next/link";

type Props = {
  title: string;
  subtitle?: string;
  href?: string;
  ctaLabel?: string;
};

export function SectionHeader({ title, subtitle, href, ctaLabel = "Lihat Semua" }: Props) {
  return (
    <div className="mb-4 flex items-end justify-between gap-4">
      <div className="min-w-0">
        <h2 className="text-lg font-extrabold tracking-tight text-zinc-900 sm:text-xl md:text-2xl">
          {title}
        </h2>
        {subtitle && (
          <p className="mt-0.5 truncate text-xs text-zinc-500 sm:text-sm">{subtitle}</p>
        )}
      </div>
      {href && (
        <Link
          href={href}
          className="shrink-0 text-sm font-bold text-natalo-500 transition hover:text-natalo-700"
        >
          {ctaLabel} →
        </Link>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Write Button**

```tsx
// components/ui/Button.tsx
import Link from "next/link";
import type { ReactNode, MouseEventHandler } from "react";

type Variant = "primary" | "secondary" | "ghost";
type Size = "sm" | "md";

const VARIANTS: Record<Variant, string> = {
  primary: "bg-natalo-500 text-white hover:bg-natalo-600 active:scale-[0.98]",
  secondary: "bg-natalo-50 text-natalo-700 hover:bg-natalo-100 active:scale-[0.98]",
  ghost: "bg-transparent text-natalo-600 hover:bg-natalo-50",
};

const SIZES: Record<Size, string> = {
  sm: "h-9 px-3 text-sm",
  md: "h-11 px-5 text-sm",
};

type Props = {
  children: ReactNode;
  variant?: Variant;
  size?: Size;
  href?: string;
  type?: "button" | "submit";
  className?: string;
  onClick?: MouseEventHandler<HTMLButtonElement | HTMLAnchorElement>;
  disabled?: boolean;
  "aria-label"?: string;
};

export function Button({
  children,
  variant = "primary",
  size = "md",
  href,
  type = "button",
  className = "",
  onClick,
  disabled = false,
  ...rest
}: Props) {
  const cls = `inline-flex items-center justify-center gap-1.5 rounded-full font-bold transition disabled:cursor-not-allowed disabled:opacity-50 ${VARIANTS[variant]} ${SIZES[size]} ${className}`;
  if (href && !disabled) {
    return (
      <Link href={href} className={cls} onClick={onClick as MouseEventHandler<HTMLAnchorElement>} {...rest}>
        {children}
      </Link>
    );
  }
  return (
    <button type={type} className={cls} onClick={onClick as MouseEventHandler<HTMLButtonElement>} disabled={disabled} {...rest}>
      {children}
    </button>
  );
}
```

- [ ] **Step 3: Verify typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add components/ui/SectionHeader.tsx components/ui/Button.tsx
git commit -m "feat(web): add SectionHeader and Button primitives"
```

---

### Task 6: Unify ProductCard (fold HomeProductCard features in)

**Files:**
- Modify: `components/ProductCard.tsx`
- Test: `tests/product-card-discount.test.ts`

**Interfaces:**
- Consumes: `StoreProduct`, `formatRupiah`, `IMAGE_BLUR_GRAY`, `ProductCardCta` (existing).
- Produces: extended `ProductCard` props — adds `badge?: "Baru" | "Original" | "Promo" | "Terlaris"`, `showCta?: boolean` (default `true`), `showRating?: boolean` (default `false`). Existing `variant`/`priority`/`isFavorited` unchanged. Also export a pure helper `export function computeDiscountPercent(price: number, displayPrice: number): number` for the unit test.

Rationale: `HomeProductCard` is a single-Link card with a `badge` + rating line and NO cta. Fold those as opt-in props on `ProductCard` so home usages set `showCta={false}` `showRating badge={...}`, everything else keeps CTA.

- [ ] **Step 1: Write the failing test for the extracted helper**

```ts
// tests/product-card-discount.test.ts
import test from "node:test";
import assert from "node:assert/strict";
import { computeDiscountPercent } from "../components/ProductCard";

test("normal markdown rounds up, min 1", () => {
  assert.equal(computeDiscountPercent(100000, 90000), 10);
  assert.equal(computeDiscountPercent(100000, 99900), 1); // <1% floors to 1
});

test("no markdown or zero price yields 0", () => {
  assert.equal(computeDiscountPercent(100000, 100000), 0);
  assert.equal(computeDiscountPercent(0, 0), 0);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx tsx --test tests/product-card-discount.test.ts`
Expected: FAIL — `computeDiscountPercent` not exported.

- [ ] **Step 3: Extract helper + add opt-in props**

At the top of `components/ProductCard.tsx` (after imports), add:

```tsx
// Exported for unit testing + reuse. Guard price=0 → hindari Infinity%.
export function computeDiscountPercent(price: number, displayPrice: number): number {
  if (price <= 0 || displayPrice >= price) return 0;
  return Math.max(1, Math.round(((price - displayPrice) / price) * 100));
}
```

Update the `Props` type:

```tsx
type Props = {
  product: StoreProduct;
  priority?: boolean;
  isFavorited?: boolean;
  variant?: "default" | "compact";
  badge?: "Baru" | "Original" | "Promo" | "Terlaris";
  showCta?: boolean;
  showRating?: boolean;
};
```

Update the destructure to include `badge`, `showCta = true`, `showRating = false`, and replace the local `discountPercent` calc with `computeDiscountPercent(product.price, displayPrice)`.

In the **default** variant return block:
1. Add the badge to the image area — inside the image `<div>`, after the `memberPrice` badge, add:

```tsx
{badge && (
  <span className="absolute right-1.5 top-1.5 rounded-full border border-white/80 bg-white/95 px-2 py-0.5 text-[10px] font-black text-natalo-500 shadow-[var(--shadow-card)]">
    {badge}
  </span>
)}
```

2. Swap hardcoded radius/shadow to tokens on the outer wrapper:

```tsx
<div className="group relative flex min-w-0 flex-col overflow-hidden rounded-[var(--radius-lg)] border border-[#e8eef7] bg-white p-2.5 shadow-[var(--shadow-card)] transition active:scale-[0.99] active:opacity-90 sm:p-3 sm:hover:-translate-y-0.5 sm:hover:shadow-[var(--shadow-card-hover)]">
```

3. After the price block (before closing the info `<div>`), add the optional rating line:

```tsx
{showRating && (product.avgRating > 0 || product.reviewCount > 0) && (
  <p className="mt-1.5 truncate text-[11px] font-semibold text-zinc-500">
    {product.avgRating > 0 ? `Rating ${product.avgRating.toFixed(1)}` : "Baru"}
    {product.reviewCount > 0 ? ` · ${product.reviewCount} ulasan` : ""}
  </p>
)}
```

4. Wrap the CTA block so it can be hidden:

```tsx
{showCta && (
  <div className="mt-3">
    <ProductCardCta
      productId={product.id}
      slug={product.slug}
      name={product.name}
      price={displayPrice}
      imageUrl={product.imageUrl}
      weightGram={product.weightGram}
      stock={product.stock}
      hasVariants={product.hasVariants}
    />
  </div>
)}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx tsx --test tests/product-card-discount.test.ts`
Expected: PASS (2 tests).

- [ ] **Step 5: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add components/ProductCard.tsx tests/product-card-discount.test.ts
git commit -m "feat(web): unify ProductCard with badge/showCta/showRating opts"
```

---

### Task 7: Migrate home consumers off HomeProductCard

**Files:**
- Modify: `components/home/HomeProductCard.tsx` (turn into thin re-export wrapper to avoid touching every call site at once)
- Grep: all importers of `HomeProductCard` / `HomeProductSkeleton`

**Interfaces:**
- Consumes: `ProductCard` (Task 6), existing `ProductGridSkeleton`/`HomeProductSkeleton`.
- Produces: `HomeProductCard` keeps its old signature `{ product, badge?, priority? }` but renders `ProductCard` with `showCta={false} showRating badge={badge}`. `HomeProductSkeleton` unchanged.

- [ ] **Step 1: Find all importers**

Run: `git grep -n "HomeProductCard\|HomeProductSkeleton"`
Expected: note every file; do not edit them (the wrapper keeps them working).

- [ ] **Step 2: Rewrite HomeProductCard as a wrapper**

Replace the `HomeProductCard` function (keep `HomeProductSkeleton` as-is at the bottom of the file) with:

```tsx
import type { StoreProduct } from "@/lib/products";
import { ProductCard } from "@/components/ProductCard";

type HomeProductCardProps = {
  product: StoreProduct;
  badge?: "Baru" | "Original" | "Promo" | "Terlaris";
  priority?: boolean;
};

export function HomeProductCard({ product, badge, priority = false }: HomeProductCardProps) {
  return (
    <ProductCard
      product={product}
      badge={badge}
      priority={priority}
      showCta={false}
      showRating
    />
  );
}
```

(Delete the now-unused `Image`, `Link`, `formatRupiah`, `IMAGE_BLUR_GRAY` imports if the linter flags them; keep whatever `HomeProductSkeleton` still needs.)

- [ ] **Step 3: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no errors, no unused-import warnings.

- [ ] **Step 4: Build to confirm nothing broke on home**

Run: `npm run build`
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add components/home/HomeProductCard.tsx
git commit -m "refactor(web): HomeProductCard delegates to unified ProductCard"
```

---

### Task 8: AnnouncementBar component

**Files:**
- Create: `components/header/AnnouncementBar.tsx`

**Interfaces:**
- Produces: `export function AnnouncementBar(): JSX.Element | null` — thin bar, `md+` only (`hidden md:block`), reads WhatsApp env for the WA item. Static content.

- [ ] **Step 1: Write the component**

```tsx
// components/header/AnnouncementBar.tsx
import Link from "next/link";

export function AnnouncementBar() {
  const wa = process.env.NEXT_PUBLIC_WHATSAPP_NUMBER || process.env.NEXT_PUBLIC_WA_NUMBER || "";
  const waHref = wa ? `https://wa.me/${wa.replace("+", "")}` : null;

  return (
    <div className="hidden bg-natalo-500 text-white md:block">
      <div className="mx-auto flex max-w-[var(--nat-container)] items-center justify-between gap-4 px-[var(--nat-gutter)] py-1.5 text-xs font-semibold">
        <div className="flex items-center gap-5">
          <span>🚚 Gratis ongkir area Medan</span>
          <span className="opacity-40">•</span>
          <span>✅ 100% Produk Original</span>
        </div>
        {waHref && (
          <Link href={waHref} className="inline-flex items-center gap-1 transition hover:opacity-80">
            💬 Chat admin via WhatsApp
          </Link>
        )}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add components/header/AnnouncementBar.tsx
git commit -m "feat(web): add desktop AnnouncementBar"
```

---

### Task 9: DesktopCategoryNav component

**Files:**
- Create: `components/header/DesktopCategoryNav.tsx`

**Interfaces:**
- Consumes: `readCategoryCache`, `writeCategoryCache`, `isCategoryCacheFresh`, `CachedCategorySummary` from `lib/client-performance.ts`; `GET /api/categories` returning `{ categories: CachedCategorySummary[] }`.
- Produces: `export function DesktopCategoryNav(): JSX.Element` — client component, `md+` nav row: a "Kategori" trigger opening a lightweight dropdown of categories, followed by static links (Brand, Promo, Terlaris, Produk Baru).

- [ ] **Step 1: Confirm the category link param**

Run: `git grep -n "searchParams" app/products/page.tsx | head` and open `app/products/page.tsx` to confirm the query key for category filtering (e.g. `category`, `c`, or `kategori`). Use that exact key in Step 2's `categoryHref`. If products page does not filter by category, link categories to `/kategori` instead. Record the chosen href pattern.

- [ ] **Step 2: Write the component**

```tsx
// components/header/DesktopCategoryNav.tsx
"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import {
  readCategoryCache,
  writeCategoryCache,
  isCategoryCacheFresh,
  type CachedCategorySummary,
} from "@/lib/client-performance";

// NOTE: replace `categoryHref` body with the confirmed pattern from Step 1.
function categoryHref(slug: string) {
  return `/products?category=${encodeURIComponent(slug)}`;
}

const STATIC_LINKS = [
  { href: "/brands", label: "Brand" },
  { href: "/products?sort=promo", label: "Promo" },
  { href: "/products?sort=terlaris", label: "Terlaris" },
  { href: "/products?sort=baru", label: "Produk Baru" },
];

export function DesktopCategoryNav() {
  const [cats, setCats] = useState<CachedCategorySummary[]>([]);
  const [open, setOpen] = useState(false);
  const closeTimer = useRef<number | null>(null);

  useEffect(() => {
    const cached = readCategoryCache();
    if (cached) setCats(cached.categories);
    if (!isCategoryCacheFresh(cached)) {
      fetch("/api/categories", { cache: "force-cache" })
        .then((r) => (r.ok ? r.json() : null))
        .then((p) => {
          if (Array.isArray(p?.categories)) {
            setCats(p.categories);
            writeCategoryCache(p.categories);
          }
        })
        .catch(() => {});
    }
  }, []);

  function openNow() {
    if (closeTimer.current) window.clearTimeout(closeTimer.current);
    setOpen(true);
  }
  function closeSoon() {
    closeTimer.current = window.setTimeout(() => setOpen(false), 120);
  }

  return (
    <nav className="hidden border-t border-zinc-100 bg-white md:block">
      <div className="mx-auto flex max-w-[var(--nat-container)] items-center gap-6 px-[var(--nat-gutter)] py-2.5 text-sm font-semibold text-zinc-700">
        <div className="relative" onMouseEnter={openNow} onMouseLeave={closeSoon}>
          <button
            type="button"
            className="inline-flex items-center gap-1.5 rounded-full px-2 py-1 transition hover:text-natalo-600"
            aria-expanded={open}
            aria-haspopup="true"
          >
            <span aria-hidden>☰</span> Kategori
          </button>
          {open && cats.length > 0 && (
            <div className="absolute left-0 top-full z-50 mt-1 grid w-[520px] grid-cols-2 gap-1 rounded-[var(--radius-lg)] border border-zinc-100 bg-white p-3 shadow-[var(--shadow-pop)]">
              {cats.slice(0, 12).map((c) => (
                <Link
                  key={c.id}
                  href={categoryHref(c.slug)}
                  className="truncate rounded-lg px-3 py-2 text-zinc-700 transition hover:bg-natalo-50 hover:text-natalo-700"
                >
                  {c.name}
                </Link>
              ))}
            </div>
          )}
        </div>
        {STATIC_LINKS.map((l) => (
          <Link key={l.href} href={l.href} className="transition hover:text-natalo-600">
            {l.label}
          </Link>
        ))}
      </div>
    </nav>
  );
}
```

- [ ] **Step 3: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add components/header/DesktopCategoryNav.tsx
git commit -m "feat(web): add data-driven DesktopCategoryNav with dropdown"
```

---

### Task 10: Wire Header desktop (announcement + persistent search + nav)

**Files:**
- Modify: `components/Header.tsx`

**Interfaces:**
- Consumes: `AnnouncementBar` (Task 8), `DesktopCategoryNav` (Task 9), existing `HomeSearchBar` (accepts `className`).

- [ ] **Step 1: Import the new pieces**

At the top of `components/Header.tsx` add:

```tsx
import { AnnouncementBar } from "@/components/header/AnnouncementBar";
import { DesktopCategoryNav } from "@/components/header/DesktopCategoryNav";
```

- [ ] **Step 2: Render announcement bar + nav on the main (non-auth, non-hidden) branch**

In the final `return (<header …>…</header>)` (the main branch, NOT the early `return null` or the auth branch), wrap so the desktop chrome shows. Immediately inside `<header …>`, before the existing content wrapper `<div className={isProductDetail ? "hidden md:block" : ""}>`, add:

```tsx
<AnnouncementBar />
```

And immediately AFTER that same content wrapper `<div>...</div>` closes (still inside `<header>`), add the nav row:

```tsx
{!isProductDetail && <DesktopCategoryNav />}
```

- [ ] **Step 3: Make the big search bar persistent on desktop**

Find the line `{isHome && <HomeSearchBar />}` near the end of the header inner content. Replace it with:

```tsx
{isHome && <HomeSearchBar />}
{/* Desktop: search bar selalu tampil di header (semua halaman), center. */}
<HomeSearchBar className="mx-auto hidden w-full max-w-xl px-0 md:flex md:pb-2" />
```

Note: `HomeSearchBar`'s default className is `mobile-search-wrapper md:hidden`; passing an explicit `md:flex` className makes a desktop instance. The mobile instance (`isHome && <HomeSearchBar />`) keeps its default and stays `md:hidden`.

- [ ] **Step 4: Typecheck + lint + build**

Run: `npx tsc --noEmit && npm run lint && npm run build`
Expected: all succeed.

- [ ] **Step 5: Preview verify header at desktop + mobile**

Start preview (Task 13 sets up `.claude/launch.json` if absent). Load `/`:
- At 1440px: announcement bar visible, logo + centered search + right actions, category nav row with working "Kategori" hover dropdown.
- At 375px: announcement bar HIDDEN, mobile header unchanged, no desktop nav.

Capture: `preview_screenshot` at 1440 and 375.

- [ ] **Step 6: Commit**

```bash
git add components/Header.tsx
git commit -m "feat(web): desktop 3-tier header (announcement + search + category nav)"
```

---

### Task 11: Homepage — containers, ResponsiveGrid, SectionHeader

**Files:**
- Modify: `app/page.tsx`

**Interfaces:**
- Consumes: `PageContainer`, `ResponsiveGrid`, `SectionHeader` (Tasks 3–5).

- [ ] **Step 1: Import primitives**

Add to `app/page.tsx` imports:

```tsx
import { PageContainer } from "@/components/ui/PageContainer";
import { ResponsiveGrid } from "@/components/ui/ResponsiveGrid";
import { SectionHeader } from "@/components/ui/SectionHeader";
```

- [ ] **Step 2: Wrap each content section in PageContainer**

For every top-level homepage section currently relying on `px-4` full-bleed (shortcuts, promo/voucher, terlaris rail, brand, kategori, rekomendasi, trust), wrap its outer element with `<PageContainer as="section" className="py-[calc(var(--nat-section-y)/2)]"> … </PageContainer>`. The hero row stays full-bleed: wrap with `<PageContainer wide>` only if it needs horizontal padding, otherwise leave as-is. Do NOT change data fetching or props.

- [ ] **Step 3: Replace fixed grids with ResponsiveGrid**

Find the "Rekomendasi" grid (currently `grid grid-cols-2 …`) and replace the wrapping `<div className="grid grid-cols-2 …">` with `<ResponsiveGrid>` (default cols 2/3/4/5). For a denser wide layout add `cols={{ base: 2, sm: 3, lg: 4, xl: 5, xxl: 6 }}`. For the "Flash Sale" `grid grid-cols-3` block, replace with `<ResponsiveGrid cols={{ base: 2, sm: 3, lg: 5, xl: 6 }}>` (flash sale is denser). Keep the same children (product cards).

- [ ] **Step 4: Standardize section titles with SectionHeader**

For each section that has an ad-hoc title + "Lihat Semua" link, replace that header markup with `<SectionHeader title="…" href="…" />` using the EXISTING title text and link target (copy them verbatim — do not invent new copy or routes).

- [ ] **Step 5: Typecheck + lint + build**

Run: `npx tsc --noEmit && npm run lint && npm run build`
Expected: all succeed.

- [ ] **Step 6: Preview verify homepage across viewports**

Load `/` and screenshot at 375 / 768 / 1024 / 1280 / 1440 / 1920. Confirm: content centered ≤1280px, no full-bleed stretch, product grid 4–5 cols on desktop, no overflow/layout shift, mobile still 2 cols.

- [ ] **Step 7: Commit**

```bash
git add app/page.tsx
git commit -m "feat(web): homepage desktop layout (container + responsive grid + section headers)"
```

---

### Task 12: Footer + mobile-web polish (token pass)

**Files:**
- Modify: `components/Footer.tsx`

**Interfaces:**
- Consumes: layout/radius/shadow tokens (Task 1).

- [ ] **Step 1: Align Footer container width + spacing to tokens**

In `components/Footer.tsx`, change the inner wrapper `max-w-6xl` to `max-w-[var(--nat-container)]` and its horizontal padding to `px-[var(--nat-gutter)]` so the footer lines up with the rest of the site. Do not remove any existing footer link/section.

- [ ] **Step 2: Typecheck + lint**

Run: `npx tsc --noEmit && npm run lint`
Expected: no errors.

- [ ] **Step 3: Preview verify footer alignment**

Load `/`, scroll to footer at 1440px and 375px. Confirm footer left/right edges align with header/content and nothing wraps awkwardly on mobile.

- [ ] **Step 4: Commit**

```bash
git add components/Footer.tsx
git commit -m "polish(web): align footer width/spacing to design tokens"
```

---

### Task 13: Full verification pass + before/after screenshots

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

- [ ] **Step 2: Lint + build clean**

Run: `npm run lint && npm run build`
Expected: both succeed with no errors.

- [ ] **Step 3: Run the unit tests**

Run: `npx tsx --test tests/responsive.test.ts tests/product-card-discount.test.ts`
Expected: all PASS.

- [ ] **Step 4: Preview matrix**

Start the `web` server via preview_start. For `/` (homepage), capture `preview_screenshot` and check `preview_console_logs` (level error) at each of: 375, 768, 1024, 1280, 1440, 1920 px. Confirm: no console errors, no horizontal scroll, content centered, grid columns scale, header desktop chrome at ≥768 and mobile chrome at <768.

- [ ] **Step 5: Confirm no forbidden files changed**

Run: `git diff --name-only main...HEAD`
Expected: only files under `app/globals.css`, `app/page.tsx`, `components/ui/**`, `components/header/**`, `components/Header.tsx`, `components/Footer.tsx`, `components/ProductCard.tsx`, `components/home/HomeProductCard.tsx`, `lib/responsive.ts`, `tests/**`, `docs/**`, `.claude/launch.json`. NO `app/api/**`, NO `flutter_app/**`, NO cart/checkout logic files.

- [ ] **Step 6: Final commit (if launch.json created)**

```bash
git add .claude/launch.json
git commit -m "chore(web): add dev-server launch config for preview"
```

---

## Self-Review (completed by plan author)

**Spec coverage:** Bagian 1 → Tasks 1–5; Bagian 2 (header) → Tasks 8–10; Bagian 3 (homepage) → Task 11; Bagian 4 (ProductCard) → Tasks 6–7; Bagian 5 (footer + mobile polish) → Task 12; verification → Task 13. All G1 spec sections mapped.

**Placeholder scan:** One deliberate confirm step (Task 9 Step 1) resolves the category query-param against the real `app/products/page.tsx` before coding the href — this is a verification instruction, not an unfilled placeholder; all code blocks are complete.

**Type consistency:** `gridColsClass` signature reused via `Parameters<typeof gridColsClass>[0]` in ResponsiveGrid; `computeDiscountPercent(price, displayPrice)` signature identical in Task 6 impl and Task 6 test; `CachedCategorySummary` used exactly as exported from `lib/client-performance.ts`.

**Out of scope (own future plans):** G2 listing/discovery, G3 product detail, G4 cart/checkout, G5 account/support — each gets its own plan after G1 lands.
