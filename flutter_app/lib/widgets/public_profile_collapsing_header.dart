import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';
import 'profile_content_tab_bar.dart';
import 'public_profile_header_motion.dart';

/// One scroll-driven surface for a public profile's navigation, expanded
/// identity and content tabs. It deliberately owns no profile state: existing
/// callbacks and the existing [TabController] remain the source of truth.
class PublicProfileCollapsingHeaderDelegate
    extends SliverPersistentHeaderDelegate {
  static const double collapseRange = 220;
  static const double toolbarHeight = 56;
  static const double regularExpandedHeight = 280;
  static const double officialExpandedHeight = 390;

  static double responsiveExpandedHeight(
    BuildContext context, {
    required bool isOfficial,
  }) {
    final base = isOfficial ? officialExpandedHeight : regularExpandedHeight;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return base + ((scale - 1).clamp(0, 1) * 80);
  }

  final TabController controller;
  final String title;
  final Widget expandedHeader;
  final VoidCallback onBack;
  final VoidCallback? onShareProfile;
  final VoidCallback? onOverflow;
  final ValueChanged<int>? onTabTap;
  final double topPadding;
  final double expandedHeight;
  final bool isOfficial;

  const PublicProfileCollapsingHeaderDelegate({
    required this.controller,
    required this.title,
    required this.expandedHeader,
    required this.onBack,
    this.onShareProfile,
    this.onOverflow,
    this.onTabTap,
    this.topPadding = 0,
    this.expandedHeight = collapseRange,
    this.isOfficial = false,
  });

  double get _topBarExtent => topPadding + toolbarHeight;

  @override
  double get minExtent => _topBarExtent + ProfileContentTabBar.height;

  @override
  double get maxExtent => minExtent + expandedHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final colors = Theme.of(context).colorScheme;
    final collapse = expandedHeight <= 0 ? 1.0 : shrinkOffset / expandedHeight;
    final progress = collapse.clamp(0.0, 1.0).toDouble();
    final motion = PublicProfileHeaderMotion.resolve(
      shrinkOffset,
      expandedHeight,
    );
    final surface = isOfficial ? NataloColors.heroTop : colors.surface;
    final foreground = isOfficial ? Colors.white : colors.onSurface;

    return ColoredBox(
      color: surface,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              // The identity scrolls naturally behind the pinned toolbar;
              // clipping (rather than relayout) keeps the grid stable.
              top: _topBarExtent - shrinkOffset,
              left: 0,
              right: 0,
              height: expandedHeight,
              child: Opacity(
                opacity: 1 - progress,
                child: IgnorePointer(
                  ignoring: progress > 0.75,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: expandedHeader,
                  ),
                ),
              ),
            ),
            Positioned(
              top: topPadding,
              left: 4,
              right: 4,
              height: toolbarHeight,
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: 'Kembali',
                    child: IconButton(
                      onPressed: onBack,
                      tooltip: 'Kembali',
                      icon: Icon(Icons.arrow_back_rounded, color: foreground),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (onShareProfile != null || onOverflow != null)
                    Semantics(
                      button: true,
                      label: 'Opsi lainnya',
                      child: PopupMenuButton<_PublicProfileAction>(
                        tooltip: 'Opsi lainnya',
                        icon: Icon(Icons.more_horiz_rounded, color: foreground),
                        onSelected: (action) {
                          switch (action) {
                            case _PublicProfileAction.share:
                              onShareProfile?.call();
                            case _PublicProfileAction.moderate:
                              onOverflow?.call();
                          }
                        },
                        itemBuilder: (context) => [
                          if (onShareProfile != null)
                            const PopupMenuItem(
                              value: _PublicProfileAction.share,
                              child: Text('Bagikan profil'),
                            ),
                          if (onOverflow != null)
                            const PopupMenuItem(
                              value: _PublicProfileAction.moderate,
                              child: Text('Laporkan atau blokir'),
                            ),
                        ],
                      ),
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: ProfileContentTabBar.height,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final available = constraints.maxWidth;
                  final width = available * motion.widthFactor;
                  // Motion uses normalized placement: 1 = right, 0 = left.
                  final left = (available - width) * motion.horizontalAlignment;
                  return Stack(
                    children: [
                      Positioned(
                        key: const Key('public_profile_tab_group'),
                        left: left,
                        width: width,
                        top: 0,
                        bottom: 0,
                        child: ProfileContentTabBar(
                          controller: controller,
                          onTap: onTabTap,
                          cornerRadius: motion.radius,
                          labelOpacity: motion.labelOpacity,
                          tabGap: motion.gap,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant PublicProfileCollapsingHeaderDelegate old) {
    return old.controller != controller ||
        old.title != title ||
        old.expandedHeader != expandedHeader ||
        old.onBack != onBack ||
        old.onShareProfile != onShareProfile ||
        old.onOverflow != onOverflow ||
        old.onTabTap != onTabTap ||
        old.topPadding != topPadding ||
        old.expandedHeight != expandedHeight ||
        old.isOfficial != isOfficial;
  }
}

enum _PublicProfileAction { share, moderate }
