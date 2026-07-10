# Voucher Ongkir — Brand Title + Synthetic-Card Removal — Design

**Date:** 2026-07-11
**Branch:** `claude/voucher-ongkir-title-synthetic` (worktree `.claude/worktrees/voucher-ongkir-fix`, from `main` `0911a091`)
**Surface:** Flutter customer app only (`flutter_app/`). No backend/schema change.

Follow-up to the merged PR #70 (brand-exclusive voucher display). Two changes, both Flutter-only.

## A) Brand-name title for brand-exclusive gratis-ongkir vouchers

A gratis-ongkir voucher locked to a brand currently shows its raw admin title ("Gratis Ongkir Brand HPI" — a code) or the generic "Voucher Gratis Ongkir", while the resolved brand is "Happy Cat". Show a consistent, brand-named title: **"Gratis Ongkir dari {brandName}"** (e.g. "Gratis Ongkir dari Happy Cat").

- **Scope:** brand-exclusive SHIPPING vouchers only (`(isFreeShipping || isShippingDiscount) && isBrandExclusive`). Public/non-brand ongkir keeps its normal title. Discount vouchers unchanged. NOT product-detail (separate surface, out of scope).
- **Surfaces:** cart sheet card title, cart collapsed sticky-bar chip, checkout sheet.
- `brandName` is already on the wire and populated in cart context (the "Brand Eksklusif" pill already renders in the cart per device verification), so no data change.

## B) Remove the fabricated free-shipping card

The cart shows a client-synthetic "Gratis Ongkir Rp15.000" card gated purely by `subtotal >= 250000`, with a flat fake `Rp15.000` estimate and sentinel code `__shipping_free__`. **The backend has no subtotal-based free shipping** — free shipping comes ONLY from a real voucher (`freeShippingVoucherCode`). So the card promises free shipping checkout won't deliver. Remove it; the cart must show/apply gratis-ongkir **only from real backend vouchers** that match the cart. A non-qualifying cart shows **no active gratis ongkir**.

### Safety (verified by 3-agent code map — removal is confined to `cart_screen.dart`)
- The synthetic shipping **never touches cart money**: `_totalVoucherSaving = _voucherDiscount` only; `_grandTotal = _selectedSubtotal - _voucherDiscount`. `_shippingEstimate`/`_shippingDiscount` feed only the cosmetic sticky-bar chip + sheet subtitle.
- `_goToCheckout` passes **only `_selectedItems`** to `/checkout` — no voucher/shipping data crosses. Checkout re-derives free shipping independently from the backend (`recalculate` → `appliedFreeShippingVoucher`). The sentinel `__shipping_free__` exists **only** in `cart_screen.dart` (grep-verified: not in checkout_screen, voucher_service, order_service).
- Real gratis-ongkir vouchers (brand + public) already flow through the same sheet via `availableShippingVouchers` + `_isCartShippingVoucherData` (real detection via `isFreeShipping`/`isShippingDiscount`/text), independent of the synthetic card.

**Conclusion:** removal cannot break the price summary, selection state, checkout handoff, or real-voucher display. Boundary = `cart_screen.dart` only. Do NOT touch checkout_screen.dart / voucher_service.dart / order_service.dart / member_profile.dart.

## Design

### Core refactor: `_appliedShippingVoucher` bool → `MemberVoucher?`
Today `bool _appliedShippingVoucher` is auto-set true on the subtotal gate. Replace with `MemberVoucher? _appliedShippingVoucher` holding the **real** selected shipping voucher (null = none). This gives both the real discount (B) and the title/brandName (A) from one source.

