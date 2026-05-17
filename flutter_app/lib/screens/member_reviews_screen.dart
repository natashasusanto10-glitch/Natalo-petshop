import 'package:flutter/material.dart';

import '../widgets/stub_screen.dart';

class MemberReviewsScreen extends StatelessWidget {
  const MemberReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) => const StubScreen(
        title: 'Ulasan Saya',
        icon: Icons.reviews_outlined,
      );
}
