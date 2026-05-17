import 'package:flutter/material.dart';

import '../widgets/stub_screen.dart';

class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StubScreen(
      title: 'Bantuan',
      icon: Icons.help_outline_rounded,
      subtitle: 'FAQ + kontak customer service belum diport.',
    );
  }
}
