import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// Bottom nav bar dengan 2 variant:
/// - `BottomNavVariant.light` (default) — putih dengan blur untuk screen biasa
/// - `BottomNavVariant.dark` — icon-only putih untuk Feed screen (Reels-style)
enum BottomNavVariant { light, dark }

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
    final isDark = variant == BottomNavVariant.dark;

    if (isDark) {
      // Dark variant (Feed page) — translucent dengan gradient bottom-up
      // supaya video bleed-through dari belakang (Scaffold extendBody:
      // true). Pattern Reels/TikTok: nav float di atas video, gradient
      // halus dari transparent (top) ke black 70% (bottom) untuk contrast
      // icon. NO solid black supaya video edge-to-edge sampai bawah layar.
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.45),
              Colors.black.withValues(alpha: 0.85),
            ],
            stops: const [0.0, 0.4, 1.0],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              0,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: SizedBox(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _FeedNavIcon(
                    icon: Icons.home_outlined,
                    selectedIcon: Icons.home_rounded,
                    selected: currentIndex == 0,
                    semanticLabel: 'Beranda',
                    onTap: () => _onTap(context, 0),
                  ),
                  _FeedNavIcon(
                    icon: Icons.search_rounded,
                    selectedIcon: Icons.storefront_rounded,
                    selected: currentIndex == 1,
                    semanticLabel: 'Produk',
                    onTap: () => _onTap(context, 1),
                  ),
                  _FeedNavIcon(
                    icon: Icons.play_circle_outline_rounded,
                    selectedIcon: Icons.play_circle_rounded,
                    selected: currentIndex == 2,
                    semanticLabel: 'Feed',
                    onTap: () => _onTap(context, 2),
                  ),
                  _FeedNavIcon(
                    icon: Icons.person_outline_rounded,
                    selectedIcon: Icons.person_rounded,
                    selected: currentIndex == 3,
                    semanticLabel: 'Akun',
                    onTap: () => _onTap(context, 3),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final bgColor = isDark
        ? Colors.black.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.90);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.94);
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.30)
        : const Color(0xFF60A5FA).withValues(alpha: 0.07);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: ClipRRect(
          borderRadius: AppRadius.extraExtraLarge,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: AppRadius.extraExtraLarge,
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: NavigationBarTheme(
                data: isDark
                    ? NavigationBarThemeData(
                        backgroundColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
                        indicatorColor: Colors.white.withValues(alpha: 0.16),
                        iconTheme: WidgetStateProperty.resolveWith(
                          (states) {
                            final selected =
                                states.contains(WidgetState.selected);
                            return IconThemeData(
                              color: selected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.72),
                              size: selected ? 28 : 25,
                            );
                          },
                        ),
                        labelTextStyle: WidgetStateProperty.resolveWith(
                          (states) {
                            final selected =
                                states.contains(WidgetState.selected);
                            return TextStyle(
                              color: selected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.72),
                              fontSize: 12,
                              fontWeight:
                                  selected ? FontWeight.w900 : FontWeight.w700,
                            );
                          },
                        ),
                      )
                    : const NavigationBarThemeData(
                        backgroundColor: Colors.transparent,
                      ),
                child: NavigationBar(
                  selectedIndex: currentIndex,
                  onDestinationSelected: (index) => _onTap(context, index),
                  backgroundColor: Colors.transparent,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: 'Beranda',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.storefront_outlined),
                      selectedIcon: Icon(Icons.storefront_rounded),
                      label: 'Produk',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.play_circle_outline_rounded),
                      selectedIcon: Icon(Icons.play_circle_rounded),
                      label: 'Feed',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.person_outline),
                      selectedIcon: Icon(Icons.person_rounded),
                      label: 'Akun',
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

class _FeedNavIcon extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final String semanticLabel;
  final VoidCallback onTap;

  const _FeedNavIcon({
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? Colors.white : Colors.white.withValues(alpha: 0.54);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          containedInkWell: false,
          child: SizedBox(
            height: 52,
            width: 58,
            child: Icon(
              selected ? selectedIcon : icon,
              color: color,
              size: selected ? 30 : 27,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: selected ? 0.90 : 0.70),
                  blurRadius: selected ? 9 : 7,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
