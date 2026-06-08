import 'package:flutter/material.dart';
// Prefix lottie supaya tidak collision dengan widget Lottie lain
// (cuma dipakai di AppEmptyState.lottiePath via lottie.Lottie.asset).
import 'package:lottie/lottie.dart' as lottie;
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
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
    } else if (onVoiceTap != null) {
      suffix = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
        hintStyle: TextStyle(
          color: cs.onSurfaceVariant,
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
            ? cs.surfaceContainerHighest
            : cs.surface.withValues(alpha: 0.90),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant),
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

    // Tinggi 44px — Apple HIG minimum touch target untuk actual TextField
    // input. Beranda search bar (tap-only display) tetap 38px untuk
    // compact Instagram-style cue. Produk + HomeSearchPage pakai 44px
    // untuk typing comfort (Option B pattern: tap target compact, input
    // target generous).
    return SizedBox(height: 44, child: field);
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
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: padding,
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: cs.surfaceContainerHighest,
        highlightColor: cs.surface,
        child: Container(
          height: itemHeight,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
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
/// Kotak ikon ber-tint (rounded, background soft) — TANPA ListTile.
///
/// Dipakai sebagai `leading:` di ListTile lain, atau standalone icon badge.
/// JANGAN pakai [SoftIconTile] untuk ini — SoftIconTile adalah full ListTile
/// (punya title/subtitle/trailing sendiri); kalau ditaruh di slot leading
/// ListTile lain, layout-nya pecah jadi kotak besar kosong (bug search
/// suggestion + home search row). SoftIconBox hanya kotak ikon, aman.
class SoftIconBox extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? color;

  const SoftIconBox({
    super.key,
    required this.icon,
    this.size = 40,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? NataloColors.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: AppRadius.medium,
      ),
      child: Icon(icon, color: tint, size: size * 0.5),
    );
  }
}

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
      leading: SoftIconBox(icon: icon, size: size, color: tint),
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
      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
  /// Path ke Lottie animation asset (mis. 'assets/lottie/empty_box.json').
  /// Kalau di-set, render Lottie animation menggantikan icon. Empty state
  /// jadi lebih hidup + branded vs icon static abu-abu.
  final String? lottiePath;
  /// Tinggi Lottie animation. Default 160 — sweet spot untuk empty state
  /// tanpa dominate viewport. Override kalau perlu (mis. 200 untuk hero
  /// empty state, 120 untuk compact).
  final double lottieHeight;

  const AppEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.subtitle,
    this.body,
    this.action,
    this.buttonLabel,
    this.onPressed,
    this.lottiePath,
    this.lottieHeight = 160,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (lottiePath != null)
              SizedBox(
                height: lottieHeight,
                child: lottie.Lottie.asset(
                  lottiePath!,
                  fit: BoxFit.contain,
                  repeat: true,
                  // Frame rate cap untuk hemat battery di Lottie loop.
                  // Default 60fps di-throttle ke 30fps untuk subtle anim.
                  frameRate: const lottie.FrameRate(30),
                  // Error fallback: kalau asset tidak ada / corrupt,
                  // render icon biasa supaya UI tidak crash.
                  errorBuilder: (_, __, ___) =>
                      Icon(icon, size: 56, color: cs.onSurfaceVariant),
                ),
              )
            else
              Icon(icon, size: 56, color: cs.onSurfaceVariant),
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
                style: TextStyle(color: cs.onSurfaceVariant),
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

/// Variant untuk AppErrorState — masing-masing punya icon + copy default
/// yang sesuai jenis error. Kalau tone-nya gak match (mis. server error
/// di-default sopan tapi context kamu butuh urgent), override via title/
/// description prop.
enum AppErrorVariant {
  /// Network offline / koneksi putus. Icon: cloud_off.
  network,

  /// Server error (5xx) / endpoint down. Icon: error_outline.
  server,

  /// 404 — resource gak ditemukan. Icon: search_off.
  notFound,

  /// Generic / unknown error. Icon: error_outline.
  generic,
}

/// Inline error state — gantiin ad-hoc "Gagal memuat" plain text yang
/// muncul di puluhan screen. Wajib pakai untuk semua API error in-flow
/// supaya user punya retry button konsisten.
///
/// Beda dari [AppErrorWidget] (catastrophic Flutter render error):
///   - [AppErrorWidget] = global crash boundary di MaterialApp.builder
///   - [AppErrorState]  = inline state di FutureBuilder / FetchView /
///                        Provider error case
///
/// Pattern recommend:
/// ```dart
/// if (snapshot.hasError) {
///   return AppErrorState(
///     variant: AppErrorVariant.network,
///     onRetry: () => setState(() => _future = _loadData()),
///   );
/// }
/// ```
class AppErrorState extends StatelessWidget {
  /// Variant nentuin icon + copy default. Override via [title]/[description]
  /// kalau perlu custom.
  final AppErrorVariant variant;

