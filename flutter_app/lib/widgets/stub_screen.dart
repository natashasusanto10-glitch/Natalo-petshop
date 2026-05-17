import 'package:flutter/material.dart';

import '../theme/natalo_colors.dart';
import 'app_ui.dart';

/// Helper scaffold untuk screen yang belum diport dari Capacitor. Tampilkan
/// title konsisten + pesan placeholder. Hapus widget ini saat semua screen
/// punya implementasi real.
class StubScreen extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;

  const StubScreen({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.construction_rounded,
    this.actions,
    this.bottomNavigationBar,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      bottomNavigationBar: bottomNavigationBar,
      body: AppEmptyState(
        icon: icon,
        title: title,
        subtitle: subtitle ?? 'Halaman ini sedang dibangun di versi Flutter.',
        action: Text(
          'Belum tersedia',
          style: TextStyle(
            color: NataloColors.textTertiary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
