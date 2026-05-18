import 'package:flutter/material.dart';

/// Bottom nav bar Natalo: integrated, clean, 4 menu utama.
///
/// `variant` tetap dipertahankan agar call-site lama tidak perlu berubah,
/// tetapi visual nav dibuat konsisten sesuai desain terbaru.
enum BottomNavVariant { light, dark }

const _navBackground = Color(0xFFFFFFFF);
const _navTopBorder = Color(0xFFE8ECF2);
const _navActiveBlue = Color(0xFF2563EB);
const _navInactiveIcon = Color(0xFF2B2F38);
const _navInactiveLabel = Color(0xFF6F7480);

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

    if (onDestinationSelected != null) {
      onDestinationSelected!(index);
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _navBackground,
        border: const Border(top: BorderSide(color: _navTopBorder)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 74,
          child: Row(
            children: [
              _BottomNavItem(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                label: 'Beranda',
                selected: currentIndex == 0,
                onTap: () => _onTap(context, 0),
              ),
              _BottomNavItem(
                icon: Icons.shopping_bag_outlined,
                selectedIcon: Icons.shopping_bag_rounded,
                label: 'Produk',
                selected: currentIndex == 1,
                onTap: () => _onTap(context, 1),
              ),
              _BottomNavItem(
                icon: Icons.play_circle_outline_rounded,
                selectedIcon: Icons.play_circle_rounded,
                label: 'Feed',
                selected: currentIndex == 2,
                onTap: () => _onTap(context, 2),
              ),
              _BottomNavItem(
                icon: Icons.person_outline_rounded,
                selectedIcon: Icons.person_rounded,
                label: 'Akun',
                selected: currentIndex == 3,
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
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? _navActiveBlue : _navInactiveIcon;
    final labelColor = selected ? _navActiveBlue : _navInactiveLabel;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: _navActiveBlue.withValues(alpha: 0.08),
            highlightColor: _navActiveBlue.withValues(alpha: 0.04),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedScale(
                      scale: selected ? 1.04 : 1,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        selected ? selectedIcon : icon,
                        color: color,
                        size: selected ? 26 : 24,
                      ),
                    ),
                    const SizedBox(height: 5),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                        color: labelColor,
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
