import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';

import '../constants/official_brand.dart';
import '../models/public_profile.dart';
import '../theme/natalo_colors.dart';
import 'official_brand_avatar.dart';
import 'public_profile_content_tab_bar.dart';
import 'public_profile_header_motion.dart';

class PublicProfileHeaderMetrics {
  final double topPadding;
  final double toolbarHeight;
  final double identityHeight;
  final double tabHeight;

  const PublicProfileHeaderMetrics({
    required this.topPadding,
    required this.toolbarHeight,
    required this.identityHeight,
    required this.tabHeight,
  });

  double get collapsedChromeHeight => topPadding + toolbarHeight + tabHeight;
  double get scrollSpaceHeight => collapsedChromeHeight + identityHeight;

  static PublicProfileHeaderMetrics resolve(
    BuildContext context,
    PublicProfile profile,
  ) {
    final scale =
        MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0).toDouble();
    final hasBio = profile.bio?.trim().isNotEmpty == true;
    final hasMutuals = profile.isOfficial &&
        !profile.isOwner &&
        profile.mutualFollowers.items.isNotEmpty;
    final base = profile.isOfficial ? 210.0 : 220.0;
    final bio = hasBio ? (profile.isOfficial ? 28.0 : 48.0) : 0.0;
    final mutual = hasMutuals ? 40.0 : 0.0;
    final scaleAllowance = (scale - 1) * (profile.isOfficial ? 72 : 64);
    return PublicProfileHeaderMetrics(
      topPadding: MediaQuery.paddingOf(context).top,
      toolbarHeight: 56,
      identityHeight: base + bio + mutual + scaleAllowance,
      tabHeight: PublicProfileContentTabBar.height,
    );
  }
}

class PublicProfileChromeOverlay extends StatelessWidget {
  final PublicProfile profile;
  final TabController controller;
  final double scrollOffset;
  final PublicProfileHeaderMetrics metrics;
  final VoidCallback onBack;
  final VoidCallback? onShareProfile;
  final VoidCallback? onOverflow;
  final ValueChanged<int>? onTabTap;

  const PublicProfileChromeOverlay({
    super.key,
    required this.profile,
    required this.controller,
    required this.scrollOffset,
    required this.metrics,
    required this.onBack,
    this.onShareProfile,
    this.onOverflow,
    this.onTabTap,
  });

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final motion = PublicProfileHeaderMotion.resolve(
      scrollOffset: scrollOffset,
      collapseDistance: metrics.identityHeight,
      reducedMotion: reducedMotion,
    );
    final expandedTop =
        metrics.topPadding + metrics.toolbarHeight + metrics.identityHeight;
    final collapsedTop = metrics.topPadding + metrics.toolbarHeight;
    final tabTop = lerpDouble(expandedTop, collapsedTop, motion.tabTravel)!;
    final horizontalInset = lerpDouble(0, 16, motion.tabTravel)!;
    final theme = Theme.of(context);
    final foreground =
        profile.isOfficial ? Colors.white : theme.colorScheme.onSurface;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: metrics.collapsedChromeHeight,
          child: IgnorePointer(
            child: ClipRect(
              child: reducedMotion
                  ? ColoredBox(
                      key: const Key('public_profile_reduced_motion_tint'),
                      color: _glassTint(context, opacity: 0.82),
                    )
                  : BackdropFilter(
                      key: const Key('public_profile_glass_layer'),
                      filter: ImageFilter.blur(
                        sigmaX: motion.blurSigma,
                        sigmaY: motion.blurSigma,
                      ),
                      child: ColoredBox(
                        key: const Key('public_profile_glass_tint'),
                        color: _glassTint(
                          context,
                          opacity: 0.72 * motion.glassOpacity,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        Positioned(
          top: metrics.topPadding,
          left: 4,
          right: 4,
          height: metrics.toolbarHeight,
          child: Row(
            children: [
              _FrostedControl(
                opacity: motion.controlSurfaceOpacity,
                child: IconButton(
                  onPressed: onBack,
                  tooltip: 'Kembali',
                  icon: Icon(Icons.arrow_back_rounded, color: foreground),
                ),
              ),
              Expanded(
                child: profile.isOfficial
                    ? Opacity(
                        opacity: motion.compactIdentityOpacity,
                        child: const Row(
                          children: [
                            OfficialBrandAvatar(size: 28),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                kOfficialBrandName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(width: 4),
                            OfficialVerifiedBadge(size: 16),
                          ],
                        ),
                      )
                    : Text(
                        profile.displayHandle,
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
                _FrostedControl(
                  opacity: motion.controlSurfaceOpacity,
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
          key: const Key('public_profile_tab_group'),
          top: tabTop,
          left: horizontalInset,
          right: horizontalInset,
          height: metrics.tabHeight,
          child: PublicProfileContentTabBar(
            controller: controller,
            isOfficial: profile.isOfficial,
            labelOpacity: motion.labelOpacity,
            pillOpacity: motion.pillOpacity,
            underlineOpacity: motion.underlineOpacity,
            onTap: onTabTap,
          ),
        ),
      ],
    );
  }

  Color _glassTint(BuildContext context, {required double opacity}) {
    if (profile.isOfficial) {
      return NataloColors.heroTop.withValues(alpha: opacity);
    }
    return Theme.of(context).colorScheme.surface.withValues(alpha: opacity);
  }
}

class _FrostedControl extends StatelessWidget {
  final double opacity;
  final Widget child;

  const _FrostedControl({required this.opacity, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context)
                .colorScheme
                .surface
                .withValues(alpha: 0.66 * opacity),
          ),
          child: child,
        ),
      ),
    );
  }
}

enum _PublicProfileAction { share, moderate }
