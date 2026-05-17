import 'package:flutter/material.dart';

import '../models/my_feed_post.dart';
import '../widgets/stub_screen.dart';

class MemberPostEditScreen extends StatelessWidget {
  final MyFeedPost post;

  const MemberPostEditScreen({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    return StubScreen(
      title: 'Edit Postingan',
      icon: Icons.edit_note_rounded,
      subtitle: 'Edit caption + tag produk untuk post ${post.slug}.',
    );
  }
}
