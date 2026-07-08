# Cart Condense-to-Pill (Auto-hide Premium) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Saat user scroll (arah apa pun, jari di layar), voucher bar + summary bar melipat jadi satu pil melayang `🎟 N item • Rp X / Hemat Rp Y →` (tap = checkout); mengembang balik HANYA saat jari diangkat & scroll settle, atau instan saat mentok puncak cart.

**Architecture:** Reuse `_chromeController` (340ms easeInOutCubic) yang sudah menggerakkan bar atas + voucher bar. Perubahan: (1) logika pure `chromeActionForScroll` → hide dua-arah, show hanya di puncak; (2) reveal timer HANYA di-arm pada `ScrollEndNotification` (= jari sudah lepas — drag yang ditahan tidak memicu End); (3) `_CartSummaryBar` ikut collapse via `SizeTransition`; (4) widget baru `CartCheckoutPill` sebagai overlay `Positioned` di Stack yang sudah ada, dianimasikan `ReverseAnimation(_chromeAnim)` — satu controller, satu napas, nol animasi liar.

**Tech Stack:** Flutter 3.41.9 / Dart 3.11.5, package `natalo_petshop_flutter`. Test: `flutter_test`.

## Global Constraints

- Animasi: `_chromeAnimDuration = 340ms`, `Curves.easeInOutCubic`, TANPA overshoot/bounce (permintaan user: "jangan liar/cepat").
- Aturan jari: TIDAK ADA reveal selama jari di layar. Pemicu reveal = `ScrollEndNotification` + idle 400ms. Pengecualian: `pixels <= minExtent + 24` (puncak cart) → show instan.
- Hide dipicu drag user saja (`dragDetails != null`) + ambang `|delta| > 4.0` — dua arah.
- Guard dasar dipertahankan: jangan hide saat `pixels >= maxExtent - 8` (hindari clamp menarik konten saat bar collapse).
- Pil: bg `Color(0xFF1E5FBF)` (brand Natalo), radius 999, teks putih; baris hemat warna `Color(0xFFFFD9E1)`; titik hijau `Color(0xFF4ADE80)` hanya jika voucher aktif; baris hemat hanya jika saving > 0. Tap seluruh pil = `_goToCheckout`.
- Pil TIDAK dirender saat `_selectedItems.isEmpty` (checkout disabled).
- Center-sliver invariant: perubahan tinggi chrome bawah aman (viewport-change tidak menggeser konten) — JANGAN sentuh `CartScrollView`/`_onCartScroll` pagination.
- Versi rilis: bump `pubspec.yaml` `1.0.173+213` → `1.0.174+214`.
- Jangan perbaiki 2 golden test yang memang flaky di Windows (`natalo_colors`, `status_pill`) — pre-existing.
- Komentar kode berbahasa Indonesia, gaya file existing.

## File Structure

- `flutter_app/lib/utils/chrome_autohide.dart` — MODIFY: semantik baru (hide dua-arah, show hanya puncak).
- `flutter_app/test/chrome_autohide_test.dart` — MODIFY: test semantik baru.
- `flutter_app/lib/widgets/cart_checkout_pill.dart` — CREATE: widget pil (pure-presentational, string sudah terformat → gampang dites).
- `flutter_app/test/cart_checkout_pill_test.dart` — CREATE: widget test pil.
- `flutter_app/lib/screens/cart_screen.dart` — MODIFY: `_onChromeScroll` (arm reveal hanya di ScrollEnd), summary bar ikut collapse, pill overlay + `_pillAnim`.
- `flutter_app/pubspec.yaml` — MODIFY: version bump.

---

### Task 1: Semantik baru `chromeActionForScroll` (hide dua-arah, show hanya puncak)

**Files:**
- Modify: `flutter_app/lib/utils/chrome_autohide.dart`
- Test: `flutter_app/test/chrome_autohide_test.dart`

**Interfaces:**
- Produces: `ChromeAction chromeActionForScroll({required double scrollDelta, required double pixels, required double minExtent, required double maxExtent, required bool currentlyVisible, double threshold = 4.0})` — signature TIDAK berubah, hanya semantik. Task 3 memanggilnya dari `_onChromeScroll`.

- [ ] **Step 1: Tulis ulang test ke semantik baru (failing)**

Ganti seluruh isi `flutter_app/test/chrome_autohide_test.dart` dengan:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/utils/chrome_autohide.dart';

