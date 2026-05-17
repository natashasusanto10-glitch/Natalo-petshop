import 'package:flutter/material.dart';

import '../widgets/stub_screen.dart';

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StubScreen(
      title: 'Lupa Password',
      icon: Icons.lock_reset_rounded,
      subtitle: 'Form reset password via email belum diport.',
    );
  }
}
