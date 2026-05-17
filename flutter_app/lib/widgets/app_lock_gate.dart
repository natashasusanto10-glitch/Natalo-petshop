import 'package:flutter/material.dart';

/// Biometric app lock gate — saat enabled, blok UI sampai user sukses
/// authenticate via Face ID / Touch ID / fingerprint. Stub minimal:
/// pass-through tanpa lock (TODO: integrate local_auth flow).
class AppLockGate extends StatelessWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // TODO: kalau settings biometric-lock ON → tampilkan LockScreen.
    return child;
  }
}
