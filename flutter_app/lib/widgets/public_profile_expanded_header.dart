import 'package:flutter/material.dart';

import '../models/public_profile.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import 'official_brand_avatar.dart';
import 'profile_avatar.dart';
import 'public_profile_mutual_followers_row.dart';

/// Expanded identity header — satu layout IG-style untuk SEMUA akun
/// (official dan user biasa). Yang membedakan official hanyalah badge
/// verified + chip "AKUN RESMI" + tombol "Pesan"; TIDAK ada lagi mode
/// hero navy terpisah (sumber bug seam/gap lama).
///
/// Struktur (mengikuti IG): avatar kiri + stats horizontal di samping,
/// nama, bio, mutual row, lalu baris aksi abu netral.
class PublicProfileExpandedHeader extends StatelessWidget {
  final PublicProfile profile;
  final bool followBusy;
  final bool chatEnabled;
  final VoidCallback? onFollowToggle;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onEditProfile;
  final VoidCallback? onShareProfile;
  final VoidCallback? onMessage;

  const PublicProfileExpandedHeader({
    super.key,
    required this.profile,
    required this.followBusy,
    required this.chatEnabled,
    this.onFollowToggle,
    this.onFollowersTap,
    this.onFollowingTap,
    this.onEditProfile,
    this.onShareProfile,
    this.onMessage,
  });

  bool get _showOfficialMessage =>
      profile.isOfficial &&
      !profile.isOwner &&
      chatEnabled &&
      onMessage != null;

  @override
  Widget build(BuildContext context) {
    // The identity has a finite scroll-space contract. Cap only its visual
    // typography so platform nonlinear and extreme accessibility scaling
    // cannot push mandatory actions outside that contract. Explicit Semantics
    // labels below keep the complete accessible names and values.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 2,
      child: _IgExpandedHeader(
        profile: profile,
        followBusy: followBusy,
        onFollowToggle: profile.isOwner ? null : onFollowToggle,
        onFollowersTap: onFollowersTap,
        onFollowingTap: onFollowingTap,
        onEditProfile: profile.isOwner ? onEditProfile : null,
        onShareProfile: onShareProfile,
        onMessage: _showOfficialMessage ? onMessage : null,
      ),
    );
  }
}

class _IgExpandedHeader extends StatelessWidget {
  final PublicProfile profile;
  final bool followBusy;
  final VoidCallback? onFollowToggle;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onEditProfile;
  final VoidCallback? onShareProfile;
  final VoidCallback? onMessage;

  const _IgExpandedHeader({
    required this.profile,
    required this.followBusy,
    this.onFollowToggle,
    this.onFollowersTap,
    this.onFollowingTap,
    this.onEditProfile,
    this.onShareProfile,
    this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasBio = profile.bio?.trim().isNotEmpty == true;
    final hasMutuals = !profile.isOwner &&
        profile.mutualFollowers.items.isNotEmpty &&
        profile.mutualFollowers.totalCount > 0;
    return ColoredBox(
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                profile.isOfficial
                    ? const ProfileAvatar(
                        initial: 'N',
                        size: 72,
                        fontSize: 26,
                        isOfficial: true,
                        plain: true,
                      )
                    : ProfileAvatar(
                        initial: profile.initial,
                        imageUrl: profile.profilePhotoUrl,
                        size: 72,
                        fontSize: 26,
                        plain: true,
                      ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: _StatsRow(
                    profile: profile,
                    foreground: cs.onSurface,
                    secondary: cs.onSurfaceVariant,
                    onFollowersTap: onFollowersTap,
                    onFollowingTap: onFollowingTap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Flexible(
                  child: Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                ),
                if (profile.isOfficial) ...[
                  const SizedBox(width: AppSpacing.xs),
                  const OfficialVerifiedBadge(size: 16),
                ],
              ],
            ),
            if (profile.isOfficial) ...[
              const SizedBox(height: 6),
              const _OfficialChip(),
            ],
            if (hasBio) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                profile.bio!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
            if (hasMutuals) ...[
              const SizedBox(height: AppSpacing.sm),
              PublicProfileMutualFollowersRow(summary: profile.mutualFollowers),
            ],
            const SizedBox(height: AppSpacing.md),
            _ActionRow(
              profile: profile,
              followBusy: followBusy,
              onFollowToggle: onFollowToggle,
              onEditProfile: onEditProfile,
              onShareProfile: onShareProfile,
              onMessage: onMessage,
            ),
          ],
        ),
      ),
    );
  }
}

class _OfficialChip extends StatelessWidget {
  const _OfficialChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: NataloColors.officialGold.withValues(alpha: 0.16),
        borderRadius: AppRadius.small,
        border: Border.all(
          color: NataloColors.officialGold.withValues(alpha: 0.48),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_rounded,
              color: NataloColors.officialGoldOnLight, size: 13),
          SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              'AKUN RESMI',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: NataloColors.officialGoldOnLight,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final PublicProfile profile;
  final Color foreground;
  final Color secondary;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;

