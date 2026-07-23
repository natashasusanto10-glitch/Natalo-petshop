import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';
import '../theme/natalo_text.dart';
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
                activeIcon: Icons.grid_on_rounded,
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
                // Samakan glyph dgn bottom nav (Icons.play_circle_outline_
                // rounded) supaya konsep "Video" konsisten sepanjang app.
                icon: Icons.play_circle_outline_rounded,
                activeIcon: Icons.play_circle_fill_rounded,
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
                pillKey: const Key('public_tab_tagged_pill'),
                controller: controller,
                index: 2,
                icon: Icons.people_outline_rounded,
                activeIcon: Icons.people_rounded,
                label: 'Ditandai',
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
  final IconData activeIcon;
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
    required this.activeIcon,
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
          // PREMIUM: emphasis mentah linear terhadap posisi jari saat swipe —
          // terasa "menempel" ke gerakan. Bungkus dengan easeOutCubic supaya
          // treatment visual (warna, gerak naik, crossfade) MENGENDAP di
          // ujung transisi, bukan tracking 1:1. Underline geser TIDAK pakai
          // ini (mekanismenya sendiri, sudah mulus).
          final curvedEmphasis = Curves.easeOutCubic.transform(emphasis);
          // Mode expanded (pillOpacity 0, dipakai MemberScreen & profil
          // publik sebelum scroll): dulu foreground SELALU = expandedForeground
          // konstan (bug — tidak pernah ikut emphasis). Sekarang warna
          // melebur abu→biru brand mengikuti curvedEmphasis, sama seperti mode
          // pill di bawahnya.
          final expandedDynamic = Color.lerp(
            expandedForeground,
            NataloColors.primary,
            curvedEmphasis,
          )!;
          final collapsedForeground = Color.lerp(
            inactiveForeground,
            activeForeground,
            curvedEmphasis,
          )!;
          final foreground = Color.lerp(
            expandedDynamic,
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
          const iconSize = 24.0;
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
                  Transform.translate(
                    // Gerak naik 3px di-ease supaya terasa "terangkat lalu
                    // mengendap", bukan meluncur linear. Crossfade outline↔
                    // filled memakai kurva yang sama supaya bentuk & posisi
                    // berubah serempak (premium: satu gerakan, bukan dua
                    // animasi yang balapan).
                    offset: Offset(0, lerpDouble(0, -3, curvedEmphasis)!),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Opacity(
                          opacity: (1 - curvedEmphasis).clamp(0.0, 1.0),
                          child: Icon(icon, color: foreground, size: iconSize),
                        ),
                        Opacity(
                          opacity: curvedEmphasis.clamp(0.0, 1.0),
                          child: Icon(
                            activeIcon,
                            color: foreground,
                            size: iconSize,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                              fontWeight: NataloWeight.strong,
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
            // Tooltip long-press SENGAJA dihapus mengikuti kebijakan
            // "Global Icon Clean Interaction" — nama tetap terbaca screen
            // reader lewat Semantics.label di atas. Lihat
            // docs/superpowers/specs/2026-07-22-tutup-tag-belanja-spec-a-design.md.
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
          );
        },
      ),
    );
  }
}
