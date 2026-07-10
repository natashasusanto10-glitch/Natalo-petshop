# Voucher Shipping-Brand Display — Design

**Date:** 2026-07-10
**Branch:** `claude/voucher-brand-filtering-bug-7f8bbe`
**Surfaces:** Flutter customer app (`flutter_app/`) + Next.js backend (`lib/`, `app/api/`)

## Problem

Two user-reported issues on brand-locked **free-shipping** vouchers (e.g. `FREEOKSHPI` "Gratis Ongkir Brand HPI", `discountScope=SHIPPING` + non-empty `eligibleBrandIds`):

1. **Unclear placeholder (real bug).** A brand-locked gratis-ongkir voucher shows only a generic green "Ongkir" / "Voucher Gratis Ongkir" tag with the generic reason `"Voucher tidak berlaku untuk produk di keranjang"`, on both the **cart voucher picker** and the **checkout voucher sheet**. It is visually indistinguishable from a store-wide free-shipping voucher. The **Voucher Member** page already shows an amber "BRAND EKSKLUSIF" badge for the same voucher, so the two surfaces are inconsistent.

2. **Cart page "voucher shouldn't appear" (misread + latent gaps).** The user saw a usable "Gratis Ongkir — Potongan ongkir Rp15.000" and believed the brand voucher was leaking. It is **not** a leak: that card is the app's **client-synthetic** free-shipping-over-Rp250k promo, and the real brand voucher is **correctly** demoted to "Belum bisa dipakai". The confusion is that the synthetic promo looks like a voucher and sits next to the blocked brand voucher, both wearing a plain "Ongkir" tag.

## Root cause (verified against current code)

All three surfaces parse the **same** `MemberVoucher` model. `MemberVoucher.isBrandExclusive` ([member_profile.dart:282](../../flutter_app/lib/models/member_profile.dart)) = `brandName != null && brandName.trim().isNotEmpty` — **scope-agnostic**, so it is already `true` for a shipping voucher. `brandName` is emitted by **both** endpoints (`/api/cart/vouchers` via [voucher-list.ts:259](../../lib/voucher-list.ts), and `/api/checkout/recalculate` via [route.ts:151,176](../../app/api/checkout/recalculate/route.ts)). **The data is already on the wire — BUG 1 is a pure Flutter render gap.**

- **Member page (correct reference):** [member_vouchers_screen.dart:355-381](../../flutter_app/lib/screens/member_vouchers_screen.dart) renders the amber pill on a single unconditional `if (voucher.isBrandExclusive)` — no shipping/product split.
- **Cart (broken):** the shipping-card loops ([cart_screen.dart:2978-2998](../../flutter_app/lib/screens/cart_screen.dart) available, [3067-3088](../../flutter_app/lib/screens/cart_screen.dart) unavailable) hardcode `badge: 'Ongkir'` and never read `isBrandExclusive`; only the product-card loops ([3089-3119](../../flutter_app/lib/screens/cart_screen.dart)) do.
- **Checkout (broken):** `_voucherTypeLabel` / `_voucherAccentColor` / `_voucherIcon` ([checkout_screen.dart:4398-4464](../../flutter_app/lib/screens/checkout_screen.dart)) check `isFreeShipping || isShippingDiscount` **first** and return before the `isBrandExclusive` branch; `_VoucherDetailTile` ([4895+](../../flutter_app/lib/screens/checkout_screen.dart)) renders no brand pill at all.
- **Shared helpers:** `voucher_promo.dart` `voucherChipText` ([128-132](../../flutter_app/lib/utils/voucher_promo.dart)) and `voucherSheetSubtitle` ([96-123](../../flutter_app/lib/utils/voucher_promo.dart)) repeat the same shipping-first precedence.

For BUG 2: usable-vs-not is 100% backend (`applicable` flag). The backend scope gate `cartMatchesVoucherScope` ([voucher-eligibility.ts:69-75](../../lib/voucher-eligibility.ts)) is scope-agnostic and correctly demotes brand-locked shipping vouchers **when `productIds` is sent**. The synthetic card ([cart_screen.dart:2962-2977](../../flutter_app/lib/screens/cart_screen.dart)) is gated only by `subtotal >= 250000` ([496-497](../../flutter_app/lib/screens/cart_screen.dart)) with a flat `Rp15.000` estimate ([471](../../flutter_app/lib/screens/cart_screen.dart)) and appears precisely when `availableShippingVouchers.isEmpty` ([2897-2898](../../flutter_app/lib/screens/cart_screen.dart)) — i.e. right after the brand voucher was correctly blocked. The only **genuine** leak path is when `productIds` is omitted (`cartProducts` undefined server-side → gate skipped), e.g. an old app build hitting the updated backend.

