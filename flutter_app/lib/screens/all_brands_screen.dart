import 'package:flutter/material.dart';

import '../widgets/stub_screen.dart';

class AllBrandsScreen extends StatelessWidget {
  const AllBrandsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StubScreen(
      title: 'Semua Brand',
      icon: Icons.storefront_outlined,
      subtitle: 'List brand + filter belum diport.',
    );
  }
}
