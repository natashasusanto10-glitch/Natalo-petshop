import 'package:flutter/material.dart';

import '../models/public_profile.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/natalo_colors.dart';
import '../utils/formatters.dart';
import 'official_brand_avatar.dart';
import 'profile_avatar.dart';
import 'public_profile_mutual_followers_row.dart';

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
    return profile.isOfficial
        ? _OfficialExpandedHeader(
            profile: profile,
            followBusy: followBusy,
            onFollowToggle: profile.isOwner ? null : onFollowToggle,
            onFollowersTap: onFollowersTap,
            onFollowingTap: onFollowingTap,
            onEditProfile: profile.isOwner ? onEditProfile : null,
            onShareProfile: onShareProfile,
            onMessage: _showOfficialMessage ? onMessage : null,
          )
        : _RegularExpandedHeader(
            profile: profile,
            followBusy: followBusy,
            onFollowToggle: profile.isOwner ? null : onFollowToggle,
            onFollowersTap: onFollowersTap,
            onFollowingTap: onFollowingTap,
            onEditProfile: profile.isOwner ? onEditProfile : null,
            onShareProfile: onShareProfile,
          );
  }
}

class _OfficialExpandedHeader extends StatelessWidget {
  final PublicProfile profile;
  final bool followBusy;
  final VoidCallback? onFollowToggle;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onEditProfile;
  final VoidCallback? onShareProfile;
  final VoidCallback? onMessage;

  const _OfficialExpandedHeader({
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
    final hasBio = profile.bio?.trim().isNotEmpty == true;
    final hasMutuals = !profile.isOwner &&
        profile.mutualFollowers.items.isNotEmpty &&
        profile.mutualFollowers.totalCount > 0;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: NataloColors.heroGradientV),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const ProfileAvatar(
                  initial: 'N',
                  size: 78,
                  fontSize: 28,
                  isOfficial: true,
                  plain: true,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        const OfficialVerifiedBadge(size: 18),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const _OfficialChip(),
                  ],
                ),
              ),
            ],
          ),
          if (hasBio) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              profile.bio!.trim(),
              maxLines: largeText ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          if (hasMutuals) ...[
            const SizedBox(height: AppSpacing.md),
            PublicProfileMutualFollowersRow(summary: profile.mutualFollowers),
          ],
          const SizedBox(height: AppSpacing.md),
          _StatsRow(
            profile: profile,
            foreground: Colors.white,
            secondary: Colors.white.withValues(alpha: 0.72),
            onFollowersTap: onFollowersTap,
            onFollowingTap: onFollowingTap,
          ),
          const SizedBox(height: AppSpacing.sm),
          _ActionRow(
            profile: profile,
            followBusy: followBusy,
            onFollowToggle: onFollowToggle,
            onEditProfile: onEditProfile,
            onShareProfile: onShareProfile,
            onMessage: onMessage,
            onHero: true,
          ),
        ],
      ),
    );
  }
}

class _RegularExpandedHeader extends StatelessWidget {
  final PublicProfile profile;
  final bool followBusy;
  final VoidCallback? onFollowToggle;
  final VoidCallback? onFollowersTap;
  final VoidCallback? onFollowingTap;
  final VoidCallback? onEditProfile;
  final VoidCallback? onShareProfile;

  const _RegularExpandedHeader({
    required this.profile,
    required this.followBusy,
    this.onFollowToggle,
    this.onFollowersTap,
    this.onFollowingTap,
    this.onEditProfile,
    this.onShareProfile,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasBio = profile.bio?.trim().isNotEmpty == true;
    return ColoredBox(
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ProfileAvatar(
                  initial: profile.initial,
                  imageUrl: profile.profilePhotoUrl,
                  size: 78,
                  fontSize: 28,
                  plain: true,
                ),
                const SizedBox(width: AppSpacing.md),
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
            Text(
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
            if (profile.username?.isNotEmpty == true) ...[
              const SizedBox(height: 2),
              Text(
                '@${profile.username}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (hasBio) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                profile.bio!.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            _ActionRow(
              profile: profile,
              followBusy: followBusy,
              onFollowToggle: onFollowToggle,
              onEditProfile: onEditProfile,
              onShareProfile: onShareProfile,
              onHero: false,
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
              color: NataloColors.officialGold, size: 13),
          SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              'AKUN RESMI',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: NataloColors.officialGold,
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
  final bool onHero;

  const _ActionRow({
    required this.profile,
    required this.followBusy,
    required this.onHero,
    this.onFollowToggle,
    this.onEditProfile,
    this.onShareProfile,
    this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final outline =
        onHero ? Colors.white.withValues(alpha: 0.55) : cs.outlineVariant;
    final foreground = onHero ? Colors.white : cs.onSurface;
    final primaryCallback = profile.isOwner ? onEditProfile : onFollowToggle;
    final hasPrimary = primaryCallback != null;
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
              background: !profile.isOwner && !profile.isFollowing
                  ? (onHero ? Colors.white : NataloColors.primary)
                  : Colors.transparent,
              foreground: !profile.isOwner && !profile.isFollowing
                  ? (onHero ? NataloColors.heroBottom : Colors.white)
                  : foreground,
              border: !profile.isOwner && !profile.isFollowing
                  ? Colors.transparent
                  : outline,
            ),
          ),
        if (onMessage != null) ...[
          if (hasPrimary) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _HeaderAction(
              key: const Key('official_message_button'),
              label: 'Pesan',
              onTap: onMessage,
              background: Colors.transparent,
              foreground: foreground,
              border: outline,
            ),
          ),
        ],
        if (onShareProfile != null) ...[
          if (hasPrimary || onMessage != null)
            const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 44,
            child: _HeaderAction(
              semanticLabel: 'Bagikan Profil',
              tooltip: 'Bagikan Profil',
              icon: Icons.ios_share_rounded,
              onTap: onShareProfile,
              background: Colors.transparent,
              foreground: foreground,
              border: outline,
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
  final Color border;

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
    required this.border,
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
                  border: Border.all(color: border),
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
