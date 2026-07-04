# Shoppable Video — TikTok Shop Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menaikkan pengalaman shoppable video di feed ke level TikTok Shop — kartu produk anchor, akses keranjang, dan konsistensi commerce — tanpa perubahan backend.

**Architecture:** Semua perubahan di satu file `flutter_app/lib/screens/feed_screen.dart` (mega-file existing; menambah/mengganti widget inline mengikuti pola file). Reuse handler & data yang sudah ada (`_feedProductPricing`, `formatRupiah`, `cartStore`, `_quickAddProduct`, route `/cart`). Tidak ada file baru, model, atau migrasi.

**Tech Stack:** Flutter (Dart), `cached_network_image`, `dart:ui` blur, `cartStore` (ChangeNotifier).

## Global Constraints

- **Flutter-only.** Tidak boleh sentuh backend/Prisma/model. Tidak ada migrasi.
- **Sistem warna commerce:** oranye `#FF7A00` (const `_feedCommerceOrange`) HANYA untuk aksi tambah-keranjang baru (tombol kartu anchor + cart-pill rail). Tombol "Beli Sekarang"/"Beli" tetap biru brand (jangan diubah — keputusan sadar, override desain spec yang menyebut popup oranye).
- **Route keranjang:** `/cart` via `Navigator.of(context).pushNamed('/cart')`.
- **Cart count:** `cartStore.totalQuantity`, tampil cap `'99+'`, badge hanya jika `> 0`.
- **Gate otomatis per task:** `cd flutter_app && flutter analyze lib/screens/feed_screen.dart` → **No issues found**. (Codebase ini tidak punya widget test untuk feed; verifikasi fungsional = analyze + cek manual di device. Jangan mengarang widget test baru.)
- **Commit per task.** Bump `pubspec.yaml` version hanya di task terakhir.
- Ikuti pola style/const feed yang ada (`_feedActionIconSize=32`, `_feedActionForegroundColor`, `_feedActionShadowColor`, `_feedActionItemSpacing=18`).

---

### Task 1: Fix ikon keranjang di header sheet "Lihat Produk"

Bug: ikon `Icons.shopping_bag_outlined` (harusnya keranjang) + tidak tappable.

**Files:**
- Modify: `flutter_app/lib/screens/feed_screen.dart` (header `_FeedTaggedProductsSheet`, sekitar `:4965-5027`)

**Interfaces:**
- Consumes: `cartStore.totalQuantity`, route `/cart`.
- Produces: — (perubahan lokal).

- [ ] **Step 1: Ganti blok ikon keranjang jadi tappable + ikon keranjang**

Cari blok yang diawali komentar `// Cart icon dengan badge count — tap → close sheet` (sekitar `:4965`) sampai penutup `AnimatedBuilder` (`},` di `:5027`, tepat sebelum `const SizedBox(width: 8),`). Ganti SELURUH blok itu dengan:

```dart
                    // Cart icon dengan badge count — tap → buka Keranjang.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        final nav = Navigator.of(context);
                        nav.pop();
                        nav.pushNamed('/cart');
                      },
                      child: AnimatedBuilder(
                        animation: cartStore,
                        builder: (context, _) {
                          final count = cartStore.totalQuantity;
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF1E5BFF),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.shopping_cart_outlined,
                                  color: Color(0xFF1E5BFF),
                                  size: 20,
                                ),
                              ),
                              if (count > 0)
                                Positioned(
                                  top: -4,
                                  right: -4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFA726),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: const Color(0xFF0B0D12),
                                        width: 1.4,
                                      ),
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 18,
                                      minHeight: 18,
                                    ),
                                    child: Text(
                                      count > 99 ? '99+' : '$count',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
```

- [ ] **Step 2: Analyze**

Run: `cd flutter_app && flutter analyze lib/screens/feed_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add flutter_app/lib/screens/feed_screen.dart
git commit -m "fix(feed): ikon keranjang sheet produk — glyph keranjang + tappable ke /cart"
```

Manual (device, nanti saat build): buka video shoppable → tap chip → sheet → tap ikon keranjang kanan-atas → sheet tertutup & halaman Keranjang terbuka.

---

### Task 2: Buang badge "Khusus Video"

Badge muncul tanpa syarat di 3 lokasi → tak bermakna. Hapus pemakaian + definisi class.

