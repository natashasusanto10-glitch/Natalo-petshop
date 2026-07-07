# Task 9: Final Review Fixes

## Changes Applied

### Fix 1: Reword stale TrustMarquee comment (line 757)
**Old comment:**
```
{/* Desktop sudah punya AnnouncementBar (header) dengan pesan yang sama
    (gratis ongkir, produk original, WA) — sembunyikan marquee ini di
    md+ supaya tidak duplikat/menumpuk di bawah nav. Mobile tetap
    seperti semula. */}
```

**New comment:**
```
{/* TrustMarquee hanya untuk mobile — di desktop bagian atas sengaja dibuat bersih (langsung header → hero), pesan gratis-ongkir/original/WA tersedia di footer. Jangan un-hide di desktop. */}
```

Rationale: AnnouncementBar was removed, so the original rationale is stale. The new comment accurately reflects the actual design intent: keep top clean on desktop (header → hero immediately), with trust messages deferred to footer.

### Fix 2: Remove priority prop from desktop Terlaris grid (line 954)
**Old:**
```jsx
<HomeProductCard key={p.id} product={p} rankBadge={i + 1} priority={i < 6} />
```

**New:**
```jsx
<HomeProductCard key={p.id} product={p} rankBadge={i + 1} />
```

Rationale: Desktop-only grid is below the fold. The `priority={i < 6}` prop was preloading images on mobile via the dual-render pattern. Removing it prevents unnecessary image preloading in the desktop grid.

## Verification Results

### 1. TypeScript: `npx tsc --noEmit`
```
(no output — clean, 0 errors)
```

### 2. Lint: `npm run lint`
```
0 errors, 45 pre-existing warnings (unrelated to this change)
Key warning from app/page.tsx line 754 was pre-existing
```

### 3. Test: `npx tsx --test tests/rank-badge.test.ts`
```
✔ top 3 ranks get distinct colors (0.6671ms)
✔ rank 4+ uses neutral (0.1037ms)

tests 2
pass 2
fail 0
```

## Summary
- 2 edits applied as specified
- All verification checks pass
- No new errors or regressions
- Ready to commit
