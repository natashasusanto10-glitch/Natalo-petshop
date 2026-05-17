import 'package:flutter/material.dart';

import '../widgets/stub_screen.dart';

class NotificationPreferencesScreen extends StatelessWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) => const StubScreen(
        title: 'Preferensi Notifikasi',
        icon: Icons.tune_rounded,
      );
}
