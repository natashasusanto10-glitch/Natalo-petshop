import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/app_crashlytics.dart';

/// Custom error widget — replace Flutter default red `ErrorWidget` (banner
/// "An error occurred" + gray "🌶 Bad state") yang muncul saat widget build
/// throws.
///
/// Strategy:
/// - **Debug build**: show full error details supaya developer cepat debug
/// - **Release build**: branded friendly UI ("Maaf, terjadi kendala") +
///   crashlytics report fired di background. User tidak panik liat red screen.
///
/// Wire di `main.dart`:
/// ```dart
/// ErrorWidget.builder = AppErrorWidget.builder;
/// ```
class AppErrorWidget extends StatelessWidget {
  final FlutterErrorDetails details;

  const AppErrorWidget({super.key, required this.details});

  /// Static builder untuk `ErrorWidget.builder` di main.
  static Widget builder(FlutterErrorDetails details) {
    // Report ke Crashlytics fire-and-forget — di-fire di builder time supaya
    // setiap kemunculan error widget ter-record (not just hook level).
    AppCrashlytics.recordError(
      details.exception,
      details.stack,
      reason: 'Widget build error',
    );
    return AppErrorWidget(details: details);
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      // Dev mode: show full details supaya cepat fix.
      return _DebugErrorView(details: details);
    }
    // Production: branded friendly UI.
    return const _ReleaseErrorView();
  }
}

/// Production error UI — friendly, branded, tidak scary.
class _ReleaseErrorView extends StatelessWidget {
  const _ReleaseErrorView();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFFFEF3C7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.sentiment_dissatisfied_rounded,
                color: Color(0xFFD97706),
                size: 40,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Ada kendala di bagian ini',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF111111),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Coba tarik ke bawah untuk muat ulang atau buka kembali '
              'halaman ini. Tim kami sudah otomatis dapat laporan.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Debug error UI — show full stacktrace untuk developer.
class _DebugErrorView extends StatelessWidget {
  final FlutterErrorDetails details;

  const _DebugErrorView({required this.details});

  @override
  Widget build(BuildContext context) {
    final exception = details.exception.toString();
    final stack = details.stack?.toString() ?? '(no stack)';
    return Material(
      color: const Color(0xFFFEF2F2),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'DEBUG',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Widget Build Error',
                      style: TextStyle(
                        color: Color(0xFFB91C1C),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(
                  exception,
                  style: const TextStyle(
                    color: Color(0xFF111111),
                    fontSize: 12,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Stack trace:',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  stack,
                  style: const TextStyle(
                    color: Color(0xFF374151),
                    fontSize: 10,
                    fontFamily: 'monospace',
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
