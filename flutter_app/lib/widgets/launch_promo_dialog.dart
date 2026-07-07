import 'package:flutter/material.dart';

import '../models/launch_popup_campaign.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';
import '../utils/motion_prefs.dart';
import 'app_product_image.dart';

/// Hasil interaksi popup pembuka.
enum LaunchPromoOutcome { cta, dismiss }

class _Tone {
  final Color color;
  final Color softBg;
  const _Tone(this.color, this.softBg);

  /// Paritas dengan _AnnouncementTone di announcement_detail_screen.dart.
  factory _Tone.of(LaunchPopupTone tone) => tone == LaunchPopupTone.promo
      ? const _Tone(Color(0xFFE11D48), Color(0xFFFFEEF2))
      : const _Tone(Color(0xFF20B26B), Color(0xFFE8F8F0));
}

/// Tampilkan popup pembuka di atas layar sekarang. Return outcome:
/// [LaunchPromoOutcome.cta] bila user tap tombol utama; selain itu
/// (tombol dismiss / X / tap area gelap / back Android) → dismiss.
Future<LaunchPromoOutcome> showLaunchPromoDialog(
  BuildContext context, {
  required LaunchPopupCampaign campaign,
}) async {
  final reduce = MotionPrefs.shouldReduce(context);
  final result = await showGeneralDialog<LaunchPromoOutcome>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Tutup',
    barrierColor: const Color(0x8C0F172A), // rgba(15,23,42,.55)
    transitionDuration:
        Duration(milliseconds: reduce ? 120 : 240),
    pageBuilder: (context, _, __) => LaunchPromoDialog(campaign: campaign),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      if (reduce) return FadeTransition(opacity: curved, child: child);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
  return result ?? LaunchPromoOutcome.dismiss;
}

class LaunchPromoDialog extends StatelessWidget {
  final LaunchPopupCampaign campaign;
  const LaunchPromoDialog({super.key, required this.campaign});

  void _close(BuildContext context, LaunchPromoOutcome outcome) {
    AppHaptics.tap();
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final tone = _Tone.of(campaign.tone);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Material(
            color: NataloColors.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (campaign.hasImage)
                  Stack(
                    children: [
                      AppProductImage(
                        imageUrl: campaign.imageUrl,
                        width: double.infinity,
                        height: 172,
                        borderRadius: BorderRadius.zero,
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: _CategoryChip(label: campaign.categoryLabel, tone: tone),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: _CloseButton(
                          onTap: () => _close(context, LaunchPromoOutcome.dismiss),
                        ),
                      ),
                    ],
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 10, 0),
                    child: Row(
                      children: [
                        _CategoryChip(label: campaign.categoryLabel, tone: tone),
                        const Spacer(),
                        _CloseButton(
                          onTap: () => _close(context, LaunchPromoOutcome.dismiss),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        campaign.title,
                        style: const TextStyle(
                          color: NataloColors.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        campaign.body,
                        style: const TextStyle(
                          color: NataloColors.textSecondary,
                          fontSize: 14,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _Actions(
                        campaign: campaign,
                        onCta: () => _close(context, LaunchPromoOutcome.cta),
                        onDismiss: () => _close(context, LaunchPromoOutcome.dismiss),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final LaunchPopupCampaign campaign;
  final VoidCallback onCta;
  final VoidCallback onDismiss;
  const _Actions({
    required this.campaign,
    required this.onCta,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final dismiss = _PillButton(
      key: const ValueKey('launch-popup-dismiss'),
      label: campaign.dismissLabel,
      filled: false,
      onTap: onDismiss,
    );
    if (!campaign.hasCta) {
      return SizedBox(width: double.infinity, child: dismiss);
    }
    return Row(
      children: [
        Expanded(child: dismiss),
        const SizedBox(width: 10),
        Expanded(
          flex: 3,
          child: _PillButton(
            key: const ValueKey('launch-popup-cta'),
            label: campaign.ctaLabel!,
            filled: true,
            onTap: onCta,
          ),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _PillButton({
    super.key,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Material(
        color: filled ? NataloColors.primary : NataloColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: filled ? Colors.white : NataloColors.primary,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final _Tone tone;
  const _CategoryChip({required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tone.color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('launch-popup-close'),
      color: NataloColors.surfaceElevated,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: NataloColors.border),
          ),
          child: const Icon(Icons.close_rounded,
              size: 18, color: NataloColors.textPrimary),
        ),
      ),
    );
  }
}
