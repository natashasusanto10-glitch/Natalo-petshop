import 'package:flutter/material.dart';

/// Bottom nav bar Natalo: compact, integrated, 4 menu utama.
///
/// `variant` tetap dipertahankan agar call-site lama tidak perlu berubah.
/// Visual terbaru dibuat putih polos seperti marketplace besar: rendah,
/// separator tipis, tanpa floating card dan tanpa shadow berat.
enum BottomNavVariant { light, dark }

const _navBackground = Color(0xFFFFFFFF);
const _navTopBorder = Color(0xFFE5E7EB);
const _navActiveBlue = Color(0xFF2563EB);
const _navInactive = Color(0xFF6B7280);
const _navDarkBackground = Color(0xFF000000);
const _navDarkTopBorder = Color(0xFF1F2937);
const _navDarkActive = Color(0xFFFFFFFF);
const _navDarkInactive = Color(0xFF9CA3AF);

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final BottomNavVariant variant;
  final ValueChanged<int>? onDestinationSelected;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    this.variant = BottomNavVariant.light,
    this.onDestinationSelected,
  });

  void _onTap(BuildContext context, int index) {
    if (index == currentIndex) return;
    final onSelected = onDestinationSelected;
    if (onSelected != null) {
      onSelected(index);
      return;
    }

    switch (index) {
      case 0:
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        break;
      case 1:
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/products',
          (route) => false,
        );
        break;
      case 2:
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/feed',
          (route) => false,
        );
        break;
      case 3:
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/member',
          (route) => false,
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = variant == BottomNavVariant.dark;
    final background = dark ? _navDarkBackground : _navBackground;
    final borderColor = dark ? _navDarkTopBorder : _navTopBorder;
    final activeColor = dark ? _navDarkActive : _navActiveBlue;
    final inactiveColor = dark ? _navDarkInactive : _navInactive;

    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(
          top: BorderSide(
            color: borderColor,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              _BottomNavItem(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                label: 'Beranda',
                selected: currentIndex == 0,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () => _onTap(context, 0),
              ),
              _BottomNavItem(
                icon: Icons.shopping_bag_outlined,
                selectedIcon: Icons.shopping_bag_rounded,
                label: 'Produk',
                selected: currentIndex == 1,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () => _onTap(context, 1),
              ),
              _BottomNavItem(
                icon: Icons.play_circle_outline_rounded,
                selectedIcon: Icons.play_circle_fill_rounded,
                label: 'Feed',
                selected: currentIndex == 2,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () => _onTap(context, 2),
              ),
              _BottomNavItem(
                icon: Icons.person_outline_rounded,
                selectedIcon: Icons.person_rounded,
                label: 'Akun',
                selected: currentIndex == 3,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () => _onTap(context, 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : inactiveColor;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: activeColor.withValues(alpha: 0.08),
            highlightColor: activeColor.withValues(alpha: 0.06),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedScale(
                      scale: selected ? 1.02 : 1,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        selected ? selectedIcon : icon,
                        color: color,
                        size: selected ? 25 : 24,
                      ),
                    ),
                    const SizedBox(height: 3),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                        color: color,
                        fontSize: 11.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        height: 1,
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
