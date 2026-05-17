import 'package:flutter/material.dart';

import '../models/feed_comment.dart';
import '../models/feed_post.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../utils/formatters.dart';
import '../utils/haptics.dart';

const _officialGold = Color(0xFFF4D47C);
const _sheetBg = Color(0xFF101114);

class FeedCommentSheet extends StatefulWidget {
  static const reelsHeightFactor = 0.60;

  final FeedPost post;
  final bool applyKeyboardInset;
  final ScrollController? sheetScrollController;
  final ValueChanged<int>? onClose;
  final ValueChanged<int>? onAddedCountChanged;
  final GestureDragUpdateCallback? onDragUpdate;
  final GestureDragEndCallback? onDragEnd;

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
  State<FeedCommentSheet> createState() => _FeedCommentSheetState();
}

class _FeedCommentSheetState extends State<FeedCommentSheet> {
  final _controller = TextEditingController();
  late final ScrollController _ownedScrollController;
  final List<FeedComment> _comments = [];
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _submitting = false;
  String? _error;
  int _addedCount = 0;

  @override
  void initState() {
    super.initState();
    _ownedScrollController = ScrollController();
    _loadInitial();
  }

  @override
  void dispose() {
    _controller.dispose();
    _ownedScrollController.dispose();
    super.dispose();
  }

  ScrollController get _effectiveScrollController =>
      widget.sheetScrollController ?? _ownedScrollController;

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await feedService.fetchComments(postId: widget.post.id);
      if (!mounted) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(page.items);
        _nextCursor = page.nextCursor;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _messageFor(error, 'Komentar belum bisa dimuat.');
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (_loadingMore || cursor == null || cursor.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await feedService.fetchComments(
        postId: widget.post.id,
        cursor: cursor,
      );
      if (!mounted) return;
      setState(() {
        _comments.addAll(page.items);
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _submit() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _submitting) return;
    if (content.length > 1000) {
      _showMessage('Komentar maksimal 1000 karakter.');
      return;
    }
    AppHaptics.tap();
    setState(() => _submitting = true);
    try {
      final comment = await feedService.addComment(
        postId: widget.post.id,
        content: content,
      );
      if (!mounted) return;
      _controller.clear();
      FocusScope.of(context).unfocus();
      setState(() {
        _comments.insert(0, comment);
        _addedCount += 1;
        _submitting = false;
      });
      widget.onAddedCountChanged?.call(_addedCount);
      final scrollController = _effectiveScrollController;
      if (scrollController.hasClients) {
        scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      if (error is ApiException && error.statusCode == 401) {
        _closeAndOpenLogin();
        return;
      }
      _showMessage(_messageFor(error, 'Komentar gagal dikirim.'));
    }
  }

  Future<void> _toggleLike(FeedComment comment) async {
    final index = _comments.indexWhere((item) => item.id == comment.id);
    if (index < 0) return;
    AppHaptics.tap();
    final wasLiked = comment.viewerLiked;
    final optimistic = comment.copyWith(
      viewerLiked: !wasLiked,
      likeCount: comment.likeCount + (wasLiked ? -1 : 1),
    );
    setState(() => _comments[index] = optimistic);
    try {
      final result = await feedService.toggleCommentLike(commentId: comment.id);
      if (!mounted) return;
      setState(() {
        _comments[index] = _comments[index].copyWith(
          viewerLiked: result.liked,
          likeCount: result.likeCount,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _comments[index] = comment);
      if (error is ApiException && error.statusCode == 401) {
        _closeAndOpenLogin();
        return;
      }
      _showMessage(_messageFor(error, 'Like komentar gagal.'));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _close() {
    FocusScope.of(context).unfocus();
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose(_addedCount);
    } else {
      Navigator.pop(context, _addedCount);
    }
  }

  void _closeAndOpenLogin() {
    final navigator = Navigator.of(context);
    _close();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigator.pushNamed('/member/login');
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final content = Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: widget.onDragUpdate,
          onVerticalDragEnd: widget.onDragEnd,
          child: Column(
            children: [
              const SizedBox(height: 9),
              Container(
                height: 4,
                width: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              _Header(
                count: widget.post.commentCount + _addedCount,
                onClose: _close,
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody()),
        _Composer(
          controller: _controller,
          submitting: _submitting,
          onSubmit: _submit,
        ),
      ],
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 28,
            offset: const Offset(0, -14),
          ),
        ],
      ),
      child: widget.applyKeyboardInset
          ? AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(bottom: keyboard),
              child: content,
            )
          : content,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        children: [
          _CreatorCaptionTile(post: widget.post),
          const SizedBox(height: 18),
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        children: [
          _CreatorCaptionTile(post: widget.post),
          const SizedBox(height: 18),
          _CommentMessageState(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Komentar belum terbuka',
            message: _error!,
            actionLabel: 'Coba lagi',
            onAction: _loadInitial,
          ),
        ],
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >
            notification.metrics.maxScrollExtent - 180) {
          _loadMore();
        }
        return false;
      },
      child: ListView.separated(
        controller: _effectiveScrollController,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        itemCount: 1 +
            _comments.length +
            (_comments.isEmpty ? 1 : 0) +
            (_nextCursor == null ? 0 : 1),
        separatorBuilder: (_, __) => const SizedBox(height: 13),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _CreatorCaptionTile(post: widget.post);
          }
          if (_comments.isEmpty && index == 1) {
            return const _CommentMessageState(
              icon: Icons.mode_comment_outlined,
              title: 'Belum ada komentar',
              message: 'Jadi yang pertama menyapa di video ini.',
            );
          }

          final commentIndex = index - 1;
          if (commentIndex >= _comments.length) {
            return Center(
              child: _loadingMore
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : TextButton(
                      onPressed: _loadMore,
                      child: const Text('Muat komentar lain'),
                    ),
            );
          }
          final comment = _comments[commentIndex];
          return _CommentTile(
            comment: comment,
            onLike: () => _toggleLike(comment),
          );
        },
      ),
    );
  }
}