  /// Override title default. Kalau null, ambil dari variant.
  final String? title;

  /// Override description default. Kalau null, ambil dari variant.
  final String? description;

  /// Override icon default. Kalau null, ambil dari variant.
  final IconData? icon;

  /// Callback retry. **WAJIB** untuk semua error state — user harus
  /// punya jalan keluar. Set ke null hanya kalau retry truly impossible
  /// (mis. resource permanently gone) — tapi case itu pakai [AppEmptyState]
  /// bukan ErrorState.
  final VoidCallback? onRetry;

  /// Label retry button. Default "Coba lagi".
  final String retryLabel;

  /// Optional secondary action (mis. "Hubungi support", "Buka WhatsApp").
  final Widget? secondaryAction;

  /// Compact mode — padding lebih kecil + icon lebih kecil. Untuk error
  /// inline di section kecil (mis. card di list). Default false = full.
  final bool compact;

  const AppErrorState({
    super.key,
    this.variant = AppErrorVariant.generic,
    this.title,
    this.description,
    this.icon,
    required this.onRetry,
    this.retryLabel = 'Coba lagi',
    this.secondaryAction,
    this.compact = false,
  });

  IconData get _resolvedIcon {
    if (icon != null) return icon!;
    switch (variant) {
      case AppErrorVariant.network:
        return Icons.cloud_off_outlined;
      case AppErrorVariant.server:
        return Icons.error_outline_rounded;
      case AppErrorVariant.notFound:
        return Icons.search_off_rounded;
      case AppErrorVariant.generic:
        return Icons.error_outline_rounded;
    }
  }

  String get _resolvedTitle {
    if (title != null) return title!;
    switch (variant) {
      case AppErrorVariant.network:
        return 'Tidak ada koneksi';
      case AppErrorVariant.server:
        return 'Server bermasalah';
      case AppErrorVariant.notFound:
        return 'Tidak ditemukan';
      case AppErrorVariant.generic:
        return 'Gagal memuat';
    }
  }

  String get _resolvedDescription {
    if (description != null) return description!;
    switch (variant) {
      case AppErrorVariant.network:
        return 'Cek koneksi internet kamu lalu coba lagi.';
      case AppErrorVariant.server:
        return 'Tim kami sudah dapat laporan. Coba lagi sebentar lagi.';
      case AppErrorVariant.notFound:
        return 'Data yang kamu cari tidak ada atau sudah dihapus.';
      case AppErrorVariant.generic:
        return 'Terjadi kesalahan. Coba lagi atau hubungi support kalau berulang.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pad = compact ? AppSpacing.lg : AppSpacing.xxl;
    final iconSize = compact ? 44.0 : 56.0;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(compact ? 14 : 18),
              decoration: BoxDecoration(
                color: NataloColors.danger.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _resolvedIcon,
                size: iconSize,
                color: NataloColors.danger,
              ),
            ),
            SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
            Text(
              _resolvedTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: compact ? 15 : 17,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _resolvedDescription,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: compact ? 12.5 : 13.5,
                height: 1.4,
              ),
            ),
            if (onRetry != null) ...[
              SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(retryLabel),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 20 : 28,
                    vertical: compact ? 10 : 12,
                  ),
                ),
              ),
            ],
            if (secondaryAction != null) ...[
              const SizedBox(height: AppSpacing.sm),
              secondaryAction!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Mapping konstanta untuk Lottie asset paths — single source of truth
/// supaya rename file Lottie tidak butuh hunt semua call site.
class AppLottiePaths {
  AppLottiePaths._();

  /// Empty state generic — kotak kosong dengan animasi subtle.
  /// Use untuk: cart kosong, wishlist kosong, orders kosong, vouchers kosong.
  static const empty = 'assets/lottie/empty_box.json';

  /// Paw print animation — branded ke pets theme.
  /// Use untuk: loading states, onboarding welcome, member intro.
  static const paw = 'assets/lottie/loading_paw.json';

  /// Order created success — celebratory checkmark / box icon.
  /// Use untuk: order confirmation, registration success, notification.
  static const orderCreated = 'assets/lottie/order_created.json';

  /// Generic success checkmark — green check animation.
  /// Use untuk: form submitted, action completed, confirmation toast.
  static const success = 'assets/lottie/success_check.json';
}
