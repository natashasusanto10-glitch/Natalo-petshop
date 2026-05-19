import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/natalo_colors.dart';

/// Kumpulan widget UI primitives generik — header icon button, skeleton list,
/// empty state, dst. Single file untuk avoid import sprawl.

class AppHeaderIconButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final String? tooltip;

  const AppHeaderIconButton({
    super.key,
    required this.child,
    this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: onPressed,
      icon: child,
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class AppSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final String query;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final VoidCallback? onVoiceTap;
  final VoidCallback? onBarcodeTap;
  final bool compact;

  const AppSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.query,
    required this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.onVoiceTap,
    this.onBarcodeTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget? suffix;
    if (query.isNotEmpty) {
      suffix = IconButton(
        onPressed: onClear ??
            () {
              controller.clear();
              onChanged('');
            },
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Hapus',
      );
    } else if (onBarcodeTap != null || onVoiceTap != null) {
      suffix = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onBarcodeTap != null)
            IconButton(
              onPressed: onBarcodeTap,
              icon: const Icon(
                Icons.qr_code_scanner_rounded,
                color: NataloColors.primary,
              ),
              tooltip: 'Scan barcode',
              visualDensity: VisualDensity.compact,
            ),
          if (onVoiceTap != null)
            IconButton(
              onPressed: onVoiceTap,
              icon: const Icon(
                Icons.mic_rounded,
                color: NataloColors.primary,
              ),
              tooltip: 'Cari dengan suara',
              visualDensity: VisualDensity.compact,
            ),
        ],
      );
    }

    final field = TextField(
      controller: controller,
      style: const TextStyle(fontSize: 13),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        // Compact 42px height: minHeight 42 + vertical padding 8 supaya
        // total field rendered = 42px (match home_screen search pill).
        prefixIconConstraints:
            const BoxConstraints(minWidth: 42, minHeight: 42),
        suffixIcon: suffix,
        filled: true,
        fillColor: compact
            ? const Color(0xFFF8FAFC)
            : Colors.white.withValues(alpha: 0.90),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NataloColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NataloColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NataloColors.primary, width: 1.4),
        ),
        // Total height: 8 + ~24 (text 13 + line-height) + 8 = ~40px content
        // + 2px border = ~42px. Match home_screen tap-area search pill.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        isDense: true,
      ),
    );

    // Selalu fix tinggi 42px — konsisten di Beranda + Produk screen,
    // match pattern Tokopedia/Shopee. `compact` flag tetap ada untuk
    // backward compat tapi sekarang affect fill color saja, bukan size.
    return SizedBox(height: 42, child: field);
  }
}

/// Skeleton placeholder untuk list saat loading.
class AppSkeletonList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final EdgeInsets padding;

  const AppSkeletonList({
    super.key,
    this.itemCount = 6,
    this.itemHeight = 80,
    this.padding = AppSpacing.screenPadding,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: NataloColors.surface,
        highlightColor: NataloColors.border,
        child: Container(
          height: itemHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.medium,
          ),
        ),
      ),
    );
  }
}

/// Tappable wrapper dengan rounded ink splash. Pakai BorderRadius dari
/// borderRadius kalau dikasih, default radius token medium.
class AppPressable extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final EdgeInsets padding;

  const AppPressable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius ?? AppRadius.medium,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Sticky bottom bar dengan frosted-glass background — buat CTA persistent
/// (Beli Sekarang, dll). Diletakkan di Scaffold.bottomNavigationBar.
class AppGlassBottomBar extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const AppGlassBottomBar({
    super.key,
    required this.child,
    this.padding = AppSpacing.bottomBarPadding,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withValues(alpha: 0.65)
              : Colors.white.withValues(alpha: 0.92),
          border: Border(
            top: BorderSide(
              color: isDark ? NataloColors.borderDark : NataloColors.border,
              width: 1,
            ),
          ),
        ),
        padding: padding,
        child: child,
      ),
    );
  }
}

