# Design — Variant picker in-sheet untuk sheet Links (Postingan video)

Tanggal: 2026-07-17
Status: Disetujui (menunggu review spec)

## Masalah

Di sheet "Links" (grid produk tag) pada video Postingan (`feed_video_post_view.dart`), tap ikon keranjang pada produk **bervarian** memanggil `_addFeedLinkToCart` → `_openProductLinkDetail(link)`, yang fetch `Product` lalu `Navigator.pushNamed(context, '/product-detail', ...)`. User keluar total dari video/postingan ke halaman detail produk untuk sekadar memilih varian.

Karena mayoritas produk petshop punya varian (ukuran kemasan, rasa), ini jadi gap terbesar dibanding pola TikTok Shop (produk-tag → overlay/sheet in-app, bukan navigasi keluar) — dikonfirmasi via riset: TikTok Shop membuka product page sebagai overlay/sheet di dalam app, dengan variant picker standar di situ, tanpa keluar dari TikTok.

Produk TANPA varian sudah benar: `cartStore.addProduct(product, quantity)` langsung + toast, tanpa navigasi.

## Tujuan

1. Tap ikon keranjang pada produk bervarian di sheet Links membuka **sheet varian kedua** (stack di atas sheet Links), bukan navigasi ke halaman detail penuh.
2. Setelah pilih varian lengkap + tekan "Tambah ke Keranjang" di sheet baru: tambah ke cart, tutup KEDUA sheet, kembali ke video, tampilkan toast, video resume — video TIDAK pernah keluar dari layar Postingan.
3. Tidak menduplikasi mesin pencocokan varian yang sudah ada (`_CartVariantPickerSheet` di `cart_screen.dart`) — ekstrak jadi widget bersama yang dipakai baik oleh Cart maupun sheet Links baru ini.

## Non-tujuan

- Tap foto/nama produk (bukan ikon keranjang) di sheet Links — TETAP tidak berubah, tetap navigasi ke halaman detail produk penuh (`onOpenProduct`/`_openProductLinkDetail`).
- Perilaku add-to-cart produk TANPA varian — tidak berubah.
- Perilaku `_CartVariantPickerSheet` yang sudah ada di halaman Cart — hanya di-refactor internalnya (jadi wrapper tipis di atas widget bersama baru), perilaku/tampilan untuk user Cart tidak berubah.
- Logika pause/resume video saat sheet Links terbuka — sudah benar (video pause saat `onOpened`, resume saat `onClosed`), tidak disentuh; sheet varian baru numpang di siklus hidup yang sama (parent Links sheet tetap terbuka secara logis selama sheet varian di atasnya terbuka, jadi video tetap pause).

## Pendekatan

### 1. Ekstrak widget bersama — `lib/widgets/product_variant_picker_sheet.dart` (baru)

Pindahkan mesin `_CartVariantPickerSheet` (`cart_screen.dart:1814-2116`, termasuk `_matchedVariant`, `_isOptionAvailable`, `_onSelect`, UI summary+chips+tombol) ke widget publik baru dengan API berbasis `Product` (bukan `CartItem`):

```dart
class ProductVariantPickerSheet extends StatefulWidget {
  const ProductVariantPickerSheet({
    super.key,
    required this.productSlug,
    this.preselectedVariant, // null untuk alur baru (feed); variant existing untuk alur Cart (ganti varian)
    required this.confirmLabel, // "Simpan" (Cart) vs "Tambah ke Keranjang" (feed)
    required this.confirmColor, // hijau (Cart, sama seperti sekarang) vs biru brand (feed, sesuai mockup)
  });

  final String productSlug;
  final ProductVariant? preselectedVariant;
  final String confirmLabel;
  final Color confirmColor;

  static Future<ProductVariantPickResult?> show(
    BuildContext context, {
    required String productSlug,
    ProductVariant? preselectedVariant,
    required String confirmLabel,
    required Color confirmColor,
  });
}

class ProductVariantPickResult {
  const ProductVariantPickResult({required this.product, required this.variant});
  final Product product;
  final ProductVariant variant;
}
```

- Fetch: `productService.fetchProductBySlug(productSlug)` di `initState` (sama pola dengan `_CartVariantPickerSheet._loadFullProduct`, hanya sumber slug dari parameter langsung, bukan dari `cartItem.product.slug`).
- Pre-seleksi opsi: kalau `preselectedVariant != null`, isi `_selectedOptions` dari variant itu (perilaku Cart, "ganti varian" dari pilihan sekarang). Kalau `null` (alur feed baru), `_selectedOptions` mulai kosong — tombol confirm disabled sampai kombinasi lengkap valid dipilih (sama seperti behavior existing untuk cart: `_matchedVariant == null` → tombol disabled).
- `confirmLabel` menggantikan teks hardcoded "Simpan" — dipakai untuk teks tombol bawah sheet.
- Loading/error state sama PERSIS seperti sekarang: spinner saat loading, teks error ("Gagal memuat varian. Coba lagi." / "Produk tidak ditemukan.") saat gagal — TIDAK ada tombol retry (mengikuti pola `_CartVariantPickerSheet` yang existing, ekstraksi faithful), dan TIDAK fallback diam ke alur navigasi lama.
- Seam testabilitas: parameter `@visibleForTesting ProductFetcher? productFetcher` (default `null` → pakai global `productService.fetchProductBySlug`). Global `productService` tidak injectable, jadi test menyuntik fetcher palsu — pola yang sudah dipakai codebase (lihat memory widget-test shimmer-hang "inject fetchers").
- `FractionallySizedBox(heightFactor: 0.78)` dipertahankan sama seperti sekarang.

