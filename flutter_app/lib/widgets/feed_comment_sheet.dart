import 'package:flutter/material.dart';

import '../models/feed_post.dart';
import '../theme/natalo_colors.dart';

/// Bottom sheet untuk daftar comment di feed post. Stub minimal — real
/// implementation perlu fetch /api/feed/posts/{id}/comments, post reply,
/// like comment, threading 1-level, dll.
class FeedCommentSheet extends StatelessWidget {
  /// Height factor default saat sheet pertama buka — match Reels: ~56% viewport.
  static const double reelsHeightFactor = 0.56;

  final FeedPost post;
  final bool applyKeyboardInset;
  final ScrollController? sheetScrollController;
  final VoidCallback? onClose;
  final ValueChanged<int>? onAddedCountChanged;
  final ValueChanged<DragUpdateDetails>? onDragUpdate;
  final ValueChanged<DragEndDetails>? onDragEnd;

  const FeedCommentSheet({
    super.key,
    required this.post,
    this.applyKeyboardInset = true,
    this.sheetScrollController,
    this.onClose,
    this.onAddedCountChanged,
    this.onDragUpdate,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          GestureDetector(
            onVerticalDragUpdate: onDragUpdate,
            onVerticalDragEnd: onDragEnd,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: NataloColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Row(
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '${post.commentCount} komentar',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: sheetScrollController,
              padding: const EdgeInsets.all(16),
              children: const [
                Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Text(
                      'Komentar belum diport ke Flutter.',
                      style: TextStyle(color: NataloColors.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
