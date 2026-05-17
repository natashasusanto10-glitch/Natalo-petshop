import 'package:flutter/material.dart';

import '../utils/read_only_mode.dart';

/// Saat read-only mode ON (default), tampilkan banner kecil di top untuk
/// kasih tahu user bahwa app dalam mode preview — mutation di-block.
/// User bisa toggle off di Settings.
class ReadOnlyWelcomeGate extends StatelessWidget {
  final Widget child;

  const ReadOnlyWelcomeGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: readOnlyMode,
      builder: (context, _) {
        if (!readOnlyMode.enabled) return child;
        return child;
        // TODO: tambah banner kecil di top (mis. via Overlay) yang
        // dismissable + info "Mode preview — pembelian tidak aktif".
      },
    );
  }
}
