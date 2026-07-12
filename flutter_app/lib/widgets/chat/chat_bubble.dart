import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../services/order_service.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/natalo_colors.dart';
import '../../utils/formatters.dart';
import '../app_product_image.dart';
import '../app_toast.dart';
import 'chat_product_card.dart' show openChatProductDetail;

/// Radius "ekor" gelembung — SENGAJA lebih kecil dari token `AppRadius`
/// manapun (terkecil `sm`=8) supaya notch-nya kerasa runcing khas chat
/// bubble (pola WhatsApp/iMessage). `AppRadius.md` (12) dipakai untuk 3
/// sudut lain sesuai Global Constraints Plan 4 ("Radius AppRadius.md=12
/// untuk gelembung") — token menang atas prosa mockup ("radius 14").
const double _kBubbleTailRadius = 4;

/// Gelembung teks chat. Alignment (customer kanan/primary, staff kiri/putih)
/// ditentukan `message.sender` — dispatch tipe pesan (bukan sender) sudah
/// dilakukan pemanggil (`ChatRoomScreen`), widget ini hanya render SATU
/// bubble untuk pesan bertipe teks.
///
/// Kalau pesan teks ini membawa konteks produk/pesanan (`message.product`/
/// `message.order` — proxy SAAT INI menulis context sbg field tambahan pada
/// pesan `type: text`, BUKAN tipe terpisah `product_context`/`order_context`
/// — lihat `app/api/chat/send/route.ts` & `lib/chat/rooms.ts`), tempel
/// [ChatContextChip] ringkas di bawah teks supaya konteksnya tetap terlihat.
class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  /// Dipanggil saat tombol "Coba lagi" (status `failed`) ditekan. Nullable —
  /// null berarti belum di-wire (retry sesungguhnya baru Task 5); tombol
  /// tetap tampil sesuai spec visual Step 1, hanya belum aktif.
  final VoidCallback? onRetry;

  const ChatBubble({super.key, required this.message, this.onRetry});

  bool get _isCustomer => message.sender == ChatSender.customer;

  @override
  Widget build(BuildContext context) {
    final isCustomer = _isCustomer;
    final hasContext = message.product != null || message.order != null;

    return Column(
      crossAxisAlignment:
          isCustomer ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        _Bubble(message: message, isCustomer: isCustomer, onRetry: onRetry),
        if (hasContext) ...[
          const SizedBox(height: AppSpacing.xs),
          ChatContextChip(
            product: message.product,
            order: message.order,
            isCustomer: isCustomer,
          ),
        ],
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool isCustomer;
  final VoidCallback? onRetry;

  const _Bubble({
    required this.message,
    required this.isCustomer,
    required this.onRetry,
  });

  BorderRadius get _radius {
    const main = Radius.circular(AppRadius.md);
    const tail = Radius.circular(_kBubbleTailRadius);
    return BorderRadius.only(
      topLeft: isCustomer ? main : tail,
      topRight: isCustomer ? tail : main,
      bottomLeft: main,
      bottomRight: main,
    );
  }

  /// Teks pesan dengan jam+status menempel INLINE di kanan-bawah baris
  /// terakhir (ala WhatsApp / paritas chat internal NLCATTER `_textWithMeta`).
  /// Trik "ruang cadangan": salinan [meta] TAK TERLIHAT disisipkan sebagai
  /// WidgetSpan di akhir teks supaya baris terakhir menyisakan ruang selebar
  /// meta; meta asli lalu di-`Positioned` mepet kanan-bawah. Kalau tak muat
  /// sebaris, meta otomatis turun ke bawahnya. Ini yang bikin bubble rapat
  /// hug-content (jam tidak lagi di baris terpisah yang memaksa bubble melebar).
  Widget _textWithMeta(String text, Widget meta) {
    final textColor =
        isCustomer ? NataloColors.white : NataloColors.textPrimary;
    return Stack(
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: text,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
              WidgetSpan(
                alignment: PlaceholderAlignment.bottom,
                child: Opacity(
                  opacity: 0,
                  // Celah teks→jam ala WhatsApp.
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: meta,
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(right: 0, bottom: 0, child: meta),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = message.text ?? '';
    final hasReply = message.replyTo != null;
    final meta =
        _MetaRow(message: message, isCustomer: isCustomer, onRetry: onRetry);

    // Dengan kutipan: IntrinsicWidth → bubble menyusut ke isi TERLEBAR
    // (kutipan/teks), kutipan dibuat full-width selebar itu (ala WA). Tanpa
    // kutipan: Stack `_textWithMeta` sudah hug-content sendiri, tak butuh
    // IntrinsicWidth (hindari biaya intrinsic tiap bubble teks biasa).
    final Widget inner = hasReply
        ? IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _ReplyQuote(reply: message.replyTo!, isCustomer: isCustomer),
                const SizedBox(height: 5),
                _textWithMeta(text, meta),
              ],
            ),
          )
        : _textWithMeta(text, meta);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isCustomer ? NataloColors.primary : NataloColors.white,
          borderRadius: _radius,
          border: isCustomer ? null : Border.all(color: NataloColors.border),
        ),
        child: inner,
      ),
    );
  }
}

