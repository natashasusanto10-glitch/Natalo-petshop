import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../services/product_service.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/natalo_colors.dart';
import '../../utils/formatters.dart';
import '../app_product_image.dart';
import '../app_toast.dart';

/// Fetch produk (by slug, fallback productId — endpoint `/api/products/<v>`
/// resolve keduanya, lihat `ProductService.fetchProductBySlug`) lalu push
/// `/product-detail`. Dipakai `ChatProductCard` ("Lihat Produk") DAN
/// `ChatContextChip` (`chat_bubble.dart`, tap kartu konteks produk) supaya
/// dua entry point navigasi produk dari chat konsisten & tak duplikasi.
///
/// Kartu chat (`ChatProductRef`) hanya bawa field allowlist ringan (bukan
/// `Product` penuh — lihat docstring `chat_message.dart`), jadi "Lihat
/// Produk" WAJIB fetch ulang sebelum push `ProductDetailScreen` (yang
/// butuh `Product` lengkap: variant, deskripsi, dst). Gagal fetch (produk
/// dihapus/network) → toast error, TIDAK push (pola `_openProductBySlug`
/// di `deep_link_service.dart`, tapi di sini tanpa fallback ke `/products`
/// karena user sedang di tengah chat, bukan deep link cold-start).
Future<void> openChatProductDetail(
  BuildContext context, {
  required String? slug,
  required String productId,
}) async {
  final query = (slug != null && slug.isNotEmpty) ? slug : productId;
  if (query.isEmpty) {
    AppToast.show(context, 'Produk tidak ditemukan', kind: ToastKind.error);
    return;
  }
  try {
    final product = await productService.fetchProductBySlug(query);
    if (!context.mounted) return;
    if (product == null) {
      AppToast.show(context, 'Produk tidak ditemukan', kind: ToastKind.error);
      return;
    }
    Navigator.pushNamed(context, '/product-detail', arguments: product);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[ChatProductCard] fetchProductBySlug gagal: $e');
    }
    if (context.mounted) {
      AppToast.show(context, 'Gagal membuka produk', kind: ToastKind.error);
    }
  }
}

/// Kartu produk penuh — pesan `type: product` (staff share produk lewat
/// picker katalog, Plan 2.5). Field mengikuti allowlist proxy
/// (`ChatProductRef`) — SENGAJA tak ada cost/margin/supplier.
class ChatProductCard extends StatefulWidget {
  final ChatProductRef product;

  const ChatProductCard({super.key, required this.product});

  @override
  State<ChatProductCard> createState() => _ChatProductCardState();
}

class _ChatProductCardState extends State<ChatProductCard> {
  bool _loading = false;

  Future<void> _openDetail() async {
    if (_loading) return;
    setState(() => _loading = true);
    await openChatProductDetail(
      context,
      slug: widget.product.slug,
      productId: widget.product.productId,
    );
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    // Proxy TIDAK mem-forward `discountPrice` di allowlist product card saat
    // ini (lihat docstring `ChatProductRef`) — biasanya null. Guard tetap
    // dipasang: strikethrough HANYA muncul kalau discountPrice ada & lebih
    // rendah dari price (konvensi sama dgn `Product.hasDiscount`), supaya
    // kartu tetap benar begitu proxy mulai mengirimnya.
    final rawPrice = product.price;
    final discount = product.discountPrice;
    final hasDiscount =
        discount != null && rawPrice != null && discount < rawPrice;
    // Nullable SENGAJA — `price` mestinya selalu ada per allowlist proxy,
    // tapi kalau ternyata null (data rusak/produk tanpa harga), SEMBUNYIKAN
    // baris harga daripada menampilkan "Rp0" yang menyesatkan.
    final int? displayPrice = hasDiscount ? discount : rawPrice;
    final outOfStock = product.stock <= 0;

    return Container(
      width: 220,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: NataloColors.white,
        borderRadius: AppRadius.medium,
        border: Border.all(color: NataloColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppProductImage(
            imageUrl: product.imageUrl,
            width: double.infinity,
            height: 120,
            fit: BoxFit.cover,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: NataloColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (displayPrice != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  formatRupiah(displayPrice),
                  style: const TextStyle(
                    color: NataloColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (hasDiscount) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    formatRupiah(rawPrice),
                    style: const TextStyle(
                      color: NataloColors.oldPriceText,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ],
              ],
            ),
          const SizedBox(height: 2),
          Text(
            outOfStock ? 'Stok habis' : 'Stok: ${product.stock}',
            style: TextStyle(
              color:
                  outOfStock ? NataloColors.danger : NataloColors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _loading ? null : _openDetail,
              style: OutlinedButton.styleFrom(
                foregroundColor: NataloColors.primary,
                side: const BorderSide(color: NataloColors.primary),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Lihat Produk',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
