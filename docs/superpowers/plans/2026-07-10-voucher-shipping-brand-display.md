# Voucher Shipping-Brand Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make brand-locked free-shipping vouchers clearly show they are brand-exclusive on the cart picker + checkout sheet, clarify the store-promo card, give brand-scoped vouchers a brand-named disabled reason, and stop brand vouchers from auto-applying silently.

**Architecture:** Pure Flutter render changes on two surfaces (the data — `brandName`/`isBrandExclusive` — is already on the wire from both backend endpoints) plus a 2-file backend string change to the scope-mismatch reason. No schema, no discount-math, no availability-logic changes. Reference behavior already exists: the Voucher Member page renders an amber "Brand Eksklusif" pill for any `isBrandExclusive` voucher regardless of type.

**Tech Stack:** Flutter/Dart (customer app), Next.js 16 API routes + `tsx --test` (backend), Prisma/Postgres (unchanged).

## Global Constraints

- **Workspace:** all edits + commands run in the isolated worktree `C:\Users\USER\Desktop\natalopetshopflutter\.claude\worktrees\voucher-brand-display` (branch `claude/voucher-brand-filtering-bug-7f8bbe`). Do NOT use the main checkout — it is shared with another session that switches branches.
- **Amber pill tokens (exact hex, from member page / approved mockup):** background `#FEF0DC`, border `#FCD9A0`, text/icon `#B85C00`.
- **Pill copy:** `Brand Eksklusif` (title case, subtle — user prefers soft tint chips over loud ALL-CAPS). Existing member-page pill keeps its own `BRAND EKSKLUSIF` wording — do not touch it.
- **Synthetic store-promo card:** KEEP the truck icon (`Icons.local_shipping_outlined`) and the green `'Ongkir'` badge — per user it must still read as *ongkos kirim*. Only the subtitle changes.
- **Brand-named reason fires only when `brandName` resolves** (voucher has `eligibleBrandIds` AND the brand id is in `brandNamesById`); otherwise keep the generic string. This preserves existing tests that pass no brand map.
- **No new widgets** — inline the pill (matches the codebase's existing inline pattern in `member_vouchers_screen.dart`).
- **Do NOT change** the cart product-voucher card appearance, `voucher_promo.dart` (product-detail rail — separate surface, out of scope), discount math, or the DB.
- **`productIds` is already sent** from every cart/voucher fetch caller (`member_service.dart:335-338,351`; cart sync passes `_selectedItems`) — Part 4's gate is already armed. This plan only adds the auto-apply guard; no productIds code change.
- All user-facing strings are Indonesian.

---

### Task 1: Cart — brand pill on shipping voucher cards + synthetic card clarity

**Files:**
- Modify: `flutter_app/lib/screens/cart_screen.dart` (`_CartVoucherCard` class ~3164-3311; synthetic card 2962-2977; shipping loops 2978-2998 and 3067-3088)

**Interfaces:**
- Consumes: `MemberVoucher.isBrandExclusive` (existing getter, `member_profile.dart:282`).
- Produces: `_CartVoucherCard` gains an optional `bool brandExclusive` param (default `false`) that renders an amber "Brand Eksklusif" pill next to the primary badge.

- [ ] **Step 1: Add the `brandExclusive` field to `_CartVoucherCard`**

In `flutter_app/lib/screens/cart_screen.dart`, find the field list + constructor (around 3164-3189) and add `brandExclusive`. Replace:

```dart
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _CartVoucherCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.icon,
    required this.accent,
    required this.background,
    required this.border,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.trailing,
  });
```

with:

```dart
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;
  final bool brandExclusive;

  const _CartVoucherCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.icon,
    required this.accent,
    required this.background,
    required this.border,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.trailing,
    this.brandExclusive = false,
  });
```

- [ ] **Step 2: Render the amber pill in the badge row**

Find the badge `Row` inside `_CartVoucherCard.build` (around 3225-3256). Insert the brand pill right after the badge `Container` and before the `if (selected)` block. Replace:

```dart
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: effectiveAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (selected) ...[
```

with:

```dart
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: effectiveAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (brandExclusive) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF0DC),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFFCD9A0)),
                          ),
                          child: const Text(
                            'Brand Eksklusif',
                            style: TextStyle(
                              color: Color(0xFFB85C00),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                      if (selected) ...[
```

- [ ] **Step 3: Pass `brandExclusive` from the available shipping loop**

Find the available shipping-voucher loop (around 2978-2998). Replace:

```dart
                    for (final voucher in availableShippingVouchers) ...[
                      _CartVoucherCard(
                        title: voucher.title,
                        subtitle: _cartShippingVoucherSubtitle(
                          voucher,
                          widget.shippingDiscount,
                        ),
                        badge: 'Ongkir',
```

with:

```dart
                    for (final voucher in availableShippingVouchers) ...[
                      _CartVoucherCard(
                        title: voucher.title,
                        subtitle: _cartShippingVoucherSubtitle(
                          voucher,
                          widget.shippingDiscount,
                        ),
                        badge: 'Ongkir',
                        brandExclusive: voucher.isBrandExclusive,
```

- [ ] **Step 4: Pass `brandExclusive` from the unavailable shipping loop**

Find the unavailable shipping-voucher loop (around 3067-3088). Replace:

```dart
                      for (final voucher in unavailableShippingVouchers) ...[
                        _CartVoucherCard(
                          title: voucher.title,
                          subtitle: voucher.disabledReason ??
                              _cartShippingVoucherSubtitle(
                                voucher,
                                widget.shippingDiscount,
                              ),
                          badge: 'Ongkir',
```

with:

```dart
                      for (final voucher in unavailableShippingVouchers) ...[
                        _CartVoucherCard(
                          title: voucher.title,
                          subtitle: voucher.disabledReason ??
                              _cartShippingVoucherSubtitle(
                                voucher,
                                widget.shippingDiscount,
                              ),
                          badge: 'Ongkir',
                          brandExclusive: voucher.isBrandExclusive,
```

- [ ] **Step 5: Clarify the synthetic store-promo card subtitle**

Find the synthetic shipping card (around 2962-2977). Replace only the subtitle. Replace:

```dart
                      _CartVoucherCard(
                        title: 'Gratis Ongkir',
                        subtitle:
                            'Potongan ongkir ${formatRupiah(widget.shippingDiscount)}',
                        badge: 'Ongkir',
                        icon: Icons.local_shipping_outlined,
```

with:

```dart
                      _CartVoucherCard(
                        title: 'Gratis Ongkir',
                        subtitle:
                            'Potongan ongkir ${formatRupiah(widget.shippingDiscount)} · min. belanja Rp250rb',
                        badge: 'Ongkir',
                        icon: Icons.local_shipping_outlined,
```

(Icon and badge intentionally unchanged. The synthetic card passes no `brandExclusive`, so it defaults to `false` — no pill.)

- [ ] **Step 6: Analyze**

Run: `cd flutter_app && flutter analyze lib/screens/cart_screen.dart`
Expected: no new errors or warnings.

- [ ] **Step 7: Manual check (narrow-screen overflow)**

There is no widget-test harness for this screen (and widget tests risk the known shimmer-hang). Visually confirm on an emulator at 360dp width that the badge row `[Ongkir] [Brand Eksklusif]` (plus `Terpilih` when selected) does not overflow. If it does, wrap the badge row children in a `Wrap(spacing: 6, runSpacing: 4, ...)` instead of `Row`. (Deferred unless observed — pills are short.)

- [ ] **Step 8: Commit**

```bash
git add flutter_app/lib/screens/cart_screen.dart
git commit -m "feat(voucher): pill Brand Eksklusif di kartu ongkir keranjang + perjelas promo toko

Kartu voucher gratis-ongkir yang dikunci brand sekarang tampil badge
amber 'Brand Eksklusif' di samping 'Ongkir' (dual-badge), paritas dgn
halaman Voucher Member. brandName sudah di wire -- render gap murni.
Kartu sintetis promo toko: subtitle tambah 'min. belanja Rp250rb'
(icon truk + badge Ongkir dipertahankan, tetap sinyal ongkos kirim)."
```

---

### Task 2: Checkout — brand pill on voucher tile + de-dup type label

**Files:**
- Modify: `flutter_app/lib/screens/checkout_screen.dart` (`_voucherTypeLabel` 4398-4412; `_VoucherDetailTile` 4895-5013)

**Interfaces:**
- Consumes: `MemberVoucher.isBrandExclusive`.
- Produces: `_VoucherDetailTile` renders an amber "Brand Eksklusif" pill above the title when `isBrandExclusive`; `_voucherTypeLabel` no longer returns a brand-specific title (the pill carries that signal).

- [ ] **Step 1: Remove the redundant brand branch from `_voucherTypeLabel`**

The pill will carry the brand signal, so the title should show the real voucher type. In `flutter_app/lib/screens/checkout_screen.dart`, find `_voucherTypeLabel` (4398-4412) and delete the `isBrandExclusive` branch. Replace:

```dart
String _voucherTypeLabel(MemberVoucher voucher) {
  if (voucher.isFreeShipping || voucher.isShippingDiscount) {
    return 'Voucher Gratis Ongkir';
  }
  if (voucher.isBrandExclusive) {
    return 'Voucher Brand Eksklusif';
  }
  if (voucher.isLoyaltyClaim) {
    return 'Voucher Reward Poin';
  }
  if (voucher.isPrivateManual) {
    return 'Voucher Kode Khusus';
  }
  return 'Voucher Diskon Produk';
}
```

with:

```dart
String _voucherTypeLabel(MemberVoucher voucher) {
  if (voucher.isFreeShipping || voucher.isShippingDiscount) {
    return 'Voucher Gratis Ongkir';
  }
  if (voucher.isLoyaltyClaim) {
    return 'Voucher Reward Poin';
  }
  if (voucher.isPrivateManual) {
    return 'Voucher Kode Khusus';
  }
  return 'Voucher Diskon Produk';
}
```

(`_voucherAccentColor` and `_voucherIcon` keep their `isBrandExclusive` branches unchanged — a brand shipping voucher still gets green/truck via the earlier shipping branch; a brand product voucher keeps amber/premium. The pill is added on top.)

- [ ] **Step 2: Render the amber pill in `_VoucherDetailTile`**

Find the inner `Column` in `_VoucherDetailTile` (around 4943-4947) whose first child is the title `Row`. Insert the pill as the first child. Replace:

```dart
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
```

with:

```dart
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (voucher.isBrandExclusive) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF0DC),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFFCD9A0)),
                      ),
                      child: const Text(
                        'Brand Eksklusif',
                        style: TextStyle(
                          color: Color(0xFFB85C00),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
```

- [ ] **Step 3: Analyze**

Run: `cd flutter_app && flutter analyze lib/screens/checkout_screen.dart`
Expected: no new errors or warnings.

- [ ] **Step 4: Commit**

```bash
git add flutter_app/lib/screens/checkout_screen.dart
git commit -m "feat(voucher): pill Brand Eksklusif di sheet voucher checkout

_VoucherDetailTile tampilkan pill amber 'Brand Eksklusif' di atas judul
untuk voucher brand-eksklusif apa pun (termasuk gratis ongkir).
_voucherTypeLabel tak lagi kembalikan 'Voucher Brand Eksklusif' -- judul
tampilkan tipe asli (Gratis Ongkir/Diskon Produk), pill yang bawa sinyal
brand -- konsisten untuk voucher shipping & produk."
```

---

### Task 3: Checkout — don't auto-apply brand-exclusive vouchers

**Files:**
- Modify: `flutter_app/lib/screens/checkout_screen.dart` (`_ensureAutoApplyFallback` 653-694)

**Interfaces:**
- Consumes: `MemberVoucher.isBrandExclusive`.
- Produces: brand-exclusive vouchers are excluded from the product + shipping auto-pick candidates; the user must select them manually.

- [ ] **Step 1: Exclude brand-exclusive from the product auto-pick**

Find the product-slot candidate in `_ensureAutoApplyFallback` (around 658-663). Replace:

```dart
      final candidate = available
          .where((v) =>
              v.isProductDiscount && !v.isLoyaltyClaim && !v.isPrivateManual)
          .toList()
        ..sort((a, b) => b.discount.compareTo(a.discount));
```

with:

```dart
      final candidate = available
          .where((v) =>
              v.isProductDiscount &&
              !v.isLoyaltyClaim &&
              !v.isPrivateManual &&
              !v.isBrandExclusive)
          .toList()
        ..sort((a, b) => b.discount.compareTo(a.discount));
```

- [ ] **Step 2: Exclude brand-exclusive from the shipping auto-pick**

Find the shipping-slot candidate (around 683-686). Replace:

```dart
      final candidate = available
          .where((v) => v.isFreeShipping || v.isShippingDiscount)
          .toList()
        ..sort((a, b) => b.discount.compareTo(a.discount));
```

with:

```dart
      final candidate = available
          .where((v) =>
              (v.isFreeShipping || v.isShippingDiscount) &&
              !v.isBrandExclusive)
          .toList()
        ..sort((a, b) => b.discount.compareTo(a.discount));
```

- [ ] **Step 3: Analyze**

Run: `cd flutter_app && flutter analyze lib/screens/checkout_screen.dart`
Expected: no new errors or warnings.

- [ ] **Step 4: Commit**

```bash
git add flutter_app/lib/screens/checkout_screen.dart
git commit -m "fix(voucher): jangan auto-apply voucher brand-eksklusif di checkout

_ensureAutoApplyFallback skip voucher isBrandExclusive di slot produk &
shipping -- voucher brand harus dipilih user secara sadar. Jaring
pengaman: kalau backend sempat bocor menaruh voucher brand ke available,
tak akan ke-apply diam-diam. Trade-off diterima: voucher brand valid pun
tak auto-apply (user pilih manual)."
```

---

### Task 4: Backend — brand-named disabled reason

**Files:**
- Modify: `lib/voucher-list.ts` (scope-mismatch reason 242-259)
- Modify: `app/api/checkout/recalculate/route.ts` (scope-mismatch branch 454-459)
- Test: `tests/voucher-list.test.ts`

**Interfaces:**
- Consumes: `formatVoucherBrandName` (already imported in both files), `brandNamesById` (already available in both call sites).
- Produces: when a brand-scoped voucher fails the cart scope check AND its brand name resolves, `disabledReason` becomes `"Belum ada produk brand {brandName} di keranjang"` instead of the generic string. Flutter echoes this verbatim, so it appears on all surfaces.

- [ ] **Step 1: Write the failing test**

Append to `tests/voucher-list.test.ts` (after the existing SHIPPING brand-scoped tests, after line ~597):

```ts
test("voucher SHIPPING brand-scoped scope-mismatch + brandNamesById -> reason sebut nama brand", () => {
  const items = buildVoucherListItems({
    vouchers: [
      voucher({
        id: "v-oks-hpi",
        code: "FREEOKSHPI",
        kind: "FREE_SHIPPING",
        type: "PUBLIC_FREE_SHIPPING",
        discountScope: "SHIPPING",
        discountAmount: 0,
        discountPercent: 0,
        eligibleBrandIds: ["brand-hpi"],
      }),
    ],
    userUsedOrders: [],
    userCtx: userCtx(),
    subtotal: 100000,
    now: NOW,
    cartProducts: [
      { id: "p1", categoryId: null, categorySlug: null, brandId: "brand-lain" },
    ],
    brandNamesById: new Map([["brand-hpi", "HPI"]]),
  });
  assert.equal(items[0].applicable, false);
  assert.ok(
    items[0].disabledReason?.includes("HPI"),
    `expected brand name in reason, got: ${items[0].disabledReason}`,
  );
  assert.ok(
    items[0].disabledReason?.toLowerCase().includes("brand"),
    `expected 'brand' in reason, got: ${items[0].disabledReason}`,
  );
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx tsx --test tests/voucher-list.test.ts`
Expected: FAIL on the new test — `disabledReason` is still `"Voucher tidak berlaku untuk produk di keranjang"` (no "HPI"). All other tests still pass.

- [ ] **Step 3: Implement the brand-named reason in `buildVoucherListItems`**

In `lib/voucher-list.ts`, find the block from `scopeUnmatched` through the (later) `const brandName` (around 242-259). Replace:

```ts
    const scopeUnmatched =
      cartProducts !== undefined && !cartMatchesVoucherScope(v, cartProducts);

    // Transient disabled state: belum mulai / NEW_MEMBER mismatch /
    // subtotal kurang / scope tidak cocok dengan isi cart. Voucher tetap
    // tampil dengan reason.
    const disabledReason =
      getVoucherDisabledReason(v, subtotal, userCtx, now) ??
      (scopeUnmatched ? "Voucher tidak berlaku untuk produk di keranjang" : null);
    const discount = disabledReason ? 0 : calcVoucherDiscount(subtotal, v);
    const isFreeShipping = isFreeShippingVoucher(v);
    // Free shipping voucher: applicable bahkan kalau discount=0 (karena
    // discount-nya di shipping fee, dihitung di checkout/recalculate
    // bukan di sini — listing tidak tau shipping fee).
    const applicable =
      disabledReason === null && (discount > 0 || isFreeShipping);

    const brandName = formatVoucherBrandName(v.eligibleBrandIds, brandNamesById);
```

with:

```ts
    const scopeUnmatched =
      cartProducts !== undefined && !cartMatchesVoucherScope(v, cartProducts);

    // Nama brand voucher (null kalau tidak scoped ke brand / brand tidak
    // ke-resolve di brandNamesById). Dipakai untuk display DAN untuk alasan
    // disabled yang spesifik brand.
    const brandName = formatVoucherBrandName(v.eligibleBrandIds, brandNamesById);

    // Transient disabled state: belum mulai / NEW_MEMBER mismatch /
    // subtotal kurang / scope tidak cocok dengan isi cart. Voucher tetap
    // tampil dengan reason. Kalau mismatch-nya karena brand, sebut nama
    // brand supaya user paham harus tambah produk brand itu.
    const disabledReason =
      getVoucherDisabledReason(v, subtotal, userCtx, now) ??
      (scopeUnmatched
        ? brandName
          ? `Belum ada produk brand ${brandName} di keranjang`
          : "Voucher tidak berlaku untuk produk di keranjang"
        : null);
    const discount = disabledReason ? 0 : calcVoucherDiscount(subtotal, v);
    const isFreeShipping = isFreeShippingVoucher(v);
    // Free shipping voucher: applicable bahkan kalau discount=0 (karena
    // discount-nya di shipping fee, dihitung di checkout/recalculate
    // bukan di sini — listing tidak tau shipping fee).
    const applicable =
      disabledReason === null && (discount > 0 || isFreeShipping);
```

(The `const brandName` declaration moved above `disabledReason`; the later duplicate is removed. The `items.push({ ... brandName })` below is unchanged and still references it.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `npx tsx --test tests/voucher-list.test.ts`
Expected: all tests pass, including the new one and the pre-existing `"...tanpa brand cocok -> unavailable"` tests (they pass no `brandNamesById`, so `brandName` is null → generic reason → still `.includes("tidak berlaku")`).

- [ ] **Step 5: Mirror the reason in the checkout recalculate route**

In `app/api/checkout/recalculate/route.ts`, find the scope-mismatch branch (around 454-459). Replace:

```ts
    if (!cartMatchesVoucherScope(voucher, cartProductInputs)) {
      unavailable.push(
        normalizeUnavailable(voucher, "Voucher tidak berlaku untuk produk di keranjang", 0, brandNamesById),
      );
      continue;
    }
```

with:

```ts
    if (!cartMatchesVoucherScope(voucher, cartProductInputs)) {
      const scopeBrandName = formatVoucherBrandName(
        voucher.eligibleBrandIds,
        brandNamesById,
      );
      unavailable.push(
        normalizeUnavailable(
          voucher,
          scopeBrandName
            ? `Belum ada produk brand ${scopeBrandName} di keranjang`
            : "Voucher tidak berlaku untuk produk di keranjang",
          0,
          brandNamesById,
        ),
      );
      continue;
    }
```

- [ ] **Step 6: Typecheck**

Run: `npx tsc --noEmit`
Expected: no new errors. (`formatVoucherBrandName` is already imported at `route.ts:23`; `brandNamesById` is already loaded at `route.ts:396`.)

- [ ] **Step 7: Commit**

```bash
git add lib/voucher-list.ts app/api/checkout/recalculate/route.ts tests/voucher-list.test.ts
git commit -m "feat(voucher): alasan disabled sebut nama brand untuk voucher brand-scoped

Voucher scoped-brand yang gagal cek isi cart sekarang beri reason
'Belum ada produk brand {nama} di keranjang' (bukan generic 'tidak
berlaku...') di /api/cart/vouchers + /api/checkout/recalculate. Hanya
kalau brandName ke-resolve; non-brand tetap generic. Flutter echo verbatim
jadi muncul di keranjang, checkout, & Voucher Member tanpa ubah Flutter."
```

---

### Task 5: Full verification checkpoint

**Files:** none (verification only)

- [ ] **Step 1: Backend tests**

Run: `npx tsx --test tests/voucher-list.test.ts` then `npm test`
Expected: all pass, no regressions.

- [ ] **Step 2: Backend build**

Run: `npx next build`
Expected: exit 0, no TypeScript errors (authoritative pre-push check for this repo).

- [ ] **Step 3: Flutter analyze**

Run: `cd flutter_app && flutter analyze`
Expected: no new errors or warnings introduced by this plan.

- [ ] **Step 4: Manual smoke test (emulator against dev backend)**

Requires a brand-locked free-shipping voucher (e.g. `FREEOKSHPI`, `discountScope=SHIPPING`, non-empty `eligibleBrandIds`) in the dev DB.

1. Cart with a NON-matching-brand product only, subtotal ≥ Rp250.000, open "Pilih voucher atau promo":
   - The brand ongkir voucher is under "Belum bisa dipakai" showing `[Ongkir] [Brand Eksklusif]` and reason "Belum ada produk brand {nama} di keranjang".
   - The synthetic "Gratis Ongkir" card shows truck icon + "Ongkir" badge + subtitle "… · min. belanja Rp250rb", and NO brand pill.
2. Checkout with the same cart, open the "Voucher Natalo" sheet:
   - The brand ongkir voucher shows the amber "Brand Eksklusif" pill above a "Voucher Gratis Ongkir" title, with the brand-named reason.
   - It is NOT auto-applied.
3. Add a MATCHING-brand product, refresh:
   - The brand ongkir voucher becomes usable with the pill; still requires a manual tap to apply (not auto).
4. Voucher Member page: unchanged (regression check — still shows its "BRAND EKSKLUSIF" pill).

- [ ] **Step 5: If anything fails, stop and fix before considering the plan complete.**

---

## What this plan does NOT do (non-goals)

- No change to `voucher_promo.dart` / product-detail voucher rail (separate surface; a brand voucher only shows there when the product already matches the brand, so "Gratis Ongkir" is acceptable there).
- No change to the cart product-voucher card appearance (already conveys brand-exclusivity). Minor accepted asymmetry: product brand card = single amber badge; shipping brand card = "Ongkir" + amber pill.
- No `productIds` code change (already sent by every caller — gate already armed).
- No new widget/enum, no schema change, no discount/availability math change.
- Member-page pill (`BRAND EKSKLUSIF`, uppercase) left as-is.
