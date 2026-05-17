import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';
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

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab.clamp(0, 3);
  }

  void setTab(int index) {
    if (_selectedIndex == index) return;
    AppHaptics.tap();
    setState(() => _selectedIndex = index);
  }

  void _onDestinationSelected(int index) => setTab(index);

  bool get _isFeedPage => _selectedIndex == 2;

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
    return Scaffold(
      backgroundColor:
          _isFeedPage ? NataloColors.feedBlack : NataloColors.background,
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: _buildBottomNavigation(),
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