/// Blok kutipan "pesan yang dibalas" di dalam bubble (di atas teks). Bentuk
/// data = [ChatReplyRef] {senderName, type, text-preview}. Warna beradaptasi:
/// di bubble customer (latar primary) teks harus terang; di bubble staff
/// (putih) pakai warna body/primary normal.
class _ReplyQuote extends StatelessWidget {
  final ChatReplyRef reply;
  final bool isCustomer;

  const _ReplyQuote({required this.reply, required this.isCustomer});

  @override
  Widget build(BuildContext context) {
    final who = reply.senderName?.trim();
    final rtext = reply.text?.trim() ?? '';
    final preview = switch (reply.type) {
      'image' => rtext.isNotEmpty ? rtext : '📷 Foto',
      'product' || 'product_context' => rtext.isNotEmpty ? rtext : '🛍️ Produk',
      _ => rtext.isNotEmpty ? rtext : 'Pesan',
    };
    final barColor =
        isCustomer ? NataloColors.white : NataloColors.primary;
    final labelColor =
        isCustomer ? NataloColors.white : NataloColors.primary;
    final textColor = isCustomer
        ? NataloColors.white.withValues(alpha: 0.85)
        : NataloColors.textSecondary;
    final tileBg = isCustomer
        ? NataloColors.white.withValues(alpha: 0.15)
        : NataloColors.primarySoft;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        color: tileBg,
        border: Border(left: BorderSide(color: barColor, width: 3)),
        borderRadius:
            const BorderRadius.horizontal(right: Radius.circular(6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (who != null && who.isNotEmpty)
            Text(who,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: labelColor)),
          Text(preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: textColor)),
        ],
      ),
    );
  }
}

/// Baris kecil timestamp + centang status DI DALAM bubble (pojok
/// kanan-bawah, pola WhatsApp). Centang hanya tampil untuk pesan CUSTOMER
/// sendiri (lazim: kamu tidak lihat centang "terkirim" di pesan lawan
/// bicara).
class _MetaRow extends StatelessWidget {
  final ChatMessage message;
  final bool isCustomer;
  final VoidCallback? onRetry;

