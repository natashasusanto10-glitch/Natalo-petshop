import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'liquid_glass.dart';

/// Public-profile content navigation with distinct neutral tab pills.
///
/// Expanded state = icon-only underline bar (ala IG); saat collapse tab
/// berubah jadi pill Liquid Glass mengambang di atas grid (pill aktif
/// gelap solid, sisanya kaca terang) — persis chrome IG/iOS 26.
class PublicProfileContentTabBar extends StatelessWidget {
  static const double height = 52;

  final TabController controller;
  final double labelOpacity;
  final double pillOpacity;
  final double underlineOpacity;
  final bool reducedMotion;
  final ValueChanged<int>? onTap;

  const PublicProfileContentTabBar({
    super.key,
    required this.controller,
    required this.labelOpacity,
    required this.pillOpacity,
    required this.underlineOpacity,
    this.reducedMotion = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final expandedForeground = theme.colorScheme.onSurface;
    final activeSurface = brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.90)
        : const Color(0xFF111111).withValues(alpha: 0.92);
    final activeForeground =
        brightness == Brightness.dark ? const Color(0xFF111111) : Colors.white;
    final inactiveForeground =
        brightness == Brightness.dark ? Colors.white : const Color(0xFF2C2C2C);

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          TabBar(
            controller: controller,
            onTap: onTap,
            indicator: const BoxDecoration(color: Colors.transparent),
            indicatorColor: Colors.transparent,
            indicatorWeight: 0.001,
            labelPadding: EdgeInsets.zero,
            splashFactory: NoSplash.splashFactory,
            overlayColor: WidgetStateProperty.all<Color>(Colors.transparent),
            dividerColor: Colors.transparent,
            dividerHeight: 0,
            tabs: [
              _PublicProfileTab(
                pillKey: const Key('public_tab_posts_pill'),
                controller: controller,
                index: 0,
                icon: Icons.grid_on_rounded,
                label: 'Postingan',
                labelOpacity: labelOpacity,
                pillOpacity: pillOpacity,
                reducedMotion: reducedMotion,
                expandedForeground: expandedForeground,
                activeSurface: activeSurface,
                activeForeground: activeForeground,
                inactiveForeground: inactiveForeground,
              ),
              _PublicProfileTab(
                pillKey: const Key('public_tab_video_pill'),
                controller: controller,
                index: 1,
                icon: Icons.smart_display_outlined,
                label: 'Video',
                labelOpacity: labelOpacity,
                pillOpacity: pillOpacity,
                reducedMotion: reducedMotion,
                expandedForeground: expandedForeground,
                activeSurface: activeSurface,
                activeForeground: activeForeground,
                inactiveForeground: inactiveForeground,
              ),
              _PublicProfileTab(
                pillKey: const Key('public_tab_shop_pill'),
                controller: controller,
                index: 2,
                icon: Icons.shopping_bag_outlined,
                label: 'Belanja',
                labelOpacity: labelOpacity,
                pillOpacity: pillOpacity,
                reducedMotion: reducedMotion,
                expandedForeground: expandedForeground,
                activeSurface: activeSurface,
                activeForeground: activeForeground,
                inactiveForeground: inactiveForeground,
              ),
            ],
          ),
          if (underlineOpacity > 0.001)
            Positioned(
              left: 0,
              right: 0,
              bottom: 3,
              height: 2.4,
              child: IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return AnimatedBuilder(
                      animation: controller.animation ?? controller,
                      builder: (context, _) {
                        final pos = controller.animation?.value ??
                            controller.index.toDouble();
                        final slot = constraints.maxWidth / 3;
                        const indicatorWidth = 24.0;
                        final centerX = slot * (pos + 0.5);
                        return Stack(
                          children: [
                            Positioned(
                              left: centerX - indicatorWidth / 2,
                              top: 0,
                              bottom: 0,
                              width: indicatorWidth,
                              child: Opacity(
                                opacity: underlineOpacity.clamp(0.0, 1.0),
                                child: DecoratedBox(
                                  key: const Key('public_tab_sliding_underline'),
                                  decoration: BoxDecoration(
                                    color: expandedForeground,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PublicProfileTab extends StatelessWidget {
  final Key pillKey;
  final TabController controller;
  final int index;
  final IconData icon;
  final String label;
  final double labelOpacity;
  final double pillOpacity;
  final bool reducedMotion;
  final Color expandedForeground;
  final Color activeSurface;
  final Color activeForeground;
  final Color inactiveForeground;

  const _PublicProfileTab({
    required this.pillKey,
    required this.controller,
    required this.index,
    required this.icon,
    required this.label,
    required this.labelOpacity,
    required this.pillOpacity,
    required this.reducedMotion,
    required this.expandedForeground,
    required this.activeSurface,
    required this.activeForeground,
    required this.inactiveForeground,
  });

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: PublicProfileContentTabBar.height,
      iconMargin: EdgeInsets.zero,
      child: AnimatedBuilder(
        animation: controller.animation ?? controller,
        builder: (context, _) {
          final position = controller.animation?.value ?? controller.index;
          final emphasis =
              (1 - (position - index).abs()).clamp(0.0, 1.0).toDouble();
          final collapsedForeground = Color.lerp(
            inactiveForeground,
            activeForeground,
            emphasis,
          )!;
          final foreground = Color.lerp(
            expandedForeground,
            collapsedForeground,
            pillOpacity,
          )!;
          // Pill aktif = gelap solid (bukan kaca) supaya kontras kuat;
          // pill tidak aktif = Liquid Glass terang. Emphasis meng-lerp
          // solid darkness mengikuti swipe antar tab.
          final solidFill = Color.lerp(
            Colors.transparent,
            activeSurface,
            pillOpacity * emphasis,
          )!;
          final iconSize = lerpDouble(27, 23, pillOpacity)!;
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final labelScaler = TextScaler.linear(scale.clamp(1.0, 1.3));

          final pillContent = DecoratedBox(
            key: pillKey,
            decoration: BoxDecoration(
              color: solidFill,
              borderRadius: BorderRadius.circular(19),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: foreground, size: iconSize),
                  if (labelOpacity > 0.001) ...[
                    SizedBox(width: 5 * labelOpacity),
                    Flexible(
                      child: Opacity(
                        opacity: labelOpacity,
                        child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: labelScaler,
                          ),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            textScaler: labelScaler,
                            style: TextStyle(
                              color: foreground,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );

          return Semantics(
            label: label,
            button: true,
            selected: emphasis > 0.5,
            excludeSemantics: true,
            child: Tooltip(
              message: label,
              excludeFromSemantics: true,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 7,
                    ),
                    child: LiquidGlass(
                      // Glass memudar saat pill aktif jadi solid gelap —
                      // opacity kaca mengikuti seberapa "inactive" pill.
                      opacity: pillOpacity * (1 - emphasis),
                      reducedMotion: reducedMotion,
                      borderRadius: BorderRadius.circular(19),
                      child: pillContent,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
