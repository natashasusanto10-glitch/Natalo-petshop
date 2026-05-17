import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/app_crashlytics.dart';
import '../theme/natalo_colors.dart';

/// Custom branded error widget — replace Flutter default red "Bad state"
/// screen. Debug build: show full stacktrace. Release: friendly UI + report
/// crashlytics fire-and-forget.
class AppErrorWidget extends StatelessWidget {
  final FlutterErrorDetails details;

  const AppErrorWidget(this.details, {super.key});

  static Widget builder(FlutterErrorDetails details) {
    // Fire-and-forget report ke Crashlytics. Tidak block UI.
    AppCrashlytics.recordError(
      details.exception,
      details.stack,
      reason: details.summary.toString(),
      fatal: false,
    );
    return AppErrorWidget(details);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NataloColors.background,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: NataloColors.danger,
            ),
            const SizedBox(height: 16),
            const Text(
              'Terjadi kesalahan',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Bagian aplikasi ini mengalami error. Tim kami sudah dapat laporan.',
              textAlign: TextAlign.center,
              style: TextStyle(color: NataloColors.textSecondary),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                color: const Color(0x11FF0000),
                child: Text(
                  details.exceptionAsString(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