// Semantik condense-pill: chrome melipat saat drag ARAH APA PUN di tengah
// list; TIDAK pernah show dari gerakan drag — reveal ditangani idle timer
// (ScrollEnd = jari lepas). Satu-satunya show dari gerakan: mentok puncak.
void main() {
  group('chromeActionForScroll (condense-pill)', () {
    test('drag ke bawah di tengah + chrome tampil → hide', () {
      expect(
        chromeActionForScroll(
          scrollDelta: 20,
          pixels: 100,
          minExtent: -500,
          maxExtent: 500,
          currentlyVisible: true,
        ),
        ChromeAction.hide,
      );
    });

    test('drag ke ATAS di tengah + chrome tampil → hide (dua arah)', () {
      expect(
        chromeActionForScroll(
          scrollDelta: -20,
          pixels: 100,
          minExtent: -500,
          maxExtent: 500,
          currentlyVisible: true,
        ),
        ChromeAction.hide,
      );
    });

    test('drag ke atas saat chrome hidden → none (reveal = idle timer, '
        'bukan gerakan)', () {
      expect(
        chromeActionForScroll(
          scrollDelta: -20,
          pixels: 100,
          minExtent: -500,
          maxExtent: 500,
          currentlyVisible: false,
        ),
        ChromeAction.none,
      );
    });

    test('mentok puncak + chrome hidden → show instan', () {
      expect(
        chromeActionForScroll(
          scrollDelta: -20,
          pixels: -490,
          minExtent: -500,
          maxExtent: 500,
          currentlyVisible: false,
        ),
        ChromeAction.show,
      );
    });

    test('di puncak + chrome sudah tampil → none (tak retrigger)', () {
      expect(
        chromeActionForScroll(
          scrollDelta: 20,
          pixels: -490,
          minExtent: -500,
          maxExtent: 500,
          currentlyVisible: true,
        ),
        ChromeAction.none,
      );
    });

    test('tepat di dasar → jangan hide (hindari clamp menarik konten)', () {
      expect(
        chromeActionForScroll(
          scrollDelta: 20,
          pixels: 498,
          minExtent: -500,
          maxExtent: 500,
          currentlyVisible: true,
        ),
        ChromeAction.none,
      );
    });

    test('gerakan mikro (|delta| < threshold) → none, dua arah', () {
      for (final delta in [2.0, -2.0]) {
        expect(
          chromeActionForScroll(
            scrollDelta: delta,
            pixels: 100,
            minExtent: -500,
            maxExtent: 500,
            currentlyVisible: true,
          ),
          ChromeAction.none,
        );
      }
    });

    test('drag saat sudah hidden di tengah → none', () {
      expect(
        chromeActionForScroll(
          scrollDelta: 20,
          pixels: 100,
          minExtent: -500,
          maxExtent: 500,
          currentlyVisible: false,
        ),
        ChromeAction.none,
      );
    });
  });
}
```

- [ ] **Step 2: Jalankan test — harus FAIL**

Run: `cd flutter_app && flutter test test/chrome_autohide_test.dart`
Expected: FAIL — minimal test "drag ke ATAS ... → hide" dan "mentok puncak ... → show instan" merah (semantik lama: scroll-up = show).

- [ ] **Step 3: Tulis implementasi baru**

Ganti seluruh isi `flutter_app/lib/utils/chrome_autohide.dart` dengan:

```dart
/// Aksi auto-hide "chrome" keranjang (baris "N terpilih" atas + voucher bar
/// + summary bar bawah yang melipat jadi pil) untuk satu update scroll
/// drag-driven. Dipisah jadi fungsi murni supaya keputusannya bisa dites
/// tanpa widget.
enum ChromeAction { hide, show, none }

