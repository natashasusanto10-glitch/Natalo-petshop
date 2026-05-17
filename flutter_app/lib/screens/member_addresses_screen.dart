import 'package:flutter/material.dart';

import '../widgets/stub_screen.dart';

class MemberAddressesScreen extends StatelessWidget {
  const MemberAddressesScreen({super.key});

  @override
  Widget build(BuildContext context) => const StubScreen(
        title: 'Alamat',
        icon: Icons.location_on_outlined,
      );
}
