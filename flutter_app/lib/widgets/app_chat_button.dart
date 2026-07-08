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
              child: const Icon(
                // Tanpa `size:` — ikut ambient IconTheme spt AppNotificationButton/
                // AppCartButton: 24 di header custom (Beranda/Transaksi), 25 di
                // AppBar (actionsIconTheme). Seragam dgn tetangganya tiap layar.
                Icons.chat_bubble_outline_rounded,
              ),
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
