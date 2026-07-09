import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/push_notification_service.dart';
import '../state/chat_store.dart';
import '../theme/natalo_colors.dart';
import 'app_ui.dart';

/// Chat bubble icon dengan badge unread count untuk header. Entry point
/// utama customer ke `/chat` (ChatRoomScreen — full UI di Task 4).
///
/// Pola meniru `AppCartButton` (badge merah + pulse-scale saat count naik),
/// tapi:
///  - Source of truth unread = `chatStore` (bukan `cartStore`), di-refresh
///    lewat REST (`chatStore.fetchUnread()`) — Natalo tidak punya Firestore
///    realtime listener seperti NLCATTER.
///  - Chrome ikon pakai `AppHeaderIconButton` supaya konsisten dengan icon
///    header lain (mis. `AppNotificationButton`).
///  - Re-fetch unread setiap kali `pushNotificationService.notificationRefreshTick`
///    berubah (dipicu saat FCM foreground message masuk / app resume) — pola
///    sama dengan `AppNotificationButton._load()`.
///
/// Kill-switch: `chatStore.chatEnabled` (fail-open true — default sebelum
/// config pertama sukses fetch). Kalau false (maintenance), sembunyikan
/// tombol sepenuhnya (`SizedBox.shrink()`) supaya user tidak masuk ke chat
/// yang sedang dimatikan.
class AppChatButton extends StatefulWidget {
  const AppChatButton({super.key});

  @override
  State<AppChatButton> createState() => _AppChatButtonState();
}

class _AppChatButtonState extends State<AppChatButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;
  int _prevCount = 0;

  @override
  void initState() {
    super.initState();
    _prevCount = chatStore.unreadCount;
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _pulseScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.4)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.4, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 60,
      ),
    ]).animate(_pulseCtrl);

    chatStore.addListener(_onChatChanged);
    pushNotificationService.notificationRefreshTick.addListener(_onRefreshTick);
    // Initial load — badge butuh angka nyata begitu icon muncul, bukan
    // nunggu FCM tick pertama (yang mungkin tidak pernah terjadi kalau
    // user tidak dapat push baru selama sesi ini).
    chatStore.fetchUnread();
  }

  @override
  void dispose() {
    chatStore.removeListener(_onChatChanged);
    pushNotificationService.notificationRefreshTick
        .removeListener(_onRefreshTick);
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onRefreshTick() {
    chatStore.fetchUnread();
  }

  void _onChatChanged() {
    final newCount = chatStore.unreadCount;
    // Pulse hanya saat count NAIK — bukan saat berkurang (read) / reset.
    if (newCount > _prevCount && mounted) {
      _pulseCtrl.forward(from: 0);
    }
    _prevCount = newCount;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: chatStore,
      builder: (context, _) {
        // Kill-switch — sembunyikan entry point sepenuhnya saat maintenance.
        if (!chatStore.chatEnabled) {
          return const SizedBox.shrink();
        }
        final count = chatStore.unreadCount;
        return Stack(
          alignment: Alignment.center,
          children: [
            AppHeaderIconButton(
              tooltip: 'Chat',
              onPressed: () => Navigator.pushNamed(context, '/chat'),
              // Ikon chat gaya marketplace (gelembung membulat + 3 titik),
              // custom-paint — Material tak punya glyph bulat+titik. Warisi
              // warna & ukuran dari ambient IconTheme (24 header custom / 25
              // AppBar), seragam dgn notif & keranjang.
              child: const ChatDotsBubbleIcon(),
            ),
            if (count > 0)
              Positioned(
                right: 6,
                top: 6,
                child: ScaleTransition(
                  scale: _pulseScale,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: NataloColors.danger,
                      borderRadius: BorderRadius.circular(8),
                      // Soft red glow saat pulse — subtle, hanya kerasa saat
                      // animation aktif (transparent saat resting karena
                      // shadow blur kecil + opacity rendah).
                      boxShadow: [
                        BoxShadow(
                          color: NataloColors.danger.withValues(alpha: 0.45),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(minWidth: 16),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Ikon chat "gaya marketplace" (Shopee/Tokopedia): gelembung membulat + ekor
/// kecil + 3 titik "sedang mengobrol". Custom paint karena Material tak punya
/// glyph bulat-plus-titik. Mewarisi warna & ukuran dari ambient [IconTheme]
/// supaya serasi dengan ikon header lain (notif/keranjang) di tiap konteks
/// (24 di header custom, 25 di AppBar).
class ChatDotsBubbleIcon extends StatelessWidget {
  const ChatDotsBubbleIcon({super.key, this.size, this.color});

  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final s = size ?? iconTheme.size ?? 24.0;
    // Fallback ke onSurface (bukan textPrimary hardcoded) supaya benar di dark
    // mode juga. Di dalam IconButton, iconTheme.color sudah = onSurface.
    final c = color ??
        iconTheme.color ??
        Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: s,
      height: s,
      child: CustomPaint(painter: _ChatDotsBubblePainter(c)),
    );
  }
}

class _ChatDotsBubblePainter extends CustomPainter {
  _ChatDotsBubblePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 24.0; // ruang desain 24x24
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * k
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = color;
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..color = color;

    // Gelembung BULAT (lingkaran) + ekor kecil bawah, gaya Tokopedia — satu
    // outline kontinu. Busur lingkaran hampir penuh (sisakan celah ~46° di
    // bawah), lalu ekor runcing menutup celahnya. Pakai arcTo dgn sudut
    // eksplisit (y-ke-bawah: 90° = titik bawah lingkaran) supaya arah busur
    // deterministik; tanpa Path.combine/PathOperation.
    const cx = 12.0, cyc = 11.0, r = 8.5; // pusat & radius (ruang 24x24)
    const gapStart = 72 * math.pi / 180; // ujung kanan celah (bawah-kanan)
    const gapEnd = 118 * math.pi / 180; // ujung kiri celah (bawah-kiri)
    final rect =
        Rect.fromCircle(center: Offset(cx * k, cyc * k), radius: r * k);
    final bubble = Path()
      // moveTo persis ke titik awal busur (sudut gapEnd) lalu busur 314°
      // sampai gapStart — celah bawah tersisa utk ekor.
      ..moveTo(
        (cx + r * math.cos(gapEnd)) * k,
        (cyc + r * math.sin(gapEnd)) * k,
      )
      ..arcTo(rect, gapEnd, 2 * math.pi - (gapEnd - gapStart), false)
      // Ekor: dari ujung kanan celah turun runcing, balik ke ujung kiri celah.
      ..lineTo((cx - 1.2) * k, (cyc + r + 3.2) * k)
      ..close();
    canvas.drawPath(bubble, stroke);

    // 3 titik horizontal di tengah lingkaran.
    for (final dx in const [-3.6, 0.0, 3.6]) {
      canvas.drawCircle(Offset((cx + dx) * k, cyc * k), 1.35 * k, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _ChatDotsBubblePainter oldDelegate) =>
      oldDelegate.color != color;
}
