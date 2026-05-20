import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../services/push_notification_service.dart';
import 'app_ui.dart';

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
    _load();
  }

  @override
  void dispose() {
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

  Future<void> _load() async {
    try {
      final result = await notificationService.fetchMine();
      if (mounted) setState(() => _unread = result.unreadCount);
    } catch (_) {
      if (mounted) setState(() => _unread = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
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
  }
}
