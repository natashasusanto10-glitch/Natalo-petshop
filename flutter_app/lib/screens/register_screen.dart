import 'package:flutter/material.dart';

import '../widgets/stub_screen.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StubScreen(
      title: 'Daftar',
      icon: Icons.person_add_rounded,
      subtitle: 'Form pendaftaran akun baru belum diport.',
    );
  }
}