  const _StatsRow({
    required this.profile,
    required this.foreground,
    required this.secondary,
    this.onFollowersTap,
    this.onFollowingTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Stat(
            value: profile.postCount,
            label: 'Postingan',
            foreground: foreground,
            secondary: secondary,
          ),
        ),
        Expanded(
          child: _Stat(
            value: profile.followersCount,
            label: 'Pengikut',
            foreground: foreground,
            secondary: secondary,
            onTap: onFollowersTap,
          ),
        ),
        Expanded(
          child: _Stat(
            value: profile.followingCount,
            label: 'Mengikuti',
            foreground: foreground,
            secondary: secondary,
            onTap: onFollowingTap,
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final int value;
  final String label;
  final Color foreground;
  final Color secondary;
  final VoidCallback? onTap;

  const _Stat({
    required this.value,
    required this.label,
    required this.foreground,
    required this.secondary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatCountCompact(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: secondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.05,
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: '$label, ${formatCountCompact(value)}',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.small,
          child: content,
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final PublicProfile profile;
  final bool followBusy;
  final VoidCallback? onFollowToggle;
  final VoidCallback? onEditProfile;
  final VoidCallback? onShareProfile;
  final VoidCallback? onMessage;

  const _ActionRow({
    required this.profile,
    required this.followBusy,
    this.onFollowToggle,
    this.onEditProfile,
    this.onShareProfile,
    this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 1:1 IG: tombol default = fill abu netral tanpa border. Satu-satunya
    // aksen adalah "Ikuti" biru brand saat belum follow (padanan Follow
    // biru di IG); setelah follow SEMUA tombol abu.
    final neutralFill = cs.surfaceContainerHighest;
    final neutralForeground = cs.onSurface;
    final primaryCallback = profile.isOwner ? onEditProfile : onFollowToggle;
    final hasPrimary = primaryCallback != null;
    final followAccent = !profile.isOwner && !profile.isFollowing;
    return Row(
      key: const Key('public_profile_action_row'),
      children: [
        if (hasPrimary)
          Expanded(
            child: _HeaderAction(
              label: profile.isOwner
                  ? 'Edit Profil'
                  : (profile.isFollowing ? 'Mengikuti' : 'Ikuti'),
              onTap: primaryCallback,
              busy: !profile.isOwner && followBusy,
              background: followAccent ? NataloColors.primary : neutralFill,
              foreground: followAccent ? Colors.white : neutralForeground,
            ),
          ),
        if (onMessage != null) ...[
          if (hasPrimary) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _HeaderAction(
              key: const Key('official_message_button'),
              label: 'Pesan',
              onTap: onMessage,
              background: neutralFill,
              foreground: neutralForeground,
            ),
          ),
        ],
        if (onShareProfile != null) ...[
          if (hasPrimary || onMessage != null)
            const SizedBox(width: AppSpacing.sm),
          // Owner (profil sendiri) meniru IG: "Edit Profil" + "Bagikan
          // Profil" dua tombol sejajar. Viewer lain cukup ikon share.
          if (profile.isOwner)
            Expanded(
              child: _HeaderAction(
                label: 'Bagikan Profil',
                tooltip: 'Bagikan Profil',
                onTap: onShareProfile,
                background: neutralFill,
                foreground: neutralForeground,
              ),
            )
          else
            SizedBox(
              width: 44,
              child: _HeaderAction(
                semanticLabel: 'Bagikan Profil',
                tooltip: 'Bagikan Profil',
                icon: Icons.ios_share_rounded,
                onTap: onShareProfile,
                background: neutralFill,
                foreground: neutralForeground,
              ),
            ),
        ],
      ],
    );
  }
}

class _HeaderAction extends StatelessWidget {
  final String? label;
  final String? semanticLabel;
  final String? tooltip;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool busy;
  final Color background;
  final Color foreground;

  const _HeaderAction({
    super.key,
    this.label,
    this.semanticLabel,
    this.tooltip,
    this.icon,
    required this.onTap,
    this.busy = false,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedLabel = semanticLabel ?? label;
    Widget child = Semantics(
      button: true,
      enabled: !busy,
      liveRegion: busy,
      label: resolvedLabel,
      value: busy ? 'Sedang diproses' : null,
      excludeSemantics: true,
      onTap: busy ? null : onTap,
      child: SizedBox(
        height: 44,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: busy ? null : onTap,
            borderRadius: AppRadius.medium,
            child: Center(
              child: Container(
                height: 40,
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: AppRadius.medium,
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: icon != null
                    ? Icon(icon, color: foreground, size: 18)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (busy) ...[
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: foreground,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                          ],
                          Flexible(
                            child: Text(
                              label!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: foreground,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
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
    if (tooltip != null) child = Tooltip(message: tooltip!, child: child);
    return child;
  }
}
