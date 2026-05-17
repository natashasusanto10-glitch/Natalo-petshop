import 'package:flutter/material.dart';

import '../widgets/stub_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StubScreen(
      title: 'Login',
      icon: Icons.login_rounded,
      subtitle: 'Form login dengan email/HP + OTP belum diport.',
    );
  }
}