## Non-goals

- No change to voucher discount / availability **math** (backend gate already correct).
- No new voucher type/enum; no DB/schema change; `isBrandExclusive` stays derived from `brandName`.
- No fix for already-installed old app builds that never send `productIds` (out of our control).
- No change to the cart **product**-voucher card appearance (already conveys brand-exclusivity correctly). We accept a minor on-sheet asymmetry (product brand card = single amber badge; shipping brand card = "Ongkir" + amber pill).
- Manual/private (`SELLER_MANUAL`) voucher reasons stay generic (out of scope).

## Design

### Part 1 — Brand-exclusive pill on shipping vouchers (dual-badge)

Approved treatment: **keep the type badge and add a dedicated amber "Brand Eksklusif" pill** (parity with the member page), rather than replacing the type badge.

**Cart** ([cart_screen.dart](../../flutter_app/lib/screens/cart_screen.dart)):
- Add an optional `bool brandExclusive` param to `_CartVoucherCard` (class at [3164](../../flutter_app/lib/screens/cart_screen.dart); default `false`). In its badge `Row` ([~3225-3244](../../flutter_app/lib/screens/cart_screen.dart)), when `brandExclusive` is true, render an amber pill after the primary badge:
  - text `Brand Eksklusif`, bg `#FEF0DC`, border `#FCD9A0`, text color `#B85C00`, fontSize 10, w900 (same tokens as [member_vouchers_screen.dart:355-381](../../flutter_app/lib/screens/member_vouchers_screen.dart)).
- In the two **shipping** loops (available [2978-2998](../../flutter_app/lib/screens/cart_screen.dart), unavailable [3067-3088](../../flutter_app/lib/screens/cart_screen.dart)): keep `badge: 'Ongkir'` + green/truck, add `brandExclusive: voucher.isBrandExclusive`.
- The synthetic card ([2962-2977](../../flutter_app/lib/screens/cart_screen.dart)) is store-wide → `brandExclusive: false` (unchanged).

**Checkout** ([checkout_screen.dart](../../flutter_app/lib/screens/checkout_screen.dart)):
- Add the same amber "Brand Eksklusif" pill to `_VoucherDetailTile` ([4895+](../../flutter_app/lib/screens/checkout_screen.dart)) when `voucher.isBrandExclusive`, rendered above/next to the title — regardless of voucher type. Keep the existing shipping type label/color/icon (so the row still reads as "Voucher Gratis Ongkir" green + the amber pill).
- Remove the now-redundant `isBrandExclusive → 'Voucher Brand Eksklusif'` branch in `_voucherTypeLabel` ([4402-4404](../../flutter_app/lib/screens/checkout_screen.dart)) so the title always shows the real type (Gratis Ongkir / Diskon Produk / Reward Poin) and the pill carries the brand signal — consistent for product **and** shipping brand vouchers.
- Optionally surface the pill in the collapsed `_VoucherSlot` applied chip ([4260-4266](../../flutter_app/lib/screens/checkout_screen.dart)).

**Shared** ([voucher_promo.dart](../../flutter_app/lib/utils/voucher_promo.dart)): leave `voucherChipText`/`voucherSheetSubtitle` type-first, but ensure any surface using them for brand vouchers still gets a brand cue (these power secondary chips; verify no regression — no reorder required if the pill approach covers the primary surfaces).

**No backend change** (brandName already emitted on both endpoints).

### Part 2 — Clarify the synthetic store promo card

[cart_screen.dart:2962-2977](../../flutter_app/lib/screens/cart_screen.dart):
- **Keep** the truck icon (`local_shipping_outlined`) — per user, it must stay so the card still signals *ongkos kirim*. **Keep** the green `'Ongkir'` badge.
- Only change: subtitle `'Potongan ongkir ${formatRupiah(shippingDiscount)}'` → append the condition, e.g. `'Potongan ongkir Rp15.000 · min. belanja Rp250rb'`.
- Differentiation from a brand voucher now comes from Part 1's amber "Brand Eksklusif" pill (which this synthetic card never has) plus the explicit min-belanja condition — not from changing the icon/badge. Final copy is tweakable.

