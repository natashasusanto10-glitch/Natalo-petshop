import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/natalo_colors.dart';

import '../services/voice_search_service.dart';
import '../utils/haptics.dart';
import 'app_toast.dart';

const _brandBlue = NataloColors.primary;

/// Tampilkan modal voice search. Resolves dengan transcript akhir (string),
/// atau `null` kalau user cancel / error.
///
/// Flow:
/// 1. Initialize service (request mic permission via OS prompt)
/// 2. Show modal — animated mic icon pulse + live transcript text
/// 3. Auto-finalize saat user diam 3 detik atau tap "Selesai"
/// 4. Return transcript ke caller (biasanya di-set ke search field)
Future<String?> showVoiceSearchModal(BuildContext context) async {
  final ready = await voiceSearchService.initialize();
  if (!context.mounted) return null;

  if (!ready) {
    // Tidak ada recognizer / permission denied permanen.
    AppToast.showBanner(
      context,
      'Pencarian suara tidak tersedia. Cek izin mikrofon di pengaturan.',
      kind: ToastKind.warning,
    );
    return null;
  }

  AppHaptics.tap();

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _VoiceSearchSheet(),
  );
}

class _VoiceSearchSheet extends StatefulWidget {
  const _VoiceSearchSheet();

  @override
  State<_VoiceSearchSheet> createState() => _VoiceSearchSheetState();
}

class _VoiceSearchSheetState extends State<_VoiceSearchSheet>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  StreamSubscription<VoiceTranscript>? _subscription;
  String _transcript = '';
  bool _isFinal = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _startListening();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _subscription?.cancel();
    voiceSearchService.cancel();
    super.dispose();
  }

  void _startListening() {
    setState(() {
      _transcript = '';
      _isFinal = false;
      _error = null;
    });
    final stream = voiceSearchService.listen();
    _subscription = stream.listen(
      (event) {
        if (!mounted) return;
        setState(() {
          _transcript = event.text;
          _isFinal = event.isFinal;
        });
        if (event.isFinal && event.text.trim().isNotEmpty) {
          // Auto-close + return transcript setelah final result.
          Future.delayed(const Duration(milliseconds: 350), () {
            if (mounted) {
              AppHaptics.success();
              Navigator.of(context).pop(event.text.trim());
            }
          });
        }
      },
      onError: (Object err) {
        if (!mounted) return;
        setState(() => _error = err.toString());
      },
      onDone: () {
        if (!mounted) return;
        if (_transcript.trim().isEmpty && _error == null) {
          setState(() => _error = 'Tidak terdengar suara. Coba lagi.');
        }
      },
    );
  }

  void _stopAndReturn() {
    final text = _transcript.trim();
    if (text.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    AppHaptics.success();
    Navigator.of(context).pop(text);
  }

  void _retry() {
    AppHaptics.tap();
    voiceSearchService.cancel().then((_) {
      if (mounted) _startListening();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF111111) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111111);
    final subTextColor =
        isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Container(
            color: bgColor,
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle grip
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 22),
                // Animated pulse mic
                _AnimatedMic(controller: _pulseController, hasError: _error != null),
                const SizedBox(height: 22),
                Text(
                  _error != null
                      ? 'Ups, tidak terdengar'
                      : _isFinal
                          ? 'Selesai'
                          : 'Bicara sekarang...',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _error ?? 'Coba: "makanan kucing", "bola anjing", "shampoo"',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: subTextColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                // Live transcript
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _transcript.isEmpty
                      ? const SizedBox(
                          key: ValueKey('empty'),
                          height: 32,
                        )
                      : Container(
                          key: const ValueKey('text'),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: _brandBlue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '"$_transcript"',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _brandBlue,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              height: 1.4,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _error != null ? _retry : () {
                          AppHaptics.tap();
                          Navigator.of(context).pop();
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: Text(
                          _error != null ? 'Coba lagi' : 'Batal',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _transcript.trim().isEmpty
                            ? null
                            : _stopAndReturn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brandBlue,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              _brandBlue.withValues(alpha: 0.35),
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        child: const Text('Cari'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedMic extends StatelessWidget {
  final AnimationController controller;
  final bool hasError;

  const _AnimatedMic({required this.controller, required this.hasError});

  @override
  Widget build(BuildContext context) {
    final color = hasError ? const Color(0xFFE11D48) : _brandBlue;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        // 2 concentric ripple rings dengan offset phase, tampak organik.
        return SizedBox(
          width: 140,
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _ripple(t, color, scale: 0.6, opacity: 0.32),
              _ripple((t + 0.35) % 1, color, scale: 0.6, opacity: 0.18),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  hasError ? Icons.mic_off_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ripple(double t, Color color,
      {required double scale, required double opacity}) {
    final eased = Curves.easeOut.transform(t);
    final size = 76 + (140 - 76) * eased;
    final alpha = (1 - eased) * opacity;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: math.max(alpha, 0)),
        shape: BoxShape.circle,
      ),
    );
  }
}
