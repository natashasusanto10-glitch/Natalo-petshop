import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../theme/natalo_colors.dart';

/// Banner di top yang auto slide-in/out berdasar connectivity status.
/// Visible saat offline, hide otomatis saat reconnect.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: connectivityService,
      builder: (context, _) {
        final offline = connectivityService.isOffline;
        return AnimatedSlide(
          offset: offline ? Offset.zero : const Offset(0, -1),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: offline ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: SafeArea(
              bottom: false,
              child: Container(
                color: NataloColors.warning,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.wifi_off_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tidak ada koneksi internet',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
