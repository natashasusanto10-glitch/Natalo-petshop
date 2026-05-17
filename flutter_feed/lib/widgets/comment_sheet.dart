import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/feed_comment.dart';
import '../state/feed_provider.dart';

// Mirror of components/feed/FeedCommentSheet.tsx.
//
// Web sheet: height 42dvh (keyboard open) → 56dvh (closed), composer
// h-76px normal / h-118px reply mode. In Flutter we let the modal sheet
// auto-resize via DraggableScrollableSheet + MediaQuery keyboard inset.

class CommentSheet extends ConsumerStatefulWidget {
  final String postId;
  const CommentSheet({super.key, required this.postId});

  @override
  ConsumerState<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends ConsumerState<CommentSheet> {
  final _composerCtrl = TextEditingController();
  FeedComment? _replyTo;

  @override
  void dispose() {
    _composerCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _composerCtrl.text.trim();
    if (content.isEmpty) return;
    _composerCtrl.clear();
    final replyId = _replyTo?.id;
    setState(() => _replyTo = null);
    await ref
        .read(commentsProvider(widget.postId).notifier)
        .add(content, parentCommentId: replyId);
  }

  @override
  Widget build(BuildContext context) {
    final asyncComments = ref.watch(commentsProvider(widget.postId));
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final screenH = MediaQuery.sizeOf(context).height;

    // 42dvh when keyboard open, 56dvh closed — match web behavior.
    final sheetHeight = keyboardInset > 0 ? screenH * 0.42 : screenH * 0.56;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: sheetHeight + keyboardInset,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text('Komentar',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const Divider(height: 1),

          // Comment list
          Expanded(
            child: asyncComments.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator.adaptive()),
              error: (e, _) => Center(child: Text('Gagal memuat: $e')),
              data: (list) {
                if (list.isEmpty) {
                  return const Center(
                    child: Text('Jadilah yang pertama berkomentar',
                        style: TextStyle(color: Colors.grey)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _CommentTile(
                    comment: list[i],
                    onReplyTap: (c) => setState(() => _replyTo = c),
                    onLikeTap: (c) => ref
                        .read(commentsProvider(widget.postId).notifier)
                        .toggleLike(c.id),
                  ),
                );
              },
            ),
          ),

          // Composer
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + keyboardInset * 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_replyTo != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.grey.shade100,
                    width: double.infinity,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Membalas @${_replyTo!.authorName ?? "user"}',
                            style:
                                const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => setState(() => _replyTo = null),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _composerCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Tulis komentar...',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        maxLines: 3,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: _submit,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final FeedComment comment;
  final void Function(FeedComment) onReplyTap;
  final void Function(FeedComment) onLikeTap;

  const _CommentTile({
    required this.comment,
    required this.onReplyTap,
    required this.onLikeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundImage: comment.authorAvatarUrl != null
                    ? NetworkImage(comment.authorAvatarUrl!)
                    : null,
                child: comment.authorAvatarUrl == null
                    ? const Icon(Icons.person, size: 16)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          comment.authorName ?? 'user',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        if (comment.isAdminOfficial) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified,
                              size: 14, color: Colors.blue),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(comment.content,
                        style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => onReplyTap(comment),
                          child: const Text('Balas',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  GestureDetector(
                    onTap: () => onLikeTap(comment),
                    child: Icon(
                      comment.viewerLiked
                          ? Icons.favorite
                          : Icons.favorite_border,
                      size: 16,
                      color:
                          comment.viewerLiked ? Colors.red : Colors.grey,
                    ),
                  ),
                  if (comment.likeCount > 0)
                    Text(comment.likeCount.toString(),
                        style: const TextStyle(fontSize: 11)),
                ],
              ),
            ],
          ),
          // Inline replies (1-level threading)
          if (comment.replies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 38, top: 6),
              child: Column(
                children: [
                  for (final r in comment.replies)
                    _CommentTile(
                      comment: r,
                      onReplyTap: onReplyTap,
                      onLikeTap: onLikeTap,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