/// Semantik condense-pill: gerakan drag ARAH APA PUN (|delta| > [threshold])
/// di tengah list → hide (melipat jadi pil). Reveal TIDAK pernah dipicu
/// gerakan — itu urusan idle timer yang di-arm saat ScrollEnd (= jari sudah
/// diangkat). Satu-satunya show dari sini: mentok PUNCAK cart
/// (`pixels <= minExtent + 24`) → chrome langsung mengembang karena user
/// sedang melihat item cart paling atas.
///
/// Tidak hide saat tepat di DASAR (`pixels >= maxExtent - 8`) supaya
/// collapse bar tidak memicu clamp yang menarik konten.
ChromeAction chromeActionForScroll({
  required double scrollDelta,
  required double pixels,
  required double minExtent,
  required double maxExtent,
  required bool currentlyVisible,
  double threshold = 4.0,
}) {
  if (pixels <= minExtent + 24) {
    return currentlyVisible ? ChromeAction.none : ChromeAction.show;
  }
  if (scrollDelta.abs() > threshold &&
      currentlyVisible &&
      pixels < maxExtent - 8) {
    return ChromeAction.hide;
  }
  return ChromeAction.none;
}
```

- [ ] **Step 4: Jalankan test — harus PASS**

Run: `cd flutter_app && flutter test test/chrome_autohide_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/utils/chrome_autohide.dart flutter_app/test/chrome_autohide_test.dart
git commit -m "feat(cart): chromeActionForScroll semantik condense-pill — hide dua-arah, show hanya di puncak"
```

---

### Task 2: Widget `CartCheckoutPill`

**Files:**
- Create: `flutter_app/lib/widgets/cart_checkout_pill.dart`
- Test: `flutter_app/test/cart_checkout_pill_test.dart`

**Interfaces:**
- Produces: `class CartCheckoutPill extends StatelessWidget` dengan konstruktor `CartCheckoutPill({super.key, required int quantity, required String totalText, String? savingText, required bool voucherActive, required VoidCallback onTap})`. String SUDAH terformat oleh pemanggil (Task 3 memformat pakai `formatRupiah` yang sudah diimport `cart_screen.dart`) — widget ini bebas dependensi util format → gampang dites.

- [ ] **Step 1: Tulis widget test (failing)**

Buat `flutter_app/test/cart_checkout_pill_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:natalo_petshop_flutter/widgets/cart_checkout_pill.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('render qty + total + hemat + arah panah', (tester) async {
    await tester.pumpWidget(_wrap(CartCheckoutPill(
      quantity: 3,
      totalText: 'Rp 312.000',
      savingText: 'Hemat Rp 41.000',
      voucherActive: true,
      onTap: () {},
    )));
    expect(find.text('3 item • Rp 312.000'), findsOneWidget);
    expect(find.text('Hemat Rp 41.000'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    // Voucher aktif → ikon tiket tampil.
    expect(
      find.byIcon(Icons.confirmation_number_rounded),
      findsOneWidget,
    );
  });

  testWidgets('tanpa saving & tanpa voucher → baris hemat + tiket hilang',
      (tester) async {
    await tester.pumpWidget(_wrap(CartCheckoutPill(
      quantity: 1,
      totalText: 'Rp 63.000',
      savingText: null,
      voucherActive: false,
      onTap: () {},
    )));
    expect(find.text('1 item • Rp 63.000'), findsOneWidget);
    expect(find.textContaining('Hemat'), findsNothing);
    expect(
      find.byIcon(Icons.confirmation_number_rounded),
      findsNothing,
    );
  });

  testWidgets('tap seluruh pil memanggil onTap', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_wrap(CartCheckoutPill(
      quantity: 2,
      totalText: 'Rp 100.000',
      savingText: null,
      voucherActive: false,
      onTap: () => tapped++,
    )));
    await tester.tap(find.byType(CartCheckoutPill));
    expect(tapped, 1);
  });
}
```

- [ ] **Step 2: Jalankan test — harus FAIL (file widget belum ada)**

Run: `cd flutter_app && flutter test test/cart_checkout_pill_test.dart`
Expected: FAIL compile — `cart_checkout_pill.dart` not found.

- [ ] **Step 3: Buat widget**

Buat `flutter_app/lib/widgets/cart_checkout_pill.dart`:

```dart
import 'package:flutter/material.dart';

// Warna pil mengikuti brand Natalo + turunan yang kebaca di atas biru.
const _pillBlue = Color(0xFF1E5FBF);
const _pillSavingPink = Color(0xFFFFD9E1);
const _pillVoucherDotGreen = Color(0xFF4ADE80);

/// Pil melayang pengganti voucher bar + summary bar saat user scroll
/// (pola "condense": CTA checkout tidak pernah hilang dari layar).
/// Konten: [ikon tiket + titik hijau jika voucher aktif] "N item • Rp X"
/// (+ "Hemat Rp Y" bila ada) [lingkaran panah]. Tap SELURUH pil = checkout.
/// String total/hemat sudah diformat pemanggil — widget ini presentasional
/// murni supaya gampang dites.
class CartCheckoutPill extends StatelessWidget {
  final int quantity;
  final String totalText;
  final String? savingText;
  final bool voucherActive;
  final VoidCallback onTap;