### 2. Refactor `cart_screen.dart` memakai widget baru

`_CartItemCard._openVariantSheet` (`cart_screen.dart:1442-1465`) diganti memanggil `ProductVariantPickerSheet.show(context, productSlug: item.product.slug, preselectedVariant: item.variant, confirmLabel: 'Simpan')`, lalu proses hasil `ProductVariantPickResult` persis seperti sekarang (`cartStore.remove` + `cartStore.addProduct(...)`). `_CartVariantPickerSheet`, `_CartVariantPickResult`, `_CartVariantSummary` (private classes lama) dihapus dari `cart_screen.dart` — tidak ada duplikasi logic tersisa.

### 3. Sheet varian sebagai layer kedua di `feed_video_post_view.dart`

`_addFeedLinkToCart` (baris ~2770-2790):

```dart
void _addFeedLinkToCart(FeedProductLink link, {int quantity = 1}) {
  if (!link.isAvailable || link.stock <= 0) {
    _showProductUnavailable();
    return;
  }
  if (link.hasVariants) {
    _openVariantPickerForFeedLink(link);
    return;
  }
  final product = feedPostProductFromFeedLink(link);
  cartStore.addProduct(product, quantity: quantity);
  if (!mounted) return;
  AppToast.showCartAdded(context, ...);
}
```

`_openVariantPickerForFeedLink(FeedProductLink link)` (baru):

```dart
Future<void> _openVariantPickerForFeedLink(FeedProductLink link) async {
  final result = await ProductVariantPickerSheet.show(
    context,
    productSlug: link.slug,
    preselectedVariant: null,
    confirmLabel: 'Tambah ke Keranjang',
  );
  if (result == null || !mounted) return;
  cartStore.addProduct(result.product, variant: result.variant, quantity: 1);
  Navigator.of(context).pop(); // tutup sheet Links (sheet varian sudah pop dirinya sendiri via ProductVariantPickerSheet.show)
  AppToast.showCartAdded(context, '${result.product.name} masuk keranjang');
}
```

Catatan mekanisme tutup-dua-sheet: `ProductVariantPickerSheet.show` sudah otomatis melakukan `Navigator.pop` dirinya sendiri saat confirm (pola `showModalBottomSheet<T>` standar — pop dengan value `ProductVariantPickResult`). Setelah `await` selesai (sheet varian sudah tertutup), kode di atas memanggil `Navigator.of(context).pop()` SEKALI LAGI untuk menutup sheet Links yang masih terbuka di baliknya. `onClosed` milik `showFeedProductLinksSheet` (sudah ada, lihat §Konteks) otomatis terpanggil oleh `.whenComplete()` saat sheet Links itu pop — resume video terjadi otomatis lewat jalur existing, tidak perlu logic baru.

Tidak ada perubahan pada `feed_product_links_sheet.dart` — `onAddToCart` callback tetap sama persis, hanya implementasinya di pemanggil (`_addFeedLinkToCart`) yang bercabang berdasarkan `hasVariants`.

**Ekstraksi untuk testabilitas:** logika `_addFeedLinkToCart` (guard unavailable + cabang varian + add langsung + toast) dipindah ke fungsi publik `addFeedLinkToCart(BuildContext, FeedProductLink, {ProductFetcher? productFetcher})` di file kecil baru `lib/features/feed/widgets/feed_link_cart_actions.dart`. `_addFeedLinkToCart` di `feed_video_post_view.dart` jadi delegasi satu baris. Ini memungkinkan test menyuntik fetcher + NavigatorObserver tanpa harus me-mount `FeedVideoPostView` yang berat (butuh controller video). Fungsi ini yang memanggil `ProductVariantPickerSheet.show`, lalu pop sheet Links + toast pada path varian; path non-varian tetap TIDAK menutup sheet Links (user bisa tambah beberapa produk berturut-turut — perilaku sekarang dipertahankan).

Catatan pop: penutupan sheet Links (`Navigator.of(context).pop()`) HANYA terjadi pada path varian setelah confirm. Path non-varian tidak pop (sama seperti sekarang).

### 4. Test

- Widget test baru untuk `ProductVariantPickerSheet`: loading→pilih opsi lengkap→tombol enabled→confirm→pop dengan `ProductVariantPickResult` yang benar; opsi habis stok ter-disable; error+retry.
- Widget test `cart_screen.dart` existing (variant-sheet Cart) tetap hijau tanpa perubahan assertion (perilaku user-facing sama).
- Widget test baru di `feed_video_post_view` (atau `member_post_detail_screen` bila sheet Links dipicu dari sana juga — cek pemakaian `showFeedProductLinksSheet`): tap ikon keranjang produk bervarian → sheet varian muncul di atas sheet Links (bukan navigasi) → confirm → kedua sheet tertutup + `cartStore` terisi + toast muncul. Tap foto/nama produk bervarian → tetap navigasi ke detail (regresi negatif, pastikan TIDAK ikut berubah).

## Ringkasan perubahan file

- Baru: `lib/widgets/product_variant_picker_sheet.dart`
- Modifikasi: `lib/screens/cart_screen.dart` (hapus 3 private class, pakai widget baru)
- Baru: `lib/features/feed/widgets/feed_link_cart_actions.dart` (fungsi publik `addFeedLinkToCart` + typedef `ProductFetcher`)
- Modifikasi: `lib/features/feed/widgets/feed_video_post_view.dart` (`_addFeedLinkToCart` jadi delegasi ke `addFeedLinkToCart`)
- Tidak berubah: `lib/features/feed/widgets/feed_product_links_sheet.dart`, `lib/models/feed_post.dart`, logic pause/resume video existing
