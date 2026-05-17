import 'package:flutter/material.dart';

import '../widgets/stub_screen.dart';

class MemberPostsScreen extends StatelessWidget {
  const MemberPostsScreen({super.key});

  @override
  Widget build(BuildContext context) => const StubScreen(
        title: 'Postingan Saya',
        icon: Icons.video_collection_outlined,
      );
}