  const _MetaRow({
    required this.message,
    required this.isCustomer,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final time = _formatClock(message.createdAt);
    final tickColor = isCustomer
        ? NataloColors.white.withValues(alpha: 0.75)
        : NataloColors.textTertiary;

    if (message.status == ChatSendStatus.failed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (time.isNotEmpty)
            Text(
              time,
              style: TextStyle(fontSize: 10, color: tickColor),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.error_outline_rounded,
              size: 12, color: NataloColors.danger),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onRetry,
            child: const Text(
              'Coba lagi',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: NataloColors.danger,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (time.isNotEmpty)
          Text(time, style: TextStyle(fontSize: 10, color: tickColor)),
        if (isCustomer) ...[
          const SizedBox(width: 4),
          Icon(_statusIcon(message.status), size: 12, color: tickColor),
        ],
      ],
    );
  }

  /// `queued`/`sending` = jam (belum tentu sampai server); `sent` = centang
  /// tunggal. Tidak ada tier "dibaca" (centang ganda biru) — `ChatSendStatus`
  /// (Task 1, frozen) sengaja tak punya nilai `read`, dan wire proxy juga
  /// belum expose field read-receipt staff (`readByStaffAt`) — lihat
  /// `lib/chat/core.ts` (hanya `readByCustomerAt`, arah sebaliknya). Null
  /// (pesan lama tanpa status eksplisit) fallback ke centang tunggal.
  IconData _statusIcon(ChatSendStatus? status) {
    switch (status) {
      case ChatSendStatus.queued:
      case ChatSendStatus.sending:
        return Icons.access_time_rounded;
      case ChatSendStatus.sent:
      case null:
        return Icons.done_rounded;
      case ChatSendStatus.failed:
        return Icons.error_outline_rounded;
    }
  }
}

String _formatClock(int epochMillis) {
  if (epochMillis <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMillis);
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// Chip ringkas konteks produk/pesanan yang menempel pada sebuah pesan —
/// lebih kecil dari [ChatProductCard] (bukan kartu penuh, cuma penunjuk
/// "pesan ini terkait produk/pesanan X"). Dipakai dua cara:
///  1. Ditempel otomatis di bawah [ChatBubble] teks yang membawa
///     `product`/`order` (jalur nyata proxy saat ini).
///  2. Dispatch langsung dari `ChatRoomScreen` untuk `ChatMsgType`
///     `productContext`/`orderContext` (nilai enum yang model-nya sudah
///     mendukung, meski belum ada jalur proxy yang benar-benar
///     menerbitkan tipe ini secara terpisah hari ini).
class ChatContextChip extends StatefulWidget {
  final ChatProductRef? product;
  final ChatOrderRef? order;
  final bool isCustomer;

  const ChatContextChip({
    super.key,
    this.product,
    this.order,
    required this.isCustomer,
  }) : assert(product != null || order != null,
            'ChatContextChip butuh product atau order');

  @override
  State<ChatContextChip> createState() => _ChatContextChipState();
}

class _ChatContextChipState extends State<ChatContextChip> {
  bool _loading = false;

  Future<void> _onTap() async {
    if (_loading) return;
    final product = widget.product;
    final order = widget.order;
    setState(() => _loading = true);
    try {
      if (product != null) {
        await openChatProductDetail(
          context,
          slug: product.slug,
          productId: product.productId,
        );
      } else if (order != null) {
        await _openOrder(order.orderNumber);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openOrder(String orderNumber) async {
    try {
      final order = await orderService.fetchOrderDetail(orderNumber);
      if (!mounted) return;
      Navigator.pushNamed(context, '/member/order-detail', arguments: order);
    } catch (e) {
      // Tangkap apa adanya (ApiException jaringan/404, atau error lain) —
      // chip cuma navigasi pelengkap, gagal fetch tak boleh crash chat.
      if (kDebugMode) {
        debugPrint('[ChatContextChip] fetchOrderDetail gagal: $e');
      }
      if (mounted) {
        AppToast.show(context, 'Gagal membuka pesanan', kind: ToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final order = widget.order;

    final IconData leadingIcon = product != null
        ? Icons.shopping_bag_outlined
        : Icons.receipt_long_outlined;
    final String label =
        product != null ? 'Menanyakan produk' : 'Terkait pesanan';
    final String title = product != null
        ? product.name
        : '#${order!.orderNumber}${order.status != null ? ' • ${order.status}' : ''}';

    return GestureDetector(
      onTap: _onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm + 2),
          decoration: BoxDecoration(
            color: NataloColors.surface,
            borderRadius: AppRadius.large,
            border: Border.all(color: NataloColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (product?.imageUrl != null)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: AppProductImage(
                    imageUrl: product!.imageUrl,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: NataloColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(leadingIcon,
                        size: 30, color: NataloColors.textSecondary),
                  ),
                ),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: NataloColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        color: NataloColors.textPrimary,
                      ),
                    ),
                    if (product?.price != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        formatRupiah(product!.price!),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: NataloColors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 1.8),
                    )
                  : const Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: NataloColors.textTertiary,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