### Part 3 — Brand-specific disabled reason (backend)

When a voucher is brand-scoped (`eligibleBrandIds` non-empty) and demoted for scope mismatch, replace the generic reason with a brand-named one. Because Flutter echoes `disabledReason` verbatim, the new text auto-appears on **all** surfaces (cart, checkout, member page) with no Flutter change.

- [voucher-list.ts:248-250](../../lib/voucher-list.ts): compute the brand label (`formatVoucherBrandName(v.eligibleBrandIds, brandNamesById)`, already available at [259](../../lib/voucher-list.ts) — move up) and, when non-null, use `` `Belum ada produk brand ${brandLabel} di keranjang` `` instead of `"Voucher tidak berlaku untuk produk di keranjang"`. Non-brand scope keeps the generic string.
- [app/api/checkout/recalculate/route.ts:456](../../app/api/checkout/recalculate/route.ts): same treatment for the scope-mismatch branch (brandNamesById already loaded at [396](../../app/api/checkout/recalculate/route.ts)).
- Multi-brand label reuses the existing `"{first} & N brand lain"` format.

### Part 4 — Anti-leak hardening

- **Core (armed gate):** verify/guarantee `productIds` is always sent from every caller of `fetchCartVouchers` / `fetchVouchers` ([member_service.dart:346-375](../../flutter_app/lib/services/member_service.dart)) and the cart sync ([cart_screen.dart ~548-559](../../flutter_app/lib/screens/cart_screen.dart)). Even an empty cart must send `productIds=''` so `cartProducts` is `[]` (gate armed), never `undefined` (gate skipped). This closes the real leak path for the current app.
- **Defense-in-depth (approved, has trade-off):** in `_ensureAutoApplyFallback` ([checkout_screen.dart:653-694](../../flutter_app/lib/screens/checkout_screen.dart)) exclude brand-exclusive vouchers from the auto-pick candidates — add `&& !v.isBrandExclusive` to the product ([658-663](../../flutter_app/lib/screens/checkout_screen.dart)) and shipping ([682-691](../../flutter_app/lib/screens/checkout_screen.dart)) candidate filters. Brand-exclusive vouchers must be selected manually, so a leaked one is never silently auto-applied. Trade-off accepted: valid brand vouchers also won't auto-apply.

## Files touched

| File | Change |
|------|--------|
| `flutter_app/lib/screens/cart_screen.dart` | `_CartVoucherCard` gains `brandExclusive` flag + amber pill; shipping loops pass it; synthetic card relabel (Part 2) |
| `flutter_app/lib/screens/checkout_screen.dart` | `_VoucherDetailTile` amber pill; drop brand branch in `_voucherTypeLabel`; `_ensureAutoApplyFallback` skips brand-exclusive |
| `flutter_app/lib/utils/voucher_promo.dart` | verify brand cue for shipping vouchers; no regression |
| `flutter_app/lib/services/member_service.dart` | ensure `productIds` always sent (verify) |
| `lib/voucher-list.ts` | brand-specific `disabledReason` |
| `app/api/checkout/recalculate/route.ts` | brand-specific reason for scope-mismatch branch |

## Testing

- **Backend:** `npx tsx --test tests/voucher-list.test.ts` — add a test: brand-scoped shipping voucher + non-matching cart → `disabledReason` includes `"brand"` and the brand name; non-brand keeps generic. Then `npx next build`.
- **Flutter:** `cd flutter_app && flutter analyze`. Manual/emulator verification of the three surfaces (widget tests risk the shimmer-hang noted in project memory — prefer manual). Check no golden test covers these voucher cards (none expected).
- **Manual smoke:** brand product absent → brand ongkir voucher under "Belum bisa dipakai" with amber pill + brand-named reason; synthetic "Promo Toko" card shows min-belanja; brand product present → voucher usable with pill, not auto-applied.

## Risk

Low. Flutter changes mirror existing patterns (product-card brand branch, member-page pill) plus one small shared-widget param; backend is a 2-3 line string change per file. No math, schema, or availability logic changes.
