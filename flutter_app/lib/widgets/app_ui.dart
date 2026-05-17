import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'glass_surface.dart';

class AppPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final bool enableHaptic;
  final double pressedScale;

  const AppPressable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.enableHaptic = true,
    this.pressedScale = 0.975,
  });

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  Future<void> _handleTap() async {
    if (widget.enableHaptic) {
      await HapticFeedback.selectionClick();
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(20);
    return MouseRegion(
      cursor:
          widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null ? null : _handleTap,
        onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? widget.pressedScale : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: ClipRRect(
            borderRadius: radius,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class AppHeaderIconButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  const AppHeaderIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 42,
            width: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.94)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandBlue.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: IconTheme(
              data: const IconThemeData(color: AppColors.ink, size: 24),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class AppSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

class AppSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final String query;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  // Voice search button — kalau di-pass DAN query kosong, mic muncul di
  // suffix. Saat user mulai ketik, suffix swap ke close icon.
  final VoidCallback? onVoiceTap;
  // Barcode scanner button — sama kondisi seperti voice. Kalau dua-duanya
  // di-pass, muncul barcode + mic berdampingan di suffix.
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
      final actions = <Widget>[
        if (onBarcodeTap != null)
          IconButton(
            onPressed: onBarcodeTap,
            icon: const Icon(
              Icons.qr_code_scanner_rounded,
              color: AppColors.brandBlue,
            ),
            tooltip: 'Scan barcode',
            visualDensity: VisualDensity.compact,
          ),
        if (onVoiceTap != null)
          IconButton(
            onPressed: onVoiceTap,
            icon: const Icon(Icons.mic_rounded, color: AppColors.brandBlue),
            tooltip: 'Cari dengan suara',
            visualDensity: VisualDensity.compact,
          ),
      ];
      suffix = Row(
        mainAxisSize: MainAxisSize.min,
        children: actions,
      );
    }
    final field = TextField(
      controller: controller,
      style: TextStyle(fontSize: compact ? 13 : null),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: compact,
        hintText: hintText,
        hintStyle: compact
            ? const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              )
            : null,
        prefixIcon: Icon(Icons.search_rounded, size: compact ? 20 : null),
        prefixIconConstraints:
            compact ? const BoxConstraints(minWidth: 42, minHeight: 40) : null,
        suffixIcon: suffix,
        filled: true,
        fillColor: compact
            ? const Color(0xFFF8FAFC)
            : Colors.white.withValues(alpha: 0.90),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compact ? 14 : 18),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compact ? 14 : 18),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compact ? 14 : 18),
          borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.4),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 0,
          vertical: compact ? 10 : 14,
        ),
      ),
    );
    if (!compact) return field;
    return SizedBox(height: 42, child: field);
  }
}

class AppInfoBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;

  const AppInfoBanner({
    super.key,
    required this.icon,
    required this.message,
    this.color = const Color(0xFFF59E0B),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const AppStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(icon == null ? 10 : 8, 6, 10, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class AppAnimatedEntrance extends StatelessWidget {
  final Widget child;
  final int index;
  final double offsetY;

  const AppAnimatedEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.offsetY = 18,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 240 + (index * 55).clamp(0, 220)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * offsetY),
            child: Transform.scale(
              scale: 0.985 + (value * 0.015),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

class AppSkeletonBox extends StatefulWidget {
  final double height;
  final double width;
  final double radius;

  const AppSkeletonBox({
    super.key,
    required this.height,
    this.width = double.infinity,
    this.radius = 18,
  });

  @override
  State<AppSkeletonBox> createState() => _AppSkeletonBoxState();
}

class _AppSkeletonBoxState extends State<AppSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.2 + (_controller.value * 2.4), 0),
              end: Alignment(-0.2 + (_controller.value * 2.4), 0),
              colors: const [
                Color(0xFFEFF4FA),
                Color(0xFFF8FBFF),
                Color(0xFFEFF4FA),
              ],
            ),
          ),
        );
      },
    );
  }
}

class AppSkeletonList extends StatelessWidget {
  final int itemCount;
  final EdgeInsetsGeometry padding;

  const AppSkeletonList({
    super.key,
    this.itemCount = 4,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 24),
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return const GlassSurface(
          radius: 22,
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              AppSkeletonBox(height: 58, width: 58, radius: 18),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeletonBox(height: 16, radius: 999),
                    SizedBox(height: 10),
                    AppSkeletonBox(height: 13, width: 170, radius: 999),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class AppGlassBottomBar extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AppGlassBottomBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 12),
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: padding,
        child: GlassSurface(
          radius: 28,
          blur: 20,
          tint: const Color(0xFFFCFEFF),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: child,
        ),
      ),
    );
  }
}
