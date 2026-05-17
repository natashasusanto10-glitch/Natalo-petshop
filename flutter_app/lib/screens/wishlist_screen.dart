import 'package:flutter/material.dart';

import '../widgets/stub_screen.dart';

class WishlistScreen extends StatelessWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context) => const StubScreen(
        title: 'Wishlist',
        icon: Icons.favorite_outline_rounded,
      );
}
