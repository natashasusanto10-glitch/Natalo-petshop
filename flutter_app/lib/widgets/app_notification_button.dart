import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../services/push_notification_service.dart';
import '../state/member_store.dart';
import 'app_ui.dart';

/// Bell icon dengan badge unread count untuk header.
///
/// Login-gated: render kosong (SizedBox.shrink) kalau user belum login.
/// Reasoning: notifikasi adalah fitur member — guest user tidak punya
/// konteks personal (no unread tracking, segment "members" tidak ke-fetch).
/// Backend `/api/notifications/me` SECARA TECHNICAL support guest (return
/// segment "all" announcements), tapi UX choice Natalo: hide bell untuk
/// guest supaya home screen lebih clean + kasih clear path "login dulu
/// untuk fitur ini".
///
/// Kalau nanti owner mau pakai broadcast "all" segment ke guest user
/// (mis. promo akhir tahun untuk semua visitor), revert guard ini —
/// backend sudah ready.
///
/// Auto re-render saat memberStore change (login/logout) — bell muncul
/// instant setelah login sukses, hilang instant saat logout.
class AppNotificationButton extends StatefulWidget {
  const AppNotificationButton({super.key});

  @override
  State<AppNotificationButton> createState() => _AppNotificationButtonState();
}

class _AppNotificationButtonState extends State<AppNotificationButton>
    with WidgetsBindingObserver {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    pushNotificationService.notificationRefreshTick.addListener(_load);
    memberStore.addListener(_onMemberChanged);
    // Initial load — guard dalam method itself (skip kalau guest).
    _load();
  }

  @override
  void dispose() {
    memberStore.removeListener(_onMemberChanged);
    pushNotificationService.notificationRefreshTick.removeListener(_load);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  /// React to login/logout — reload count saat user baru login (dapat
  /// real count) atau reset ke 0 saat logout.
  void _onMemberChanged() {
    if (memberStore.isLoggedIn) {
      _load();
    } else {
      if (mounted) setState(() => _unread = 0);
    }
  }

  Future<void> _load() async {
    // Guard: skip API call untuk guest. Sebelumnya widget tetep call
    // /api/notifications/me yang return 401 → silent fail → wasted req.
    if (!memberStore.isLoggedIn) {
      if (mounted) setState(() => _unread = 0);
      return;
    }
    try {
      final result = await notificationService.fetchMine();
      if (mounted) setState(() => _unread = result.unreadCount);
    } catch (_) {
      if (mounted) setState(() => _unread = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: memberStore,
      builder: (context, _) {
        // Hide entirely untuk guest — gak render slot kosong, ga ada
        // ripple, ga ada placeholder. Header look clean tanpa fitur
        // member-only yang gak relevant.
        if (!memberStore.isLoggedIn) {
          return const SizedBox.shrink();
        }
        return AppHeaderIconButton(
          onPressed: () async {
            await Navigator.pushNamed(context, '/notifications');
            if (mounted) _load();
          },
          tooltip: 'Notifikasi',
          child: Badge(
            isLabelVisible: _unread > 0,
            label: Text(_unread > 99 ? '99+' : '$_unread'),
            child: const Icon(Icons.notifications_none_rounded),
          ),
        );
      },
    );
  }
}
