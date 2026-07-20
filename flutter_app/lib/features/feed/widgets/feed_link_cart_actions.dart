import 'package:flutter/material.dart';

import '../../../models/feed_post.dart';
import '../../../state/cart_store.dart';
import '../../../theme/natalo_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/product_variant_picker_sheet.dart';
import 'feed_post_shared_widgets.dart';

/// Aksi tap ikon keranjang pada sebuah [FeedProductLink] di sheet Links.
///
/// - Produk tak tersedia → toast peringatan.
/// - Produk bervarian → buka [ProductVariantPickerSheet] di atas sheet Links;
///   setelah user pilih varian & confirm: masuk keranjang, tutup sheet Links
///   (kembali ke video), toast. Batal → tidak terjadi apa-apa (sheet Links
///   tetap terbuka).
/// - Produk tanpa varian → langsung masuk keranjang + toast; sheet Links TETAP
///   terbuka supaya user bisa menambah beberapa produk.
Future<void> addFeedLinkToCart(
  BuildContext context,
  FeedProductLink link, {
  int quantity = 1,
  ProductFetcher? productFetcher,
}) async {
  if (!link.isAvailable || link.stock <= 0) {
    AppToast.show(
      context,
      'Produk sedang tidak tersedia.',
      kind: ToastKind.warning,
    );
    return;
  }

  if (link.hasVariants) {
    final result = await ProductVariantPickerSheet.show(
      context,
      productSlug: link.slug,
      preselectedVariant: null,
      confirmLabel: 'Tambah ke Keranjang',
      confirmColor: NataloColors.nataloBlue,
      productFetcher: productFetcher,
    );
    if (result == null || !context.mounted) return;
    await cartStore.addProduct(
      result.product,
      variant: result.variant,
      variantLabel: cartVariantOptionLabel(result.product, result.variant),
      quantity: quantity,
    );
    if (!context.mounted) return;
    // Tutup sheet Links yang masih terbuka di baliknya → kembali ke video,
    // onClosed sheet Links memicu resume video (jalur existing).
    Navigator.of(context).pop();
    AppToast.showCartAdded(
      context,
      '${result.product.title} masuk keranjang',
      imageUrl: result.product.imageUrl,
    );
    return;
  }

  final product = feedPostProductFromFeedLink(link);
  await cartStore.addProduct(product, quantity: quantity);
  if (!context.mounted) return;
  AppToast.showCartAdded(
    context,
    quantity > 1
        ? '$quantity x ${link.name} masuk keranjang'
        : '${link.name} masuk keranjang',
    imageUrl: link.imageUrl,
  );
}