**Files:**
- Modify: `flutter_app/lib/screens/feed_screen.dart` (`:5136`, `:5283`, `:6616`, hapus class `:5143-5169`)

**Interfaces:**
- Consumes: — . Produces: — .

- [ ] **Step 1: Hapus 3 pemakaian `const _KhususVideoBadge()`**

Di `_VideoPromoBanner` (`:5136`) — hapus baris `const _KhususVideoBadge(),` (baris terakhir sebelum penutup `Row`). Setelah hapus, `Row` berakhir di `Expanded(...)`.

Di `_FeedTaggedProductCard` (`:5283`) — dalam `Wrap` badges, hapus baris `const _KhususVideoBadge(),`. `Wrap` menyisakan `if (pricing.hasPromo) Container(...)` saja (Wrap dengan 0/1 child valid).

Di `_EndOfVideoProductCta` (`:6616`) — dalam `Wrap` badges, hapus baris `const _KhususVideoBadge(),`. Sama, sisakan promo pill saja.

- [ ] **Step 2: Hapus definisi class `_KhususVideoBadge`**

Hapus blok `:5143-5169` — komentar doc `/// Badge \`Khusus Video\` putih ...` sampai penutup class `_KhususVideoBadge` (`}` sebelum `class _FeedTaggedProductCard`).

- [ ] **Step 3: Analyze**

Run: `cd flutter_app && flutter analyze lib/screens/feed_screen.dart`
Expected: `No issues found!` (kalau ada `unused` untuk `_KhususVideoBadge`, berarti Step 2 belum kena — pastikan class terhapus).

- [ ] **Step 4: Commit**

```bash
git add flutter_app/lib/screens/feed_screen.dart
git commit -m "refactor(feed): buang badge 'Khusus Video' (muncul di semua produk, tak bermakna)"
```

---

### Task 3: Kartu produk anchor (ganti chip teks berputar)

Ganti `_ProductLinkChip` (chip teks) dengan kartu: thumbnail + nama + harga(coret) + tombol keranjang oranye. Badge Flash Sale/Diskon di atas kartu.

**Files:**
- Modify: `flutter_app/lib/screens/feed_screen.dart` — tambah const `_feedCommerceOrange`; ganti class `_ProductLinkChip` (`:4751-4889`) jadi `_ProductAnchorCard` + `_AnchorCartButton`; update 2 call site (`:1818`, `:4700`).

**Interfaces:**
- Consumes: `_feedProductPricing(FeedProductLink)`, `formatRupiah(int)`, `CachedNetworkImage`, `ui.ImageFilter`.
- Produces: `_ProductAnchorCard({required List<FeedProductLink> products, required FeedProductLink featuredProduct, required int featuredIndex, required VoidCallback onTap, VoidCallback? onQuickAdd})` — signature sama persis dgn `_ProductLinkChip` lama (call site cuma ganti nama class).

- [ ] **Step 1: Tambah const warna commerce**

Setelah baris `const _feedActionRailRightInset = 4.0;` (`:57`), tambah:

```dart
// Aksen commerce oranye — dipakai untuk aksi tambah-keranjang (kartu anchor
// + cart-pill rail). Tombol "Beli" utama tetap biru brand.
const _feedCommerceOrange = Color(0xFFFF7A00);
```

- [ ] **Step 2: Ganti class `_ProductLinkChip` (`:4751-4889`) dengan `_ProductAnchorCard` + `_AnchorCartButton`**

Ganti seluruh class `_ProductLinkChip` (dari `class _ProductLinkChip extends StatelessWidget {` sampai `}` penutupnya di `:4889`) dengan:

