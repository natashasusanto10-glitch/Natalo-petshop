import 'dart:async';

import 'package:flutter/material.dart';

import '../services/notification_counts.dart';
import '../theme/admin_theme.dart';
import 'dashboard_screen.dart';
import 'orders_screen.dart';
import 'products_screen.dart';
import 'settings_screen.dart';

/// Shell utama dengan bottom navigation 4 tab — match pattern Shopee Seller.
///
/// Back button behaviour (Android):
///   - Kalau bukan di tab Dashboard, back pindah ke Dashboard dulu.
///   - Kalau di Dashboard, back pertama kasih snackbar "Tekan sekali lagi
///     untuk keluar"; tap kedua dalam 2 detik baru keluar app.
///
/// Notif badges:
///   - Pesanan tab → order PENDING + cancel request urgent
///   - Akun tab    → feed pending review + abuse flag open
///   Counter refresh saat init, lifecycle resume, auto-poll 60s.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  DateTime? _lastBackPressAt;
  Timer? _pollTimer;

  static const _tabs = <Widget>[
    DashboardScreen(),
    OrdersScreen(),
    ProductsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationCounts.instance.refresh();
    // Fallback poll 60s — kalau push notif belum aktif (Firebase belum
    // di-setup atau notif blocked), badge tetap update reasonably fresh.
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      NotificationCounts.instance.refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Admin balik ke foreground — refresh counter supaya badge fresh.
      NotificationCounts.instance.refresh();
    }
  }

  Future<void> _handlePop(bool didPop, Object? _) async {
    if (didPop) return;
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return;
    }
    final now = DateTime.now();
    if (_lastBackPressAt == null ||
        now.difference(_lastBackPressAt!) > const Duration(seconds: 2)) {
      _lastBackPressAt = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tekan sekali lagi untuk keluar'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _tabs,
        ),
        bottomNavigationBar: AnimatedBuilder(
          animation: NotificationCounts.instance,
          builder: (_, _) {
            final counts = NotificationCounts.instance;
            return BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (i) {
                setState(() => _currentIndex = i);
                // Refresh saat user pindah ke tab — kalau ada update
                // setelah admin process order, counter auto-clear.
                NotificationCounts.instance.refresh();
              },
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard_outlined),
                  activeIcon:
                      Icon(Icons.dashboard_rounded, color: AdminColors.primary),
                  label: 'Dashboard',
                ),
                BottomNavigationBarItem(
                  icon: _BadgedIcon(
                    icon: Icons.receipt_long_outlined,
                    count: counts.ordersTabBadge,
                  ),
                  activeIcon: _BadgedIcon(
                    icon: Icons.receipt_long_rounded,
                    count: counts.ordersTabBadge,
                    color: AdminColors.primary,
                  ),
                  label: 'Pesanan',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.inventory_2_outlined),
                  activeIcon:
                      Icon(Icons.inventory_2_rounded, color: AdminColors.primary),
                  label: 'Produk',
                ),
                BottomNavigationBarItem(
                  icon: _BadgedIcon(
                    icon: Icons.person_outline_rounded,
                    count: counts.accountTabBadge,
                  ),
                  activeIcon: _BadgedIcon(
                    icon: Icons.person_rounded,
                    count: counts.accountTabBadge,
                    color: AdminColors.primary,
                  ),
                  label: 'Akun',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Icon dgn red dot / count badge di pojok kanan atas.
/// Pattern standar Shopee/Tokopedia — angka 1-99, "99+" kalau lebih besar.
class _BadgedIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color? color;

  const _BadgedIcon({
    required this.icon,
    required this.count,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return Icon(icon, color: color);
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, color: color),
        Positioned(
          right: -6,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            decoration: BoxDecoration(
              color: AdminColors.danger,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: Text(
              count > 99 ? '99+' : count.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
