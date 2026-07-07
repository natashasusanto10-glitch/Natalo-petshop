# Task 4 Fix Report: Rank Pill Overlap with Member Pill

## Fix Applied
In `components/ProductCard.tsx` (DEFAULT variant), fixed the collision between the Member pill and rank pill by making the rank pill's vertical position conditional.

### Changed ClassName Expression
**Line 161** — Updated the rank pill's className from:
```
`absolute left-1.5 top-1.5 z-10 flex h-5 w-5 items-center justify-center rounded-full text-[10px] font-black shadow ${rankBadgeClass(rankBadge)}`
```

To:
```
`absolute left-1.5 ${memberPrice !== null ? 'top-9' : 'top-1.5'} z-10 flex h-5 w-5 items-center justify-center rounded-full text-[10px] font-black shadow ${rankBadgeClass(rankBadge)}`
```

### Logic
- When `memberPrice !== null` (Member pill is rendered): rank pill moves down to `top-9` to sit below the Member pill
- When `memberPrice === null` (no Member pill): rank pill stays at `top-1.5` as before
- Keeps `left-1.5` unchanged; all other styles (size, colors, z-10, aria-label, content) unchanged

## Verification Results

### 1. TypeScript Type Checking
```bash
$ npx tsc --noEmit
(no errors)
```
✓ PASS

### 2. Rank Badge Tests
```bash
$ npx tsx --test tests/rank-badge.test.ts
✔ top 3 ranks get distinct colors (0.676ms)
✔ rank 4+ uses neutral (0.1105ms)
ℹ tests 2
ℹ suites 0
ℹ pass 2
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 226.5381
```
✓ PASS — 2/2 tests pass (helper unchanged, confirmed nothing broke)

### 3. ESLint Check
```bash
$ npx eslint components/ProductCard.tsx
(no errors)
```
✓ PASS
