import 'package:flutter/material.dart';

import '../models/my_feed_post.dart';
import '../widgets/stub_screen.dart';

class MemberPostDetailScreen extends StatelessWidget {
  final MyFeedPost post;

  const MemberPostDetailScreen({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    return StubScreen(
      title: 'Detail Postingan',
      icon: Icons.play_circle_outline_rounded,
      subtitle: 'Post ${post.slug} • ${post.likeCount} like, ${post.viewCount} view.',
    );
  }
}
