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

  const ProfileContentTabBar({
    super.key,
    required this.controller,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.outlineVariant, width: 0.5),
          bottom: BorderSide(color: colors.outlineVariant, width: 0.5),
        ),
      ),
      child: TabBar(
        controller: controller,
        onTap: onTap,
        indicator: UnderlineTabIndicator(
          borderSide: const BorderSide(
            color: NataloColors.primary,
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
        tabs: [
          _AnimatedProfileTab(
            key: const Key('profile_tab_posts'),
            controller: controller,
            index: 0,
            icon: Icons.grid_on_rounded,
            label: 'Postingan',
          ),
          _AnimatedProfileTab(
            key: const Key('profile_tab_video'),
            controller: controller,
            index: 1,
            icon: Icons.smart_display_outlined,
            label: 'Video',
          ),
          _AnimatedProfileTab(
            key: const Key('profile_tab_shop'),
            controller: controller,
            index: 2,
            icon: Icons.shopping_bag_outlined,
            label: 'Belanja',
          ),
        ],
      ),
    );
  }
}

class _AnimatedProfileTab extends StatelessWidget {
  final TabController controller;
  final int index;
  final IconData icon;
  final String label;

  const _AnimatedProfileTab({
    super.key,
    required this.controller,
    required this.index,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tab(
      height: ProfileContentTabBar.height,
      iconMargin: EdgeInsets.zero,
      child: AnimatedBuilder(
        animation: controller.animation ?? controller,
        builder: (context, _) {
          final position = controller.animation?.value ?? controller.index;
          final emphasis =
              (1 - (position - index).abs()).clamp(0.0, 1.0).toDouble();
          final color = Color.lerp(
            colors.onSurfaceVariant,
            NataloColors.primary,
            emphasis,
          );
          final size = lerpDouble(27, 28.5, emphasis)!;

          return Semantics(
            button: true,
            selected: emphasis > 0.5,
            label: label,
            child: Tooltip(
              message: label,
              child: SizedBox.square(
                dimension: 36,
                child: Center(
                  child: Icon(icon, color: color, size: size),
                ),
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
