import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../constants/official_brand.dart';
import '../models/public_profile.dart';
import '../theme/natalo_text.dart';
import 'liquid_glass.dart';
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
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 2);
    // Nonlinear accessibility scaling is font-size dependent. Sampling only
    // `scale(1)` can substantially under-allocate the fixed identity sliver,
    // so resolve the largest effective factor used by this header's text.
    var scale = 1.0;
    for (final fontSize in const <double>[10.5, 11.5, 13, 14, 15, 16, 19]) {
      final effectiveScale = scaler.scale(fontSize) / fontSize;
      if (effectiveScale > scale) scale = effectiveScale;
    }
    final hasMutuals = !profile.isOwner &&
        profile.mutualFollowers.items.isNotEmpty &&
        profile.mutualFollowers.totalCount > 0;
    final bioText = profile.bio?.trim() ?? '';
    double bioBlockHeight = 0;
    if (bioText.isNotEmpty) {
      final availableWidth =
          MediaQuery.sizeOf(context).width - (16 * 2); // AppSpacing.lg kiri+kanan
      final painter = TextPainter(
        text: TextSpan(
          text: bioText,
          // WAJIB sama dengan font produksi (app_theme.dart:55-56) —
          // advance-width glyph beda antar font mengubah jumlah baris
          // WRAP, jadi salah font → salah ukur baris → tinggi kurang →
          // tab menimpa aksi / header ter-clip di device.
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            fontFamily: 'PlusJakartaSans',
            fontFamilyFallback: ['Roboto', 'Arial'],
          ),
        ),
        maxLines: 2,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(maxWidth: availableWidth);
      bioBlockHeight = 8 + painter.height; // 8 = AppSpacing.sm gap sebelum bio
    }
    return PublicProfileHeaderMetrics(
      topPadding: MediaQuery.paddingOf(context).top,
      toolbarHeight: 56,
      identityHeight: _identityHeight(
        scale: scale,
        bioBlockHeight: bioBlockHeight,
        hasMutuals: hasMutuals,
        isOfficial: profile.isOfficial,
      ),
      tabHeight: PublicProfileContentTabBar.height,
    );
  }

  /// Mirrors the unified IG-style header's fixed rows exactly:
  /// padding(12) + avatar row(72) + gap(12) + name + [chip] + [bio] +
  /// [mutuals] + gap(12) + actions(44) + padding(12). The +2 safety
  /// absorbs fractional line-height rounding from Jakarta Sans.
  static double _identityHeight({
    required double scale,
    required double bioBlockHeight,
    required bool hasMutuals,
    required bool isOfficial,
  }) {
    const fixedRows = 12.0 + 72 + 12 + 12 + 44 + 12;
    final nameRow = (15 * 1.15 * scale).clamp(16.0, double.infinity);
    // Chip "AKUN RESMI": teks 10.5 ikut text-scale (line-height default
    // font bisa ~1.25) + padding vertikal 8 + border 2.
    final chip = isOfficial ? 6 + (10.5 * 1.25 * scale) + 10 : 0.0;
    final mutuals = hasMutuals ? 8 + 30.0 : 0.0;
    // Safety menyerap pembulatan line-height fraksional Jakarta Sans;
    // tumbuh sedikit mengikuti scale karena pembulatan ikut membesar.
    final safety = 2 + (scale - 1) * 6;
    return fixedRows + nameRow + chip + bioBlockHeight + mutuals + safety;
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
      // The outer sliver consumes the complete spacer before the inner grid
      // owns the scroll. Keeping choreography on that same distance means the
      // glass transition is still in flight while the first row moves beneath
      // the collapsed chrome, instead of completing before any underlap.
      collapseDistance: metrics.scrollSpaceHeight,
      reducedMotion: reducedMotion,
    );
    final expandedTop =
        metrics.topPadding + metrics.toolbarHeight + metrics.identityHeight;
    final collapsedTop = metrics.topPadding + metrics.toolbarHeight;
    final tabTop = lerpDouble(expandedTop, collapsedTop, motion.tabTravel)!;
    final horizontalInset = lerpDouble(0, 16, motion.tabTravel)!;
    final theme = Theme.of(context);
    // Satu layout terang untuk semua akun — tidak ada lagi chrome navy
    // khusus official. Chip mengambang bergaya Liquid Glass (blur +
    // saturasi + rim) menggantikan band blur full-width lama, persis
    // pola chrome IG saat grid ter-scroll ke bawah pill.
    final foreground = theme.colorScheme.onSurface;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: metrics.topPadding,
          left: 4,
          right: 4,
          height: metrics.toolbarHeight,
          child: Row(
            children: [
              _GlassControl(
                opacity: motion.controlSurfaceOpacity,
                reducedMotion: reducedMotion,
                child: IconButton(
                  onPressed: onBack,
                  tooltip: 'Kembali',
                  icon: Icon(Icons.arrow_back_rounded, color: foreground),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: profile.isOfficial
                      ? Opacity(
                          opacity: motion.compactIdentityOpacity,
                          child: LiquidGlass(
                            opacity: motion.controlSurfaceOpacity,
                            reducedMotion: reducedMotion,
                            borderRadius: BorderRadius.circular(21),
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(5, 5, 12, 5),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const OfficialBrandAvatar(size: 26),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      kOfficialBrandName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: foreground,
                                        fontSize: 14,
                                        fontWeight: NataloWeight.strong,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const OfficialVerifiedBadge(size: 15),
                                ],
                              ),
                            ),
                          ),
                        )
                      : LiquidGlass(
                          opacity: motion.controlSurfaceOpacity,
                          reducedMotion: reducedMotion,
                          borderRadius: BorderRadius.circular(21),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Text(
                              profile.displayHandle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: foreground,
                                fontSize: 17,
                                fontWeight: NataloWeight.strong,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              if (onShareProfile != null || onOverflow != null)
                _GlassControl(
                  opacity: motion.controlSurfaceOpacity,
                  reducedMotion: reducedMotion,
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
            labelOpacity: motion.labelOpacity,
            pillOpacity: motion.pillOpacity,
            underlineOpacity: motion.underlineOpacity,
            reducedMotion: reducedMotion,
            onTap: onTabTap,
          ),
        ),
      ],
    );
  }
}

class _GlassControl extends StatelessWidget {
  final double opacity;
  final bool reducedMotion;
  final Widget child;

  const _GlassControl({
    required this.opacity,
    required this.reducedMotion,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: LiquidGlass(
          opacity: opacity,
          reducedMotion: reducedMotion,
          borderRadius: BorderRadius.circular(22),
          child: child,
        ),
      ),
    );
  }
}

enum _PublicProfileAction { share, moderate }
