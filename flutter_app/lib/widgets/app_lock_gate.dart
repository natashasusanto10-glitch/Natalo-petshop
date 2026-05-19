import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/biometric_service.dart';
import '../state/settings_store.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';

/// Biometric app lock gate.
///
/// Kalau `appSettingsStore.appLockEnabled == true`:
/// - **Cold start**: tampil LockScreen → user wajib biometric authenticate
///   sebelum content app accessible.
/// - **Resume from background** (>= 60 detik di-pause): lock ulang.
///
/// Pattern security app fintech / marketplace yang handle data sensitif —
/// kalau HP user dipinjam orang, attacker tidak bisa lihat akun.
///
/// Implementation note: pakai `WidgetsBindingObserver.didChangeAppLifecycleState`
/// untuk detect pause/resume. Lock screen overlay full-screen, tidak bisa
/// di-bypass dengan back button (system overlay).
///
/// Terpisah dari `biometricService.isEnabled()` — yang khusus untuk LOGIN
/// auto-fill credential. App lock = lapis security tambahan untuk SESI
/// yang sudah login.
class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

/// Threshold pause time sebelum re-lock — kalau user balik dari background
/// dalam kurang dari ini, tidak perlu auth ulang (mis. swipe ke notif
/// center lalu balik segera). 60 detik = standar pattern banking app.
const _kAutoLockAfter = Duration(seconds: 60);

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  /// True = content blocked, lock screen visible.
  bool _locked = false;
  DateTime? _pausedAt;
  bool _authInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appSettingsStore.addListener(_onSettingsChanged);
    // Initial check setelah first frame — settings store hydrate dari disk
    // async, jadi initial value mungkin belum reflect saved settings.
    WidgetsBinding.instance.addPostFrameCallback((_) => _evaluateInitialLock());
  }

  @override
  void dispose() {
    appSettingsStore.removeListener(_onSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onSettingsChanged() {
    // Kalau user disable app lock dari Settings, unlock immediately.
    if (!appSettingsStore.appLockEnabled && _locked) {
      setState(() => _locked = false);
    }
  }

  Future<void> _evaluateInitialLock() async {
    if (!appSettingsStore.appLockEnabled) return;
    final supported = await biometricService.isDeviceSupported();
    if (!supported || !mounted) return;
    setState(() => _locked = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _maybeLockOnResume();
    }
  }

  void _maybeLockOnResume() {
    if (!appSettingsStore.appLockEnabled) return;
    if (_locked) return; // sudah locked, no-op
    final pausedAt = _pausedAt;
    if (pausedAt == null) return;
    final elapsed = DateTime.now().difference(pausedAt);
    if (elapsed >= _kAutoLockAfter) {
      setState(() => _locked = true);
    }
    _pausedAt = null;
  }

  Future<void> _attemptUnlock() async {
    if (_authInProgress) return;
    setState(() => _authInProgress = true);
    try {
      final ok = await biometricService.authenticate(
        reason: 'Buka kunci Natalo Petshop',
      );
      if (!mounted) return;
      if (ok) {
        AppHaptics.success();
        setState(() => _locked = false);
      } else {
        AppHaptics.warning();
      }
    } finally {
      if (mounted) setState(() => _authInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked)
          _LockScreen(
            authInProgress: _authInProgress,
            onUnlock: _attemptUnlock,
          ),
      ],
    );
  }
}

/// Full-screen overlay lock screen — natural blue gradient + paw logo +
/// "Buka kunci" button → biometric prompt.
class _LockScreen extends StatefulWidget {
  final bool authInProgress;
  final VoidCallback onUnlock;

  const _LockScreen({
    required this.authInProgress,
    required this.onUnlock,
  });

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  @override
  void initState() {
    super.initState();
    // Auto-trigger biometric prompt saat lock screen muncul — UX:
    // user buka app, biometric langsung pop up (Apple Wallet pattern).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onUnlock();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Material(
        // Solid + non-transparent — fully cover content di belakangnya
        // supaya tidak bocor lewat ScrollView/Hero animation.
        color: NataloColors.surface,
        child: SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFE6F2FF),
                  Color(0xFFF1F7FF),
                  Colors.white,
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: NataloColors.primary.withValues(alpha: 0.22),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.pets_rounded,
                    color: NataloColors.primary,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Natalo Petshop',
                  style: TextStyle(
                    color: NataloColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Buka kunci untuk lanjut',
                  style: TextStyle(
                    color: NataloColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(flex: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: widget.authInProgress ? null : widget.onUnlock,
                      icon: widget.authInProgress
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.fingerprint_rounded, size: 24),
                      label: Text(
                        widget.authInProgress
                            ? 'Memverifikasi...'
                            : 'Buka Kunci',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NataloColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