class _CreatorCaptionTile extends StatefulWidget {
  final FeedPost post;

  const _CreatorCaptionTile({required this.post});

  @override
  State<_CreatorCaptionTile> createState() => _CreatorCaptionTileState();
}

class _CreatorCaptionTileState extends State<_CreatorCaptionTile> {
  bool _expanded = false;

  String get _caption {
    final description = widget.post.description?.trim() ?? '';
    if (description.isNotEmpty) return description;
    return widget.post.title.trim();
  }

  @override
  Widget build(BuildContext context) {
    final author = widget.post.author;
    final isOfficial = author.isAdmin;
    final caption = _caption;
    final canExpand = caption.length > 120;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Avatar(name: isOfficial ? 'Natalo' : author.name),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isOfficial ? 'Natalo Petshop' : author.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isOfficial ? _officialGold : Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (isOfficial) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.verified_rounded,
                        color: _officialGold,
                        size: 15,
                      ),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      'Creator',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.48),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (caption.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    caption,
                    maxLines: _expanded ? null : 3,
                    overflow: _expanded
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      height: 1.42,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (canExpand) ...[
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () {
                        AppHaptics.tap();
                        setState(() => _expanded = !_expanded);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          _expanded ? 'Lebih sedikit' : 'Selengkapnya',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.58),
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final int count;
  final VoidCallback onClose;

  const _Header({
    required this.count,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: SizedBox(
        height: 42,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Komentar',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatCount(count)} komentar',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.52),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ],
            ),
            Positioned(
              right: 0,
              child: IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                tooltip: 'Tutup',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final FeedComment comment;
  final VoidCallback onLike;

  const _CommentTile({
    required this.comment,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    final isOfficial = comment.isAdminOfficial || comment.author.isAdmin;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Avatar(name: isOfficial ? 'Natalo' : comment.author.name),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isOfficial ? 'Natalo Petshop' : comment.author.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isOfficial ? _officialGold : Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (isOfficial) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.verified_rounded,
                        color: _officialGold,
                        size: 15,
                      ),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      formatRelativeTime(comment.createdAt),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.48),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  comment.content,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    height: 1.42,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkResponse(
          onTap: onLike,
          radius: 24,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: Column(
              children: [
                Icon(
                  comment.viewerLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: comment.viewerLiked
                      ? const Color(0xFFEF4444)
                      : Colors.white70,
                  size: 22,
                ),
                if (comment.likeCount > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    _formatCount(comment.likeCount),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool submitting;
  final VoidCallback onSubmit;

  const _Composer({
    required this.controller,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;
    final bottomPadding = keyboardOpen ? 8.0 : 10.0 + bottomSafe;

    return Container(
      padding: EdgeInsets.fromLTRB(14, 9, 14, bottomPadding),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0D12),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              maxLength: 1000,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Tulis komentar...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontWeight: FontWeight.w700,
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: const BorderSide(
                    color: _officialGold,
                    width: 1.1,
                  ),
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSubmit(),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 44,
            width: 44,
            child: FilledButton(
              onPressed: submitting ? null : onSubmit,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: _officialGold,
                foregroundColor: const Color(0xFF241A04),
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.12),
                shape: const CircleBorder(),
              ),
              child: submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.arrow_upward_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentMessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _CommentMessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white54, size: 42),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;

  const _Avatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? 'N' : name.trim()[0].toUpperCase();
    return Container(
      height: 34,
      width: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF60A5FA), Color(0xFF1E5FBF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white, width: 1.2),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

String _messageFor(Object error, String fallback) {
  if (error is ApiException) return error.message;
  return fallback;
}

String _formatCount(int count) {
  if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}jt';
  if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}rb';
  return '$count';
}