/// Status pill (label berwarna kecil) — untuk status order, badge filter, dll.
/// Boleh dipanggil dengan `label` atau `title` (alias).
class AppStatusPill extends StatelessWidget {
  final String? label;
  final String? title;
  final Color color;
  final IconData? icon;

  /// Ukuran font + padding. Default 11px font.
  final double size;

  const AppStatusPill({
    super.key,
    this.label,
    this.title,
    this.color = NataloColors.primary,
    this.icon,
    this.size = 11,
  }) : assert(label != null || title != null,
            'AppStatusPill butuh label atau title');

  String get _text => (label ?? title)!;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size <= 11 ? AppSpacing.md : AppSpacing.lg,
        vertical: size <= 11 ? AppSpacing.xs : AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pill,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: size + 2, color: color),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            _text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: size,
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft-style ListTile dengan icon kotak + chevron. Dipakai di setting /
/// detail screens untuk grouped nav rows.
class SoftIconTile extends StatelessWidget {
  final IconData icon;

  /// Title row utama. Boleh dipanggil dengan `title` atau `label`.
  final String? title;
  final String? label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Color untuk icon — boleh `iconColor` atau `color`.
  final Color? iconColor;
  final Color? color;

  /// Ukuran icon container — default 40.
  final double size;

  const SoftIconTile({
    super.key,
    required this.icon,
    this.title,
    this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.color,
    this.size = 40,
  });

  String get _title => title ?? label ?? '';

  @override
  Widget build(BuildContext context) {
    final tint = color ?? iconColor ?? NataloColors.primary;
    return ListTile(
      leading: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.12),
          borderRadius: AppRadius.medium,
        ),
        child: Icon(icon, color: tint, size: size * 0.5),
      ),
      title: Text(
        _title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing ??
          (onTap == null ? null : const Icon(Icons.chevron_right_rounded)),
      onTap: onTap,
    );
  }
}

/// Banner informasi non-blocking, biasanya di-show di top body sebelum konten.
class AppInfoBanner extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color color;

  const AppInfoBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.color = NataloColors.info,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      padding: AppSpacing.cardPaddingSmall,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.medium,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wrapper animasi fade+slide untuk list/card entries — versi yang accept
/// `index` untuk staggered delay sederhana.
class AppAnimatedEntrance extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration baseDuration;

  const AppAnimatedEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.baseDuration = const Duration(milliseconds: 280),
  });

  @override
  State<AppAnimatedEntrance> createState() => _AppAnimatedEntranceState();
}

class _AppAnimatedEntranceState extends State<AppAnimatedEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.baseDuration,
  );

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: 40 * widget.index.clamp(0, 8));
    Future<void>.delayed(delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// Stub Lottie asset — kalau asset file tidak ada di assets/lottie/,
/// fallback ke icon. Dipakai untuk empty-state animasi.
class AppLottieAsset extends StatelessWidget {
  final String asset;
  final double size;
  final bool repeat;
  final IconData fallbackIcon;

  const AppLottieAsset({
    super.key,
    required this.asset,
    this.size = 120,
    this.repeat = true,
    this.fallbackIcon = Icons.pets_rounded,
  });

  @override
  Widget build(BuildContext context) {
    // TODO: pakai package:lottie LottieBuilder.asset(asset) — saat ini
    // fallback ke icon supaya tidak crash kalau asset belum ada.
    return Icon(
      fallbackIcon,
      size: size,
      color: NataloColors.textTertiary,
    );
  }
}

/// Empty-state placeholder.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? body;
  final Widget? action;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  const AppEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.subtitle,
    this.body,
    this.action,
    this.buttonLabel,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: NataloColors.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            if (subtitle != null || body != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle ?? body!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: NataloColors.textSecondary),
              ),
            ],
            if (action != null ||
                (buttonLabel != null && onPressed != null)) ...[
              const SizedBox(height: AppSpacing.lg),
              action ??
                  ElevatedButton(
                    onPressed: onPressed,
                    child: Text(buttonLabel!),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
