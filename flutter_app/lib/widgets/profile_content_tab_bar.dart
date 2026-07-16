import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';

/// Shared profile content navigation for Grid, Video, and Belanja.
///
/// The controller animation drives both the underline and icon emphasis, so
/// taps and horizontal swipes feel like one continuous transition.
class ProfileContentTabBar extends StatelessWidget {
  static const double height = 52;

  final TabController controller;
  final ValueChanged<int>? onTap;
  final double cornerRadius;
  final double labelOpacity;
  final double tabGap;
  final double surfaceOpacity;
  final double underlineOpacity;
  final Color? foregroundColor;
  final Color? mergedSurfaceColor;

  const ProfileContentTabBar({
    super.key,
    required this.controller,
    this.onTap,
    this.cornerRadius = 0,
    this.labelOpacity = 0,
    this.tabGap = 0,
    this.surfaceOpacity = 0,
    this.underlineOpacity = 1,
    this.foregroundColor,
    this.mergedSurfaceColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final expandedForeground = foregroundColor ?? colors.onSurfaceVariant;
    final surface = Color.lerp(
      Colors.transparent,
      (mergedSurfaceColor ?? Colors.black).withValues(alpha: 0.72),
      surfaceOpacity,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(cornerRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface,
        ),
        child: TabBar(
          controller: controller,
          onTap: onTap,
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(
              color: NataloColors.primary.withValues(alpha: underlineOpacity),
              width: 2.4,
            ),
            borderRadius: BorderRadius.circular(3),
            insets: const EdgeInsets.symmetric(horizontal: 12),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorColor: NataloColors.primary,
          indicatorWeight: 0.001,
          labelPadding: EdgeInsets.zero,
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.all<Color>(Colors.transparent),
          padding: EdgeInsets.symmetric(horizontal: tabGap / 2),
          tabs: [
            _AnimatedProfileTab(
              key: const Key('profile_tab_posts'),
              controller: controller,
              index: 0,
              icon: Icons.grid_on_rounded,
              label: 'Postingan',
              labelOpacity: labelOpacity,
              surfaceOpacity: surfaceOpacity,
              foregroundColor: expandedForeground,
            ),
            _AnimatedProfileTab(
              key: const Key('profile_tab_video'),
              controller: controller,
              index: 1,
              icon: Icons.smart_display_outlined,
              label: 'Video',
              labelOpacity: labelOpacity,
              surfaceOpacity: surfaceOpacity,
              foregroundColor: expandedForeground,
            ),
            _AnimatedProfileTab(
              key: const Key('profile_tab_shop'),
              controller: controller,
              index: 2,
              icon: Icons.shopping_bag_outlined,
              label: 'Belanja',
              labelOpacity: labelOpacity,
              surfaceOpacity: surfaceOpacity,
              foregroundColor: expandedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedProfileTab extends StatelessWidget {
  final TabController controller;
  final int index;
  final IconData icon;
  final String label;
  final double labelOpacity;
  final double surfaceOpacity;
  final Color foregroundColor;

  const _AnimatedProfileTab({
    super.key,
    required this.controller,
    required this.index,
    required this.icon,
    required this.label,
    required this.labelOpacity,
    required this.surfaceOpacity,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: ProfileContentTabBar.height,
      iconMargin: EdgeInsets.zero,
      child: AnimatedBuilder(
        animation: controller.animation ?? controller,
        builder: (context, _) {
          final position = controller.animation?.value ?? controller.index;
          final emphasis =
              (1 - (position - index).abs()).clamp(0.0, 1.0).toDouble();
          final inactiveColor = Color.lerp(
            foregroundColor,
            Colors.white,
            surfaceOpacity,
          );
          final color = Color.lerp(inactiveColor, NataloColors.primary, emphasis);
          final size = lerpDouble(27, 28.5, emphasis)!;

          return Semantics(
            button: true,
            selected: emphasis > 0.5,
            label: label,
            child: Tooltip(
              message: label,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: size),
                  if (labelOpacity > 0) ...[
                    SizedBox(width: 5 * labelOpacity),
                    Flexible(
                      child: Opacity(
                        opacity: labelOpacity,
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class ProfileContentTabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TabController controller;
  final ValueChanged<int>? onTap;

  const ProfileContentTabHeaderDelegate({
    required this.controller,
    this.onTap,
  });

  @override
  double get minExtent => ProfileContentTabBar.height;

  @override
  double get maxExtent => ProfileContentTabBar.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ProfileContentTabBar(controller: controller, onTap: onTap);
  }

  @override
  bool shouldRebuild(covariant ProfileContentTabHeaderDelegate oldDelegate) {
    return oldDelegate.controller != controller || oldDelegate.onTap != onTap;
  }
}
