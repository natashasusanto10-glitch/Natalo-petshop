import 'package:flutter/material.dart';

import '../models/feed_comment.dart';
import '../services/api_client.dart';
import '../services/feed_service.dart';
import '../theme/natalo_colors.dart';
import '../utils/haptics.dart';

/// Seam kirim balasan — default ke [feedService.postComment].
typedef CommentReplyPoster = Future<void> Function(
  String postId, {
  required String content,
  String? parentCommentId,
});

const List<String> _kQuickEmojis = [
  '❤️',
  '🙌',
  '🔥',
  '👏',
  '😢',
  '😍',
  '😮',
  '😂',
];

/// Buka composer balas ringan (overlay ala IG) di atas daftar notifikasi.
/// Daftar notif tetap terlihat di belakang barrier transparan; sheet
/// menempel keyboard (keyboard-safe: isScrollControlled + viewInsets).
Future<void> showNotificationReplyComposer(
  BuildContext context, {
  required FeedComment comment,
  required String feedPostId,
  CommentReplyPoster? poster,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => NotificationReplyComposer(
      comment: comment,
      feedPostId: feedPostId,
      poster: poster,
    ),
  );
}

class NotificationReplyComposer extends StatefulWidget {
  final FeedComment comment;
  final String feedPostId;
  final CommentReplyPoster? poster;

  const NotificationReplyComposer({
    super.key,
    required this.comment,
    required this.feedPostId,
    this.poster,
  });

  @override
  State<NotificationReplyComposer> createState() =>
      _NotificationReplyComposerState();
}

class _NotificationReplyComposerState extends State<NotificationReplyComposer> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  bool _sending = false;
  bool _canSend = false;

  bool get _hasUsername {
    final u = widget.comment.author.username;
    return u != null && u.trim().isNotEmpty;
  }

  String get _handle {
    final u = widget.comment.author.username;
    return _hasUsername ? u!.trim() : widget.comment.author.displayName;
  }

  @override
  void initState() {
    super.initState();
    final prefill = _hasUsername ? '@$_handle ' : '';
    _controller = TextEditingController(text: prefill);
    _canSend = _controller.text.trim().isNotEmpty;
    _controller.addListener(() {
      final can = _controller.text.trim().isNotEmpty;
      if (can != _canSend) setState(() => _canSend = can);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _insertEmoji(String emoji) {
    final text = _controller.text;
    final sel = _controller.selection;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final next = text.replaceRange(start, end, emoji);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  Future<void> _send() async {
    if (_sending || !_canSend) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    AppHaptics.tap();
    setState(() => _sending = true);
    final post = widget.poster ??
        (String postId, {required String content, String? parentCommentId}) =>
            feedService.postComment(
              postId,
              content: content,
              parentCommentId: parentCommentId,
            );
    try {
      await post(
        widget.feedPostId,
        content: text,
        parentCommentId: widget.comment.id,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Balasan terkirim')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 404) {
        // Post terhapus tepat saat kirim (celah race) — draf tak berguna.
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Postingan sudah dihapus.')),
        );
        return;
      }
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal mengirim balasan. Coba lagi.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal mengirim balasan. Coba lagi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 6),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _hasUsername ? 'Membalas @$_handle' : 'Membalas $_handle',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: _kQuickEmojis.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 4),
                  itemBuilder: (_, i) => InkWell(
                    onTap: () => _insertEmoji(_kQuickEmojis[i]),
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        _kQuickEmojis[i],
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: 'Tulis balasan…',
                          filled: true,
                          fillColor: cs.surfaceContainerHighest,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SendButton(
                      key: const ValueKey('composer-send'),
                      enabled: _canSend && !_sending,
                      sending: _sending,
                      onTap: _send,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final bool sending;
  final VoidCallback onTap;
  const _SendButton({
    super.key,
    required this.enabled,
    required this.sending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 40,
        width: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled
              ? NataloColors.primary
              : cs.onSurfaceVariant.withValues(alpha: 0.25),
        ),
        child: sending
            ? const Padding(
                padding: EdgeInsets.all(11),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
      ),
    );
  }
}