```dart
class _ProductAnchorCard extends StatelessWidget {
  final List<FeedProductLink> products;
  final FeedProductLink featuredProduct;
  final int featuredIndex;
  final VoidCallback onTap;
  final VoidCallback? onQuickAdd;

  const _ProductAnchorCard({
    required this.products,
    required this.featuredProduct,
    required this.featuredIndex,
    required this.onTap,
    this.onQuickAdd,
  });

  @override
  Widget build(BuildContext context) {
    final product = featuredProduct;
    final pricing = _feedProductPricing(product);
    final badgeText = product.hasActiveDiscount
        ? (product.isFlashSale
            ? 'Flash Sale ${product.discountPercent}%'
            : 'Diskon ${product.discountPercent}%')
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (badgeText != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFF4D4F),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badgeText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.52),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.all(7),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(9),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 40,
                                height: 40,
                                child: (product.imageUrl != null &&
                                        product.imageUrl!.isNotEmpty)
                                    ? CachedNetworkImage(
                                        imageUrl: product.imageUrl!,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => Container(
                                          color: Colors.white
                                              .withValues(alpha: 0.08),
                                        ),
                                        errorWidget: (_, __, ___) => Container(
                                          color: Colors.white
                                              .withValues(alpha: 0.08),
                                          child: const Icon(
                                            Icons.image_not_supported_outlined,
                                            color: Colors.white54,
                                            size: 18,
                                          ),
                                        ),
                                      )
                                    : Container(
                                        color: Colors.white
                                            .withValues(alpha: 0.08),
                                        child: const Icon(
                                          Icons.shopping_bag_outlined,
                                          color: Colors.white54,
                                          size: 18,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 260),
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                        opacity: animation, child: child),
                                child: Column(
                                  key: ValueKey(product.id),
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        height: 1.15,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          formatRupiah(pricing.displayPrice),
                                          style: const TextStyle(
                                            color: Color(0xFFFF5A5F),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w900,
                                            height: 1,
                                          ),
                                        ),
                                        if (pricing.hasPromo) ...[
                                          const SizedBox(width: 5),
                                          Text(
                                            formatRupiah(pricing.originalPrice),
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.5),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              height: 1,
                                              decoration:
                                                  TextDecoration.lineThrough,
                                              decorationColor: Colors.white
                                                  .withValues(alpha: 0.5),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _AnchorCartButton(onTap: onQuickAdd),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnchorCartButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _AnchorCartButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _feedCommerceOrange,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: const SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            Icons.add_shopping_cart_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Update call site di `_PhotoCarouselPostView` (`:1818`)**

Ganti `_ProductLinkChip(` → `_ProductAnchorCard(` (argumen sama persis: `products`, `featuredProduct`, `featuredIndex`, `onTap`, `onQuickAdd`).

- [ ] **Step 4: Update call site di `_ProductCommerceOverlayGroup` (`:4700`)**

Ganti `_ProductLinkChip(` → `_ProductAnchorCard(` (argumen sama persis).

- [ ] **Step 5: Analyze**

Run: `cd flutter_app && flutter analyze lib/screens/feed_screen.dart`
Expected: `No issues found!` (kalau muncul error `_ProductLinkChip` tak terdefinisi → ada call site yang belum diganti).

- [ ] **Step 6: Commit**

```bash
git add flutter_app/lib/screens/feed_screen.dart
git commit -m "feat(feed): kartu produk anchor (gambar + harga + keranjang oranye) ganti chip teks"
```

Manual: video/photo shoppable menampilkan kartu (bukan chip); tap badan → sheet; tap tombol oranye → produk masuk keranjang (toast existing).

---

### Task 4: Cart-pill di action rail (video shoppable saja)

Ikon keranjang + badge jumlah di rail, tap → `/cart`. Hanya saat `products.isNotEmpty`.

**Files:**
- Modify: `flutter_app/lib/screens/feed_screen.dart` — tambah class `_ReelsCartGlyph`; sisipkan `_ReelsAction` cart di 2 rail (`_PhotoCarouselPostView` `:1787`, `_FeedPostView` `:3268`).

**Interfaces:**
- Consumes: `_ReelsAction`, `cartStore.totalQuantity`, `_feedCommerceOrange`, `_feedActionIconSize`, `_feedActionForegroundColor`, `_feedActionShadowColor`, route `/cart`.
- Produces: `_ReelsCartGlyph({required int count})`.

- [ ] **Step 1: Tambah class `_ReelsCartGlyph`**

Tepat SETELAH penutup class `_ReelsMoreGlyph` (`:4592` dst — cari `class _ReelsMoreGlyph` lalu `}` penutupnya), tambah:

```dart
class _ReelsCartGlyph extends StatelessWidget {
  final int count;

  const _ReelsCartGlyph({required this.count});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(
          Icons.shopping_cart,
          color: _feedActionForegroundColor,
          size: _feedActionIconSize,
          shadows: [
            Shadow(
              color: _feedActionShadowColor,
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        if (count > 0)
          Positioned(
            top: -5,
            right: -7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: _feedCommerceOrange,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 2: Sisipkan cart action di rail `_PhotoCarouselPostView` (`:1787`)**

Di rail (Column of `_ReelsAction`), TEPAT SEBELUM blok `// More actions (Report/Block)` + `_ReelsAction(iconChild: const _ReelsMoreGlyph(), ...)` (`:1787-1792`), sisipkan:

```dart
                      if (products.isNotEmpty) ...[
                        const SizedBox(height: _feedActionItemSpacing),
                        AnimatedBuilder(
                          animation: cartStore,
                          builder: (context, _) => _ReelsAction(
                            iconChild:
                                _ReelsCartGlyph(count: cartStore.totalQuantity),
                            onTap: () =>
                                Navigator.of(context).pushNamed('/cart'),
                          ),
                        ),
                      ],
```

- [ ] **Step 3: Sisipkan cart action di rail `_FeedPostView` (`:3268`)**

Cari rail video (Column dgn `_ReelsHeartGlyph`/`_ReelsCommentGlyph`/`_ReelsShareGlyph`, sekitar `:3248-3278`). TEPAT SEBELUM blok komentar `// ── More actions (Report / Block) ──` + `_ReelsAction(iconChild: const _ReelsMoreGlyph(), onTap: _onMoreActions)`, sisipkan blok yang SAMA seperti Step 2:

```dart
                                  if (products.isNotEmpty) ...[
                                    const SizedBox(
                                        height: _feedActionItemSpacing),
                                    AnimatedBuilder(
                                      animation: cartStore,
                                      builder: (context, _) => _ReelsAction(
                                        iconChild: _ReelsCartGlyph(
                                            count: cartStore.totalQuantity),
                                        onTap: () => Navigator.of(context)
                                            .pushNamed('/cart'),
                                      ),
                                    ),
                                  ],
```

Catatan: `products` harus dalam scope di rail video. Verifikasi variabel `products` (List<FeedProductLink>) sudah ada di `build` `_FeedPostView` (dipakai di bottom info `if (products.isNotEmpty)`). Kalau namanya beda, samakan.

- [ ] **Step 4: Analyze**

Run: `cd flutter_app && flutter analyze lib/screens/feed_screen.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add flutter_app/lib/screens/feed_screen.dart
git commit -m "feat(feed): cart-pill di action rail video shoppable, tap ke /cart"
```

Manual: video shoppable → rail punya ikon keranjang + badge jumlah live; video non-shoppable → tidak ada cart-pill; tap → halaman Keranjang.

---

### Task 5: Verifikasi penuh + bump versi

**Files:**
- Modify: `flutter_app/pubspec.yaml` (version)

- [ ] **Step 1: Analyze penuh (lintas-file)**

Run: `cd flutter_app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Bump versi**

Di `flutter_app/pubspec.yaml`, naikkan `version:` satu patch+build (mis. dari `1.0.155+195` → `1.0.156+196`).

- [ ] **Step 3: Commit**

```bash
git add flutter_app/pubspec.yaml
git commit -m "chore: bump versi untuk shoppable video TikTok Shop parity"
```

- [ ] **Step 4: Push**

```bash
git push
```

Catatan deploy: Flutter-only → cukup build Codemagic; tidak butuh deploy Vercel.

---

## Self-Review (penulis plan)

**Spec coverage:**
- Kartu produk anchor → Task 3 ✅
- Cart-pill di rail → Task 4 ✅
- Fix ikon keranjang sheet → Task 1 ✅
- Poles kartu sheet + buang "Khusus Video" → Task 2 ✅ (poles = pembersihan badge; harga coret/rating sudah ada, tak diubah)
- Popup akhir video (opsi B, dipertahankan) → tidak dihapus; badge "Khusus Video"-nya dibersihkan di Task 2. **Deviasi sadar:** tombol "Beli" popup TETAP biru (bukan oranye seperti garis spec) — lihat Global Constraints; brand-consistency, sudah ada komentar spec biru di kode.

**Placeholder scan:** tidak ada TBD/TODO; semua step berisi kode/aksi konkret.

**Type consistency:** `_ProductAnchorCard` memakai signature identik `_ProductLinkChip` lama (products/featuredProduct/featuredIndex/onTap/onQuickAdd) → call site cuma rename. `_ReelsCartGlyph({required int count})` konsisten dipakai di Task 4. `_feedCommerceOrange` didefinisikan Task 3 Step 1, dipakai Task 3 & Task 4 (Task 3 dijalankan lebih dulu → aman).