Ripple spots (all in `cart_screen.dart`, exact edits in the plan):
- `_shippingDiscount` (~485-488) → `_appliedShippingVoucher?.discount.toDouble() ?? 0` (or 0; it's display-only).
- `_syncVouchersForSelection` (~565-619): drop `_shippingVoucherEligible` auto-activation; pick the best real shipping voucher from `available` (mirror `_bestProductVoucher`/`_bestLoyaltyVoucher` ~622-647) via `_isCartShippingVoucherData`; drop the `__shipping_free__` manual branch (~575-580).
- `_openVoucherSheet` (~747-755): remove `shippingEligible`/`shippingDiscount` synthetic args; feed from the real applied voucher; `shippingSelected` = presence.
- `CartCheckoutPill.voucherActive` (~1063) and `_StickyVoucherBar` (~1079-1092, 2552-2578) → presence-based (`_appliedShippingVoucher != null`), NOT `shippingDiscount > 0` (real cart discount may be 0 pre-checkout).

### Remove synthetic machinery (`cart_screen.dart`)
- Delete `_shippingVoucherCode = '__shipping_free__'` (~59), `_shippingEstimate` (~471), `_shippingVoucherEligible` (~496-497) after removing usages.
- `_CartVoucherSheet`: remove `showSyntheticShipping` (~2901-2902) + the synthetic `_CartVoucherCard` (~2966-2981); update `hasAnyVoucher` (~2903-2905); `_firstAvailableShippingCode` (~2839-2844) drop the `_shippingVoucherCode` fallback → null; `_pickShipping` (~2867-2873) require a real code (drop `?? _shippingVoucherCode`); fix the synthetic `selected` check (~2976); remove `shippingEligible`/`shippingDiscount` sheet fields (~2760-2783).
- `_isCartShippingVoucherData` (~2472-2485): drop ONLY the sentinel clause (~2473); KEEP the real detection (~2474+).
- `_cartShippingVoucherSubtitle` (~2487-2502): pass `0` fallback instead of the Rp15k.

### A) Title helper
`String _shippingVoucherTitle(MemberVoucher v)` → `v.isBrandExclusive && (v.brandName?.trim().isNotEmpty ?? false) ? 'Gratis Ongkir dari ${v.brandName!.trim()}' : v.title` (or the existing generic). Apply at:
- Cart sheet real-shipping card `title:` (~2984).
- Cart collapsed chip: `_StickyVoucherBar` shippingText (~2636) — plumb the applied voucher's brandName/title into the bar (currently only bool+amount).
- Checkout `_voucherTypeLabel` (~4403-4405): for brand-exclusive shipping return `'Gratis Ongkir dari ${brandName}'`, else `'Voucher Gratis Ongkir'`.

## Files touched
| File | Change |
|------|--------|
| `flutter_app/lib/screens/cart_screen.dart` | B removal + refactor `_appliedShippingVoucher`→MemberVoucher?; A titles (sheet card + sticky chip) |
| `flutter_app/lib/screens/checkout_screen.dart` | A: `_voucherTypeLabel` brand-shipping title |

## Testing
- `cd flutter_app && flutter analyze` clean.
- Existing cart widget tests (beware the shimmer-hang gotcha — bounded pump, mock prefs, clear cartStore). If they assert on the synthetic card/subtotal gate, update them.
- Manual/emulator smoke: (1) cart with non-qualifying product → NO active gratis ongkir (no chip, no synthetic card); brand ongkir stays under "Belum bisa dipakai" with brand title. (2) cart with a matching brand product → brand ongkir usable, title "Gratis Ongkir dari Happy Cat", chip shows it. (3) public gratis-ongkir voucher (if any) → shows normally as "Gratis Ongkir". (4) checkout unaffected (free shipping still auto-applies from backend).

## Risks / non-goals
- Presence-vs-amount chip: decided **presence-based** (show when a real shipping voucher is applied, even if cart-side discount is 0).
- Keep real `_isCartShippingVoucherData` detection intact (only drop the sentinel) — else brand/public ongkir vanish.
- Brand title gated on `isBrandExclusive` — public ongkir keeps generic title.
- Large file (~3900 lines) + shimmer-hang test gotcha — keep edits scoped to shipping-voucher logic.
- Non-goal: product-detail rail (green badge / generic title) — separate follow-up. Discount-voucher titles unchanged.
