import 'package:flutter/material.dart';

import '../services/biometric_service.dart';
import '../state/member_store.dart';

/// App lock gate — wraps root MaterialApp dengan WidgetsBindingObserver
/// untuk detect lifecycle changes.
///
/// Behavior:
/// - Kalau user login + biometric enabled: lock app saat background >30s
/// - Saat foreground kembali, tampilkan biometric prompt
/// - Sukses → unlock. Gagal/cancel → tetap di lock screen
///
/// Pattern bank app: minimize info leak saat HP ditinggal. Capacitor
/// WebView tidak bisa: tidak punya hook ke OS lifecycle yang reliable
/// + tidak bisa trigger biometric prompt.
class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  static const _lockThreshold = Duration(seconds: 30);
  DateTime? _pausedAt;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final paused = _pausedAt;
      _pausedAt = null;
      if (paused == null) return;
      final delta = DateTime.now().difference(paused);
      // Hanya lock kalau user login DAN biometric enabled DAN background
      // lebih lama dari threshold. Anti annoying-too-often.
      if (delta < _lockThreshold) return;
      _maybeLock();
    }
  }

  Future<void> _maybeLock() async {
    if (!memberStore.isLoggedIn) return;
    final enabled = await biometricService.isEnabled();
    if (!enabled) return;
    if (mounted) setState(() => _locked = true);
  }

  Future<void> _unlock() async {
    final ok = await biometricService.authenticate(
      reason: 'Verifikasi untuk lanjut ke Natalo Petshop',
    );
    if (ok && mounted) {
      setState(() => _locked = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: _LockOverlay(onUnlock: _unlock),
          ),
      ],
    );
  }
}

class _LockOverlay extends StatefulWidget {
  final VoidCallback onUnlock;

  const _LockOverlay({required this.onUnlock});

  @override
  State<_LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends State<_LockOverlay> {
  @override
  void initState() {
    super.initState();
    // Auto-prompt biometric saat overlay muncul.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onUnlock();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E5FBF),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                // Pakai icon-only.png (square iOS-style) — exact match
                // Capacitor. brand/logo.png wordmark horizontal akan ter-crop
                // di 88x88 square.
                child: Image.asset(
                  'assets/native/icon-only.png',
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 88,
                    height: 88,
                    child: Center(
                      child: Icon(
                        Icons.shield_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Natalo Petshop',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'App dikunci untuk keamanan',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: widget.onUnlock,
                icon: const Icon(Icons.fingerprint_rounded, size: 24),
                label: const Text('Buka kunci'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1E5FBF),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
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
