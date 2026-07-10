import 'dart:async';

import 'package:flutter/material.dart';

/// Reactive countdown timer untuk Flash Sale section header + product
/// detail badge. Format HH:MM:SS. Auto-stop saat reach 00:00:00.
///
/// Performance:
/// - Pakai Timer.periodic 1 detik (tidak butuh frame-by-frame precision).
/// - Compute remaining duration di setiap tick (resilient ke app
///   suspend/resume — re-sync ke real time, tidak drift).
/// - Saat reach 0, cancel timer + trigger onExpired callback → parent
///   bisa refresh list / hide section.
///
/// Visual:
/// - 3 segment box: JAM : MNT : DET dengan separator ":".
/// - Soft red gradient bg supaya stand out (urgency cue).
/// - Pulse animation di last hour (remaining < 1 hour) — extra urgency.
class FlashSaleCountdown extends StatefulWidget {
  /// Target end time. Counter count-down sampai timestamp ini.
  final DateTime endsAt;

  /// Callback saat countdown reach 00:00:00. Parent bisa setState
  /// (refresh products list, hide section, etc).
  final VoidCallback? onExpired;

  /// Style variant — section header (large, 3-box prominent) atau
  /// product detail badge (compact, inline pill).
  final _CountdownStyle _style;

  const FlashSaleCountdown({
    super.key,
    required this.endsAt,
    this.onExpired,
  }) : _style = _CountdownStyle.section;

  const FlashSaleCountdown.compact({
    super.key,
    required this.endsAt,
    this.onExpired,
  }) : _style = _CountdownStyle.compact;

  const FlashSaleCountdown.digitsOnly({
    super.key,
    required this.endsAt,
    this.onExpired,
  }) : _style = _CountdownStyle.digitsOnly;

  /// Boxes-only HH:MM:SS — 3 kotak merah + separator, tanpa label/bg
  /// pembungkus. Dipakai di pita Flash Sale beranda (Opsi B) langsung di
  /// atas band rose, senada warna judul.
  const FlashSaleCountdown.boxes({
    super.key,
    required this.endsAt,
    this.onExpired,
  }) : _style = _CountdownStyle.boxes;

  @override
  State<FlashSaleCountdown> createState() => _FlashSaleCountdownState();
}

enum _CountdownStyle { section, compact, digitsOnly, boxes }

class _FlashSaleCountdownState extends State<FlashSaleCountdown> {
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  static const _urgencyThreshold = Duration(hours: 1);

  @override
  void initState() {
    super.initState();
    _recompute();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _recompute());
  }

  @override
  void didUpdateWidget(covariant FlashSaleCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endsAt != widget.endsAt) {
      _recompute();
    }
  }

  void _recompute() {
    final diff = widget.endsAt.difference(DateTime.now());
    if (!mounted) return;
    if (diff <= Duration.zero) {
      _ticker?.cancel();
      setState(() => _remaining = Duration.zero);
      // Defer callback supaya tidak fire di tengah build phase.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onExpired?.call();
      });
      return;
    }
    setState(() => _remaining = diff);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    if (_remaining <= Duration.zero) {
      return const SizedBox.shrink();
    }
    final hours = _remaining.inHours;
    final minutes = _remaining.inMinutes.remainder(60);
    final seconds = _remaining.inSeconds.remainder(60);
    final isUrgent = _remaining < _urgencyThreshold;

    if (widget._style == _CountdownStyle.compact) {
      return _CompactBadge(
        hours: hours,
        minutes: minutes,
        seconds: seconds,
        isUrgent: isUrgent,
        formatTwo: _two,
      );
    }
    if (widget._style == _CountdownStyle.digitsOnly) {
      return _DigitsOnlyCountdown(
        hours: hours,
        minutes: minutes,
        seconds: seconds,
        formatTwo: _two,
      );
    }
    if (widget._style == _CountdownStyle.boxes) {
      return _BoxesCountdown(
        hours: hours,
        minutes: minutes,
        seconds: seconds,
        formatTwo: _two,
      );
    }
    return _SectionHeaderTimer(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      isUrgent: isUrgent,
      formatTwo: _two,
    );
  }
}

