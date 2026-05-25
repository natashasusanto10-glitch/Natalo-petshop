import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/natalo_colors.dart';
import '../utils/android_back_overlays.dart';
import '../utils/haptics.dart';
import '../widgets/bottom_nav.dart';
import 'feed_screen.dart';
import 'home_screen.dart';
import 'member_screen.dart';
import 'products_screen.dart';

/// Main shell screen — wraps 5 main tab di IndexedStack.
///
/// **Architectural benefits over old Navigator-based pattern:**
/// - State preservation per tab (scroll position, list, form data)
/// - Instant tab switch (no Navigator push overhead)
/// - Cart count badge real-time sync via cartStore listener
/// - Feed tab pakai dark theme override (full-immersive Reels-style)
///
/// **Sub-pages** (mis. product detail, member orders, checkout) tetap
/// di-push **di atas** shell pakai Navigator standar — back gesture
/// kembali ke tab yang sama.
///
/// Pass `initialTab` saat construct untuk jump ke tab tertentu
/// (mis. dari deep link, push notif tap, quick action).
class MainNavigationScreen extends StatefulWidget {
  final int initialTab;

  const MainNavigationScreen({super.key, this.initialTab = 0});

  /// Helper untuk jump ke tab dari anywhere di app.
  /// Cek apakah ancestor MainNavigationScreen exists → pakai setTab,
  /// else fallback push route baru.
  static void jumpTo(BuildContext context, int tabIndex) {
    final state = context.findAncestorStateOfType<_MainNavigationScreenState>();
    if (state != null) {
      state.setTab(tabIndex);
    } else {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/',
        (_) => false,
        arguments: tabIndex,
      );
    }
  }

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late int _selectedIndex;

  /// Timestamp Samsung Back terakhir untuk double-tap-to-exit detection.
  /// Window 2 detik — kalau back ke-2 dalam window, exit app.
  /// Reset auto kalau user pindah tab atau setelah window habis.
  DateTime? _lastBackTap;
  static const _doubleBackWindow = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab.clamp(0, 3);
  }

  void setTab(int index) {
    if (_selectedIndex == index) return;
    AppHaptics.tap();
    setState(() => _selectedIndex = index);
    // Reset double-back timer saat user pindah tab — supaya gak ke-exit
    // gara2 sisa timer dari tab sebelumnya.
    _lastBackTap = null;
  }

  void _onDestinationSelected(int index) => setTab(index);

  bool get _isFeedPage => _selectedIndex == 2;

  /// Android system back handler. Logic priority:
  ///   1. Ada overlay non-modal (e.g. Feed comment drawer) → close
  ///      via consumeAndroidBackOverlay() yang call closer dari stack
  ///   2. Tab != Beranda → switch ke Beranda. Tidak exit.
  ///   3. Tab Beranda + first back press → snackbar "Tekan sekali lagi
  ///      untuk keluar", record timestamp.
  ///   4. Tab Beranda + back ke-2 dalam 2 detik → SystemNavigator.pop()
  ///      exit app.
  ///
  /// iOS skip — gak ada system back button, swipe-back diatur Navigator
  /// default per route.
  void _handleAndroidBack() {
    // Priority 1: cek overlay registry — kalau ada (mis. Feed comment
    // drawer), close itu dulu. Return tanpa lanjut tab nav.
    if (consumeAndroidBackOverlay()) {
      _lastBackTap = null; // reset exit timer kalau ada overlay tertutup
      return;
    }
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
      _lastBackTap = null;
      return;
    }
    final now = DateTime.now();
    final last = _lastBackTap;
    if (last != null && now.difference(last) <= _doubleBackWindow) {
      // Second tap dalam window — exit app.
      SystemNavigator.pop();
      return;
    }
    _lastBackTap = now;
    if (!mounted) return;
    // Hide snackbar lama supaya gak stack kalau user spam tap.
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Tekan sekali lagi untuk keluar'),
        duration: _doubleBackWindow,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Tabs di-instantiate sekali — IndexedStack keep them mounted across
  // switches. Each tab keep its own state (scroll, list, form, video).
  static const List<Widget> _pages = <Widget>[
    HomeScreen(),
    ProductsScreen(),
    FeedScreen(),
    MemberScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    // Android-only PopScope: intercept system back untuk tab nav +
    // double-back-to-exit. iOS skip — gak ada system back button,
    // swipe-back per-route Navigator default handle sendiri.
    final scaffold = Scaffold(
      backgroundColor:
          _isFeedPage ? NataloColors.feedBlack : NataloColors.background,
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: _buildBottomNavigation(),
    );
    if (!isAndroid) return scaffold;
    return PopScope(
      // canPop=false supaya semua back press masuk ke onPopInvokedWithResult
      // dulu. Tidak block iOS karena di atas udah early-return.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleAndroidBack();
      },
      child: scaffold,
    );
  }

  Widget _buildBottomNavigation() {
    return BottomNavBar(
      currentIndex: _selectedIndex,
      variant: _isFeedPage ? BottomNavVariant.dark : BottomNavVariant.light,
      onDestinationSelected: _onDestinationSelected,
    );
  }
}
