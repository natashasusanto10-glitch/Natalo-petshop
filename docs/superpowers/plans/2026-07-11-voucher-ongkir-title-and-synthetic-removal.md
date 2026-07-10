# Voucher Ongkir — Brand Title + Synthetic-Card Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the fabricated client-side "Gratis Ongkir Rp15.000" card so free shipping shows only from real matching vouchers, and title brand-locked ongkir vouchers as "Gratis Ongkir dari {brand}".

**Architecture:** Flutter-only. Refactor `bool _appliedShippingVoucher` → `MemberVoucher?` in `cart_screen.dart` so the cart's "shipping active" state is driven by a real backend voucher (not a `subtotal>=250000` gate), then delete the synthetic machinery. Add a display-title helper for brand-exclusive shipping vouchers on the cart sheet, the collapsed sticky-bar chip, and the checkout label. No backend/schema change; the synthetic sentinel `__shipping_free__` lives only in `cart_screen.dart` and never crosses to checkout (verified), so removal is confined to this file plus one checkout label helper.

**Tech Stack:** Flutter/Dart. Verify with `flutter analyze`.

## Global Constraints

- **Workspace:** all edits + commands run in `C:\Users\USER\Desktop\natalopetshopflutter\.claude\worktrees\voucher-ongkir-fix` (branch `claude/voucher-ongkir-title-synthetic`). The MAIN checkout is shared with other sessions — never use it. All git via `git -C "<worktree>"`; run analyze as one command: `cd "<worktree>/flutter_app" && flutter analyze lib/screens/<file>`.
- **Removal boundary = `cart_screen.dart` only** for B; A also touches `checkout_screen.dart` (`_voucherTypeLabel`). Do NOT touch `voucher_service.dart`, `order_service.dart`, `member_profile.dart`, or `checkout_screen.dart` beyond `_voucherTypeLabel`.
- **Brand title format (exact):** `Gratis Ongkir dari ${brandName}` — only when `voucher.isBrandExclusive` AND `brandName` non-empty. Public/non-brand ongkir keeps `voucher.title` / `'Voucher Gratis Ongkir'`. Ongkir vouchers only (not discount/loyalty).
- **Chip is presence-based:** the sticky-bar Gratis Ongkir chip shows when a real shipping voucher is applied (`_appliedShippingVoucher != null`), NOT gated on `shippingDiscount > 0` (a real free-shipping voucher's cart-side discount may be 0).
- **Keep real shipping detection** in `_isCartShippingVoucherData` — remove ONLY the `__shipping_free__` sentinel clause; the `isFreeShipping`/`isShippingDiscount`/text detection MUST stay.
- **Auto-apply skips brand-exclusive** ongkir (mirror checkout): `_bestShippingVoucher` excludes `isBrandExclusive`; a manually-picked brand ongkir still applies.
- Indonesian UI strings. `cart_screen.dart` is ~3900 lines with an auto-hide-chrome saga — keep edits scoped to shipping-voucher logic.

---

### Task 1: Remove synthetic free-shipping card + refactor `_appliedShippingVoucher` → `MemberVoucher?`

**Files:**
- Modify: `flutter_app/lib/screens/cart_screen.dart`

**Interfaces:**
- Consumes: `MemberVoucher` (existing), `_isCartShippingVoucher`, `_findVoucherByCode`, `_bestProductVoucher`/`_bestLoyaltyVoucher` (existing patterns).
- Produces: `MemberVoucher? _appliedShippingVoucher`; `_bestShippingVoucher(List<MemberVoucher>)`. Removes `_shippingVoucherCode`, `_shippingEstimate`, `_shippingVoucherEligible`, the synthetic card, and the `_CartVoucherSheet.shippingEligible`/`shippingDiscount` params.

- [ ] **Step 1: Change the applied-shipping state field to a nullable voucher**

`cart_screen.dart:115` — replace:
```dart
  bool _appliedShippingVoucher = false;
```
with:
```dart
  MemberVoucher? _appliedShippingVoucher;
```

- [ ] **Step 2: Delete the fabricated shipping estimate + eligibility getters, rewrite `_shippingDiscount`**

Replace (`cart_screen.dart:471`):
```dart
  double get _shippingEstimate => _selectedItems.isEmpty ? 0 : 15000;
```
with nothing (delete the line and its blank line).

Replace (`cart_screen.dart:485-488`):
```dart
  double get _shippingDiscount {
    if (_selectedItems.isEmpty || !_appliedShippingVoucher) return 0;
    return _shippingEstimate;
  }
```
with:
```dart
  double get _shippingDiscount {
    final voucher = _appliedShippingVoucher;
    if (_selectedItems.isEmpty || voucher == null) return 0;
    return voucher.discount.toDouble();
  }
```

Replace (`cart_screen.dart:496-497`):
```dart
  bool get _shippingVoucherEligible =>
      _selectedItems.isNotEmpty && _selectedSubtotal >= 250000;
```
with nothing (delete the getter and its blank line).

- [ ] **Step 3: Add `_bestShippingVoucher` helper**

In `cart_screen.dart`, after `_bestLoyaltyVoucher` (ends ~647, before `_findVoucherByCode`), insert:
```dart
  /// Best real gratis-ongkir voucher untuk cart. Brand-exclusive ongkir
  /// TIDAK auto-apply (user pilih manual) -- konsisten dgn checkout
  /// _ensureAutoApplyFallback. Tidak filter discount>0 karena voucher
  /// gratis-ongkir bisa discount=0 di konteks cart (dihitung di checkout).
  MemberVoucher? _bestShippingVoucher(List<MemberVoucher> vouchers) {
    final eligible = vouchers
        .where((voucher) =>
            _isCartShippingVoucher(voucher) && !voucher.isBrandExclusive)
        .toList();
    if (eligible.isEmpty) return null;
    eligible.sort((a, b) => b.discount.compareTo(a.discount));
    return eligible.first;
  }
```

- [ ] **Step 4: Rewrite the sync logic (`_syncVouchersForSelection`)**

Replace the reset assignment (`cart_screen.dart:532`):
```dart
        _appliedShippingVoucher = false;
```
with:
```dart
        _appliedShippingVoucher = null;
```

Replace the whole compute block (`cart_screen.dart:565-608`):
```dart
    // Per business rule Natalo: 3 voucher type bisa apply bersamaan
    // (1 ongkir + 1 produk + 1 reward poin). Pick best per type separately.
    final bestProduct = _bestProductVoucher(available);
    final bestLoyalty = _bestLoyaltyVoucher(available);
    var nextProduct = _appliedDiscountVoucher;
    var nextLoyalty = _appliedLoyaltyVoucher;
    var nextShipping = _appliedShippingVoucher && _shippingVoucherEligible;
    var manualStillEligible = false;

    if (_isManualVoucherSelected && _manualVoucherCode != null) {
      if (_manualVoucherCode == _shippingVoucherCode &&
          _shippingVoucherEligible) {
        manualStillEligible = true;
        nextShipping = true;
        nextProduct = bestProduct;
        nextLoyalty = bestLoyalty;
      } else {
        final manualVoucher =
            _findVoucherByCode(available, _manualVoucherCode!);
        if (manualVoucher != null && _isCartShippingVoucher(manualVoucher)) {
          manualStillEligible = true;
          nextShipping = true;
          nextProduct = bestProduct;
          nextLoyalty = bestLoyalty;
        } else if (manualVoucher != null) {
          manualStillEligible = true;
          // Manual override pick — replace slot yang sesuai type.
          if (manualVoucher.isLoyaltyClaim) {
            nextLoyalty = manualVoucher;
            nextProduct = bestProduct;
          } else {
            nextProduct = manualVoucher;
            nextLoyalty = bestLoyalty;
          }
          nextShipping = _shippingVoucherEligible;
        }
      }
    }

    if (!_isManualVoucherSelected || !manualStillEligible) {
      nextProduct = bestProduct;
      nextLoyalty = bestLoyalty;
      nextShipping = _shippingVoucherEligible;
    }
```
with:
```dart
    // Per business rule Natalo: 3 voucher type bisa apply bersamaan
    // (1 ongkir + 1 produk + 1 reward poin). Pick best per type separately.
    final bestProduct = _bestProductVoucher(available);
    final bestLoyalty = _bestLoyaltyVoucher(available);
    final bestShipping = _bestShippingVoucher(available);
    var nextProduct = _appliedDiscountVoucher;
    var nextLoyalty = _appliedLoyaltyVoucher;
    var nextShipping = bestShipping;
    var manualStillEligible = false;

    if (_isManualVoucherSelected && _manualVoucherCode != null) {
      final manualVoucher = _findVoucherByCode(available, _manualVoucherCode!);
      if (manualVoucher != null && _isCartShippingVoucher(manualVoucher)) {
        manualStillEligible = true;
        // Manual pick shipping (termasuk brand-exclusive) tetap dihormati.
        nextShipping = manualVoucher;
        nextProduct = bestProduct;
        nextLoyalty = bestLoyalty;
      } else if (manualVoucher != null) {
        manualStillEligible = true;
        // Manual override pick — replace slot yang sesuai type.
        if (manualVoucher.isLoyaltyClaim) {
          nextLoyalty = manualVoucher;
          nextProduct = bestProduct;
        } else {
          nextProduct = manualVoucher;
          nextLoyalty = bestLoyalty;
        }
        nextShipping = bestShipping;
      }
    }

    if (!_isManualVoucherSelected || !manualStillEligible) {
      nextProduct = bestProduct;
      nextLoyalty = bestLoyalty;
      nextShipping = bestShipping;
    }
```

(The `setState` block right after — `cart_screen.dart:611-619` — already assigns `_appliedShippingVoucher = nextShipping;`; now `nextShipping` is a `MemberVoucher?`, so no change needed there.)

- [ ] **Step 5: Update `_openVoucherSheet` sheet args + result handler**

Replace (`cart_screen.dart:747-755`):
```dart
        shippingEligible: _shippingVoucherEligible,
        shippingDiscount: _shippingEstimate.round(),
        selectedDiscountCode: _appliedDiscountVoucher?.code,
        selectedLoyaltyCode: _appliedLoyaltyVoucher?.code,
        selectedShippingCode:
            _appliedShippingVoucher && _isManualVoucherSelected
                ? _manualVoucherCode
                : null,
        shippingSelected: _appliedShippingVoucher,
```
with:
```dart
        selectedDiscountCode: _appliedDiscountVoucher?.code,
        selectedLoyaltyCode: _appliedLoyaltyVoucher?.code,
        selectedShippingCode: _appliedShippingVoucher?.code,
        shippingSelected: _appliedShippingVoucher != null,
```

Replace (`cart_screen.dart:768`):
```dart
        _appliedShippingVoucher = false;
```
with:
```dart
        _appliedShippingVoucher = null;
```

Replace (`cart_screen.dart:782-783`):
```dart
      _appliedShippingVoucher =
          picked.shippingSelected && _shippingVoucherEligible;
```
with:
```dart
      _appliedShippingVoucher =
          picked.shippingSelected && picked.shippingCode != null
              ? _findVoucherByCode(
                  _availableDiscountVouchers, picked.shippingCode!)
              : null;
```

- [ ] **Step 6: Update the pill + sticky-bar wiring for the nullable field**

Replace (`cart_screen.dart:1060-1063`):
```dart
                                      voucherActive:
                                          _appliedDiscountVoucher != null ||
                                              _appliedLoyaltyVoucher != null ||
                                              _appliedShippingVoucher,
```
with:
```dart
                                      voucherActive:
                                          _appliedDiscountVoucher != null ||
                                              _appliedLoyaltyVoucher != null ||
                                              _appliedShippingVoucher != null,
```

Replace (`cart_screen.dart:1084`):
```dart
                        shippingSelected: _appliedShippingVoucher,
```
with:
```dart
                        shippingSelected: _appliedShippingVoucher != null,
```

- [ ] **Step 7: Make the sticky-bar chip presence-based**

Replace (`cart_screen.dart:2578`):
```dart
    final hasShipping = shippingSelected && shippingDiscount > 0;
```
with:
```dart
    final hasShipping = shippingSelected;
```

- [ ] **Step 8: Drop the sentinel clause from shipping detection**

Replace (`cart_screen.dart:2472-2474`):
```dart
bool _isCartShippingVoucherData(MemberVoucher voucher) {
  if (voucher.code == _shippingVoucherCode) return true;
  if (voucher.isFreeShipping || voucher.isShippingDiscount) return true;
```
with:
```dart
bool _isCartShippingVoucherData(MemberVoucher voucher) {
  if (voucher.isFreeShipping || voucher.isShippingDiscount) return true;
```

- [ ] **Step 9: Remove the `shippingEligible` / `shippingDiscount` sheet params**

Replace (`cart_screen.dart:2761-2783`) the `_CartVoucherSheet` field list + constructor:
```dart
  final List<MemberVoucher> availableDiscounts;
  final List<MemberVoucher> unavailableDiscounts;
  final bool shippingEligible;
  final int shippingDiscount;
  final String? selectedDiscountCode;
  final String? selectedLoyaltyCode;
  final String? selectedShippingCode;
  final bool shippingSelected;
  final bool isManual;
  final bool loading;

  const _CartVoucherSheet({
    required this.availableDiscounts,
    required this.unavailableDiscounts,
    required this.shippingEligible,
    required this.shippingDiscount,
    required this.selectedDiscountCode,
    required this.selectedLoyaltyCode,
    required this.selectedShippingCode,
    required this.shippingSelected,
    required this.isManual,
    required this.loading,
  });
```
with:
```dart
  final List<MemberVoucher> availableDiscounts;
  final List<MemberVoucher> unavailableDiscounts;
  final String? selectedDiscountCode;
  final String? selectedLoyaltyCode;
  final String? selectedShippingCode;
  final bool shippingSelected;
  final bool isManual;
  final bool loading;

  const _CartVoucherSheet({
    required this.availableDiscounts,
    required this.unavailableDiscounts,
    required this.selectedDiscountCode,
    required this.selectedLoyaltyCode,
    required this.selectedShippingCode,
    required this.shippingSelected,
    required this.isManual,
    required this.loading,
  });
```

- [ ] **Step 10: Fix `_firstAvailableShippingCode` + `_pickShipping` (drop synthetic fallback/default)**

Replace (`cart_screen.dart:2839-2844`):
```dart
  String? _firstAvailableShippingCode() {
    for (final voucher in widget.availableDiscounts) {
      if (_isCartShippingVoucher(voucher)) return voucher.code;
    }
    return widget.shippingEligible ? _shippingVoucherCode : null;
  }
```
with:
```dart
  String? _firstAvailableShippingCode() {
    for (final voucher in widget.availableDiscounts) {
      if (_isCartShippingVoucher(voucher)) return voucher.code;
    }
    return null;
  }
```

Replace (`cart_screen.dart:2867-2873`):
```dart
  void _pickShipping([String? code]) {
    final nextCode = code ?? _shippingVoucherCode;
    setState(() {
      _selectedShippingCode =
          _selectedShippingCode == nextCode ? null : nextCode;
    });
  }
```
with:
```dart
  void _pickShipping(String code) {
    setState(() {
      _selectedShippingCode =
          _selectedShippingCode == code ? null : code;
    });
  }
```

- [ ] **Step 11: Remove the synthetic card render + `showSyntheticShipping`**

Replace (`cart_screen.dart:2901-2905`):
```dart
    final showSyntheticShipping =
        widget.shippingEligible && availableShippingVouchers.isEmpty;
    final hasAnyVoucher = showSyntheticShipping ||
        availableShippingVouchers.isNotEmpty ||
        availableProductVouchers.isNotEmpty;
```
with:
```dart
    final hasAnyVoucher = availableShippingVouchers.isNotEmpty ||
        availableProductVouchers.isNotEmpty;
```

Replace (`cart_screen.dart:2966-2981`) the synthetic card block:
```dart
                    if (showSyntheticShipping) ...[
                      _CartVoucherCard(
                        title: 'Gratis Ongkir',
                        subtitle:
                            'Potongan ongkir ${formatRupiah(widget.shippingDiscount)} · min. belanja Rp250rb',
                        badge: 'Ongkir',
                        icon: Icons.local_shipping_outlined,
                        accent: _shippingGreen,
                        background: _shippingGreenSoft,
                        border: _shippingGreenBorder,
                        selected: _selectedShippingCode == _shippingVoucherCode,
                        enabled: true,
                        onTap: _pickShipping,
                      ),
                      const SizedBox(height: 10),
                    ],
```
with nothing (delete the entire `if (showSyntheticShipping) ...[ ... ],` block).

- [ ] **Step 12: Fix the real-shipping-card subtitle fallback (no fabricated amount)**

Replace (`cart_screen.dart:2985-2988`):
```dart
                        subtitle: _cartShippingVoucherSubtitle(
                          voucher,
                          widget.shippingDiscount,
                        ),
```
with:
```dart
                        subtitle: _cartShippingVoucherSubtitle(voucher, 0),
```

- [ ] **Step 13: Delete the now-unused sentinel constant**

Replace (`cart_screen.dart:59`):
```dart
const _shippingVoucherCode = '__shipping_free__';
```
with nothing (delete the line).

- [ ] **Step 14: Analyze**

Run: `cd "/c/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/voucher-ongkir-fix/flutter_app" && flutter analyze lib/screens/cart_screen.dart`
Expected: no errors, no warnings, and NO remaining references to `_shippingVoucherCode`, `_shippingEstimate`, or `_shippingVoucherEligible` (grep to confirm: `grep -n "_shippingVoucherCode\|_shippingEstimate\|_shippingVoucherEligible" lib/screens/cart_screen.dart` returns nothing).

- [ ] **Step 15: Commit**

```bash
git -C "/c/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/voucher-ongkir-fix" add flutter_app/lib/screens/cart_screen.dart
git -C "/c/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/voucher-ongkir-fix" commit -m "fix(voucher): hapus kartu gratis-ongkir sintetis; ongkir dari voucher asli

Kartu 'Gratis Ongkir Rp15.000' (gate subtotal>=250rb, __shipping_free__,
Rp15rb palsu) tak didukung backend -> false promise. _appliedShippingVoucher
bool->MemberVoucher? (voucher ongkir asli terpilih). Aktif hanya kalau ada
voucher ongkir asli yg cocok produk; brand-exclusive tak auto-apply.
Chip berbasis kehadiran. cart_screen.dart only; checkout tak tersentuh."
```

---

### Task 2: Brand-name title "Gratis Ongkir dari {brand}"

**Files:**
- Modify: `flutter_app/lib/screens/cart_screen.dart` (sheet card title + sticky-bar chip)
- Modify: `flutter_app/lib/screens/checkout_screen.dart` (`_voucherTypeLabel`)

**Interfaces:**
- Consumes: `MemberVoucher.brandName` / `.isBrandExclusive` (existing), `_appliedShippingVoucher` (Task 1).
- Produces: `_shippingVoucherDisplayTitle(MemberVoucher)` in cart_screen.dart; `_StickyVoucherBar.shippingText` param.

- [ ] **Step 1: Add the display-title helper**

In `cart_screen.dart`, right after `_cartShippingVoucherSubtitle` (ends ~2502, before `bool _isCartShippingVoucher`), insert:
```dart
/// Judul display voucher gratis-ongkir. Brand-eksklusif -> "Gratis Ongkir
/// dari {brand}" (pakai nama brand asli, bukan judul admin/kode); selain
/// itu pakai judul voucher apa adanya.
String _shippingVoucherDisplayTitle(MemberVoucher voucher) {
  final brand = voucher.brandName?.trim();
  if (voucher.isBrandExclusive && brand != null && brand.isNotEmpty) {
    return 'Gratis Ongkir dari $brand';
  }
  return voucher.title;
}
```

- [ ] **Step 2: Use it on the cart sheet real-shipping card**

Inside the `availableShippingVouchers` loop (after Task 1 the subtitle reads `_cartShippingVoucherSubtitle(voucher, 0)`). Replace this exact two-line hunk (unique — the product loop's `title: voucher.title,` is followed by `subtitle: voucher.description,` instead):
```dart
                        title: voucher.title,
                        subtitle: _cartShippingVoucherSubtitle(voucher, 0),
```
with:
```dart
                        title: _shippingVoucherDisplayTitle(voucher),
                        subtitle: _cartShippingVoucherSubtitle(voucher, 0),
```

- [ ] **Step 3: Add a `shippingText` param to `_StickyVoucherBar` and forward it**

In `_StickyVoucherBar`, add the field + constructor param. Replace (`cart_screen.dart:2557-2569`):
```dart
  final bool shippingSelected;
  final double shippingDiscount;
  final VoidCallback? onTap;

  const _StickyVoucherBar({
    required this.hasSelection,
    required this.loading,
    required this.discountVoucher,
    required this.discountAmount,
    required this.shippingSelected,
    required this.shippingDiscount,
    required this.onTap,
  });
```
with:
```dart
  final bool shippingSelected;
  final double shippingDiscount;
  final String shippingText;
  final VoidCallback? onTap;

  const _StickyVoucherBar({
    required this.hasSelection,
    required this.loading,
    required this.discountVoucher,
    required this.discountAmount,
    required this.shippingSelected,
    required this.shippingDiscount,
    required this.shippingText,
    required this.onTap,
  });
```

Replace the hardcoded chip text (`cart_screen.dart:2636`):
```dart
                      shippingText: 'Gratis Ongkir',
```
with:
```dart
                      shippingText: shippingText,
```

- [ ] **Step 4: Pass the applied voucher's display title from the cart**

Replace (`cart_screen.dart:1084-1085`, the `_StickyVoucherBar(...)` call):
```dart
                        shippingSelected: _appliedShippingVoucher != null,
                        shippingDiscount: _shippingDiscount,
```
with:
```dart
                        shippingSelected: _appliedShippingVoucher != null,
                        shippingDiscount: _shippingDiscount,
                        shippingText: _appliedShippingVoucher != null
                            ? _shippingVoucherDisplayTitle(
                                _appliedShippingVoucher!)
                            : 'Gratis Ongkir',
```

- [ ] **Step 5: Brand title in checkout `_voucherTypeLabel`**

In `checkout_screen.dart`, replace (`checkout_screen.dart:4404-4406`):
```dart
  if (voucher.isFreeShipping || voucher.isShippingDiscount) {
    return 'Voucher Gratis Ongkir';
  }
```
with:
```dart
  if (voucher.isFreeShipping || voucher.isShippingDiscount) {
    final brand = voucher.brandName?.trim();
    if (voucher.isBrandExclusive && brand != null && brand.isNotEmpty) {
      return 'Gratis Ongkir dari $brand';
    }
    return 'Voucher Gratis Ongkir';
  }
```

- [ ] **Step 6: Analyze both files**

Run: `cd "/c/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/voucher-ongkir-fix/flutter_app" && flutter analyze lib/screens/cart_screen.dart lib/screens/checkout_screen.dart`
Expected: no errors or warnings.

- [ ] **Step 7: Commit**

```bash
git -C "/c/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/voucher-ongkir-fix" add flutter_app/lib/screens/cart_screen.dart flutter_app/lib/screens/checkout_screen.dart
git -C "/c/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/voucher-ongkir-fix" commit -m "feat(voucher): judul 'Gratis Ongkir dari {brand}' utk voucher ongkir brand

Voucher gratis-ongkir brand-eksklusif tampil 'Gratis Ongkir dari {nama
brand}' (nama brand asli, bukan judul admin/kode) di kartu sheet keranjang,
chip voucher bar, dan checkout _voucherTypeLabel. Ongkir publik tetap
'Gratis Ongkir'/judul apa adanya."
```

---

### Task 3: Verification checkpoint

**Files:** none.

- [ ] **Step 1: Full Flutter analyze**

Run: `cd "/c/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/voucher-ongkir-fix/flutter_app" && flutter analyze`
Expected: no NEW errors/warnings from this plan (pre-existing unrelated lints, if any, are out of scope).

- [ ] **Step 2: Confirm synthetic machinery is fully gone**

Run: `cd "/c/Users/USER/Desktop/natalopetshopflutter/.claude/worktrees/voucher-ongkir-fix" && grep -rn "__shipping_free__\|_shippingEstimate\|_shippingVoucherEligible\|_shippingVoucherCode\|showSyntheticShipping\|min. belanja Rp250rb" flutter_app/lib`
Expected: no matches.

- [ ] **Step 3: Manual/emulator smoke test**

Beware the widget-test shimmer-hang gotcha; prefer manual/emulator.
1. Cart with a NON-qualifying product (no matching ongkir voucher) → **no active Gratis Ongkir**: no synthetic card in the sheet, no "Gratis Ongkir" chip in the voucher bar. A brand ongkir voucher stays under "Belum bisa dipakai" titled "Gratis Ongkir dari {brand}".
2. Cart with a product matching a brand ongkir voucher → the voucher is usable, titled "Gratis Ongkir dari {brand}"; picking it shows the chip "Gratis Ongkir dari {brand}".
3. Cart with a real PUBLIC gratis-ongkir voucher (if one exists) → auto-applies, chip shows "Gratis Ongkir".
4. Checkout unaffected: free shipping still auto-applies from the backend; a brand ongkir voucher shows "Gratis Ongkir dari {brand}".

- [ ] **Step 4: If anything fails, stop and fix before completion.**

---

## Non-goals
- Product-detail voucher rail (green badge / generic "Gratis Ongkir" title) — separate follow-up.
- Discount/loyalty voucher titles — unchanged.
- No backend/schema/API change. No changes to how checkout computes shipping.