class _DigitsOnlyCountdown extends StatelessWidget {
  final int hours;
  final int minutes;
  final int seconds;
  final String Function(int) formatTwo;

  const _DigitsOnlyCountdown({
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.formatTwo,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      '${formatTwo(hours)}:${formatTwo(minutes)}:${formatTwo(seconds)}',
      maxLines: 1,
      overflow: TextOverflow.clip,
      softWrap: false,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w900,
        height: 1,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Boxes-only HH:MM:SS — 3 kotak merah + separator, tanpa label/bg
/// pembungkus (beda dari _SectionHeaderTimer yang punya "Berakhir" + bg).
/// Dipakai di pita Flash Sale beranda (Opsi B).
class _BoxesCountdown extends StatelessWidget {
  final int hours;
  final int minutes;
  final int seconds;
  final String Function(int) formatTwo;

  const _BoxesCountdown({
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.formatTwo,
  });

  @override
  Widget build(BuildContext context) {
    // Senada judul pita + chip diskon + harga (0xFFE11D48). Putih di atas
    // merah tetap terbaca di band rose muda maupun rose gelap (dark mode).
    const accent = Color(0xFFE11D48);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TimeBox(label: formatTwo(hours), accent: accent),
        const _Separator(accent: accent),
        _TimeBox(label: formatTwo(minutes), accent: accent),
        const _Separator(accent: accent),
        _TimeBox(label: formatTwo(seconds), accent: accent),
      ],
    );
  }
}

/// Section header timer — 3-box HH:MM:SS prominent. Dipakai di atas
/// _FlashSaleGrid di home.
class _SectionHeaderTimer extends StatelessWidget {
  final int hours;
  final int minutes;
  final int seconds;
  final bool isUrgent;
  final String Function(int) formatTwo;

  const _SectionHeaderTimer({
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.isUrgent,
    required this.formatTwo,
  });

  @override
  Widget build(BuildContext context) {
    // Flash Sale color scheme = MERAH (consistent dengan banner + badge
    // "Harga Diskon"). Sebelumnya non-urgent orange. Sekarang dua-duanya
    // red, beda intensity: urgent = darker red + saturated bg.
    final accent = isUrgent ? const Color(0xFFDC2626) : const Color(0xFFEF4444);
    final bg = isUrgent ? const Color(0xFFFECACA) : const Color(0xFFFEE2E2);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.20), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.access_time_rounded, color: accent, size: 16),
          const SizedBox(width: 6),
          Text(
            'Berakhir',
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          _TimeBox(label: formatTwo(hours), accent: accent),
          _Separator(accent: accent),
          _TimeBox(label: formatTwo(minutes), accent: accent),
          _Separator(accent: accent),
          _TimeBox(label: formatTwo(seconds), accent: accent),
        ],
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  final String label;
  final Color accent;

  const _TimeBox({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  final Color accent;

  const _Separator({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Text(
        ':',
        style: TextStyle(
          color: accent,
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// Compact badge — inline pill untuk product detail page.
class _CompactBadge extends StatelessWidget {
  final int hours;
  final int minutes;
  final int seconds;
  final bool isUrgent;
  final String Function(int) formatTwo;

  const _CompactBadge({
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.isUrgent,
    required this.formatTwo,
  });

  @override
  Widget build(BuildContext context) {
    // Compact variant — keep red palette consistent dengan full variant.
    final accent = isUrgent ? const Color(0xFFDC2626) : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, accent.withValues(alpha: 0.85)],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.30),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.bolt_rounded,
            color: Colors.white,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            'Flash Sale berakhir ${formatTwo(hours)}:${formatTwo(minutes)}:${formatTwo(seconds)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
