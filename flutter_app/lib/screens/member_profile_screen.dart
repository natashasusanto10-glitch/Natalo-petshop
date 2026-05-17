import 'package:flutter/material.dart';

import '../widgets/stub_screen.dart';

class MemberProfileScreen extends StatelessWidget {
  const MemberProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => const StubScreen(
        title: 'Profil',
        icon: Icons.person_outline_rounded,
      );
}