  const CartCheckoutPill({
    super.key,
    required this.quantity,
    required this.totalText,
    this.savingText,
    required this.voucherActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _pillBlue,
      borderRadius: BorderRadius.circular(999),
      elevation: 8,
      shadowColor: _pillBlue.withValues(alpha: 0.38),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (voucherActive) ...[
                _VoucherDotIcon(),
                const SizedBox(width: 10),
              ],
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$quantity item • $totalText',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (savingText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        savingText!,
                        style: const TextStyle(
                          color: _pillSavingPink,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 11),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ikon tiket kecil dengan titik hijau = penanda "voucher aktif kepasang"
/// tetap terlihat walau voucher bar sedang terlipat.
class _VoucherDotIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.confirmation_number_rounded,
              color: _pillSavingPink,
              size: 15,
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: _pillVoucherDotGreen,
                shape: BoxShape.circle,
                border: Border.all(color: _pillBlue, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Jalankan test — harus PASS**

Run: `cd flutter_app && flutter test test/cart_checkout_pill_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/widgets/cart_checkout_pill.dart flutter_app/test/cart_checkout_pill_test.dart
git commit -m "feat(cart): widget CartCheckoutPill — pil checkout melayang saat chrome terlipat"
```

---

### Task 3: Wiring di `cart_screen.dart` — reveal hanya saat jari lepas + summary collapse + pill overlay

**Files:**
- Modify: `flutter_app/lib/screens/cart_screen.dart` (import; field animasi ±line 73-78; `_onChromeScroll` ±line 330-351; build body ±line 843-984)

**Interfaces:**
- Consumes: `chromeActionForScroll` (Task 1, semantik baru — kode panggil TIDAK berubah), `CartCheckoutPill` (Task 2).
- Consumes (sudah ada di file): `_grandTotal`, `_totalVoucherSaving`, `_selectedQuantity`, `_selectedItems`, `_goToCheckout`, `formatRupiah`, `_appliedDiscountVoucher`, `_appliedLoyaltyVoucher`, `_appliedShippingVoucher`.

- [ ] **Step 1: Tambah import**

Di blok import `cart_screen.dart`, tambahkan (urut alfabet dengan import `../widgets/` lain):

```dart
import '../widgets/cart_checkout_pill.dart';
```

- [ ] **Step 2: Tambah animasi pil (kebalikan chrome)**

Setelah deklarasi `_chromeSlideAnim` (±line 76), tambah field:

```dart
  // Pil checkout = kebalikan chrome: muncul saat chrome terlipat. Satu
  // controller yang sama → morph serempak satu napas, tanpa animasi liar.
  late final Animation<double> _pillAnim;
  late final Animation<Offset> _pillSlideAnim;
```

Di `initState()` setelah inisialisasi `_chromeSlideAnim` (±line 130), tambah:

```dart
    _pillAnim = ReverseAnimation(_chromeAnim);
    // Slide halus dari bawah TANPA overshoot (easeInOutCubic dari parent).
    _pillSlideAnim = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(_pillAnim);
```

- [ ] **Step 3: Ubah `_onChromeScroll` — reveal HANYA di ScrollEnd**

Ganti method `_onChromeScroll` (±line 330-351) menjadi:

```dart
  // ── Auto-hide chrome (drag-driven, condense-pill) ──
  bool _onChromeScroll(ScrollNotification notification) {
    // Hanya bereaksi ke drag USER (dragDetails != null) — jumpTo anchor awal &
    // scroll programatik lain tak boleh salah-sembunyikan chrome.
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      // Jari masih gerak → batalkan reveal yang mungkin ter-arm; chrome tidak
      // boleh mengembang selama jari di layar (aturan finger-up).
      _chromeIdleTimer?.cancel();
      final metrics = notification.metrics;
      final action = chromeActionForScroll(
        scrollDelta: notification.scrollDelta ?? 0,
        pixels: metrics.pixels,
        minExtent: metrics.minScrollExtent,
        maxExtent: metrics.maxScrollExtent,
        currentlyVisible: _chromeVisible,
      );
      if (action == ChromeAction.hide) _setChromeVisible(false);
      if (action == ChromeAction.show) _setChromeVisible(true);
    }
    // ScrollEnd = drag dilepas / ballistic selesai → jari SUDAH diangkat.
    // Drag yang ditahan diam TIDAK memicu End → chrome tetap terlipat
    // selama jari nempel, persis aturan lama onPointerUp.
    if (notification is ScrollEndNotification) {
      _armIdleReveal();
    }
    return false;
  }
```

(Perubahan vs sekarang: cabang `ScrollUpdateNotification ||` dihapus dari kondisi `_armIdleReveal`, dan `_chromeIdleTimer?.cancel()` ditambah di jalur drag.)

- [ ] **Step 4: Summary bar ikut collapse + pill overlay di Stack**

Dua edit di build body (±line 930-981):

**4a.** Bungkus `_CartSummaryBar` dengan `SizeTransition` — ganti:

```dart
                _CartSummaryBar(
                  grandTotal: _grandTotal,
                  totalSaving: _totalVoucherSaving,
                  selectedQuantity: _selectedQuantity,
                  disabled: _selectedItems.isEmpty,
                  onCheckout: _goToCheckout,
                ),
```

menjadi:

```dart
                // Summary bar ikut melipat bersama voucher bar — CTA checkout
                // pindah ke pil melayang selama scroll (pola condense).
                SizeTransition(
                  sizeFactor: _chromeAnim,
                  axisAlignment: 1,
                  child: _CartSummaryBar(
                    grandTotal: _grandTotal,
                    totalSaving: _totalVoucherSaving,
                    selectedQuantity: _selectedQuantity,
                    disabled: _selectedItems.isEmpty,
                    onCheckout: _goToCheckout,
                  ),
                ),
```

**4b.** Di dalam `Stack` (setelah `Positioned` overlay baris "N terpilih", sebelum `],` penutup children Stack ±line 951), tambah:

```dart
                      // Pil checkout melayang — muncul saat chrome terlipat
                      // (ReverseAnimation). CTA + total + hemat tidak pernah
                      // hilang dari layar. Tap seluruh pil = checkout.
                      if (_selectedItems.isNotEmpty)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 12,
                          child: IgnorePointer(
                            ignoring: _chromeVisible,
                            child: SlideTransition(
                              position: _pillSlideAnim,
                              child: FadeTransition(
                                opacity: _pillAnim,
                                child: Center(
                                  child: CartCheckoutPill(
                                    quantity: _selectedQuantity,
                                    totalText: formatRupiah(_grandTotal),
                                    savingText: _totalVoucherSaving > 0
                                        ? 'Hemat ${formatRupiah(_totalVoucherSaving)}'
                                        : null,
                                    voucherActive:
                                        _appliedDiscountVoucher != null ||
                                            _appliedLoyaltyVoucher != null ||
                                            _appliedShippingVoucher,
                                    onTap: _goToCheckout,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
```

- [ ] **Step 5: Analyze + format**

Run: `cd flutter_app && dart format lib/screens/cart_screen.dart lib/widgets/cart_checkout_pill.dart lib/utils/chrome_autohide.dart test/chrome_autohide_test.dart test/cart_checkout_pill_test.dart && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Jalankan seluruh test suite**

Run: `cd flutter_app && flutter test`
Expected: Semua pass KECUALI 2 golden pre-existing (`natalo_colors_test.dart`, `status_pill_test.dart`) — jumlah pass ≥ 50 (47 existing + 3 pill baru; chrome_autohide tetap 8).

- [ ] **Step 7: Commit**

```bash
git add flutter_app/lib/screens/cart_screen.dart
git commit -m "feat(cart): condense-to-pill — voucher+summary melipat jadi pil checkout, reveal hanya saat jari lepas"
```

---

### Task 4: Version bump + PR

**Files:**
- Modify: `flutter_app/pubspec.yaml:4`

- [ ] **Step 1: Bump versi**

Ganti `version: 1.0.173+213` → `version: 1.0.174+214`.

- [ ] **Step 2: Commit + push + PR**

```bash
git add flutter_app/pubspec.yaml
git commit -m "chore: bump versi 1.0.174+214"
git push -u origin claude/cart-jump-diagnostic
gh pr create --title "feat(cart): condense-to-pill auto-hide premium (v1.0.174)" --body "..."
```

(Isi body PR: ringkasan desain condense-pill + aturan jari + link plan ini. TUNGGU perintah "merge" dari user.)

- [ ] **Step 3: Handoff verifikasi device**

Minta user build dari branch → cek Versi 1.0.174 → tes: scroll dua arah (melipat), tahan jari (tetap pil), lepas jari (mengembang 340ms halus), mentok puncak (instan mengembang), tap pil (ke checkout), tanpa voucher (titik hijau & hemat hilang).
