import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';

/// Offline banner — slide-in dari top saat koneksi hilang, slide-out saat
/// reconnect. Auto-show via AnimatedBuilder subscribe ke connectivityService.
///
/// Pasang di root MaterialApp.builder supaya muncul di atas semua screen.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: connectivityService,
      builder: (context, _) {
        return AnimatedSlide(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          offset: connectivityService.isOffline
              ? Offset.zero
              : const Offset(0, -1.2),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: connectivityService.isOffline ? 1 : 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Material(
                  elevation: 8,
                  shadowColor: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(16),
                  color: const Color(0xFFEF4444),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tidak ada koneksi internet',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          'Beberapa fitur dibatasi',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
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
      },
    );
  }
}
